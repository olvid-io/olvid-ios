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

import XCTest
import OlvidUtils


/// When the background task that drains the engine's inbox asks for its next window.
///
/// **The only part of that feature a test can reach, and the part where being wrong is expensive.** Everything else
/// needs a device, a backlog, or both, and the two cannot be had on one machine. This rule is a function of what the last run left and of the clock, and the whole of it is the
/// difference between one night's work and thirty hours of it: a window that clears 20'000 of 100'000 and then stands
/// down for six hours needs thirty hours of charging to finish what a night could have done.
///
/// The switch over ``ObvInboxDrainStopReason`` in ``testEveryStopReasonWithWorkOutstandingIsAccountedFor`` is
/// exhaustive deliberately: a new ending that nobody classifies stops this file compiling, which is the only thing
/// that will keep the rule honest as the drain grows more ways to end.
final class ObvInboxDrainWindowScheduleTests: XCTestCase {

    /// A fixed clock. Nothing here reads the real one — that is the whole reason the rule takes `now`.
    private static let now = Date(timeIntervalSince1970: 1_757_500_000)

    private static let aMinute = TimeInterval(minutes: 1)
    private static let sixHours = TimeInterval(hours: 6)

    private func lastRun(_ stopReason: ObvInboxDrainStopReason,
                         _ whatWasLearnedAboutTheInbox: ObvInboxDrainWindowSchedule.WhatWasLearnedAboutTheInbox,
                         theStaleSettingsPassLeftRowsHeld: Bool = false,
                         startedAt: Date = ObvInboxDrainWindowScheduleTests.now) -> ObvInboxDrainWindowSchedule.WhatTheLastRunLeft {
        .init(stopReason: stopReason, whatWasLearnedAboutTheInbox: whatWasLearnedAboutTheInbox, theStaleSettingsPassLeftRowsHeld: theStaleSettingsPassLeftRowsHeld, startedAt: startedAt)
    }

    private func earliestBeginDate(after lastRun: ObvInboxDrainWindowSchedule.WhatTheLastRunLeft?) -> Date {
        ObvInboxDrainWindowSchedule.earliestBeginDate(after: lastRun, now: Self.now)
    }


    // MARK: A run cut off with work outstanding comes back in a minute

    /// The normal ending of a background window: the system takes it away because the user picked the device up.
    func testAWindowTakenAwayWithWorkOutstandingAsksAgainInAMinute() {
        let date = earliestBeginDate(after: lastRun(.weWereAskedToStop, .thereIsWorkOutstanding))
        XCTAssertEqual(date, Self.now.addingTimeInterval(Self.aMinute))
    }

    /// The loop standing itself down on its own ceiling, with rows still owed.
    func testTheDeadlinePassingWithWorkOutstandingAsksAgainInAMinute() {
        let date = earliestBeginDate(after: lastRun(.theDeadlinePassed, .thereIsWorkOutstanding))
        XCTAssertEqual(date, Self.now.addingTimeInterval(Self.aMinute))
    }

    /// Standing down to stay inside the memory limit leaves the work exactly as resumable as the other two.
    func testRunningOutOfMemoryHeadroomWithWorkOutstandingAsksAgainInAMinute() {
        let date = earliestBeginDate(after: lastRun(.weRanOutOfMemoryHeadroom, .thereIsWorkOutstanding))
        XCTAssertEqual(date, Self.now.addingTimeInterval(Self.aMinute))
    }

    /// **The one that is easy to get backwards.** A run that never reached the server learnt nothing about the inbox,
    /// and the network may be back in a minute — where a backlog that cannot move will still not move in six hours.
    /// Folded into `nothingWasMovingAnyMore`, as it was before this case existed, it would take the long interval.
    func testAServerThatCouldNotBeReachedAsksAgainInAMinute() {
        let date = earliestBeginDate(after: lastRun(.theServerCouldNotBeReached, .thereIsWorkOutstanding))
        XCTAssertEqual(date, Self.now.addingTimeInterval(Self.aMinute))
    }

    /// And with nothing outstanding it waits, like everything else: there is no point being woken every minute over an
    /// inbox that was empty last time we could see it.
    func testAServerThatCouldNotBeReachedWithNothingOutstandingWaitsSixHours() {
        let date = earliestBeginDate(after: lastRun(.theServerCouldNotBeReached, .thereIsNothingOutstanding))
        XCTAssertEqual(date, Self.now.addingTimeInterval(Self.sixHours))
    }

