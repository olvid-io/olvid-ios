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
import ObvServerInterface
import ObvTypes
import ObvOperation
import ObvCrypto
import ObvMetaManager
import CoreData
import OlvidUtils


actor BatchDeleteAndMarkAsListedCoordinator: BatchDeleteAndMarkAsListedDelegate {
    
    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "BatchDeleteAndMarkAsListedCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
    private static var logger = Logger(subsystem: defaultLogSubsystem, category: logCategory)

    weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()

    private var currentTaskForOwnedCryptoIdentity = [ObvCryptoIdentity: Task<Void, Error>]()

    func setDelegateManager(_ delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }

    private var cacheOfCurrentDeviceUIDForOwnedIdentity = [ObvCryptoIdentity: UID]()
    
    private static let defaultFetchLimit = 50

    /// How many rows needing only a local deletion are taken in one go.
    ///
    /// Not ``defaultFetchLimit``. That number is what the server accepts in one request, and is halved when the server answers 413.
    /// Deleting these rows sends nothing to the server, so the only limit that matters is the size of one Core Data save. This
    /// matches the `fetchBatchSize` used elsewhere in this manager.
    private static let localDeletionFetchLimit = 500

    /// How many rows of profiles that no longer exist are taken in one go.
    ///
    /// Smaller than ``localDeletionFetchLimit``, and not for the same reason that one is larger than ``defaultFetchLimit``. These rows are fetched as objects,
    /// each carrying its encrypted content inline, and a deleted profile's inbox can be the whole backlog it never got through — so the page size here is what
    /// one save should hold in memory. It is 100, the same value `ObvNetworkFetchDelegateManager.numberOfMessagesSavedToTheInboxAtOnce` carries as a memory
    /// guard over the same rows — and a constant of its own, because the three constants there were split on 2026-09-15 for exactly the reason that sharing
    /// one means changing it here to change something else.
    private static let nonExistingOwnedIdentityFetchLimit = 100

    /// The batch size currently in use for each owned identity, which is **not** always ``defaultFetchLimit``.
    ///
    /// A payload the server refuses with a 413 is retried at half the size, and that halving used to be forgotten the moment the round ended: the recursive
    /// follow-up call in ``createBatchTask`` goes through the two-argument entry point, which starts again from ``defaultFetchLimit``. A client whose payload is
    /// persistently too large therefore re-paid a 413 on every single round, for ever. Remembering the working size per owned identity is what stops that.
    ///
    /// **The size is never grown back**, and the first version of this fix did grow it — doubling after any accepted round — which reinstated the bug in a
    /// subtler form: the round that immediately follows a halving is the *halved* one, so it succeeds, doubles the size straight back, and the next round pays
    /// the 413 again. Nor is a slower climb worth having, because a 413 here is not a transient condition: the payload is ~43 bytes per message and otherwise
    /// fixed, so a refusal at a given size means the server's limit is below it and will refuse again. Probing upwards can only re-pay the 413 it just learnt
    /// to avoid. The cost of never growing back is bounded and small — a server accepting 40 leaves us batching 25 for the rest of the session — and this map
    /// is in memory, so a relaunch starts from the default anyway.
    private var fetchLimitForOwnedCryptoIdentity = [ObvCryptoIdentity: Int]()

    private func currentFetchLimit(for ownedCryptoIdentity: ObvCryptoIdentity) -> Int {
        fetchLimitForOwnedCryptoIdentity[ownedCryptoIdentity] ?? Self.defaultFetchLimit
    }

    /// Called when the server refused a payload of `refusedFetchLimit` messages. Returns the size to try next, or `nil` when we are already down to one message
    /// and halving cannot help.
    private func halveFetchLimit(for ownedCryptoIdentity: ObvCryptoIdentity, refusedFetchLimit: Int) -> Int? {
        guard refusedFetchLimit > 1 else { return nil }
        let newFetchLimit = max(1, refusedFetchLimit / 2)
        fetchLimitForOwnedCryptoIdentity[ownedCryptoIdentity] = newFetchLimit
        Self.logger.info("🎉 The server refused a payload of \(refusedFetchLimit) message(s). The batch size for this owned identity is now \(newFetchLimit), and stays there for the rest of the session.")
        return newFetchLimit
    }
    
    private static let urlSession: URLSession = {
        var configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = true
        configuration.isDiscretionary = false
        configuration.shouldUseExtendedBackgroundIdleMode = true
        configuration.waitsForConnectivity = false
        configuration.allowsConstrainedNetworkAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        let urlSession = URLSession(configuration: configuration)
        return urlSession
    }()

}


