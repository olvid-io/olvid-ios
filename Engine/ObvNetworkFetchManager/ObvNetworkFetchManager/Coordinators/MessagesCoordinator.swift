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
import ObvServerInterface
import ObvTypes
import ObvOperation
import ObvCrypto
import ObvMetaManager
import OlvidUtils
import CoreData

final class MessagesCoordinator: NSObject {
    
    // MARK: - Instance variables
    
    fileprivate let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "MessagesCoordinator"
    
    weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    private let localQueue = DispatchQueue(label: "MessagesCoordinator local queue")
    
    private lazy var session: URLSession! = {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        return URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }()
    
    private var _currentTasks = [UIBackgroundTaskIdentifier: (ownedIdentity: ObvCryptoIdentity, currentDeviceUid: UID, flowId: FlowIdentifier, dataReceived: Data)]()
    private var _currentExtendedPayloadDownloadTasks = [Int: (messageId: MessageIdentifier, flowId: FlowIdentifier, dataReceived: Data)]()
    private var currentTasksQueue = DispatchQueue(label: "MessagesCoordinator queue for current task")

    private static func makeError(message: String) -> Error { NSError(domain: "MessagesCoordinator", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { MessagesCoordinator.makeError(message: message) }

    private let queueForCallingDelegate = DispatchQueue(label: "MessagesCoordinator queue for calling delegate methods")

}

// MARK: - Synchronized access to the current download tasks

extension MessagesCoordinator {
    
    private func currentTaskExistsFor(_ identity: ObvCryptoIdentity, andDeviceUid uid: UID) -> Bool {
        var exist = true
        currentTasksQueue.sync {
            exist = _currentTasks.values.contains(where: { $0.ownedIdentity == identity && $0.currentDeviceUid == uid })
        }
        return exist
    }
    
    private func removeInfoFor(_ task: URLSessionTask) -> (ownedIdentity: ObvCryptoIdentity, currentDeviceUid: UID, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (ObvCryptoIdentity, UID, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentTasks.removeValue(forKey: UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier))
        }
        return info
    }
    
    private func getInfoFor(_ task: URLSessionTask) -> (ownedIdentity: ObvCryptoIdentity, currentDeviceUid: UID, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (ObvCryptoIdentity, UID, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)]
        }
        return info
    }
    
    private func insert(_ task: URLSessionTask, for identity: ObvCryptoIdentity, andDeviceUid uid: UID, flowId: FlowIdentifier) {
        currentTasksQueue.sync {
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (identity, uid, flowId, Data())
        }
    }
    
    private func accumulate(_ data: Data, forTask task: URLSessionTask) {
        currentTasksQueue.sync {
            guard let (ownedIdentity, currentDeviceUid, flowId, currentData) = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] else { return }
            var newData = currentData
            newData.append(data)
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (ownedIdentity, currentDeviceUid, flowId, newData)
        }
    }

}


// MARK: - Synchronized access to the current extended message payload download tasks

extension MessagesCoordinator {
    
    private func extendedPayloadDownloadTaskExistsFor(_ messageId: MessageIdentifier) -> Bool {
        var exist = true
        currentTasksQueue.sync {
            exist = _currentExtendedPayloadDownloadTasks.values.contains(where: { $0.messageId == messageId })
        }
        return exist
    }
    
    private func removeInfoForExtendedPayloadDownloadTask(_ task: URLSessionTask) -> (messageId: MessageIdentifier, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (MessageIdentifier, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentExtendedPayloadDownloadTasks.removeValue(forKey: task.taskIdentifier)
        }
        return info
    }
    
    private func getInfoForExtendedPayloadDownloadTask(_ task: URLSessionTask) -> (messageId: MessageIdentifier, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (MessageIdentifier, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentExtendedPayloadDownloadTasks[task.taskIdentifier]
        }
        return info
    }
    
    private func insertExtendedPayloadDownloadTask(_ task: URLSessionTask, for messageId: MessageIdentifier, flowId: FlowIdentifier) {
        currentTasksQueue.sync {
            _currentExtendedPayloadDownloadTasks[task.taskIdentifier] = (messageId, flowId, Data())
        }
    }
    
