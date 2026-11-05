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
import OSLog
import CoreData
import ObvMetaManager
import OlvidUtils

final class ObvNetworkFetchDelegateManager {
    
    let sharedContainerIdentifier: String
    let supportBackgroundFetch: Bool
    
    static let defaultLogSubsystem = "io.olvid.network.fetch"
    private(set) var logSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    
    /// Engine box holding incoming server messages awaiting protocol-side processing.
    let inbox: URL
    
    /// Engine box that the network fetch manager fully owns, used to stage files awaiting upload to the
    /// server via `putUserData` server queries.
    ///
    /// **Lifecycle:**
    /// - On receipt of a `putUserData` server query (whether from a protocol via the channel-mediated
    ///   path, or from `ServerUserDataCoordinator` for a re-upload), the network manager **adopts** the
    ///   caller-supplied source file by hardlinking (or copying as fallback) it into this directory and
    ///   rewriting the `PendingServerQuery`'s `dataURL` to point at the hardlink. The caller may delete
    ///   its own copy of the source file at any time afterwards.
    /// - The actual upload reads bytes from the hardlink in this directory.
    /// - Once the upload succeeds (or fails permanently), the hardlink is removed from this directory.
    ///
    /// **Files outside this directory are off-limits.** The network manager deletes only files inside
    /// `pendingUserDataUploads`. This is the retro-compatibility safety net for any `PendingServerQuery`
    /// row created by an earlier app version that referenced a caller-owned file directly (e.g. an
    /// identity-manager-owned photo): such files are never deleted by the network manager because their
    /// path does not start with this directory's path.
    ///
    /// **Orphans** can accumulate if the app is terminated between queuing and uploading. Bootstrap GC
    /// sweeps the directory at engine launch.
    let pendingUserDataUploads: URL

    let internalNotificationCenter = NotificationCenter()

    // MARK: - Queues allowing to execute Core Data operations
    
    private static let qualityOfService: QualityOfService = .userInitiated
    let queueSharedAmongCoordinators = OperationQueue.createSerialQueue(name: "Queue shared among coordinators of ObvNetworkFetchManagerImplementation", qualityOfService: qualityOfService)
    let queueForComposedOperations = {
        let queue = OperationQueue()
        queue.name = "Queue for composed operations"
        queue.qualityOfService = qualityOfService
        return queue
    }()
    
    // MARK: - How many messages are handled at a time
    //
    // Three of these used to be a single constant. That was a problem: changing it for one purpose silently changed the other two.
    // They were separated on 2026-09-15. All of them are 100, the value the single constant had, so the split changed no behaviour.
    //
    // The size of the batch the app receives depends on how the message arrived:
    // - the app is catching up on messages already in the inbox: `numberOfMessagesStreamedToTheAppAtOnce`
    // - the message was just listed from the server: `numberOfMessagesSavedToTheInboxAtOnce`
    // - the message arrived any other way: `numberOfMessagesDecryptedAtOnce`
    //
    // Larger batches do not make a drain faster. Measured on 2026-09-15: decrypting a message costs 3.1ms, and the app then
    // spends 110.8ms on it. The app does the same work per message whatever the batch size, so there is nothing to amortise.

    /// How many freshly listed messages are written to the inbox in one operation.
    ///
    /// This is a memory guard. An `InboxMessage` row holds its encrypted content inline, so saving several hundred of them in
    /// one operation keeps all of that content in memory at once.
    ///
    /// It also decides how many messages the app receives at a time for freshly listed messages. Such a batch is decrypted by a
    /// `ProcessBatchOfUnprocessedMessagesOperation` limited to the messages this slice saved, so
    /// ``numberOfMessagesDecryptedAtOnce`` plays no part.
    ///
    /// Careful: each slice used to be sent to the server as one "mark as listed" request, so raising this constant also raised a
    /// request size. That is no longer true. The request is sized where it is sent, by
    /// `BatchDeleteAndMarkAsListedCoordinator.markSpecificMessagesAsListedOrRequestTheirDeletion`, which halves its batch when
    /// the server answers 413.
    static let numberOfMessagesSavedToTheInboxAtOnce = 100

    /// How many messages waiting in the inbox are decrypted in one operation.
    ///
    /// This is the fetch limit used by `ProcessBatchOfUnprocessedMessagesOperation`, for every execution reason except the one
    /// that names its own messages. It therefore decides how many messages the app receives at a time for a message that arrived
    /// on the WebSocket, or that a listing left behind, or whose sender has just become a contact.
    ///
    /// Raising this does not speed up a drain. Decryption costs 3.1ms per message, against 110.8ms per message in the app.
    static let numberOfMessagesDecryptedAtOnce = 100