// MARK: - Implementing BatchDeleteAndMarkAsListedDelegate

extension BatchDeleteAndMarkAsListedCoordinator {
    
    /// This is called by the `MessagesCoordinator` just after saving to DB a slice of downloaded messages.
    ///
    /// The size of the request is decided here, not by the caller. The caller's slice is
    /// `ObvNetworkFetchDelegateManager.numberOfMessagesSavedToTheInboxAtOnce`, which is a memory guard on the save, because a message
    /// row carries its `rawEncryptedContent` inline. It says nothing about what this server method will accept.
    ///
    /// Sending one request per slice therefore tied this payload to a constant that is tuned for something else. The raise from 10 to
    /// 100 on 2026-09-13 took it past the sweep's own default of 50, without anybody choosing that. Against a server whose limit is
    /// below 100, the result is a 413 on every slice of every listing, for ever: nothing gets marked as listed, so the next listing
    /// returns the same messages and pays the same cost again.
    ///
    /// So this batches at ``currentFetchLimit(for:)``, and halves on a 413, exactly as
    /// ``batchDeleteAndMarkAsListed(ownedCryptoIdentity:fetchLimit:flowId:)`` does. The remembered size is shared with the sweep, so
    /// whichever path meets the refusal first, both learn from it.
    func markSpecificMessagesAsListedOrRequestTheirDeletion(ownedCryptoId: ObvCryptoIdentity, messageUIDsAndCategories: [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory], flowId: FlowIdentifier) async throws {

        guard !messageUIDsAndCategories.isEmpty else { return }

        guard let delegateManager else {
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        // A slice rather than an `Array`, because `dropFirst` below returns a slice too: an `Array` here would have to be rebuilt on every round.
        var remaining = messageUIDsAndCategories[...]

        while !remaining.isEmpty {

            let batch = Array(remaining.prefix(currentFetchLimit(for: ownedCryptoId)))

            do {
                let taskId = String(UUID().description.prefix(5))
                try await requestDeleteMessageAndAttachments(ownedCryptoIdentity: ownedCryptoId,
                                                             messageUIDsAndCategories: batch,
                                                             delegateManager: delegateManager,
                                                             flowId: flowId,
                                                             taskId: taskId)
                remaining = remaining.dropFirst(batch.count)
            } catch ObvError.serverQueryPayloadIsTooLargeForServer(currentFetchLimit: let refusedFetchLimit) {
                // The refused batch is retried at half the size, and the halving is remembered for the rest of the session. `remaining` is deliberately left
                // alone: nothing of this batch reached the server, so the smaller request must cover the same messages.
                guard halveFetchLimit(for: ownedCryptoId, refusedFetchLimit: refusedFetchLimit) != nil else {
                    // We are down to a single message and halving cannot help. Giving up here is the same bounded cost as any other failure below.
                    Self.logger.fault("The server refused a payload of one message. Giving up on marking \(remaining.count) message(s) as listed.")
                    assertionFailure()
                    return
                }
                continue
            } catch {
                // Swallowed on purpose, as it always has been, and the cost of doing so is bounded: nothing was recorded for the batches not yet sent, so those
                // messages keep `markedAsListedOnServer == false` and the server still holds them. The next listing therefore returns them and the batch sweep
                // tries again — the cost of a failure here is one redundant listing, not a lost message.
                Self.logger.fault("Could not mark specific messages as listed, nor request their deletion: \(error.localizedDescription)")
                assertionFailure()
                return
            }

        }

    }


    func batchDeleteAndMarkAsListed(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws {
        try await batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: currentFetchLimit(for: ownedCryptoIdentity), flowId: flowId)
    }


    /// Removes every inbox row belonging to an owned identity that is not in `existingOwnedCryptoIds`. Called during bootstrap and when an owned identity is
    /// deleted, like the sweeps of server sessions and pending server queries that answer the same call.
    ///
    /// A deleted profile's rows are marked for deletion by the first step of the deletion protocol and swept by the ordinary batch tasks that step starts —
    /// but nothing awaits those tasks, and the identity row goes in a later step, so whatever they had not reached by then is left behind. A batch task cannot
    /// finish that work itself: it is told one owned identity and, finding no such identity, cannot tell a profile that has been deleted from one it merely
    /// cannot see. Here the question is the other way round — these are the profiles that exist — so the answer is not a guess.
    ///
    /// Paged, because a profile deleted while it was behind can hold its entire backlog, and a page that removes nothing ends the loop: asking again would
    /// fetch the same rows and remove none of them again.
    ///
    /// Everything here rests on `existingOwnedCryptoIds` being what a successful fetch found, an empty set meaning *this device has no profile at all* and
    /// never *the profiles could not be read*. The caller is where that holds: it throws rather than carrying on with what it has, and this sweep is not
    /// reached at all when it does. A caller that ever answered a failure with an empty set would take a live profile's inbox with it.
    func deleteInboxMessagesAssociatedToNonExistingOwnedIdentity(existingOwnedCryptoIds: Set<ObvCryptoIdentity>, flowId: FlowIdentifier) async throws {

        guard let delegateManager else {
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        var rowsDeleted = 0

        while true {

            let op1 = DeleteInboxMessagesOfNonExistingOwnedIdentitiesOperation(existingOwnedCryptoIds: existingOwnedCryptoIds, fetchLimit: Self.nonExistingOwnedIdentityFetchLimit, inbox: delegateManager.inbox)
            // At the queue's normal priority, though it removes rows. A remover goes first when the operations behind it would otherwise scan the rows it
            // takes; nothing behind this one works on a profile that no longer exists, so nothing gets cheaper for waiting. And it loops: at `.high`, a profile
            // deleted with its backlog behind it would overtake every other operation on the queue at every turn, for the whole of the purge.
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)

            guard op1.numberOfRowsDeleted > 0 else { break }

            rowsDeleted += op1.numberOfRowsDeleted

        }

        if rowsDeleted > 0 {
            Self.logger.notice("🎉 Removed \(rowsDeleted) inbox row(s) belonging to owned identities that no longer exist")
        }

    }
    
    
    private func batchDeleteAndMarkAsListed(ownedCryptoIdentity: ObvCryptoIdentity, fetchLimit: Int, flowId: FlowIdentifier) async throws {
        
        Self.logger.debug("Call to batchDeleteAndMarkAsListed")
        
        guard let delegateManager else {
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        do {
            try await internalBatchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity, afterWaitingFor: nil, fetchLimit: fetchLimit, delegateManager: delegateManager, flowId: flowId)
            failedAttemptsCounterManager.reset(counter: .batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity))
        } catch {
            if let obvError = error as? ObvError {
                // Certain errors do not require us to wait before trying again
                switch obvError {
                case .serverQueryPayloadIsTooLargeForServer(let refusedFetchLimit):
                    // The halved size is remembered, so the follow-up rounds do not start again from the default and re-pay a 413 every time.
                    if let newFetchLimit = halveFetchLimit(for: ownedCryptoIdentity, refusedFetchLimit: refusedFetchLimit) {
                        try? await batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: newFetchLimit, flowId: flowId)
                        return
                    }
                case .tryAgainNowThatTheServerSessionIsValid:
                    try? await batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: fetchLimit, flowId: flowId)
                    return
                default:
                    break
                }
            }
            // If we reach this point, the error requires to wait for a certain delay.
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity))
            await retryManager.waitForDelay(milliseconds: delay)
            try await batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: fetchLimit, flowId: flowId)
        }

    }
    
    
    /// Runs a batch task for this owned identity, waiting first for the one already running, if any.
    ///
    /// `alreadyAwaited` is the task this call has already waited for, and is nil on the way in. It is what tells a task that will do our
    /// work from one that has already finished: when a task ends, every caller awaiting it is resumed in an order the actor does not fix,
    /// so the creator's `defer` may not have cleared the entry yet. A second caller finding that entry would await a finished task and
    /// return having run no round at all, leaving its own work undone — which is the fault the `Task`-based self-re-entry used to cause
    /// until 2026-09-14, met again from the other side. Knowing *how* a call got here cannot see it; knowing *which task* it waited for can.
    ///
    /// The send manager's `BatchUploadMessagesWithoutAttachmentCoordinator` is the twin of this and was written the same way, for the same reason.
    private func internalBatchDeleteAndMarkAsListed(ownedCryptoIdentity: ObvCryptoIdentity, afterWaitingFor alreadyAwaited: Task<Void, Error>?, fetchLimit: Int, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) async throws {
        
        if let currentTask = currentTaskForOwnedCryptoIdentity[ownedCryptoIdentity], currentTask != alreadyAwaited {
            
            // Somebody else's task is running. Wait for it, then ask again rather than assume it did our work: whether it fetched after
            // our rows were committed is not something it can be asked.
            
            defer {
                if self.currentTaskForOwnedCryptoIdentity[ownedCryptoIdentity] == currentTask {
                    self.currentTaskForOwnedCryptoIdentity.removeValue(forKey: ownedCryptoIdentity)
                }
            }
            
            try await currentTask.value
            try await internalBatchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity, afterWaitingFor: currentTask, fetchLimit: fetchLimit, delegateManager: delegateManager, flowId: flowId)
            
        } else {
            
            // Either no task is running, or the only one registered is the one we have just waited for. Both need a task of our own.
            // Registering it replaces a stale entry, and its owner then clears nothing, every `defer` here matching on identity.
            
            let localTask = createBatchTask(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: fetchLimit, delegateManager: delegateManager, flowId: flowId)
            
            self.currentTaskForOwnedCryptoIdentity[ownedCryptoIdentity] = localTask

            defer {
                if self.currentTaskForOwnedCryptoIdentity[ownedCryptoIdentity] == localTask {
                    self.currentTaskForOwnedCryptoIdentity.removeValue(forKey: ownedCryptoIdentity)
                }
            }
            
            try await localTask.value

        }

    }

    
    /// One task that clears as much as it can for this owned identity. It returns when there is nothing left to do, or when it
    /// cannot make progress.
    ///
    /// This is a loop, not a recursion, since 2026-09-14. Each round used to end by calling
    /// ``batchDeleteAndMarkAsListed(ownedCryptoIdentity:flowId:)`` again from a `Task` nobody awaited. That caused two faults.
    ///
    /// First, a round whose only work was a local deletion returned before the follow-up was even started, because the `guard` on
    /// the server-side batch sat between the two. Rows the server had already confirmed it no longer held were therefore removed
    /// fifty at a time, and only when something outside called in again. There are three such callers: a message being marked for
    /// deletion, a processing round finding nothing to process, and the bootstrap. On a quiet device that means a relaunch, so the
    /// measured behaviour was about 250 rows per launch and then nothing at all.
    ///
    /// Second, the follow-up re-entered the de-duplication gate while the task it came from was still registered. That task had
    /// finished, so the follow-up awaited it and returned without starting a round, again leaving work undone.
    ///
    /// The loop removes the re-entry, so neither fault can happen. The gate now does only the job it was written for: stopping two
    /// real callers from starting two chains.
    ///
    /// The batch size is deliberately not re-read inside the loop. When the server refuses a payload with a 413, this task throws,
    /// and ``batchDeleteAndMarkAsListed(ownedCryptoIdentity:fetchLimit:flowId:)`` halves the remembered size and starts a fresh
    /// task. So a halving is picked up by the next task instead of mid-loop. Same result, one less actor hop per iteration.
    private func createBatchTask(ownedCryptoIdentity: ObvCryptoIdentity, fetchLimit: Int, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) -> Task<Void, Error> {
        return Task { [weak self] in
                                    
            guard let self else { return }

            var rowsDeletedLocally = 0
            var messagesSentToTheServer = 0
            var previousBatchSentToTheServer: [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory]?

            // Read once, not per round: a profile reactivated while this task runs is picked up by the next kick, and there is one on
            // reactivation. An inactive profile can ask the server nothing — no listing enumerates it and the sweep has no session —
            // so its rows are removed outright rather than marked and kept for a request that will never be made.
            //
            // A profile that no longer exists is not the same question and does not get an answer here. This task is started for every
            // message a deleted profile has, before the owned identity row is removed, so it is ordinary for one of them to run after
            // it has gone. What its rows deserve is decided where the engine decides it for every other kind of leftover, in
            // `deleteInboxMessagesAssociatedToNonExistingOwnedIdentity`, which is told which profiles exist rather than asking about one.
            guard let ownedIdentityIsActive = try await isOwnedIdentityActive(ownedCryptoIdentity: ownedCryptoIdentity, delegateManager: delegateManager, flowId: flowId) else {
                Self.logger.notice("🎉 This batch task is done: the owned identity no longer exists, so none of its rows are this sweep's to judge")
                return
            }
            let grounds: InboxMessage.GroundsForLocalDeletion = ownedIdentityIsActive ? .theServerHasConfirmed : .nothingWillEverAskTheServer

            while true {

                let taskId = String(UUID().description.prefix(5))

                // Phase 1: the rows that need no request at all — the server has confirmed it no longer holds them, or the profile is
                // inactive and nothing will ever ask. Cleared first, at their own batch size. See `InboxMessage.fetchMessagesToDeleteLocally`.
                // Taking them first also shrinks the table that phase 2 has to scan.

                let messageIdsToDeleteLocally = try await fetchMessagesToDeleteLocally(ownedCryptoIdentity: ownedCryptoIdentity, grounds: grounds, delegateManager: delegateManager)

                if !messageIdsToDeleteLocally.isEmpty {

                    Self.logger.debug("🎉 [\(taskId)] Deleting \(messageIdsToDeleteLocally.count) row(s) needing no server request")

                    let op1 = DeleteMessagesNeedingNoServerRequestOperation(messageIds: messageIdsToDeleteLocally, grounds: grounds, inbox: delegateManager.inbox)
                    do {
                        try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, queuePriority: .high, log: Self.log, flowId: flowId)
                    } catch {
                        // This used to carry on with the server-side work. Under a loop it must not: the rows are still there, so the
                        // next iteration would fetch the same ones and fail the same way, for ever. Stopping leaves them to whatever
                        // calls in next.
                        Self.logger.fault("🎉 [\(taskId)] Could not delete the messages the server already deleted: \(error.localizedDescription)")
                        assertionFailure()
                        Self.logger.notice("🎉 [\(taskId)] This batch task stops because a local deletion failed, having removed \(rowsDeletedLocally) row(s) locally and sent \(messagesSentToTheServer) message(s) to the server")
                        return
                    }

                    // The operation does not always delete all the rows we give it: it skips a row that no longer exists, and a row
                    // that no longer satisfies the conditions for deletion. If it deleted none of them, the next iteration would
                    // fetch the same rows and delete none of them again, looping with no server request and no pause. So we stop.
                    // We also count the rows that were deleted, not the rows we asked for, otherwise the logs would be wrong.
                    guard op1.numberOfRowsDeleted > 0 else {
                        Self.logger.notice("🎉 [\(taskId)] This batch task stops because a page of \(messageIdsToDeleteLocally.count) row(s) needing only a local deletion could not be cleared, having removed \(rowsDeletedLocally) row(s) locally and sent \(messagesSentToTheServer) message(s) to the server")
                        return
                    }

                    rowsDeletedLocally += op1.numberOfRowsDeleted
                    continue

                }

                // Phase 2 is the work that costs a round trip, and an inactive profile has no way to make one. Its remaining rows are the
                // ones the app is not done with, which phase 1 must not remove and no request can advance, so this task is finished.
                switch grounds {
                case .theServerHasConfirmed:
                    break
                case .nothingWillEverAskTheServer:
                    Self.logger.notice("🎉 [\(taskId)] This batch task is done: the owned identity is inactive, so nothing is asked of the server, having removed \(rowsDeletedLocally) row(s) locally")
                    return
                }

                let messageUIDsAndCategories = try await fetchMessagesToProcessOnServer(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: fetchLimit, delegateManager: delegateManager)

                guard !messageUIDsAndCategories.isEmpty else {
                    // `notice` only when this task did something, `debug` otherwise. Every kick that finds the inbox already in order
                    // comes through here, so logging all of them at a persisted level would bury the two endings below, which are the
                    // ones worth finding in a report.
                    if rowsDeletedLocally > 0 || messagesSentToTheServer > 0 {
                        Self.logger.notice("🎉 [\(taskId)] This batch task is done: nothing is left to do, having removed \(rowsDeletedLocally) row(s) locally and sent \(messagesSentToTheServer) message(s) to the server")
                    } else {
                        Self.logger.debug("🎉 [\(taskId)] This batch task is done: there was nothing to do at all")
                    }
                    return
                }

                // Getting the same batch twice means the server accepted it and nothing changed, so the operation that records the
                // outcome must have failed. A successful round always moves every message it names out of one of the two sets. Asking
                // again cannot give a different answer, and this is the only path on which the loop could otherwise spin for ever.
                //
                // The category is part of a batch's identity, not decoration. One message makes two trips: marked as listed when it
                // arrives, then deleted once the app has processed it. Comparing the identifiers alone would read that normal sequence
                // as a stall, and stop a round that still had work to do.
                let batch = messageUIDsAndCategories
                guard batch != previousBatchSentToTheServer else {
                    Self.logger.fault("🎉 [\(taskId)] The server accepted a batch of \(batch.count) message(s) and the very same batch came back, so nothing recorded the outcome. Stopping rather than asking again")
                    assertionFailure()
                    Self.logger.notice("🎉 [\(taskId)] This batch task stops because it stopped making progress, having removed \(rowsDeletedLocally) row(s) locally and sent \(messagesSentToTheServer) message(s) to the server")
                    return
                }

                Self.logger.debug("🎉 [\(taskId)] Starting the task for deleting from server, or marking as listed, \(messageUIDsAndCategories.count) received messages")

                try await requestDeleteMessageAndAttachments(ownedCryptoIdentity: ownedCryptoIdentity,
                                                             messageUIDsAndCategories: messageUIDsAndCategories,
                                                             delegateManager: delegateManager,
                                                             flowId: flowId,
                                                             taskId: taskId)

                previousBatchSentToTheServer = batch
                messagesSentToTheServer += messageUIDsAndCategories.count

            }
            
        }
    }
    
    
    /// Sends one batch to the server, at most twice: once, and once more with the invalid token named so that the session coordinator knows not to hand it
    /// back.
    ///
    /// **Bounded, where this used to call itself on every `invalidSession` with no bound and no delay.** A session the server keeps refusing is not something
    /// asking again can mend, and the recursion answered such a server with an unbroken run of two requests per round — a token request and a delete — for as
    /// long as it kept refusing. Giving up instead hands the failure to ``batchDeleteAndMarkAsListed(ownedCryptoIdentity:fetchLimit:flowId:)``, whose
    /// back-off is where waiting belongs. `MessagesCoordinator.performOneListing` bounds the same exchange the same way.
    private func requestDeleteMessageAndAttachments(ownedCryptoIdentity: ObvCryptoIdentity, messageUIDsAndCategories: [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory], delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier, taskId: String) async throws {

        var currentInvalidToken: Data?

        let maxNumberOfAttempts = 2
        
        for attemptNumber in 0..<maxNumberOfAttempts {

            let isTheLastAttempt = (attemptNumber == maxNumberOfAttempts-1)

            let token = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: ownedCryptoIdentity, currentInvalidToken: currentInvalidToken, flowId: flowId).serverSessionToken
            let deviceUid = try await getCurrentDeviceUidOfOwnedIdentity(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId)

            let method = ObvServerDeleteMessageAndAttachmentsMethod(ownedCryptoId: ownedCryptoIdentity,
                                                                    token: token,
                                                                    deviceUid: deviceUid,
                                                                    messageUIDsAndCategories: messageUIDsAndCategories,
                                                                    flowId: flowId)

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await Self.urlSession.data(for: method.getURLRequest())
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain {
                    switch nsError.code {
                    case Int(CFNetworkErrors.cfurlErrorNotConnectedToInternet.rawValue):
                        break
                    default:
                        assertionFailure()
                    }
                } else {
                    assertionFailure()
                }
                throw error
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ObvError.invalidServerResponse
            }

            Self.logger.debug("🎉 [\(taskId)] HTTP response status code is \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                switch httpResponse.statusCode {
                case 413:
                    Self.logger.debug("🎉 [\(taskId)] Payload is too large")
                    throw ObvError.serverQueryPayloadIsTooLargeForServer(currentFetchLimit: messageUIDsAndCategories.count)
                default:
                    throw ObvError.serverReturnedBadStatusCode
                }
            }

            guard let returnStatus = ObvServerDeleteMessageAndAttachmentsMethod.parseObvServerResponse(responseData: data, using: Self.log) else {
                assertionFailure()
                throw ObvError.couldNotParseReturnStatusFromServer
            }

            switch returnStatus {

            case .generalError:

                assertionFailure()
                throw ObvError.serverReturnedGeneralError

            case .invalidSession:

                guard !isTheLastAttempt else {
                    Self.logger.fault("🎉 [\(taskId)] The server refused \(maxNumberOfAttempts) session(s) for this batch of \(messageUIDsAndCategories.count) message(s). Giving up on it for now")
                    throw ObvError.theServerSessionCouldNotBeMadeValid
                }
                // No delay here, and none should be added: the cache very often holds the newer token already, in which case the next attempt costs nothing
                // at all.
                currentInvalidToken = token
                continue

            case .ok:
                Self.logger.debug("🎉 [\(taskId)] Will process the ok from server")
                let op1 = ProcessMessagesThatWereDeletedFromServerOrMarkedAsListedOnServerOperation(ownedCryptoIdentity: ownedCryptoIdentity, messageUIDsAndCategories: messageUIDsAndCategories, inbox: delegateManager.inbox)
                // `.high` priority only when the batch removes rows. A batch that merely marks rows as listed removes none — the row stays, content and all — and there
                // is one such batch per page the listing brings in, so at `.high` it would overtake whatever waits on the queue once per page for as long
                // as a backlog is listed.
                let theBatchRemovesRows = messageUIDsAndCategories.contains { $0.category == .requestDeletion }
                try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, queuePriority: theBatchRemovesRows ? .high : nil, log: Self.log, flowId: flowId)
                return

            }

        }

        // Unreachable: the loop either returns on `.ok`, throws, or takes its second attempt.
        assertionFailure()
        throw ObvError.theServerSessionCouldNotBeMadeValid

    }
    
    
    private func fetchMessagesToDeleteLocally(ownedCryptoIdentity: ObvCryptoIdentity, grounds: InboxMessage.GroundsForLocalDeletion, delegateManager: ObvNetworkFetchDelegateManager) async throws -> [ObvMessageIdentifier] {

        guard let contextCreator = delegateManager.contextCreator else {
            assertionFailure()
            throw ObvError.theContextCreatorIsNotSet
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ObvMessageIdentifier], any Error>) in
            contextCreator.performBackgroundTask() { context in
                do {
                    let messageIds = try InboxMessage.fetchMessagesToDeleteLocally(ownedCryptoIdentity: ownedCryptoIdentity, grounds: grounds, fetchLimit: Self.localDeletionFetchLimit, within: context)
                    return continuation.resume(returning: messageIds)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }

    }


    private func fetchMessagesToProcessOnServer(ownedCryptoIdentity: ObvCryptoIdentity, fetchLimit: Int, delegateManager: ObvNetworkFetchDelegateManager) async throws -> [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory] {

        guard let contextCreator = delegateManager.contextCreator else {
            assertionFailure()
            throw ObvError.theContextCreatorIsNotSet
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory], any Error>) in
            contextCreator.performBackgroundTask() { context in
                do {
                    let messages = try InboxMessage.fetchMessagesToProcessOnServer(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: fetchLimit, within: context)
                    return continuation.resume(returning: messages)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }

    }
    
}


