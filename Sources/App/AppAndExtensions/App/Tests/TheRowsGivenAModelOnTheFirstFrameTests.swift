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


/// Which rows of a discussion are given a model before its first frame.
final class TheRowsGivenAModelOnTheFirstFrameTests: XCTestCase {

    private func range(around index: Int, amongRows numberOfRows: Int) -> Range<Int> {
        TheRowsGivenAModelOnTheFirstFrame.range(around: index, amongRows: numberOfRows, size: 25)
    }

    /// With nothing unread the discussion opens on its last message, and gets the last 25 rows.
    func testTheEndGetsTheLastRows() {
        XCTAssertEqual(range(around: 99, amongRows: 100), 75..<100)
    }

    /// The marker near the end gets the rows an entry with nothing unread gets. A clipped window would keep only its upper half: 13 rows with one unread message.
    func testTheMarkerNearTheEndGetsTheSameRowsAsTheEnd() {
        XCTAssertEqual(range(around: 98, amongRows: 100), 75..<100)
        XCTAssertEqual(range(around: 90, amongRows: 100), 75..<100)
    }

    /// The marker far from both ends: twelve rows above it and twelve below.
    func testTheMarkerFarFromBothEndsIsCentred() {
        XCTAssertEqual(range(around: 50, amongRows: 100), 38..<63)
    }

    func testTheMarkerNearTheTopGetsAWholeWindow() {
        XCTAssertEqual(range(around: 3, amongRows: 100), 0..<25)
    }

    func testADiscussionShorterThanTheWindowIsTakenWhole() {
        XCTAssertEqual(range(around: 7, amongRows: 10), 0..<10)
    }

    /// An empty discussion opens on index -1, as it has no last message.
    func testAnEmptyDiscussionGetsNoRows() {
        XCTAssertEqual(range(around: -1, amongRows: 0), 0..<0)
    }

    func testEveryPositionGetsAWholeWindowHoldingTheRowItOpensOn() {
        for numberOfRows in [1, 24, 25, 26, 100] {
            for index in 0..<numberOfRows {
                let window = range(around: index, amongRows: numberOfRows)
                XCTAssertEqual(window.count, min(25, numberOfRows), "rows=\(numberOfRows) index=\(index)")
                XCTAssertTrue(window.contains(index), "rows=\(numberOfRows) index=\(index)")
                XCTAssertGreaterThanOrEqual(window.lowerBound, 0, "rows=\(numberOfRows) index=\(index)")
                XCTAssertLessThanOrEqual(window.upperBound, numberOfRows, "rows=\(numberOfRows) index=\(index)")
            }
        }
    }

}
