/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import OSLog
import ObvTypes
@preconcurrency import ObvMetaManager
import ObvCrypto
import OlvidUtils


final class BootstrapWorker: @unchecked Sendable {
    
    private let defaultLogSubsystem = ObvNetworkSendDelegateManager.defaultLogSubsystem
    private let logCategory = "BootstrapWorker"
    private let internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "BootstrapWorker internal Queue"
        return queue
    }()
    private let queueForPostingNotifications = DispatchQueue(label: "Queue for posting certain notifications from the BootstrapWorker")

    private let appType: AppType
    private let outbox: URL

    weak var delegateManager: ObvNetworkSendDelegateManager?
        

    init(appType: AppType, outbox: URL) {
        self.appType = appType
        self.outbox = outbox
    }
    
    func applicationWasInitializedButWasNeverOnScreen(flowId: FlowIdentifier) async {

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

        internalQueue.addOperation { [weak self] in
            delegateManager.uploadAttachmentChunksDelegate.cleanExistingOutboxAttachmentSessionsCreatedBy(.mainApp, flowId: flowId)
            self?.rescheduleAllOutboxMessagesAndAttachments(flowId: flowId, log: log, contextCreator: contextCreator, delegateManager: delegateManager)
            self?.pruneOldOutboxMessages(flowId: flowId, log: log, contextCreator: contextCreator, delegateManager: delegateManager)
            self?.rePostOutboxMessageWasUploadedNotificationsAndTryToDeleteUploadedMessages(flowId: flowId, log: log, delegateManager: delegateManager)
        }
    }

    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {

        guard appType == .mainApp else { return }

        let flowId = FlowIdentifier()
        
        guard let delegateManager = delegateManager else {
            let logger = Logger(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            logger.fault("The Delegate Manager is not set")
            assertionFailure()
            return
        }
        
        let logger = Logger(subsystem: delegateManager.logSubsystem, category: logCategory)
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            logger.fault("The Context Creator is not set")
            assertionFailure()
            return
        }

        if forTheFirstTime {
            
            // We used to schedule these operations in `finalizeInitialization`. In order to speed up the boot process, we schedule them here instead
            internalQueue.addOperation { [weak self] in
                self?.deleteOrphanedDatabaseObjects(flowId: flowId, log: log, contextCreator: contextCreator)
                // 2020-06-29 Added this to make sure we always send attachments
                delegateManager.uploadAttachmentChunksDelegate.cleanExistingOutboxAttachmentSessionsCreatedBy(.shareExtension, flowId: flowId)
            }
            
            internalQueue.addOperation { [weak self] in
                self?.cleanOutboxFromOrphanedMessagesDirectories(flowId: flowId)
                delegateManager.uploadAttachmentChunksDelegate.resumeMissingAttachmentUploads(flowId: flowId)
                delegateManager.uploadAttachmentChunksDelegate.queryServerOnSessionsTasksCreatedByShareExtension(flowId: flowId)
            }
            
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
                attachmentSessions = try OutboxAttachmentSession.getAllCreatedByAppType(appTypeCreator, within: obvContext.context)
            } catch {
                os_log("Could not invalidate and cancel old OutboxAttachmentSessions: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
            
            for attachmentSession in attachmentSessions {
                let configuration = URLSessionConfiguration.background(withIdentifier: attachmentSession.sessionIdentifier)
                let urlSession = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
                urlSession.invalidateAndCancel()
                obvContext.context.delete(attachmentSession)
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

        os_log("Rescheduling all outbox messages and attachmentds during bootstrap", log: log, type: .info)
                
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            // Perform a batch upload of messages without attachment

            do {
                let serverURLs = try OutboxMessage.getAllServerURLsForMessagesToUpload(within: obvContext.context)
                for serverURL in serverURLs {
                    Task {
                        try? await delegateManager.networkSendFlowDelegate.requestBatchUploadMessagesWithoutAttachment(serverURL: serverURL, flowId: flowId)
                    }
                }
            } catch {
                os_log("Could not reschedule batch upload of messages", log: log, type: .fault)
                assertionFailure()
                return
            }

            // Upload messages with attachments

            let outboxMessageIdentifiers: [ObvMessageIdentifier]
            do {
                let outboxMessages = try OutboxMessage.getAllMessagesToUploadWithAttachments(within: obvContext.context)
                outboxMessageIdentifiers = outboxMessages.compactMap { $0.messageId }
            } catch {
                os_log("Could not reschedule existing OutboxMessages", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            os_log("Number of outbox messages found during bootstrap: %{public}d", log: log, type: .info, outboxMessageIdentifiers.count)

            for messageId in outboxMessageIdentifiers {
                delegateManager.networkSendFlowDelegate.newOutboxMessageWithAttachments(messageId: messageId, flowId: flowId)
            }
            
        }
    }
    
    
    private func pruneOldOutboxMessages(flowId: FlowIdentifier, log: OSLog, contextCreator: ObvCreateContextDelegate, delegateManager: ObvNetworkSendDelegateManager) {
        guard appType == .mainApp else { assertionFailure(); return }
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            let dateInThePast = Date(timeIntervalSinceNow: -TimeInterval(days: 30))
            do {
                try OutboxMessage.pruneOldOutboxMessages(createdEarlierThan: dateInThePast, log: log, within: obvContext.context)
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not prune old OutboxMessages: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                // In producation, continue anyway
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
        var notificationPosted = Set<ObvMessageIdentifier>()
        
        for change in relevantChanges {
            guard let updatedProperties = change.updatedProperties else { continue }
            let updatedPropertiesNames = updatedProperties.map { $0.name }
            guard updatedPropertiesNames.contains(OutboxMessage.Predicate.Key.timestampFromServer.rawValue) else { continue }
            // We look for the message. If it does not exist, we do not notify the app. It will eventually be notified when we will deal with the change containing the deletion of the message.
            guard let outboxMessage = try? obvContext.existingObject(with: change.changedObjectID) as? OutboxMessage else { continue }
            guard let timestampFromServer = outboxMessage.timestampFromServer else { assertionFailure(); continue }
            guard let messageId = outboxMessage.messageId else { assertionFailure(); continue }
            guard !notificationPosted.contains(messageId) else { continue }
            notificationPosted.insert(messageId)
            os_log("Sending a outboxMessageWasUploaded notification (bootstraped update transaction) for messageId: %{public}@", log: log, type: .info, outboxMessage.messageId.debugDescription)
            
            ObvNetworkPostNotification.outboxMessageWasUploaded(messageId: messageId, timestampFromServer: timestampFromServer, isAppMessageWithUserContent: outboxMessage.isAppMessageWithUserContent, isVoipMessage: outboxMessage.isVoipMessage, flowId: obvContext.flowId)
                .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

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
            deletedMessages = try DeletedOutboxMessage.getAll(within: obvContext.context)
        } catch {
            os_log("Could not get all deleted outbox messages", log: log, type: .fault)
            assertionFailure()
            return
        }

        let messageIdsAndTimestampsFromServer = deletedMessages.map() { ($0.messageId, $0.timestampFromServer) }
        guard !messageIdsAndTimestampsFromServer.isEmpty else { return }
        ObvNetworkPostNotification.outboxMessagesAndAllTheirAttachmentsWereAcknowledged(
            messageIdsAndTimestampsFromServer: messageIdsAndTimestampsFromServer,
            flowId: obvContext.flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }
    
    
    public func deleteHistoryConcerningTheAcknowledgementOfOutboxMessage(messageIdentifier: ObvMessageIdentifier, flowId: FlowIdentifier) async {
        
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

        contextCreator.performBackgroundTask(flowId: flowId) { obvContext in

            do {
                try DeletedOutboxMessage.batchDelete(messageId: messageIdentifier, within: obvContext.context)
                try obvContext.save(logOnFailure: log)
                os_log("Just deleted one DeletedOutboxMessages with messageIdentifier: %{public}@", log: log, type: .info, messageIdentifier.debugDescription)
            } catch {
                os_log("Could not delete DeletedOutboxMessages with messageIdentifier: %{public}@", log: log, type: .fault, messageIdentifier.debugDescription)
                assertionFailure()
            }
            
        }
        
    }
    

    func deleteHistoryConcerningTheAcknowledgementOfOutboxMessages(withTimestampFromServerEarlierOrEqualTo referenceDate: Date, flowId: FlowIdentifier) async {
        
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

        contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
            
            do {
                try DeletedOutboxMessage.batchDelete(withTimestampFromServerEarlierOrEqualTo: referenceDate, within: obvContext.context)
                try obvContext.save(logOnFailure: log)
                os_log("Just batch deleted all DeletedOutboxMessage entries inserted before %{public}@", log: log, type: .info, referenceDate.debugDescription)
            } catch {
                os_log("Could not batch delete DeletedOutboxMessages inserted before %{public}@: %{public}@", log: log, type: .fault, referenceDate.debugDescription, error.localizedDescription)
                assertionFailure()
            }

        }
    }
    
}


// MARK: - Bootstrapping when application did become active

extension BootstrapWorker {
    
    private func rePostOutboxMessageWasUploadedNotificationsAndTryToDeleteUploadedMessages(flowId: FlowIdentifier, log: OSLog, delegateManager: ObvNetworkSendDelegateManager) {
        
        guard let notificationDelegate = delegateManager.notificationDelegate else { assertionFailure(); return }
        
        delegateManager.contextCreator?.performBackgroundTaskAndWait(flowId: flowId, { (obvContext) in
            let uploadedMessages: [OutboxMessage]
            do {
                uploadedMessages = try OutboxMessage.getAllUploaded(within: obvContext.context)
            } catch {
                os_log("Could not get all uploaded messages", log: log, type: .fault)
                assertionFailure()
                return
            }
            for msg in uploadedMessages {
                guard let timestampFromServer = msg.timestampFromServer else { assertionFailure(); continue }
                guard let messageId = msg.messageId else { assertionFailure(); continue }
                ObvNetworkPostNotification.outboxMessageWasUploaded(messageId: messageId,
                                                                    timestampFromServer: timestampFromServer,
                                                                    isAppMessageWithUserContent: msg.isAppMessageWithUserContent,
                                                                    isVoipMessage: msg.isVoipMessage,
                                                                    flowId: flowId)
                .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)
                Task {
                    delegateManager.tryToDeleteMessageAndAttachmentsDelegate.tryToDeleteMessageAndAttachments(messageId: messageId, flowId: flowId)
                }
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
        
        // The local copy of `self.outbox` that used to stand here existed so that the closure below could build keep-URLs without capturing `self`. It builds
        // names now, and needs neither.

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

            let existingMessages: [OutboxMessage]
            do {
                existingMessages = try OutboxMessage.getAll(within: obvContext.context)
            } catch {
                os_log("Could not clean outbox: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }

            // **Nothing is deleted while anything is unknown.** `OutboxMessage.messageId` is nil for a message deleted on another thread — its getter says
            // so — and `compactMap` dropped such a message from the keep-set in silence, whereupon its directory was deleted. The two failure directions are
            // not symmetric: an orphan directory left on disk costs a few bytes until the next sweep, and deleting a live one destroys the encrypted chunks
            // of an upload in flight. So doubt means keep, and doubt about any one message means this sweep does nothing at all — it cannot know which
            // directory the unknown message would have claimed.
            let messageIdsOfExistingMessages = existingMessages.map({ $0.messageId })
            guard !messageIdsOfExistingMessages.contains(where: { $0 == nil }) else {
                os_log("📁 Not sweeping the outbox: an OutboxMessage could not say which directory is its own, and nothing may be deleted while that is true", log: log, type: .error)
                return
            }
            let existingMessageIds = Set(messageIdsOfExistingMessages.compactMap({ $0 }))

            // **Compared by name, and never by URL**, exactly as `BootstrapWorker.cleanInboxFromOrphanedMessagesDirectories` was taught to on 2026-08-31 —
            // the reasoning is written out there. This was a `Set<URL>` subtraction between
            // candidates from `contentsOfDirectory(at:)`, which answers `file:///private/var/mobile/…`, and a keep-set from
            // `appendingPathComponent(_:isDirectory:)`, which answers `file:///var/mobile/…`: the same directory, and never an exact match, so the keep-set
            // was inert and **every** live message directory in the outbox was deleted on every launch. The inbox's twin of this was measured doing exactly
            // that on an iPhone 13, and then found in production on 2026-09-03 as an inbox holding no directories at all while its rows had all survived.
            // Every candidate and every keep name is a direct child of `outbox`, so within that one directory the name **is** the identity: a 64-character
            // hex string, needing no filesystem access, and correct for a directory not yet created.
            //
            // Both names are kept for every message, the deterministic one and the legacy ones, whatever is on disk. The legacy half used to be a `reduce`
            // whose closure ignored `partialResult` and returned only the names it had just computed, so it kept the legacy names of the **last** message of
            // the set and of no other.
            var namesOfDirectoriesToKeep = Set<String>()
            for messageId in existingMessageIds {
                namesOfDirectoriesToKeep.insert(messageId.directoryNameForMessageAttachments)
                namesOfDirectoriesToKeep.formUnion(messageId.legacyDirectoryNamesForMessageAttachments)
            }

            messageDirectoriesToDelete = messageDirectories.filter({ !namesOfDirectoriesToKeep.contains($0.lastPathComponent) })

            // **It says so when it deletes, and stays quiet otherwise.** What made the bug above invisible for as long as it lasted is that a sweep removed a
            // live upload's chunks and said nothing. A healthy outbox is silent: the counts are not printed and the loop below does not run.
            if !messageDirectoriesToDelete.isEmpty {
                os_log("📁 Sweeping %d orphaned message director(ies) from the outbox, of %d found, against %d OutboxMessage(s)", log: log, type: .info, messageDirectoriesToDelete.count, messageDirectories.count, existingMessages.count)
            }

        }

        for url in messageDirectoriesToDelete {
            // Named one by one, not counted, for the same reason the inbox's sweep names them.
            do {
                try FileManager.default.removeItem(at: url)
                os_log("📁 Swept the orphaned message directory %{public}@ from the outbox, and every encrypted chunk staged in it", log: log, type: .info, url.path)
            } catch {
                os_log("📁 Could not sweep the orphaned message directory %{public}@ from the outbox: %{public}@", log: log, type: .error, url.path, error.localizedDescription)
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
                let sessionIdentifiers = try OutboxAttachmentSession.getSessionIdentifiersOfAllOrphanedOutboxAttachmentSession(within: obvContext.context)
                guard !sessionIdentifiers.isEmpty else { return }
                for sessionIdentifier in sessionIdentifiers {
                    let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
                    let urlSession = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
                    urlSession.invalidateAndCancel()
                }
                try OutboxAttachmentSession.deleteAllOrphaned(within: obvContext.context)
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
                chunks = try OutboxAttachmentChunk.getAllOrphanedOutboxAttachmentChunk(with: obvContext.context)
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
                obvContext.context.delete(chunk)
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
                try OutboxAttachment.deleteAllOrphanedAttachments(within: obvContext.context)
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
                try MessageHeader.deleteAllOrphanedHeaders(within: obvContext.context)
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not delete orphaned headers: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
        }
    }

    
}
