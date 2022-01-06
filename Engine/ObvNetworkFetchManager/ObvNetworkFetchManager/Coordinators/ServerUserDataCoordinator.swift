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
import os.log
import ObvTypes
import ObvCrypto
import ObvMetaManager
import ObvServerInterface
import ObvEncoder
import OlvidUtils

protocol ServerUserDataDelegate {
    func cleanUserData(flowId: FlowIdentifier)
    func postUserData(input: ServerUserDataInput, flowId: FlowIdentifier)
}

enum ServerUserDataTaskKind {
    case refresh
    case deleted
}

/// Minimal information that are needed to create a ServerUserData operation
struct ServerUserDataInput: Hashable {
    let label: String
    let ownedIdentity: ObvCryptoIdentity
    let kind: ServerUserDataTaskKind
}

final class ServerUserDataCoordinator: NSObject {

    // MARK: - Instance variables

    fileprivate let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "ServerUserDataCoordinator"

    weak var delegateManager: ObvNetworkFetchDelegateManager?

    private lazy var session: URLSession! = {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.useOlvidSettings(sharedContainerIdentifier: delegateManager?.sharedContainerIdentifier)
        return URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }()

    private var _currentTasks = [UIBackgroundTaskIdentifier: (input: ServerUserDataInput, dataReceived: Data, flowId: FlowIdentifier)]()
    private var currentTasksQueue = DispatchQueue(label: "ServerUserDataCoordinatorForCurrentTasks")

    private var localQueue = DispatchQueue(label: "ServerUserDataCoordinatorQueue")
    private let internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .default
        queue.name = "ServerUserDataCoordinatorQueueOperationQueue"
        return queue
    }()

    let prng: PRNGService
    let downloadedUserData: URL
    private var notificationCenterTokens = [NSObjectProtocol]()

    init(prng: PRNGService, downloadedUserData: URL) {
        self.prng = prng
        self.downloadedUserData = downloadedUserData
    }

    func finalizeInitialization() {
        guard let notificationDelegate = delegateManager?.notificationDelegate else { assertionFailure(); return }
        notificationCenterTokens.append(ObvIdentityNotificationNew.observeServerLabelHasBeenDeleted(within: notificationDelegate, queue: internalQueue) { [weak self] (ownedCryptoIdentity, label) in
            let flowId = FlowIdentifier()
            let input = ServerUserDataInput(label: label, ownedIdentity: ownedCryptoIdentity, kind: .deleted)
            self?.postUserData(input: input, flowId: flowId)
        })
    }


    public func cleanUserData(flowId: FlowIdentifier) {
        // Check all ServerUserData
        // Delete no longer useful ServerUserData, refresh those that need it

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        guard let identityDelegate = delegateManager.identityDelegate else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Identity Delegate is not set", log: log, type: .fault)
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            return
        }

        // Check all ServerUserData
        // Delete no longer useful ServerUserData, refresh those that need it

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { obvContext in

            let userDatas: (toDelete: Set<UserData>, toRefresh: Set<UserData>)
            do {
                userDatas = try identityDelegate.getAllServerDataToSynchronizeWithServer(within: obvContext)
            } catch {
                os_log("Could not get user datas to sync with server: %{public}@", type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            
            for userData in userDatas.toDelete {
                queueNewDeleteUserDataOperation(ownedIdentity: userData.ownedIdentity, label: userData.label, flowId: flowId, within: obvContext)
            }
            
            for userData in userDatas.toRefresh {
                queueNewRefreshUserDataOperation(ownedIdentity: userData.ownedIdentity, label: userData.label, flowId: flowId, within: obvContext)
            }
            
        }

        // Cleanup downloaded user data dir of orphan files

        if let files = try? FileManager.default.contentsOfDirectory(at: self.downloadedUserData, includingPropertiesForKeys: nil, options: []) {
            for file in files {
                /// REMARK This file name is built in ObvServerGetUserDataMethod#parseObvServerResponse
                let components = file.lastPathComponent.components(separatedBy: ".")
                if components.count == 2 {
                    if let expireTimestamp = Int(components.first!) {
                        let expirationDate = Date(timeIntervalSince1970: TimeInterval(expireTimestamp))
                        if expirationDate > Date() { continue }
                    }
                    /// filename is not well-formed, or the file is expired --> delete it
                    try? FileManager.default.removeItem(at: file)

                }
            }
        }

    }

}

