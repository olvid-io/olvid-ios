/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import CoreData
import os.log
import ObvServerInterface
import ObvMetaManager
import ObvTypes
import ObvCrypto
import OlvidUtils

final class ServerQueryCoordinator: NSObject {

    // MARK: - Instance variables

    fileprivate let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "ServerQueryCoordinator"

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { ServerQueryCoordinator.makeError(message: message) }

    weak var delegateManager: ObvNetworkFetchDelegateManager?

    private var localQueue = DispatchQueue(label: "ServerQueryCoordinatorQueue")
    private let internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .default
        queue.name = "ServerQueryCoordinatorOperationQueue"
        return queue
    }()

    private lazy var session: URLSession! = {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.useOlvidSettings(sharedContainerIdentifier: delegateManager?.sharedContainerIdentifier)
        return URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }()

    private var _currentTasks = [UIBackgroundTaskIdentifier: (objectId: NSManagedObjectID, dataReceived: Data, flowId: FlowIdentifier)]()
    private var currentTasksQueue = DispatchQueue(label: "ServerQueryCoordinatorQueueForCurrentTasks")

    let prng: PRNGService
    let downloadedUserData: URL
    private var notificationCenterTokens = [NSObjectProtocol]()

    init(prng: PRNGService, downloadedUserData: URL) {
        self.prng = prng
        self.downloadedUserData = downloadedUserData
    }

    func finalizeInitialization() {
        notificationCenterTokens.append(ObvIdentityNotificationNew.observeOwnedIdentityWasReactivated(within: self.delegateManager!.notificationDelegate!, queue: internalQueue) { [weak self] (ownedCryptoIdentity, flowId) in
            self?.postAllPendingServerQuery(for: ownedCryptoIdentity, flowId: flowId)
        })
    }

}


// MARK: - Synchronized access to the current download tasks

extension ServerQueryCoordinator {

    private func currentTaskExistsForServerQuery(with objectId: NSManagedObjectID) -> Bool {
        var exist = true
        currentTasksQueue.sync {
            exist = _currentTasks.values.contains(where: { $0.objectId == objectId })
        }
        return exist
    }

    private func removeInfoFor(_ task: URLSessionTask) -> (objectId: NSManagedObjectID, dataReceived: Data, flowId: FlowIdentifier)? {
        var info: (NSManagedObjectID, Data, FlowIdentifier)? = nil
        currentTasksQueue.sync {
            info = _currentTasks.removeValue(forKey: UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier))
        }
        return info
    }

    private func getInfoFor(_ task: URLSessionTask) -> (objectId: NSManagedObjectID, dataReceived: Data, flowId: FlowIdentifier)? {
        var info: (NSManagedObjectID, Data, FlowIdentifier)? = nil
        currentTasksQueue.sync {
            info = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)]
        }
        return info
    }

    private func insert(_ task: URLSessionTask, forObjectId objectId: NSManagedObjectID, flowId: FlowIdentifier) {
        currentTasksQueue.sync {
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (objectId, Data(), flowId)
        }
    }

    private func accumulate(_ data: Data, forTask task: URLSessionTask) {
        currentTasksQueue.sync {
            guard let (objectID, currentData, flowId) = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] else { return }
            var newData = currentData
            newData.append(data)
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (objectID, newData, flowId)
        }
    }

    func postAllPendingServerQuery(for ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            return
        }
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                let serverQueries = try PendingServerQuery.getAllServerQuery(for: ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext)
                for serverQuery in serverQueries {
                    postServerQuery(withObjectId: serverQuery.objectID, flowId: flowId)
                }
            } catch(let error) {
                os_log("Could fetch server queries for the given owned identity.", log: log, type: .error, error.localizedDescription)
                return

            }

        }
    }

}


// MARK: - ServerQueryDelegate

extension ServerQueryCoordinator: ServerQueryDelegate {

    private enum SyncQueueOutput {
        case previousTaskExists
        case couldNotFindServerQueryInDatabase
        case newTaskToRun(task: URLSessionTask)
        case failedToCreateTask(methodName: String, error: Error)
        case serverSessionRequired(for: ObvCryptoIdentity, flowId: FlowIdentifier)
    }