    /// How many messages already waiting in the inbox are handed to the app at a time, when the app asks for the stream.
    ///
    /// These messages are already decrypted. `Predicate.toBeProcessByApp` requires a message payload, and only a successful
    /// decryption writes one. So this path does no cryptography: it reads rows and hands them over.
    ///
    /// A message goes through here only if it was decrypted before the app asked for the stream. A drain that starts while the
    /// app is already running never uses this path.
    ///
    /// Careful: this number does not limit how much memory this path uses.
    /// `InboxMessage.getObjectIDsOfInboxMessagesToBeProcessedByApp` takes every waiting identifier with no fetch limit, and the
    /// stream buffers without limit, so a large backlog is held in memory whatever this number is.
    static let numberOfMessagesStreamedToTheAppAtOnce = 100

    /// How many messages are marked for deletion in one operation.
    ///
    /// The same memory guard as ``numberOfMessagesSavedToTheInboxAtOnce``, for the other direction: marking fetches the rows, and a
    /// row holds its encrypted content inline, so marking several hundred of them in one save keeps all of that content in memory at
    /// once. A caller can name many more messages than this — the app's stale-settings pass walks pages of 500, in a background
    /// window, where the memory limit is tightest — so `deleteApplicationMessagesAndAttachments` slices the work rather than trusting
    /// what it was handed.
    static let numberOfMessagesMarkedForDeletionAtOnce = 100

    let queueForDecryptingChunks = OperationQueue.createSerialQueue(name: "Queue for decrypting chunks")

    let queueForPostingNotifications = DispatchQueue(label: "ObvNetworkFetchDelegateManager queue for posting notifications")

    /// Holds how long recent server requests took, for the diagnostics the app can show and a reader can send us.
    let serverRequestTimingStore: ServerRequestTimingStore

    // MARK: Instance variables (internal delegates)
    
    let networkFetchFlowDelegate: NetworkFetchFlowDelegate
    let serverSessionDelegate: ServerSessionDelegate
    let messagesDelegate: MessagesDelegate
    let downloadAttachmentChunksDelegate: DownloadAttachmentChunksDelegate
    let batchDeleteAndMarkAsListedDelegate: BatchDeleteAndMarkAsListedDelegate
    let serverPushNotificationsDelegate: ServerPushNotificationsDelegate
    let webSocketDelegate: WebSocketDelegate
    let getTurnCredentialsDelegate: GetTurnCredentialsDelegate?
    let freeTrialQueryDelegate: FreeTrialQueryDelegate?
    let verifyReceiptDelegate: VerifyReceiptDelegate?
    let serverQueryDelegate: ServerQueryDelegate
    let serverQueryWebSocketDelegate: ServerQueryWebSocketDelegate
    let serverUserDataDelegate: ServerUserDataDelegate
    let wellKnownCacheDelegate: WellKnownCacheDelegate

    // MARK: Instance variables (external delegates)
    
    weak var contextCreator: ObvCreateContextDelegate?
    weak var processDownloadedMessageDelegate: ObvProcessDownloadedMessageDelegate?
    weak var solveChallengeDelegate: ObvSolveChallengeDelegate?
    weak var notificationDelegate: ObvNotificationDelegate?
    weak var identityDelegate: ObvIdentityDelegate?
    weak var simpleFlowDelegate: ObvSimpleFlowDelegate?
    weak var channelDelegate: ObvChannelDelegate?

    // MARK: Initialiazer
    
    init(inbox: URL,
         pendingUserDataUploads: URL,
         sharedContainerIdentifier: String,
         supportBackgroundFetch: Bool,
         logPrefix: String,
         networkFetchFlowDelegate: NetworkFetchFlowDelegate,
         serverSessionDelegate: ServerSessionDelegate,
         downloadMessagesAndListAttachmentsDelegate: MessagesDelegate,
         downloadAttachmentChunksDelegate: DownloadAttachmentChunksDelegate,
         batchDeleteAndMarkAsListedDelegate: BatchDeleteAndMarkAsListedDelegate,
         serverPushNotificationsDelegate: ServerPushNotificationsDelegate,
         webSocketDelegate: WebSocketDelegate,
         getTurnCredentialsDelegate: GetTurnCredentialsDelegate?,
         freeTrialQueryDelegate: FreeTrialQueryDelegate,
         verifyReceiptDelegate: VerifyReceiptDelegate,
         serverQueryDelegate: ServerQueryDelegate,
         serverQueryWebSocketDelegate: ServerQueryWebSocketDelegate,
         serverUserDataDelegate: ServerUserDataDelegate,
         wellKnownCacheDelegate: WellKnownCacheDelegate) {

        self.logSubsystem = "\(logPrefix).\(logSubsystem)"
        self.inbox = inbox
        self.pendingUserDataUploads = pendingUserDataUploads
        self.sharedContainerIdentifier = sharedContainerIdentifier
        self.supportBackgroundFetch = supportBackgroundFetch
        self.serverRequestTimingStore = ServerRequestTimingStore(sharedContainerIdentifier: sharedContainerIdentifier)

        self.networkFetchFlowDelegate = networkFetchFlowDelegate
        self.serverSessionDelegate = serverSessionDelegate
        self.messagesDelegate = downloadMessagesAndListAttachmentsDelegate
        self.downloadAttachmentChunksDelegate = downloadAttachmentChunksDelegate
        self.batchDeleteAndMarkAsListedDelegate = batchDeleteAndMarkAsListedDelegate
        self.serverPushNotificationsDelegate = serverPushNotificationsDelegate
        self.webSocketDelegate = webSocketDelegate
        self.getTurnCredentialsDelegate = getTurnCredentialsDelegate
        //self.queryApiKeyStatusDelegate = queryApiKeyStatusDelegate
        self.verifyReceiptDelegate = verifyReceiptDelegate
        self.serverQueryDelegate = serverQueryDelegate
        self.serverQueryWebSocketDelegate = serverQueryWebSocketDelegate
        self.serverUserDataDelegate = serverUserDataDelegate
        self.wellKnownCacheDelegate = wellKnownCacheDelegate
        self.freeTrialQueryDelegate = freeTrialQueryDelegate
    }
}