// MARK: - ServerUserDataDelegate

extension ServerUserDataCoordinator: ServerUserDataDelegate {

    private enum SyncQueueOutput {
        case previousTaskExists
        case newTaskToRun(task: URLSessionTask)
        case failedToCreateTask(methodName: String, error: Error)
        case serverSessionRequired(flowId: FlowIdentifier)
    }

    private func queueNewUserDataOperation(ownedIdentity: ObvCryptoIdentity, label: String, flowId: FlowIdentifier, within obvContext: ObvContext, buildMethod: (OSLog, Data) -> (ObvServerDataMethod, String, ServerUserDataTaskKind)) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        var syncQueueOutput: SyncQueueOutput? // The state after the localQueue.sync is executed

        localQueue.sync {

            guard !currentTaskExistsForServerUserData(with: label) else {
                syncQueueOutput = .previousTaskExists
                return
            }

            guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: ownedIdentity) else {
                syncQueueOutput = .serverSessionRequired(flowId: flowId)
                return
            }
            guard let token = serverSession.token else {
                syncQueueOutput = .serverSessionRequired(flowId: flowId)
                return
            }

            var (method, methodName, kind) = buildMethod(log, token)
            method.identityDelegate = delegateManager.identityDelegate

            let task: URLSessionDataTask
            do {
                task = try method.dataTask(within: self.session)
            } catch let error {
                syncQueueOutput = .failedToCreateTask(methodName: methodName, error: error)
                return
            }

            let input = ServerUserDataInput(label: label, ownedIdentity: ownedIdentity, kind: kind)
            insert(task, input: input, flowId: flowId)

            syncQueueOutput = .newTaskToRun(task: task)
            return
        } // End of localQueue.sync


        guard syncQueueOutput != nil else {
            os_log("syncQueueOutput is nil", log: log, type: .fault)
            return
        }

        switch syncQueueOutput! {

        case .previousTaskExists:
            os_log("A running task already exists for label %{public}@", log: log, type: .debug, label)
            return

        case .failedToCreateTask(methodName: let methodName ,error: let error):
            os_log("Could not create task for %@: %{public}@", log: log, type: .error,  methodName, error.localizedDescription)
            return

        case .serverSessionRequired:
            /// REMARK we will be called again by NetworkFetchFlowCoordinator#newToken
            try? delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: ownedIdentity, flowId: flowId)
        case .newTaskToRun(task: let task):
            os_log("New task to run for the label %{public}@", log: log, type: .debug, label)
            task.resume()
        }
    }

    func queueNewRefreshUserDataOperation(ownedIdentity: ObvCryptoIdentity, label: String, flowId: FlowIdentifier, within obvContext: ObvContext) {
        queueNewUserDataOperation(ownedIdentity: ownedIdentity, label: label, flowId: flowId, within: obvContext) { log, token in
            os_log("Creating a ObvServerGetUserDataMethod of the contact identity", log: log, type: .debug)
            return (ObvServerRefreshUserDataMethod(ownedIdentity: ownedIdentity, token: token, serverLabel: label, flowId: flowId), "ObvServerRefreshUserDataMethod", .refresh)
        }
    }


    func queueNewDeleteUserDataOperation(ownedIdentity: ObvCryptoIdentity, label: String, flowId: FlowIdentifier, within obvContext: ObvContext) {
        queueNewUserDataOperation(ownedIdentity: ownedIdentity, label: label, flowId: flowId, within: obvContext) { log, token in
            os_log("Creating a ObvServerDeleteUserDataMethod of the contact identity", log: log, type: .debug)
            return (ObvServerDeleteUserDataMethod(ownedIdentity: ownedIdentity, token: token, serverLabel: label, flowId: flowId), "ObvServerDeleteUserDataMethod", .deleted)
        }
    }

    func postUserData(input: ServerUserDataInput, flowId: FlowIdentifier) {
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            return
        }

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            switch input.kind {
            case .refresh:
                self.queueNewRefreshUserDataOperation(ownedIdentity: input.ownedIdentity, label: input.label, flowId: flowId, within: obvContext)
            case .deleted:
                self.queueNewDeleteUserDataOperation(ownedIdentity: input.ownedIdentity, label: input.label, flowId: flowId, within: obvContext)
            }
        }
    }

}

