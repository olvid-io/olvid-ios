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
import ObvTypes
import ObvMetaManager
import ObvCrypto
import OlvidUtils


final class BootstrapWorker {
    
    private let defaultLogSubsystem = ObvNetworkSendDelegateManager.defaultLogSubsystem
    private let logCategory = "BootstrapWorker"
    private let internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "BootstrapWorker internal Queue"
        return queue
    }()
    private let queueForPostingNotifications: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 5
        queue.name = "Operation Queue for posting certain notifications from the BootstrapWorker"
        return queue
    }()

    private var observationTokens = [NSObjectProtocol]()
    private let appType: AppType
    private let outbox: URL

    weak var delegateManager: ObvNetworkSendDelegateManager?
    
    /// Only required under iOS 12, not needed under iOS 13.
    /// This Set stores the hashValues of the transactions replayed when receiving a
    /// NSPersistentStoreRemoteChange notification.
    private var transactionsAlreadyReplayedWithinPersistentStoreRemoteChange = Set<Int>()
    
    /// This timer is only used under iOS 11, within the pollRemoteChanges(flowId: FlowIdentifier) method.
    private var timer: Timer?

    
    init(appType: AppType, outbox: URL) {
        self.appType = appType
        self.outbox = outbox
    }
    
    
    func finalizeInitialization(flowId: FlowIdentifier) {

        guard appType == .mainApp else { return }
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        os_log("SendManager: Finalizing initialization", log: log, type: .info)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The Context Creator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        internalQueue.addOperation { [weak self] in
            self?.deleteOrphanedDatabaseObjects(flowId: flowId, log: log, contextCreator: contextCreator)
            delegateManager.uploadAttachmentChunksDelegate.cleanExistingOutboxAttachmentSessionsCreatedBy(.mainApp, flowId: flowId)
            self?.rescheduleAllOutboxMessagesAndAttachments(flowId: flowId, log: log, contextCreator: contextCreator, delegateManager: delegateManager)
            // 2020-06-29 Added this to make sure we always send attachments
            delegateManager.uploadAttachmentChunksDelegate.cleanExistingOutboxAttachmentSessionsCreatedBy(.shareExtension, flowId: flowId)
        }

    }
    
    
    func applicationDidStartRunning() {

        guard appType == .mainApp else { return }

        let flowId = FlowIdentifier()
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        os_log("SendManager: application did become active", log: log, type: .info)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The Context Creator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        internalQueue.addOperation { [weak self] in
            self?.deleteOrphanedDatabaseObjects(flowId: flowId, log: log, contextCreator: contextCreator)
            self?.cleanOutboxFromOrphanedMessagesDirectories(flowId: flowId)
            delegateManager.uploadAttachmentChunksDelegate.resumeMissingAttachmentUploads(flowId: flowId)
            delegateManager.uploadAttachmentChunksDelegate.queryServerOnSessionsTasksCreatedByShareExtension(flowId: flowId)
        }
        
    }
    
    
    /// This method wraps all the calls to the methods allowing to clean the various databases of this manager, by deleting
    /// the objects that should have been cascade deleted but that, for some reason, still exist. This method is called on init,
    /// but also each time the app becomes active.
    private func deleteOrphanedDatabaseObjects(flowId: FlowIdentifier, log: OSLog, contextCreator: ObvCreateContextDelegate) {
        guard appType == .mainApp else { return }
        deleteOrphanedOutboxAttachmentChunk(flowId: flowId, log: log, contextCreator: contextCreator)
        deleteOrphanedAttachments(flowId: flowId, log: log, contextCreator: contextCreator)
        deleteAllOrphanedOutboxAttachmentSession(flowId: flowId, log: log, contextCreator: contextCreator)
        deleteOrphanedMessageHeaders(flowId: flowId, log: log, contextCreator: contextCreator)
    }
    
    
    func replayTransactionsHistory(transactions: [NSPersistentHistoryTransaction], within obvContext: ObvContext) {
        guard appType == .mainApp else { return }
        replayTransactionsHistoryRelatedToOutboxMessageDeletion(within: obvContext)
        for transaction in transactions.reversed() {
            guard let changes = transaction.changes else { continue }
            replayTransactionsHistoryRelatedToOutboxMessageUpdate(changes: changes, within: obvContext)
        }
    }
        
}


// MARK: - On init (finalizing the initialization)

extension BootstrapWorker {
    

