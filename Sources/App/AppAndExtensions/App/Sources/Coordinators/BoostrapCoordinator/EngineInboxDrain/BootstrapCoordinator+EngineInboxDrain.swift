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
import os
import OSLog
import ObvTypes
import OlvidUtils
import ObvAppCoreConstants
import ObvUICoreData
import ObvAppTypes


// MARK: - Draining the engine's inbox for as long as we are given

extension BootstrapCoordinator {

    /// Starts an ordinary listing and watches the inbox empty, until there is nothing left, the deadline passes, or somebody asks us to stop.
    ///
    /// **It drives nothing, and that is the design.** Listing fetches the messages; the app decrypts and stores them; and as the app finishes with each one
    /// the engine marks it and fires the batch deletion itself — see `ObvNetworkFetchManagerImplementation.markMessageForDeletion`. The whole chain runs
    /// without help. What this adds is a reason for the device to stay awake while it happens, and an account of what it achieved.
    ///
    /// **So it is a loop because progress can only be observed, never awaited.** `downloadAllMessagesForOwnedIdentities()` returns at the end of the
    /// *listing*; the processing of what it found is enqueued and never awaited; and nothing posts an aggregate *we are finished*. Counting what is left is
    /// the only way to know, which is what the two existing background-fetch call sites approximate with `try await Task.sleep(seconds: 2)`.
    ///
    /// **The sweep is deliberately not driven from here.** A stall was once measured in which 100'000 forged rows left 69'599 marked and not going, and a
    /// relaunch cleared a hundred and stalled again. That stall has never been explained, and driving the sweep ourselves would hide it rather than fix it.
    /// A run here is also an observation of whether the normal path works.
    ///
    /// **Nothing here can be cancelled, and the loop is built around that.** No part of the engine's fetch path checks `Task.isCancelled`, so a listing or a
    /// processing round in flight runs to its end. All a stop request can do is stop us asking for *more*. Every row involved is persistent, so an
    /// interruption at any point loses nothing and the next window carries on from where this one stopped.
    ///
    /// - Parameters:
    ///   - deadline: when to stop asking for more work. Checked between every step and inside every poll.
    ///   - run: the run's live state — the way a background processing task's expiration handler asks this to stop, and the way it finds out what was
    ///   achieved without waiting for this to return.
    ///   - trigger: what asked for this drain. Recorded, so that a figure in the diagnostics panel can be read knowing whether a reader was watching.
    func drainEngineInbox(deadline: Date, run: ObvInboxDrainInProgress, trigger: ObvInboxDrainReport.Trigger) async -> ObvInboxDrainReport {

        let startedAt = Date.now

        // Taken and claimed as one act, as `syncMessageIdsKeptForLaterIfRequired` does and for the same reason: this is reachable from a background
        // processing task and from the reader asking in the settings, on whatever executor called it. Two drains at once would both be listing and both be
        // counting, and neither could make sense of what it measured. (Unlike that sync, nothing runs this when the app appears — it needs a window, or a
        // reader who has gone looking for it.)
        let thisDrainIsOurs = isDrainingTheEngineInboxInProgress.withLock { isInProgress in
            guard !isInProgress else { return false }
            isInProgress = true
            return true
        }
        guard thisDrainIsOurs else {
            Self.logger.notice("🤿 A drain of the engine's inbox is already running. Standing aside.")
            ObvDisplayableLogs.shared.log("🤿 A drain of the engine's inbox is already running. Standing aside.")
            var report = run.latestReport
            report.stopReason = .anotherDrainWasAlreadyRunning
            run.publish(report)
            return report
        }
        defer { isDrainingTheEngineInboxInProgress.withLock { $0 = false } }

        var report = run.latestReport

        // The baseline. Both of the claims this run will make are differences against it: what the app finished with, and what left the store.
        //
        // Asked again rather than given up on, against the same bound ``ObvInboxDrainRoundDecision`` uses mid-run. It is taken in the first moments of a
        // background launch, over a store three extensions also write to, which is the busiest that store ever is. Ending the window on one refusal cost
        // the night: `theCountsCouldNotBeRead` is the ending ``ObvInboxDrainWindowSchedule`` stands down six hours for, over a count the next second would
        // have answered.
        var countsAtStart: ObvInboxCounts?
        while true {
            countsAtStart = await inboxCounts(alsoCountingMessagesWaitingForAManualDownload: true, alsoCountingMessagesOfInactiveProfiles: true, reportingInto: &report)
            if countsAtStart != nil { break }
            // Asked *after* an attempt rather than before one, so that a reading is always taken however little is left: this is the reading that decides
            // whether the run happens at all, and it costs tens of milliseconds.
            guard !run.isStopRequested,
                  Date.now < deadline,
                  Date.now.timeIntervalSince(startedAt) < ObvInboxDrainRoundDecision.howLongTheCountsMayBeUnreadableBeforeGivingUp else { break }
            // Published between attempts, so that a reader watching the settings screen sees the seconds and the failures climb rather than half a minute of
            // a screen with nothing on it.
            report.secondsUsed = Date.now.timeIntervalSince(startedAt)
            run.publish(report)
            try? await Task.sleep(seconds: Self.intervalBetweenPolls)
        }

        guard let countsAtStart else {
            // Three ways out of that loop, and they do not want the same next window. Only a store that went on refusing for the whole bound earns the
            // six-hour ending; the rule says which is which, where a test can reach it.
            report.stopReason = ObvInboxDrainRoundDecision.reasonTheBaselineCouldNotBeTaken(isStopRequested: run.isStopRequested, now: .now, deadline: deadline)
            // In a background window a stop request is the expiration handler, which is the system taking the window and not a fault, and the sentence the
            // reader is shown says one or the other.
            report.endedOnTheExpirationHandler = run.theWindowExpired
            report.secondsUsed = Date.now.timeIntervalSince(startedAt)
            run.publish(report)
            logTheDrainReport(report, note: "no baseline counts, after \(report.numberOfTimesTheCountsCouldNotBeRead) attempt(s)")
            return report
        }
        report.record(countsAtStart: countsAtStart)
        // Recorded as the end as well, so that a run which does nothing at all reports the truth — nothing moved — rather than a nil that reads as a
        // measurement that failed.
        report.record(countsAtEnd: countsAtStart)
        report.notePeakFootprint()

        // Recorded before any reason to stop is consulted, so that a run which ends before its first round still says what the memory was, and so that a
        // positive reading marks this process as memory-limited from the outset, which is what lets a later nought be believed.
        report.record(headroom: ObvProcessMemory.available())
        run.publish(report)

        Self.logger.notice("🤿 Starting a drain of the engine's inbox. \(countsAtStart.descriptionForLogs, privacy: .public) deadline in \(Int(deadline.timeIntervalSinceNow), privacy: .public)s \(ObvProcessMemory.description(), privacy: .public)")
        ObvDisplayableLogs.shared.log("🤿 Starting a drain of the engine's inbox (\(trigger.rawValue)). \(countsAtStart.descriptionForLogs) deadline in \(Int(deadline.timeIntervalSinceNow))s \(ObvProcessMemory.description())")

        // This runs before the listing, in a background window as well as on a tap. For a device carrying this backlog, clearing it
        // is what helps the reader; a listing meanwhile is worth little. Once it is cleared, the pass costs one bounded fetch that
        // finds nothing, so the order stops mattering.
        await discardStaleSharedSettingsMessagesOnHold(run: run, deadline: deadline, reportingInto: &report)
        report.secondsUsed = Date.now.timeIntervalSince(startedAt)
        run.publish(report)

        // The figure a reader means by *did it work*. Every other number here describes the engine's inbox, which this loop keeps near empty on purpose, so
        // a run that fetches a backlog off the server begins and ends at nought there. Nothing removes messages from the app's store while a drain runs, so
        // the difference between the two ends of this is a genuine flow.
        report.numberOfMessagesHeldByTheAppAtStart = numberOfMessagesHeldByTheApp()

        // Seeded as a *poll* reads it, not as the baseline did: `nothingMovedSince` compares whole structs, so a baseline carrying the stranded count against
        // polls that do not would make round one report movement whatever the inbox did.
        var countsAtTheEndOfThePreviousRound = ObvInboxCounts(
            numberOfMessages: countsAtStart.numberOfMessages,
            numberOfMessagesNotYetDecrypted: countsAtStart.numberOfMessagesNotYetDecrypted,
            numberOfMessagesAwaitingTheApp: countsAtStart.numberOfMessagesAwaitingTheApp,
            numberOfMessagesMarkedForDeletion: countsAtStart.numberOfMessagesMarkedForDeletion,
            numberOfMessagesWaitingForAManualDownload: countsAtStart.numberOfMessagesWaitingForAManualDownload,
            numberOfMessagesBelongingToAnInactiveOwnedIdentity: nil)

        /// When one of the inbox counts last changed, or nil while the listing is still fetching.
        ///
        /// **Nil rather than a date while the listing runs, so that the clock starts when it returns.** A single large page can take a minute during which
        /// nothing local moves at all, and carrying that minute forward would hand the stop rule a stall the instant the listing came back.
        var whenSomethingLastMoved: Date?

        /// When the counts were last read successfully. **Starts at the baseline, which is a reading that came back** — the run does not get this far
        /// otherwise — so the first poll that fails measures against a real moment rather than against the start of the run.
        var whenTheCountsWereLastRead = Date.now

        // Every way this run can end is named by one function, asked once here and once after each poll, so the endings are a list rather than
        // scattered `break`s. Asked *before* the listing is started: the pass above may have spent the whole window, and a listing cannot be taken
        // back once asked for, so a run that is already over starts none — on borrowed time, in the background, for a report that then said the
        // server still had more.

        var reasonToStop = reasonToStopBeforeAnotherRound(havingRead: countsAtStart,
                                                          isTheFirstRound: true,
                                                          // The baseline came back, so nothing is unreadable, nothing has been watched, and the listing
                                                          // has not had time to report on itself.
                                                          howLongTheCountsHaveBeenUnreadable: nil,
                                                          howLongNothingHasMoved: nil,
                                                          howLongTheListingHasBeenUnableToReachTheServer: nil,
                                                          // Nobody has asked the server anything yet. The first round does not read this.
                                                          theServerHasMore: true,
                                                          deadline: deadline,
                                                          run: run,
                                                          reportingInto: &report)

        // **Started once, and never awaited from the loop.** `downloadAllMessagesForOwnedIdentities` returns only once a listing has come back untruncated,
        // so awaiting it here would *be* the whole run. Started in a task instead, with its completion recorded, so the loop can ask *has the listing
        // finished* between two polls.
        //
        // It is the same call pull-to-refresh makes: one listing path, which this run joins rather than competes with. The engine serialises listings per
        // owned identity, so a reader who taps this while the app is already fetching gets one listing, not two.
        //
        // **It does not report failure.** A listing that cannot reach the server waits out an uncapped back-off and tries again, for ever, without
        // returning and without throwing. So `theListingHasFinished` staying false means either a large backlog or a server that has gone, and the engine's
        // own timings are what tell the two apart, below.
        let theListingHasFinished = OSAllocatedUnfairLock<Bool>(initialState: false)
        let theListingWasStarted = reasonToStop == nil
        if theListingWasStarted {
            Task { [obvEngine] in
                defer { theListingHasFinished.withLock { $0 = true } }
                do {
                    try await obvEngine.downloadAllMessagesForOwnedIdentities(trigger: trigger == .backgroundProcessingTask ? .theBackgroundProcessingTaskDrainingTheInbox : .theAppAskedForIt)
                } catch {
                    // Only the setup can throw — a missing delegate, an identity that is not active. The listing's own failures never reach here.
                    Self.logger.error("🤿 The listing could not be started: \(error.localizedDescription, privacy: .public)")
                    ObvDisplayableLogs.shared.log("🤿 The listing could not be started: \(error.localizedDescription)")
                }
            }
        }

        while reasonToStop == nil {

            report.numberOfPolls += 1
            let round = report.numberOfPolls

            // Published every poll, not only at the end: a screen watching the run reads this to know whether the server still has more, and a value
            // written once after the loop would say *nothing more* from the first second. The listing is started before the first poll, so *has more* is
            // simply *the listing has not returned*; before it starts, which is the whole of the stale-settings pass, the flag is nil.
            report.theServerStillHadMoreAtTheEnd = !theListingHasFinished.withLock { $0 }
            report.secondsUsed = Date.now.timeIntervalSince(startedAt)
            run.publish(report)

            // The whole of a round: wait, then look. The listing is fetching, the app is decrypting and storing, and the engine removes each row once the
            // app says it is done with it, none of which needs driving from here.
            try? await Task.sleep(seconds: Self.intervalBetweenPolls)

            // The stranded count is not asked for here: it cannot change while a run is in flight, no index can narrow it, and the baseline took it once.
            let counts = await inboxCounts(alsoCountingMessagesWaitingForAManualDownload: true, alsoCountingMessagesOfInactiveProfiles: false, reportingInto: &report)
            report.notePeakFootprint()

            // How long the refusals have gone on is what the rule is given, not whether this one reading failed: over a store three extensions also write
            // to, one refusal says nothing, and the next reading a second later usually comes back.
            if counts != nil { whenTheCountsWereLastRead = Date.now }
            let howLongTheCountsHaveBeenUnreadable: TimeInterval? = counts == nil ? Date.now.timeIntervalSince(whenTheCountsWereLastRead) : nil

            var whatMoved = "counts=unreadable"

            /// Whether anything at all changed since the previous poll. **A reading we could not take is not stillness**: it says nothing either way, so it
            /// leaves the clock where it is rather than starting it.
            var somethingMoved: Bool?

            if let counts {
                // Asked *before* the previous reading is overwritten, which is the whole reason this sits here rather than below.
                somethingMoved = !counts.nothingMovedSince(countsAtTheEndOfThePreviousRound)

                report.record(countsAtEnd: counts)
                report.numberOfMessagesHeldByTheAppAtEnd = numberOfMessagesHeldByTheApp()
                let messagesProcessedThisRound = max(0, countsAtTheEndOfThePreviousRound.numberOfMessagesAwaitingTheApp - counts.numberOfMessagesAwaitingTheApp)
                let rowsRemovedThisRound = max(0, countsAtTheEndOfThePreviousRound.numberOfMessages - counts.numberOfMessages)
                report.record(messagesProcessedThisRound: messagesProcessedThisRound, rowsRemovedThisRound: rowsRemovedThisRound)

                countsAtTheEndOfThePreviousRound = counts
                whatMoved = "\(counts.descriptionForLogs) processedThisRound=\(messagesProcessedThisRound) rowsRemovedThisRound=\(rowsRemovedThisRound)"
            }

            let listingHasFinished = theListingHasFinished.withLock { $0 }

            // Stillness is only evidence once the listing has finished, so the clock is held at nil until it returns: while a page is being fetched a flat
            // count means the server is slow, not that the work has stopped. A count that changes in either direction is movement.
            if !listingHasFinished {
                whenSomethingLastMoved = nil
            } else if somethingMoved ?? false || whenSomethingLastMoved == nil {
                whenSomethingLastMoved = Date.now
            }
            let howLongNothingHasMoved = whenSomethingLastMoved.map { Date.now.timeIntervalSince($0) }

            // The one fact the listing never reports itself: the engine records a timing for every attempt, including the ones that never got as far as
            // asking, and this reads them. Bounded by the start of this run, so a device that was offline yesterday is not held against a listing that
            // has not yet come back.
            let howLongTheListingHasBeenUnableToReachTheServer = try? await obvEngine.howLongTheListingHasBeenUnableToReachTheServer(since: startedAt)

            let stillness = howLongNothingHasMoved.map { "\(Int($0))s" } ?? "listing"
            // Logged unconditionally, with both terms of each test and not only its verdict: a guard that declines in silence cannot be told apart from
            // one whose circumstance never arose.
            let unreachable = howLongTheListingHasBeenUnableToReachTheServer.map { "\(Int($0))s" } ?? "no"
            let unreadable = howLongTheCountsHaveBeenUnreadable.map { "\(Int($0))s" } ?? "no"
            let line = "🤿 Round \(round): \(whatMoved) listingFinished=\(listingHasFinished) unreachableFor=\(unreachable) countsUnreadableFor=\(unreadable) nothingMovedFor=\(stillness) elapsed=\(Int(Date.now.timeIntervalSince(startedAt)))s \(ObvProcessMemory.description())"
            Self.logger.notice("\(line, privacy: .public)")
            ObvDisplayableLogs.shared.log(line)

            reasonToStop = reasonToStopBeforeAnotherRound(havingRead: counts,
                                                          isTheFirstRound: false,
                                                          howLongTheCountsHaveBeenUnreadable: howLongTheCountsHaveBeenUnreadable,
                                                          howLongNothingHasMoved: howLongNothingHasMoved,
                                                          howLongTheListingHasBeenUnableToReachTheServer: howLongTheListingHasBeenUnableToReachTheServer,
                                                          theServerHasMore: !listingHasFinished,
                                                          deadline: deadline,
                                                          run: run,
                                                          reportingInto: &report)

            // Published at the round boundary, where the figures agree with one another, so that an expiration handler firing during the next round has
            // something true to write down without waiting for us.
            report.theServerStillHadMoreAtTheEnd = !listingHasFinished
            report.secondsUsed = Date.now.timeIntervalSince(startedAt)
            run.publish(report)

        }

        // The return receipts this run produced are rows, and a row is sent by a sweep. Without this, a background run would leave them for the next
        // foreground, hours away. Swept after the loop, since what is in flight at any other moment is on its way out anyway.
        //
        // Given a deadline of its own: one of the ways the loop ends *is* the window's deadline, and a sweep with a spent deadline does nothing. `max` lets
        // a window that ended early hand over what it has left, and leaves the reader's run, whose deadline is `.distantFuture`, untouched.
        //
        // Not asked for once the system has taken the window back: anything started after the expiration handler has fired runs on borrowed time.
        if run.theWindowExpired {
            let line = "🤿 The window expired, so this run's return receipts are left for the next sweep"
            Self.logger.notice("\(line, privacy: .public)")
            ObvDisplayableLogs.shared.log(line)
        } else {
            let deadlineForTheSweep = max(deadline, Date.now.addingTimeInterval(Self.secondsGrantedToTheSweepOfReturnReceipts))
            await obvEngine.drainReturnReceiptsToSend(until: deadlineForTheSweep)
        }

        // Non-nil by the loop's own condition — the loop runs exactly while this is nil.
        if let reasonToStop {
            report.stopReason = reasonToStop
        }
        // Recorded whatever the ending, because it is what stops a clear inbox buying six hours: a window that ran out of time usually has nothing left
        // locally and a server that still holds a backlog. Left nil by a run that never started the listing, since nobody asked the server anything and
        // the flag says so. Whether the system took the window is asked of the run, since *somebody asked us to stop* and *the window expired* are
        // different facts about it.
        if theListingWasStarted {
            report.theServerStillHadMoreAtTheEnd = !theListingHasFinished.withLock { $0 }
        }
        report.endedOnTheExpirationHandler = run.theWindowExpired
        report.secondsUsed = Date.now.timeIntervalSince(startedAt)
        run.publish(report)

        logTheDrainReport(report, note: nil)

        return report

    }


