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
import Foundation
@testable import OlvidUtils


/// Tests for `Data.isLessThan(lhs:rhs:)`: the shorter data comes first, and data of the same length compare byte by byte.
struct DataIsLessThanTests {

    @Test func theShorterComesFirstWhateverItsBytes() {
        let shorter = Data([0xff, 0xff])
        let longer = Data([0x00, 0x00, 0x00])
        #expect(Data.isLessThan(lhs: shorter, rhs: longer))
        #expect(!Data.isLessThan(lhs: longer, rhs: shorter))
    }


    @Test func theEmptyDataComesFirst() {
        #expect(Data.isLessThan(lhs: Data(), rhs: Data([0x00])))
        #expect(!Data.isLessThan(lhs: Data([0x00]), rhs: Data()))
        #expect(!Data.isLessThan(lhs: Data(), rhs: Data()))
    }


    @Test func dataOfTheSameLengthCompareByteByByte() {
        let lhs = Data([0x01, 0x02, 0x03])
        let rhs = Data([0x01, 0x02, 0x04])
        #expect(Data.isLessThan(lhs: lhs, rhs: rhs))
        #expect(!Data.isLessThan(lhs: rhs, rhs: lhs))
        // The first byte that differs decides, whatever follows
        #expect(Data.isLessThan(lhs: Data([0x01, 0xff]), rhs: Data([0x02, 0x00])))
    }


    @Test func dataIsNotLessThanItself() {
        let data = Data([0x68, 0x74, 0x74, 0x70, 0x00, 0x01])
        #expect(!Data.isLessThan(lhs: data, rhs: data))
        #expect(!Data.isLessThan(lhs: data, rhs: Data(data)))
    }


    /// A slice keeps the indices of the data it comes from; the comparison must not depend on them.
    @Test func aSliceComparesByItsBytes() {
        let whole = Data([0x09, 0x01, 0x02])
        let slice = whole.dropFirst()
        #expect(slice.startIndex == 1)
        #expect(!Data.isLessThan(lhs: slice, rhs: Data([0x01, 0x02])))
        #expect(!Data.isLessThan(lhs: Data([0x01, 0x02]), rhs: slice))
        #expect(Data.isLessThan(lhs: slice, rhs: Data([0x01, 0x03])))
    }

}
