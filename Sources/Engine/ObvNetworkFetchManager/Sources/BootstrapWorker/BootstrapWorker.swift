/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
    
    private static let logCategory = "BootstrapWorker"
    private static var log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)

    private let inbox: URL

    weak var delegateManager: ObvNetworkFetchDelegateManager?

    init(inbox: URL, logPrefix: String) {
        let logSubsystem = "\(logPrefix).\(ObvNetworkFetchDelegateManager.defaultLogSubsystem)"
        Self.log = OSLog(subsystem: logSubsystem, category: Self.logCategory)
        self.inbox = inbox
    }

    
    func finalizeInitialization(flowId: FlowIdentifier) {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        
        Task {
            do {
                try await delegateManager.wellKnownCacheDelegate.initializateCache(flowId: flowId)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }

    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) {
        Task {
            await applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime, flowId: flowId)
        }
    }
    
    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {

        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The Context Creator is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        
        // These operations used to be scheduled in the `finalizeInitialization` method. In order to speed up the boot process, we schedule them here instead
        try? await delegateManager.downloadAttachmentChunksDelegate.cleanExistingOutboxAttachmentSessions(flowId: flowId)
        performBatchDeleteAndMarkAsListedForAllOwnedIdentities(flowId: flowId, log: Self.log, identityDelegate: identityDelegate, contextCreator: contextCreator, delegateManager: delegateManager)

        if forTheFirstTime {
            Task { [weak self] in
                guard let self else { return }
                await removeExpectedContactForReProcessingIfAppropriate(flowId: flowId, contextCreator: contextCreator, identityDelegate: identityDelegate, delegateManager: delegateManager)
                await deleteOldInboxMessagesExpectingContactForReProcessing(delegateManager: delegateManager, flowId: flowId)
                resumeAttachmentsDownloadNotAlreadyDownloading(delegateManager: delegateManager, flowId: flowId)
                reNotifyAboutDecryptedApplicationMessage(flowId: flowId, contextCreator: contextCreator, notificationDelegate: notificationDelegate, delegateManager: delegateManager)
                await deleteAllWebSocketServerQueries(delegateManager: delegateManager, flowId: flowId, logOnFailure: Self.log)

                do { try await delegateManager.wellKnownCacheDelegate.downloadAndUpdateCache(flowId: flowId) } catch { assertionFailure(error.localizedDescription) }
                
                do { try await delegateManager.serverQueryDelegate.deletePendingServerQueryOfNonExistingOwnedIdentities(flowId: flowId) } catch { assertionFailure(error.localizedDescription) }
                do { try await postAllPendingServerQuery(delegateManager: delegateManager, flowId: flowId) } catch { assertionFailure(error.localizedDescription) }
                reNotifyAboutAPIKeyStatus(contextCreator: contextCreator, notificationDelegate: notificationDelegate, flowId: flowId)
            }
        }

        await deleteOrphanedDatabaseObjects(flowId: flowId, log: Self.log, delegateManager: delegateManager)

        Task { [weak self] in
            guard let self else { return }
            cleanInboxFromOrphanedMessagesDirectories(flowId: flowId)
            do {
                try await deleteOrRefreshServerUserData(flowId: flowId)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
        
    }

    /// This method wraps all the calls to the methods allowing to clean the various databases of this manager, by deleting
    /// the objects that should have been cascade deleted but that, for some reason, still exist. This method is called on init,
    /// but also each time the app becomes active.
    private func deleteOrphanedDatabaseObjects(flowId: FlowIdentifier, log: OSLog, delegateManager: ObvNetworkFetchDelegateManager) async {
        await deleteOrphanedInboxAttachmentChunk(flowId: flowId, log: Self.log, delegateManager: delegateManager)
        await deleteOrphanedInboxAttachments(flowId: flowId, log: Self.log, delegateManager: delegateManager)
        await deleteOrphanedInboxAttachmentSessions(flowId: flowId, log: Self.log, delegateManager: delegateManager)
    }

}

// MARK: - On init (finalizing the initialization)

extension BootstrapWorker {
    
    private func reNotifyAboutAPIKeyStatus(contextCreator: ObvCreateContextDelegate, notificationDelegate: ObvNotificationDelegate, flowId: FlowIdentifier) {
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { obvContext in
            do {
                let serverSessions = try ServerSession.getAllServerSessions(within: obvContext.context).filter({ !$0.isDeleted })
                for serverSession in serverSessions {
                    guard let ownedCryptoId = try? serverSession.ownedCryptoIdentity else { assertionFailure(); continue }
                    guard let apiKeyStatus = serverSession.apiKeyStatus, let apiPermissions = serverSession.apiPermissions else { continue }
                    ObvNetworkFetchNotificationNew.newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(
                        ownedIdentity: ownedCryptoId,
                        apiKeyStatus: apiKeyStatus,
                        apiPermissions: apiPermissions,
                        apiKeyExpirationDate: serverSession.apiKeyExpirationDate)
                    .postOnBackgroundQueue(delegateManager?.queueForPostingNotifications, within: notificationDelegate)
                }
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    
    private func deleteOrphanedInboxAttachmentChunk(flowId: FlowIdentifier, log: OSLog, delegateManager: ObvNetworkFetchDelegateManager) async {
        let op1 = DeleteOrphanedInboxAttachmentChunkOperation()
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            os_log("Could not delete orphaned inbox attachments chunks during bootstrap: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }

    
    private func deleteOrphanedInboxAttachments(flowId: FlowIdentifier, log: OSLog, delegateManager: ObvNetworkFetchDelegateManager) async {
        let op1 = DeleteOrphanedInboxAttachmentsOperation()
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            os_log("Could not delete orphaned inbox attachments chunks during bootstrap: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    
    
    private func deleteOrphanedInboxAttachmentSessions(flowId: FlowIdentifier, log: OSLog, delegateManager: ObvNetworkFetchDelegateManager) async {
        let op1 = DeleteOrphanedInboxAttachmentSessionsOperation()
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            os_log("Could not delete orphaned inbox attachments chunks during bootstrap: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    
    
    private func performBatchDeleteAndMarkAsListedForAllOwnedIdentities(flowId: FlowIdentifier, log: OSLog, identityDelegate: ObvIdentityDelegate, contextCreator: ObvCreateContextDelegate, delegateManager: ObvNetworkFetchDelegateManager) {
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { obvContext in

            do {
                let ownedCryptoIds = try identityDelegate.getOwnedIdentities(restrictToActive: true, within: obvContext)
                for ownedCryptoId in ownedCryptoIds {
                    Task {
                        do {
                            try await delegateManager.batchDeleteAndMarkAsListedDelegate.batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoId, flowId: flowId)
                        } catch {
                            os_log("Could not perform batch delete and marked as listed for an owned identity during bootstrap: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                            assertionFailure()
                        }
                    }
                }
            } catch {
                os_log("Could not perform batch delete and marked as listed during bootstrap: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }

    }
    
    
    private func resumeAttachmentsDownloadNotAlreadyDownloading(delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) {
        Task {
            do {
                try await delegateManager.downloadAttachmentChunksDelegate.resumeDownloadOfAttachmentsNotAlreadyDownloading(downloadKind: .allDownloadableAttachmentsWithoutSession, flowId: flowId)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }

    
    private func reNotifyAboutDecryptedApplicationMessage(flowId: FlowIdentifier, contextCreator: ObvCreateContextDelegate, notificationDelegate: ObvNotificationDelegate, delegateManager: ObvNetworkFetchDelegateManager) {
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { obvContext in
            
            let messages: [InboxMessage]
            do {
                messages = try InboxMessage.fetchApplicationMessagesToReNotify(within: obvContext)
                assert(messages.allSatisfy({ !$0.canBeDeletedFromServer }))
            } catch {
                os_log("Could not get inbox messages", log: Self.log, type: .fault)
                assertionFailure()
                return
            }

            os_log("Number of InboxMessage instances that cannot be deleted from server during bootstrap: %d", log: Self.log, type: .info, messages.count)

            // Re-send a notification that will eventually allow the app to process the message

            for inboxMessage in messages {
                
                if !inboxMessage.markedForDeletion {
                    
                    guard let obvMessageOrObvOwnedMessage = inboxMessage.getObvMessageOrObvOwnedMessage(inbox: inbox) else {
                        assertionFailure()
                        continue
                    }
                    
                    ObvNetworkFetchNotificationNew.applicationMessagesDecrypted(messages: [obvMessageOrObvOwnedMessage], flowId: flowId)
                        .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
                    
                } else {
                    
                    for attachment in inboxMessage.attachments {
                        guard let attachmentId = attachment.attachmentId else { assertionFailure(); continue }
                        switch attachment.status {
                        case .paused:
                            break
                        case .resumeRequested:
                            // We already resumed all downloads above
                            break
                        case .downloaded:
                            delegateManager.networkFetchFlowDelegate.attachmentWasDownloaded(attachmentId: attachmentId, flowId: flowId)
                        case .cancelledByServer:
                            delegateManager.networkFetchFlowDelegate.attachmentWasCancelledByServer(attachmentId: attachmentId, flowId: flowId)
                        case .markedForDeletion:
                            continue
                        }
                    }

                }
                
            }
            
        }
        
    }
    
    
    /// Fetches all ``InboxMessage`` instances with a non-nil expected contact for reprocessing. For each remote identity found, we check if this remote identity is now a contact.
    /// If this is the case, we remove this expected remote identity and re-process the messages. This is only required in the case we missed the notification about the fact that a remote
    /// identity is now a contact.
    private func removeExpectedContactForReProcessingIfAppropriate(flowId: FlowIdentifier, contextCreator: ObvCreateContextDelegate, identityDelegate: ObvIdentityDelegate, delegateManager: ObvNetworkFetchDelegateManager) async {

        do {
            
            let expectedContactsThatAreNowContacts = try await determineExpectedContactsThatAreNowContacts(flowId: flowId, contextCreator: contextCreator, identityDelegate: identityDelegate)

            os_log("Number of expected contacts that can be re-processed inbox messages during bootstrap: %d", log: Self.log, type: .info, expectedContactsThatAreNowContacts.count)
            
            guard !expectedContactsThatAreNowContacts.isEmpty else { return }
            
            try await delegateManager.messagesDelegate.removeExpectedContactForReProcessingOperationThenProcessUnprocessedMessages(expectedContactsThatAreNowContacts: expectedContactsThatAreNowContacts, flowId: flowId)
            
        } catch {
            assertionFailure()
        }
        
    }
    
    
    /// ``InboxMessage`` instances that expect a contact before re-processing (a situation that only occurs when the message was sent using a pre-key) shall be deleted after a certain retention period.
    private func deleteOldInboxMessagesExpectingContactForReProcessing(delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) async {
        
        let op1 = MarkForDeletionOldInboxMessagesExpectingContactForReProcessingOperation()
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            assertionFailure(error.localizedDescription)
        }

    }
    
    
    private func determineExpectedContactsThatAreNowContacts(flowId: FlowIdentifier, contextCreator: ObvCreateContextDelegate, identityDelegate: ObvIdentityDelegate) async throws -> Set<ObvContactIdentifier> {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<ObvContactIdentifier>, any Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    var expectedContactsThatAreNowContacts = Set<ObvContactIdentifier>()
                    let expectedContactsForReProcessing = try InboxMessage.getExpectedContactsForReProcessing(within: obvContext.context)
                    os_log("Number of expected contacts for re-processing inbox messages during bootstrap: %d", log: Self.log, type: .info, expectedContactsForReProcessing.count)
                    for contact in expectedContactsForReProcessing {
                        if try identityDelegate.isIdentity(contact.contactCryptoId.cryptoIdentity, aContactIdentityOfTheOwnedIdentity: contact.ownedCryptoId.cryptoIdentity, within: obvContext) {
                            expectedContactsThatAreNowContacts.insert(contact)
                        }
                    }

                    return continuation.resume(returning: expectedContactsThatAreNowContacts)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
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
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The Context Creator is not set", log: Self.log, type: .fault)
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
            os_log("Could not clean inbox: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
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
            os_log("Could not clean inbox: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            return
        }
        
        guard !messageDirectories.isEmpty else { return }
               
        var messageDirectoriesToDelete = Set<URL>()
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            let existingMessages: [InboxMessage]
            do {
                existingMessages = try InboxMessage.getAll(within: obvContext)
            } catch {
                os_log("Could not clean outbox: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                return
            }

            let messageDirectoriesToKeep: Set<URL> = Set(existingMessages.compactMap({ $0.getAttachmentDirectory(withinInbox: inbox) }) )
            
            messageDirectoriesToDelete = messageDirectories.subtracting(messageDirectoriesToKeep)
            
        }
        
        for url in messageDirectoriesToDelete {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                os_log("Could not properly clean the outbox", log: Self.log, type: .error)
            }

        }
        
    }

    
    private func deleteOrRefreshServerUserData(flowId: FlowIdentifier) async throws {
        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.delegateManagerIsNil
        }
        try await delegateManager.serverUserDataDelegate.deleteOrRefreshServerUserData(flowId: flowId)
    }

    
    private func postAllPendingServerQuery(delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) async throws {
        try await delegateManager.serverQueryDelegate.processAllPendingServerQuery(flowId: flowId)
    }
    
    
    private func deleteAllWebSocketServerQueries(delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier, logOnFailure: OSLog) async {
        let op1 = DeleteAllWebSocketPendingServerQueryOperation(delegateManager: delegateManager)
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: logOnFailure, flowId: flowId)
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }
    
    
}


// MARK: - Erros

extension BootstrapWorker {
    
    enum ObvError: Error {
        case delegateManagerIsNil
        case theContextCreatorIsNotSet
        case couldNotProcessMessageMarkedForDeletion
        case identityDelegateIsNil
    }
    
}