// MARK: - Synchronized access to the current user data tasks

extension ServerUserDataCoordinator {

    private func currentTaskExistsForServerUserData(with label: String) -> Bool {
        var exist = true
        currentTasksQueue.sync {
            // The following condition is weaker than the == on inputs, but it's ok to suppose that we cannot have differents operation for the same label.
            exist = _currentTasks.values.contains(where: { $0.input.label == label })
        }
        return exist
    }

    private func insert(_ task: URLSessionTask, input: ServerUserDataInput, flowId: FlowIdentifier) {
        currentTasksQueue.sync {
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (input, Data(), flowId)
        }
    }

    private func accumulate(_ data: Data, forTask task: URLSessionTask) {
        currentTasksQueue.sync {
            guard let (taskData, currentData, flowId) = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] else { return }
            var newData = currentData
            newData.append(data)
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (taskData, newData, flowId)
        }
    }

    private func getInfoFor(_ task: URLSessionTask) -> (input: ServerUserDataInput, dataReceived: Data, flowId: FlowIdentifier)? {
        var info: (ServerUserDataInput, Data, FlowIdentifier)? = nil
        currentTasksQueue.sync {
            info = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)]
        }
        return info
    }

    private func removeInfoFor(_ task: URLSessionTask) -> (input: ServerUserDataInput, dataReceived: Data, flowId: FlowIdentifier)? {
        var info: (ServerUserDataInput, Data, FlowIdentifier)? = nil
        currentTasksQueue.sync {
            info = _currentTasks.removeValue(forKey: UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier))
        }
        return info
    }

}

// MARK: - URLSessionDataDelegate