    // MARK: Every way this can end

    /// Why the drain should not run another round, or nil if it should. The rule is ``ObvInboxDrainRoundDecision``, where a unit test can reach it; this
    /// reads the run's stop flag and the memory available now, records the second, and hands the rest over.
    private func reasonToStopBeforeAnotherRound(havingRead counts: ObvInboxCounts?,
                                                isTheFirstRound: Bool,
                                                howLongTheCountsHaveBeenUnreadable: TimeInterval?,
                                                howLongNothingHasMoved: TimeInterval?,
                                                howLongTheListingHasBeenUnableToReachTheServer: TimeInterval?,
                                                theServerHasMore: Bool,
                                                deadline: Date,
                                                run: ObvInboxDrainInProgress,
                                                reportingInto report: inout ObvInboxDrainReport) -> ObvInboxDrainReport.StopReason? {

        // Recorded before it is read back: a nought means nothing until a positive reading has been seen, and this reading may be that one.
        let headroom = ObvProcessMemory.available()
        report.record(headroom: headroom)

        return ObvInboxDrainRoundDecision.reasonToStopBeforeAnotherRound(.init(
            counts: counts,
            howLongTheCountsHaveBeenUnreadable: howLongTheCountsHaveBeenUnreadable,
            isTheFirstRound: isTheFirstRound,
            theServerHasMore: theServerHasMore,
            howLongNothingHasMoved: howLongNothingHasMoved,
            howLongTheListingHasBeenUnableToReachTheServer: howLongTheListingHasBeenUnableToReachTheServer,
            isStopRequested: run.isStopRequested,
            deadline: deadline,
            now: .now,
            headroom: headroom,
            weKnowThisProcessIsMemoryLimited: report.weKnowThisProcessIsMemoryLimited))

    }


