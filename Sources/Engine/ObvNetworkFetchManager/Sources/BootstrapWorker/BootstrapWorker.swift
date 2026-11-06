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
import ObvMetaManager
import OlvidUtils


final class BootstrapWorker {

    private static let logCategory = "BootstrapWorker"
    private static var log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
    private static var logger = Logger(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)

    private let inbox: URL

    weak var delegateManager: ObvNetworkFetchDelegateManager?

    init(inbox: URL, logPrefix: String) {
        let logSubsystem = "\(logPrefix).\(ObvNetworkFetchDelegateManager.defaultLogSubsystem)"
        Self.log = OSLog(subsystem: logSubsystem, category: Self.logCategory)
        Self.logger = Logger(subsystem: logSubsystem, category: Self.logCategory)
        self.inbox = inbox
    }

    
    func finalizeInitialization(flowId: FlowIdentifier) {
        
        guard let delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
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

    
    func applicationWasInitializedButWasNeverOnScreen(flowId: FlowIdentifier) async {

        guard let delegateManager = delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            return
        }

        guard let contextCreator = delegateManager.contextCreator else {
            Self.logger.fault("The Context Creator is not set")
            assertionFailure()
            return
        }

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            Self.logger.fault("The notification delegate is not set")
            assertionFailure()
            return
        }

