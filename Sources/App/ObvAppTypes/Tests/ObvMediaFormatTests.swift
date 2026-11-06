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

import Testing
import ObvAppTypes


/// The weight a size is encoded under: that of the lightest larger size.
struct ObvMediaFormatTests {

    @Test func theLightestLargerSizeIsReturned() {
        let lightest = ObvMediaFormat.lightestSize(largerThan: .low, among: [.max: 4_000, .hi: 3_000, .med: 1_000])
        #expect(lightest?.format == .med)
        #expect(lightest?.byteCount == 1_000)
    }

    @Test func onlyLargerSizesAreConsidered() {
        let lightest = ObvMediaFormat.lightestSize(largerThan: .hi, among: [.max: 4_000, .med: 1_000, .low: 500])
        #expect(lightest?.format == .max)
        #expect(lightest?.byteCount == 4_000)
    }

    /// A larger size that points at the original weighs the same as `max`, and `max` is returned.
    @Test func atEqualWeightTheLargestSizeIsReturned() {
        let lightest = ObvMediaFormat.lightestSize(largerThan: .med, among: [.max: 4_000, .hi: 4_000])
        #expect(lightest?.format == .max)
    }

    /// A size whose encode failed has no weight, and the next larger size is used instead.
    @Test func aLargerSizeWithNoWeightIsSkipped() {
        let lightest = ObvMediaFormat.lightestSize(largerThan: .low, among: [.max: 4_000, .hi: 3_000])
        #expect(lightest?.format == .hi)
    }

    @Test func nothingIsLargerThanMax() {
        #expect(ObvMediaFormat.lightestSize(largerThan: .max, among: [.max: 4_000, .hi: 3_000]) == nil)
    }

}