    // MARK: The stale shared-settings pass

    /// Discards the discussion-shared-settings messages that 4.3.1 put on hold, for every profile.
    ///
    /// Nothing else can do this: `isOnHold` is one-way, and a held message is in neither work set, so only a caller that holds its
    /// identifier can move it.
    ///
    /// Advance the offset by the number of rows kept, not by the page size. Discarded rows are deleted, so the table shrinks under
    /// the walk, and a page-sized step would skip one row for every row deleted. Stopping halfway costs nothing: what is discarded
    /// is gone, and the next run walks a shorter table.
    private func discardStaleSharedSettingsMessagesOnHold(run: ObvInboxDrainInProgress, deadline: Date, reportingInto report: inout ObvInboxDrainReport) async {

        // `report.secondsUsed` is the run's clock and must stay that; what this pass costs is its own figure.
        let whenThePassBegan = Date.now

        var examined = 0
        var discarded = 0

        // The one way out, taken whichever way this returns. It says the pass is over, which the counts alone cannot: an early exit leaves fewer rows
        // examined than there were, exactly like a pass still running. And it logs what the pass did, since a pass that found nothing, one that gave up
        // and one that never ran are three different things.
        defer {
            report.noteThatTheStaleSettingsPassEnded()
            run.publish(report)
            let seconds = Int(Date.now.timeIntervalSince(whenThePassBegan))
            Self.logger.notice("🤿 The stale shared settings pass examined \(examined) held message(s) and discarded \(discarded) in \(seconds)s")
            ObvDisplayableLogs.shared.log("🤿 The stale shared settings pass examined \(examined) held message(s) and discarded \(discarded) in \(seconds)s")
        }

        // Every profile, not only the active ones, unlike the counts a drain reads. Nothing here asks a server. And a deactivated
        // profile's held messages are the ones with no other way out: the thirty-day give-up happens after a listing, and listings
        // skip them. They are marked rather than removed, because the batch deletion has no session to ask, which is still better
        // than leaving them held.
        let ownedCryptoIds: [ObvCryptoId]
        do {
            ownedCryptoIds = try obvEngine.getOwnedIdentities(restrictToActive: false).map { $0.cryptoId }
        } catch {
            Self.logger.fault("🤿 Could not obtain the owned identities, so the stale shared settings cannot be discarded: \(error.localizedDescription)")
            assertionFailure()
            return
        }

        // Counted before any row is touched, so that the progress bar has an exact total. This is the only exact total this screen
        // ever has: the listing that follows cannot know how much the server still holds, whereas this is simply how many rows are
        // held right now. The count also decides whether the pass has anything to do at all, which on an ordinary device is its
        // whole cost.
        //
        // A profile whose count is refused is left out of the walk, and the others are walked: the store is busiest at a cold background
        // launch, which is when this runs, and one refusal on one profile is no reason to leave every profile's rows held. The report says
        // the pass stopped early, as every exit that leaves rows held does, so the next window is asked for in a minute rather than six
        // hours, and the total stays exact for the profiles that are walked. A refusal is not a zero: `try?` here read as a device holding
        // nothing, said nothing about it, and stood the schedule down for six hours over a backlog the run had never looked at.
        var toExamine = 0
        var ownedCryptoIdsWhoseHeldMessagesWereCounted: [ObvCryptoId] = []
        for ownedCryptoId in ownedCryptoIds {
            do {
                toExamine += try await appInboxService.countMessageIdentifiersForLater(ownedCryptoId: ownedCryptoId)
                ownedCryptoIdsWhoseHeldMessagesWereCounted.append(ownedCryptoId)
            } catch {
                Self.logger.error("🤿 Could not count the held messages of a profile, so its stale shared settings are left for the next run: \(error.localizedDescription, privacy: .public)")
                ObvDisplayableLogs.shared.log("🤿 Could not count the held messages of a profile, so its stale shared settings are left for the next run: \(error.localizedDescription)")
                report.theStaleSettingsPassStoppedEarly = true
            }
        }
        // A device with nothing held stays on "not measured"; one whose only counts were refused returns here too, with the flag set above.
        guard toExamine > 0 else { return }
        report.numberOfHeldMessagesToExamine = toExamine
        // Nought from here, not nil: the screen shows these two rows as soon as there is a total, rather than once the first page has
        // landed, which on a busy device can be minutes away.
        report.numberOfHeldMessagesExamined = 0
        report.numberOfStaleSettingsMessagesDiscarded = 0
        run.publish(report)

        for ownedCryptoId in ownedCryptoIdsWhoseHeldMessagesWereCounted {

            var kept = 0

            while true {

                // The memory floor is checked here too, not only by the round decision. This runs before the first round, and in a
                // background window, where the memory limit is tighter than in the foreground app. Stopping while we still can
                // leaves the work resumable; being killed for memory leaves nothing in the report to say what happened.
                let headroom = ObvProcessMemory.available()
                report.record(headroom: headroom)
                let outOfMemory = ObvInboxDrainRoundDecision.weAreOutOfMemoryHeadroom(given: headroom, knownToBeMemoryLimited: report.weKnowThisProcessIsMemoryLimited)

                guard !run.isStopRequested, Date.now < deadline, !outOfMemory else {
                    // Tested in the order the guard tests them, so the sentence names what actually decided.
                    let why: String
                    if run.isStopRequested {
                        why = "it was asked to stop"
                    } else if Date.now >= deadline {
                        why = "the deadline passed"
                    } else {
                        why = "too little memory is left"
                    }
                    Self.logger.notice("🤿 The stale shared settings pass stops early after \(Int(Date.now.timeIntervalSince(whenThePassBegan)))s because \(why), having examined \(examined) held message(s) and discarded \(discarded)")
                    // Said in the report, because the schedule cannot tell from the counts: the rows left are held, and held rows are in no count.
                    report.theStaleSettingsPassStoppedEarly = true
                    return
                }

                // Each of the four steps below is announced before it is awaited, and published, so the screen names the step a page is
                // on and a report stored mid-page names the step it was on. How long each took is read back from the report before the
                // next step overwrites it.

                report.begin(stepOfTheStaleSettingsPass: .readingIdentifiers)
                run.publish(report)

                let messageIds: [ObvMessageIdentifier]
                do {
                    messageIds = try await appInboxService.fetchMessageIdentifiersForLater(ownedCryptoId: ownedCryptoId, fetchOffset: kept, fetchLimit: Self.pageOfHeldMessages)
                } catch {
                    // This profile's walk is abandoned, and the next profile's is not. A page left unread costs nothing beyond the next run walking it —
                    // provided the report says the pass stopped early, since the rows left are held and held rows are in no count. Each of the four
                    // exits below says so.
                    Self.logger.fault("🤿 Could not read a page of held message identifiers, so this profile is left for the next run: \(error.localizedDescription)")
                    assertionFailure()
                    report.theStaleSettingsPassStoppedEarly = true
                    break
                }
                guard !messageIds.isEmpty else { break }
                let secondsReadingIdentifiers = report.secondsOnTheCurrentStepOfTheStaleSettingsPass ?? 0

                report.begin(stepOfTheStaleSettingsPass: .readingPayloads(count: messageIds.count))
                run.publish(report)

                let payloads: [ObvMessageIdentifier: Data]
                do {
                    payloads = try await obvEngine.getPayloadsOfMessagesOnHold(messageIds: messageIds)
                } catch {
                    Self.logger.fault("🤿 Could not read the payloads of a page of held messages, so this profile is left for the next run: \(error.localizedDescription)")
                    assertionFailure()
                    report.theStaleSettingsPassStoppedEarly = true
                    break
                }
                let secondsReadingPayloads = report.secondsOnTheCurrentStepOfTheStaleSettingsPass ?? 0

                // A message whose payload could not be read counts as kept, so the offset moves past it and the walk cannot stall.
                let messageIdsToDiscard = messageIds.filter { messageId in
                    guard let payload = payloads[messageId] else { return false }
                    guard let persistedItemJSON = try? PersistedItemJSON.jsonDecode(payload) else { return false }
                    return persistedItemJSON.isADiscussionSharedConfigurationAndNothingElse
                }

                examined += messageIds.count

                // Nil, not nought, for a page with nothing to discard: the two steps did not run.
                var secondsMarkingForDeletion: TimeInterval?
                var secondsForgettingIdentifiers: TimeInterval?

                if messageIdsToDiscard.isEmpty {

                    kept += messageIds.count

                } else {

                    report.begin(stepOfTheStaleSettingsPass: .markingForDeletion(count: messageIdsToDiscard.count))
                    run.publish(report)

                    do {
                        try await obvEngine.deleteMessagesAndAttachments(messageIds: messageIdsToDiscard)
                    } catch {
                        Self.logger.fault("🤿 Could not request the deletion of a page of stale shared settings, so this profile is left for the next run: \(error.localizedDescription)")
                        assertionFailure()
                        report.theStaleSettingsPassStoppedEarly = true
                        break
                    }
                    secondsMarkingForDeletion = report.secondsOnTheCurrentStepOfTheStaleSettingsPass ?? 0

                    report.begin(stepOfTheStaleSettingsPass: .forgettingIdentifiers(count: messageIdsToDiscard.count))
                    run.publish(report)

                    let rowsRemoved: Int
                    do {
                        rowsRemoved = try await appInboxService.deleteMessageIdentifiersForLater(messageIds: messageIdsToDiscard)
                    } catch {
                        // The rows may still be there, and `kept` has not moved past them, so the next page we asked for would be the page
                        // we just read. Marking a message for deletion does not end its hold either, so its payload would come back too,
                        // and we would decode and delete the same rows until the deadline. This profile is left for the next run.
                        Self.logger.fault("🤿 Could not delete the identifiers of a page of stale shared settings, so this profile is left for the next run: \(error.localizedDescription)")
                        assertionFailure()
                        report.theStaleSettingsPassStoppedEarly = true
                        break
                    }

                    // The offset advances by what was read minus what was removed, not minus what we asked to remove. The two differ when another
                    // process deleted a row first: counting rows that are gone skips a few, which the next run examines, where counting rows that are
                    // still there hands us the same page for as long as the window lasts.
                    kept += messageIds.count - rowsRemoved
                    secondsForgettingIdentifiers = report.secondsOnTheCurrentStepOfTheStaleSettingsPass ?? 0

                    discarded += messageIdsToDiscard.count

                }

                let page = ObvInboxDrainReport.PageOfTheStaleSettingsPass(examined: messageIds.count,
                                                                          discarded: messageIdsToDiscard.count,
                                                                          secondsReadingIdentifiers: secondsReadingIdentifiers,
                                                                          secondsReadingPayloads: secondsReadingPayloads,
                                                                          secondsMarkingForDeletion: secondsMarkingForDeletion,
                                                                          secondsForgettingIdentifiers: secondsForgettingIdentifiers)
                report.record(pageOfTheStaleSettingsPass: page)
                report.record(heldMessagesExamined: messageIds.count,
                              staleSettingsMessagesDiscarded: messageIdsToDiscard.count,
                              secondsSpentOnTheStaleSettingsPass: Date.now.timeIntervalSince(whenThePassBegan))
                report.notePeakFootprint()
                run.publish(report)
                // One line per page, so a log says where each page's time went and not only how the pass ended.
                Self.logger.notice("🤿 A page of the stale shared settings pass: \(page.descriptionForLogs)")
                ObvDisplayableLogs.shared.log("🤿 A page of the stale shared settings pass: \(page.descriptionForLogs)")

                // A short page is the end of this profile's rows.
                if messageIds.count < Self.pageOfHeldMessages { break }

            }

        }

    }


