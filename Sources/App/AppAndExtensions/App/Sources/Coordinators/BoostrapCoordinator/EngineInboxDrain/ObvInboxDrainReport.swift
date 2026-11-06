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


/// The live state of one drain: whether it has been asked to stop, and what it has achieved so far.
///
/// Both duties here because one caller needs both at once. A background task's expiration handler must stop the loop *and* write down where it got to — it
/// cannot wait for the loop to return, since `setTaskCompleted` invites the system to suspend the app immediately, and a run that leaves no figures behind
/// looks exactly like one that never happened.
///
/// **Asking to stop is not cancelling.** Nothing in the engine's fetch path checks `Task.isCancelled`, so work in flight runs to its end. This only stops the
/// loop starting more.
///
/// The loop publishes at each round boundary, where the figures are self-consistent, so a report read here may be one round stale — which is why the handler
/// records the ending itself. Under a lock rather than an actor: the readers are a synchronous loop condition and a handler with a tiny budget.
final class ObvInboxDrainInProgress: Sendable {

    private struct State {
        var stopRequested: Bool
        var theWindowExpired: Bool
        var theLoopHasWrittenTheRecord: Bool
        var latestReport: ObvInboxDrainReport
    }

    private let state: OSAllocatedUnfairLock<State>

    init(report: ObvInboxDrainReport) {
        self.state = .init(initialState: .init(stopRequested: false, theWindowExpired: false, theLoopHasWrittenTheRecord: false, latestReport: report))
    }

    var isStopRequested: Bool {
        state.withLock { $0.stopRequested }
    }

    /// Whether the stop came from a background task's window expiring rather than a reader asking.
    ///
    /// Here rather than only in the handler's copy because **either ending may be the one that records the run**, and who asked must survive whichever
    /// wins — otherwise a loop returning just before the handler reports a stop nobody can account for.
    var theWindowExpired: Bool {
        state.withLock { $0.theWindowExpired }
    }

    func requestStop(becauseTheWindowExpired: Bool) {
        state.withLock { state in
            state.stopRequested = true
            state.theWindowExpired = state.theWindowExpired || becauseTheWindowExpired
        }
    }

    /// What the drain had achieved when it last published — at worst one round ago.
    var latestReport: ObvInboxDrainReport {
        state.withLock { $0.latestReport }
    }

    func publish(_ report: ObvInboxDrainReport) {
        state.withLock { $0.latestReport = report }
    }


    /// Whether the expiration handler should be the one to write the run's record.
    ///
    /// **The loop's account supersedes the handler's, never the reverse**: the handler holds only the last published snapshot where the loop holds everything
    /// up to the moment it returned. Measured on an iPhone 13, a handler-written record claimed `seconds=0 sweeps=0` for a run the loop reported as
    /// `seconds=21 sweeps=1` — both true of the same run at different instants.
    ///
    /// The handler still writes when it gets there first, because the loop may never come back at all. What it writes is a floor, not the final word.
    var theExpirationHandlerShouldWriteTheRecord: Bool {
        state.withLock { !$0.theLoopHasWrittenTheRecord }
    }


    /// Claimed by the loop just before it writes, so that a handler firing afterwards leaves its record alone.
    func noteThatTheLoopIsWritingTheRecord() {
        state.withLock { $0.theLoopHasWrittenTheRecord = true }
    }

}


