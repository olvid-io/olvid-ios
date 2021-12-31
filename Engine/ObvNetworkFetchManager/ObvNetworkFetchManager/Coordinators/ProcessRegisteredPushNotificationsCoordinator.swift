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
import os.log
import ObvServerInterface
import ObvTypes
import ObvOperation
import ObvCrypto
import ObvMetaManager
import OlvidUtils


final class ProcessRegisteredPushNotificationsCoordinator: NSObject {
    
    // MARK: - Instance variables
    
    fileprivate let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "ProcessRegisteredPushNotificationsCoordinator"
    
    weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    private let localQueue = DispatchQueue(label: "ProcessRegisteredPushNotificationsCoordinatorQueue")
    
    private lazy var session: URLSession! = {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        return URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }()

    private var _currentTasks = [UIBackgroundTaskIdentifier: (ownedIdentity: ObvCryptoIdentity, currentDeviceUid: UID, dataReceived: Data, flowId: FlowIdentifier)]()
    private var currentTasksQueue = DispatchQueue(label: "GetTokenCoordinatorQueueForCurrentDownloadTasks")
    
    private let remoteNotificationByteIdentifierForServer: Data
    
    init(remoteNotificationByteIdentifierForServer: Data) {
        self.remoteNotificationByteIdentifierForServer = remoteNotificationByteIdentifierForServer
        super.init()
    }

}

// MARK: - Synchronized access to the current download tasks

extension ProcessRegisteredPushNotificationsCoordinator {
    
    private func currentTaskExistsFor(_ identity: ObvCryptoIdentity, andDeviceUid deviceUid: UID) -> Bool {
        var exist = true
        currentTasksQueue.sync {
            exist = _currentTasks.values.contains(where: { $0.ownedIdentity == identity && $0.currentDeviceUid == deviceUid })
        }
        return exist
    }
    
    private func removeInfoFor(_ task: URLSessionTask) -> (ownedIdentity: ObvCryptoIdentity, currentDeviceUid: UID, dataReceived: Data, flowId: FlowIdentifier)? {
        var info: (ObvCryptoIdentity, UID, Data, FlowIdentifier)? = nil
        currentTasksQueue.sync {
            info = _currentTasks.removeValue(forKey: UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier))
        }
        return info
    }
    
    private func getInfoFor(_ task: URLSessionTask) -> (ownedIdentity: ObvCryptoIdentity, currentDeviceUid: UID, dataReceived: Data, flowId: FlowIdentifier)? {
        var info: (ObvCryptoIdentity, UID, Data, FlowIdentifier)? = nil
        currentTasksQueue.sync {
            info = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)]
        }
        return info
    }
    
    private func insert(_ task: URLSessionTask, for identity: ObvCryptoIdentity, andDeviceUid deviceUid: UID, flowId: FlowIdentifier) {
        currentTasksQueue.sync {
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (identity, deviceUid, Data(), flowId)
        }
    }
    
    private func accumulate(_ data: Data, forTask task: URLSessionTask) {
        currentTasksQueue.sync {
            guard let (ownedIdentity, currentDeviceUid, currentData, flowId) = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] else { return }
            var newData = currentData
            newData.append(data)
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (ownedIdentity, currentDeviceUid, newData, flowId)
        }
    }

}

// MARK: - ProcessRegisteredPushNotificationsDelegate

extension ProcessRegisteredPushNotificationsCoordinator: ProcessRegisteredPushNotificationsDelegate {
    
    private enum SyncQueueOutput {
        case previousTaskExists
        case serverSessionRequired(flowId: FlowIdentifier)
        case failedToGetRegisteredPushNotifications
        case pollingRequested(withPollingIdentifier: UUID)
        case newTaskToRun(task: URLSessionTask)
        case noRegisteredPushNotification
        case failedToCreateTask(error: Error)
    }