// MARK: - Helpers

extension BatchDeleteAndMarkAsListedCoordinator {
    
    /// Whether this owned identity is active, or `nil` when there is no such owned identity any more.
    ///
    /// Not cached, unlike the current device UID below: this answer changes during the life of the process, and acting on a stale one either
    /// leaves an inactive profile's rows for ever or deletes an active profile's from under the server.
    ///
    /// The profile that no longer exists is *asked* about rather than thrown on, and that is the whole reason `isOwned` is consulted first:
    /// the identity manager answers a missing profile with an error, this question is the first thing a batch task asks, and an error here
    /// reaches the caller's back-off — which waits and asks again, for ever, since the answer cannot change. Nobody sees a retry, the catch
    /// logging nothing; what it costs is the caller's `await`, which never returns.
    private func isOwnedIdentityActive(ownedCryptoIdentity: ObvCryptoIdentity, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) async throws -> Bool? {

        guard let identityDelegate = delegateManager.identityDelegate else {
            assertionFailure()
            throw ObvError.theIdentityDelegateIsNotSet
        }

        guard let contextCreator = delegateManager.contextCreator else {
            assertionFailure()
            throw ObvError.theContextCreatorIsNotSet
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool?, Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    // Both questions on the one context, so there is no window between them.
                    guard try identityDelegate.isOwned(ownedCryptoIdentity, within: obvContext) else {
                        return continuation.resume(returning: nil)
                    }
                    let isActive = try identityDelegate.isOwnedIdentityActive(ownedIdentity: ownedCryptoIdentity, within: obvContext)
                    continuation.resume(returning: isActive)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

    }


    private func getCurrentDeviceUidOfOwnedIdentity(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> UID {
        
        if let currentDeviceUID = cacheOfCurrentDeviceUIDForOwnedIdentity[ownedCryptoIdentity] {
            return currentDeviceUID
        }
        
        guard let delegateManager = delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        guard let identityDelegate = delegateManager.identityDelegate else {
            Self.logger.fault("The identity delegate is not set")
            assertionFailure()
            throw ObvError.theIdentityDelegateIsNotSet
        }

        guard let contextCreator = delegateManager.contextCreator else {
            Self.logger.fault("The context creator is not set")
            assertionFailure()
            throw ObvError.theContextCreatorIsNotSet
        }

        let currentDeviceUID = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UID, Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedCryptoIdentity, within: obvContext)
                    continuation.resume(returning: currentDeviceUid)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
        cacheOfCurrentDeviceUIDForOwnedIdentity[ownedCryptoIdentity] = currentDeviceUID

        return currentDeviceUID
        
    }

}


// MARK: - Errors

extension BatchDeleteAndMarkAsListedCoordinator {
    