/// What one drain of the engine's inbox achieved.
///
/// A background run is otherwise invisible — it happens while the device is idle and on power, and the only evidence it ran is what it writes down. Stored in
/// the app group's `UserDefaults` and shown in the engine diagnostics panel.
///
/// **The two claims are reported separately**, which is the point of the shape: ``numberOfMessagesProcessed`` is what the app finished with,
/// ``numberOfRowsRemoved`` is what left the store. On a device holding 100'000, a backlog drained entirely by the first measure and barely at all by the
/// second, so a single number could claim success while the database said otherwise.
struct ObvInboxDrainReport: Codable, Sendable {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ObvInboxDrainReport.self))

    /// What asked for this drain.
    enum Trigger: String, Codable, Sendable {
        case backgroundProcessingTask
        /// The row in the advanced settings. The only way to run one on a simulator, where background tasks are never scheduled.
        case userRequestedItInTheSettings
    }


    /// Why the drain stopped. Declared in `ObvInboxDrainStopReason.swift`, which imports Foundation alone, so that the
    /// scheduling rule that reads it can be compiled into the app's unit tests — see ``ObvInboxDrainWindowSchedule``.
    /// The alias is what keeps every call site reading as `ObvInboxDrainReport.StopReason`.
    typealias StopReason = ObvInboxDrainStopReason


    let trigger: Trigger
    let startedAt: Date
    var secondsUsed: TimeInterval = 0
    var stopReason: StopReason

    /// Whether the run ended because a background processing task's expiration handler fired. Distinct from `stopReason == .weWereAskedToStop`, which the
    /// settings row can also produce: this one says the *system* ended the window, which is the normal case and not a fault.
    var endedOnTheExpirationHandler = false

    // The inbox, before and after. Nil until read; a report whose figures are missing says so rather than showing noughts.

    var numberOfMessagesAtStart: Int?
    /// Optional and added after the first version of this type, so an older stored report decodes with it nil — which is what `decodeIfPresent` does for an
    /// Optional and is the reason these are all Optional rather than defaulted.
    var numberOfMessagesNotYetDecryptedAtStart: Int?
    var numberOfMessagesAwaitingTheAppAtStart: Int?
    var numberOfMessagesMarkedForDeletionAtStart: Int?
    var numberOfMessagesWaitingForAManualDownloadAtStart: Int?

    var numberOfMessagesAtEnd: Int?
    var numberOfMessagesNotYetDecryptedAtEnd: Int?
    var numberOfMessagesAwaitingTheAppAtEnd: Int?
    var numberOfMessagesMarkedForDeletionAtEnd: Int?
    var numberOfMessagesWaitingForAManualDownloadAtEnd: Int?

    /// Messages belonging to a profile that is no longer active, as this run last saw it.
    ///
    /// **Reported because it is the difference between the total and the parts**, the work counts covering active profiles only. Without it, a device with a
    /// deactivated profile shows messages held and nothing outstanding, which sends somebody looking for a bug. It means *reactivate that profile or delete
    /// it*; no drain will change it.
    var numberOfMessagesBelongingToAnInactiveOwnedIdentityAtEnd: Int?

    // What the run did

    /// How many times the run looked at the counts.
    ///
    /// The loop is a poll, so this is just elapsed time over the poll interval — which is why it is not shown: *Rounds: 1200* tells a reader the run lasted
    /// twenty minutes, in the worst available units. Kept because a counter that stops climbing says the loop has stopped.
    var numberOfPolls = 0

    /// How many messages this device held when the run began, and when it ended.
    ///
    /// **The only sound way to say how much a drain achieved.** Everything else here describes the *engine's inbox*, which a drain keeps near empty by
    /// design, so a run that fetched ten thousand messages began and ended at nought — a successful drain of 10'218 reported *Messages stored by the app: 0*.
    ///
    /// A level difference is legitimate for *this* store, where it was not for that one: nothing removes from it while a drain runs, so the two ends differ
    /// by a genuine flow rather than by where something happened to be when it was read.
    var numberOfMessagesHeldByTheAppAtStart: Int?
    var numberOfMessagesHeldByTheAppAtEnd: Int?

    /// What the app finished with, and what left the store, summed over the rounds. Nil on an older report, and on a run that never completed a round.
    ///
    /// **A flow, where everything around them is a level** — that distinction is the whole reason they are summed per round rather than taken as the gap
    /// between two readings. A level difference agrees with the work done only while nothing arrives, which is true of every simulator walk and of none of
    /// the cases this exists for.
    ///
    /// **A floor, not an identity.** Each round's contribution is clamped at nought, a round in which the inbox grew having un-processed nothing, so these
    /// will not reconcile against the before and after counts when messages arrived mid-run. That is correct rather than a rounding error. Anybody adding a
    /// third figure here should say which of the two kinds it is.
    var numberOfMessagesProcessedAcrossRounds: Int?
    var numberOfRowsRemovedAcrossRounds: Int?

    // The stale shared-settings pass, which runs before the listing, in a background window as well as on a tap.

    /// How many messages were held when the pass began. This is the total the progress bar needs, and the only exact one this screen
    /// ever has: the listing phase cannot know how much the server holds, whereas this is a count taken before any row is touched.
    var numberOfHeldMessagesToExamine: Int?

    /// How many held messages were read, in order to find the stale settings among them. This is the total for the figure below.
    ///
    /// Nil until the pass has counted what there is to examine, and nought from then until the first page lands, so the row is on
    /// screen while that page is in flight. A device holding no message on hold stops the pass before that, so it reports "not
    /// measured" rather than zero.
    var numberOfHeldMessagesExamined: Int?

    /// How many of them carried a discussion shared configuration and nothing else, and were therefore discarded.
    var numberOfStaleSettingsMessagesDiscarded: Int?

    /// How long that pass took. It cannot be derived from ``secondsUsed``, which is the clock for the whole run. This is the figure
    /// that says whether one tap can clear a backlog.
    var secondsSpentOnTheStaleSettingsPass: TimeInterval?

    /// When the pass returned, whichever way it returned. Nil while it is still running.
    ///
    /// This cannot be computed from the counts. Every early exit (the deadline, the memory floor, a stop request, a page that could
    /// not be read) leaves fewer rows examined than there were to examine, which looks exactly like a pass that is still running.
    ///
    /// A `Date?` rather than a `Bool`, because reports written by an older build do not contain this key. Decoding a non-optional
    /// would then fail for the whole report, and a report is decoded with `try?`, so the last background run would be lost.
    var whenTheStaleSettingsPassEnded: Date?

    /// True when the pass returned with rows still to examine: the deadline, the memory floor or a stop request took it out of its loop, a profile's
    /// held messages could not be counted and that profile was left out of the walk, or a page of a profile could not be read, marked or forgotten and
    /// that profile was left for the next run.
    ///
    /// The schedule reads this. A held message is in none of the three inbox counts, so without it a window spent entirely in the
    /// pass and cut off part-way ends with counts that say nothing is outstanding, and the next window is asked for six hours later
    /// instead of one minute. Optional so that a report stored by an older build still decodes.
    var theStaleSettingsPassStoppedEarly: Bool?

    /// Which of the four steps of a page the pass is on, and since when. Nil once the pass has returned, and before it has a page.
    ///
    /// In the report rather than beside it on purpose. The background window's expiration handler stores the last published report
    /// while the pass may still be waiting on a step, and that stored report then says which step it was waiting on. The screen
    /// reads the same two fields once a second, so a stuck page says which step is stuck and for how long.
    var currentStepOfTheStaleSettingsPass: StaleSettingsPassStep?
    var whenTheCurrentStepOfTheStaleSettingsPassBegan: Date?

    /// How long the pass had been on that step when the window was taken away, set by the expiration handler and by nothing else.
    ///
    /// The duration is otherwise measured from now, which is right for the screen watching a live run and wrong for a report read
    /// back later: a window taken ten seconds into a step and mailed eleven hours on read as an eleven-hour step. Once this is set the
    /// duration is a fact about the run rather than about when it was read. Optional so that a report stored by an older build still
    /// decodes.
    var secondsOnTheCurrentStepOfTheStaleSettingsPassWhenTheRunWasCutOff: TimeInterval?

    /// The last pages of the pass, oldest first, each with how long its four steps took.
    ///
    /// The step above says where a page *is*; these say where the time *went*. They travel in the report, so they reach a support
    /// mail from a device whose running logs are off. Bounded, so the report stays small whatever the backlog. Optional, so a
    /// report stored by an older build still decodes.
    var lastPagesOfTheStaleSettingsPass: [PageOfTheStaleSettingsPass]?

    /// Whether the last page came back truncated — the server's own statement that it still holds something for this device.
    ///
    /// **Not derivable from any local count.** An empty inbox at the end of a run means either the backlog is gone or a page has just been cleared and the
    /// next not asked for; only the server tells them apart.
    ///
    /// **Nil until the listing has been started**, which is the whole of the stale-settings pass and every early exit before it. A `false` there would
    /// claim the server has nothing more when nobody has asked, and the screen showed exactly that for as long as the pass took.
    var theServerStillHadMoreAtTheEnd: Bool?
    var numberOfTimesTheCountsCouldNotBeRead = 0

    // Memory

    var peakFootprintInBytes: UInt64 = 0

    /// What was left of this process's memory limit when last asked, or nil if the platform would not say.
    var headroomAtEndInBytes: Int?

    /// Whether a positive memory reading was ever seen during the run. **A `false` here means the memory figures say nothing**: this process was never known
    /// to be memory-limited, which is every simulator, so `headroomAtEndInBytes` being nil is *no information* rather than *no room*.
    var weKnowThisProcessIsMemoryLimited = false


    init(trigger: Trigger, startedAt: Date, stopReason: StopReason) {
        self.trigger = trigger
        self.startedAt = startedAt
        self.stopReason = stopReason
    }


    /// What to answer when a drain could not be started at all — by default, a nil delegate somewhere along the chain.
    ///
    /// A report rather than an optional or a throw, so every hop says the same thing and the caller has one shape to show: a run that never happened is a
    /// fact worth putting on screen, not an error to swallow.
    ///
    /// `stopReason` is defaulted because the nil delegate is what the screen's chain always means. A background window has a second way here — the app not
    /// finishing its launch in time — wanting the same shape and a different ending, the two differing in how long the fault lasts, which is what decides
    /// when the next window is asked for.
    static func couldNotBeRun(trigger: Trigger, stopReason: ObvInboxDrainStopReason = .theDrainCouldNotBeStarted) -> ObvInboxDrainReport {
        .init(trigger: trigger, startedAt: .now, stopReason: stopReason)
    }


    // MARK: What the run achieved

    /// How many messages this device gained while the run was going: the figure a reader means by *did it work*.
    ///
    /// Falls back to the old accumulation for a report stored before the app's own store was counted, so an earlier report goes on reading as it did rather
    /// than becoming *Not measured*.
    var numberOfMessagesStoredByTheApp: Int? {
        if let start = numberOfMessagesHeldByTheAppAtStart, let end = numberOfMessagesHeldByTheAppAtEnd {
            return max(0, end - start)
        }
        return numberOfMessagesProcessed
    }


    /// How many messages the app finished with, summed over the rounds. Nil when nothing was ever measured.
    ///
    /// Falls back to the difference of the two levels for a report stored by a build from before the rounds were summed — which is what that figure meant
    /// then, and the honest reading of an old report rather than a nought asserted about a run nobody measured that way.
    var numberOfMessagesProcessed: Int? {
        if let acrossRounds = numberOfMessagesProcessedAcrossRounds { return acrossRounds }
        guard let start = numberOfMessagesAwaitingTheAppAtStart, let end = numberOfMessagesAwaitingTheAppAtEnd else { return nil }
        return max(0, start - end)
    }

    /// How many rows actually left the store, summed over the rounds. **Not the same claim as the one above**, and usually a much smaller number: a message
    /// the app has finished with keeps its row until the sweep gets to it, fifty per round per profile.
    ///
    /// Falls back to the old difference for the same reason, and with the same caveat.
    var numberOfRowsRemoved: Int? {
        if let acrossRounds = numberOfRowsRemovedAcrossRounds { return acrossRounds }
        guard let start = numberOfMessagesAtStart, let end = numberOfMessagesAtEnd else { return nil }
        return max(0, start - end)
    }


    /// Of the rows the app has finished with, how many a sweep could actually take — at the start of the run and at its end.
    ///
    /// Nil when the marked count was never read, since there is then nothing to show. Where *that* is known and the manual-download count is not — a report
    /// stored by a build from before it existed — this answers the whole marked population, which is what the figure meant then: the honest reading of an old
    /// report rather than a nought asserted about a device nobody counted.
    var numberOfMessagesStillToBeRemovedAtStart: Int? {
        guard let markedForDeletion = numberOfMessagesMarkedForDeletionAtStart else { return nil }
        return max(0, markedForDeletion - (numberOfMessagesWaitingForAManualDownloadAtStart ?? 0))
    }

    var numberOfMessagesStillToBeRemovedAtEnd: Int? {
        guard let markedForDeletion = numberOfMessagesMarkedForDeletionAtEnd else { return nil }
        return max(0, markedForDeletion - (numberOfMessagesWaitingForAManualDownloadAtEnd ?? 0))
    }

    /// What this run found out about the inbox — which, with the stop reason, decides how soon the next window is asked for.
    ///
    /// The rule is ``ObvInboxDrainWindowSchedule/whatWasLearnedAboutTheInbox(from:)``, where a unit test can reach it; this hands over the facts of the
    /// report it reads and nothing else.
    var whatWasLearnedAboutTheInbox: ObvInboxDrainWindowSchedule.WhatWasLearnedAboutTheInbox {
        ObvInboxDrainWindowSchedule.whatWasLearnedAboutTheInbox(from: .init(
            theServerStillHadMoreAtTheEnd: theServerStillHadMoreAtTheEnd,
            theStaleSettingsPassStoppedEarly: theStaleSettingsPassStoppedEarly,
            theStaleSettingsPassHadSomethingToExamine: numberOfHeldMessagesToExamine != nil,
            theStaleSettingsPassHasEnded: whenTheStaleSettingsPassEnded != nil,
            numberOfMessagesNotYetDecryptedAtEnd: numberOfMessagesNotYetDecryptedAtEnd,
            numberOfMessagesAwaitingTheAppAtEnd: numberOfMessagesAwaitingTheAppAtEnd,
            numberOfMessagesStillToBeRemovedAtEnd: numberOfMessagesStillToBeRemovedAtEnd))
    }


    /// Whether this window was worth having, which is what `BGTask.setTaskCompleted(success:)` is told. A question about *progress*, not about the backlog
    /// being gone: a device holding a hundred thousand messages cannot empty its inbox in one window, and reporting failure on every such run would teach
    /// the scheduler that the app cannot use the time it is given.
    ///
    /// Two ways to succeed. **Nothing was owed**, or **something moved**, asked of three figures because each reads nought on the others' kind of run: a
    /// backlog fetched from the server is counted by ``numberOfMessagesStoredByTheApp``, one already on the device by ``numberOfRowsRemoved``, and one of
    /// stale settings held by the app by ``numberOfStaleSettingsMessagesDiscarded``. The third is the one a device with tens of thousands of held
    /// messages spends its whole window on: the pass marks rows rather than removing them, so the inbox count does not fall, and the run ends before its
    /// first round, so nothing else is measured. Without it, every such window told the scheduler the time had been wasted, on the one device that
    /// needed the windows.
    ///
    /// The stop reason is not consulted: a window whose deadline passes on the poll that empties the inbox owes nothing.
    var theWindowWasWorthHaving: Bool {

        switch whatWasLearnedAboutTheInbox {
        case .thereIsNothingOutstanding:
            return true
        case .thereIsWorkOutstanding, .theInboxWasNeverRead:
            break
        }

        // Nil is *never measured*, which is not progress.
        return (numberOfMessagesStoredByTheApp ?? 0) > 0 || (numberOfRowsRemoved ?? 0) > 0 || (numberOfStaleSettingsMessagesDiscarded ?? 0) > 0

    }


    // MARK: Recording

    mutating func record(countsAtStart counts: ObvInboxCounts) {
        numberOfMessagesAtStart = counts.numberOfMessages
        numberOfMessagesNotYetDecryptedAtStart = counts.numberOfMessagesNotYetDecrypted
        numberOfMessagesAwaitingTheAppAtStart = counts.numberOfMessagesAwaitingTheApp
        numberOfMessagesMarkedForDeletionAtStart = counts.numberOfMessagesMarkedForDeletion
        numberOfMessagesWaitingForAManualDownloadAtStart = counts.numberOfMessagesWaitingForAManualDownload
        // Taken from the baseline and never asked for again: nothing lists, decrypts, marks or sweeps a message of an inactive profile, so it cannot change
        // during a run, and it is the one count no index can narrow, so asking again is a scan of the whole table. Stored as the *end* figure because that
        // is the one the screen shows; `record(countsAtEnd:)` does not blank it, a reading that did not ask being nil.
        if let numberOfMessagesBelongingToAnInactiveOwnedIdentity = counts.numberOfMessagesBelongingToAnInactiveOwnedIdentity {
            numberOfMessagesBelongingToAnInactiveOwnedIdentityAtEnd = numberOfMessagesBelongingToAnInactiveOwnedIdentity
        }
    }

    /// **A count that was not asked for does not erase one that was.** Some readings leave out
    /// ``ObvInboxCounts/numberOfMessagesWaitingForAManualDownload``, and assigning it unconditionally would blank a row that was right a moment ago. Nil here
    /// means *not asked*, never *none*.
    mutating func record(countsAtEnd counts: ObvInboxCounts) {
        numberOfMessagesAtEnd = counts.numberOfMessages
        numberOfMessagesNotYetDecryptedAtEnd = counts.numberOfMessagesNotYetDecrypted
        numberOfMessagesAwaitingTheAppAtEnd = counts.numberOfMessagesAwaitingTheApp
        numberOfMessagesMarkedForDeletionAtEnd = counts.numberOfMessagesMarkedForDeletion
        if let numberOfMessagesWaitingForAManualDownload = counts.numberOfMessagesWaitingForAManualDownload {
            numberOfMessagesWaitingForAManualDownloadAtEnd = numberOfMessagesWaitingForAManualDownload
        }
        // Guarded for the reason the line above is: nil is *not asked*, and a reading that did not ask must not blank a figure that did.
        if let numberOfMessagesBelongingToAnInactiveOwnedIdentity = counts.numberOfMessagesBelongingToAnInactiveOwnedIdentity {
            numberOfMessagesBelongingToAnInactiveOwnedIdentityAtEnd = numberOfMessagesBelongingToAnInactiveOwnedIdentity
        }
    }

    /// The inbox as this report last saw it, or nil before the first reading.
    ///
    /// So that a screen watching a run reads the counts here rather than asking the engine itself. The loop already pays for a reading every poll, and the
    /// fifth count costs 72ms on a store of 81'210 messages, so a second poller would double that for figures that could then disagree.
    var countsAtEnd: ObvInboxCounts? {
        guard let numberOfMessagesAtEnd,
              let numberOfMessagesNotYetDecryptedAtEnd,
              let numberOfMessagesAwaitingTheAppAtEnd,
              let numberOfMessagesMarkedForDeletionAtEnd else { return nil }
        return .init(numberOfMessages: numberOfMessagesAtEnd,
                     numberOfMessagesNotYetDecrypted: numberOfMessagesNotYetDecryptedAtEnd,
                     numberOfMessagesAwaitingTheApp: numberOfMessagesAwaitingTheAppAtEnd,
                     numberOfMessagesMarkedForDeletion: numberOfMessagesMarkedForDeletionAtEnd,
                     // Nil rather than nought when it was never asked for, which is what `ObvInboxCounts` reads as *there may be work* rather than as *there
                     // is none* — the pessimistic side, and the only safe one for a caller deciding whether to stop.
                     numberOfMessagesWaitingForAManualDownload: numberOfMessagesWaitingForAManualDownloadAtEnd,
                     numberOfMessagesBelongingToAnInactiveOwnedIdentity: numberOfMessagesBelongingToAnInactiveOwnedIdentityAtEnd)
    }

    /// The stranded-messages row, **and an empty list when there are none**.
    ///
    /// Unlike every other figure on this screen it is shown conditionally, because it is nought on every ordinary device: a permanent *0* against a row
    /// naming a state most readers have never met is noise, and the row is the whole diagnosis on the rare device that has one. Nil — the count was never
    /// asked for — shows nothing either, since *not measured* here would be a row about a question nobody put.
    private var figuresForMessagesOfADeactivatedProfile: [Figure] {
        guard let count = numberOfMessagesBelongingToAnInactiveOwnedIdentityAtEnd, count > 0 else { return [] }
        return [.init(label: String(localized: "Belonging to a deactivated profile"), value: Self.countForDisplay(count))]
    }

    /// The stale-settings rows. They are shown as soon as the pass examined at least one held message, even if it discarded none:
    /// examining a hundred thousand rows and finding nothing to discard is a result, and it must not look like a pass that never ran.
    ///
    /// The list is empty when nothing was examined, which is the case on a device that never ran 4.3.1: there, the pass finds no held
    /// message at all and stops before examining anything.
    private var figuresForTheStaleSettingsPass: [Figure] {
        guard let examined = numberOfHeldMessagesExamined else { return [] }
        var figures: [Figure] = [
            .init(label: String(localized: "Stale settings messages discarded"), value: Self.countForDisplay(numberOfStaleSettingsMessagesDiscarded)),
            .init(label: String(localized: "Held messages examined"), value: Self.countForDisplay(examined)),
            .init(label: String(localized: "Time spent discarding them"), value: secondsSpentOnTheStaleSettingsPass.map { Self.durationForDisplay($0) } ?? String(localized: "Not measured")),
        ]
        // Only a report stored while the pass was still on a step carries one: the window expired, or the process ended, before the
        // pass returned. This is the row that says which step it was on.
        if let step = currentStepOfTheStaleSettingsPass {
            figures.append(.init(label: String(localized: "Stopped during"), value: step.sentenceForDisplay))
        }
        return figures
    }


    /// Adds what one round moved to the run's totals.
    ///
    /// Called once per round with the round's own deltas, which is the only place they exist: by the time the run ends, the levels they were computed from
    /// have been overwritten several times over. Both start at nil and become non-nil on the first round, so a run that never completed one keeps saying
    /// *not measured* rather than claiming a nought it never established.
    mutating func record(messagesProcessedThisRound: Int, rowsRemovedThisRound: Int) {
        numberOfMessagesProcessedAcrossRounds = (numberOfMessagesProcessedAcrossRounds ?? 0) + messagesProcessedThisRound
        numberOfRowsRemovedAcrossRounds = (numberOfRowsRemovedAcrossRounds ?? 0) + rowsRemovedThisRound
    }

    /// Adds what one page of the stale-settings pass examined and discarded. Both values start at nil, so a run that never ran the
    /// pass keeps reporting "not measured".
    mutating func record(heldMessagesExamined: Int, staleSettingsMessagesDiscarded: Int, secondsSpentOnTheStaleSettingsPass: TimeInterval) {
        numberOfHeldMessagesExamined = (numberOfHeldMessagesExamined ?? 0) + heldMessagesExamined
        numberOfStaleSettingsMessagesDiscarded = (numberOfStaleSettingsMessagesDiscarded ?? 0) + staleSettingsMessagesDiscarded
        // Assigned, not added up. The caller measures from the start of the pass, so each page already reports the whole duration so far.
        self.secondsSpentOnTheStaleSettingsPass = secondsSpentOnTheStaleSettingsPass
    }

    /// Says which step of a page the pass is on, from now. The caller publishes, so the screen and a report stored mid-page both name it.
    mutating func begin(stepOfTheStaleSettingsPass step: StaleSettingsPassStep) {
        currentStepOfTheStaleSettingsPass = step
        whenTheCurrentStepOfTheStaleSettingsPassBegan = .now
    }

    /// How long the pass has been on its current step, or had been when the run was cut off. Nil when it is on none.
    var secondsOnTheCurrentStepOfTheStaleSettingsPass: TimeInterval? {
        guard let began = whenTheCurrentStepOfTheStaleSettingsPassBegan else { return nil }
        return secondsOnTheCurrentStepOfTheStaleSettingsPassWhenTheRunWasCutOff ?? Date.now.timeIntervalSince(began)
    }

    /// Freezes the duration of the current step, for a report stored while the pass is still on one. Does nothing when it is on none.
    mutating func noteThatTheRunWasCutOffDuringTheStaleSettingsPass() {
        guard let began = whenTheCurrentStepOfTheStaleSettingsPassBegan else { return }
        secondsOnTheCurrentStepOfTheStaleSettingsPassWhenTheRunWasCutOff = Date.now.timeIntervalSince(began)
    }

    /// Says the pass has returned, whichever way, and so is on no step.
    mutating func noteThatTheStaleSettingsPassEnded() {
        whenTheStaleSettingsPassEnded = .now
        currentStepOfTheStaleSettingsPass = nil
        whenTheCurrentStepOfTheStaleSettingsPassBegan = nil
        secondsOnTheCurrentStepOfTheStaleSettingsPassWhenTheRunWasCutOff = nil
    }

    static let numberOfPagesOfTheStaleSettingsPassKept = 20

    /// Keeps the page, and drops the oldest once more than ``numberOfPagesOfTheStaleSettingsPassKept`` are held.
    mutating func record(pageOfTheStaleSettingsPass page: PageOfTheStaleSettingsPass) {
        var pages = lastPagesOfTheStaleSettingsPass ?? []
        pages.append(page)
        if pages.count > Self.numberOfPagesOfTheStaleSettingsPassKept {
            pages.removeFirst(pages.count - Self.numberOfPagesOfTheStaleSettingsPassKept)
        }
        lastPagesOfTheStaleSettingsPass = pages
    }

    /// One of the four steps of a page of the stale-settings pass. A page reads its identifiers from the app's store, reads their
    /// payloads from the engine's, marks the stale ones for deletion in the engine, then forgets their identifiers on the app side.
    /// The last two run only when the page has something to discard.
    enum StaleSettingsPassStep: Codable, Hashable, Sendable {
        case readingIdentifiers
        case readingPayloads(count: Int)
        case markingForDeletion(count: Int)
        case forgettingIdentifiers(count: Int)

        /// The sentence the screen shows, step number included, so nothing is assembled from parts a translator cannot reorder.
        var sentenceForDisplay: String {
            switch self {
            case .readingIdentifiers: return String(localized: "Step 1 of 4 — reading held messages")
            case .readingPayloads(let count): return String(localized: "Step 2 of 4 — reading \(count) messages")
            case .markingForDeletion(let count): return String(localized: "Step 3 of 4 — marking \(count) messages for deletion")
            case .forgettingIdentifiers(let count): return String(localized: "Step 4 of 4 — forgetting \(count) held messages")
            }
        }

        var descriptionForLogs: String {
            switch self {
            case .readingIdentifiers: return "1/4 readingIdentifiers"
            case .readingPayloads(let count): return "2/4 readingPayloads(\(count))"
            case .markingForDeletion(let count): return "3/4 markingForDeletion(\(count))"
            case .forgettingIdentifiers(let count): return "4/4 forgettingIdentifiers(\(count))"
            }
        }
    }

    /// One page of the pass: what it examined and discarded, and how long each of its four steps took. The two deleting steps are
    /// nil for a page that had nothing to discard, which is not the same as their taking no time.
    struct PageOfTheStaleSettingsPass: Codable, Hashable, Sendable {
        let examined: Int
        let discarded: Int
        let secondsReadingIdentifiers: TimeInterval
        let secondsReadingPayloads: TimeInterval
        let secondsMarkingForDeletion: TimeInterval?
        let secondsForgettingIdentifiers: TimeInterval?

        var descriptionForLogs: String {
            func seconds(_ value: TimeInterval?) -> String { value.map { String(format: "%.1fs", $0) } ?? "-" }
            return "examined=\(examined) discarded=\(discarded) identifiers=\(seconds(secondsReadingIdentifiers)) payloads=\(seconds(secondsReadingPayloads)) marking=\(seconds(secondsMarkingForDeletion)) forgetting=\(seconds(secondsForgettingIdentifiers))"
        }
    }

    /// Keeps the latest headroom, and remembers for good whether this process has ever been *seen* to have a limit. The report is the one accumulator,
    /// which is why the flag is derived here rather than passed in.
    mutating func record(headroom: ObvProcessMemory.Allowance) {
        headroomAtEndInBytes = headroom.bytes
        weKnowThisProcessIsMemoryLimited = weKnowThisProcessIsMemoryLimited || headroom.provesTheProcessIsMemoryLimited
    }

    /// Keeps the largest footprint seen. The expensive of the two memory questions, so this is asked at the ends of a round and not inside one.
    mutating func notePeakFootprint() {
        peakFootprintInBytes = max(peakFootprintInBytes, ObvProcessMemory.footprint())
    }


    // MARK: Reading it back

    /// Whether this run counted nothing *and* its ending says nothing about the device either, so that recording it would replace what is known about this
    /// device with a screenful of `Not measured`.
    ///
    /// Two ordinary ways to be here: a drain that stood aside because another was already going, and a window taken away before its baseline counts came
    /// back, which the expiration handler writes from a snapshot with no figures in it. Keyed on the figures rather than on the ending, because the handler
    /// stamps `weWereAskedToStop` on either.
    ///
    /// The three fault endings are deliberately not here, though they have no figures either: *the counts could not be read*, *the drain could not be
    /// started* and *the app did not finish initializing in time* are facts worth putting on screen, and each wants its own interval. Exhaustive over the
    /// endings so that a new one has to be classified.
    private var thisRunHasNothingToSayAboutTheInbox: Bool {
        guard numberOfMessagesAtStart == nil else { return false }
        switch stopReason {
        case .anotherDrainWasAlreadyRunning, .weWereAskedToStop, .theDeadlinePassed, .weRanOutOfMemoryHeadroom:
            return true
        case .theCountsCouldNotBeRead, .theDrainCouldNotBeStarted, .theAppDidNotFinishInitializingInTime:
            return false
        case .thereWasNothingLeftToDo, .nothingWasMovingAnyMore, .theServerCouldNotBeReached:
            // Not reachable without figures, all three being concluded from the counts. Listed rather than left to a `default`, so that the compiler
            // notices a new ending.
            return false
        }
    }


    /// Writes this report where the diagnostics panel and the scheduling of the next window can read it.
    ///
    /// Here rather than on the coordinator, because three places write it: the loop when it returns, the expiration handler when the system takes the window
    /// away, and the settings row. One definition of the key, in the file that owns the type it holds. The schedule reads `startedAt` off the report, so no
    /// separate date is stored.
    func store(in userDefaults: UserDefaults?) {
        guard let userDefaults else { assertionFailure(); return }

        // A run with nothing to say does not replace the record of one that had something: the panel would read `Not measured` for a device whose last real
        // window cleared thirty thousand rows, and `scheduleBackgroundTasks` reads this same record to time the next window. Refused here rather than at the
        // call sites so that a new one cannot forget, and logged, since a guard that declines in silence cannot be told apart from a case that never arose.
        if thisRunHasNothingToSayAboutTheInbox {
            let line = "🤿 Not recording this run (\(stopReason.rawValue)): it never counted the inbox, so the last report that did stands."
            Self.logger.notice("\(line, privacy: .public)")
            ObvDisplayableLogs.shared.log(line)
            return
        }

        do {
            userDefaults.set(try JSONEncoder().encode(self), forKey: ObvMessengerConstants.UserDefaultsKeys.lastEngineInboxDrainReport.rawValue)
        } catch {
            assertionFailure()
        }
    }


    /// The last drain's report. Nil when no drain has ever run on this device, which is itself worth showing.
    static func lastStored(in userDefaults: UserDefaults?) -> ObvInboxDrainReport? {
        guard let userDefaults else { return nil }
        guard let encoded = userDefaults.data(forKey: ObvMessengerConstants.UserDefaultsKeys.lastEngineInboxDrainReport.rawValue) else { return nil }
        // A report written by a version whose shape has since changed decodes to nothing. There is nothing to repair and nothing worth keeping.
        return try? JSONDecoder().decode(ObvInboxDrainReport.self, from: encoded)
    }


    // MARK: Showing it to somebody

    /// One labelled figure of the report.
    struct Figure: Identifiable, Hashable {
        let label: String
        let value: String
        var id: String { label }
    }


    /// A heading and the figures under it.
    struct FigureGroup: Identifiable, Hashable {
        let title: String
        let figures: [Figure]
        var id: String { title }
    }


    /// What became of the run, in a sentence somebody can read.
    ///
    /// The stop reasons are deliberately not shown by their case names: `thereWasNothingLeftToDo` is precise and means nothing to the reader whose device
    /// this is, and a report we ask somebody to send us has to be legible to the person sending it.
    var outcomeForDisplay: String {
        switch stopReason {
        case .thereWasNothingLeftToDo:
            return String(localized: "Finished — there was nothing left to do")
        case .theDeadlinePassed:
            return String(localized: "Stopped after the time allowed, with work still to do")
        case .weWereAskedToStop:
            return endedOnTheExpirationHandler
                ? String(localized: "Interrupted by the system, with work still to do")
                : String(localized: "Stopped early, with work still to do")
        case .nothingWasMovingAnyMore:
            return String(localized: "Stopped — nothing was moving any more")
        case .theServerCouldNotBeReached:
            return String(localized: "Stopped — the server could not be reached")
        case .weRanOutOfMemoryHeadroom:
            return String(localized: "Stopped to stay within the memory available")
        case .theCountsCouldNotBeRead:
            return String(localized: "Stopped — the inbox could not be read")
        case .anotherDrainWasAlreadyRunning:
            return String(localized: "Nothing to do — another run was already in progress")
        case .theDrainCouldNotBeStarted:
            return String(localized: "Could not be started")
        case .theAppDidNotFinishInitializingInTime:
            return String(localized: "Could not be started — the app was still starting up")
        }
    }


    /// The few figures worth showing where there is only room for a few: the last-run row of the diagnostics panel.
    ///
    /// Both claims are here, because each reads nought on the other's kind of run: a backlog fetched from the server is counted by
    /// ``numberOfMessagesStoredByTheApp``, one that was already on this device by ``numberOfRowsRemoved``. A summary carrying either alone says *nothing
    /// happened* about half the runs it describes. The wording is the full report's, so the two screens read alike and nothing new is translated.
    var summaryForDisplay: [Figure] {
        [
            .init(label: String(localized: "When"), value: startedAt.formatted(date: .abbreviated, time: .shortened)),
            .init(label: String(localized: "Outcome"), value: outcomeForDisplay),
            // The row the panel is most often read for: it tells a background window apart from somebody's tap, which is the only way to know whether the
            // system grants this task a window at all.
            .init(label: String(localized: "Started by"), value: trigger == .backgroundProcessingTask ? String(localized: "Olvid, in the background") : String(localized: "You, from the settings")),
            .init(label: String(localized: "Messages stored by the app"), value: Self.countForDisplay(numberOfMessagesStoredByTheApp)),
            .init(label: String(localized: "Rows the inbox lost"), value: Self.countForDisplay(numberOfRowsRemoved)),
        ]
    }


    /// The whole report, grouped under headings.
    ///
    /// **Localized, unlike `ObvEngineDiagnostic`'s figures.** The reader is an ordinary user who was asked to tap a button and wait, and a report arriving
    /// in French is still readable by us, since the rows, the numbers and the groups are in the same order whatever the language. `descriptionForLogs` stays
    /// English, which is where a fixed vocabulary matters. Anything that was never measured says so rather than showing a nought.
    var groupsForDisplay: [FigureGroup] {

        return [
            // The figure that says whether it worked comes first, next to the result. A group about *when* and *how long* with the achievement buried near
            // the bottom read as a screen of noughts after a successful drain.
            .init(title: String(localized: "Outcome"), figures: [
                .init(label: String(localized: "Result"), value: outcomeForDisplay),
                    .init(label: String(localized: "Messages stored by the app"), value: Self.countForDisplay(numberOfMessagesStoredByTheApp)),
                .init(label: String(localized: "When"), value: startedAt.formatted(date: .abbreviated, time: .shortened)),
                .init(label: String(localized: "Started by"), value: trigger == .backgroundProcessingTask ? String(localized: "Olvid, in the background") : String(localized: "You, from the settings")),
                .init(label: String(localized: "Time taken"), value: Self.durationForDisplay(secondsUsed)),
            ] + figuresForTheStaleSettingsPass),
            // These states are not a partition of "messages held" and the rows deliberately do not add up to it: a message on hold, or one waiting for a
            // contact to exist, is in none of them. The gap between the total and the sum is itself the useful reading, being the population no drain
            // will ever move.
            //
            // "Waiting for a manual download" is a row of its own, and the largest of these on an ordinary device. Folded into "still to be removed", one
            // unopened photograph made that figure never reach nought. The name matches `ObvEngineDiagnostic`'s figure for the same population.
            .init(title: String(localized: "The inbox afterwards"), figures: [
                .init(label: String(localized: "Messages held"), value: Self.countForDisplay(numberOfMessagesAtEnd)),
                .init(label: String(localized: "Still to be decrypted"), value: Self.countForDisplay(numberOfMessagesNotYetDecryptedAtEnd)),
                .init(label: String(localized: "Still to be stored by the app"), value: Self.countForDisplay(numberOfMessagesAwaitingTheAppAtEnd)),
                .init(label: String(localized: "Still to be removed"), value: Self.countForDisplay(numberOfMessagesStillToBeRemovedAtEnd)),
                .init(label: String(localized: "Waiting for a manual download"), value: Self.countForDisplay(numberOfMessagesWaitingForAManualDownloadAtEnd)),
            ] + figuresForMessagesOfADeactivatedProfile),
            .init(title: String(localized: "The inbox before"), figures: [
                .init(label: String(localized: "Messages held"), value: Self.countForDisplay(numberOfMessagesAtStart)),
                .init(label: String(localized: "To be decrypted"), value: Self.countForDisplay(numberOfMessagesNotYetDecryptedAtStart)),
                .init(label: String(localized: "To be stored by the app"), value: Self.countForDisplay(numberOfMessagesAwaitingTheAppAtStart)),
                .init(label: String(localized: "To be removed"), value: Self.countForDisplay(numberOfMessagesStillToBeRemovedAtStart)),
                .init(label: String(localized: "Waiting for a manual download"), value: Self.countForDisplay(numberOfMessagesWaitingForAManualDownloadAtStart)),
            ]),
            .init(title: String(localized: "Work done"), figures: [
                .init(label: String(localized: "The server still had more"), value: Self.serverHasMoreForDisplay(theServerStillHadMoreAtTheEnd, whileRunning: false)),
                // Named for the narrow thing it measures: the change in the *engine's inbox*, which is meaningful when the backlog was already on this
                // device and nought when it came off the server during the run, the inbox being empty at both ends.
                .init(label: String(localized: "Rows the inbox lost"), value: Self.countForDisplay(numberOfRowsRemoved)),
                .init(label: String(localized: "Times the inbox could not be counted"), value: "\(numberOfTimesTheCountsCouldNotBeRead)"),
            ]),
            .init(title: String(localized: "Memory"), figures: [
                .init(label: String(localized: "Most used at once"), value: ObvProcessMemory.megabytes(peakFootprintInBytes)),
                .init(label: String(localized: "Still available at the end"), value: headroomForDisplay),
            ]),
        ]

    }


    private var headroomForDisplay: String {
        if let headroomAtEndInBytes {
            return ObvProcessMemory.megabytes(UInt64(headroomAtEndInBytes))
        } else if weKnowThisProcessIsMemoryLimited {
            return String(localized: "None of the limit was left")
        } else {
            // Not the same as *plenty of room*: this process was never known to be memory-limited, which is every simulator, so the platform said nothing.
            return String(localized: "Not reported on this device")
        }
    }


    private static func countForDisplay(_ value: Int?) -> String {
        guard let value else { return String(localized: "Not measured") }
        return value.formatted()
    }


    /// Three answers, not two: the third is that the listing was never asked, which a live run says as *not yet* and a finished one as *never*.
    static func serverHasMoreForDisplay(_ value: Bool?, whileRunning: Bool) -> String {
        switch value {
        case .some(true): return String(localized: "Yes")
        case .some(false): return String(localized: "No")
        case .none: return whileRunning ? String(localized: "Not asked yet") : String(localized: "Never asked")
        }
    }


    private static func durationForDisplay(_ seconds: TimeInterval) -> String {
        guard seconds >= 1 else { return String(localized: "less than a second") }
        return Duration.seconds(Int(seconds)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }


    /// The whole thing as plain text, for the clipboard and for a support mail.
    var textForSharing: String {
        var lines: [String] = [String(localized: "Olvid — inbox maintenance report")]
        for group in groupsForDisplay {
            lines.append("")
            lines.append("--- \(group.title) ---")
            for figure in group.figures {
                lines.append("\(figure.label): \(figure.value)")
            }
        }
        if let pages = lastPagesOfTheStaleSettingsPass, !pages.isEmpty {
            lines.append("")
            lines.append("--- \(String(localized: "Last pages of the stale settings pass")) ---")
            lines.append(contentsOf: pages.map(\.descriptionForLogs))
        }
        lines.append("")
        lines.append(descriptionForLogs)
        return lines.joined(separator: "\n")
    }


    /// One line with every figure in it, for the log. The order is fixed so a column can be read down a log without parsing.
    var descriptionForLogs: String {
        let processed = numberOfMessagesProcessed.map(String.init) ?? "?"
        let removed = numberOfRowsRemoved.map(String.init) ?? "?"
        let headroom = headroomAtEndInBytes.map { ObvProcessMemory.megabytes(UInt64($0)) } ?? (weKnowThisProcessIsMemoryLimited ? "0" : "unknown")
        // The step is "none" for a report written after the pass returned; anything else is a report written while it was still on that step.
        let passStep = currentStepOfTheStaleSettingsPass.map { "\($0.descriptionForLogs) for \(Int(secondsOnTheCurrentStepOfTheStaleSettingsPass ?? 0))s" } ?? "none"
        return "trigger=\(trigger.rawValue) stopReason=\(stopReason.rawValue) expired=\(endedOnTheExpirationHandler) seconds=\(Int(secondsUsed)) polls=\(numberOfPolls) processed=\(processed) rowsRemoved=\(removed) total=\(numberOfMessagesAtEnd.map(String.init) ?? "?") notYetDecrypted=\(numberOfMessagesNotYetDecryptedAtEnd.map(String.init) ?? "?") awaitingTheApp=\(numberOfMessagesAwaitingTheAppAtEnd.map(String.init) ?? "?") markedForDeletion=\(numberOfMessagesMarkedForDeletionAtEnd.map(String.init) ?? "?") serverHasMore=\(theServerStillHadMoreAtTheEnd.map { $0 ? "true" : "false" } ?? "notAsked") countReadFailures=\(numberOfTimesTheCountsCouldNotBeRead) peakFootprint=\(ObvProcessMemory.megabytes(peakFootprintInBytes)) headroom=\(headroom) passStep=\(passStep) passStoppedEarly=\(theStaleSettingsPassStoppedEarly ?? false)"
    }

}
