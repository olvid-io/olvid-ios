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
import os
import SwiftUI
import ObvTypes
import ObvEngine
import ObvUICoreData
import OlvidUtils
import ObvAppCoreConstants
import ObvAppTypes


/// Runs one inbox maintenance and says, once a second, what it has achieved so far. A drain of ten thousand messages takes a quarter of an hour, and a
/// reader cannot tell a spinner from a hang.
///
/// There is no denominator while the server has more, and the design lives with that rather than inventing one: the server never says how many messages
/// are waiting, only whether the page it just sent was truncated. So the screen shows a number that climbs and whether the server still has more.
protocol InboxMaintenanceModelDelegate: AnyObject {
    @MainActor func userRequestedDrainOfTheEngineInbox(_ model: InboxMaintenanceModel, run: ObvInboxDrainInProgress) async -> ObvInboxDrainReport
}


/// **`ObservableObject` and not `@Observable`, because this screen is not gated and the app's floor is iOS 16.** `@Observable` is iOS 17, which would put
/// `@available(iOS 17.0, *)` on this model, the view, the hosting controller and the Troubleshooting row that pushes it — and that row is one we ask ordinary
/// readers to tap. `StorageManagementViewModel` shows the other choice being made deliberately.
///
/// Nothing is lost here: `@Observable`'s advantage is per-property tracking, and this screen's three published properties are written together in one refresh
/// and read together in one body.
@MainActor
final class InboxMaintenanceModel: ObservableObject {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "InboxMaintenanceModel")

    /// How often the figures are refreshed while a run is going. Cheap, because a refresh reads the run's report rather than the databases; what is still
    /// read here is one pair of aggregates for the progress walk.
    ///
    /// Equal to the drain's own poll interval, which bounds how stale a reading can be: nothing phases the two loops, so a reading is between nought and
    /// one second old, and never more than one drain poll behind. Keep them equal, or make this one the shorter.
    private static let refreshInterval: TimeInterval = 1

    enum State {
        case notStarted
        case running
        case finished(report: ObvInboxDrainReport)
    }

    @Published private(set) var state: State = .notStarted

    /// How far along the run is, which is also what the system is told while it keeps this device awake.
    ///
    /// There is a total only once the server says it has nothing more. While pages are still coming, what is left is unknown: a run fetched 2'043 messages
    /// in pages of 29, 54, 99, 94, 146, 232, 202, 271, 222, 361 and 333, and after the first the only figures in hand were *29 done, 0 left*. Once the
    /// server is done, what remains is the local work, which is countable, and the bar becomes real.
    ///
    /// Clamped so it cannot go backwards once it is real: the inbox jumps each time a page lands, and a bar that retreats reads as a fault.
    struct ProgressSnapshot: Equatable {
        let done: Int
        /// Nil while the server may still have pages: there is then a fraction to show but no honest total to name.
        let total: Int?
        /// Nil when there is no position to report at all, before the first page. **Nil is not nought**: a bar at nought says nothing has happened, and
        /// it said so once while the count beside it climbed past a thousand. Rising whenever it is present.
        let fraction: Double?
        var theTotalIsKnown: Bool { total != nil }
    }

    @Published private(set) var progress: ProgressSnapshot?

    /// How far through the backlog's timeline this run has walked, and the only thing that decides what the bar and the system are told.
    ///
    /// The anchor, the high-water mark, the clamp and the frontier guard all live in ``ObvInboxDrainBacklogWalk``, which is a file of its own so that a test
    /// can reach it — the fraction having had two defects that only a device ever showed. Nil until a run starts.
    private var backlogWalk: ObvInboxDrainBacklogWalk?

    /// The newest server timestamp this device already held when the run began, which is what separates *this run's* backlog from everything received before
    /// it. `.distantPast` for a device holding nothing.
    ///
    /// **Nil until a run starts *and its baseline has come back*, which is not the same instant.** Reading it is a `min`/`max` over every received message, so
    /// it is done off the main actor and the first moment of a run has it outstanding. Anything reading this must treat nil as *not known yet* rather than
    /// substitute `.distantPast`, which would say the device held nothing and hand the walk every message it has ever received.
    private var newestServerTimestampHeldAtStart: Date?

    /// What to show, in the order it is shown. Empty until the first figures arrive.
    @Published private(set) var figures: [ObvInboxDrainReport.Figure] = []

    /// What the run is doing, so the header can name it.
    ///
    /// The two phases look the same from outside, and the progress bar completes twice, which reads as if the first attempt had
    /// failed. The phases are named rather than numbered: on an ordinary device the first one is a single fetch that finds nothing,
    /// so the reader never sees it, and "step 1 of 2" would describe a step they skipped.
    enum WhatIsHappening {
        case discardingStaleSettings
        case fetchingMessages

        var localizedDescription: String {
            switch self {
            case .discardingStaleSettings: return String(localized: "Removing old settings messages")
            case .fetchingMessages: return String(localized: "Fetching your messages")
            }
        }
    }

    @Published private(set) var whatIsHappening: WhatIsHappening = .fetchingMessages

    /// Who runs the drain, and the only thing this model needs from the rest of the app. The inbox counts come from the report the run publishes, so
    /// this touches no manager at all.
    weak var delegate: InboxMaintenanceModelDelegate?

    /// The run in progress, held behind a lock rather than as main-actor state.
    ///
    /// **Because `deinit` has to be able to stop it, and `deinit` is nonisolated.** A screen can be deallocated without its view ever disappearing — the
    /// settings flow going away while something else is popped — and the run holds this model weakly, so nothing else would end it: on a platform without a
    /// continued processing task that leaves a drain with no deadline running, and the idle timer held, for a screen that no longer exists.
    /// `ObvInboxDrainInProgress` is `Sendable` and lock-backed, so reaching it from anywhere is sound.
    private let runInProgress = OSAllocatedUnfairLock<ObvInboxDrainInProgress?>(initialState: nil)

    private var refreshTask: Task<Void, Never>?

    init() {}


    var aRunIsInProgress: Bool {
        if case .running = state { return true }
        return false
    }


    // MARK: Starting and stopping

    func userWantsToStartTheInboxMaintenance() {

        guard !aRunIsInProgress else { return }

        let run = ObvInboxDrainInProgress(report: .init(trigger: .userRequestedItInTheSettings, startedAt: .now, stopReason: .theDeadlinePassed))
        runInProgress.withLock { $0 = run }
        self.state = .running
        self.figures = []
        self.progress = nil
        self.backlogWalk = .init(millisecondsAtTheStartOfTheRun: Int(Date.now.timeIntervalSince1970 * 1000))
        // Not read here: it is read in the task below, before the drain is asked for anything. See the comment there.
        self.newestServerTimestampHeldAtStart = nil
        // The run does not outlive the app going to the background, deliberately. A `BGContinuedProcessingTask` is meant to survive exactly that, and
        // measured on an iPhone 13 running iOS 26, three such runs were taken back by the system within a minute or two of the screen going dark. A
        // mechanism that looks as though the reader may walk away and then stops is worse than one that says plainly *keep this screen open*, so this
        // holds the screen awake instead.

        startRefreshing(run: run)

        // Held here rather than through `ObvContinuedProcessingTaskManager`, which does the same thing on its fallback path: that type is shared with the
        // history transfer, which still takes a continued processing task, and nothing decided about this screen should reach it.
        let screenAwakeRequest = IdleTimerManager.shared.disableIdleTimer(reason: .longRunningTask)

        // Held strongly for the call: the delegate takes this model as its first argument, and a run is minutes long. Nothing here is a cycle, the
        // delegate being weak, and what stops a run when the screen goes is the hosting controller's `deinit`.
        Task {

            // The baseline, read before the drain is asked for anything: one taken a second late has already had some of the run subtracted from it. The
            // *count* baseline is not read here, the drain taking its own and publishing it.
            //
            // Off the main actor: `performBackgroundTaskAndWait` waits on the context's own queue, and this is a `min`/`max` over every received message
            // on an unindexed column. Asked from the tap, it froze the screen on the hundred-thousand-message device this screen exists for.
            //
            // `.distantPast` rather than nil for a device holding nothing, or whose store cannot be read, so that every message that arrives counts towards
            // this run's backlog.
            let newestHeld: Date? = await Task.detached {
                Self.serverTimestampSpanOfMessagesStored(after: .distantPast)?.latest
            }.value

            self.newestServerTimestampHeldAtStart = newestHeld ?? .distantPast

            let report: ObvInboxDrainReport
            if let delegate = self.delegate {
                report = await delegate.userRequestedDrainOfTheEngineInbox(self, run: run)
            } else {
                // Nothing ran. It still has to end the same way, or the screen is left spinning and the device awake.
                assertionFailure("The inbox maintenance screen has no delegate, so the drain cannot be run")
                report = .couldNotBeRun(trigger: .userRequestedItInTheSettings)
            }
            await MainActor.run { [weak self] in
                // Released here rather than in ``theRunFinished(with:)``, and unconditionally rather than through `self`: a screen that has gone away while
                // its run was still finishing must not leave the device unable to sleep.
                IdleTimerManager.shared.enableIdleTimer(disableRequestIdentifier: screenAwakeRequest)
                self?.theRunFinished(with: report)
            }
        }

    }


    /// Stops whatever is running. Called when the screen goes, and when the app is backgrounded.
    ///
    /// Safe to call when nothing is running, and safe to call twice.
    nonisolated func stopTheRunInProgress() {
        runInProgress.withLock { $0 }?.requestStop(becauseTheWindowExpired: false)
    }


    /// Ends the polling. Separate from ``stopTheRunInProgress()`` because the two answer different questions: a run may be asked to stop while its last round
    /// is still in flight, and the figures should go on being read until it actually returns.
    func theScreenIsGoingAway() {
        stopTheRunInProgress()
        refreshTask?.cancel()
        refreshTask = nil
    }


    private func theRunFinished(with report: ObvInboxDrainReport) {
        refreshTask?.cancel()
        refreshTask = nil
        runInProgress.withLock { $0 = nil }
        progress = nil
        backlogWalk = nil
        newestServerTimestampHeldAtStart = nil
        // Not stored here: the coordinator that ran it already did, at the end of `drainEngineInbox`, and one writer is what keeps the *Last run* row and
        // this screen saying the same thing.
        figures = report.groupsForDisplay.flatMap(\.figures)
        state = .finished(report: report)
    }


    // MARK: Reading the figures

    private func startRefreshing(run: ObvInboxDrainInProgress) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshTheFigures(run: run)
                try? await Task.sleep(seconds: Self.refreshInterval)
            }
        }
    }


    /// Reads everything worth showing. Almost all of it comes from the run's own report, which the drain publishes every poll, so there is one reader of
    /// the databases and the figures cannot disagree with the ones the drain decides on. What is still read here is the backlog's span in the app's own
    /// store, for the progress walk.
    private func refreshTheFigures(run: ObvInboxDrainInProgress) async {

        let report = run.latestReport
        let counts = report.countsAtEnd
        let heldNow = report.numberOfMessagesHeldByTheAppAtEnd

        // Where the messages themselves say the backlog has got to, whoever fetched them.
        //
        // Off this actor: `performBackgroundTaskAndWait` waits on the context's own queue, and would stop the main thread once a second against a store
        // that may hold a hundred thousand messages. Nothing is read until the baseline is in: `.distantPast` in its place would ask a different question,
        // every message the device has ever received, and the walk already has a state for having no position.
        let backlogSpan: (earliest: Date, latest: Date)?
        if let baseline = newestServerTimestampHeldAtStart {
            backlogSpan = await Task.detached { Self.serverTimestampSpanOfMessagesStored(after: baseline) }.value
        } else {
            backlogSpan = nil
        }

        var figures: [ObvInboxDrainReport.Figure] = []

        // First of all, while the pass is on a step: which of a page's four steps, and for how long, so a page that is stuck says which
        // step is stuck. The seconds tick because this runs once a second.
        if theStaleSettingsPassIsRunning(report: report), let step = report.currentStepOfTheStaleSettingsPass, let seconds = report.secondsOnTheCurrentStepOfTheStaleSettingsPass {
            // One format rather than the sentence and the duration joined by a dash: the sentence already carries one, and the order of the two is the
            // translator's to choose.
            let stepAndHowLongItHasRun = String(localized: "\(step.sentenceForDisplay) for \(Self.durationForDisplay(seconds))",
                                                comment: "The Now row of the inbox maintenance screen while the stale-settings pass runs. The first %@ is a whole sentence naming the step, such as 'Step 2 of 4 — reading 500 messages'; the second is how long the pass has been on it, such as '12s'.")
            figures.append(.init(label: String(localized: "Now"), value: stepAndHowLongItHasRun))
        }

        // Next, and only while there is a backlog of these messages. On a device carrying one, this is the phase the reader
        // waits through, and until it ends every other figure here stays at its starting value. These two climb.
        if let discarded = report.numberOfStaleSettingsMessagesDiscarded, let examined = report.numberOfHeldMessagesExamined {
            figures.append(.init(label: String(localized: "Stale settings messages discarded"), value: discarded.formatted()))
            figures.append(.init(label: String(localized: "Held messages examined"), value: examined.formatted()))
        }

        if let heldNow, let heldAtStart = report.numberOfMessagesHeldByTheAppAtStart {
            figures.append(.init(label: String(localized: "Messages stored by the app"), value: max(0, heldNow - heldAtStart).formatted()))
        }

        figures.append(.init(label: String(localized: "More still waiting on the server"), value: ObvInboxDrainReport.serverHasMoreForDisplay(report.theServerStillHadMoreAtTheEnd, whileRunning: true)))
        figures.append(.init(label: String(localized: "Time taken"), value: Self.durationForDisplay(Date.now.timeIntervalSince(report.startedAt))))

        if let counts {
            figures.append(.init(label: String(localized: "In the inbox right now"), value: counts.numberOfMessages.formatted()))
            figures.append(.init(label: String(localized: "…still to be decrypted"), value: counts.numberOfMessagesNotYetDecrypted.formatted()))
            figures.append(.init(label: String(localized: "…waiting for the app"), value: counts.numberOfMessagesAwaitingTheApp.formatted()))
            figures.append(.init(label: String(localized: "…still to be removed"), value: counts.numberOfMessagesStillToBeRemoved.formatted()))
        }

        self.figures = figures
        self.updateTheProgress(report: report, counts: counts, heldNow: heldNow, backlogSpan: backlogSpan)

    }


    /// Whether the stale-settings pass is running, which decides both the header and the bar below.
    ///
    /// Running as soon as there is a total, which is published before the first page, and until the pass says it has returned. The counts are not
    /// consulted at either end: `examined == toExamine` is reached by the last page while the pass is still deleting it, so testing it flipped the header
    /// to "Fetching your messages" a page early.
    private func theStaleSettingsPassIsRunning(report: ObvInboxDrainReport) -> Bool {
        guard report.whenTheStaleSettingsPassEnded == nil else { return false }
        return report.numberOfHeldMessagesToExamine != nil
    }


    /// Works out how far along the run is, and tells both the screen and the system the same thing. The system prioritises the termination of tasks that
    /// report no progress, so a run that says nought for its whole life is a task the system is invited to kill.
    private func updateTheProgress(report: ObvInboxDrainReport, counts: ObvInboxCounts?, heldNow: Int?, backlogSpan: (earliest: Date, latest: Date)?) {

        let done: Int
        if let heldNow, let heldAtStart = report.numberOfMessagesHeldByTheAppAtStart {
            done = max(0, heldNow - heldAtStart)
        } else {
            done = 0
        }

        let stillInTheInbox = counts?.numberOfMessagesStillOwed ?? 0

        // Nil, the listing not yet asked, lands on the estimate side: a total nobody has asked for is not a known total, and treating it as known once
        // drew `19 of 52` on a backlog of two thousand.
        let theServerMayHaveMore = report.theServerStillHadMoreAtTheEnd ?? true

        // What the run is doing, so the header can say it. The bar completes once for the pass and once for the listing. Without a
        // line naming them, the second start reads as if the first had failed.
        self.whatIsHappening = theStaleSettingsPassIsRunning(report: report) ? .discardingStaleSettings : .fetchingMessages

        // While the stale-settings pass is running, its own progress is the answer, and it is exact: it knows how many rows were
        // held before it started, and how many it has looked at. Nothing else on this screen has a real total. Without this, the bar
        // would sit at zero for the whole pass, because the listing has not begun, so `done` is zero and the count beside it is still
        // the starting value. A progress bar that does not move is the one thing to avoid.
        if theStaleSettingsPassIsRunning(report: report), let toExamine = report.numberOfHeldMessagesToExamine {
            let examined = report.numberOfHeldMessagesExamined ?? 0
            self.progress = .init(done: examined, total: toExamine, fraction: Double(examined) / Double(max(1, toExamine)))
            return
        }

        if theServerMayHaveMore {

            // How far through the backlog's timeline the listing has walked, the only measure that does not need to know how big the backlog is: a
            // count-based estimate has to guess at a scale. Nil rather than the floor when the walk has no position yet, since a bar at nought says
            // nothing is happening.
            self.progress = .init(done: done, total: nil, fraction: backlogWalk?.fractionWalked(positionsInMilliseconds: positionsWalkedTo(backlogSpan: backlogSpan)))

        } else {

            // The server has nothing left, so what remains is the local work and this is exact. It counts rows removed, not messages stored: on a device
            // whose backlog is discarded rather than filed, nothing is ever stored, and a count stuck at zero beside a shrinking total reads as a run
            // going backwards.
            let removed = report.numberOfRowsRemoved ?? 0
            let fraction = backlogWalk?.fractionFromTheExactCount(done: removed, outstanding: stillInTheInbox)
            self.progress = .init(done: removed, total: max(1, removed + stillInTheInbox), fraction: fraction)

        }

    }


    /// Every position known at this moment, in the server's own milliseconds. Read from the messages the app has stored: a message carries the server's
    /// clock whoever fetched it, so this keeps moving whether the drain is listing or the app is, and through the wait for the app to catch up.
    ///
    /// The oldest position is passed as well as the newest: the smallest ever seen anchors the walk, and the oldest message of the backlog is a better
    /// anchor than the end of the first page.
    private func positionsWalkedTo(backlogSpan: (earliest: Date, latest: Date)?) -> [Int] {
        var positions = [Int]()
        if let backlogSpan {
            positions.append(Int(backlogSpan.earliest.timeIntervalSince1970 * 1000))
            positions.append(Int(backlogSpan.latest.timeIntervalSince1970 * 1000))
        }
        return positions
    }


    /// Among the messages the server received after `date`, the oldest and newest of those timestamps: the two ends of the walk the progress bar follows.
    /// Two aggregates that materialise nothing, which is what makes this affordable once a second.
    ///
    /// Answers nil rather than throwing: a figure that cannot be read is one row that says nothing, never a run that stops.
    private nonisolated static func serverTimestampSpanOfMessagesStored(after date: Date) -> (earliest: Date, latest: Date)? {
        var backlogSpan: (earliest: Date, latest: Date)?
        ObvStack.shared.performBackgroundTaskAndWait { context in
            backlogSpan = try? PersistedMessageReceived.serverTimestampSpanOfMessagesReceived(after: date, within: context)
        }
        return backlogSpan
    }


    private static func durationForDisplay(_ seconds: TimeInterval) -> String {
        let seconds = Int(seconds.rounded())
        guard seconds >= 60 else { return "\(seconds)s" }
        return "\(seconds / 60)min \(seconds % 60)s"
    }

}