    private func accumulateExtendedPayloadData(_ data: Data, forTask task: URLSessionTask) {
        currentTasksQueue.sync {
            guard let (messageId, flowId, currentData) = _currentExtendedPayloadDownloadTasks[task.taskIdentifier] else { return }
            var newData = currentData
            newData.append(data)
            _currentExtendedPayloadDownloadTasks[task.taskIdentifier] = (messageId, flowId, newData)
        }
    }

}


// MARK: - DownloadMessagesAndListAttachmentsDelegate

extension MessagesCoordinator: MessagesDelegate {
    
    private enum SyncQueueOutput {
        case previousTaskExists
        case serverSessionRequired
        case newTaskToRun(task: URLSessionTask)
        case failedToCreateTask(error: Error)
    }

    
    func downloadMessagesAndListAttachments(for identity: ObvCryptoIdentity, andDeviceUid deviceUid: UID, flowId: FlowIdentifier) {
        
        assert(!Thread.isMainThread)

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
        
        os_log("🌊 Call to downloadMessagesAndListAttachments for identity %@ with flow id %{public}@", log: log, type: .debug, identity.debugDescription, flowId.debugDescription)
        
        var syncQueueOutput: SyncQueueOutput? // The state after the localQueue.sync is executed
        
        localQueue.sync {
            
            guard !currentTaskExistsFor(identity, andDeviceUid: deviceUid) else {
                syncQueueOutput = .previousTaskExists
                return
            }
            
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: identity) else {
                    syncQueueOutput = .serverSessionRequired
                    return
                }
                
                guard let token = serverSession.token else {
                    syncQueueOutput = .serverSessionRequired
                    return
                }
                
                // If we reach this point, we can list
                
                let method = ObvServerDownloadMessagesAndListAttachmentsMethod(ownedIdentity: identity, token: token, deviceUid: deviceUid, toIdentity: identity, flowId: flowId)
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
            }
            
        } // End of localQueue.sync
        
        assert(syncQueueOutput != nil)
        guard syncQueueOutput != nil else {
            os_log("syncQueueOutput is nil", log: log, type: .fault)
            return
        }
        
        switch syncQueueOutput! {
            
        case .previousTaskExists:
            os_log("A running task already exists for identity %@ with flow identifier %{public}@", log: log, type: .debug, identity.debugDescription, flowId.debugDescription)
            queueForCallingDelegate.async {
                delegateManager.networkFetchFlowDelegate.downloadingMessagesAndListingAttachmentWasNotNeeded(for: identity, andDeviceUid: deviceUid, flowId: flowId)
            }
            
        case .serverSessionRequired:
            os_log("Server session required for identity %@ with flow identifier %{public}@", log: log, type: .debug, identity.debugDescription, flowId.debugDescription)
            queueForCallingDelegate.async {
                do {
                    try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: identity, flowId: flowId)
                } catch {
                    os_log("Call serverSessionRequired did fail", log: log, type: .fault)
                    assertionFailure()
                }
            }
            
        case .failedToCreateTask(error: let error):
            if let serverMethodError = error as? ObvServerMethodError {
                switch serverMethodError {
                case .ownedIdentityIsActiveCheckerDelegateIsNotSet:
                    os_log("Could not create task for ObvServerDownloadMessagesAndListAttachmentsMethod (ownedIdentityIsActiveCheckerDelegateIsNotSet): %{public}@", log: log, type: .error, serverMethodError.localizedDescription)
                case .ownedIdentityIsNotActive:
                    os_log("Could not create task for ObvServerDownloadMessagesAndListAttachmentsMethod (ownedIdentityIsNotActive): %{public}@", log: log, type: .error, serverMethodError.localizedDescription)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: identity, flowId: flowId)
                    }
                    return
                }
            } else {
                os_log("Could not create task for ObvServerDownloadMessagesAndListAttachmentsMethod: %{public}@", log: log, type: .error, error.localizedDescription)
            }
            return
            
        case .newTaskToRun(task: let task):
            os_log("New task to run for identity %{public}@ with flow identifier %{public}@", log: log, type: .debug, identity.debugDescription, flowId.debugDescription)
            task.resume()
            
        }
    }

    
    
    /// Delete the message (and its attachments) from the inbox and creates a `PendingDeleteFromServer`.
    /// The reason why this method is defined within this coordinator is because this allows to synchronize it with the list of new messages.
    /// For this method to actually do something, the message and all its attachments must be marked for deletion, i.e., the `canBeDeleted`
    /// must return `true` when called on the message.
    func processMarkForDeletionForMessageAndAttachmentsAndCreatePendingDeleteFromServer(messageId: MessageIdentifier, flowId: FlowIdentifier) throws {
        
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
        
        try localQueue.sync {

            try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in

                guard let message = try InboxMessage.get(messageId: messageId, within: obvContext) else {
                    os_log("Could not find message, no need to delete it", log: log, type: .info)
                    return
                }

                guard message.canBeDeleted else {
                    os_log("Message cannot be deleted yet", log: log, type: .error)
                    assertionFailure()
                    return
                }
                
                for attachment in message.attachments {
                    try? attachment.deleteDownload(fromInbox: delegateManager.inbox)
                }

                try? message.deleteAttachmentsDirectory(fromInbox: delegateManager.inbox)
                
                obvContext.delete(message) // Cascade delete attachments
                
                if try PendingDeleteFromServer.get(messageId: messageId, within: obvContext) == nil {
                    _ = PendingDeleteFromServer(messageId: messageId, within: obvContext)
                }
                
                let queueForCallingDelegate = DispatchQueue(label: "MessagesCoordinator queue for calling delegate in processMarkForDeletionForMessageAndAttachmentsAndCreatePendingDeleteFromServer")

                try obvContext.addContextDidSaveCompletionHandler { (error) in
                    guard error == nil else { return }
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.newPendingDeleteToProcessForMessage(messageId: messageId, flowId: flowId)
                    }
                }
                
                do {
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not delete local message/attachments and thus, could not create PendingDeleteFromServer: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                }
                
            }
        }
    }
    
    
    /// When a message has no attachment, it can be received directely on the websocket. In such a case, the websocket manager calls this method.
    /// The reason why this method is defined within this coordinator is because this allows to synchronize it with the list of new messages.
    func saveMessageReceivedOnWebsocket(message: ObvServerDownloadMessagesAndListAttachmentsMethod.MessageAndAttachmentsOnServer, downloadTimestampFromServer: Date, ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) throws {
        
        let listOfMessageAndAttachmentsOnServer = [message]
        let localDownloadTimestamp = Date()
        
        try localQueue.sync {
            let idsOfNewMessages = try saveMessagesAndAttachmentsFromServer(listOfMessageAndAttachmentsOnServer,
                                                                            downloadTimestampFromServer: downloadTimestampFromServer,
                                                                            localDownloadTimestamp: localDownloadTimestamp,
                                                                            ownedIdentity: ownedIdentity,
                                                                            flowId: flowId)
            guard idsOfNewMessages.count == 1 else { throw makeError(message: "Could not save message") }
        }
        
        queueForCallingDelegate.async { [weak self] in
            self?.delegateManager?.networkFetchFlowDelegate.aMessageReceivedThroughTheWebsocketWasSavedByTheMessageDelegate(ownedCryptoIdentity: ownedIdentity, flowId: flowId)
        }
        
    }
}


