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
import ObvTypes
import OlvidUtils


/// Whether a drain of the engine's inbox runs another round.
///
/// **The second part of that feature a test can reach**, and the part the paged listing was built to fix: a round used to ask the server for its whole
/// backlog, so a budget running out could not be told from a server that was gone, and a local count could not be told from the server being empty. Both of
/// those are decided here, and both were wrong in a way that cost a device six hours.
final class ObvInboxDrainRoundDecisionTests: XCTestCase {

    private static let now = Date(timeIntervalSince1970: 1_757_500_000)

    /// An inbox with plenty to do.
    private static let busy = ObvInboxCounts(numberOfMessages: 500, numberOfMessagesNotYetDecrypted: 500, numberOfMessagesAwaitingTheApp: 0, numberOfMessagesMarkedForDeletion: 0, numberOfMessagesWaitingForAManualDownload: 0, numberOfMessagesBelongingToAnInactiveOwnedIdentity: 0)

    /// An inbox with nothing in it at all.
    private static let empty = ObvInboxCounts(numberOfMessages: 0, numberOfMessagesNotYetDecrypted: 0, numberOfMessagesAwaitingTheApp: 0, numberOfMessagesMarkedForDeletion: 0, numberOfMessagesWaitingForAManualDownload: 0, numberOfMessagesBelongingToAnInactiveOwnedIdentity: 0)

    /// An inbox holding rows a drain can never move — one unopened photograph — and nothing else. Nothing is owed, so this is *finished*, not *stalled*.
    private static let nothingOwed = ObvInboxCounts(numberOfMessages: 1, numberOfMessagesNotYetDecrypted: 0, numberOfMessagesAwaitingTheApp: 0, numberOfMessagesMarkedForDeletion: 1, numberOfMessagesWaitingForAManualDownload: 1, numberOfMessagesBelongingToAnInactiveOwnedIdentity: 0)

    /// The shape that made a healthy device report a fault for ever. Two thousand rows in the store, all belonging to a deactivated profile, so nothing
    /// lists, decrypts, marks or sweeps any of them. Counted as work, this read as two thousand messages owed, and every drain waited out its stillness
    /// bound and ended on `nothingWasMovingAnyMore`, six hours apart, for as long as the profile was kept.
    private static let strandedByADeadProfile = ObvInboxCounts(numberOfMessages: 2_000, numberOfMessagesNotYetDecrypted: 0, numberOfMessagesAwaitingTheApp: 0, numberOfMessagesMarkedForDeletion: 0, numberOfMessagesWaitingForAManualDownload: 0, numberOfMessagesBelongingToAnInactiveOwnedIdentity: 2_000)

    private func known(counts: ObvInboxCounts? = ObvInboxDrainRoundDecisionTests.busy,
                       howLongTheCountsHaveBeenUnreadable: TimeInterval? = nil,
                       isTheFirstRound: Bool = false,
                       theServerHasMore: Bool = false,
                       howLongNothingHasMoved: TimeInterval? = nil,
                       howLongTheListingHasBeenUnableToReachTheServer: TimeInterval? = nil,
                       isStopRequested: Bool = false,
                       secondsUntilTheDeadline: TimeInterval = 600,
                       headroom: ObvProcessMemory.Allowance = .bytesRemaining(500 * 1024 * 1024),
                       weKnowThisProcessIsMemoryLimited: Bool = false) -> ObvInboxDrainRoundDecision.WhatTheRunKnows {
        .init(counts: counts,
              howLongTheCountsHaveBeenUnreadable: howLongTheCountsHaveBeenUnreadable,
              isTheFirstRound: isTheFirstRound,
              theServerHasMore: theServerHasMore,
              howLongNothingHasMoved: howLongNothingHasMoved,
              howLongTheListingHasBeenUnableToReachTheServer: howLongTheListingHasBeenUnableToReachTheServer,
              isStopRequested: isStopRequested,
              deadline: Self.now.addingTimeInterval(secondsUntilTheDeadline),
              now: Self.now,
              headroom: headroom,
              weKnowThisProcessIsMemoryLimited: weKnowThisProcessIsMemoryLimited)
    }