    func process(forIdentity identity: ObvCryptoIdentity, withDeviceUid deviceUid: UID, flowId: FlowIdentifier) throws {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        var syncQueueOutput: SyncQueueOutput? // The state after the localQueue.sync is executed
        
        try localQueue.sync {
            
            guard !currentTaskExistsFor(identity, andDeviceUid: deviceUid) else {
                syncQueueOutput = .previousTaskExists
                return
            }

            try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
                
                guard let serverSession = try ServerSession.get(within: obvContext, withIdentity: identity) else {
                    syncQueueOutput = .serverSessionRequired(flowId: flowId)
                    return
                }
                
                guard let token = serverSession.token else {
                    syncQueueOutput = .serverSessionRequired(flowId: flowId)
                    return
                }
                
                // Find all registered push notifications for the targeted identity
                
                guard var registeredPushNotifications = RegisteredPushNotification.getAllSortedByCreationDate(for: identity, delegateManager: delegateManager, within: obvContext) else {
                    os_log("Could not get the registered push notifications", log: log, type: .error)
                    syncQueueOutput = .failedToGetRegisteredPushNotifications
                    return
                }
                
                guard !registeredPushNotifications.isEmpty else {
                    os_log("There is no registered push notification for the identity %@ (this may happen if we just registered to remote push notifications)", log: log, type: .debug, identity.debugDescription)
                    syncQueueOutput = .noRegisteredPushNotification
                    return
                }
                
                // Extract the latest registered push notification of type "remote push". If there is none, extract the latest push notification. It will soon be the current one.
                
                let registeredPushNotificationToUse: RegisteredPushNotification
                do {
                    let registeredRemotePushNotifications = registeredPushNotifications.filter {
                        switch $0.pushNotificationType {
                        case .remote:
                            return true
                        case .polling, .registerDeviceUid:
                            return false
                        }
                    }
                    if registeredRemotePushNotifications.count > 0 {
                        registeredPushNotificationToUse = registeredRemotePushNotifications.last!
                    } else {
                        registeredPushNotificationToUse = registeredPushNotifications.removeLast()
                    }
                }
                
                let keycloakPushTopics: Set<String>
                do {
                    keycloakPushTopics = try identityDelegate.getKeycloakPushTopics(ownedCryptoIdentity: identity, within: obvContext)
                } catch {
                    os_log("Could not get registered push topics from identity manager: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    // In production, continue anyway
                    keycloakPushTopics = Set<String>()
                }

                // Process the latest registered push notification
                
                switch registeredPushNotificationToUse.pushNotificationType {
                    
                case .polling:
                    
                    registeredPushNotifications.forEach { obvContext.delete($0) } // We delete the other polling push notifications
                    try? obvContext.save(logOnFailure: log)
                    syncQueueOutput = .pollingRequested(withPollingIdentifier: registeredPushNotificationToUse.pollingIdentifier!)
                    return
                    
                case .remote(pushToken: let pushToken, voipToken: let voipToken, maskingUID: let maskingUID, parameters: let parameters):
                                        
                    let method = ObvServerRegisterRemotePushNotificationMethod(ownedIdentity: identity,
                                                                               token: token,
                                                                               deviceUid: deviceUid,
                                                                               remoteNotificationByteIdentifierForServer: remoteNotificationByteIdentifierForServer,
                                                                               toIdentity: identity,
                                                                               deviceTokensAndmaskingUID: (pushToken, voipToken, maskingUID),
                                                                               parameters: parameters,
                                                                               keycloakPushTopics: keycloakPushTopics,
                                                                               flowId: flowId)
                    method.identityDelegate = delegateManager.identityDelegate

                    let task: URLSessionDataTask
                    do {
                        task = try method.dataTask(within: self.session)
                    } catch let error {
                        syncQueueOutput = .failedToCreateTask(error: error)
                        return
                    }

                    insert(task, for: identity, andDeviceUid: deviceUid, flowId: flowId)
                    
                    syncQueueOutput = .newTaskToRun(task: task)
                    
                    return
                    
                case .registerDeviceUid(parameters: let parameters):
                    
                    let method = ObvServerRegisterRemotePushNotificationMethod(ownedIdentity: identity,
                                                                               token: token,
                                                                               deviceUid: deviceUid,
                                                                               remoteNotificationByteIdentifierForServer: Data([0xff]),
                                                                               toIdentity: identity,
                                                                               deviceTokensAndmaskingUID: nil,
                                                                               parameters: parameters,
                                                                               keycloakPushTopics: keycloakPushTopics,
                                                                               flowId: flowId)
                    method.identityDelegate = delegateManager.identityDelegate

                    let task: URLSessionDataTask
                    do {
                        task = try method.dataTask(within: self.session)
                    } catch let error {
                        syncQueueOutput = .failedToCreateTask(error: error)
                        return
                    }

                    insert(task, for: identity, andDeviceUid: deviceUid, flowId: flowId)
                    
                    syncQueueOutput = .newTaskToRun(task: task)
                    
                    return

                }
            }
        } // End of localQueue.sync
        
        guard syncQueueOutput != nil else {
            os_log("syncQueueOutput is nil", log: log, type: .fault)
            return
        }
        
        switch syncQueueOutput! {

        case .previousTaskExists:
            os_log("A running task already exists for identity %{public}@ and device uid %{public}@", log: log, type: .debug, identity.debugDescription, deviceUid.debugDescription)

        case .serverSessionRequired(flowId: let flowId):
            os_log("Server session required for identity %{public}@", log: log, type: .debug, identity.debugDescription)
            try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: identity, flowId: flowId)
            delegateManager.networkFetchFlowDelegate.failedToProcessRegisteredPushNotification(for: identity, withDeviceUid: deviceUid, flowId: flowId)

        case .failedToGetRegisteredPushNotifications:
            os_log("Failed to get the registered push notification for identity %{public}@", log: log, type: .error, identity.debugDescription)
            delegateManager.networkFetchFlowDelegate.failedToProcessRegisteredPushNotification(for: identity, withDeviceUid: deviceUid, flowId: flowId)

        case .pollingRequested(withPollingIdentifier: let pollingIdentifier):
            os_log("Polling requested for identity %{public}@", log: log, type: .debug, identity.debugDescription)
            delegateManager.networkFetchFlowDelegate.pollingRequested(for: identity, withDeviceUid: deviceUid, andPollingIdentifier: pollingIdentifier, flowId: flowId)

        case .newTaskToRun(task: let task):
            os_log("New task to run for identity %{public}@ (the remote notification byte identifier is %{public}@)", log: log, type: .debug, identity.debugDescription, remoteNotificationByteIdentifierForServer as CVarArg)
            task.resume()

        case .failedToCreateTask(error: let error):
            os_log("Could not create task for ObvServerRegisterRemotePushNotificationMethod: %{public}@", log: log, type: .error, error.localizedDescription)
            return

        case .noRegisteredPushNotification:
            os_log("Could not find a registered push notification within the RegisteredPushNotification DB. We do nothing.", log: log, type: .debug)
        }
    }
}