// MARK: - Downloading extended payload

extension MessagesCoordinator {
    
    private enum SyncQueueOutputForExtendedPayload {
        case previousTaskExists
        case serverSessionRequired
        case cannotFindMessageInDatabase
        case extendedMessagePayloadKeyIsNotSet
        case newTaskToRun(task: URLSessionTask)
        case failedToCreateTask(error: Error)
    }

    
    func downloadExtendedMessagePayload(messageId: MessageIdentifier, flowId: FlowIdentifier) {
        
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
        
        os_log("🌊 Call to downloadExtendedMessagePayload for message %{public}@ with flow id %{public}@", log: log, type: .debug, messageId.debugDescription, flowId.debugDescription)
        
        var syncQueueOutput: SyncQueueOutputForExtendedPayload? // The state after the localQueue.sync is executed

        localQueue.sync {
            
            guard !extendedPayloadDownloadTaskExistsFor(messageId) else {
                syncQueueOutput = .previousTaskExists
                return
            }
            
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                guard let message = try? InboxMessage.get(messageId: messageId, within: obvContext) else {
                    syncQueueOutput = .cannotFindMessageInDatabase
                    return
                }
                
                guard message.hasEncryptedExtendedMessagePayload else { return }
                guard message.extendedMessagePayload == nil else { return }
                
                guard message.extendedMessagePayloadKey != nil else {
                    syncQueueOutput = .extendedMessagePayloadKeyIsNotSet
                    return
                }
                
                guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: messageId.ownedCryptoIdentity) else {
                    syncQueueOutput = .serverSessionRequired
                    return
                }
                
                guard let token = serverSession.token else {
                    syncQueueOutput = .serverSessionRequired
                    return
                }
                
                // If we reach this point, we can download the encrypted extended message content
                
                let method = ObvServerDownloadMessageExtendedPayloadMethod(messageId: messageId, token: token, flowId: flowId)
                method.identityDelegate = delegateManager.identityDelegate

                let task: URLSessionDataTask
                do {
                    task = try method.dataTask(within: self.session)
                } catch let error {
                    syncQueueOutput = .failedToCreateTask(error: error)
                    return
                }
                
                insertExtendedPayloadDownloadTask(task, for: messageId, flowId: flowId)
                
                syncQueueOutput = .newTaskToRun(task: task)
            }
            
        } // End of localQueue.sync

        assert(syncQueueOutput != nil)
        guard syncQueueOutput != nil else {
            os_log("syncQueueOutput is nil", log: log, type: .fault)
            return
        }
        
        let queueForCallingDelegate = DispatchQueue(label: "MessagesCoordinator queue for calling delegate in downloadExtendedMessagePayload")

        switch syncQueueOutput! {
            
        case .previousTaskExists:
            os_log("A running task already exists for message %{public}@ with flow identifier %{public}@", log: log, type: .debug, messageId.debugDescription, flowId.debugDescription)
            
        case .serverSessionRequired:
            os_log("Server session required for identity %@ with flow identifier %{public}@", log: log, type: .debug, messageId.ownedCryptoIdentity.debugDescription, flowId.debugDescription)
            queueForCallingDelegate.async {
                do {
                    try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: messageId.ownedCryptoIdentity, flowId: flowId)
                } catch {
                    os_log("Call serverSessionRequired did fail", log: log, type: .fault)
                    assertionFailure()
                }
            }
            
        case .failedToCreateTask(error: let error):
            if let serverMethodError = error as? ObvServerMethodError {
                switch serverMethodError {
                case .ownedIdentityIsActiveCheckerDelegateIsNotSet:
                    os_log("Could not create task for ObvServerDownloadMessageExtendedPayloadMethod (ownedIdentityIsActiveCheckerDelegateIsNotSet): %{public}@", log: log, type: .error, serverMethodError.localizedDescription)
                case .ownedIdentityIsNotActive:
                    os_log("Could not create task for ObvServerDownloadMessageExtendedPayloadMethod (ownedIdentityIsNotActive): %{public}@", log: log, type: .error, serverMethodError.localizedDescription)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: messageId.ownedCryptoIdentity, flowId: flowId)
                    }
                    return
                }
            } else {
                os_log("Could not create task for ObvServerDownloadMessageExtendedPayloadMethod: %{public}@", log: log, type: .error, error.localizedDescription)
            }
            return
            
        case .newTaskToRun(task: let task):
            os_log("New task to run for identity %@ with flow identifier %{public}@", log: log, type: .debug, messageId.ownedCryptoIdentity.debugDescription, flowId.debugDescription)
            task.resume()
            
        case .cannotFindMessageInDatabase:
            os_log("Could not find message in database -> Cannot download encrypted extended message payload for identity %@ with flow identifier %{public}@. This also happens if the attachment was a duplicate of a previous attachment at the app level, in which the app immediately requested to delete the InboxMessage (reason why we cannot find it).", log: log, type: .error, messageId.ownedCryptoIdentity.debugDescription, flowId.debugDescription)

        case .extendedMessagePayloadKeyIsNotSet:
            os_log("Could not find the extended message payload decryption key -> We do NOT download the encrypted extended message payload for identity %@ with flow identifier %{public}@", log: log, type: .fault, messageId.ownedCryptoIdentity.debugDescription, flowId.debugDescription)
            assertionFailure()
        }

    }

}


