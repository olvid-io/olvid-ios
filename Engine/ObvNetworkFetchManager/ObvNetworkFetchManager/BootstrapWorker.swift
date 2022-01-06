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
import ObvTypes
import ObvMetaManager
import OlvidUtils

final class BootstrapWorker {
    
    private let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
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
    private let inbox: URL
    private var engineWasJustInitialized = true

    weak var delegateManager: ObvNetworkFetchDelegateManager?

    init(inbox: URL) {
        self.inbox = inbox
    }

    func finalizeInitialization(flowId: FlowIdentifier) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        os_log("FetchManager: Finalizing initialization", log: log, type: .info)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The Context Creator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        internalQueue.addOperation { [weak self] in
            self?.deleteAllRegisteredPushNotifications(flowId: flowId, log: log, contextCreator: contextCreator)
            self?.deleteOrphanedDatabaseObjects(flowId: flowId, log: log, contextCreator: contextCreator)
            self?.reschedulePendingDeleteFromServers(flowId: flowId, log: log, delegateManager: delegateManager, contextCreator: contextCreator)
            delegateManager.downloadAttachmentChunksDelegate.cleanExistingOutboxAttachmentSessions(flowId: flowId)
            delegateManager.wellKnownCacheDelegate.initializateCache(flowId: flowId)
        }

    }

    func applicationDidStartRunning() {

        let flowId = FlowIdentifier()
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        os_log("FetchManager: application did become active", log: log, type: .info)
        guard let contextCreator = delegateManager.contextCreator else {
            
            os_log("The Context Creator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        if engineWasJustInitialized {
            engineWasJustInitialized = false
            internalQueue.addOperation { [weak self] in
                // We cannot call this method in the finalizeInitialization method because the generated notifications would not be received by the app
                self?.rescheduleAllInboxMessagesAndAttachments(flowId: flowId, log: log, contextCreator: contextCreator, delegateManager: delegateManager)
            }
        }
        
        internalQueue.addOperation { [weak self] in
            self?.deleteOrphanedDatabaseObjects(flowId: flowId, log: log, contextCreator: contextCreator)
            self?.cleanInboxFromOrphanedMessagesDirectories(flowId: flowId)
            self?.cleanUserData(flowId: flowId)
        }
        
    }

    /// This method wraps all the calls to the methods allowing to clean the various databases of this manager, by deleting
    /// the objects that should have been cascade deleted but that, for some reason, still exist. This method is called on init,
    /// but also each time the app becomes active.
    private func deleteOrphanedDatabaseObjects(flowId: FlowIdentifier, log: OSLog, contextCreator: ObvCreateContextDelegate) {
        deleteOrphanedInboxAttachmentChunk(flowId: flowId, log: log, contextCreator: contextCreator)
        deleteOrphanedInboxAttachments(flowId: flowId, log: log, contextCreator: contextCreator)
        deleteOrphanedInboxAttachmentSessions(flowId: flowId, log: log, contextCreator: contextCreator)
    }

}

// MARK: - On init (finalizing the initialization)

extension BootstrapWorker {
    
