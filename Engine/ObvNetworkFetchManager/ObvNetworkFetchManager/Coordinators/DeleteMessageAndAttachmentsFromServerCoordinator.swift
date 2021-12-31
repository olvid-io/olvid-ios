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
import CoreData
import OlvidUtils

final class DeleteMessageAndAttachmentsFromServerCoordinator: NSObject {
    
    // MARK: - Instance variables
    
    fileprivate let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "DeleteMessageAndAttachmentsFromServerAndLocalInboxesCoordinator"
    
    weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    private let localQueue = DispatchQueue(label: "DeleteMessageAndAttachmentsFromServerAndLocalInboxesCoordinatorQueue")
    
    private lazy var session: URLSession! = {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        return URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }()

    private var _currentTasks = [UIBackgroundTaskIdentifier: (messageId: MessageIdentifier, flowId: FlowIdentifier, dataReceived: Data)]()
    private var currentTasksQueue = DispatchQueue(label: "DeleteMessageAndAttachmentsFromServerAndLocalInboxesCoordinatorQueueForCurrentDownloadTasks")
}


// MARK: - Synchronized access to the current download tasks

extension DeleteMessageAndAttachmentsFromServerCoordinator {
    
    private func currentTaskExistsForMessage(messageId: MessageIdentifier) -> Bool {
        var exist = true
        currentTasksQueue.sync {
            exist = _currentTasks.values.contains(where: { $0.messageId == messageId })
        }
        return exist
    }
    
    private func removeInfoFor(_ task: URLSessionTask) -> (messageId: MessageIdentifier, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (MessageIdentifier, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentTasks.removeValue(forKey: UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier))
        }
        return info
    }
    
    private func getInfoFor(_ task: URLSessionTask) -> (messageId: MessageIdentifier, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (MessageIdentifier, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)]
        }
        return info
    }
    
    private func insert(_ task: URLSessionTask, messageId: MessageIdentifier, flowId: FlowIdentifier) {
        currentTasksQueue.sync {
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (messageId, flowId, Data())
        }
    }
   
    private func accumulate(_ data: Data, forTask task: URLSessionTask) {
        currentTasksQueue.sync {
            guard let (messageId, flowId, currentData) = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] else { return }
            var newData = currentData
            newData.append(data)
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (messageId, flowId, newData)
        }
    }

}


// MARK: - DeleteMessageAndAttachmentsFromServerAndLocalInboxesDelegate

extension DeleteMessageAndAttachmentsFromServerCoordinator: DeleteMessageAndAttachmentsFromServerDelegate {
    
    private enum SyncQueueOutput {
        case cannotFindPendingDeleteInDatabase
        case previousTaskExists
        case serverSessionRequired(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
        case newTaskToRun(task: URLSessionTask)
        case failedToCreateTask(error: Error)
    }

    
    func processPendingDeleteFromServer(messageId: MessageIdentifier, flowId: FlowIdentifier) throws {
        
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
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        var syncQueueOutput: SyncQueueOutput? // The state after the localQueue.sync is executed

        try localQueue.sync {
            
            guard !currentTaskExistsForMessage(messageId: messageId) else {
                syncQueueOutput = .previousTaskExists
                return
            }
            
            try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
                
                guard try PendingDeleteFromServer.get(messageId: messageId, within: obvContext) != nil else {
                    os_log("No pending deleting item found, finishing immediately", log: log, type: .debug)
                    syncQueueOutput = .cannotFindPendingDeleteInDatabase
                    return
                }
                
                let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(messageId.ownedCryptoIdentity, within: obvContext)
                
                guard let serverSession = try ServerSession.get(within: obvContext, withIdentity: messageId.ownedCryptoIdentity) else {
                    syncQueueOutput = .serverSessionRequired(ownedIdentity: messageId.ownedCryptoIdentity, flowId: flowId)
                    return
                }
                guard let token = serverSession.token else {
                    syncQueueOutput = .serverSessionRequired(ownedIdentity: messageId.ownedCryptoIdentity, flowId: flowId)
                    return
                }

                // If we reach this point, we can delete the message/attachments from the server
                                
                let method = ObvServerDeleteMessageAndAttachmentsMethod(token: token,
                                                                        messageId: messageId,
                                                                        deviceUid: currentDeviceUid,
                                                                        flowId: flowId)
                method.identityDelegate = delegateManager.identityDelegate
                let task: URLSessionDataTask
                do {
                    task = try method.dataTask(within: self.session)
                } catch let error {
                    syncQueueOutput = .failedToCreateTask(error: error)
                    return
                }

                insert(task, messageId: messageId, flowId: flowId)
                
                syncQueueOutput = .newTaskToRun(task: task)

            }
            
        } // End of localQueue.sync
        
        guard syncQueueOutput != nil else {
            os_log("syncQueueOutput is nil", log: log, type: .fault)
            return
        }