    /// A run started hours ago and cut off a moment ago still comes back in a minute: the short interval is counted
    /// from *now*, not from when the run began, which is what the six-hour case does instead.
    func testTheMinuteIsCountedFromNowRatherThanFromWhenTheRunStarted() {
        let startedLongAgo = Self.now.addingTimeInterval(-Self.sixHours)
        let date = earliestBeginDate(after: lastRun(.theDeadlinePassed, .thereIsWorkOutstanding, startedAt: startedLongAgo))
        XCTAssertEqual(date, Self.now.addingTimeInterval(Self.aMinute))
    }


    /// The expiration handler writes the last published snapshot, and for the first moments of a run that snapshot has
    /// no figures in it, so a cold background launch terminated in its first second reports `weWereAskedToStop` with
    /// nothing counted. Read as *no work*, that asked for the next window six hours later, over a backlog it had never
    /// looked at.
    func testAWindowTakenAwayBeforeItCouldCountAnythingAsksAgainInAMinute() {
        let date = earliestBeginDate(after: lastRun(.weWereAskedToStop, .theInboxWasNeverRead))
        XCTAssertEqual(date, Self.now.addingTimeInterval(Self.aMinute))
    }


    // MARK: A run that found nothing waits the ordinary interval

    func testARunThatFoundNothingLeftToDoWaitsSixHours() {
        let date = earliestBeginDate(after: lastRun(.thereWasNothingLeftToDo, .thereIsNothingOutstanding))
        XCTAssertEqual(date, Self.now.addingTimeInterval(Self.sixHours))
    }

    /// Rows may well remain — a message waiting for a contact, one whose attachment nobody has tapped — and asking
    /// again in a minute would find exactly the same ones.
    func testNothingMovingAnyMoreWaitsSixHoursEvenWithRowsOutstanding() {
        let date = earliestBeginDate(after: lastRun(.nothingWasMovingAnyMore, .thereIsWorkOutstanding))
        XCTAssertEqual(date, Self.now.addingTimeInterval(Self.sixHours))
    }

    /// The pair a run produces when the stale-settings pass gives a profile up and the listing then finds nothing: the flag makes the run read
    /// as *work outstanding*, and the stop reason alone would still say six hours. The rows are held, so a minute.
    func testAPassThatLeftRowsHeldAsksAgainInAMinuteWhateverTheEnding() {
        for stopReason in Self.everyStopReason {
            let date = earliestBeginDate(after: lastRun(stopReason, .thereIsWorkOutstanding, theStaleSettingsPassLeftRowsHeld: true))
            XCTAssertEqual(date, Self.now.addingTimeInterval(Self.aMinute), "\(stopReason.rawValue) should ask again in a minute when rows are still held")
        }
    }

    /// The same ending without the flag is the control: the listing's own verdict stands.
    func testAListingThatFoundNothingWithNoRowsHeldWaitsSixHoursThoughWorkReadsAsOutstanding() {
        let date = earliestBeginDate(after: lastRun(.thereWasNothingLeftToDo, .thereIsWorkOutstanding))
        XCTAssertEqual(date, Self.now.addingTimeInterval(Self.sixHours))
    }

    /// A store we could not read will not become readable in a minute.
    func testCountsThatCouldNotBeReadWaitSixHours() {
        let date = earliestBeginDate(after: lastRun(.theCountsCouldNotBeRead, .thereIsWorkOutstanding))
        XCTAssertEqual(date, Self.now.addingTimeInterval(Self.sixHours))
    }

    func testADrainThatCouldNotBeStartedWaitsSixHours() {
        let date = earliestBeginDate(after: lastRun(.theDrainCouldNotBeStarted, .thereIsWorkOutstanding))
        XCTAssertEqual(date, Self.now.addingTimeInterval(Self.sixHours))
    }

    /// **The counterpart to the test above, and the whole reason the two endings are not one.** Both mean *nothing ran*,
    /// and from the inbox's point of view they are indistinguishable — neither knows a thing about it. What separates
    /// them is how long the fault lasts: a delegate that is missing is a fault in how the app is put together and will
    /// still be missing in six hours, where an app too busy to finish launching within its budget may well not be busy
    /// in a minute. Folding the two together would have put a device that is merely slow to start off until the next
    /// morning, every time.
    func testAnAppThatDidNotFinishInitializingInTimeAsksAgainInAMinute() {
        let date = earliestBeginDate(after: lastRun(.theAppDidNotFinishInitializingInTime, .thereIsWorkOutstanding))
        XCTAssertEqual(date, Self.now.addingTimeInterval(Self.aMinute))
    }