// MARK: - Errors

extension ObvNetworkFetchDelegateManager {
    
    enum ObvError: Error {
        case contextCreatorIsNil
        case composedOperationCancelled
    }
    
}


// MARK: - Helpers

extension ObvNetworkFetchDelegateManager {
    
    func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>, log: OSLog, flowId: FlowIdentifier) throws -> CompositionOfOneContextualOperation<T> {
        
        guard let contextCreator else {
            assertionFailure("The context creator manager is not set")
            throw ObvError.contextCreatorIsNil
        }
        
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: contextCreator, queueForComposedOperations: queueForComposedOperations, log: log, flowId: flowId)
        
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: log)
        }
        return composedOp
        
    }
    
    func createCompositionOfTwoContextualOperation<T1: LocalizedErrorWithLogType, T2: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T1>, op2: ContextualOperationWithSpecificReasonForCancel<T2>, log: OSLog, flowId: FlowIdentifier) throws -> CompositionOfTwoContextualOperations<T1, T2> {
        
        guard let contextCreator else {
            assertionFailure("The context creator manager is not set")
            throw ObvError.contextCreatorIsNil
        }

        let composedOp = CompositionOfTwoContextualOperations(op1: op1, op2: op2, contextCreator: contextCreator, queueForComposedOperations: queueForComposedOperations, log: log, flowId: flowId)
        
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: log)
        }
        return composedOp
    }
    
    /// Queues one operation on the serial queue shared by the coordinators, and waits for it.
    ///
    /// **Leave `queuePriority` nil unless the operation deletes rows.** Every caller of this queue adds one operation and waits for it before
    /// adding the next, so at normal priority the queue is first come, first served and a caller waits for at most one turn per other caller.
    /// A priority reorders only what is waiting, and a caller that loops at a higher priority — the listing, saving one page after
    /// another — overtakes a waiting operation at every turn, for as long as it loops. The exception is an operation that removes rows
    /// the operations behind it would otherwise scan: once it has run, every one of them has fewer rows to read and less to hold, so it
    /// goes first (the batch-delete sweep's two, the second only for a batch the server has confirmed a deletion in). Marking a row for
    /// deletion, or as listed, is not that — the row stays, content and all — and stays at normal. Nor is the purge of a deleted
    /// profile's rows, which nothing behind it would read and which loops for as long as the profile's backlog lasts.
    ///
    /// What this costs a message arriving while the stale-settings pass runs is not measured: its processing now waits its turn behind the
    /// pass's marks, one segment of a path from arrival to the app's write that nothing yet times end to end.
    func queueAndAwaitCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>, queuePriority: Operation.QueuePriority? = nil, log: OSLog, flowId: FlowIdentifier) async throws {
        
        let composedOp = try createCompositionOfOneContextualOperation(op1: op1, log: log, flowId: flowId)
        if let queuePriority {
            composedOp.queuePriority = queuePriority
        }
        await queueSharedAmongCoordinators.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            if let reasonForCancel = op1.reasonForCancel as? ObvNetworkFetchManager.GetPendingServerQueryTypeOperation.ReasonForCancel {
                switch reasonForCancel {
                case .ownedIdentityIsNotActive:
                    break
                case .pendingServerQueryNotFound:
                    break
                default:
                    assertionFailure()
                }
            } else {
                //assertionFailure()
            }
            throw ObvError.composedOperationCancelled
        }

    }
    
    func queueAndAwaitCompositionOfTwoContextualOperation<T1: LocalizedErrorWithLogType, T2: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T1>, op2: ContextualOperationWithSpecificReasonForCancel<T2>, log: OSLog, flowId: FlowIdentifier) async throws {
     
        let composedOp = try createCompositionOfTwoContextualOperation(op1: op1, op2: op2, log: log, flowId: flowId)
        await queueSharedAmongCoordinators.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw ObvError.composedOperationCancelled
        }

    }
    
}
