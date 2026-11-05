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


/// How far through a backlog's timeline a drain says it has walked.
///
/// **The third part of this feature a test can reach, and the one with the worst record.** The fraction has had two defects that only a device ever showed:
/// a bar reading nought for a whole run while the count beside it climbed past a thousand, and — the reason the positions now come from the messages the app
/// has stored rather than from the listing — a run in which the drain was not the one listing and therefore had no position at all.
final class ObvInboxDrainBacklogWalkTests: XCTestCase {

    /// The moment the run began: the far end of every walk below.
    private static let start = 1_757_500_000_000

    /// A minute of backlog before that moment.
    private static let aMinuteBefore = start - 60_000
    private static let halfAMinuteBefore = start - 30_000

    private func walk() -> ObvInboxDrainBacklogWalk {
        .init(millisecondsAtTheStartOfTheRun: Self.start)
    }


    // MARK: Having no position at all

    /// **Nil is not nought.** A run that has not yet stored a message has nothing to say, and a bar at nought there says the opposite of what is happening.
    func testNoPositionAtAllAnswersNil() {
        var walk = walk()
        XCTAssertNil(walk.fractionWalked(positionsInMilliseconds: []))
        XCTAssertFalse(walk.aPositionHasBeenEstablished)
    }


    /// Asked repeatedly with nothing, it must go on saying nothing rather than settling on a floor.
    func testNoPositionStaysNilHowManyTimesItIsAsked() {
        var walk = walk()
        for _ in 0..<10 {
            XCTAssertNil(walk.fractionWalked(positionsInMilliseconds: []))
        }
        XCTAssertFalse(walk.aPositionHasBeenEstablished)
    }


    // MARK: The walk itself

    /// One position is an anchor and nothing more: the walk starts where it starts, so the fraction is nought — but a position now *exists*, which is a
    /// different thing from having none and is what the screen reads to decide whether to draw a bar at all.
    func testTheFirstPositionAnchorsTheWalk() {
        var walk = walk()
        XCTAssertEqual(walk.fractionWalked(positionsInMilliseconds: [Self.aMinuteBefore]), 0)
        XCTAssertTrue(walk.aPositionHasBeenEstablished)
    }


    /// Half way through the span is half the bar.
    func testHalfOfTheSpanIsHalfOfTheBar() {
        var walk = walk()
        _ = walk.fractionWalked(positionsInMilliseconds: [Self.aMinuteBefore])
        let fraction = walk.fractionWalked(positionsInMilliseconds: [Self.halfAMinuteBefore])
        XCTAssertEqual(try XCTUnwrap(fraction), 0.5, accuracy: 0.0001)
    }


    /// **A span given in one call is measured, not thrown away.** The oldest and newest messages the app has stored arrive together, so a walk that only
    /// looked at the newest of them would anchor on it and report nought on a backlog it can already see the extent of.
    func testAnEarliestAndALatestInOneCallMeasureTheSpanBetweenThem() {
        var walk = walk()
        let fraction = walk.fractionWalked(positionsInMilliseconds: [Self.aMinuteBefore, Self.halfAMinuteBefore])
        XCTAssertEqual(try XCTUnwrap(fraction), 0.5, accuracy: 0.0001)
    }


    /// The furthest position given is what counts, whatever order they arrive in.
    func testTheFurthestPositionIsTheOneThatCounts() {
        var walk = walk()
        _ = walk.fractionWalked(positionsInMilliseconds: [Self.aMinuteBefore])
        let fraction = walk.fractionWalked(positionsInMilliseconds: [Self.halfAMinuteBefore, Self.aMinuteBefore + 1_000])
        XCTAssertEqual(try XCTUnwrap(fraction), 0.5, accuracy: 0.0001)
    }


    // MARK: Never going backwards

    /// Messages are expected in timestamp order and not promised to be in it, so a position behind the last one must not pull the bar back.
    func testAPositionOutOfOrderDoesNotMoveTheBarBack() {
        var walk = walk()
        _ = walk.fractionWalked(positionsInMilliseconds: [Self.aMinuteBefore])
        let reached = try? XCTUnwrap(walk.fractionWalked(positionsInMilliseconds: [Self.halfAMinuteBefore]))
        let afterGoingBack = walk.fractionWalked(positionsInMilliseconds: [Self.aMinuteBefore + 1_000])
        XCTAssertEqual(try XCTUnwrap(afterGoingBack), try XCTUnwrap(reached))
    }