    /// This method invalidate and cancels the URLSessions associated with an existing `OutboxAttachmentSession` object *if* it was created by the app type passed within the parameters. It then deletes all these `OutboxAttachmentSession` objects.
    ///
    /// When the `appType` is `mainApp`, this shall only be done when finalizing the initialization of the send manager, so as to start from a clean state, no matter what happened.
    /// It will be up to subsequent bootstrap methods to requeue any outstanding attachment.
    private func invalidateAndCancelAndDeleteOutboxAttachmentSessionsCreatedBy(_ appTypeCreator: AppType, flowId: FlowIdentifier, log: OSLog, contextCreator: ObvCreateContextDelegate) {
        
        guard appType == .mainApp else { assertionFailure(); return }
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            let attachmentSessions: [OutboxAttachmentSession]
            do {
                attachmentSessions = try OutboxAttachmentSession.getAllCreatedByAppType(appTypeCreator, within: obvContext)
            } catch {
                os_log("Could not invalidate and cancel old OutboxAttachmentSessions: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
            
            for attachmentSession in attachmentSessions {
                let configuration = URLSessionConfiguration.background(withIdentifier: attachmentSession.sessionIdentifier)
                let urlSession = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
                urlSession.invalidateAndCancel()
                obvContext.delete(attachmentSession)
            }

            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not invalidate and cancel old OutboxAttachmentSessions: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
        }
        
    }
    
    
    /// This method is called on init and reschedules all messages by calling the newOutboxMessage() method on the flow coordinator.
    private func rescheduleAllOutboxMessagesAndAttachments(flowId: FlowIdentifier, log: OSLog, contextCreator: ObvCreateContextDelegate, delegateManager: ObvNetworkSendDelegateManager) {
        
        guard appType == .mainApp else { assertionFailure(); return }

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in

            let outboxMessageIdentifiers: [MessageIdentifier]
            do {
                let outboxMessages = try OutboxMessage.getAll(delegateManager: delegateManager, within: obvContext)
                outboxMessageIdentifiers = outboxMessages.map { $0.messageId }
            } catch {
                os_log("Could not reschedule existing OutboxMessages", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            for messageId in outboxMessageIdentifiers {
                delegateManager.networkSendFlowDelegate.newOutboxMessage(messageId: messageId, flowId: flowId)
            }
            
        }
    }

}

// MARK: - Replaying transactions

extension BootstrapWorker {
        
    private func process(externalTransactions: [NSPersistentHistoryTransaction]) {
        
    }
    
    private func replayTransactionsHistoryRelatedToOutboxMessageUpdate(changes: [NSPersistentHistoryChange], within obvContext: ObvContext) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set (6)", log: log, type: .fault)
            return
        }

        // We only keep the changes for OutboxMessages, that are updates
        let relevantChanges = changes.filter { $0.changedObjectID.entity.name == OutboxMessage.entity().name && $0.changeType == .update }
        
        // Used to ensure we only post the relevant notification once
        var notificationPosted = Set<MessageIdentifier>()
        
        for change in relevantChanges {
            guard let updatedProperties = change.updatedProperties else { continue }
            let updatedPropertiesNames = updatedProperties.map { $0.name }
            guard updatedPropertiesNames.contains(OutboxMessage.timestampFromServerKey) else { continue }
            // We look for the message. If it does not exist, we do not notify the app. It will eventually be notified when we will deal with the change containing the deletion of the message.
            guard let outboxMessage = try? obvContext.existingObject(with: change.changedObjectID) as? OutboxMessage else { continue }
            guard let timestampFromServer = outboxMessage.timestampFromServer else { assertionFailure(); continue }
            guard !notificationPosted.contains(outboxMessage.messageId) else { continue }
            notificationPosted.insert(outboxMessage.messageId)
            os_log("Sending a outboxMessageWasUploaded notification (bootstraped update transaction) for messageId: %{public}@", log: log, type: .info, outboxMessage.messageId.debugDescription)
            
            ObvNetworkPostNotificationNew.outboxMessageWasUploaded(messageId: outboxMessage.messageId, timestampFromServer: timestampFromServer, isAppMessageWithUserContent: outboxMessage.isAppMessageWithUserContent, isVoipMessage: outboxMessage.isVoipMessage, flowId: obvContext.flowId)
                .postOnOperationQueue(operationQueue: queueForPostingNotifications, within: notificationDelegate)

        }
        
    }
    