    private func reason(_ known: ObvInboxDrainRoundDecision.WhatTheRunKnows) -> ObvInboxDrainStopReason? {
        ObvInboxDrainRoundDecision.reasonToStopBeforeAnotherRound(known)
    }


    // MARK: The server's word outranks the local counts

    /// **The case the paged listing exists for.** A page has just been listed, decrypted, stored and swept, so the inbox is momentarily empty — and the
    /// server has already said there is another page. Concluding *there was nothing left to do* here is what used to end a run with a backlog still on the
    /// server, and then, because the report said nothing was outstanding, wait six hours before asking again.
    func testAnEmptyInboxDoesNotEndTheRunWhileTheServerStillHasPages() {
        XCTAssertNil(reason(known(counts: Self.empty, theServerHasMore: true)))
    }

    func testAnInboxOwingNothingDoesNotEndTheRunWhileTheServerStillHasPages() {
        XCTAssertNil(reason(known(counts: Self.nothingOwed, theServerHasMore: true)))
    }

    /// A run whose listing is still fetching moves nothing locally for a while — the app is keeping up, or the page is large — and that must not read as a
    /// stall however long it lasts.
    func testStillnessDoesNotEndTheRunWhileTheServerStillHasPages() {
        XCTAssertNil(reason(known(counts: Self.empty, theServerHasMore: true, howLongNothingHasMoved: 3_600)))
    }

    /// The same three inputs with the server saying it is finished must give the opposite answer, or the tests above prove nothing.
    func testTheSameInboxEndsTheRunOnceTheServerSaysItIsFinished() {
        XCTAssertEqual(reason(known(counts: Self.empty, theServerHasMore: false)), .thereWasNothingLeftToDo)
        XCTAssertEqual(reason(known(counts: Self.nothingOwed, theServerHasMore: false)), .thereWasNothingLeftToDo)
        XCTAssertEqual(reason(known(counts: Self.busy, theServerHasMore: false, howLongNothingHasMoved: 30)), .nothingWasMovingAnyMore)
    }


    // MARK: Stillness is measured in seconds, not in rounds

    /// **The bound this replaced was silently invalidated once already.** It counted *rounds*, and was set to two when a round was a listing plus a wait plus
    /// a sweep — tens of seconds. The loop later became a half-second poll and nobody moved the bound, so *two rounds* quietly became *one second*, which is
    /// an ordinary pause between batches: a healthy run would have been reported as a stall, and in a night-time window that buys six hours. Expressed in
    /// seconds, re-timing the loop cannot break it, and these two cases are what say so.
    func testStillnessShorterThanTheBoundDoesNotEndTheRun() {
        XCTAssertNil(reason(known(counts: Self.busy, theServerHasMore: false, howLongNothingHasMoved: 1)))
        XCTAssertNil(reason(known(counts: Self.busy, theServerHasMore: false,
                                  howLongNothingHasMoved: ObvInboxDrainRoundDecision.stillnessThatMeansSomethingIsWrong - 1)))
    }

    /// **Nil is *the listing is still fetching*, and must never be read as nought.** A run that has not begun watching has said nothing about stillness.
    func testNoStillnessReadingDoesNotEndTheRun() {
        XCTAssertNil(reason(known(counts: Self.busy, theServerHasMore: false, howLongNothingHasMoved: nil)))
    }


    // MARK: What still outranks the server

    /// The server having more is a reason to carry on, not a reason to ignore the clock, the reader, or the memory.
    func testTheServerHavingMoreDoesNotOverrideTheDeadlineTheStopFlagOrTheMemoryFloor() {
        XCTAssertEqual(reason(known(theServerHasMore: true, secondsUntilTheDeadline: 0)), .theDeadlinePassed)
        XCTAssertEqual(reason(known(theServerHasMore: true, isStopRequested: true)), .weWereAskedToStop)
        XCTAssertEqual(reason(known(theServerHasMore: true, headroom: .bytesRemaining(1024))), .weRanOutOfMemoryHeadroom)
        XCTAssertEqual(reason(known(counts: nil, howLongTheCountsHaveBeenUnreadable: ObvInboxDrainRoundDecision.howLongTheCountsMayBeUnreadableBeforeGivingUp, theServerHasMore: true)), .theCountsCouldNotBeRead)
    }