        switch syncQueueOutput! {
            
        case .cannotFindPendingDeleteInDatabase:
            os_log("Cannot find a pending delete in database for message %{public}@", log: log, type: .debug, messageId.debugDescription)
            
        case .previousTaskExists:
            os_log("A running task already exists for message %{public}@", log: log, type: .debug, messageId.debugDescription)
            
        case .serverSessionRequired(ownedIdentity: let identity, flowId: let flowId):
            os_log("Server session required for identity %{public}@", log: log, type: .debug, identity.debugDescription)
            try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: identity, flowId: flowId)
            
        case .failedToCreateTask(error: let error):
            os_log("Could not create task for ObvServerDeleteMessageAndAttachmentsMethod: %{public}@", log: log, type: .error, error.localizedDescription)
            return

        case .newTaskToRun(task: let task):
            os_log("New task to run for message %{public}@", log: log, type: .debug, messageId.debugDescription)
            task.resume()
        }
        
    }
}


// MARK: - URLSessionDataDelegate

extension DeleteMessageAndAttachmentsFromServerCoordinator: URLSessionDataDelegate {
    
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

        guard let (messageId, flowId, responseData) = getInfoFor(task) else { return }
        
        guard error == nil else {
            os_log("The ObvServerDeleteMessageAndAttachmentsMethod download task failed for message %{public}@ within flow %{public}@: %@", log: log, type: .error, messageId.debugDescription, flowId.debugDescription, error!.localizedDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.failedToProcessPendingDeleteFromServer(messageId: messageId, flowId: flowId)
            return
        }
        
        // If we reach this point, the data task did complete without error

        guard let status = ObvServerDeleteMessageAndAttachmentsMethod.parseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response for the ObvServerDeleteMessageAndAttachmentsMethod download task for message %{public}@ within flow %{public}@", log: log, type: .fault, messageId.debugDescription, flowId.debugDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.failedToProcessPendingDeleteFromServer(messageId: messageId, flowId: flowId)
            return
        }
        
        switch status {
        case .ok:
            os_log("The message/attachments %{public}@ were deleted from the server within flow %{public}@", log: log, type: .debug, messageId.debugDescription, flowId.debugDescription)
            
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                
                obvContext.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
                
                guard let pendingDeleteFromServer = try? PendingDeleteFromServer.get(messageId: messageId, within: obvContext) else {
                    os_log("No pending deleting item found, finishing immediately", log: log, type: .debug)
                    _ = removeInfoFor(task)
                    return
                }
                
                obvContext.delete(pendingDeleteFromServer)
                
                // Normally, a pending delete from server object can only be created atomically with the deletion of the message.
                // Moreover, the message cannot be "listed" during the existence of this PendingDeleteFromServer object.
                // Thus: the InboxMessage should not contain the message at this point.
                assert((try? InboxMessage.get(messageId: messageId, within: obvContext)) == nil)
                
                do {
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not save context", log: log, type: .fault)
                    return
                }
                
                os_log("We successfully deleted message/attachments %{public}@ from server within flow %{public}@", log: log, type: .debug, messageId.debugDescription, flowId.debugDescription)
                _ = removeInfoFor(task)
                delegateManager.networkFetchFlowDelegate.messageAndAttachmentsWereDeletedFromServerAndInboxes(messageId: messageId, flowId: flowId)
            }
            
            return
            
        case .invalidSession:
            os_log("The session is invalid", log: log, type: .error)

            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                
                let ownedCryptoIdentity = messageId.ownedCryptoIdentity
                
                guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: ownedCryptoIdentity) else {
                    _ = removeInfoFor(task)
                    do {
                        try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: ownedCryptoIdentity, flowId: flowId)
                    } catch {
                        os_log("Call to serverSessionRequired did fail", log: log, type: .fault)
                        assertionFailure()
                    }
                    return
                }
                
                guard let token = serverSession.token else {
                    _ = removeInfoFor(task)
                    do {
                        try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: ownedCryptoIdentity, flowId: flowId)
                    } catch {
                        os_log("Call to serverSessionRequired did fail", log: log, type: .fault)
                        assertionFailure()
                    }
                    return
                }
                
                _ = removeInfoFor(task)
                do {
                    try delegateManager.networkFetchFlowDelegate.serverSession(of: ownedCryptoIdentity, hasInvalidToken: token, flowId: flowId)
                } catch {
                    os_log("Call to serverSession(of: ObvCryptoIdentity, hasInvalidToken: Data, flowId: FlowIdentifier) did fail", log: log, type: .fault)
                    assertionFailure()
                }
            }
            
            return
            
        case .generalError:
            os_log("Server reported general error during the ObvServerDeleteMessageAndAttachmentsMethod download task for message %{public}@ within flow %{public}@", log: log, type: .fault, messageId.debugDescription, flowId.debugDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.failedToProcessPendingDeleteFromServer(messageId: messageId, flowId: flowId)
            return
        }
    }
}
