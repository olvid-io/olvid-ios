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
@testable import ObvTypes


/// What a drain owes, and in particular what it does *not*.
///
/// These are here rather than beside the drain because this is where the arithmetic lives, and because the drain itself cannot be reached from a test: its
/// loop needs an engine, a backlog and a device. `ObvInboxDrainReport.whatWasLearnedAboutTheInbox` restates the same rule over the report's optional figures and is
/// **not** covered here — that file reaches into the app target, which the hostless test target cannot compile. Keep the two in step by hand.
final class ObvInboxCountsTests: XCTestCase {

    private func counts(total: Int, notYetDecrypted: Int = 0, awaitingTheApp: Int = 0, markedForDeletion: Int = 0, waitingForAManualDownload: Int?, belongingToAnInactiveOwnedIdentity: Int? = nil) -> ObvInboxCounts {
        .init(numberOfMessages: total,
              numberOfMessagesNotYetDecrypted: notYetDecrypted,
              numberOfMessagesAwaitingTheApp: awaitingTheApp,
              numberOfMessagesMarkedForDeletion: markedForDeletion,
              numberOfMessagesWaitingForAManualDownload: waitingForAManualDownload,
              numberOfMessagesBelongingToAnInactiveOwnedIdentity: belongingToAnInactiveOwnedIdentity)
    }


    // MARK: What a sweep can actually take

    /// The case measured on a simulator on 2026-09-11: one photograph the reader chose not to download, its message marked for deletion and its attachment
    /// not. The drain read this as one message owed and could not report that it had finished.
    func testAMessageWaitingForAManualDownloadIsNotOwedWork() {
        let counts = counts(total: 1, markedForDeletion: 1, waitingForAManualDownload: 1)
        XCTAssertEqual(counts.numberOfMessagesStillToBeRemoved, 0)
        XCTAssertEqual(counts.numberOfMessagesStillOwed, 0)
    }

    func testAMessageTheSweepCanTakeIsOwedWork() {
        let counts = counts(total: 1, markedForDeletion: 1, waitingForAManualDownload: 0)
        XCTAssertEqual(counts.numberOfMessagesStillToBeRemoved, 1)
        XCTAssertEqual(counts.numberOfMessagesStillOwed, 1)
    }

    func testTheTwoPopulationsAreSubtractedRatherThanAdded() {
        let counts = counts(total: 100, markedForDeletion: 70, waitingForAManualDownload: 8)
        XCTAssertEqual(counts.numberOfMessagesStillToBeRemoved, 62)
        XCTAssertEqual(counts.numberOfMessagesStillOwed, 62)
    }

    /// The two counts describe one instant, so this should not arise; arithmetic does not know that, and a reader is owed a count rather than a negative
    /// number.
    func testMoreWaitingThanMarkedIsClampedRatherThanNegative() {
        let counts = counts(total: 5, markedForDeletion: 2, waitingForAManualDownload: 3)
        XCTAssertEqual(counts.numberOfMessagesStillToBeRemoved, 0)
        XCTAssertEqual(counts.numberOfMessagesStillOwed, 0)
    }


    // MARK: A count that was not asked for

    /// Nil is *nobody counted this*, never *there are none* — so it answers the whole marked population and the caller is told there may be work. A drain
    /// then runs another round it did not need, where the opposite reading would have it stand down over a backlog it never looked at.
    func testACountThatWasNotAskedForErrsTowardsThereBeingWork() {
        let counts = counts(total: 1, markedForDeletion: 1, waitingForAManualDownload: nil)
        XCTAssertEqual(counts.numberOfMessagesStillToBeRemoved, 1)
        XCTAssertEqual(counts.numberOfMessagesStillOwed, 1)
    }


    // MARK: The states that are nobody's work either

    /// The gap between the total and the sum of the rest: a message on hold, one waiting for a contact, one that could never be decrypted. Nought owed with
    /// rows still held is the ordinary state of a healthy device, and is what lets a drain say it has finished.
    func testRowsInNoneOfTheStatesAreNotOwedWork() {
        let counts = counts(total: 12, waitingForAManualDownload: 0)
        XCTAssertEqual(counts.numberOfMessagesStillOwed, 0)
        XCTAssertEqual(counts.numberOfMessages, 12)
    }

    /// The trap this sum exists to close, kept here so it cannot be undone by accident: a hundred thousand freshly-listed messages, nothing decrypted yet.
    func testAFreshlyListedBacklogIsOwedWork() {
        let counts = counts(total: 100_000, notYetDecrypted: 100_000, waitingForAManualDownload: 0)
        XCTAssertEqual(counts.numberOfMessagesStillOwed, 100_000)
    }

    func testAnEmptyInboxOwesNothing() {
        XCTAssertEqual(counts(total: 0, waitingForAManualDownload: 0).numberOfMessagesStillOwed, 0)
    }


    // MARK: Movement

    /// Two readings that asked different questions are not comparable, and this is the one place that could quietly make a round look busy.
    func testAReadingThatAskedForTheFifthCountDiffersFromOneThatDidNot() {
        let asked = counts(total: 1, markedForDeletion: 1, waitingForAManualDownload: 1)
        let notAsked = counts(total: 1, markedForDeletion: 1, waitingForAManualDownload: nil)
        XCTAssertFalse(asked.nothingMovedSince(notAsked))
        XCTAssertTrue(asked.nothingMovedSince(asked))
    }

    /// Growth is movement: a round that *added* messages is a listing doing its job, not a barren round.
    func testAnInboxThatGrewCountsAsHavingMoved() {
        let before = counts(total: 10, notYetDecrypted: 10, waitingForAManualDownload: 0)
        let after = counts(total: 510, notYetDecrypted: 510, waitingForAManualDownload: 0)
        XCTAssertFalse(after.nothingMovedSince(before))
    }

}