    /// Asked before everything else, so that a reader who has left the screen is not kept waiting on a deadline that has also passed.
    func testTheStopFlagOutranksTheDeadline() {
        XCTAssertEqual(reason(known(isStopRequested: true, secondsUntilTheDeadline: 0)), .weWereAskedToStop)
    }


    // MARK: A listing that cannot reach the server

    /// A listing that has been unable to reach anybody for long enough, and the run says so rather than claiming to have finished.
    func testAListingThatCannotReachTheServerForLongEnoughEndsTheRun() {
        let bound = ObvInboxDrainRoundDecision.howLongTheServerMayBeUnreachableBeforeGivingUp
        XCTAssertNil(reason(known(howLongTheListingHasBeenUnableToReachTheServer: bound - 1)))
        XCTAssertEqual(reason(known(howLongTheListingHasBeenUnableToReachTheServer: bound)), .theServerCouldNotBeReached)
    }

    /// A listing that is merely slow is not one that cannot reach the server: only attempts that were never made at all accumulate here, so a long-running
    /// listing on a working network reports nil however long it takes.
    ///
    /// **Nil is *nothing known*, not *all is well*, and it must not be read as trouble either.** It is what every run gets before its listing has reported
    /// anything, so a rule that treated it as a failure would stop every run on its second round — which is what the first assertion pins.
    func testASlowListingIsNotAnUnreachableServer() {
        XCTAssertNil(reason(known(howLongTheListingHasBeenUnableToReachTheServer: nil)))
        XCTAssertNil(reason(known(theServerHasMore: true, howLongTheListingHasBeenUnableToReachTheServer: nil)))
    }

    /// **Asked before the local counts, and this is what proves it.** A device that could not reach the server does not know what the server holds, so an
    /// inbox that looks finished must not be allowed to answer *there was nothing left to do* — that is a confident ending drawn from a question nobody
    /// managed to ask, and it buys six hours.
    func testNotReachingTheServerOutranksAnInboxThatLooksFinished() {
        XCTAssertEqual(reason(known(counts: Self.empty, howLongTheListingHasBeenUnableToReachTheServer: ObvInboxDrainRoundDecision.howLongTheServerMayBeUnreachableBeforeGivingUp)), .theServerCouldNotBeReached)
    }


    // MARK: A count that could not be read

    /// **The failure the bound exists for, and it cost a night.** The count is taken over a store three extensions also write to, so one of them refusing is
    /// an ordinary event that the next reading a second later does not repeat — and this used to be `guard let counts`, which ended the run on the first
    /// refusal. Whatever the window had left went with it, and then six hours more: `theCountsCouldNotBeRead` is the one ending
    /// ``ObvInboxDrainWindowSchedule`` reads as an unknown that will still be unknown in a minute, so it takes the long interval even when the same report
    /// says the server still had pages.
    func testASingleUnreadableCountDoesNotEndTheRun() {
        XCTAssertNil(reason(known(counts: nil, howLongTheCountsHaveBeenUnreadable: 1)))
        XCTAssertNil(reason(known(counts: nil, howLongTheCountsHaveBeenUnreadable: 1, theServerHasMore: true)))
        XCTAssertNil(reason(known(counts: nil, howLongTheCountsHaveBeenUnreadable: ObvInboxDrainRoundDecision.howLongTheCountsMayBeUnreadableBeforeGivingUp - 1)))
    }

    /// A store that has gone on refusing for the whole of the bound is one that is not readable rather than one that was busy — which is the claim the
    /// schedule makes on the strength of this ending, and it is this test that makes the claim true rather than assumed.
    func testCountsUnreadableForTheWholeBoundEndTheRun() {
        XCTAssertEqual(reason(known(counts: nil, howLongTheCountsHaveBeenUnreadable: ObvInboxDrainRoundDecision.howLongTheCountsMayBeUnreadableBeforeGivingUp)), .theCountsCouldNotBeRead)
    }