    private func deleteOrphanedInboxAttachmentChunk(flowId: FlowIdentifier, log: OSLog, contextCreator: ObvCreateContextDelegate) {
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                try InboxAttachmentChunk.deleteAllOrphaned(within: obvContext)
            } catch {
                os_log("Could not delete orphaned inbox attachments chunks during bootstrap: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
    }
    
    private func deleteOrphanedInboxAttachments(flowId: FlowIdentifier, log: OSLog, contextCreator: ObvCreateContextDelegate) {
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                try InboxAttachment.deleteAllOrphaned(within: obvContext)
            } catch {
                os_log("Could not delete orphaned inbox attachments during bootstrap: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
    }
    
    private func deleteOrphanedInboxAttachmentSessions(flowId: FlowIdentifier, log: OSLog, contextCreator: ObvCreateContextDelegate) {
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                try InboxAttachmentSession.deleteAllOrphaned(within: obvContext)
            } catch {
                os_log("Could not delete orphaned inbox attachments sessions during bootstrap: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
    }
    
    
    private func reschedulePendingDeleteFromServers(flowId: FlowIdentifier, log: OSLog, delegateManager: ObvNetworkFetchDelegateManager, contextCreator: ObvCreateContextDelegate) {
        
        var messageIdsWithPendingDeletes = [MessageIdentifier]()
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in

            let allPendingDeleteFromServer: [PendingDeleteFromServer]
            do {
                allPendingDeleteFromServer = try PendingDeleteFromServer.getAll(within: obvContext)
            } catch {
                os_log("Could not get all PendingDeleteFromServer during bootstrap: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            
            messageIdsWithPendingDeletes = allPendingDeleteFromServer.map({ $0.messageId })
                        
        }
        
        for messageId in messageIdsWithPendingDeletes {
            delegateManager.networkFetchFlowDelegate.newPendingDeleteToProcessForMessage(messageId: messageId, flowId: flowId)
        }

    }
    
    
    /// This method is called on init and reschedules all messages by calling the newOutboxMessage() method on the flow coordinator.
    private func rescheduleAllInboxMessagesAndAttachments(flowId: FlowIdentifier, log: OSLog, contextCreator: ObvCreateContextDelegate, delegateManager: ObvNetworkFetchDelegateManager) {
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in

            var messages: [InboxMessage]
            do {
                messages = try InboxMessage.getAll(within: obvContext)
            } catch {
                os_log("Could not get inbox messages", log: log, type: .fault)
                assertionFailure()
                return
            }

            os_log("Number of InboxMessage instances found during bootstrap: %d", log: log, type: .info, messages.count)
            
            // Processs the messages that can be deleted
            do {
                let messagesToDelete = messages.filter({ $0.canBeDeleted })
                messages.removeAll(where: { messagesToDelete.contains($0) })
                for msg in messagesToDelete {
                    try? delegateManager.messagesDelegate.processMarkForDeletionForMessageAndAttachmentsAndCreatePendingDeleteFromServer(messageId: msg.messageId, flowId: flowId)
                }
            }
            
            // Process the messages that are not yet processed.

            do {
                let messagesToProcess = messages.filter({ !$0.isProcessed })
                messages.removeAll(where: { messagesToProcess.contains($0) })
                let messageIds = messagesToProcess.map({ $0.messageId })
                delegateManager.networkFetchFlowDelegate.processUnprocessedMessages(messageIds: messageIds, flowId: flowId)
            }
            
            // The remaining messages are already process.
            
            do {
                for msg in messages {
                    for attachment in msg.attachments {
                        switch attachment.status {
                        case .paused:
                            break
                        case .resumeRequested:
                            delegateManager.downloadAttachmentChunksDelegate.resumeAttachmentDownloadIfResumeIsRequested(attachmentId: attachment.attachmentId, flowId: flowId)
                        case .downloaded:
                            delegateManager.networkFetchFlowDelegate.downloadedAttachment(attachmentId: attachment.attachmentId, flowId: flowId)
                        case .cancelledByServer:
                            delegateManager.networkFetchFlowDelegate.attachmentWasCancelledByServer(attachmentId: attachment.attachmentId, flowId: flowId)
                        case .markedForDeletion:
                            continue
                        }
                    }
                    delegateManager.networkFetchFlowDelegate.messagePayloadAndFromIdentityWereSet(messageId: msg.messageId, attachmentIds: msg.attachmentIds, hasEncryptedExtendedMessagePayload: msg.hasEncryptedExtendedMessagePayload, flowId: flowId)
                }
            }
            
        }
    }

    
    /// This method is called at launch. It deletes any previously registered push notification. We expect the app to register to push notifications at each launch, *after* this bootstrap.
    private func deleteAllRegisteredPushNotifications(flowId: FlowIdentifier, log: OSLog, contextCreator: ObvCreateContextDelegate) {
        
        os_log("Bootstraping RegisteredPushNotifications: We will delete all previous RegisteredPushNotification", log: log, type: .info)

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            do {
                try RegisteredPushNotification.deleteAll(within: obvContext)
            } catch let error {
                os_log("Could not delete old registered push notifications at bootstrap: %{public}@", log: log, type: .fault, error.localizedDescription)
            }
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not save context. The previous RegisteredPushNotification were *not* deleted: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
            
        }
        
        os_log("Bootstraping RegisteredPushNotifications finished. All previous RegisteredPushNotification were deleted.", log: log, type: .info)

    }

}


// MARK: - Bootstrapping when application did become active

extension BootstrapWorker {
    
    /// The inbox contains one directory per message (if it has attachments).
    /// This directory was created when setting the "from identity", the message payload, etc. within the `ObvNetworkFetchManagerImplementation`
    /// (which eventually calls the `createAttachmentsDirectoryIfRequired` method within `InboxMessage`).
    /// The name of the directory is the sha256 of the message identifier.
    /// This method lists all the directories, filters out directories that do no have an appropriate name,
    /// and deletes all the directories that do not have an appropriate `InboxMessage` object in database.
    /// We do not deal with the encrypted chunks that are managed by the URLSession.
    private func cleanInboxFromOrphanedMessagesDirectories(flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
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
        let directoriesInInbox: [URL]
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
            directoriesInInbox = try urls.filter({ (url) in
                let values = try url.resourceValues(forKeys: Set(keys))
                guard let isDirectory = values.isDirectory else { assertionFailure(); return false }
                return isDirectory
            })
        } catch {
            os_log("Could not clean inbox: %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }
        
        let inbox = self.inbox
        
        let messageDirectories: Set<URL>
        do {
            messageDirectories = Set(try directoriesInInbox.filter { (url) in
                let values = try url.resourceValues(forKeys: Set(keys))
                guard let name = values.name else { assertionFailure(); return false }
                guard name.count == 64 else { assertionFailure("the inbox is supposed to only contain direcotires for messages, which name is the sha256 of the message identifier"); return true }
                return true
            })
        } catch {
            os_log("Could not clean inbox: %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }
        
        guard !messageDirectories.isEmpty else { return }
               
        var messageDirectoriesToDelete = Set<URL>()
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            let existingMessages: [InboxMessage]
            do {
                existingMessages = try InboxMessage.getAll(within: obvContext)
            } catch {
                os_log("Could not clean outbox: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }

            let messageDirectoriesToKeep: Set<URL> = Set(existingMessages.map({ $0.getAttachmentDirectory(withinInbox: inbox) }) )
            
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

    private func cleanUserData(flowId: FlowIdentifier) {
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        delegateManager.serverUserDataDelegate.cleanUserData(flowId: flowId)
    }

    
}