// MARK: - URLSessionDataDelegate

extension ProcessRegisteredPushNotificationsCoordinator: URLSessionDataDelegate {
    
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
        
        guard let (identity, deviceUid, responseData, flowId) = getInfoFor(task) else { return }
        
        guard error == nil else {
            os_log("The ObvServerRegisterRemotePushNotificationMethod task failed for identity %{public}@: %@", log: log, type: .error, identity.debugDescription, error!.localizedDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.failedToProcessRegisteredPushNotification(for: identity, withDeviceUid: deviceUid, flowId: flowId)
            return
        }
        
        // If we reach this point, the data task did complete without error

        guard let status = ObvServerRegisterRemotePushNotificationMethod.parseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response for the ObvServerRegisterRemotePushNotificationMethod download task for identity %{public}@", log: log, type: .fault, identity.debugDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.failedToProcessRegisteredPushNotification(for: identity, withDeviceUid: deviceUid, flowId: flowId)
            return
        }
        
        switch status {
        case .ok:
            os_log("The push notification registration was successfully received by the server for identity %{public}@. This device is registered 🥳.", log: log, type: .info, identity.debugDescription)
            _ = removeInfoFor(task)
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                guard let registeredPushNotifications = RegisteredPushNotification.getAllSortedByCreationDate(for: identity, delegateManager: delegateManager, within: obvContext) else {
                    os_log("Could not get the registered push notifications", log: log, type: .fault)
                    return
                }
                registeredPushNotifications.forEach { obvContext.delete($0) }
                try? obvContext.save(logOnFailure: log)
            }
            delegateManager.networkFetchFlowDelegate.serverReportedThatThisDeviceWasSuccessfullyRegistered(forOwnedIdentity: identity, flowId: flowId)
            return
            
        case .invalidSession:
            os_log("The session is invalid", log: log, type: .error)
            
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: identity) else {
                    _ = removeInfoFor(task)
                    do {
                        try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: identity, flowId: flowId)
                    } catch {
                        os_log("Call to serverSessionRequired did fail", log: log, type: .fault)
                        assertionFailure()
                    }
                    return
                }
                
                guard let token = serverSession.token else {
                    _ = removeInfoFor(task)
                    do {
                        try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: identity, flowId: flowId)
                    } catch {
                        os_log("Call to serverSessionRequired did fail", log: log, type: .fault)
                        assertionFailure()
                    }
                    return
                }
                
                _ = removeInfoFor(task)
                do {
                    try delegateManager.networkFetchFlowDelegate.serverSession(of: identity, hasInvalidToken: token, flowId: flowId)
                } catch {
                    os_log("Call to to serverSession(of: ObvCryptoIdentity, hasInvalidToken: Data, flowId: FlowIdentifier) did fail", log: log, type: .fault)
                    assertionFailure()
                }
            }
            
            return
            
        case .anotherDeviceIsAlreadyRegistered:
            os_log("Server reported that another device is already registered, during the ObvServerRegisterRemotePushNotificationMethod download task for identity %{public}@", log: log, type: .error, identity.debugDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.serverReportedThatAnotherDeviceIsAlreadyRegistered(forOwnedIdentity: identity, flowId: flowId)
            return
            
        case .generalError:
            os_log("Server reported general error during the ObvServerRegisterRemotePushNotificationMethod download task for identity %{public}@", log: log, type: .fault, identity.debugDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.failedToProcessRegisteredPushNotification(for: identity, withDeviceUid: deviceUid, flowId: flowId)
            return
        }
    }
}
