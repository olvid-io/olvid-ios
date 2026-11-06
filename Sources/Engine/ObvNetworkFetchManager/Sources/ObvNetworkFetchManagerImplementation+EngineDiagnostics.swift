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
import OlvidUtils
import ObvTypes
import ObvCrypto


// MARK: - Describing the state of the inbox, one figure at a time

extension ObvNetworkFetchManagerImplementation {

    /// Figures describing the state of the inbox, streamed as each is found.
    ///
    /// A stream rather than one answer because there are two dozen of these and, on the devices this exists for, that is seconds rather than milliseconds:
    /// a reader watching a screen fill has evidence that something is happening, where a reader watching a spinner has none. It also means a figure that
    /// cannot be computed costs only itself.
    ///
    /// **A fresh stream on every call**, since an `AsyncStream` may be iterated once and the screen showing these can be left and returned to.
    ///
    /// The figures are emitted in a fixed order, so whatever consumes them can group and report them in arrival order without sorting.
    public func getAsyncStreamOfEngineDiagnostics(flowId: FlowIdentifier) -> AsyncStream<ObvEngineDiagnostic> {
        return AsyncStream { continuation in
            let task = Task {
                await collectEngineDiagnostics(yieldingTo: continuation, flowId: flowId)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }


    /// How long the listing has been failing to reach the server, counting only what happened since `since`, or nil if it is reaching it.
    ///
    /// Read from the timings the listing records anyway, which until now nothing read at all. The derivation — and the reason the answer is a duration
    /// rather than a count — is on ``ServerRequestTimingStore/howLongTheListingHasBeenUnableToReachTheServer(since:now:)``.
    public func howLongTheListingHasBeenUnableToReachTheServer(since: Date, now: Date) async -> TimeInterval? {
        await delegateManager.serverRequestTimingStore.howLongTheListingHasBeenUnableToReachTheServer(since: since, now: now)
    }


    /// How much work the inbox still holds — a handful of counts over one context, materialising nothing.
    ///
    /// Deliberately not part of the stream above. That pass reads two dozen figures, one of them a negated subquery over every message's attachments, and
    /// its own comment puts it at seconds rather than milliseconds; a caller polling to see whether a drain is still making progress needs the opposite
    /// bargain. `context.count(for:)` answers from SQLite without loading a row, which matters here more than anywhere: these rows carry their whole
    /// encrypted content inline, and there may be six figures of them.
    ///
    /// **The last two counts are the ones the caller chooses**, being the two that are not flag counts. The fifth was measured at 72ms on a store of
    /// 81'210 messages with one attachment each, against 12–14ms for each of the four. The sixth is a *negated* membership test, so the composite index
    /// on `(rawMessageIdOwnedIdentity, rawMessageIdUid)` cannot narrow it and SQLite scans the table, for a figure that cannot change while a drain runs.
    /// Asked unconditionally, each cost a whole-table scan a second for a number nobody was reading between rounds.
    public func getInboxCounts(alsoCountingMessagesWaitingForAManualDownload: Bool, alsoCountingMessagesOfInactiveProfiles: Bool, flowId: FlowIdentifier) async throws -> ObvInboxCounts {

        guard let contextCreator = delegateManager.contextCreator else { assertionFailure(); throw ObvError.theContextCreatorIsNotSet }
        guard let identityDelegate = delegateManager.identityDelegate else { assertionFailure(); throw ObvError.theIdentityDelegateIsNotSet }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ObvInboxCounts, Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    // **Read in the same context as the counts, so it describes the same instant as they do.** A profile deactivating between this and the
                    // counts below would otherwise produce a reading in which the parts and the total cannot be reconciled by any arithmetic.
                    let activeOwnedIdentities = Array(try identityDelegate.getOwnedIdentities(restrictToActive: true, within: obvContext))

                    // One context for all of them, so they describe the same instant. That matters most for the last two: `stillToBeRemoved` is their
                    // difference, and a difference of two numbers read at two instants is not a count of anything.
                    //
                    // Read as separate counts rather than derived from one another: the states are **not a partition** — a message on hold is in none of
                    // them, and one waiting for a contact is in none of them either — so subtracting any of these from `all` would invent a number.
                    // `notYetDecrypted` is here because a drain that cannot see it reads a freshly-listed backlog as an empty inbox.
                    //
                    // **Every count of *work* is restricted to the active profiles; the count of the *store* is not.** Nothing lists, decrypts, marks or
                    // sweeps a message of an inactive profile, so counting one as work is a claim that something will move it, and nothing will — see
                    // `ObvInboxCounts.numberOfMessagesBelongingToAnInactiveOwnedIdentity`, which is what the restriction takes out and is reported so that
                    // the parts and the total can still be reconciled.
                    let active = InboxMessage.OwnedIdentityScope.theseProfiles(activeOwnedIdentities)
                    continuation.resume(returning: ObvInboxCounts(
                        numberOfMessages: try InboxMessage.count(.all, over: .everyProfile, within: obvContext.context),
                        numberOfMessagesNotYetDecrypted: try InboxMessage.count(.notYetDecrypted, over: active, within: obvContext.context),
                        numberOfMessagesAwaitingTheApp: try InboxMessage.count(.awaitingTheApp, over: active, within: obvContext.context),
                        numberOfMessagesMarkedForDeletion: try InboxMessage.count(.markedForDeletion, over: active, within: obvContext.context),
                        numberOfMessagesWaitingForAManualDownload: alsoCountingMessagesWaitingForAManualDownload
                        ? try InboxMessage.count(.markedForDeletionYetNotDeletableFromTheServer, over: active, within: obvContext.context)
                        : nil,
                        numberOfMessagesBelongingToAnInactiveOwnedIdentity: alsoCountingMessagesOfInactiveProfiles
                        ? try InboxMessage.countOfMessagesBelongingToNoneOf(activeOwnedIdentities, within: obvContext.context)
                        : nil))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

    }


    /// How many of the most recent messages are read when estimating durations. Enough to see a spread, few enough to cost nothing.
    private static var numberOfRecentMessagesConsidered: Int { 200 }

    /// How many individual timings are named in the report, as opposed to summarised. A handful: the point of the summary is that the rest are in it.
    private static var numberOfTimingsNamedIndividually: Int { 3 }


    private func collectEngineDiagnostics(yieldingTo continuation: AsyncStream<ObvEngineDiagnostic>.Continuation, flowId: FlowIdentifier) async {

        let logger = Logger(subsystem: delegateManager.logSubsystem, category: "EngineDiagnostics")

        // Read in memory, before any database work, so that the figures most likely to explain a slow arrival are also the ones we hold soonest.

        let timings = await delegateManager.serverRequestTimingStore.timings(for: .downloadMessagesAndListAttachments)
        let returnReceipts = await delegateManager.webSocketDelegate.getNumbersOfReturnReceiptsSinceLaunch()

        guard let contextCreator = delegateManager.contextCreator else {
            continuation.yield(.couldNotCompute(figure: "Everything from the database", reason: "the context creator is not set"))
            assertionFailure()
            return
        }

        let inbox = delegateManager.inbox
        let identityDelegate = delegateManager.identityDelegate

        await withCheckedContinuation { (finished: CheckedContinuation<Void, Never>) in

            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in

                // One pass over one context, yielding as each figure is found. Note that the pass is not interruptible once begun: cancelling the stream
                // stops it being read and the remaining yields are dropped, but the queries themselves run to the end. They are read-only and bounded,
                // so that costs nothing worth the machinery of stopping them.

                /// Yields the figure, or yields why it could not be computed. A figure we failed to produce is said out loud rather than left out, so that
                /// a line missing from the report cannot be read as a figure nobody asked for.
                func yielding<T>(_ figure: String, _ compute: () throws -> T, _ diagnostic: (T) -> ObvEngineDiagnostic) {
                    do {
                        continuation.yield(diagnostic(try compute()))
                    } catch {
                        logger.error("Could not compute the diagnostic figure '\(figure)': \(error.localizedDescription)")
                        continuation.yield(.couldNotCompute(figure: figure, reason: error.localizedDescription))
                    }
                }

                // Context

                yielding("Profiles", {
                    guard let identityDelegate else { throw ObvError.theIdentityDelegateIsNotSet }
                    // Inactive profiles included, deliberately: a profile being deleted or deactivated is exactly where a stuck backlog hides.
                    return try identityDelegate.getOwnedIdentities(restrictToActive: false, within: obvContext).count
                }, ObvEngineDiagnostic.numberOfProfiles)

                let recentTimestamps = (try? InboxMessage.timestampsOfTheMostRecentMessages(limit: Self.numberOfRecentMessagesConsidered, within: obvContext.context)) ?? []

                // The two clocks are read at what is nearly the same instant — the server states one in its answer and we note the other as we save — so
                // what separates them is very largely the skew between them.
                let skews = recentTimestamps.map { $0.localDownloadTimestamp.timeIntervalSince($0.downloadTimestampFromServer) }
                continuation.yield(.estimatedClockSkewAgainstTheServer(skews.median))

                // Recent listings

                continuation.yield(.numberOfRecordedListings(timings.count))
                continuation.yield(.durationsOfTheListingRequest(
                    median: timings.percentile(0.5, of: \.durationOfTheRequest),
                    ninetieth: timings.percentile(0.9, of: \.durationOfTheRequest),
                    worst: timings.percentile(1, of: \.durationOfTheRequest)))
                continuation.yield(.durationsOfTheSaveAndProcess(
                    median: timings.percentile(0.5, of: \.durationOfTheSaveAndProcess),
                    ninetieth: timings.percentile(0.9, of: \.durationOfTheSaveAndProcess),
                    worst: timings.percentile(1, of: \.durationOfTheSaveAndProcess)))
                continuation.yield(.outcomesOfTheRecordedListings(timings.countPerOutcome()))
                continuation.yield(.slowestRecordedListings(Array(timings.sorted { $0.durationOfTheRequest > $1.durationOfTheRequest }.prefix(Self.numberOfTimingsNamedIndividually))))
                continuation.yield(.mostRecentRecordedListings(Array(timings.suffix(Self.numberOfTimingsNamedIndividually).reversed())))
                // A truncated listing completed a page; only an untruncated one means the server had nothing left to give, which is the stronger statement.
                let lastCompleted = timings.last { $0.outcome == .ok || $0.outcome == .listingTruncated }
                let lastUntruncated = timings.last { $0.outcome == .ok }
                continuation.yield(.timeSinceTheLastCompletedListing(lastCompleted.map { Date.now.timeIntervalSince($0.date) }))
                continuation.yield(.timeSinceTheLastUntruncatedListing(lastUntruncated.map { Date.now.timeIntervalSince($0.date) }))

                // The WebSocket

                continuation.yield(.numberOfReturnReceiptsReceivedOnTheWebSocket(returnReceipts.received))
                continuation.yield(.numberOfDeleteReturnReceiptRequestsSent(returnReceipts.deleteRequestsSent))

                // The inbox, by state

                // Scoped exactly as `getInboxCounts` scopes the same populations, so the two screens can be read side by side. The counts of *work* ask only
                // about the active profiles, because nothing lists, decrypts, marks or sweeps a message of an inactive one; the rows describing the *store*
                // ask about every profile; and `Belonging to an inactive profile` reconciles them. Scoped differently, a device with a deactivated profile
                // showed *Not yet decrypted: 2000* beside *nothing outstanding* and no figure explained the gap.
                //
                // Held as a `Result` rather than defaulted to *every profile* when it cannot be found out: a row meant to be scoped to the active profiles
                // that quietly counts all of them is that discrepancy again, and `yielding` already knows how to say a figure could not be computed.
                // Fetched once for every row about the active profiles, so they describe the same instant.
                let activeProfiles = Result { () -> [ObvCryptoIdentity] in
                    guard let identityDelegate else { throw ObvError.theIdentityDelegateIsNotSet }
                    return Array(try identityDelegate.getOwnedIdentities(restrictToActive: true, within: obvContext))
                }

                /// A count of *work outstanding*, which asks only about the active profiles. The rows describing the store call `yielding` directly with
                /// `.everyProfile`, so which of the two questions a row puts is visible at the call site.
                func yieldingWorkCount(_ figure: String, _ population: InboxMessage.Population, _ diagnostic: (Int) -> ObvEngineDiagnostic) {
                    yielding(figure, { try InboxMessage.count(population, over: .theseProfiles(activeProfiles.get()), within: obvContext.context) }, diagnostic)
                }

                /// The age beside such a count, scoped identically — which is the promise written on ``InboxMessage/Population``.
                func yieldingWorkAge(_ figure: String, _ population: InboxMessage.Population, _ diagnostic: (Date?) -> ObvEngineDiagnostic) {
                    yielding(figure, { try InboxMessage.dateOfTheOldestMessage(in: population, over: .theseProfiles(activeProfiles.get()), within: obvContext.context) }, diagnostic)
                }

                yielding("Inbox messages", { try InboxMessage.count(.all, over: .everyProfile, within: obvContext.context) }, ObvEngineDiagnostic.numberOfInboxMessages)
                yieldingWorkCount("Not yet decrypted", .notYetDecrypted, ObvEngineDiagnostic.numberOfInboxMessagesNotYetDecrypted)
                yieldingWorkCount("Awaiting the app", .awaitingTheApp, ObvEngineDiagnostic.numberOfInboxMessagesAwaitingTheApp)
                yielding("On hold", { try InboxMessage.count(.onHold, over: .everyProfile, within: obvContext.context) }, ObvEngineDiagnostic.numberOfInboxMessagesOnHold)
                yieldingWorkCount("Marked for deletion", .markedForDeletion, ObvEngineDiagnostic.numberOfInboxMessagesMarkedForDeletion)
                yielding("Awaiting a contact", { try InboxMessage.count(.awaitingAContactForReProcessing, over: .everyProfile, within: obvContext.context) }, ObvEngineDiagnostic.numberOfInboxMessagesAwaitingAContact)
                yielding("Marked as listed", { try InboxMessage.count(.markedAsListedOnTheServer, over: .everyProfile, within: obvContext.context) }, ObvEngineDiagnostic.numberOfInboxMessagesMarkedAsListedOnTheServer)
                yielding("Deleted from the server", { try InboxMessage.count(.deletedFromTheServer, over: .everyProfile, within: obvContext.context) }, ObvEngineDiagnostic.numberOfInboxMessagesDeletedFromTheServer)
                yielding("With an attachment", { try InboxMessage.count(.withAtLeastOneAttachment, over: .everyProfile, within: obvContext.context) }, ObvEngineDiagnostic.numberOfInboxMessagesWithAtLeastOneAttachment)
                yielding("Belonging to an inactive profile", { try InboxMessage.countOfMessagesBelongingToNoneOf(activeProfiles.get(), within: obvContext.context) }, ObvEngineDiagnostic.numberOfInboxMessagesBelongingToAnInactiveProfile)

                // Ages

                // Each age takes the scope of the count it sits beside, which is the promise written on `Population`: an age and a count of the same
                // population must not be answering about different sets of profiles.
                yieldingWorkAge("Oldest not yet decrypted", .notYetDecrypted, { .ageOfTheOldestInboxMessageNotYetDecrypted(Self.age(of: $0)) })
                yieldingWorkAge("Oldest awaiting the app", .awaitingTheApp, { .ageOfTheOldestInboxMessageAwaitingTheApp(Self.age(of: $0)) })
                yielding("Oldest on hold", { try InboxMessage.dateOfTheOldestMessage(in: .onHold, over: .everyProfile, within: obvContext.context) }, { .ageOfTheOldestInboxMessageOnHold(Self.age(of: $0)) })

                let waitsOnTheServer = recentTimestamps.map { $0.downloadTimestampFromServer.timeIntervalSince($0.messageUploadTimestampFromServer) }
                continuation.yield(.timeSpentOnTheServerBeforeBeingListed(median: waitsOnTheServer.median, worst: waitsOnTheServer.max()))

                // Attachments

                var countPerStatus = [ObvInboxAttachmentStatus: Int]()
                for status in InboxAttachment.Status.allCases {
                    countPerStatus[status.forDiagnostics] = (try? InboxAttachment.count(withStatus: status, within: obvContext.context)) ?? 0
                }
                continuation.yield(.numberOfInboxAttachments(perStatus: countPerStatus))

                yielding("Unmarked attachments on a message marked for deletion", {
                    try InboxAttachment.Status.allCases
                        .filter { $0 != .markedForDeletion }
                        .reduce(0) { try $0 + InboxAttachment.count(withStatus: $1, onAMessageMarkedForDeletion: true, within: obvContext.context) }
                }, ObvEngineDiagnostic.numberOfUnmarkedAttachmentsOnAMessageMarkedForDeletion)

                // Messages whose attachments the reader has not asked for. Placed here rather than with the other counts because the predicate behind it is
                // the one expensive query in this pass — a negated subquery over every message's attachments — and everything above it has already arrived
                // by the time it answers.

                yieldingWorkCount("Waiting for a manual download", .markedForDeletionYetNotDeletableFromTheServer, ObvEngineDiagnostic.numberOfMessagesWaitingForAManualDownload)

                var waitingPerStatus = [ObvInboxAttachmentStatus: Int]()
                for status in InboxAttachment.Status.allCases where status != .markedForDeletion {
                    waitingPerStatus[status.forDiagnostics] = (try? InboxAttachment.count(withStatus: status, onAMessageMarkedForDeletion: true, within: obvContext.context)) ?? 0
                }
                continuation.yield(.attachmentsWaitingForAManualDownload(perStatus: waitingPerStatus))

                yielding("Bytes waiting", { try InboxAttachment.sumOfInitialByteCountToDownload(withStatus: .paused, onAMessageMarkedForDeletion: true, within: obvContext.context) }, ObvEngineDiagnostic.bytesWaitingForAManualDownload)
                yieldingWorkAge("Oldest waiting for a manual download", .markedForDeletionYetNotDeletableFromTheServer, { .ageOfTheOldestMessageWaitingForAManualDownload(Self.age(of: $0)) })

                // Disk, last: reading a directory of unknown size is the one thing here that is not a database query.

                continuation.yield(.stateOfTheInboxOnDisk(Self.stateOfTheInbox(at: inbox)))
                yielding("Message directories on disk", {
                    // Every profile: the question is what is on disk, and a deactivated profile's messages are still there.
                    let expected = try InboxMessage.count(.decryptedWithAtLeastOneAttachment, over: .everyProfile, within: obvContext.context)
                    return (Self.numberOfMessageDirectories(in: inbox), expected)
                }, { .messageDirectoriesOnDisk(onDisk: $0.0, expected: $0.1) })

                continuation.yield(.sizeOfTheEngineDatabase(Self.sizeOfTheStores(behind: obvContext.context)))

                // Discussion shared settings, last of all.
                //
                // **The most expensive figure in this pass by a wide margin**, and the only one that reads a *column* rather than counting rows: `messagePayload`
                // is a `Binary` attribute, so no predicate can ask this question and the payloads have to be read and tested one at a time. Everything above has
                // therefore already reached the reader's screen by the time this answers, which is the whole reason the figures are a stream.
                //
                // Not four `yielding` calls: the four rows come from one pass over the payloads, so either all four are known or none of them is.
                do {
                    // Every profile: this describes the store, and a deactivated profile's settings messages are still in it — and are exactly the kind that
                    // accumulate with nothing to move them.
                    let tally = try InboxMessage.tallyOfTheDiscussionSharedSettingsMessages(over: .everyProfile, within: obvContext.context)
                    continuation.yield(.numberOfInboxMessagesThatAreDiscussionSharedSettings(tally.numberOfMessages))
                    continuation.yield(.numberOfDecryptedPayloadsExamined(tally.numberOfPayloadsExamined))
                    continuation.yield(.discussionSharedSettingsPerState(awaitingTheApp: tally.awaitingTheApp, onHold: tally.onHold, markedForDeletion: tally.markedForDeletion))
                    continuation.yield(.ageOfTheOldestDiscussionSharedSettingsMessage(Self.age(of: tally.dateOfTheOldest)))
                } catch {
                    logger.error("Could not compute the diagnostic figure 'Discussion shared settings': \(error.localizedDescription)")
                    continuation.yield(.couldNotCompute(figure: "Discussion shared settings", reason: error.localizedDescription))
                }

                finished.resume()

            }

        }

    }


    private static func age(of date: Date?) -> TimeInterval? {
        guard let date else { return nil }
        return Date.now.timeIntervalSince(date)
    }


    /// Whether the inbox can be read at all, told apart from an inbox that is simply empty: a count of zero would say both, and only one of them is a fault.
    private static func stateOfTheInbox(at inbox: URL) -> ObvEngineDiagnostic.StateOfTheInboxOnDisk {
        guard FileManager.default.fileExists(atPath: inbox.path) else { return .isMissing }
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: inbox.path) else { return .cannotBeRead }
        return .holdsEntries(entries.count)
    }