    enum ObvError: LocalizedError {
        case theDelegateManagerIsNotSet
        case theIdentityDelegateIsNotSet
        case theContextCreatorIsNotSet
        case invalidServerResponse
        case couldNotParseReturnStatusFromServer
        case tryAgainNowThatTheServerSessionIsValid
        case serverReturnedGeneralError
        case serverQueryPayloadIsTooLargeForServer(currentFetchLimit: Int)
        case serverReturnedBadStatusCode
        case theServerSessionCouldNotBeMadeValid

        
        var errorDescription: String? {
            switch self {
            case .theDelegateManagerIsNotSet:
                return "The delegate manager is not set"
            case .theIdentityDelegateIsNotSet:
                return "The identity delegate is not set"
            case .theContextCreatorIsNotSet:
                return "The context creator is not set"
            case .invalidServerResponse:
                return "Invalid server response"
            case .couldNotParseReturnStatusFromServer:
                return "Could not parse return status from server"
            case .tryAgainNowThatTheServerSessionIsValid:
                return "Try again now that the server session is valid"
            case .serverReturnedGeneralError:
                return "Server returned a general error"
            case .serverQueryPayloadIsTooLargeForServer(currentFetchLimit: let currentFetchLimit):
                return "Server query payload is too large for server (\(currentFetchLimit))"
            case .serverReturnedBadStatusCode:
                return "Server returned a bad status code"
            case .theServerSessionCouldNotBeMadeValid:
                return "The server session could not be made valid"
            }
        }
    }

}