        resumeAttachmentsDownloadNotAlreadyDownloading(delegateManager: delegateManager, flowId: flowId)
        reNotifyAboutDecryptedApplicationMessage(flowId: flowId, contextCreator: contextCreator, notificationDelegate: notificationDelegate, delegateManager: delegateManager)
    }

    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) {
        Task {
            await applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime, flowId: flowId)
        }
    }
    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {

        guard let delegateManager = delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            return
        }

        guard let contextCreator = delegateManager.contextCreator else {
            Self.logger.fault("The Context Creator is not set")
            assertionFailure()
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            Self.logger.fault("The notification delegate is not set")
            assertionFailure()
            return
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            Self.logger.fault("The identity delegate is not set")
            assertionFailure()
            return
        }
        
        if forTheFirstTime {
            
            // These operations used to be scheduled in the `finalizeInitialization` method. In order to speed up the boot process, we schedule them here instead
            try? await delegateManager.downloadAttachmentChunksDelegate.cleanExistingInboxAttachmentSessions(flowId: flowId)
            performBatchDeleteAndMarkAsListedForAllOwnedIdentities(flowId: flowId, log: Self.log, identityDelegate: identityDelegate, contextCreator: contextCreator, delegateManager: delegateManager)

            Task { [weak self] in
                guard let self else { return }
                await removeExpectedContactForReProcessingIfAppropriate(flowId: flowId, contextCreator: contextCreator, identityDelegate: identityDelegate, delegateManager: delegateManager)
                await deleteOldInboxMessagesExpectingContactForReProcessing(delegateManager: delegateManager, flowId: flowId)
                await deleteAllWebSocketServerQueries(delegateManager: delegateManager, flowId: flowId, logOnFailure: Self.log)

                do { try await delegateManager.wellKnownCacheDelegate.downloadAndUpdateCache(flowId: flowId) } catch { assertionFailure(error.localizedDescription) }

                do { try await delegateManager.serverQueryDelegate.deletePendingServerQueryOfNonExistingOwnedIdentities(flowId: flowId) } catch { assertionFailure(error.localizedDescription) }
                do { try await postAllPendingServerQuery(delegateManager: delegateManager, flowId: flowId) } catch { assertionFailure(error.localizedDescription) }
                reNotifyAboutAPIKeyStatus(contextCreator: contextCreator, notificationDelegate: notificationDelegate, flowId: flowId)
            }
            Task(priority: .low) { [weak self] in
                await self?.deleteOldPendingUserDataUploads()
            }
            
            await deleteOrphanedDatabaseObjects(flowId: flowId, log: Self.log, delegateManager: delegateManager)

            Task { [weak self] in
                guard let self else { return }
                cleanInboxFromOrphanedMessagesDirectories(flowId: flowId)
                do {
                    try await deleteOrRefreshServerUserData(flowId: flowId)
                } catch {
                    //assertionFailure(error.localizedDescription)
                }
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
        
        contextCreator.performBackgroundTaskAndWait { context in
            
            let messages: [InboxMessage]
            do {
                messages = try InboxMessage.fetchApplicationMessagesToReNotify(within: context)
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
                   
                    // 2025-07-30: We used to notify that an ObvMessage or ObvOwnedMessage has been decrypted, allowing the app
                    // to process the message. We don't do that anymore, as the app either has processed the message or
                    // will request a stream of messages.
                    
                } else {
                    
                    for attachment in inboxMessage.attachments {
                        guard let attachmentId = try? attachment.attachmentId else { assertionFailure(); continue }
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
                        if try identityDelegate.isIdentity(contact.contactCryptoId.cryptoIdentity, aContactIdentityOfTheOwnedIdentity: contact.ownedCryptoId.cryptoIdentity, within: obvContext.context) {
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
            Self.logger.fault("The Context Creator is not set")
            assertionFailure()
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
        
        contextCreator.performBackgroundTaskAndWait { context in
            
            let existingMessages: [InboxMessage]
            do {
                existingMessages = try InboxMessage.getAll(within: context)
            } catch {
                os_log("Could not clean inbox: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                return
            }

            // **Nothing is deleted while anything is unknown.** `getAttachmentsDirectory(withinInbox:)` returns nil when the message was deleted on another
            // thread — its own doc comment says so — and a message that answers nil silently drops out of the keep-set, whereupon its directory is deleted.
            // That is the same data loss as the URL comparison below, by a second route. The two failure directions here are not symmetric: leaving an orphan
            // directory on disk costs a few bytes until the next sweep, and deleting a live one destroys a download in flight. So doubt means keep, and doubt
            // about any one message means this sweep does nothing at all — it cannot know which directory the unknown message would have claimed.
            let directoriesOfExistingMessages = existingMessages.map({ $0.getAttachmentsDirectory(withinInbox: inbox) })
            guard !directoriesOfExistingMessages.contains(where: { $0 == nil }) else {
                Self.logger.error("Not sweeping the inbox: an InboxMessage could not say which directory is its own, and nothing may be deleted while that is true")
                return
            }

            // **Compared by name, and never by URL.** This was a `Set<URL>` subtraction until 2026-08-31, and it deleted **every** message directory in the
            // inbox on **every** launch and every return to the foreground. The two sides are built differently — the candidates come from
            // `contentsOfDirectory(at:)`, which answers `file:///private/var/mobile/…`, and the keep-set from `inbox.appendingPathComponent(_:isDirectory:)`,
            // which answers `file:///var/mobile/…` — so `subtracting` matched nothing and the keep-set was inert. Measured on an iPhone 13 with both forms
            // printed side by side: *found 1 message directory, 1 InboxMessage, keeps 1, DELETES 1*.
            //
            // **What it cost was silent data loss on a download in flight.** A completed attachment has already been moved into the app's `Fyle` store, so its
            // directory really is disposable and the mistake is invisible; an attachment still downloading has its bytes here, and they went. The chunk flags
            // live in Core Data and survived, so nothing re-requested the lost chunks: a 1GB attachment came out the right size with its first 590MB reading as
            // zeros and failed its sha256 with no way back — twice in one download, once per return to the foreground. Small attachments finish inside one
            // foreground session, which is the whole reason this survived in production.
            //
            // **A name rather than a canonicalised URL**, deliberately, and the alternatives were weighed: `resolvingSymlinksInPath()` fixes the difference
            // that was measured and leaves a path-string match that can break again on percent-encoding or normalisation, and `fileResourceIdentifierKey` is
            // the canonical answer but needs both sides to exist on disk. Every candidate and every keep-URL is a direct child of `inbox`, so within that one
            // directory the name **is** the identity: a 64-character hex string, needing no filesystem access, and correct for a directory not yet created.
            // This does not canonicalise the URLs; it removes the need to.
            let namesOfDirectoriesToKeep = Set(directoriesOfExistingMessages.compactMap({ $0?.lastPathComponent }))

            messageDirectoriesToDelete = messageDirectories.filter({ !namesOfDirectoriesToKeep.contains($0.lastPathComponent) })

            // **It says so when it deletes, and stays quiet otherwise.** Not a probe left behind: what made the bug above invisible for as long as it lasted is
            // that a sweep removed a live download's bytes and said nothing, and the counts are what would have shown it in a single line. A healthy inbox is
            // silent, so this costs nothing in the ordinary case.
            if !messageDirectoriesToDelete.isEmpty {
                Self.logger.info("Sweeping \(messageDirectoriesToDelete.count) orphaned message director(ies) from the inbox, of \(messageDirectories.count) found, against \(existingMessages.count) InboxMessage(s)")
            }
        }
        
        for url in messageDirectoriesToDelete {
            // **Named one by one, not counted.** This sweep deleted every live message directory in the inbox for as long as it compared URLs, and what made
            // that invisible is that it said nothing about *which* directory it removed. A healthy inbox is still silent: the loop does not run.
            do {
                try FileManager.default.removeItem(at: url)
                Self.logger.info("📁 Swept the orphaned message directory \(url.path, privacy: .public) from the inbox, and every attachment file in it")
            } catch {
                Self.logger.error("📁 Could not sweep the orphaned message directory \(url.path, privacy: .public) from the inbox: \(error.localizedDescription, privacy: .public)")
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
        try await delegateManager.serverQueryDelegate.processAllPendingServerQueryOnBootstrap(flowId: flowId)
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


// MARK: - Orphan cleanup for the `pendingUserDataUploads` staging directory

extension BootstrapWorker {

    /// When the network manager receives a `putUserData` server query, it hardlinks the caller-supplied
    /// source file into the `pendingUserDataUploads` staging directory. The file is normally removed once
    /// the upload completes (success or permanent failure). However, if the app is terminated mid-upload
    /// the hardlink may be left behind.
    ///
    /// This sweep runs at the first `applicationAppearedOnScreen` of each launch and removes files that:
    ///   1. are **not referenced** by any active `PendingServerQuery` row (so we never pull a file out
    ///      from under a still-pending upload), and
    ///   2. are at least one hour old (a small TTL guard against racing with an in-progress adoption
    ///      whose `PendingServerQuery` row exists in a context that has not yet saved).
    fileprivate func deleteOldPendingUserDataUploads() async {

        guard let delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            return
        }

        guard let contextCreator = delegateManager.contextCreator else {
            Self.logger.fault("The Context Creator is not set")
            assertionFailure()
            return
        }

        let pendingUserDataUploads = delegateManager.pendingUserDataUploads
        let includingPropertiesForKeys: [URLResourceKey] = [
            .creationDateKey,
            .isWritableKey,
            .isRegularFileKey,
        ]
        let fileURLs: [URL]
        do {
            fileURLs = try FileManager.default.contentsOfDirectory(at: pendingUserDataUploads, includingPropertiesForKeys: includingPropertiesForKeys, options: .skipsHiddenFiles)
        } catch {
            Self.logger.fault("Could not enumerate the pendingUserDataUploads directory: \(error.localizedDescription, privacy: .public)")
            assertionFailure()
            return
        }

        guard !fileURLs.isEmpty else { return }

        // Collect the set of file paths still referenced by an active `.putUserData` server query. Any
        // file in `pendingUserDataUploads` outside this set is an orphan and a candidate for deletion.
        let referencedPaths: Set<String>
        do {
            referencedPaths = Set(try await PendingServerQuery.getAllPutUserDataFileURLs(contextCreator: contextCreator).map(\.path))
        } catch {
            Self.logger.fault("Could not enumerate pending server queries while sweeping pendingUserDataUploads: \(error.localizedDescription, privacy: .public)")
            assertionFailure()
            return
        }

        let dateLimit = Date(timeIntervalSinceNow: -TimeInterval(hours: 1))

        for fileURL in fileURLs {
            guard !referencedPaths.contains(fileURL.path) else { continue }
            guard let attributes = try? fileURL.resourceValues(forKeys: Set(includingPropertiesForKeys)) else { continue }
            guard attributes.isWritable == true else { continue }
            guard attributes.isRegularFile == true else { continue }
            guard let creationDate = attributes.creationDate, creationDate < dateLimit else { continue }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

}