    // MARK: Reading the counts

    /// How many messages this device holds, or nil if it could not be counted. A figure that cannot be read is one row that says
    /// nothing, never a run that stops.
    private func numberOfMessagesHeldByTheApp() -> Int? {
        var count: Int?
        ObvStack.shared.performBackgroundTaskAndWait { context in
            count = try? PersistedMessage.countAllMessages(within: context)
        }
        return count
    }


    /// - Parameter alsoCountingMessagesWaitingForAManualDownload: whether to ask for the one count that is not a flag count, 72ms against 12–14ms apiece for
    /// the other four, on a store of 81'210 messages with one attachment each.
    ///
    /// The loop passes `true` every poll, deliberately. Without it `ObvInboxCounts.numberOfMessagesStillOwed` falls back to the raw marked-for-deletion
    /// count, which never reaches nought on a device holding one unopened photograph, so a cheap reading is safe but cannot conclude. The cost is about 7%
    /// of a core at one poll a second. If that ever needs to come down, poll cheaply and pay for the fifth count only when the cheap reading says the only
    /// thing left is marked rows.
    private func inboxCounts(alsoCountingMessagesWaitingForAManualDownload: Bool, alsoCountingMessagesOfInactiveProfiles: Bool, reportingInto report: inout ObvInboxDrainReport) async -> ObvInboxCounts? {
        do {
            return try await obvEngine.getInboxCounts(alsoCountingMessagesWaitingForAManualDownload: alsoCountingMessagesWaitingForAManualDownload,
                                                      alsoCountingMessagesOfInactiveProfiles: alsoCountingMessagesOfInactiveProfiles)
        } catch {
            report.numberOfTimesTheCountsCouldNotBeRead += 1
            Self.logger.fault("🤿 Could not read the inbox counts: \(error.localizedDescription, privacy: .public)")
            ObvDisplayableLogs.shared.log("🤿 Could not read the inbox counts: \(error.localizedDescription)")
            return nil
        }
    }








