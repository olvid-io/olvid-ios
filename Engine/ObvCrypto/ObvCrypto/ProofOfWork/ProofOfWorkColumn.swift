/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import ObvEncoder

struct Column {
    
    let indexes: [Int] // List of the matrix indexes used to compute this column
    let val: [UInt64]
    
    init?(indexes: [Int], val: [UInt64]) {
        guard val.count == ProofOfWorkEngineSyndromeBasedConstants.numberOfUInt64PerColumn else { return nil }
        self.indexes = indexes
        self.val = val
    }
    
    init?(indexes: [Int], bytes: Data) {
        guard bytes.count == ProofOfWorkEngineSyndromeBasedConstants.numberOfBytesPerColumn else { return nil }
        self.indexes = indexes
        var val = [UInt64]()
        // By stride, 8 bytes at a time (i.e., 64 bits at a time)
        for i in stride(from: bytes.startIndex, to: bytes.endIndex, by: 8) {
            var valElement = UInt64(0)
            for j in 0..<8 {
                valElement ^= UInt64(bytes[i+j]) << (j*8)
            }
            val.append(valElement)
        }
        self.val = val
    }
    
    func xor(_ other: Column) -> Column {
        var xorVal = [UInt64].init(repeating: 0, count: ProofOfWorkEngineSyndromeBasedConstants.numberOfUInt64PerColumn)
        for i in 0..<ProofOfWorkEngineSyndromeBasedConstants.numberOfUInt64PerColumn {
            xorVal[i] = self.val[i] ^ other.val[i]
        }
        let xoredIndexes = self.indexes + other.indexes
        return Column.init(indexes: xoredIndexes, val: xorVal)!
    }
}

extension Column: Hashable {
    
    /// We only consider values, not the indexes
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.val)
    }
    
}

extension Column: Equatable {

    /// We only consider values when comparing two columns (i.e., we do not consider indexes).
    static func == (lhs: Column, rhs: Column) -> Bool {
        return lhs.val == rhs.val
    }

}
