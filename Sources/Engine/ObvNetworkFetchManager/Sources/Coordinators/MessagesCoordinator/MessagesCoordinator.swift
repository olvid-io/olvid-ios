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
import OlvidUtils
import CoreData


actor MessagesCoordinator {
    
    // MARK: - Instance variables
    
    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "MessagesCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
    private static var logger = Logger(subsystem: defaultLogSubsystem, category: logCategory)

    weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    private enum ExtendedPayloadDownloadTask {
        case inProgress(task: Task<Void, Error>)
    }
    
    private var extendedPayloadDownloadTasks = [ObvMessageIdentifier: ExtendedPayloadDownloadTask]()
    
    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()

    init(logPrefix: String) {
        let logSubsystem = "\(logPrefix).\(Self.defaultLogSubsystem)"
        Self.logger = Logger(subsystem: logSubsystem, category: Self.logCategory)
    }

    func setDelegateManager(_ delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }

    private var cacheOfCurrentDeviceUIDForOwnedIdentity = [ObvCryptoIdentity: UID]()
    
    private typealias DownloadMessagesTask = Task<Void,Error>

    /// The listing in flight for an owned identity, whichever of the two policies asked for it.
    ///
    /// **One slot per owned identity is what stops two listings overlapping**, and that matters for more than wasted effort: an untruncated listing makes
    /// `ProcessBatchOfUnprocessedMessagesOperation` announce that the server and the inbox hold nothing unprocessed, and what acts on that announcement
    /// deletes the current device's expired pre-keys. A second listing holding a fetched page it has not saved yet would make that announcement false, and a
    /// message in that page encrypted with a deleted pre-key is lost for good.
    private var downloadMessagesTaskInProgressForOwnedCryptoId = [ObvCryptoIdentity: DownloadMessagesTask]()
    private var continuationForAsyncStreamOfObvMessageOrObvOwnedMessage: AsyncStream<[ObvTypes.ObvMessageOrObvOwnedMessage]>.Continuation?

}


// MARK: - MessagesDelegate

extension MessagesCoordinator: MessagesDelegate {

    public func getAsyncStreamOfObvMessageOrObvOwnedMessages() -> AsyncStream<[ObvTypes.ObvMessageOrObvOwnedMessage]> {
        let stream = AsyncStream([ObvTypes.ObvMessageOrObvOwnedMessage].self) { [weak self] (continuation: AsyncStream<[ObvTypes.ObvMessageOrObvOwnedMessage]>.Continuation) in
            guard let self else { return }

            Task {
                
                await self.replaceContinuationForAsyncStreamOfObvMessageOrObvOwnedMessage(by: continuation)

                // We stream the messages currently in DB that still need to be processed by the app (these messages are, in
                // particular, no marked as "on hold")
                let objectIDsOfProcessableInboxMessages: [NSManagedObjectID]
                do {
                    objectIDsOfProcessableInboxMessages = try await self.getObjectIDsOfInboxMessagesToBeProcessedByApp()
                } catch {
                    Self.logger.fault("Could not obtain objectIDs of processable messages: \(error.localizedDescription)")
                    assertionFailure() // In production, continue anyway
                    objectIDsOfProcessableInboxMessages = []
                }
                
                // This path and `notifyAboutDecryptedApplicationMessage` both feed the single stream the app consumes, so a reader
                // watching a backlog is fed by whichever of the two happens to be running. Until 2026-09-15 that was the argument for
                // one shared constant. The three sizes turned out to answer to three different things, so they are separate now.
                // Whoever changes one of them should think about the other two.

                let slices = objectIDsOfProcessableInboxMessages.toSlices(ofMaxSize: ObvNetworkFetchDelegateManager.numberOfMessagesStreamedToTheAppAtOnce)
                
                for slice in slices {
                    let messages = try await self.getObvMessageOrObvOwnedMessagesToBeProcessedByApp(inboxMessageObjectIDs: slice)
                    continuation.yield(messages)
                }
                
            }
        }
        return stream
    }

    
    func downloadAllMessagesAndListAttachments(ownedCryptoId: ObvCryptoIdentity, trigger: ObvServerRequestTiming.Trigger, flowId: FlowIdentifier) async {
                
        Self.logger.debug("[🚩][\(flowId.shortDebugDescription)] Call to downloadAllMessagesAndListAttachments for owned identity \(ownedCryptoId.debugDescription)")
        ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] MessagesCoordinator.downloadAllMessagesAndListAttachments(ownedCryptoId:flowId:)")
        defer {
            Self.logger.debug("[🚩][\(flowId.shortDebugDescription)] End of the call to downloadAllMessagesAndListAttachments for owned identity \(ownedCryptoId.debugDescription)")
        }
        
        var awaitTaskFailed = false
        let awaitedTaskDescription: String

        if let downloadMessagesTaskInProgress = downloadMessagesTaskInProgressForOwnedCryptoId[ownedCryptoId] {
            
            // A download message task is already in progress. Since it was created before our own call to downloadAllMessagesAndListAttachments(ownedCryptoId:flowId:), we wait until it's done before performing our own work.
            
            Self.logger.debug("[🚩][\(flowId.shortDebugDescription)] A task \(downloadMessagesTaskInProgress.shortDebugDescription) is already in progress for downloading messages for owned identity \(ownedCryptoId.debugDescription)")
            ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] A task \(downloadMessagesTaskInProgress.shortDebugDescription) is already in progress for downloading messages for owned identity \(ownedCryptoId.debugDescription)")
            
            try? await downloadMessagesTaskInProgress.value
            
            // Since this task was suspended while we were waiting for the end of the tasks prior our call to downloadAllMessagesAndListAttachments(ownedCryptoId:flowId:), there might be a new task in progress, created *after*
            // our call to downloadAllMessagesAndListAttachments(ownedCryptoId:flowId:).
            
            if let newDownloadMessagesTaskInProgress = downloadMessagesTaskInProgressForOwnedCryptoId[ownedCryptoId], newDownloadMessagesTaskInProgress != downloadMessagesTaskInProgress {

                // A download message task already exists. It was created *after* our call to downloadAllMessagesAndListAttachments(ownedCryptoId:flowId:) so we can simply await until it's done

                Self.logger.debug("[🚩][\(flowId.shortDebugDescription)] The previous download task \(downloadMessagesTaskInProgress.shortDebugDescription) is done. A new one was created in the meantime \(newDownloadMessagesTaskInProgress.shortDebugDescription). We await it.")
                ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] The previous download task \(downloadMessagesTaskInProgress.shortDebugDescription) is done. A new one was created in the meantime \(newDownloadMessagesTaskInProgress.shortDebugDescription). We await it.")

                do {
                    try await newDownloadMessagesTaskInProgress.value
                } catch {
                    awaitTaskFailed = true
                }