    /// This method simply fetch all entries of the DeletedOutboxMessage database so as to send appropriate notifications for all these messages.
    /// We are not leveraging Core Data's Persistent Transaction History since there is a bug in Xcode 11.5 (11E608c) preventing any kind of heavyweight
    /// migration when using tombstones.
    private func replayTransactionsHistoryRelatedToOutboxMessageDeletion(within obvContext: ObvContext) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set (6)", log: log, type: .fault)
            return
        }

        let deletedMessages: [DeletedOutboxMessage]
        do {
            deletedMessages = try DeletedOutboxMessage.getAll(delegateManager: delegateManager, within: obvContext)
        } catch {
            os_log("Could not get all deleted outbox messages", log: log, type: .fault)
            assertionFailure()
            return
        }

        let messageIdsAndTimestampsFromServer = deletedMessages.map() { ($0.messageId, $0.timestampFromServer) }
        ObvNetworkPostNotificationNew.outboxMessagesAndAllTheirAttachmentsWereAcknowledged(messageIdsAndTimestampsFromServer: messageIdsAndTimestampsFromServer, flowId: obvContext.flowId)
            .postOnOperationQueue(operationQueue: queueForPostingNotifications, within: notificationDelegate)

    }
    
    
    public func deleteHistoryConcerningTheAcknowledgementOfOutboxMessages(messageIdentifiers: [MessageIdentifier], flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The Context Creator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        contextCreator.performBackgroundTaskAndWait(flowId: flowId, { (obvContext) in
            
            do {
                try DeletedOutboxMessage.batchDelete(messageIds: messageIdentifiers, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not batch delete DeletedOutboxMessages: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
            
        })
        
    }
    
}


// MARK: - Bootstrapping when application did become active

extension BootstrapWorker {
    
    private func rePostOutboxMessageWasUploadedNotifications(flowId: FlowIdentifier, log: OSLog, delegateManager: ObvNetworkSendDelegateManager) {
        
        guard let notificationDelegate = delegateManager.notificationDelegate else { assertionFailure(); return }
        
        delegateManager.contextCreator?.performBackgroundTaskAndWait(flowId: flowId, { (obvContext) in
            let uploadedMessages: [OutboxMessage]
            do {
                uploadedMessages = try OutboxMessage.getAllUploaded(delegateManager: delegateManager, within: obvContext)
            } catch {
                os_log("Could not get all uploaded messages", log: log, type: .fault)
                assertionFailure()
                return
            }
            let queue = DispatchQueue(label: "Queue for posting an outboxMessageWasUploaded notification (1)")
            for msg in uploadedMessages {
                guard let timestampFromServer = msg.timestampFromServer else { assertionFailure(); continue }
                let notification = ObvNetworkPostNotificationNew.outboxMessageWasUploaded(messageId: msg.messageId,
                                                                                          timestampFromServer: timestampFromServer,
                                                                                          isAppMessageWithUserContent: msg.isAppMessageWithUserContent,
                                                                                          isVoipMessage: msg.isVoipMessage,
                                                                                          flowId: flowId)
                notification.postOnDispatchQueue(dispatchQueue: queue, within: notificationDelegate)
            }
        })
        
    }

    
    /// The outbox contains one directory per message (if it has attachments).
    /// This directory was created in the `EncryptAttachmentChunkOperation`. The name of the directory is the sha256
    /// of the message identifier. This method lists all the directories, filters out directories that do no have an appropriate name,
    /// and deletes all the directories that do not have an appropriate OutboxMessage object in database. Note that the individual
    /// chunks were deleted when acknowledging the corresponding `OutboxAttachmentChunk` object.
    private func cleanOutboxFromOrphanedMessagesDirectories(flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The Context Creator is not set", log: log, type: .fault)
            return
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        let directoriesInOutbox: [URL]
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
            directoriesInOutbox = try urls.filter({ (url) in
                let values = try url.resourceValues(forKeys: Set(keys))
                guard let isDirectory = values.isDirectory else { assertionFailure(); return false }
                return isDirectory
            })
        } catch {
            os_log("Could not clean outbox: %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }
        
        let outbox = self.outbox
        
        let messageDirectories: Set<URL>
        do {
            messageDirectories = Set(try directoriesInOutbox.filter { (url) in
                let values = try url.resourceValues(forKeys: Set(keys))
                guard let name = values.name else { assertionFailure(); return false }
                guard name.count == 64 else { assertionFailure("the outbox is supposed to only contain direcotires for messages, which name is the sha256 of the message identifier"); return true }
                return true
            })
        } catch {
            os_log("Could not clean outbox: %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }
        
        guard !messageDirectories.isEmpty else { return }
               
        var messageDirectoriesToDelete = Set<URL>()
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            let existingMessageIds: Set<MessageIdentifier>
            do {
                let existingMessages = try OutboxMessage.getAll(delegateManager: delegateManager, within: obvContext)
                existingMessageIds = Set(existingMessages.map({ $0.messageId }))
            } catch {
                os_log("Could not clean outbox: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }

            let messageDirectoriesToKeep: Set<URL> = Set(existingMessageIds.map { outbox.appendingPathComponent($0.directoryName, isDirectory: true) })
            
            messageDirectoriesToDelete = messageDirectories.subtracting(messageDirectoriesToKeep)
            
        }
        
        for url in messageDirectoriesToDelete {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                os_log("Could not properly clean the outbox", log: log, type: .error)
            }

        }
        
    }

    /// This method invalidate and cancels the URLSessions associated with an existing `OutboxAttachmentSession` object that does *not* have an associated attachment. It then deletes all these objects.
    ///
    /// It is very unlikely that such `OutboxAttachmentSession` even exist, since they are created when an attachment requires them, and cascaded deleted when this attachment is deleted.
    /// Yet, no database mechanism enforces that the to-one relationship to be non-nil, so we clean these `OutboxAttachmentSession` objects each time the app becomes active.
    private func deleteAllOrphanedOutboxAttachmentSession(flowId: FlowIdentifier, log: OSLog, contextCreator: ObvCreateContextDelegate) {
        guard appType == .mainApp else { assertionFailure(); return }
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                let sessionIdentifiers = try OutboxAttachmentSession.getSessionIdentifiersOfAllOrphanedOutboxAttachmentSession(within: obvContext)
                guard !sessionIdentifiers.isEmpty else { return }
                for sessionIdentifier in sessionIdentifiers {
                    let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
                    let urlSession = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
                    urlSession.invalidateAndCancel()
                }
                try OutboxAttachmentSession.deleteAllOrphaned(within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not batch delete all orphaned OutboxAttachmentSession", log: log, type: .fault)
            }
        }
        
    }
    
    
    /// This method deletes all the `OutboxAttachmentChunk` objects that don't have an associated `OutboxAttachment` object.
    ///
    /// It is very unlikely that such `OutboxAttachmentChunk` even exist, since they are created for a particular attachment,
    /// and cascaded deleted when this attachment is deleted. Yet, no database mechanism enforces that the to-one relationship
    /// to be non-nil, so we clean these `OutboxAttachmentChunk` objects each time the app becomes active.
    private func deleteOrphanedOutboxAttachmentChunk(flowId: FlowIdentifier, log: OSLog, contextCreator: ObvCreateContextDelegate) {
        guard appType == .mainApp else { assertionFailure(); return }
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            let chunks: [OutboxAttachmentChunk]
            do {
                chunks = try OutboxAttachmentChunk.getAllOrphanedOutboxAttachmentChunk(with: obvContext)
            } catch {
                os_log("Could not delete orphaned chunks (1)", log: log, type: .fault)
                return
            }
            for chunk in chunks {
                guard let encryptedChunkURL = chunk.encryptedChunkURL else { continue }
                guard FileManager.default.fileExists(atPath: encryptedChunkURL.path) else { continue }
                do {
                    try FileManager.default.removeItem(at: encryptedChunkURL)
                } catch {
                    os_log("Could not delete file of orphaned chunk", log: log, type: .fault)
                    // Continue anyway
                }
                obvContext.delete(chunk)
            }
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not delete orphaned chunks (2)", log: log, type: .fault)
                return
            }
        }
    }
    
    
    /// This method deletes all the `OutboxAttachment` objects that don't have an associated `OutboxMessage` object.
    ///
    /// It is very unlikely that such `OutboxAttachment` even exist, since they are created when a message requires them,
    /// and cascaded deleted when this message is deleted. Yet, no database mechanism enforces that the to-one relationship
    /// to be non-nil, so we clean these `OutboxAttachment` objects each time the app becomes active.
    private func deleteOrphanedAttachments(flowId: FlowIdentifier, log: OSLog, contextCreator: ObvCreateContextDelegate) {
        guard appType == .mainApp else { assertionFailure(); return }
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                try OutboxAttachment.deleteAllOrphanedAttachments(within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not delete orphaned attachments: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
        }
    }
    
    
    /// This method deletes all the `MessageHeader` objects that don't have an associated `OutboxMessage` object.
    ///
    /// It is very unlikely that such `MessageHeader` even exist, since they are created when a message requires them,
    /// and cascaded deleted when this message is deleted. Yet, no database mechanism enforces that the to-one relationship
    /// to be non-nil, so we clean these `MessageHeader` objects each time the app becomes active.
    private func deleteOrphanedMessageHeaders(flowId: FlowIdentifier, log: OSLog, contextCreator: ObvCreateContextDelegate) {
        guard appType == .mainApp else { assertionFailure(); return }
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                try MessageHeader.deleteAllOrphanedHeaders(within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not delete orphaned headers: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
        }
    }

    
}