    /// And the same when that run never read the inbox, which is in fact the only state it can be in — it gave the
    /// window up before the delegate existed, so nothing ever counted anything.
    func testAnAppThatDidNotFinishInitializingInTimeAsksAgainInAMinuteHavingReadNothing() {
        let date = earliestBeginDate(after: lastRun(.theAppDidNotFinishInitializingInTime, .theInboxWasNeverRead))
        XCTAssertEqual(date, Self.now.addingTimeInterval(Self.aMinute))
    }

    /// **Standing aside settles nothing, so it comes back rather than standing down.** It waited six hours before, on the
    /// reasoning that such a run "cannot be reached with work outstanding" — true of a `Bool` that had no way to say
    /// *unknown*, and wrong in the direction that costs a night: the run that *was* going may be the one from the
    /// settings row, which asks for no window when it finishes.
    func testARunThatStoodAsideAsksAgainInAMinute() {
        let date = earliestBeginDate(after: lastRun(.anotherDrainWasAlreadyRunning, .theInboxWasNeverRead))
        XCTAssertEqual(date, Self.now.addingTimeInterval(Self.aMinute))
    }

    /// **The six hours run from when the last run *started*, not from when it ended**, which is what the other two
    /// processing tasks do and what keeps a long run from pushing the whole cadence out by its own duration.
    func testTheSixHoursAreCountedFromWhenTheRunStarted() {
        let startedTenMinutesAgo = Self.now.addingTimeInterval(-TimeInterval(minutes: 10))
        let date = earliestBeginDate(after: lastRun(.thereWasNothingLeftToDo, .thereIsNothingOutstanding, startedAt: startedTenMinutesAgo))
        XCTAssertEqual(date, startedTenMinutesAgo.addingTimeInterval(Self.sixHours))
    }

    /// A report old enough that its six hours have already elapsed asks for a window now rather than for one in the
    /// past. `scheduleBackgroundTasks()` reaches this every time a device has not been on a charger for a day.
    func testAnOldReportAsksForAWindowNowRatherThanInThePast() {
        let startedYesterday = Self.now.addingTimeInterval(-TimeInterval(hours: 24))
        let date = earliestBeginDate(after: lastRun(.thereWasNothingLeftToDo, .thereIsNothingOutstanding, startedAt: startedYesterday))
        XCTAssertEqual(date, Self.now)
    }


    // MARK: No report at all

    /// Nil is the request submitted *before* the work, whose whole purpose is to survive the window ending abruptly —
    /// so it is a minute, not six hours. It is also what a device asks for before it has ever run a drain.
    func testNoReportAsksAgainInAMinute() {
        let date = earliestBeginDate(after: nil)
        XCTAssertEqual(date, Self.now.addingTimeInterval(Self.aMinute))
    }


    // MARK: Every ending is classified

    /// Exhaustive over ``ObvInboxDrainStopReason``, so that a new ending cannot be added without somebody deciding
    /// which of the two intervals it belongs to. The assertion is only that the answer is one of the two; which one
    /// is the business of the tests above.
    func testEveryStopReasonWithWorkOutstandingIsAccountedFor() {

        for stopReason in Self.everyStopReason {

            let date = earliestBeginDate(after: lastRun(stopReason, .thereIsWorkOutstanding))

            switch stopReason {
            case .weWereAskedToStop, .theDeadlinePassed, .weRanOutOfMemoryHeadroom, .theServerCouldNotBeReached, .anotherDrainWasAlreadyRunning, .theAppDidNotFinishInitializingInTime:
                XCTAssertEqual(date, Self.now.addingTimeInterval(Self.aMinute), "\(stopReason.rawValue) should ask again in a minute")
            case .thereWasNothingLeftToDo, .nothingWasMovingAnyMore, .theCountsCouldNotBeRead, .theDrainCouldNotBeStarted:
                XCTAssertEqual(date, Self.now.addingTimeInterval(Self.sixHours), "\(stopReason.rawValue) should wait the ordinary interval")
            }

        }

    }