    func postServerQuery(withObjectId objectId: NSManagedObjectID, flowId: FlowIdentifier) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            return
        }

        var syncQueueOutput: SyncQueueOutput? // The state after the localQueue.sync is executed

        localQueue.sync {

            guard !currentTaskExistsForServerQuery(with: objectId) else {
                syncQueueOutput = .previousTaskExists
                return
            }

            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in

                let serverQuery: PendingServerQuery
                do {
                    serverQuery = try PendingServerQuery.get(objectId: objectId,
                                                             delegateManager: delegateManager,
                                                             within: obvContext)
                } catch {
                    syncQueueOutput = .couldNotFindServerQueryInDatabase
                    return
                }
                let ownedIdentity = serverQuery.ownedIdentity

                // If we reach this point, we do need to send the server query to the server

                switch serverQuery.queryType {
                case .deviceDiscovery(of: let contactIdentity):

                    os_log("Creating a ObvServerDeviceDiscoveryMethod of the contact identity %@", log: log, type: .debug, contactIdentity.debugDescription)

                    let method = ObvServerDeviceDiscoveryMethod(ownedIdentity: serverQuery.ownedIdentity, toIdentity: contactIdentity, flowId: flowId)
                    method.identityDelegate = delegateManager.identityDelegate
                    let task: URLSessionDataTask
                    do {
                        task = try method.dataTask(within: self.session)
                    } catch let error {
                        syncQueueOutput = .failedToCreateTask(methodName: "ObvServerDeviceDiscoveryMethod", error: error)
                        return
                    }

                    insert(task, forObjectId: objectId, flowId: flowId)

                    syncQueueOutput = .newTaskToRun(task: task)
                    return

                case .putUserData(label: let label, dataURL: let dataURL, dataKey: let dataKey):
                    os_log("Creating a ObvServerPutUserDataMethod", log: log, type: .debug)

                    let authEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption()

                    guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: ownedIdentity) else {
                        syncQueueOutput = .serverSessionRequired(for: ownedIdentity, flowId: flowId)
                        return
                    }
                    guard let token = serverSession.token else {
                        syncQueueOutput = .serverSessionRequired(for: ownedIdentity, flowId: flowId)
                        return
                    }

                    // Encrypt the photo

                    guard let data = try? Data(contentsOf: dataURL) else {
                        os_log("Could not read data", log: log, type: .error)
                        syncQueueOutput = .failedToCreateTask(methodName: "ObvServerPutUserDataMethod", error: makeError(message: "Could not get data content"))
                        return
                    }
                    guard let encryptedData = try? authEnc.encrypt(data, with: dataKey, and: prng) else {
                        os_log("Could not encrypt photo", log: log, type: .error)
                        syncQueueOutput = .failedToCreateTask(methodName: "ObvServerPutUserDataMethod", error: makeError(message: "Could not encrypt photo"))
                        return
                    }


                    let method = ObvServerPutUserDataMethod(ownedIdentity: ownedIdentity,
                                                            token: token,
                                                            serverLabel: label,
                                                            data: encryptedData,
                                                            flowId: flowId)
                    method.identityDelegate = delegateManager.identityDelegate
                    let task: URLSessionDataTask
                    do {
                        task = try method.dataTask(within: self.session)
                    } catch let error {
                        syncQueueOutput = .failedToCreateTask(methodName: "ObvServerPutUserDataMethod", error: error)
                        return
                    }

                    insert(task, forObjectId: objectId, flowId: flowId)

                    syncQueueOutput = .newTaskToRun(task: task)
                    return

                case .getUserData(of: let contactIdentity, label: let label):

                    os_log("Creating a ObvServerGetUserDataMethod of the contact identity %@", log: log, type: .debug, contactIdentity.debugDescription)

                    let method = ObvServerGetUserDataMethod(ownedIdentity: serverQuery.ownedIdentity, toIdentity: contactIdentity, serverLabel: label, flowId: flowId)
                    method.identityDelegate = delegateManager.identityDelegate

                    let task: URLSessionDataTask
                    do {
                        task = try method.dataTask(within: self.session)
                    } catch let error {
                        syncQueueOutput = .failedToCreateTask(methodName: "ObvServerGetUserDataMethod", error: error)
                        return
                    }

                    insert(task, forObjectId: objectId, flowId: flowId)

                    syncQueueOutput = .newTaskToRun(task: task)
                    return

                case .checkKeycloakRevocation(keycloakServerUrl: let keycloakServerUrl, signedContactDetails: let signedContactDetails):

                    guard let (serverURL, path) = ObvServerCheckKeycloakRevocationMethod.splitServerAndPath(from: keycloakServerUrl) else {
                        os_log("Could not compute url and path", log: log, type: .error)
                        syncQueueOutput = .failedToCreateTask(methodName: "ObvServerCheckKeycloakRevocationMethod", error: makeError(message: "Could not compute url and path"))
                        return
                    }

                    os_log("Creating a ObvServerCheckKeycloakRevocationMethod for the server %@", log: log, type: .debug, keycloakServerUrl.absoluteString)

                    let method = ObvServerCheckKeycloakRevocationMethod(ownedIdentity: ownedIdentity, serverURL: serverURL, path: path, signedContactDetails: signedContactDetails, flowId: flowId)
                    method.identityDelegate = delegateManager.identityDelegate

                    let task: URLSessionDataTask
                    do {
                        task = try method.dataTask(within: self.session)
                    } catch let error {
                        syncQueueOutput = .failedToCreateTask(methodName: "ObvServerCheckKeycloakRevocationMethod", error: error)
                        return
                    }

                    insert(task, forObjectId: objectId, flowId: flowId)

                    syncQueueOutput = .newTaskToRun(task: task)
                    return
                }

            }

        } // End of localQueue.sync

        guard syncQueueOutput != nil else {
            os_log("syncQueueOutput is nil", log: log, type: .fault)
            assertionFailure()
            return
        }

        switch syncQueueOutput! {

        case .previousTaskExists:
            os_log("A running task already exists for pending server query %{public}@", log: log, type: .debug, objectId.debugDescription)
            return

        case .couldNotFindServerQueryInDatabase:
            os_log("Could not find pending server query %{public}@ in database", log: log, type: .error, objectId.debugDescription)
            return

        case .failedToCreateTask(methodName: let methodName, error: let error):
            os_log("Could not create task for %@: %{public}@", log: log, type: .error, methodName, error.localizedDescription)
            return

        case .serverSessionRequired(for: let ownedIdentity, flowId: let flowId):
            // REMARK we will be called again by NetworkFetchFlowCoordinator#newToken
            try? delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: ownedIdentity, flowId: flowId)
        case .newTaskToRun(task: let task):
            os_log("New task to run for the server query %{public}@", log: log, type: .debug, objectId.debugDescription)
            task.resume()
        }
    }
}


