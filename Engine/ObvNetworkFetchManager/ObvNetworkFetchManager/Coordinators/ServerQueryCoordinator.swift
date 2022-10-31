/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

    private let queueForCallingDelegate = DispatchQueue(label: "ServerQueryCoordinator queue for calling delegate methods")

    let prng: PRNGService
    let downloadedUserData: URL
    private var notificationCenterTokens = [NSObjectProtocol]()

    init(prng: PRNGService, downloadedUserData: URL) {
        self.prng = prng
        self.downloadedUserData = downloadedUserData
        super.init()
    }

    func finalizeInitialization() {
        notificationCenterTokens.append(contentsOf: [
            ObvIdentityNotificationNew.observeOwnedIdentityWasReactivated(within: self.delegateManager!.notificationDelegate!, queue: internalQueue) { [weak self] (ownedCryptoIdentity, flowId) in
                self?.postAllPendingServerQuery(for: ownedCryptoIdentity, flowId: flowId)
            },
        ])
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

    // Used during bootstrap
    func postAllPendingServerQuery(flowId: FlowIdentifier) {
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
                let serverQueries = try PendingServerQuery.getAllServerQuery(delegateManager: delegateManager, within: obvContext)
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
                    
                case .createGroupBlob(groupIdentifier: let groupIdentifier, serverAuthenticationPublicKey: let serverAuthenticationPublicKey, encryptedBlob: let encryptedBlob):
                    
                    guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: ownedIdentity) else {
                        syncQueueOutput = .serverSessionRequired(for: ownedIdentity, flowId: flowId)
                        return
                    }
                    guard let token = serverSession.token else {
                        syncQueueOutput = .serverSessionRequired(for: ownedIdentity, flowId: flowId)
                        return
                    }

                    let method = ObvServerCreateGroupBlobServerMethod(ownedIdentity: ownedIdentity,
                                                                      token: token,
                                                                      groupIdentifier: groupIdentifier,
                                                                      newGroupAdminServerAuthenticationPublicKey: serverAuthenticationPublicKey,
                                                                      encryptedBlob: encryptedBlob,
                                                                      flowId: flowId)
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

                case .getGroupBlob(groupIdentifier: let groupIdentifier):
                    
                    let method = ObvServerGetGroupBlobServerMethod(ownedIdentity: ownedIdentity,
                                                                   groupIdentifier: groupIdentifier,
                                                                   flowId: flowId)
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
                    
                case .deleteGroupBlob(groupIdentifier: let groupIdentifier, signature: let signature):
                    
                    let method = ObvServerDeleteGroupBlobServerMethod(ownedIdentity: ownedIdentity,
                                                                      groupIdentifier: groupIdentifier,
                                                                      signature: signature,
                                                                      flowId: flowId)
                    method.identityDelegate = delegateManager.identityDelegate

                    let task: URLSessionDataTask
                    do {
                        task = try method.dataTask(within: self.session)
                    } catch let error {
                        syncQueueOutput = .failedToCreateTask(methodName: "ObvServerDeleteGroupBlobServerMethod", error: error)
                        return
                    }

                    insert(task, forObjectId: objectId, flowId: flowId)

                    syncQueueOutput = .newTaskToRun(task: task)
                    return
                    
                case .putGroupLog(groupIdentifier: let groupIdentifier, querySignature: let querySignature):
                    
                    let method = ObvServerPutGroupLogServerMethod(ownedIdentity: ownedIdentity,
                                                                  groupIdentifier: groupIdentifier,
                                                                  signature: querySignature,
                                                                  flowId: flowId)
                    method.identityDelegate = delegateManager.identityDelegate

                    let task: URLSessionDataTask
                    do {
                        task = try method.dataTask(within: self.session)
                    } catch let error {
                        syncQueueOutput = .failedToCreateTask(methodName: "ObvServerPutGroupLogServerMethod", error: error)
                        return
                    }

                    insert(task, forObjectId: objectId, flowId: flowId)

                    syncQueueOutput = .newTaskToRun(task: task)
                    return
                    
                case .requestGroupBlobLock(groupIdentifier: let groupIdentifier, lockNonce: let lockNonce, signature: let signature):
                    
                    let method = ObvServerGroupBlobLockServerMethod(ownedIdentity: ownedIdentity,
                                                                    groupIdentifier: groupIdentifier,
                                                                    lockNonce: lockNonce,
                                                                    signature: signature,
                                                                    flowId: flowId)
                    method.identityDelegate = delegateManager.identityDelegate

                    let task: URLSessionDataTask
                    do {
                        task = try method.dataTask(within: self.session)
                    } catch let error {
                        syncQueueOutput = .failedToCreateTask(methodName: "ObvServerGroupBlobLockServerMethod", error: error)
                        return
                    }

                    insert(task, forObjectId: objectId, flowId: flowId)

                    syncQueueOutput = .newTaskToRun(task: task)
                    return
                    
                case .updateGroupBlob(groupIdentifier: let groupIdentifier, encodedServerAdminPublicKey: let encodedServerAdminPublicKey, encryptedBlob: let encryptedBlob, lockNonce: let lockNonce, signature: let signature):
                    
                    let method = ObvServerGroupBlobUpdateServerMethod(ownedIdentity: ownedIdentity,
                                                                      groupIdentifier: groupIdentifier,
                                                                      lockNonce: lockNonce,
                                                                      signature: signature,
                                                                      encodedServerAdminPublicKey: encodedServerAdminPublicKey,
                                                                      encryptedBlob: encryptedBlob,
                                                                      flowId: flowId)
                    method.identityDelegate = delegateManager.identityDelegate

                    let task: URLSessionDataTask
                    do {
                        task = try method.dataTask(within: self.session)
                    } catch let error {
                        syncQueueOutput = .failedToCreateTask(methodName: "ObvServerGroupBlobUpdateServerMethod", error: error)
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
            queueForCallingDelegate.async {
                try? delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: ownedIdentity, flowId: flowId)
            }
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
            queueForCallingDelegate.async {
                delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
            }
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
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    }
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
                        queueForCallingDelegate.async {
                            delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                        }
                        return
                    }

                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return

                case .generalError:
                    os_log("Server reported general error during the ObvServerDeviceDiscoveryMethod task for pending server query %@", log: log, type: .fault, objectId.debugDescription)
                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return
                }

            case .putUserData:

                let result = ObvServerPutUserDataMethod.parseObvServerResponse(responseData: responseData, using: log)
                
                switch result {
                case .success(let status):
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
                            queueForCallingDelegate.async {
                                delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                            }
                            return
                        }

                        _ = removeInfoFor(task)
                        queueForCallingDelegate.async {
                            delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: objectId, flowId: flowId)
                        }
                        return

                    case .invalidSession:
                        processInvalidSessionForTask(task, ownedIdentity: serverQuery.ownedIdentity, flowId: flowId)
                        return

                    case .generalError:
                        _ = removeInfoFor(task)
                        os_log("Server reported general error during the ObvServerPutUserDataMethod task for pending server query %{public}@", log: log, type: .fault, objectId.debugDescription)

                    }
                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerPutUserDataMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, objectId.debugDescription, error.localizedDescription)
                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return
                }
                
            case .getUserData(of: _, label: let label):

                guard let (status, userDataPath) = ObvServerGetUserDataMethod.parseObvServerResponse(responseData: responseData, using: log, downloadedUserData: downloadedUserData, serverLabel: label) else {
                    os_log("Could not parse the server response for the ObvServerGetUserDataMethod task of pending server query %{public}@", log: log, type: .fault, objectId.debugDescription)
                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return
                }

                switch status {
                    
                case .generalError:
                    _ = removeInfoFor(task)
                    os_log("Server reported general error during the ObvServerGetUserDataMethod task for pending server query %@", log: log, type: .fault, objectId.debugDescription)
                    return
                    
                case .ok:
                    os_log("The ObvServerGetUserDataMethod returned .ok", log: log, type: .debug)
                    guard let userDataPath = userDataPath else { assertionFailure(); return }

                    let serverResponseType = ServerResponse.ResponseType.getUserData(result: .downloaded(userDataPath: userDataPath))
                    serverQuery.responseType = serverResponseType
                    // Continues after the end of the status block

                case .deletedFromServer:
                    
                    os_log("Server reported deleted form server data during the ObvServerGetUserDataMethod task for pending server query %@", log: log, type: .info, objectId.debugDescription)
                    
                    let serverResponseType = ServerResponse.ResponseType.getUserData(result: .deletedFromServer)
                    serverQuery.responseType = serverResponseType
                    // Continues after the end of the status block

                }
                
                // Common to the ok and deletedFromServer cases
                
                do {
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return
                }

                _ = removeInfoFor(task)
                queueForCallingDelegate.async {
                    delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: objectId, flowId: flowId)
                }
                return

            case .checkKeycloakRevocation:

                guard let (status, verificationSuccessful) = ObvServerCheckKeycloakRevocationMethod.parseObvServerResponse(responseData: responseData, using: log) else {
                    os_log("Could not parse the server response for the ObvServerCheckKeycloakRevocationMethod task of pending server query %{public}@", log: log, type: .fault, objectId.debugDescription)
                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    }
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
                        queueForCallingDelegate.async {
                            delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                        }
                        return
                    }

                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return

                case .generalError:
                    _ = removeInfoFor(task)
                    os_log("Server reported general error during the ObvServerCheckKeycloakRevocationMethod task for pending server query %@", log: log, type: .fault, objectId.debugDescription)
                }

            case .createGroupBlob:
                
                let result = ObvServerCreateGroupBlobServerMethod.parseObvServerResponse(responseData: responseData, using: log)

                switch result {
                case .success(let status):

                    os_log("The ObvServerCreateGroupBlobServerMethod returned status is %{public}@", log: log, type: .debug, String(reflecting: status))

                    switch status {
                        
                    case .invalidSession, .generalError:
                        processInvalidSessionForTask(task, ownedIdentity: serverQuery.ownedIdentity, flowId: flowId)
                        return

                    case .ok:
                        
                        let serverResponseType = ServerResponse.ResponseType.createGroupBlob(uploadResult: .success)
                        serverQuery.responseType = serverResponseType
                        // Continues after the end of the status block

                    case .groupUIDAlreadyUsed:
                        
                        let serverResponseType = ServerResponse.ResponseType.createGroupBlob(uploadResult: .permanentFailure)
                        serverQuery.responseType = serverResponseType
                        // Continues after the end of the status block

                    }
                    
                    // Common to .ok, .groupUIDAlreadyUsed
                    
                    do {
                        try obvContext.save(logOnFailure: log)
                    } catch {
                        os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                        _ = removeInfoFor(task)
                        queueForCallingDelegate.async {
                            delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                        }
                        return
                    }

                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return
                    
                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerCreateGroupBlobServerMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, objectId.debugDescription, error.localizedDescription)
                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return
                }

            case .getGroupBlob:
                
                let result = ObvServerGetGroupBlobServerMethod.parseObvServerResponse(responseData: responseData, using: log)

                switch result {
                case .success(let status):

                    os_log("The ObvServerGetGroupBlobServerMethod returned status is %{public}@", log: log, type: .debug, String(reflecting: status))

                    switch status {
                        
                    case .groupIsLocked:
                        _ = removeInfoFor(task)
                        queueForCallingDelegate.async {
                            delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                        }
                        return

                    case .ok(let encryptedBlob, let logItems, let adminPublicKey):
                        
                        let serverResponseType = ServerResponse.ResponseType.getGroupBlob(result: .blobDownloaded(encryptedServerBlob: encryptedBlob, logEntries: logItems, groupAdminPublicKey: adminPublicKey))
                        serverQuery.responseType = serverResponseType
                        // Continues after the end of the status block

                    case .deletedFromServer:

                        let serverResponseType = ServerResponse.ResponseType.getGroupBlob(result: .blobWasDeletedFromServer)
                        serverQuery.responseType = serverResponseType
                        // Continues after the end of the status block

                    case .generalError:
                        
                        let serverResponseType = ServerResponse.ResponseType.getGroupBlob(result: .blobCouldNotBeDownloaded)
                        serverQuery.responseType = serverResponseType
                        // Continues after the end of the status block

                    }
                    
                    // Common to .ok, .deletedFromServer, .generalError
                    
                    do {
                        try obvContext.save(logOnFailure: log)
                    } catch {
                        os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                        _ = removeInfoFor(task)
                        queueForCallingDelegate.async {
                            delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                        }
                        return
                    }

                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return

                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerGetGroupBlobServerMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, objectId.debugDescription, error.localizedDescription)
                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return
                }
                
            case .deleteGroupBlob:
                
                let result = ObvServerDeleteGroupBlobServerMethod.parseObvServerResponse(responseData: responseData, using: log)

                switch result {
                case .success(let status):
                    
                    os_log("The ObvServerDeleteGroupBlobServerMethod returned status is %{public}@", log: log, type: .debug, String(reflecting: status))

                    switch status {
                        
                    case .groupIsLocked:
                        _ = removeInfoFor(task)
                        queueForCallingDelegate.async {
                            delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                        }
                        return

                    case .ok:
                        
                        let serverResponseType = ServerResponse.ResponseType.deleteGroupBlob(groupDeletionWasSuccessful: true)
                        serverQuery.responseType = serverResponseType
                        // Continues after the end of the status block

                    case .invalidSignature, .generalError:
                        
                        let serverResponseType = ServerResponse.ResponseType.deleteGroupBlob(groupDeletionWasSuccessful: false)
                        serverQuery.responseType = serverResponseType
                        // Continues after the end of the status block

                    }

                    // Common to .ok, .invalidSignature, .generalError

                    do {
                        try obvContext.save(logOnFailure: log)
                    } catch {
                        os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                        _ = removeInfoFor(task)
                        queueForCallingDelegate.async {
                            delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                        }
                        return
                    }

                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return
                    
                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerDeleteGroupBlobServerMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, objectId.debugDescription, error.localizedDescription)
                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return
                }

            case .putGroupLog:
                
                let result = ObvServerPutGroupLogServerMethod.parseObvServerResponse(responseData: responseData, using: log)

                switch result {
                case .success(let status):
                    
                    os_log("The ObvServerPutGroupLogServerMethod returned status is %{public}@", log: log, type: .debug, String(reflecting: status))

                    switch status {
                        
                    case .groupIsLocked, .generalError:
                        _ = removeInfoFor(task)
                        queueForCallingDelegate.async {
                            delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                        }
                        return

                    case .ok, .deletedFromServer:
                        
                        let serverResponseType = ServerResponse.ResponseType.putGroupLog
                        serverQuery.responseType = serverResponseType

                        do {
                            try obvContext.save(logOnFailure: log)
                        } catch {
                            os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                            _ = removeInfoFor(task)
                            queueForCallingDelegate.async {
                                delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                            }
                            return
                        }

                        _ = removeInfoFor(task)
                        queueForCallingDelegate.async {
                            delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: objectId, flowId: flowId)
                        }
                        return
                        
                    }
                    
                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerPutGroupLogServerMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, objectId.debugDescription, error.localizedDescription)
                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return
                }

            case .requestGroupBlobLock:
                
                let result = ObvServerGroupBlobLockServerMethod.parseObvServerResponse(responseData: responseData, using: log)

                switch result {
                case .success(let status):
                    
                    os_log("The ObvServerGroupBlobLockServerMethod returned status is %{public}@", log: log, type: .debug, String(reflecting: status))

                    switch status {
                        
                    case .groupIsLocked, .generalError:
                        
                        _ = removeInfoFor(task)
                        queueForCallingDelegate.async {
                            delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                        }
                        return

                    case .ok(let encryptedBlob, let logItems, let adminPublicKey):
                        
                        let serverResponseType = ServerResponse.ResponseType.requestGroupBlobLock(result: .lockObtained(encryptedServerBlob: encryptedBlob, logEntries: logItems, groupAdminPublicKey: adminPublicKey))
                        serverQuery.responseType = serverResponseType
                        // Continues after the end of the status block

                    case .deletedFromServer, .invalidSignature:

                        let serverResponseType = ServerResponse.ResponseType.requestGroupBlobLock(result: .permanentFailure)
                        serverQuery.responseType = serverResponseType
                        // Continues after the end of the status block

                    }
                    
                    // Common to .ok, .deletedFromServer, .invalidSignature, .generalError

                    do {
                        try obvContext.save(logOnFailure: log)
                    } catch {
                        os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                        _ = removeInfoFor(task)
                        queueForCallingDelegate.async {
                            delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                        }
                        return
                    }

                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return

                    
                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerGroupBlobLockServerMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, objectId.debugDescription, error.localizedDescription)
                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return

                }

            case .updateGroupBlob:
                
                let result = ObvServerGroupBlobUpdateServerMethod.parseObvServerResponse(responseData: responseData, using: log)

                switch result {
                case .success(let status):
                    
                    os_log("The ObvServerGroupBlobUpdateServerMethod returned status is %{public}@", log: log, type: .debug, String(reflecting: status))

                    switch status {
                        
                    case .generalError, .groupIsLocked:
                        
                        _ = removeInfoFor(task)
                        queueForCallingDelegate.async {
                            delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                        }
                        return

                    case .ok:
                        
                        let serverResponseType = ServerResponse.ResponseType.updateGroupBlob(uploadResult: .success)
                        serverQuery.responseType = serverResponseType
                        // Continues after the end of the status block

                    case .deletedFromServer, .invalidSignature:

                        let serverResponseType = ServerResponse.ResponseType.updateGroupBlob(uploadResult: .permanentFailure)
                        serverQuery.responseType = serverResponseType
                        // Continues after the end of the status block

                    case .groupNotLocked:
                        
                        let serverResponseType = ServerResponse.ResponseType.updateGroupBlob(uploadResult: .temporaryFailure)
                        serverQuery.responseType = serverResponseType
                        // Continues after the end of the status block

                    }
                    
                    // Common to .ok, .deletedFromServer, .invalidSignature, .groupNotLocked

                    do {
                        try obvContext.save(logOnFailure: log)
                    } catch {
                        os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                        _ = removeInfoFor(task)
                        queueForCallingDelegate.async {
                            delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                        }
                        return
                    }

                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return

                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerGroupBlobUpdateServerMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, objectId.debugDescription, error.localizedDescription)
                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerQuery(withObjectId: objectId, flowId: flowId)
                    }
                    return

                }

            }

        }

    }
    
    
    /// Helper method called when the server query failed because the server session is invalid.
    private func processInvalidSessionForTask(_ task: URLSessionTask, ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
                
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        os_log("The session is invalid", log: log, type: .error)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            return
        }

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: ownedIdentity) else {
                _ = removeInfoFor(task)
                queueForCallingDelegate.async {
                    do {
                        try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: ownedIdentity, flowId: flowId)
                    } catch {
                        os_log("Call to serverSessionRequired did fail", log: log, type: .fault)
                        assertionFailure()
                    }
                }
                return
            }
            
            guard let token = serverSession.token else {
                _ = removeInfoFor(task)
                queueForCallingDelegate.async {
                    do {
                        try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: ownedIdentity, flowId: flowId)
                    } catch {
                        os_log("Call to serverSessionRequired did fail", log: log, type: .fault)
                        assertionFailure()
                    }
                }
                return
            }
            
            _ = removeInfoFor(task)
            queueForCallingDelegate.async {
                do {
                    try delegateManager.networkFetchFlowDelegate.serverSession(of: ownedIdentity, hasInvalidToken: token, flowId: flowId)
                } catch {
                    os_log("Call to serverSession(of: ObvCryptoIdentity, hasInvalidToken: Data, flowId: FlowIdentifier) did fail", log: log, type: .fault)
                    assertionFailure()
                }
            }
        }
        
        return

    }
}