    /// **The same sweep for a run that never read the inbox, which is the case the third answer exists for.** Every
    /// ending is classified again rather than trusting that *unknown* behaves like *outstanding*, because two endings
    /// deliberately do not: a store that could not be counted and a drain that could not be started are both permanent
    /// enough to be worth standing down over, where a window taken away before its first count is not.
    func testEveryStopReasonWithTheInboxNeverReadIsAccountedFor() {

        for stopReason in Self.everyStopReason {

            let date = earliestBeginDate(after: lastRun(stopReason, .theInboxWasNeverRead))

            switch stopReason {
            case .weWereAskedToStop, .theDeadlinePassed, .weRanOutOfMemoryHeadroom, .theServerCouldNotBeReached, .anotherDrainWasAlreadyRunning, .theAppDidNotFinishInitializingInTime:
                XCTAssertEqual(date, Self.now.addingTimeInterval(Self.aMinute), "\(stopReason.rawValue) should ask again in a minute")
            case .theCountsCouldNotBeRead, .theDrainCouldNotBeStarted:
                XCTAssertEqual(date, Self.now.addingTimeInterval(Self.sixHours), "\(stopReason.rawValue) should wait the ordinary interval")
            case .thereWasNothingLeftToDo, .nothingWasMovingAnyMore:
                // Unreachable in practice — both are concluded *from* the counts — and classified anyway rather than
                // left to a `default`, so that the compiler goes on being the thing that notices a new ending.
                XCTAssertEqual(date, Self.now.addingTimeInterval(Self.sixHours), "\(stopReason.rawValue) should wait the ordinary interval")
            }

        }

    }

    /// **Nothing outstanding waits, whatever the ending** — the one answer that is about the inbox rather than about the
    /// window, and the reason the tri-state is read before the stop reason rather than after it.
    func testNothingOutstandingWaitsSixHoursWhateverTheEnding() {

        for stopReason in Self.everyStopReason {
            let date = earliestBeginDate(after: lastRun(stopReason, .thereIsNothingOutstanding))
            XCTAssertEqual(date, Self.now.addingTimeInterval(Self.sixHours), "\(stopReason.rawValue) should wait the ordinary interval")
        }

    }

    // MARK: What a report says about the inbox

    /// The facts a report holds, every one of them saying *nothing outstanding* unless a test says otherwise: counts at nought, the listing finished, and
    /// a pass that had nothing to examine. Each test below changes the one fact it is about.
    private func report(theServerStillHadMoreAtTheEnd: Bool? = false,
                        theStaleSettingsPassStoppedEarly: Bool? = nil,
                        theStaleSettingsPassHadSomethingToExamine: Bool = false,
                        theStaleSettingsPassHasEnded: Bool = false,
                        numberOfMessagesNotYetDecryptedAtEnd: Int? = 0,
                        numberOfMessagesAwaitingTheAppAtEnd: Int? = 0,
                        numberOfMessagesStillToBeRemovedAtEnd: Int? = 0) -> ObvInboxDrainWindowSchedule.WhatTheReportHolds {
        .init(theServerStillHadMoreAtTheEnd: theServerStillHadMoreAtTheEnd,
              theStaleSettingsPassStoppedEarly: theStaleSettingsPassStoppedEarly,
              theStaleSettingsPassHadSomethingToExamine: theStaleSettingsPassHadSomethingToExamine,
              theStaleSettingsPassHasEnded: theStaleSettingsPassHasEnded,
              numberOfMessagesNotYetDecryptedAtEnd: numberOfMessagesNotYetDecryptedAtEnd,
              numberOfMessagesAwaitingTheAppAtEnd: numberOfMessagesAwaitingTheAppAtEnd,
              numberOfMessagesStillToBeRemovedAtEnd: numberOfMessagesStillToBeRemovedAtEnd)
    }

    private func learned(_ report: ObvInboxDrainWindowSchedule.WhatTheReportHolds) -> ObvInboxDrainWindowSchedule.WhatWasLearnedAboutTheInbox {
        ObvInboxDrainWindowSchedule.whatWasLearnedAboutTheInbox(from: report)
    }

    func testCountsAtNoughtWithTheListingFinishedMeanNothingOutstanding() {
        XCTAssertEqual(learned(report()), .thereIsNothingOutstanding)
    }

    /// **The regression this exists to pin.** A window spent entirely in the stale-settings pass and cut off by its deadline has thousands of rows still held,
    /// and a held row is in none of the counts, so the counts say nothing is outstanding. Only the pass's own word says otherwise.
    func testAPassThatStoppedEarlyMeansWorkOutstandingWhateverTheCountsSay() {
        XCTAssertEqual(learned(report(theStaleSettingsPassStoppedEarly: true, theStaleSettingsPassHadSomethingToExamine: true, theStaleSettingsPassHasEnded: true)), .thereIsWorkOutstanding)
        // Even when the counts were never read: the pass outranks them.
        XCTAssertEqual(learned(report(theStaleSettingsPassStoppedEarly: true, numberOfMessagesAwaitingTheAppAtEnd: nil, numberOfMessagesStillToBeRemovedAtEnd: nil)), .thereIsWorkOutstanding)
    }