    /// **A reading that failed is not a count, and none of the endings drawn from the counts may be reached without one.** Each of them concludes that the
    /// run is *finished*; drawing that from figures nobody read is the same class of lie as drawing it from a server nobody asked. Every input that makes
    /// those three fire is set here, with the reading missing.
    func testNoEndingIsConcludedFromCountsThatWereNotRead() {
        XCTAssertNil(reason(known(counts: nil, howLongTheCountsHaveBeenUnreadable: 1, theServerHasMore: false, howLongNothingHasMoved: 3_600)))
    }

    /// The rest of the rule still runs while the counts are missing, which is why the bound is read *before* them rather than in place of them. A
    /// `guard let` on the counts made the last two unreachable: a run whose readings had stopped coming back could not stand down for memory and could
    /// not say that the server was unreachable.
    func testTheOtherEndingsSurviveCountsThatCouldNotBeRead() {
        XCTAssertEqual(reason(known(counts: nil, howLongTheCountsHaveBeenUnreadable: 1, isStopRequested: true)), .weWereAskedToStop)
        XCTAssertEqual(reason(known(counts: nil, howLongTheCountsHaveBeenUnreadable: 1, secondsUntilTheDeadline: 0)), .theDeadlinePassed)
        XCTAssertEqual(reason(known(counts: nil, howLongTheCountsHaveBeenUnreadable: 1, headroom: .bytesRemaining(1024))), .weRanOutOfMemoryHeadroom)
        XCTAssertEqual(reason(known(counts: nil, howLongTheCountsHaveBeenUnreadable: 1, howLongTheListingHasBeenUnableToReachTheServer: ObvInboxDrainRoundDecision.howLongTheServerMayBeUnreachableBeforeGivingUp)), .theServerCouldNotBeReached)
    }


    // MARK: The first round

    /// One round always runs, however empty the inbox looks: an empty inbox says nothing about what the server still holds, and a device restored from a
    /// backup has a backlog waiting with nothing local to hint at it.
    func testTheFirstRoundAlwaysRunsWhateverTheInboxLooksLike() {
        XCTAssertNil(reason(known(counts: Self.empty, isTheFirstRound: true)))
        XCTAssertNil(reason(known(counts: Self.empty, isTheFirstRound: true, howLongNothingHasMoved: 3_600, howLongTheListingHasBeenUnableToReachTheServer: 3_600)))
    }

    /// But not at any price: the first round still yields to the reader, the clock, the counts and the memory.
    func testTheFirstRoundStillYieldsToTheFourThatComeBeforeIt() {
        XCTAssertEqual(reason(known(counts: Self.empty, isTheFirstRound: true, isStopRequested: true)), .weWereAskedToStop)
        XCTAssertEqual(reason(known(counts: Self.empty, isTheFirstRound: true, secondsUntilTheDeadline: 0)), .theDeadlinePassed)
        XCTAssertEqual(reason(known(counts: nil, howLongTheCountsHaveBeenUnreadable: ObvInboxDrainRoundDecision.howLongTheCountsMayBeUnreadableBeforeGivingUp, isTheFirstRound: true)), .theCountsCouldNotBeRead)
        XCTAssertEqual(reason(known(counts: Self.empty, isTheFirstRound: true, headroom: .bytesRemaining(1024))), .weRanOutOfMemoryHeadroom)
    }


    // MARK: The baseline that never came back

    /// **The ending has to say which of the three it was, and only one of them is expensive.** The baseline reading is retried now rather than given up on
    /// after one refusal, and a retry can be left by a reader picking the device up or by a window running out of time — neither of which is anything to do
    /// with the store. Recording those as `theCountsCouldNotBeRead` would stand the device down for six hours, which is precisely what the retry was added
    /// to avoid: the single attempt it replaced gave that answer to every failure by construction, having no other to give.
    func testTheBaselineEndingSaysWhichOfTheThreeItWas() {
        let deadline = Self.now.addingTimeInterval(600)
        XCTAssertEqual(ObvInboxDrainRoundDecision.reasonTheBaselineCouldNotBeTaken(isStopRequested: false, now: Self.now, deadline: deadline), .theCountsCouldNotBeRead)
        XCTAssertEqual(ObvInboxDrainRoundDecision.reasonTheBaselineCouldNotBeTaken(isStopRequested: true, now: Self.now, deadline: deadline), .weWereAskedToStop)
        XCTAssertEqual(ObvInboxDrainRoundDecision.reasonTheBaselineCouldNotBeTaken(isStopRequested: false, now: Self.now, deadline: Self.now), .theDeadlinePassed)
    }

