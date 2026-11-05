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


/// Which progress reports of a draft's video export reach the composition bar.
final class ExportProgressReportFilterTests: XCTestCase {

    /// A fraction accepted after its export's nil would leave a ring over a finished clip.
    func testAFractionArrivingAfterItsOwnNilIsDropped() {
        var filter = ExportProgressReportFilter<String>()
        XCTAssertTrue(filter.accepts(0, for: "A", generation: 1))
        XCTAssertTrue(filter.accepts(0.5, for: "A", generation: 1))
        XCTAssertTrue(filter.accepts(nil, for: "A", generation: 1))
        XCTAssertFalse(filter.accepts(0.87, for: "A", generation: 1))
    }

    /// The nil of a cancelled pass, arriving after the pass that replaced it reported the clip as waiting.
    func testAnOlderNilArrivingAfterANewerReportIsDropped() {
        var filter = ExportProgressReportFilter<String>()
        XCTAssertTrue(filter.accepts(0, for: "B", generation: 2))
        XCTAssertTrue(filter.accepts(0, for: "B", generation: 5))
        XCTAssertFalse(filter.accepts(nil, for: "B", generation: 2))
    }

    func testAnOlderFractionArrivingAfterANewerReportIsDropped() {
        var filter = ExportProgressReportFilter<String>()
        XCTAssertTrue(filter.accepts(0, for: "A", generation: 3))
        XCTAssertTrue(filter.accepts(0.1, for: "A", generation: 6))
        XCTAssertFalse(filter.accepts(0.9, for: "A", generation: 3))
    }

    /// The same clip is exported again when the reader changes size.
    func testANewerGenerationIsAcceptedAfterANil() {
        var filter = ExportProgressReportFilter<String>()
        XCTAssertTrue(filter.accepts(0.5, for: "A", generation: 1))
        XCTAssertTrue(filter.accepts(nil, for: "A", generation: 1))
        XCTAssertTrue(filter.accepts(0, for: "A", generation: 2))
        XCTAssertTrue(filter.accepts(0.3, for: "A", generation: 2))
    }

    func testANilIsAcceptedOnceForItsGeneration() {
        var filter = ExportProgressReportFilter<String>()
        XCTAssertTrue(filter.accepts(nil, for: "A", generation: 1))
        XCTAssertFalse(filter.accepts(nil, for: "A", generation: 1))
    }

    func testKeysAreIndependent() {
        var filter = ExportProgressReportFilter<String>()
        XCTAssertTrue(filter.accepts(0, for: "A", generation: 7))
        XCTAssertTrue(filter.accepts(0, for: "B", generation: 2))
        XCTAssertTrue(filter.accepts(nil, for: "A", generation: 7))
        XCTAssertTrue(filter.accepts(0.4, for: "B", generation: 2))
    }

}