    /// **An earlier position widens the span rather than moving the bar.** The anchor is the smallest ever seen, so a position before anything yet seen
    /// makes the walk longer — which is the safe direction, the alternative being a fraction above 1 that has to be clipped.
    func testAnEarlierPositionWidensTheSpanWithoutLoweringTheBar() {
        var walk = walk()
        _ = walk.fractionWalked(positionsInMilliseconds: [Self.aMinuteBefore])
        let before = try? XCTUnwrap(walk.fractionWalked(positionsInMilliseconds: [Self.halfAMinuteBefore]))
        let afterWidening = walk.fractionWalked(positionsInMilliseconds: [Self.start - 120_000])
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(afterWidening), try XCTUnwrap(before))
    }


    // MARK: The ends of the walk

    /// A backlog whose whole span is shorter than a millisecond, or a device clock behind the server's, leaves nothing to divide by. Say nothing rather than
    /// assert a number.
    func testAPositionAtOrAfterTheStartOfTheRunHasNoSpanToMeasure() {
        var walk = walk()
        XCTAssertNil(walk.fractionWalked(positionsInMilliseconds: [Self.start]))
        XCTAssertFalse(walk.aPositionHasBeenEstablished)
    }


    /// **Passing the frontier means the walk is spent, not that the work is done.** Messages keep arriving while a drain runs, and one uploaded after the run
    /// began carries a timestamp past the far end. Clipping to 1 there reads as *finished* and the high-water mark then holds it there for the rest of the run.
    func testPassingTheFrontierStopsShortOfTheEnd() {
        var walk = walk()
        _ = walk.fractionWalked(positionsInMilliseconds: [Self.aMinuteBefore])
        let fraction = walk.fractionWalked(positionsInMilliseconds: [Self.start + 5_000])
        XCTAssertEqual(try XCTUnwrap(fraction), ObvInboxDrainBacklogWalk.asFarAsTheWalkCanClaim)
        XCTAssertLessThan(try XCTUnwrap(fraction), 1)
    }


    /// The walk never claims the end on its own, however far along it gets: the last of the bar belongs to the server saying it has nothing left.
    func testTheWalkNeverReachesOne() {
        var walk = walk()
        _ = walk.fractionWalked(positionsInMilliseconds: [Self.aMinuteBefore])
        let fraction = walk.fractionWalked(positionsInMilliseconds: [Self.start - 1])
        XCTAssertLessThanOrEqual(try XCTUnwrap(fraction), ObvInboxDrainBacklogWalk.asFarAsTheWalkCanClaim)
    }


    // MARK: The exact count taking over

    /// Once the server says it has nothing more, what remains is local work and a count of it is exact — so this one may reach the end where the walk may not.
    func testTheExactCountMayReachTheEnd() {
        var walk = walk()
        XCTAssertEqual(walk.fractionFromTheExactCount(done: 500, outstanding: 0), 1)
        XCTAssertTrue(walk.aPositionHasBeenEstablished)
    }


    /// The exact count is held to the same high-water mark as the walk: the inbox empties and refills mid-run, and a bar that retreats reads as a fault.
    func testTheExactCountDoesNotLowerTheBar() {
        var walk = walk()
        let higher = walk.fractionFromTheExactCount(done: 900, outstanding: 100)
        let lower = walk.fractionFromTheExactCount(done: 100, outstanding: 900)
        XCTAssertEqual(lower, higher)
    }


    /// A count taking over from the walk may only raise the bar.
    func testTheExactCountDoesNotUndoTheWalk() {
        var walk = walk()
        _ = walk.fractionWalked(positionsInMilliseconds: [Self.aMinuteBefore])
        let walked = try? XCTUnwrap(walk.fractionWalked(positionsInMilliseconds: [Self.start - 1_000]))
        let counted = walk.fractionFromTheExactCount(done: 1, outstanding: 999)
        XCTAssertEqual(counted, try XCTUnwrap(walked))
    }


    /// Nothing done and nothing outstanding must not divide by nought.
    func testAnEmptyCountDoesNotDivideByNought() {
        var walk = walk()
        XCTAssertEqual(walk.fractionFromTheExactCount(done: 0, outstanding: 0), 0)
    }



}