    /// The stop flag outranks the deadline here as it does in the round rule, so a window whose expiration handler fires as the clock runs out is recorded as
    /// the system taking it rather than as time running out — a truer account of the run, and the two are told apart nowhere else.
    func testTheStopFlagOutranksTheDeadlineForTheBaselineToo() {
        XCTAssertEqual(ObvInboxDrainRoundDecision.reasonTheBaselineCouldNotBeTaken(isStopRequested: true, now: Self.now, deadline: Self.now), .weWereAskedToStop)
    }


    // MARK: Messages nothing will ever move

    /// A drain must call this finished. Rows belonging to a deactivated profile are never listed, decrypted, marked or swept, so treating them as work
    /// outstanding makes the run wait out its stillness bound and report the one ending that means *something is wrong*, on a device with nothing wrong
    /// with it, every six hours. Observed on a simulator: 2'000 such rows, thirty rounds, thirty-one seconds, `stopReason=nothingWasMovingAnyMore`.
    func testMessagesOfADeactivatedProfileAreNotWorkOutstanding() {
        XCTAssertEqual(Self.strandedByADeadProfile.numberOfMessagesStillOwed, 0)
        XCTAssertEqual(reason(known(counts: Self.strandedByADeadProfile)), .thereWasNothingLeftToDo)
    }

    /// The control, and the direction that would be far worse to get wrong: restricting the counts must not make a drain stand down while there is real work
    /// for a live profile. Same two thousand stranded rows, plus one message a live profile owes.
    func testALiveProfilesWorkStillCountsAlongsideStrandedRows() {
        let mixed = ObvInboxCounts(numberOfMessages: 2_001, numberOfMessagesNotYetDecrypted: 1, numberOfMessagesAwaitingTheApp: 0, numberOfMessagesMarkedForDeletion: 0, numberOfMessagesWaitingForAManualDownload: 0, numberOfMessagesBelongingToAnInactiveOwnedIdentity: 2_000)
        XCTAssertEqual(mixed.numberOfMessagesStillOwed, 1)
        XCTAssertNil(reason(known(counts: mixed)))
    }


    // MARK: The memory floor

    /// **A nought is two different facts and only one of them is a reason to stop.** `os_proc_available_memory()` answers nought both for a process with no
    /// limit — every simulator, which is where this loop is exercised — and for one that has already exceeded its limit. Believing an unqualified nought
    /// would stand the drain down on its first round on every machine we test it on, and would look exactly like the loop being broken.
    func testAnAmbiguousNoughtIsOnlyBelievedOnceALimitHasBeenSeen() {
        XCTAssertNil(reason(known(headroom: .zeroWhichIsAmbiguous, weKnowThisProcessIsMemoryLimited: false)))
        XCTAssertEqual(reason(known(headroom: .zeroWhichIsAmbiguous, weKnowThisProcessIsMemoryLimited: true)), .weRanOutOfMemoryHeadroom)
    }

    func testTheMemoryFloorIsWhereItSays() {
        XCTAssertNil(reason(known(headroom: .bytesRemaining(ObvInboxDrainRoundDecision.minimumBytesOfMemoryHeadroom))))
        XCTAssertEqual(reason(known(headroom: .bytesRemaining(ObvInboxDrainRoundDecision.minimumBytesOfMemoryHeadroom - 1))), .weRanOutOfMemoryHeadroom)
    }


    // MARK: The ordinary case

    func testAWorkingRoundCarriesOn() {
        XCTAssertNil(reason(known()))
        XCTAssertNil(reason(known(howLongNothingHasMoved: 1)))
    }

}