// MARK: - URLSessionDataDelegate

extension ServerQueryCoordinator: URLSessionDataDelegate {

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        accumulate(data, forTask: dataTask)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            return
        }

        guard let (objectId, responseData, flowId) = getInfoFor(task) else { return }

        guard error == nil else {
            os_log("The task failed for server query %{public}@: %@", log: log, type: .error, objectId.debugDescription, error!.localizedDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
            return
        }

        // If we reach this point, the data task did complete without error

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in

            let serverQuery: PendingServerQuery
            do {
                serverQuery = try PendingServerQuery.get(objectId: objectId,
                                                         delegateManager: delegateManager,
                                                         within: obvContext)
            } catch {
                os_log("Could not find server query in database", log: log, type: .fault)
                _ = removeInfoFor(task)
                return
            }

            switch serverQuery.queryType {

            case .deviceDiscovery(of: let contactIdentity):

                guard let (status, deviceUids) = ObvServerDeviceDiscoveryMethod.parseObvServerResponse(responseData: responseData, using: log) else {
                    os_log("Could not parse the server response for the ObvServerDeviceDiscoveryMethod task of pending server query %{public}@", log: log, type: .fault, objectId.debugDescription)
                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    return
                }

                switch status {

                case .ok:
                    os_log("The ObvServerDeviceDiscoveryMethod returned %d device uids", log: log, type: .debug, deviceUids!.count)

                    let serverResponseType = ServerResponse.ResponseType.deviceDiscovery(of: contactIdentity, deviceUids: deviceUids!)
                    serverQuery.responseType = serverResponseType

                    do {
                        try obvContext.save(logOnFailure: log)
                    } catch {
                        os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                        _ = removeInfoFor(task)
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                        return
                    }

                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: objectId, flowId: flowId)
                    return

                case .generalError:
                    os_log("Server reported general error during the ObvServerDeviceDiscoveryMethod task for pending server query %@", log: log, type: .fault, objectId.debugDescription)
                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    return
                }

            case .putUserData:

                guard let status = ObvServerPutUserDataMethod.parseObvServerResponse(responseData: responseData, using: log) else {
                    os_log("Could not parse the server response for the ObvServerPutUserDataMethod task of pending server query %{public}@", log: log, type: .fault, objectId.debugDescription)
                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    return
                }

                switch status {
                case .ok:
                    os_log("The ObvServerPutUserDataMethod returned .ok", log: log, type: .debug)

                    let serverResponseType = ServerResponse.ResponseType.putUserData
                    serverQuery.responseType = serverResponseType

                    do {
                        try obvContext.save(logOnFailure: log)
                    } catch {
                        os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                        _ = removeInfoFor(task)
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                        return
                    }

                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: objectId, flowId: flowId)
                    return

                case .generalError:
                    _ = removeInfoFor(task)
                    os_log("Server reported general error during the ObvServerPutUserDataMethod task for pending server query %@", log: log, type: .fault, objectId.debugDescription)

                }

            case .getUserData(of: let contactIdentity, label: let label):

                guard let (status, userDataPath) = ObvServerGetUserDataMethod.parseObvServerResponse(responseData: responseData, using: log, downloadedUserData: downloadedUserData, serverLabel: label) else {
                    os_log("Could not parse the server response for the ObvServerGetUserDataMethod task of pending server query %{public}@", log: log, type: .fault, objectId.debugDescription)
                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    return
                }

                switch status {
                case .ok:
                    os_log("The ObvServerGetUserDataMethod returned .ok", log: log, type: .debug)
                    guard let userDataPath = userDataPath else { assertionFailure(); return }

                    let serverResponseType = ServerResponse.ResponseType.getUserData(of: contactIdentity, userDataPath: userDataPath)
                    serverQuery.responseType = serverResponseType

                    do {
                        try obvContext.save(logOnFailure: log)
                    } catch {
                        os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                        _ = removeInfoFor(task)
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                        return
                    }

                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: objectId, flowId: flowId)
                    return

                case .generalError:
                    _ = removeInfoFor(task)
                    os_log("Server reported general error during the ObvServerGetUserDataMethod task for pending server query %@", log: log, type: .fault, objectId.debugDescription)
                case .deletedFromServer:
                    _ = removeInfoFor(task)
                    os_log("Server reported deleted form server data during the ObvServerGetUserDataMethod task for pending server query %@", log: log, type: .fault, objectId.debugDescription)

                }

            case .checkKeycloakRevocation:

                guard let (status, verificationSuccessful) = ObvServerCheckKeycloakRevocationMethod.parseObvServerResponse(responseData: responseData, using: log) else {
                    os_log("Could not parse the server response for the ObvServerCheckKeycloakRevocationMethod task of pending server query %{public}@", log: log, type: .fault, objectId.debugDescription)
                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    return
                }

                switch status {
                case .ok:
                    os_log("The ObvServerCheckKeycloakRevocationMethod returned .ok", log: log, type: .debug)
                    guard let verificationSuccessful = verificationSuccessful else { assertionFailure(); return }

                    let serverResponseType = ServerResponse.ResponseType.checkKeycloakRevocation(verificationSuccessful: verificationSuccessful)
                    serverQuery.responseType = serverResponseType

                    do {
                        try obvContext.save(logOnFailure: log)
                    } catch {
                        os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                        _ = removeInfoFor(task)
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                        return
                    }

                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: objectId, flowId: flowId)
                    return

                case .generalError:
                    _ = removeInfoFor(task)
                    os_log("Server reported general error during the ObvServerCheckKeycloakRevocationMethod task for pending server query %@", log: log, type: .fault, objectId.debugDescription)
                }


            }

        }

    }
}