                awaitedTaskDescription = newDownloadMessagesTaskInProgress.shortDebugDescription

            } else {
                
                // No download message task was created. So we create one, save it in order to make it accessible to other calls to downloadAllMessagesAndListAttachments(ownedCryptoId:flowId:)
                
                let newDownloadMessagesTaskInProgress = createDownloadMessagesAndListAttachmentsTask(ownedCryptoId: ownedCryptoId, trigger: trigger, flowId: flowId)

                downloadMessagesTaskInProgressForOwnedCryptoId[ownedCryptoId] = newDownloadMessagesTaskInProgress
                
                Self.logger.debug("[🚩][\(flowId.shortDebugDescription)] The previous download task \(downloadMessagesTaskInProgress.shortDebugDescription) is done. No other download task was created in the meantime. We created and saved a new one \(newDownloadMessagesTaskInProgress.shortDebugDescription). We await it.")
                ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] The previous download task \(downloadMessagesTaskInProgress.shortDebugDescription) is done. No other download task was created in the meantime. We created and saved a new one \(newDownloadMessagesTaskInProgress.shortDebugDescription). We await it.")
                
                do {
                    try await newDownloadMessagesTaskInProgress.value
                } catch {
                    awaitTaskFailed = true
                }
                
                if downloadMessagesTaskInProgressForOwnedCryptoId[ownedCryptoId] == newDownloadMessagesTaskInProgress {
                    downloadMessagesTaskInProgressForOwnedCryptoId[ownedCryptoId] = nil
                }

                awaitedTaskDescription = newDownloadMessagesTaskInProgress.shortDebugDescription

            }
            
        } else {
            
            // No download task is in progress. We create one, and save it in order to make it accessible to other calls to downloadAllMessagesAndListAttachments(ownedCryptoId:flowId:)
            
            let awaitedTask = createDownloadMessagesAndListAttachmentsTask(ownedCryptoId: ownedCryptoId, trigger: trigger, flowId: flowId)
            
            downloadMessagesTaskInProgressForOwnedCryptoId[ownedCryptoId] = awaitedTask

            Self.logger.debug("[🚩][\(flowId.shortDebugDescription)] No existing task found for downloading messages for owned identity \(ownedCryptoId.debugDescription). We created task \(awaitedTask.shortDebugDescription) will now await for it.")
            ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] No existing task found for downloading messages for owned identity \(ownedCryptoId.debugDescription). We created task \(awaitedTask.shortDebugDescription) will now await for it.")

            do {
                try await awaitedTask.value
            } catch {
                awaitTaskFailed = true
            }
            
            if downloadMessagesTaskInProgressForOwnedCryptoId[ownedCryptoId] == awaitedTask {
                downloadMessagesTaskInProgressForOwnedCryptoId[ownedCryptoId] = nil
            }

            awaitedTaskDescription = awaitedTask.shortDebugDescription

        }
        
        Self.logger.debug("[🚩][\(flowId.shortDebugDescription)] The task \(awaitedTaskDescription) for downloading messages for owned identity \(ownedCryptoId.debugDescription) is finished (awaitTaskFailed: \(awaitTaskFailed)).")
        ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] The task \(awaitedTaskDescription) for downloading messages for owned identity \(ownedCryptoId.debugDescription) is finished (awaitTaskFailed: \(awaitTaskFailed))")

        if awaitTaskFailed {
            // The delay increase/reset is managed by the DownloadMessagesTask
            let delay = failedAttemptsCounterManager.getCurrentDelay(.downloadAllMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
            Self.logger.error("[🚩][\(flowId.shortDebugDescription)] 🖲️ Will retry the call to downloadAllMessagesAndListAttachments in \(Double(delay) / 1000.0) seconds")
            ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] Will retry the call to downloadAllMessagesAndListAttachments in \(delay) seconds")
            await retryManager.waitForDelay(milliseconds: delay)
            await downloadAllMessagesAndListAttachments(ownedCryptoId: ownedCryptoId, trigger: .retryOfAPreviousAttempt, flowId: flowId)
        }

    }
    
    
    private func createDownloadMessagesAndListAttachmentsTask(ownedCryptoId: ObvCryptoIdentity, trigger: ObvServerRequestTiming.Trigger, flowId: FlowIdentifier) -> DownloadMessagesTask {
        return Task {

            do {
                try await downloadMessagesAndListAttachments(ownedCryptoId: ownedCryptoId, trigger: trigger, flowId: flowId)
                failedAttemptsCounterManager.reset(counter: .downloadAllMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
                Self.logger.info("[🚩][\(flowId.shortDebugDescription)] Call to downloadMessagesAndListAttachments for owned identity \(ownedCryptoId.debugDescription) was a success")
            } catch {
                // The companion branch on `ObvError.deviceIsNotRegistered` was deleted on 2026-09-13: that case is never thrown — the server saying so is an
                // outcome, `.theServerDeclined(reason: .deviceIsNotRegistered)`, handled in the listing loop — and the notification it sent is sent from
                // `performOneListing` on every attempt that meets it. Nothing changes by removing it; it had not been reachable since the outcome existed.
                if let error = error as? ObvServerMethodError {
                    switch error {
                    case .ownedIdentityIsNotActive:
                        delegateManager?.networkFetchFlowDelegate.fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ownedCryptoId, flowId: flowId)
                        return
                    default:
                        break
                    }
                }
                _ = failedAttemptsCounterManager.incrementAndGetDelay(.downloadAllMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
                throw error
            }
            
        }
        
    }
     

    /// Lists every page the server has for this owned identity, one after another, exactly as this has always done.
    ///
    /// **A loop over ``performOneListing(ownedCryptoId:trigger:resumingAt:flowId:)`` rather than a recursion, and the two differ in more than shape.** Each
    /// page's payload is released at the end of its iteration, where a recursion suspended at the call for the next page held every page it had ever fetched
    /// alive until the whole chain unwound — a hundred pages of decoded server payload on a device working through a backlog, which is precisely the device
    /// that can least afford it.
    ///
    /// The retry economics live here and nowhere else: the worker performs one attempt and says what happened, this decides whether to pay a delay and ask
    /// again. It briefly had a second caller with the opposite policy — one page, no back-off — which the inbox drain listed through; that is gone, and the
    /// drain now starts an ordinary listing like any other caller and watches the inbox counts to see what it achieves.
    private func downloadMessagesAndListAttachments(ownedCryptoId: ObvCryptoIdentity, trigger: ObvServerRequestTiming.Trigger, flowId: FlowIdentifier) async throws {

        /// The cursor of the page to ask for next. Nil is *from the beginning*.
        var resumePoint: Int?
        /// **Three-valued and it matters.** The caller's trigger names the first attempt only; an attempt that follows a decline is
        /// `retryOfAPreviousAttempt` and one that follows a truncated page is `continuationOfATruncatedListing`, and the two compose — a decline in the
        /// middle of a long backlog goes back to the first of them and then returns to the second. Passing the caller's trigger to every attempt would
        /// mislabel every timing record of every multi-page listing, which is the whole of what that enum exists to distinguish.
        var triggerOfTheNextAttempt = trigger

        while true {

            let attempt = try await performOneListing(ownedCryptoId: ownedCryptoId, trigger: triggerOfTheNextAttempt, resumingAt: resumePoint, flowId: flowId)

            // **A session that had to be refreshed forgives the back-off accumulated so far**, which is what the `reset` on the invalid-session branch used
            // to say from inside the recursion. An invalid session is somebody else's success — another request for this identity got a new token — not a
            // failure of ours, and treating it as one would leave the next real failure waiting out a delay it never earned.
            if attempt.theBackOffShouldBeForgiven {
                failedAttemptsCounterManager.reset(counter: .downloadAllMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
            }

            switch attempt.outcome {

            case .listed(let nextResumePoint, let downloadTimestampFromServer):

                if let nextResumePoint {

                    Self.logger.info("[🚩][\(flowId.shortDebugDescription)] 🌊 Will call downloadMessagesAndListAttachments as the listing was truncated")
                    ObvDisplayableLogs.shared.log("[\(flowId.shortDebugDescription)] Will call downloadMessagesAndListAttachments as the listing was truncated")

                    do {
                        try launchProcessingOfUnprocessedMessages(ownedCryptoIdentity: ownedCryptoId,
                                                                  executionReason: .truncatedListPerformed,
                                                                  flowId: flowId)
                    } catch {
                        Self.logger.fault("[🚩] We could not process truncated list of messages: \(error.localizedDescription)")
                        assertionFailure() // In production, continue anyway
                    }

                    resumePoint = nextResumePoint
                    triggerOfTheNextAttempt = .continuationOfATruncatedListing
                    continue

                } else {

                    do {
                        try launchProcessingOfUnprocessedMessages(ownedCryptoIdentity: ownedCryptoId,
                                                                  executionReason: .untruncatedListPerformed(downloadTimestampFromServer: downloadTimestampFromServer),
                                                                  flowId: flowId)
                    } catch {
                        Self.logger.fault("[🚩] We could not process untruncated list of messages: \(error.localizedDescription)")
                        assertionFailure() // In production, continue anyway
                    }

                    Self.logger.info("[🚩][\(flowId.shortDebugDescription)] 🌊 Ending the listing as the last one was not truncated")
                    ObvDisplayableLogs.shared.log("[\(flowId.shortDebugDescription)] Ending the listing as the last one was not truncated")

                    return

                }

            case .theServerDeclined(let reason):

                let delay = failedAttemptsCounterManager.incrementAndGetDelay(.downloadAllMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
                Self.logger.error("[🚩] 🖲️ Will retry the call to downloadMessagesAndListAttachments in \(Double(delay) / 1000.0) seconds (\(reason.rawValue))")
                await retryManager.waitForDelay(milliseconds: delay)
                triggerOfTheNextAttempt = .retryOfAPreviousAttempt
                continue // Same cursor: the page we asked for is still the page we want

            case .theSessionCouldNotBeMadeValid:

                // **Backed off rather than thrown, which is what makes this equivalent to the unbounded spin it replaces.** Two invalid sessions in a row
                // means the token is being rotated faster than we can use it — another device registering, or a re-registration of our own — and asking
                // again is still the right answer. All that is added is a delay, and the caller's contract is unchanged.
                let delay = failedAttemptsCounterManager.incrementAndGetDelay(.downloadAllMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
                Self.logger.error("[🚩] 🖲️ The server session could not be made valid. Will retry the call to downloadMessagesAndListAttachments in \(Double(delay) / 1000.0) seconds")
                await retryManager.waitForDelay(milliseconds: delay)
                triggerOfTheNextAttempt = .retryOfAPreviousAttempt
                continue

            }

        }

    }


    // MARK: Listing exactly one page

    /// Why the server refused to answer a listing with a list.
    ///
    /// **Two cases rather than one**, because they want opposite things of a caller working to a deadline: a device that is not registered needs registering,
    /// and the registration that follows starts a listing of its own, where a general error simply wants trying again later. A caller shown one opaque
    /// *declined* cannot tell the two apart and neither can anybody reading its log.
    enum ServerDeclinedTheListing: String, Sendable {
        case deviceIsNotRegistered
        case generalError
    }


    /// What one attempt at a listing produced. **One page, never two**: a truncated page says where it stopped and leaves the next one to the caller.
    enum OneListingOutcome: Sendable {
        /// `nextResumePoint` is nil when the server had nothing more — which is the only thing that means the server is empty, and is what the
        /// `downloadTimestampFromServer` alongside it is for: it is the cut-off the identity manager uses to delete the current device's expired pre-keys, so
        /// it has to travel with the page rather than be re-derived.
        case listed(nextResumePoint: Int?, downloadTimestampFromServer: Date)
        case theServerDeclined(reason: ServerDeclinedTheListing)
        /// The session was invalid twice running, so the bounded refresh below gave up.
        case theSessionCouldNotBeMadeValid
    }


    /// One attempt's outcome, and the one thing about *how* it got there that the caller needs.
    private struct OneListingAttempt: Sendable {
        let outcome: OneListingOutcome
        /// Whether an invalid session was met and answered with a fresh token. Not the test for forgiving the back-off — see ``theBackOffShouldBeForgiven``.
        let theSessionWasRefreshed: Bool

        /// Whether this attempt should wipe the back-off accumulated so far.
        ///
        /// **``theSessionWasRefreshed`` alone reads like the test and is not, because it is true by construction on the one outcome that must not forgive
        /// anything.** `.theSessionCouldNotBeMadeValid` is returned from exactly one place — the second pass of the bounded refresh loop, which is reached only
        /// by the first pass having met an invalid session and set that flag. So the policy above was zeroing the counter eight lines before incrementing it,
        /// every time, and the delay for that outcome was `serverQueryBackoffDelay(forAttemptCount: 1)` — five seconds — on the first spin and on the
        /// ten-thousandth. The schedule it was meant to climb ends at thirty minutes.
        ///
        /// **`.theServerDeclined` was in this set until 2026-09-13 and had the same fault one step removed.** The argument for it was that a refresh which
        /// *worked* is somebody else's success — another request for this identity got a new token — so the failures before it were not ours to pay for. True
        /// of the refresh, and it says nothing about what the attempt then did. An attempt that meets an invalid session, refreshes, and is *declined* is an
        /// attempt that failed; forgiving it zeroes the counter immediately before the decline branch increments it, so the delay is
        /// `serverQueryBackoffDelay(forAttemptCount: 1)` again. A server rotating tokens *and* answering `generalError` — which is one outage, not two — was
        /// therefore polled every five seconds for ever, rather than climbing 5, 15, 30, 60, 300, 600, 1800.
        ///
        /// **So the test is what the attempt achieved, and only one outcome achieved anything.** Both others go straight on to increment, and forgiving
        /// either of them cancels the very increment that follows. Nothing is lost by narrowing it: a listing that finishes resets this counter outright
        /// where the task is created, so forgiveness here is only about a mid-listing page — page forty of a backlog meeting a rotated token — not paying for
        /// declines it has already served the delay for.
        var theBackOffShouldBeForgiven: Bool {
            guard theSessionWasRefreshed else { return false }
            switch outcome {
            case .listed:
                return true
            case .theServerDeclined, .theSessionCouldNotBeMadeValid:
                return false
            }
        }
    }







    /// Performs **one** listing attempt: gets a session token, asks the server, and saves what came back.
    ///
    /// **It never asks for a second page and it never waits out a back-off.** Both of those are policy, and the two callers above want opposite policies. What
    /// it does answer for itself is an invalid session, because that is not a failure and costs no round trip to fix — the token is shared by every request
    /// this identity makes, so somebody else refreshing it between our fetching it and our using it is ordinary, and the cache usually hands over the new one
    /// at once. Bounded to one such retry: a second invalid session means the token is being rotated faster than we can use it, which is a different
    /// situation and one a delay suits better than a spin.
    ///
    /// **It does not touch `failedAttemptsCounterManager`.** The counter is keyed per owned identity and shared by both policies, so a worker that adjusted
    /// it would let one caller's failures lengthen the delay another caller pays. Everything it knows that bears on the counter is in what it returns.
    ///
    /// Exactly one timing is recorded per **attempt** — so this emits two when it answers an invalid session, which is what a reader wants to see.
    private func performOneListing(ownedCryptoId: ObvCryptoIdentity, trigger triggerOfTheFirstAttempt: ObvServerRequestTiming.Trigger, resumingAt serverTimestampOfLastMessageBeforeTruncation: Int?, flowId: FlowIdentifier) async throws -> OneListingAttempt {

        guard let delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        guard let identityDelegate = delegateManager.identityDelegate else {
            Self.logger.fault("The identity delegate is not set")
            assertionFailure()
            throw ObvError.theIdentityDelegateIsNotSet
        }

        var trigger = triggerOfTheFirstAttempt
        var currentInvalidToken: Data?
        var theSessionWasRefreshed = false

        // At most twice: once, and once more with the invalid token named so the session coordinator knows not to hand it back.
        for attemptNumber in 0..<2 {

            let isTheLastAttempt = (attemptNumber == 1)

            // Each phase below is timed separately, and deliberately not summed. Getting the token, asking the server, and saving what came back have entirely
            // different remedies when one of them is slow, so a reader's report has to be able to say which of the three it was.

            let startOfTheServerSessionTokenRequest = Date.now

            let sessionToken: Data
            let currentDeviceUid: UID
            do {
                sessionToken = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(
                    for: ownedCryptoId,
                    currentInvalidToken: currentInvalidToken,
                    flowId: flowId).serverSessionToken

                currentDeviceUid = try await getCurrentDeviceUidOfOwnedIdentity(ownedCryptoIdentity: ownedCryptoId, flowId: flowId)
            } catch {
                recordTimingOfTheListing(
                    trigger: trigger,
                    outcome: .couldNotPerformTheRequest,
                    durationOfTheServerSessionTokenRequest: Date.now.timeIntervalSince(startOfTheServerSessionTokenRequest),
                    durationOfTheRequest: 0)
                throw error
            }

            let durationOfTheServerSessionTokenRequest = Date.now.timeIntervalSince(startOfTheServerSessionTokenRequest)

            // Perform the server query allowing to download messages and to list their attachments

            let startOfTheRequest = Date.now

            let serverReturnStatus: ObvServerDownloadMessagesAndListAttachmentsMethod.PossibleReturnStatus
            do {
                serverReturnStatus = try await performServerDownloadMessagesAndListAttachmentsMethod(
                    ownedCryptoId: ownedCryptoId,
                    sessionToken: sessionToken,
                    currentDeviceUid: currentDeviceUid,
                    serverTimestampOfLastMessageBeforeTruncation: serverTimestampOfLastMessageBeforeTruncation,
                    identityDelegate: identityDelegate,
                    flowId: flowId)
            } catch {
                recordTimingOfTheListing(
                    trigger: trigger,
                    outcome: .couldNotPerformTheRequest,
                    durationOfTheServerSessionTokenRequest: durationOfTheServerSessionTokenRequest,
                    durationOfTheRequest: Date.now.timeIntervalSince(startOfTheRequest))
                throw error
            }

            let durationOfTheRequest = Date.now.timeIntervalSince(startOfTheRequest)

            // Process the status returned by the server

            let downloadTimestampFromServer: Date
            let messagesAndAttachmentsOnServer: [ObvServerDownloadMessagesAndListAttachmentsMethod.MessageAndAttachmentsOnServer]
            let newServerTimestampOfLastMessageBeforeTruncation: Int?

            switch serverReturnStatus {

            case .deviceIsNotRegistered:

                recordTimingOfTheListing(
                    trigger: trigger,
                    outcome: .deviceIsNotRegistered,
                    durationOfTheServerSessionTokenRequest: durationOfTheServerSessionTokenRequest,
                    durationOfTheRequest: durationOfTheRequest)
                // Fired on every attempt that meets it, as it always has been.
                Task { delegateManager.networkFetchFlowDelegate.serverReportedThatThisDeviceIsNotRegistered(ownedIdentity: ownedCryptoId, flowId: flowId) }
                return .init(outcome: .theServerDeclined(reason: .deviceIsNotRegistered), theSessionWasRefreshed: theSessionWasRefreshed)

            case .invalidSession:

                recordTimingOfTheListing(
                    trigger: trigger,
                    outcome: .invalidSession,
                    durationOfTheServerSessionTokenRequest: durationOfTheServerSessionTokenRequest,
                    durationOfTheRequest: durationOfTheRequest)
                guard !isTheLastAttempt else {
                    return .init(outcome: .theSessionCouldNotBeMadeValid, theSessionWasRefreshed: theSessionWasRefreshed)
                }
                // No delay here, and none should be added: the cache very often holds the newer token already, in which case the next attempt costs nothing
                // at all.
                currentInvalidToken = sessionToken
                theSessionWasRefreshed = true
                trigger = .retryOfAPreviousAttempt
                continue

            case .generalError:

                recordTimingOfTheListing(
                    trigger: trigger,
                    outcome: .generalError,
                    durationOfTheServerSessionTokenRequest: durationOfTheServerSessionTokenRequest,
                    durationOfTheRequest: durationOfTheRequest)
                return .init(outcome: .theServerDeclined(reason: .generalError), theSessionWasRefreshed: theSessionWasRefreshed)

            case .listingTruncated(let _downloadTimestampFromServer, let _messagesAndAttachmentsOnServer, let _serverTimestampOfLastMessageBeforeTruncation):
                downloadTimestampFromServer = _downloadTimestampFromServer
                messagesAndAttachmentsOnServer = _messagesAndAttachmentsOnServer
                newServerTimestampOfLastMessageBeforeTruncation = _serverTimestampOfLastMessageBeforeTruncation

            case .ok(let _downloadTimestampFromServer, let _messagesAndAttachmentsOnServer):
                downloadTimestampFromServer = _downloadTimestampFromServer
                messagesAndAttachmentsOnServer = _messagesAndAttachmentsOnServer
                newServerTimestampOfLastMessageBeforeTruncation = nil

            }

            // If we reach this point, the server returned a proper list of messages and attachments that we can save.
            // Note that the listing is truncated iff serverTimestampOfLastMessageBeforeTruncation != nil
                    
            ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] We successfully downloaded \(messagesAndAttachmentsOnServer.count) messages that we will now save to DB. New serverTimestampOfLastMessageBeforeTruncation: \(String(describing: newServerTimestampOfLastMessageBeforeTruncation))")
            Self.logger.info("[🚩][\(flowId.shortDebugDescription)] We successfully downloaded \(messagesAndAttachmentsOnServer.count) messages that we will now save to DB. New serverTimestampOfLastMessageBeforeTruncation: \(String(describing: newServerTimestampOfLastMessageBeforeTruncation))")

            // We may have downloaded hundreds of messages. We don't want to save them all in one big operation. So we split the
            // messagesAndAttachmentsOnServer array into slices, and save then process each slice idependently.
            
            let messagesAndAttachmentsOnServerSlices = messagesAndAttachmentsOnServer.toSlices(ofMaxSize: ObvNetworkFetchDelegateManager.numberOfMessagesSavedToTheInboxAtOnce)

            // Timed apart from the request above: this is the phase whose cost grows with the number of messages the server had for us, and it is ours to make
            // faster where the request's duration is not.
            let startOfTheSaveAndProcess = Date.now

            for (index, messagesAndAttachmentsOnServerSlice) in messagesAndAttachmentsOnServerSlices.enumerated() {
                
                let isLastSlice: Bool = (index == messagesAndAttachmentsOnServerSlices.count - 1)
                
                let idsOfMessagesToProcess: [ObvMessageIdentifier]
                let idsOfMessagesSafelyInDatabase: Set<UID>
                do {
                    let op1 = SaveMessagesAndAttachmentsFromServerOperation(
                        ownedIdentity: ownedCryptoId,
                        listOfMessageAndAttachmentsOnServer: messagesAndAttachmentsOnServerSlice,
                        downloadTimestampFromServer: downloadTimestampFromServer,
                        localDownloadTimestamp: Date(),
                        logger: Self.logger,
                        flowId: flowId)
                    // At the queue's normal priority, deliberately. This save used to be queued at `.high`, so on a device listing page after page each
                    // new save overtook whatever was already waiting at normal — the stale-settings pass's marks among them — for as long as the
                    // listing went on. First come, first served bounds every caller's wait to one turn per other caller.
                    try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
                    idsOfMessagesToProcess = op1.idsOfMessagesToProcess
                    idsOfMessagesSafelyInDatabase = op1.idsOfMessagesSafelyInDatabase
                } catch {
                    recordTimingOfTheListing(
                        trigger: trigger,
                        outcome: .couldNotSaveWhatCameBack,
                        durationOfTheServerSessionTokenRequest: durationOfTheServerSessionTokenRequest,
                        durationOfTheRequest: durationOfTheRequest,
                        durationOfTheSaveAndProcess: Date.now.timeIntervalSince(startOfTheSaveAndProcess),
                        numberOfMessagesReturned: messagesAndAttachmentsOnServer.count)
                    assertionFailure()
                    throw ObvError.failedSaveMessagesAndAttachmentsFromServer
                }

                ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] Among the \(messagesAndAttachmentsOnServer.count) downloaded messages, \(idsOfMessagesToProcess.count) should be processed. isLastSlice: \(isLastSlice.description)")
                Self.logger.info("[🚩][\(flowId.shortDebugDescription)] Among the \(messagesAndAttachmentsOnServer.count) downloaded messages, \(idsOfMessagesToProcess.count) should be processed. isLastSlice: \(isLastSlice.description)")
                
                // All the messages of the slice were saved, so we can tell the server about each of them: either that we are aware of it, or — when everything
                // the server holds for it is now in our database — that it can delete it outright.
                // We do this asynchronously so as not to slow down the saving of other messages.
                
                Task {
                    do {
                        let messageUIDsAndCategories = Self.messageUIDsAndCategories(
                            forSlice: messagesAndAttachmentsOnServerSlice,
                            messageUIDsSafelyInDatabase: idsOfMessagesSafelyInDatabase,
                            flowId: flowId)
                        try await delegateManager.batchDeleteAndMarkAsListedDelegate.markSpecificMessagesAsListedOrRequestTheirDeletion(ownedCryptoId: ownedCryptoId, messageUIDsAndCategories: messageUIDsAndCategories, flowId: flowId)
                    } catch {
                        Self.logger.fault("[🚩] The call to markSpecificMessagesAsListedOrRequestTheirDeletion did fail: \(error.localizedDescription)")
                        assertionFailure()
                    }
                }
                
                // All the messages of the slice where saved, we can request their processing.
                // We do this asynchronously so as not to slow down the saving of other messages.

                do {
                    try launchProcessingOfUnprocessedMessages(ownedCryptoIdentity: ownedCryptoId,
                                                              executionReason: .oneSliceOfListOfDownloadedMessagesWasSaved(idsOfMessagesToProcess: idsOfMessagesToProcess),
                                                              flowId: flowId)
                } catch {
                    Self.logger.fault("[🚩] We could not process the saved slice of messages: \(error.localizedDescription)")
                    assertionFailure() // In production, save the other slices anyway
                }

                // We requested the "mark as listed" and the processing of the slice, we loop to the next slice
                
            }
            recordTimingOfTheListing(
                trigger: trigger,
                outcome: newServerTimestampOfLastMessageBeforeTruncation == nil ? .ok : .listingTruncated,
                durationOfTheServerSessionTokenRequest: durationOfTheServerSessionTokenRequest,
                durationOfTheRequest: durationOfTheRequest,
                durationOfTheSaveAndProcess: Date.now.timeIntervalSince(startOfTheSaveAndProcess),
                numberOfMessagesReturned: messagesAndAttachmentsOnServer.count)

            // We saved all the listed messages, requested them to be "marked as listed", and requested their processing. Whether the server has more is the
            // caller's business now — this attempt is over either way.

            return .init(outcome: .listed(nextResumePoint: newServerTimestampOfLastMessageBeforeTruncation,
                                          downloadTimestampFromServer: downloadTimestampFromServer),
                         theSessionWasRefreshed: theSessionWasRefreshed)

        }

        // Unreachable: every branch of the loop above either returns or is the invalid-session `continue`, and that one returns on its second pass. Answered
        // rather than left to fall off the end so that the compiler goes on being what notices a new branch.
        assertionFailure()
        return .init(outcome: .theSessionCouldNotBeMadeValid, theSessionWasRefreshed: theSessionWasRefreshed)

    }
    
    
    /// Keeps how long one attempt at listing took, so that the app can show it and a reader can send it to us.
    ///
    /// Every exit of `downloadMessagesAndListAttachments` records exactly one of these, including the ones that failed and the ones that asked for another
    /// attempt: a run of short failures followed by a success is a shape a single duration could not show.
    ///
    /// **Deliberately not awaited.** Listing is how messages arrive, and an instrument has no business standing in the way of the thing it measures — even
    /// briefly, and even though the cost is small beside a network round trip. Nothing depends on the order the timings land in, because they carry their
    /// own date and are sorted on the way out.
    private func recordTimingOfTheListing(trigger: ObvServerRequestTiming.Trigger, outcome: ObvServerRequestTiming.Outcome, durationOfTheServerSessionTokenRequest: TimeInterval, durationOfTheRequest: TimeInterval, durationOfTheSaveAndProcess: TimeInterval? = nil, numberOfMessagesReturned: Int? = nil) {
        guard let delegateManager else { return }
        let timing = ObvServerRequestTiming(
            date: Date.now,
            request: .downloadMessagesAndListAttachments,
            trigger: trigger,
            outcome: outcome,
            durationOfTheServerSessionTokenRequest: durationOfTheServerSessionTokenRequest,
            durationOfTheRequest: durationOfTheRequest,
            durationOfTheSaveAndProcess: durationOfTheSaveAndProcess,
            numberOfMessagesReturned: numberOfMessagesReturned)
        Task { await delegateManager.serverRequestTimingStore.record(timing) }
    }


    private func performServerDownloadMessagesAndListAttachmentsMethod(ownedCryptoId: ObvCryptoIdentity, sessionToken: Data, currentDeviceUid: UID, serverTimestampOfLastMessageBeforeTruncation: Int?, identityDelegate: ObvIdentityDelegate, flowId: FlowIdentifier) async throws -> ObvServerDownloadMessagesAndListAttachmentsMethod.PossibleReturnStatus {
        
        let method = ObvServerDownloadMessagesAndListAttachmentsMethod(
            ownedIdentity: ownedCryptoId,
            currentDeviceUid: currentDeviceUid,
            sessionToken: sessionToken,
            serverTimestampOfLastMessageBeforeTruncation: serverTimestampOfLastMessageBeforeTruncation,
            flowId: flowId)
        
        method.identityDelegate = identityDelegate

        let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ObvError.invalidServerResponse
        }
        
        guard let returnStatus = ObvServerDownloadMessagesAndListAttachmentsMethod.parseObvServerResponse(responseData: data, flowId: flowId) else {
            assertionFailure()
            throw ObvError.couldNotParseReturnStatusFromServer
        }

        return returnStatus
        
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

        let currentDeviceUID =  try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UID, Error>) in
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

    
    
    private func launchProcessingOfUnprocessedMessages(ownedCryptoIdentity: ObvCryptoIdentity, executionReason: ProcessBatchOfUnprocessedMessagesOperation.ExecutionReason, flowId: FlowIdentifier) throws {
        
        guard let delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            Self.logger.fault("The notification delegate is not set")
            assertionFailure()
            throw ObvError.theNotificationDelegateIsNotSet
        }
        
        guard let processDownloadedMessageDelegate = delegateManager.processDownloadedMessageDelegate else {
            Self.logger.fault("The processDownloadedMessageDelegate is not set")
            assertionFailure()
            throw ObvError.theProcessDownloadedMessageDelegateIsNotSet
        }
                
        Self.logger.info("[\(flowId.shortDebugDescription)] Queuing a ProcessBatchOfUnprocessedMessagesOperation")
        
        let op1 = ProcessBatchOfUnprocessedMessagesOperation(
            ownedCryptoIdentity: ownedCryptoIdentity,
            executionReason: executionReason,
            notificationDelegate: notificationDelegate,
            processDownloadedMessageDelegate: processDownloadedMessageDelegate,
            inbox: delegateManager.inbox,
            logger: Self.logger,
            flowId: flowId)
        // At the queue's normal priority, like every operation on that queue that does not delete rows. See
        // ``ObvNetworkFetchDelegateManager/queueAndAwaitCompositionOfOneContextualOperation(op1:queuePriority:log:flowId:)``.
        let composedOp = try delegateManager.createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        composedOp.completionBlock = { [weak self] in
            Task { [weak self] in
                guard let self else { return }
                await onCompletionOfProcessBatchOfUnprocessedMessagesOperation(op1, flowId: flowId)
            }
        }

        delegateManager.queueSharedAmongCoordinators.addOperation(composedOp)
        
    }
    
    
    private func onCompletionOfProcessBatchOfUnprocessedMessagesOperation(_ op: ProcessBatchOfUnprocessedMessagesOperation, flowId: FlowIdentifier) async {
        
        guard op.isFinished && !op.isCancelled else {
            let reasonForCancel = op.reasonForCancel
            Self.logger.fault("ProcessBatchOfUnprocessedMessagesOperation failed: \(reasonForCancel)")
            assertionFailure()
            return
        }
        
        guard let delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            Self.logger.fault("The notification delegate is not set")
            assertionFailure()
            return
        }

        let postOperationTasksToPerform = op.postOperationTasksToPerform.sorted()
        
        for postOperationTaskToPerform in postOperationTasksToPerform {
            
            switch postOperationTaskToPerform {
                
            case .batchDeleteAndMarkAsListed(ownedCryptoIdentity: let ownedCryptoIdentity):
                
                Self.logger.debug("[\(flowId.shortDebugDescription)] Will batch delete and mark as listed")
                Task {
                    do {
                        try await delegateManager.batchDeleteAndMarkAsListedDelegate.batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId)
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
                
            case .processInboxAttachmentsOfMessage(let messageId):
                
                Task {
                    do {
                        try await delegateManager.downloadAttachmentChunksDelegate.resumeDownloadOfAttachmentsNotAlreadyDownloading(
                            downloadKind: .allDownloadableAttachmentsWithoutSessionForMessage(messageId: messageId),
                            flowId: flowId)
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
                
            case .downloadExtendedPayload(let messageId):
                
                Task {
                    do {
                        try await downloadExtendedMessagePayload(messageId: messageId, flowId: flowId)
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
                
            case .notifyAboutDecryptedApplicationMessage(messages: let messages, flowId: let flowId):
                
                Self.logger.debug("✉️ [\(flowId.shortDebugDescription)] Notifying about \(messages.count) decrypted application messages")
                ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] Notifying the engine about \(messages.count) decrypted application messages")
                
                if let continuation = continuationForAsyncStreamOfObvMessageOrObvOwnedMessage {
                    continuation.yield(messages)
                } else {
                    // The messages will be fetched and streamed when the stream is requested by the app
                }
                
                // We also notify the engine that we received an app message from that contact, so that the engine coordinator
                // can notifiy the identity manager
                Task {
                    let contactIds: [ObvContactIdentifier] = messages.compactMap { message in
                        switch message {
                        case .obvMessage(let obvMessage):
                            return obvMessage.fromContactIdentity
                        case .obvOwnedMessage:
                            return nil
                        }
                    }
                    ObvNetworkFetchNotificationNew.applicationMessagesWhereReceivedFromContacts(contactIds: Set(contactIds))
                        .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)

                }

            }
            
        }
        
        // If more unprocessed messages remain, loop. Otherwise, it might be a good time to delete old current device's pre-keys within the identity manager in case the last listing we untruncated
        
        assert(op.moreUnprocessedMessagesRemain != nil)
        let moreUnprocessedMessagesRemain = op.moreUnprocessedMessagesRemain ?? false

        if moreUnprocessedMessagesRemain {
            
            do {
                try launchProcessingOfUnprocessedMessages(ownedCryptoIdentity: op.ownedCryptoIdentity, executionReason: op.executionReason, flowId: flowId)
            } catch {
                Self.logger.fault("Could not luanch processing of remaining messages to process")
                return
            }
            
        } else {
            
            switch op.executionReason {
            case .untruncatedListPerformed(downloadTimestampFromServer: let downloadTimestampFromServer):
                ObvNetworkFetchNotificationNew.serverAndInboxContainNoMoreUnprocessedMessages(ownedIdentity: op.ownedCryptoIdentity, downloadTimestampFromServer: downloadTimestampFromServer)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
            default:
                break
            }

        }

    }
    
    
    /// When a message has no attachment, it can be received directely on the websocket. In such a case, the websocket manager calls this method.
    func saveMessageReceivedOnWebsocket(message: ObvServerDownloadMessagesAndListAttachmentsMethod.MessageAndAttachmentsOnServer, downloadTimestampFromServer: Date, ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws {
        
        guard let delegateManager else {
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        let op1 = SaveMessagesAndAttachmentsFromServerOperation(
            ownedIdentity: ownedCryptoId,
            listOfMessageAndAttachmentsOnServer: [message],
            downloadTimestampFromServer: downloadTimestampFromServer,
            localDownloadTimestamp: Date(),
            logger: Self.logger,
            flowId: flowId)
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            throw ObvError.failedSaveMessagesAndAttachmentsFromServer
        }

        // The message received on the websocket was saved, so we can tell the server about it: either that we are aware of it, or — when everything the server
        // holds for it is now in our database — that it can delete it outright.
        // We do this asynchronously.
        
        Task {
            do {
                let messageUIDsAndCategories = Self.messageUIDsAndCategories(
                    forSlice: [message],
                    messageUIDsSafelyInDatabase: op1.idsOfMessagesSafelyInDatabase,
                    flowId: flowId)
                try await delegateManager.batchDeleteAndMarkAsListedDelegate.markSpecificMessagesAsListedOrRequestTheirDeletion(ownedCryptoId: ownedCryptoId, messageUIDsAndCategories: messageUIDsAndCategories, flowId: flowId)
            } catch {
                Self.logger.fault("The call to markSpecificMessagesAsListedOrRequestTheirDeletion did fail: \(error.localizedDescription)")
                assertionFailure()
            }
        }

        // We can process the saved message
        
        do {
            let idOfMessageToProcess: ObvMessageIdentifier = .init(ownedCryptoId: .init(cryptoIdentity: ownedCryptoId), uid: message.messageUidFromServer)
            try launchProcessingOfUnprocessedMessages(ownedCryptoIdentity: ownedCryptoId, executionReason: .messageReceivedOnWebSocket(idOfMessageToProcess: idOfMessageToProcess), flowId: flowId)
        } catch {
            assertionFailure(error.localizedDescription)
        }
                
    }
    
    
    func removeExpectedContactForReProcessingOperationThenProcessUnprocessedMessages(expectedContactsThatAreNowContacts: Set<ObvContactIdentifier>, flowId: FlowIdentifier) async throws {
        
        guard !expectedContactsThatAreNowContacts.isEmpty else { return }
        
        guard let delegateManager else {
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        let op1 = RemoveExpectedContactForReProcessingOperation(expectedContactsThatAreNowContacts: expectedContactsThatAreNowContacts)
        try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        
        if op1.didRemoveAtLeastOneExpectedContactForReProcessing {
            for ownedCryptoId in Set(expectedContactsThatAreNowContacts.map(\.ownedCryptoId)) {
                try launchProcessingOfUnprocessedMessages(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, executionReason: .removedExpectedContactOfPreKeyMessage, flowId: flowId)
            }
        }

    }
    
}


// MARK: - Deciding what to tell the server about each listed message

extension MessagesCoordinator {

    /// Decides, for each message of a listing we have just saved, whether to tell the server that we are aware of it or that it can delete it.
    ///
    /// A message can be deleted from the server as soon as its row is committed when **everything the server holds for it is already in our database**. That is
    /// the case exactly when it has no attachment and no extended payload:
    /// - an attachment's bytes are fetched separately, chunk by chunk, so the server must keep the message until the last one has arrived;
    /// - an extended payload (a link preview, say) is fetched separately too, by `ObvServerDownloadMessageExtendedPayloadMethod`, keyed on the message UID and
    ///   needing a key that only exists once the message has been decrypted. Asking the server to delete such a message before its extended payload has been
    ///   downloaded would very likely make that content unavailable for good, and the symptom — previews quietly ceasing to arrive — would be near-impossible
    ///   to attribute afterwards. So those keep the two-step path, and are deleted the ordinary way once the app is done with them.
    ///
    /// Both facts are read from the **server's own listing**, which is the only authoritative account of what the server holds. They are deliberately not read
    /// from our database: `SaveMessagesAndAttachmentsFromServerOperation` continues past an attachment it could not insert, so a row can exist with fewer
    /// attachments than the server has — possibly none — and a database-side test would then delete an attachment we never recorded.
    ///
    /// Messages absent from `messageUIDsSafelyInDatabase` are dropped entirely rather than being reported to the server in either category. The save operation
    /// continues past a message it could not insert, so a UID appearing in the listing is not evidence that we hold the message; saying nothing about it leaves
    /// it to be listed again, which is the only outcome that gives us another chance to save it.
    fileprivate static func messageUIDsAndCategories(forSlice slice: [ObvServerDownloadMessagesAndListAttachmentsMethod.MessageAndAttachmentsOnServer], messageUIDsSafelyInDatabase: Set<UID>, flowId: FlowIdentifier) -> [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory] {

        var messageUIDsAndCategories = [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory]()
        var numberOfDeletionsRequested = 0
        var numberOfMessagesMarkedAsListed = 0
        var numberOfMessagesDropped = 0

        for messageAndAttachmentsOnServer in slice {

            let messageUID = messageAndAttachmentsOnServer.messageUidFromServer
            let numberOfAttachments = messageAndAttachmentsOnServer.attachments.count
            let hasExtendedPayload = messageAndAttachmentsOnServer.hasEncryptedExtendedMessagePayload
            let isSafelyInDatabase = messageUIDsSafelyInDatabase.contains(messageUID)
            let serverHoldsNothingMore = numberOfAttachments == 0 && !hasExtendedPayload

            let category: ObvServerDeleteMessageAndAttachmentsMethod.Category? = isSafelyInDatabase ? (serverHoldsNothingMore ? .requestDeletion : .markAsListed) : nil

            if let category {
                messageUIDsAndCategories.append(.init(messageUID: messageUID, category: category))
                switch category {
                case .requestDeletion: numberOfDeletionsRequested += 1
                case .markAsListed: numberOfMessagesMarkedAsListed += 1
                }
            } else {
                numberOfMessagesDropped += 1
            }

        }

        let summary = "[🚩][\(flowId.shortDebugDescription)] Of the \(slice.count) listed message(s), we ask the server to delete \(numberOfDeletionsRequested), to mark \(numberOfMessagesMarkedAsListed) as listed, and say nothing about \(numberOfMessagesDropped) that are not safely in database"
        ObvDisplayableLogs.shared.log(summary)
        Self.logger.info("\(summary, privacy: .public)")

        return messageUIDsAndCategories

    }

}


// MARK: - Downloading extended payload

extension MessagesCoordinator {
    
    private func downloadExtendedMessagePayload(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) async throws {
        
        Self.logger.debug("[\(flowId.shortDebugDescription)] Call to downloadExtendedMessagePayload for message \(messageId.debugDescription)")

        guard let delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        let sessionToken = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: messageId.ownedCryptoIdentity, currentInvalidToken: nil, flowId: flowId).serverSessionToken

        if let cached = extendedPayloadDownloadTasks[messageId] {
            switch cached {
            case .inProgress(task: let task):
                try await task.value
                return
            }
        }
        
        let task = try createTaskToDownloadAndSaveExtendedMessagePayload(messageId: messageId, sessionToken: sessionToken, delegateManager: delegateManager, flowId: flowId)
                
        do {
            extendedPayloadDownloadTasks[messageId] = .inProgress(task: task)
            try await task.value
            extendedPayloadDownloadTasks.removeValue(forKey: messageId)
        } catch {
            extendedPayloadDownloadTasks.removeValue(forKey: messageId)
            throw error
        }
        
    }
    
    
    private func createTaskToDownloadAndSaveExtendedMessagePayload(messageId: ObvMessageIdentifier, sessionToken: Data, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) throws -> Task<Void, Error> {
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            assertionFailure()
            throw ObvError.theNotificationDelegateIsNotSet
        }
        
        return Task {
            
            guard try await shouldDownloadExtendedPayloadOfMessage(messageId: messageId, delegateManager: delegateManager, flowId: flowId) else { return }
            
            let method = ObvServerDownloadMessageExtendedPayloadMethod(messageId: messageId, token: sessionToken, flowId: flowId)
            method.identityDelegate = delegateManager.identityDelegate
            
            let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ObvError.invalidServerResponse
            }
            
            guard let returnStatus = ObvServerDownloadMessageExtendedPayloadMethod.parseObvServerResponse(responseData: data, using: Self.log) else {
                assertionFailure()
                throw ObvError.couldNotParseReturnStatusFromServer
            }

            let encryptedExtendedMessagePayload: EncryptedData
            
            switch returnStatus {
            case .invalidSession:
                failedAttemptsCounterManager.reset(counter: .downloadOfExtendedMessagePayload(messageId: messageId))
                let newSessionToken = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: messageId.ownedCryptoIdentity, currentInvalidToken: sessionToken, flowId: flowId).serverSessionToken
                let newTask = try createTaskToDownloadAndSaveExtendedMessagePayload(messageId: messageId, sessionToken: newSessionToken, delegateManager: delegateManager, flowId: flowId)
                try await newTask.value
                return
            case .extendedContentUnavailable:
                failedAttemptsCounterManager.reset(counter: .downloadOfExtendedMessagePayload(messageId: messageId))
                return
            case .generalError:
                let delay = failedAttemptsCounterManager.incrementAndGetDelay(.downloadOfExtendedMessagePayload(messageId: messageId))
                os_log("Will retry the call to createTaskToDownloadAndSaveExtendedMessagePayload in %f seconds", log: Self.log, type: .error, Double(delay) / 1000.0)
                await retryManager.waitForDelay(milliseconds: delay)
                let newTask = try createTaskToDownloadAndSaveExtendedMessagePayload(messageId: messageId, sessionToken: sessionToken, delegateManager: delegateManager, flowId: flowId)
                try await newTask.value
                return
            case .ok(let _encryptedExtendedMessagePayload):
                encryptedExtendedMessagePayload = _encryptedExtendedMessagePayload
            }
            
            // If we reach this point, the extended message payload of the message was downloaded from the server and we should save it
            
            let obvMessageOrObvOwnedMessage = try await decryptAndSaveExtendedMessagePayload(messageId: messageId, encryptedExtendedMessagePayload: encryptedExtendedMessagePayload, flowId: flowId)
            
            if let obvMessageOrObvOwnedMessage {
                ObvNetworkFetchNotificationNew.downloadingMessageExtendedPayloadWasPerformed(message: obvMessageOrObvOwnedMessage, flowId: flowId)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
            }

        }
        
    }
    
    
    private func shouldDownloadExtendedPayloadOfMessage(messageId: ObvMessageIdentifier, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) async throws -> Bool {
        
        guard let contextCreator = delegateManager.contextCreator else {
            assertionFailure()
            throw ObvError.theContextCreatorIsNotSet
        }
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            contextCreator.performBackgroundTask { context in
                do {
                    guard let message = try InboxMessage.get(messageId: messageId, within: context) else {
                        return continuation.resume(returning: false)
                    }
                    let shouldDownload = message.hasEncryptedExtendedMessagePayload && (message.extendedMessagePayload == nil) && message.extendedMessagePayloadKey != nil
                    return continuation.resume(returning: shouldDownload)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
}


// MARK: - URLSessionDataDelegate

extension MessagesCoordinator { //}: URLSessionDataDelegate {
    
    /// When receiving an encrypted extended message payload from the server, we call this method to fetch the message from database, use the decryption key to decrypt the
    /// extended payload, and store the decrypted payload back to database
    private func decryptAndSaveExtendedMessagePayload(messageId: ObvMessageIdentifier, encryptedExtendedMessagePayload: EncryptedData, flowId: FlowIdentifier) async throws -> ObvMessageOrObvOwnedMessage? {
        
        guard let delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        let op1 = DecryptAndSaveExtendedMessagePayloadOperation(messageId: messageId, encryptedExtendedMessagePayload: encryptedExtendedMessagePayload, inbox: delegateManager.inbox)
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            throw ObvError.failedDecryptAndSaveExtendedMessagePayload
        }
        
        return op1.obvMessageOrObvOwnedMessage
        
    }
    
}


// MARK: - ObvMessageOrObvOwnedMessage stream management

extension MessagesCoordinator {
    
    private func replaceContinuationForAsyncStreamOfObvMessageOrObvOwnedMessage(by newContinuation: AsyncStream<[ObvTypes.ObvMessageOrObvOwnedMessage]>.Continuation) {
        if let continuation = self.continuationForAsyncStreamOfObvMessageOrObvOwnedMessage {
            continuation.finish()
        }
        continuationForAsyncStreamOfObvMessageOrObvOwnedMessage = newContinuation
    }
        
    
    private func getObjectIDsOfInboxMessagesToBeProcessedByApp() async throws -> [NSManagedObjectID] {
        guard let delegateManager else {
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        guard let contextCreator = delegateManager.contextCreator else {
            assertionFailure()
            throw ObvError.theContextCreatorIsNotSet
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[NSManagedObjectID], any Error>) in
            contextCreator.performBackgroundTask { context in
                do {
                    let objectIDsOfProcessableInboxMessages: [NSManagedObjectID] = try InboxMessage.getObjectIDsOfInboxMessagesToBeProcessedByApp(within: context)
                    return continuation.resume(returning: objectIDsOfProcessableInboxMessages)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    private func getObvMessageOrObvOwnedMessagesToBeProcessedByApp(inboxMessageObjectIDs: [NSManagedObjectID]) async throws -> [ObvMessageOrObvOwnedMessage] {
        guard let delegateManager else {
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        guard let contextCreator = delegateManager.contextCreator else {
            assertionFailure()
            throw ObvError.theContextCreatorIsNotSet
        }
        let inbox = delegateManager.inbox
        return await withCheckedContinuation { (continuation: CheckedContinuation<[ObvMessageOrObvOwnedMessage], Never>) in
            contextCreator.performBackgroundTask { context in
                var messages = [ObvMessageOrObvOwnedMessage]()
                for objectID in inboxMessageObjectIDs {
                    do {
                        if let obvMessageOrObvOwnedMessage = try InboxMessage.getObvMessageOrObvOwnedMessageToBeProcessedByApp(inboxMessageObjectID: objectID, inbox: inbox, within: context) {
                            messages.append(obvMessageOrObvOwnedMessage)
                        }
                    } catch {
                        Self.logger.fault("Could not get processable ObvMessageOrObvOwnedMessage for InboxMessageObjectID: \(objectID)")
                        assertionFailure() // In production, continue with the next item
                    }
                }
                assert(messages.count == inboxMessageObjectIDs.count)
                return continuation.resume(returning: messages)
            }
        }
    }
    
}


// MARK: - Errors

extension MessagesCoordinator {
    
    enum ObvError: Error {
        case theDelegateManagerIsNotSet
        case theContextCreatorIsNotSet
        case failedDecryptAndSaveExtendedMessagePayload
        case failedSaveMessagesAndAttachmentsFromServer
        case theIdentityDelegateIsNotSet
        case invalidServerResponse
        case couldNotParseReturnStatusFromServer
        case theNotificationDelegateIsNotSet
        case theProcessDownloadedMessageDelegateIsNotSet
    }
    
}


// MARK: - Private helpers

fileprivate extension Task<Void, Error> {
    
    var shortDebugDescription: String {
        return "<\(self.hashValue & 0xFF)>"
    }
    
}