    // MARK: Recording what the run achieved

    private func logTheDrainReport(_ report: ObvInboxDrainReport, note: String?) {
        let line = "🤿 Drain finished: \(report.descriptionForLogs)" + (note.map { " (\($0))" } ?? "")
        Self.logger.notice("\(line, privacy: .public)")
        ObvDisplayableLogs.shared.log(line)
    }


    // MARK: Constants

    /// How often the counts are asked while the listing and the app do their work.
    ///
    /// A poll reads five counts, the fifth of which is 72ms, so once a second is about 7% of a core, and nothing on the screen moves faster than this
    /// anyway. Nothing else is calibrated against it: the bounds that end a run are expressed in seconds, so re-timing this line cannot change what they
    /// mean.
    private static var intervalBetweenPolls: TimeInterval { 1 }

    /// How long the sweep that sends this run's return receipts may take when the window has nothing left to give it.
    ///
    /// Measured from the moment the loop ends rather than taken from the window, because the commonest way the loop ends *is* the window's deadline, and
    /// that run produced the most receipts. Small, because these are seconds beyond a budget already spent: the first pages go out, and the rest is what
    /// the next sweep is for.
    private static var secondsGrantedToTheSweepOfReturnReceipts: TimeInterval { 10 }

    /// How many held messages the stale-settings pass reads in one go.
    ///
    /// This is bounded by what one Core Data save and one page of payloads should hold. Nothing in that pass talks to a server, so
    /// no server limit applies.
    private static var pageOfHeldMessages: Int { 500 }

    // The constants that decide when to stop live on `ObvInboxDrainRoundDecision` with the rule that reads them, so that the two can be tested together.

}
