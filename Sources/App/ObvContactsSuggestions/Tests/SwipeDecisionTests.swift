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
@testable import ObvContactsSuggestions


final class SwipeDecisionTests: XCTestCase {

    private let width: CGFloat = 300

    func testASlowDragPastTheThresholdAccepts() {
        XCTAssertEqual(SwipeDecision.decide(translation: 120, predictedEndTranslation: 125, cardWidth: width), .accept)
    }

    func testASlowDragPastTheThresholdToTheLeftDeclines() {
        XCTAssertEqual(SwipeDecision.decide(translation: -120, predictedEndTranslation: -125, cardWidth: width), .decline)
    }

    func testAShortSlowDragCancels() {
        XCTAssertEqual(SwipeDecision.decide(translation: 60, predictedEndTranslation: 70, cardWidth: width), .cancel)
        XCTAssertEqual(SwipeDecision.decide(translation: -60, predictedEndTranslation: -70, cardWidth: width), .cancel)
    }

    func testAShortFlickCounts() {
        XCTAssertEqual(SwipeDecision.decide(translation: 40, predictedEndTranslation: 260, cardWidth: width), .accept)
        XCTAssertEqual(SwipeDecision.decide(translation: -40, predictedEndTranslation: -260, cardWidth: width), .decline)
    }

    func testAFlickBackTowardsTheCentreCancels() {
        // Far enough to the right, but thrown back to the left on release.
        XCTAssertEqual(SwipeDecision.decide(translation: 120, predictedEndTranslation: -40, cardWidth: width), .cancel)
    }

    func testAFlickAgainstTheDragDoesNotDecideTheOtherWay() {
        // The finger is slightly to the right but flicked hard to the left: that is not a decline of a card dragged right.
        XCTAssertEqual(SwipeDecision.decide(translation: 10, predictedEndTranslation: -300, cardWidth: width), .cancel)
    }

    func testNoWidthNeverDecides() {
        XCTAssertEqual(SwipeDecision.decide(translation: 500, predictedEndTranslation: 500, cardWidth: 0), .cancel)
    }

    func testProgressIsCappedAtOne() {
        XCTAssertEqual(SwipeDecision.progress(translation: 0, cardWidth: width), 0)
        XCTAssertEqual(SwipeDecision.progress(translation: width * SwipeDecision.distanceThreshold, cardWidth: width), 1, accuracy: 0.0001)
        XCTAssertEqual(SwipeDecision.progress(translation: -width, cardWidth: width), 1)
    }

    /// The haptic is felt at the decision line, so the line must be where a slow drag starts to decide, on both sides.
    func testTheDecisionLineIsWhereASlowDragStartsToDecide() {
        let line = width * SwipeDecision.distanceThreshold
        for translation in [line - 1, -(line - 1)] {
            XCTAssertFalse(SwipeDecision.isPastTheDecisionLine(translation: translation, cardWidth: width))
            XCTAssertEqual(SwipeDecision.decide(translation: translation, predictedEndTranslation: translation, cardWidth: width), .cancel)
        }
        XCTAssertTrue(SwipeDecision.isPastTheDecisionLine(translation: line + 1, cardWidth: width))
        XCTAssertEqual(SwipeDecision.decide(translation: line + 1, predictedEndTranslation: line + 1, cardWidth: width), .accept)
        XCTAssertTrue(SwipeDecision.isPastTheDecisionLine(translation: -(line + 1), cardWidth: width))
        XCTAssertEqual(SwipeDecision.decide(translation: -(line + 1), predictedEndTranslation: -(line + 1), cardWidth: width), .decline)
    }

    func testNoWidthIsNeverPastTheDecisionLine() {
        XCTAssertFalse(SwipeDecision.isPastTheDecisionLine(translation: 500, cardWidth: 0))
    }

}