// MARK: - URLSessionDataDelegate

extension MessagesCoordinator: URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if getInfoFor(dataTask) != nil {
            accumulate(data, forTask: dataTask)
        } else if getInfoForExtendedPayloadDownloadTask(dataTask) != nil {
            accumulateExtendedPayloadData(data, forTask: dataTask)
        }
    }
    
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        
        assert(!Thread.isMainThread)
        
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
            
        let queueForCallingDelegate = DispatchQueue(label: "MessagesCoordinator queue for calling delegate in urlSession didCompleteWithError")

        if let (ownedIdentity, deviceUid, flowId, responseData) = getInfoFor(task) {
            
            // Case 1: the task is downloading messages and listing attachments
            
            os_log("🌊 Got infos from task. The flow is %{public}@", log: log, type: .debug, flowId.debugDescription)
                        
            guard error == nil else {
                os_log("The DownloadMessagesAndListAttachmentsCoordinator task failed for identity %{public}@: %{public}@", log: log, type: .error, ownedIdentity.debugDescription, error!.localizedDescription)
                _ = removeInfoFor(task)
                queueForCallingDelegate.async {
                    delegateManager.networkFetchFlowDelegate.downloadingMessagesAndListingAttachmentFailed(for: ownedIdentity, andDeviceUid: deviceUid, flowId: flowId)
                }
                return
            }
            
            // If we reach this point, the data task did complete without error
            
            guard let (status, timestampFromServer, returnedValues) = ObvServerDownloadMessagesAndListAttachmentsMethod.parseObvServerResponse(responseData: responseData, using: log) else {
                os_log("Could not parse the server response for the ObvServerDownloadMessagesAndListAttachmentsMethod for identity %{public}@", log: log, type: .fault, ownedIdentity.debugDescription)
                _ = removeInfoFor(task)
                queueForCallingDelegate.async {
                    delegateManager.networkFetchFlowDelegate.downloadingMessagesAndListingAttachmentFailed(for: ownedIdentity, andDeviceUid: deviceUid, flowId: flowId)
                }
                return
            }
            
            switch status {
            case .ok:
                let listOfMessageAndAttachmentsOnServer = returnedValues!
                let downloadTimestampFromServer = timestampFromServer!
                let localDownloadTimestamp = Date()
                
                localQueue.sync {
                    
                    let idsOfNewMessages: [MessageIdentifier]
                    do {
                        idsOfNewMessages = try saveMessagesAndAttachmentsFromServer(listOfMessageAndAttachmentsOnServer,
                                                                                    downloadTimestampFromServer: downloadTimestampFromServer,
                                                                                    localDownloadTimestamp: localDownloadTimestamp,
                                                                                    ownedIdentity: ownedIdentity,
                                                                                    flowId: flowId)
                    } catch {
                        os_log("Could not save the messages and list of attachments", log: log, type: .fault)
                        _ = removeInfoFor(task)
                        queueForCallingDelegate.async {
                            delegateManager.networkFetchFlowDelegate.downloadingMessagesAndListingAttachmentFailed(for: ownedIdentity, andDeviceUid: deviceUid, flowId: flowId)
                        }
                        return
                    }
                    
                    os_log("🌊 We successfully downloaded %d messages (%d are new) for identity %@ within flow %{public}@", log: log, type: .debug, listOfMessageAndAttachmentsOnServer.count, idsOfNewMessages.count, ownedIdentity.debugDescription, flowId.debugDescription)
                    _ = removeInfoFor(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.downloadingMessagesAndListingAttachmentWasPerformed(for: ownedIdentity, andDeviceUid: deviceUid, flowId: flowId)
                    }
                    
                }
                
                return
                
            case .invalidSession:
                os_log("The session is invalid", log: log, type: .error)
                
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
                
            case .deviceIsNotRegistered:
                _ = removeInfoFor(task)
                os_log("This device is not registered", log: log, type: .error)
                queueForCallingDelegate.async {
                    delegateManager.networkFetchFlowDelegate.serverReportedThatThisDeviceIsNotRegistered(ownedIdentity: ownedIdentity, flowId: flowId)
                }
                
                
            case .generalError:
                os_log("Server reported general error during the ObvServerListMessagesAndAttachmentsMethod download task for identity %@", log: log, type: .fault, ownedIdentity.debugDescription)
                _ = removeInfoFor(task)
                queueForCallingDelegate.async {
                    delegateManager.networkFetchFlowDelegate.downloadingMessagesAndListingAttachmentFailed(for: ownedIdentity, andDeviceUid: deviceUid, flowId: flowId)
                }
                return
            }
            
            
        } else if let (messageId, flowId, responseData) = getInfoForExtendedPayloadDownloadTask(task) {

            // Case 2: the task is downloading an encrypted extended message payload

            os_log("🌊 Got infos from task downloading extended message payload. The flow is %{public}@", log: log, type: .debug, flowId.debugDescription)
                        
            guard error == nil else {
                os_log("The ObvServerDownloadMessageExtendedPayloadMethod task failed for message %{public}@: %@", log: log, type: .error, messageId.debugDescription, error!.localizedDescription)
                _ = removeInfoFor(task)
                try? removeExtendedMessagePayload(messageId: messageId, flowId: flowId)
                queueForCallingDelegate.async {
                    delegateManager.networkFetchFlowDelegate.downloadingMessageExtendedPayloadFailed(messageId: messageId, flowId: flowId)
                }
                return
            }

            // If we reach this point, the data task did complete without error
            
            guard let (status, encryptedExtendedMessagePayload) = ObvServerDownloadMessageExtendedPayloadMethod.parseObvServerResponse(responseData: responseData, using: log) else {
                os_log("Could not parse the server response for the ObvServerDownloadMessageExtendedPayloadMethod for message %{public}@", log: log, type: .fault, messageId.debugDescription)
                _ = removeInfoFor(task)
                try? removeExtendedMessagePayload(messageId: messageId, flowId: flowId)
                queueForCallingDelegate.async {
                    delegateManager.networkFetchFlowDelegate.downloadingMessageExtendedPayloadFailed(messageId: messageId, flowId: flowId)
                }
                return
            }
            
            switch status {
            case .ok:
                
                let encryptedExtendedMessagePayload = encryptedExtendedMessagePayload!
                
                localQueue.sync {
                    
                    do {
                        try decryptAndSaveExtendedMessagePayload(messageId: messageId, encryptedExtendedMessagePayload: encryptedExtendedMessagePayload, flowId: flowId)
                    } catch {
                        os_log("Could not decrypt and save extended message payload: %{public}@", log: log, type: .fault, error.localizedDescription)
                        _ = removeInfoForExtendedPayloadDownloadTask(task)
                        try? removeExtendedMessagePayload(messageId: messageId, flowId: flowId)
                        queueForCallingDelegate.async {
                            delegateManager.networkFetchFlowDelegate.downloadingMessageExtendedPayloadFailed(messageId: messageId, flowId: flowId)
                        }
                        return
                    }
                    
                    _ = removeInfoForExtendedPayloadDownloadTask(task)
                    queueForCallingDelegate.async {
                        delegateManager.networkFetchFlowDelegate.downloadingMessageExtendedPayloadWasPerformed(messageId: messageId, flowId: flowId)
                    }

                }
                
                return

            case .invalidSession:
                
                os_log("The session is invalid", log: log, type: .error)
                
                contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                    guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: messageId.ownedCryptoIdentity) else {
                        _ = removeInfoForExtendedPayloadDownloadTask(task)
                        queueForCallingDelegate.async {
                            do {
                                try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: messageId.ownedCryptoIdentity, flowId: flowId)
                            } catch {
                                os_log("Call to serverSessionRequired did fail", log: log, type: .fault)
                                assertionFailure()
                            }
                        }
                        return
                    }
                    
                    guard let token = serverSession.token else {
                        _ = removeInfoForExtendedPayloadDownloadTask(task)
                        queueForCallingDelegate.async {
                            do {
                                try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: messageId.ownedCryptoIdentity, flowId: flowId)
                            } catch {
                                os_log("Call to serverSessionRequired did fail", log: log, type: .fault)
                                assertionFailure()
                            }
                        }
                        return
                    }
                    
                    _ = removeInfoForExtendedPayloadDownloadTask(task)
                    queueForCallingDelegate.async {
                        do {
                            try delegateManager.networkFetchFlowDelegate.serverSession(of: messageId.ownedCryptoIdentity, hasInvalidToken: token, flowId: flowId)
                        } catch {
                            os_log("Call to serverSession(of: ObvCryptoIdentity, hasInvalidToken: Data, flowId: FlowIdentifier) did fail", log: log, type: .fault)
                            assertionFailure()
                        }
                    }
                }
                
                return
                
            case .generalError:
                os_log("Server reported general error during the ObvServerDownloadMessageExtendedPayloadMethod download task for message %{public}@", log: log, type: .fault, messageId.debugDescription)
                _ = removeInfoForExtendedPayloadDownloadTask(task)
                try? removeExtendedMessagePayload(messageId: messageId, flowId: flowId)
                queueForCallingDelegate.async {
                    delegateManager.networkFetchFlowDelegate.downloadingMessageExtendedPayloadFailed(messageId: messageId, flowId: flowId)
                }
                return

            case .extendedContentUnavailable:
                os_log("Server reported that the message extended payload is not available for message %{public}@", log: log, type: .fault, messageId.debugDescription)
                _ = removeInfoForExtendedPayloadDownloadTask(task)
                try? removeExtendedMessagePayload(messageId: messageId, flowId: flowId)
                queueForCallingDelegate.async {
                    delegateManager.networkFetchFlowDelegate.downloadingMessageExtendedPayloadFailed(messageId: messageId, flowId: flowId)
                }
                return
            }

        }
        
    }
    
    
    /// When receiving an encrypted extended message payload from the server, we call this method to fetch the message from database, use the decryption key to decrypt the
    /// extended payload, and store the decrypted payload back to database
    private func decryptAndSaveExtendedMessagePayload(messageId: MessageIdentifier, encryptedExtendedMessagePayload: EncryptedData, flowId: FlowIdentifier) throws {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            throw makeError(message: "The Delegate Manager is not set")
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            throw makeError(message: "The context creator manager is not set")
        }

        try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in

            // In-memory changes (made here) trump external changes (typically made when marking the message for deletion)
            obvContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
            
            guard let message = try InboxMessage.get(messageId: messageId, within: obvContext) else {
                throw makeError(message: "We received an extended message payload for a message that cannot be found in DB")
            }
            
            guard let extendedMessagePayloadKey = message.extendedMessagePayloadKey else {
                throw makeError(message: "Could not find the decryption key for the encrypted message payload we just downloaded")
            }
            
            let authEnc = extendedMessagePayloadKey.algorithmImplementationByteId.algorithmImplementation
            let extendedMessagePayload = try authEnc.decrypt(encryptedExtendedMessagePayload, with: extendedMessagePayloadKey)

            message.setExtendedMessagePayload(to: extendedMessagePayload)
            
            try obvContext.save(logOnFailure: log)

        }
    }
    
    
    /// If we fail to download an extended message payload (or if we cannot decrypt it), we remove any information about this payload from the database
    private func removeExtendedMessagePayload(messageId: MessageIdentifier, flowId: FlowIdentifier) throws {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            throw makeError(message: "The Delegate Manager is not set")
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            throw makeError(message: "The context creator manager is not set")
        }

        os_log("Deleting an extended message payload...", log: log, type: .error)

        try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in

            // In-memory changes (made here) trump external changes (typically made when marking the messge for deletion)
            obvContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
            
            guard let message = try InboxMessage.get(messageId: messageId, within: obvContext) else {
                throw makeError(message: "We received an extended message payload for a message that cannot be found in DB")
            }

            message.deleteExtendedMessagePayload()
            
            try obvContext.save(logOnFailure: log)

        }

    }
    
    
    /// This method is used when receiving a list of messages (and their attachments) from the server. It saves each one in the `InboxMessage` database. It returns the `MessageIdentifier` of all the messages it manages to save.
    private func saveMessagesAndAttachmentsFromServer(_ listOfMessageAndAttachmentsOnServer: [ObvServerDownloadMessagesAndListAttachmentsMethod.MessageAndAttachmentsOnServer], downloadTimestampFromServer: Date, localDownloadTimestamp: Date, ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) throws -> [MessageIdentifier] {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            throw makeError(message: "The Delegate Manager is not set")
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            throw makeError(message: "The context creator manager is not set")
        }

        var idsOfNewMessages = [MessageIdentifier]()

        try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            
            for messageAndAttachmentsOnServer in listOfMessageAndAttachmentsOnServer {
                
                let messageId = MessageIdentifier(ownedCryptoIdentity: ownedIdentity, uid: messageAndAttachmentsOnServer.messageUidFromServer)
                
                // Check that the message does not already exist in DB
                do {
                    guard try InboxMessage.get(messageId: messageId, within: obvContext) == nil else { continue }
                } catch {
                    assertionFailure()
                    continue
                }
                
                // Check that the message was not recently deleted from DB
                do {
                    guard try PendingDeleteFromServer.get(messageId: messageId, within: obvContext) == nil else { continue }
                } catch {
                    assertionFailure()
                    continue
                }
                
                // If we reach this point, the message is actually new
                
                let message: InboxMessage
                do {
                    os_log("Trying yo insert InboxMessage for identity %{public}@: %{public}@", log: log, type: .info, ownedIdentity.debugDescription, messageId.debugDescription)
                    message = try InboxMessage(
                        messageId: messageId,
                        encryptedContent: messageAndAttachmentsOnServer.encryptedContent,
                        hasEncryptedExtendedMessagePayload: messageAndAttachmentsOnServer.hasEncryptedExtendedMessagePayload,
                        wrappedKey: messageAndAttachmentsOnServer.wrappedKey,
                        messageUploadTimestampFromServer: messageAndAttachmentsOnServer.messageUploadTimestampFromServer,
                        downloadTimestampFromServer: downloadTimestampFromServer,
                        localDownloadTimestamp: localDownloadTimestamp,
                        within: obvContext)
                } catch let error {
                    guard let inboxMessageError = error as? InboxMessage.InternalError else {
                        os_log("Could not insert message in DB for identity %{public}@ for some unknown reason.", log: log, type: .fault, ownedIdentity.debugDescription)
                        assertionFailure()
                        continue
                    }
                    switch inboxMessageError {
                    case .aMessageWithTheSameMessageIdAlreadyExists:
                        os_log("Could not insert message in DB for identity %{public}@: %{public}@", log: log, type: .fault, ownedIdentity.debugDescription, inboxMessageError.localizedDescription)
                        assertionFailure()
                        continue
                    case .tryingToInsertAMessageThatWasAlreadyDeleted:
                        // This can happen
                        os_log("Could not insert message in DB for identity %{public}@: %{public}@", log: log, type: .error, ownedIdentity.debugDescription, inboxMessageError.localizedDescription)
                        continue
                    }
                }
                for attachmentOnServer in messageAndAttachmentsOnServer.attachments {
                    guard let inboxAttachment = try? InboxAttachment(message: message,
                                                                     attachmentNumber: attachmentOnServer.attachmentNumber,
                                                                     byteCountToDownload: attachmentOnServer.expectedLength,
                                                                     expectedChunkLength: attachmentOnServer.expectedChunkLength,
                                                                     within: obvContext)
                    else {
                        os_log("Could not insert attachment in DB for identity %{public}@", log: log, type: .fault, ownedIdentity.debugDescription)
                        continue
                    }
                    
                    // For now, we make sure that none of the signed URL is nil before setting them on the new InboxAttachment. This may change in the future.
                    // If one of the signed URL is nil, we mark the attachment for deletion.
                    if let chunkDownloadSignedUrls = attachmentOnServer.chunkDownloadPrivateUrls as? [URL], !chunkDownloadSignedUrls.isEmpty {
                        do {
                            try inboxAttachment.setChunksSignedURLs(chunkDownloadSignedUrls)
                        } catch {
                            os_log("We could not set the chunk download private URLs. We mark it for deletion", log: log, type: .error)
                            inboxAttachment.markForDeletion()
                        }
                    } else {
                        os_log("Attachment %{public}@ has a nil chunk URL. It was cancelled by the server.", log: log, type: .info, inboxAttachment.debugDescription)
                        inboxAttachment.markAsCancelledByServer()
                    }
                    
                }
                idsOfNewMessages.append(messageId)
                
            }

            try obvContext.save(logOnFailure: log)
            
        }
        
        return idsOfNewMessages
    }
}