extension ServerUserDataCoordinator: URLSessionDataDelegate {

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        accumulate(data, forTask: dataTask)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        guard let identityDelegate = delegateManager.identityDelegate else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Identity Delegate is not set", log: log, type: .fault)
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            return
        }

        guard let (input, responseData, flowId) = getInfoFor(task) else { return }

        guard error == nil else {
            os_log("The task failed for server user data: %{public}@", log: log, type: .error, error!.localizedDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.failedToProcessServerUserData(input: input, flowId: flowId)
            return
        }

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            switch input.kind {
            case .refresh:
                guard let status = ObvServerRefreshUserDataMethod.parseObvServerResponse(responseData: responseData, using: log) else {
                    os_log("Could not parse the server response for the ObvServerRefreshUserDataMethod task of pending server query %{public}@", log: log, type: .fault, input.label)
                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.failedToProcessServerUserData(input: input, flowId: flowId)
                    return
                }
                switch status {
                case .ok:
                    identityDelegate.updateUserDataNextRefreshTimestamp(for: input.ownedIdentity, with: input.label, within: obvContext)

                    do {
                        try obvContext.save(logOnFailure: log)
                    } catch {
                        os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                        _ = removeInfoFor(task)
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerUserData(input: input, flowId: flowId)
                        return
                    }

                    _ = removeInfoFor(task)
                    return

                case .invalidToken:
                    _ = removeInfoFor(task)
                    createSession(input: input, delegateManager: delegateManager, task: task, log: log, within: obvContext, flowId: flowId)
                    return

                case .deletedFromServer:
                    let networkFetchDelegate = delegateManager.networkFetchFlowDelegate

                    do {
                        if let userData = identityDelegate.getServerUserData(for: input.ownedIdentity, with: input.label, within: obvContext) {
                            let dataURL: URL?
                            let dataKey: AuthenticatedEncryptionKey?
                            switch userData.kind {
                            case .identity:
                                let (ownedIdentityDetailsElements, photoURL) = try identityDelegate.getPublishedIdentityDetailsOfOwnedIdentity(userData.ownedIdentity, within: obvContext)
                                dataURL = photoURL
                                dataKey = ownedIdentityDetailsElements.photoServerKeyAndLabel?.key
                            case .group(groupUid: let groupUid):
                                let groupInformationWithPhoto = try identityDelegate.getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: userData.ownedIdentity, groupUid: groupUid, within: obvContext)
                                dataURL = groupInformationWithPhoto.groupDetailsElementsWithPhoto.photoURL
                                dataKey = groupInformationWithPhoto.groupDetailsElementsWithPhoto.photoServerKeyAndLabel?.key
                            }
                            if let dataURL = dataURL, let dataKey = dataKey {
                                let serverQueryType: ServerQuery.QueryType = .putUserData(label: input.label, dataURL: dataURL, dataKey: dataKey)
                                let noElements: [ObvEncoded] = []

                                let serverQuery = ServerQuery(ownedIdentity: input.ownedIdentity, queryType: serverQueryType, encodedElements: noElements.encode())

                                networkFetchDelegate.post(serverQuery, within: obvContext)

                                do {
                                    try obvContext.save(logOnFailure: log)
                                } catch {
                                    os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                                    _ = removeInfoFor(task)
                                    delegateManager.networkFetchFlowDelegate.failedToProcessServerUserData(input: input, flowId: flowId)
                                    return
                                }
                            }
                        }
                    } catch {
                        // Do nothing, this will be retried after the next restart
                    }
                    _ = removeInfoFor(task)
                    return
                case .generalError:
                    os_log("Server reported general error during the ObvServerRefreshUserDataMethod for label %{public}@ within flow %{public}@", log: log, type: .fault, input.label, flowId.debugDescription)
                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.failedToProcessServerUserData(input: input, flowId: flowId)
                    return
                }
            case .deleted:
                guard let status = ObvServerDeleteUserDataMethod.parseObvServerResponse(responseData: responseData, using: log) else {
                    os_log("Could not parse the server response for the ObvServerDeleteUserDataMethod task of pending server query %{public}@", log: log, type: .fault, input.label)
                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.failedToProcessServerUserData(input: input, flowId: flowId)
                    return
                }
                switch status {
                case .ok:
                    identityDelegate.deleteUserData(for: input.ownedIdentity, with: input.label, within: obvContext)

                    do {
                        try obvContext.save(logOnFailure: log)
                    } catch {
                        os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                        _ = removeInfoFor(task)
                        delegateManager.networkFetchFlowDelegate.failedToProcessServerUserData(input: input, flowId: flowId)
                        return
                    }

                    _ = removeInfoFor(task)
                    return

                case .invalidToken:
                    _ = removeInfoFor(task)
                    createSession(input: input, delegateManager: delegateManager, task: task, log: log, within: obvContext, flowId: flowId)
                    return

                case .generalError:
                    os_log("Server reported general error during the ObvServerDeleteUserDataMethod for label %{public}@ within flow %{public}@", log: log, type: .fault, input.label, flowId.debugDescription)
                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.failedToProcessServerUserData(input: input, flowId: flowId)
                    return
                }
            }

        }


    }

    private func createSession(input: ServerUserDataInput, delegateManager: ObvNetworkFetchDelegateManager, task: URLSessionTask, log: OSLog, within obvContext: ObvContext, flowId: FlowIdentifier) {
        guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: input.ownedIdentity) else {
            _ = removeInfoFor(task)
            do {
                try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: input.ownedIdentity, flowId: flowId)
            } catch {
                os_log("Call to serverSessionRequired did fail", log: log, type: .fault)
                assertionFailure()
            }
            return
        }

        guard let token = serverSession.token else {
            _ = removeInfoFor(task)
            do {
                try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: input.ownedIdentity, flowId: flowId)
            } catch {
                os_log("Call to serverSessionRequired did fail", log: log, type: .fault)
                assertionFailure()
            }
            return
        }

        _ = removeInfoFor(task)
        do {
            try delegateManager.networkFetchFlowDelegate.serverSession(of: input.ownedIdentity, hasInvalidToken: token, flowId: flowId)
        } catch {
            os_log("Call to serverSession(of: ObvCryptoIdentity, hasInvalidToken: Data, flowId: FlowIdentifier) did fail", log: log, type: .fault)
            assertionFailure()
        }
    }


}