    /// The report an expiration handler stores while the pass is still running: it has a total and no end.
    func testAPassStillRunningWhenTheReportWasWrittenMeansWorkOutstanding() {
        XCTAssertEqual(learned(report(theStaleSettingsPassHadSomethingToExamine: true, theStaleSettingsPassHasEnded: false)), .thereIsWorkOutstanding)
    }

    func testAPassThatEndedOnItsOwnLeavesTheCountsToDecide() {
        XCTAssertEqual(learned(report(theStaleSettingsPassHadSomethingToExamine: true, theStaleSettingsPassHasEnded: true)), .thereIsNothingOutstanding)
        XCTAssertEqual(learned(report(theStaleSettingsPassHadSomethingToExamine: true, theStaleSettingsPassHasEnded: true, numberOfMessagesAwaitingTheAppAtEnd: 1)), .thereIsWorkOutstanding)
    }

    /// A pass with nothing to examine never sets an end either, and that must not read as a pass still running.
    func testAPassWithNothingToExamineIsNotAPassStillRunning() {
        XCTAssertEqual(learned(report(theStaleSettingsPassHadSomethingToExamine: false, theStaleSettingsPassHasEnded: false)), .thereIsNothingOutstanding)
    }

    func testTheServerStillHoldingPagesMeansWorkOutstandingWhateverTheCountsSay() {
        XCTAssertEqual(learned(report(theServerStillHadMoreAtTheEnd: true)), .thereIsWorkOutstanding)
        XCTAssertEqual(learned(report(theServerStillHadMoreAtTheEnd: true, numberOfMessagesAwaitingTheAppAtEnd: nil, numberOfMessagesStillToBeRemovedAtEnd: nil)), .thereIsWorkOutstanding)
    }

    /// **A listing that never started is not a server that has nothing more.** The flag is nil, and nil falls through to the counts rather than counting
    /// as either answer.
    func testAListingThatNeverStartedFallsThroughToTheCounts() {
        XCTAssertEqual(learned(report(theServerStillHadMoreAtTheEnd: nil)), .thereIsNothingOutstanding)
        XCTAssertEqual(learned(report(theServerStillHadMoreAtTheEnd: nil, numberOfMessagesNotYetDecryptedAtEnd: 1)), .thereIsWorkOutstanding)
        XCTAssertEqual(learned(report(theServerStillHadMoreAtTheEnd: nil, numberOfMessagesAwaitingTheAppAtEnd: nil, numberOfMessagesStillToBeRemovedAtEnd: nil)), .theInboxWasNeverRead)
    }

    func testEachOfTheThreeCountsIsWork() {
        XCTAssertEqual(learned(report(numberOfMessagesNotYetDecryptedAtEnd: 1)), .thereIsWorkOutstanding)
        XCTAssertEqual(learned(report(numberOfMessagesAwaitingTheAppAtEnd: 1)), .thereIsWorkOutstanding)
        XCTAssertEqual(learned(report(numberOfMessagesStillToBeRemovedAtEnd: 1)), .thereIsWorkOutstanding)
    }

    /// An older report has no undecrypted count, which reads as nought — the safe direction — and never as *unread*.
    func testAMissingUndecryptedCountReadsAsNought() {
        XCTAssertEqual(learned(report(numberOfMessagesNotYetDecryptedAtEnd: nil)), .thereIsNothingOutstanding)
    }

    func testCountsThatWereNeverReadMeanTheInboxWasNeverRead() {
        XCTAssertEqual(learned(report(numberOfMessagesAwaitingTheAppAtEnd: nil)), .theInboxWasNeverRead)
        XCTAssertEqual(learned(report(numberOfMessagesStillToBeRemovedAtEnd: nil)), .theInboxWasNeverRead)
    }


    /// **Written out rather than taken from `CaseIterable`**, deliberately: a list the compiler generates would grow
    /// on its own and this test would go on passing over a case nobody had thought about, which is the opposite of
    /// what it is for. The switch above is what makes forgetting one a compile error.
    private static let everyStopReason: [ObvInboxDrainStopReason] = [
        .thereWasNothingLeftToDo,
        .theDeadlinePassed,
        .weWereAskedToStop,
        .nothingWasMovingAnyMore,
        .theServerCouldNotBeReached,
        .weRanOutOfMemoryHeadroom,
        .theCountsCouldNotBeRead,
        .anotherDrainWasAlreadyRunning,
        .theDrainCouldNotBeStarted,
        .theAppDidNotFinishInitializingInTime,
    ]

}