    /// How many bytes the engine's store occupies, counting the write-ahead log and shared-memory files beside it.
    ///
    /// Asked of the coordinator this context is talking to rather than assembled from a path we happen to know: the store's own URL cannot be out of date.
    /// And the three files are added together because only the total means anything — a database that looks small with a very large log beside it is not a
    /// small database, and the log is exactly what grows when saves are not landing.
    ///
    /// Nil rather than zero when nothing could be measured: no database is nought bytes, so a zero would be a lie about a measurement that did not happen.
    private static func sizeOfTheStores(behind context: NSManagedObjectContext) -> Int64? {
        guard let stores = context.persistentStoreCoordinator?.persistentStores, !stores.isEmpty else { return nil }
        var total: Int64 = 0
        var somethingWasMeasured = false
        for store in stores {
            guard let url = store.url, url.isFileURL else { continue }
            for suffixOfACompanionFile in ["", "-wal", "-shm"] {
                let fileURL = URL(fileURLWithPath: url.path + suffixOfACompanionFile)
                guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else { continue }
                total += Int64(size)
                somethingWasMeasured = true
            }
        }
        return somethingWasMeasured ? total : nil
    }


    /// The directories in the inbox that are named as a message's directory is named.
    ///
    /// Matched on the shape of the name, which is the digest of a message identifier written out in full. Anything else in there is not a message's
    /// directory and is not counted, so that the comparison this feeds is between like and like.
    private static func numberOfMessageDirectories(in inbox: URL) -> Int {
        let numberOfCharactersInADigestWrittenInFull = 64
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: inbox.path) else { return 0 }
        return entries.filter({ $0.count == numberOfCharactersInADigestWrittenInFull }).count
    }

}


// MARK: - Helpers

fileprivate extension Array where Element == TimeInterval {

    /// Nil for an empty set rather than zero, since "no measurement" and "no delay" are answers to different questions.
    var median: TimeInterval? {
        guard !isEmpty else { return nil }
        let sorted = self.sorted()
        return sorted[sorted.count / 2]
    }

}


fileprivate extension InboxAttachment.Status {

    /// The status as anything outside the engine sees it.
    var forDiagnostics: ObvInboxAttachmentStatus {
        switch self {
        case .paused: return .paused
        case .resumeRequested: return .resumeRequested
        case .downloaded: return .downloaded
        case .cancelledByServer: return .cancelledByServer
        case .markedForDeletion: return .markedForDeletion
        }
    }

}
