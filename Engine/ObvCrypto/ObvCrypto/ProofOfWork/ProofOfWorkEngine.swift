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
import BigInt

public protocol ProofOfWorkEngine {
    static func solve(_: ObvEncoded) -> ObvEncoded?
}

struct ProofOfWorkEngineSyndromeBasedConstants {
    static let numberOfLines = 128 // Must be a multiple of 64
    static let numberOfColumns = 256
    
    static var numberOfUInt64PerColumn: Int {
        return numberOfLines / 64
    }
    
    static var numberOfBytesPerColumn: Int {
        return numberOfLines / 8
    }
    
    static var numberOfBytesPerMatrix: Int {
        return numberOfLines*numberOfColumns / 8
    }
}

final class ProofOfWorkEngineSyndromeBased: ProofOfWorkEngine {
    
    static func solve(_ challenge: ObvEncoded) -> ObvEncoded? {
        guard let (H, S) = decode(challenge) else { return nil }
        var (setHalf, setHalfS) = computeAllPairwiseColumnsXor(of: H, alsoXoring: S)
        // Removes from setHalf the columns (of this set) that aren’t also in setHalfS
        setHalf.formIntersection(setHalfS)
        // At this point, each column in setHalf contains two indices that are part of a solution made of 4 indices.
        // We consider a arbitrary column of setHalf, and look for a column with identical value in setHalfS.
        // Once found, we will deduce the 4 indices (i.e., the final solution).
        guard let columnFromSetHalf = setHalf.first else { return nil }
        let columnFromSetHalfS = setHalfS[setHalfS.firstIndex(of: columnFromSetHalf)!]
        let indexes = (columnFromSetHalf.indexes + columnFromSetHalfS.indexes).sorted()
        return encode(indexes)
    }
    
    private static func computeAllPairwiseColumnsXor(of H: Matrix, alsoXoring S: Column) -> (Set<Column>, Set<Column>) {
        let expectedNumberOfColumns = H.columns.count * (H.columns.count+1) / 2
        var pairwiseColumnXors = Set<Column>.init(minimumCapacity: expectedNumberOfColumns)
        var pairwiseColumnXorsWithS = Set<Column>.init(minimumCapacity: expectedNumberOfColumns)
        for i in 1..<H.columns.count {
            let firstColumn = H.columns[i]
            for j in 0..<i {
                let secondColumn = H.columns[j]
                let newColumn = firstColumn.xor(secondColumn)
                pairwiseColumnXors.update(with: newColumn)
                pairwiseColumnXorsWithS.update(with: newColumn.xor(S))
            }
        }
        return (pairwiseColumnXors, pairwiseColumnXorsWithS)
    }
    
    private static func decode(_ challenge: ObvEncoded) -> (H: Matrix, S: Column)? {
        guard let listOfEncodedElements = [ObvEncoded](challenge) else { return nil }
        guard listOfEncodedElements.count == 2 else { return nil }
        // Decode H
        guard let seed = Seed(listOfEncodedElements[0]) else { return nil }
        guard let H = Matrix(from: seed) else { return nil }
        // Decode S
        guard let bytesForColumnS = Data(listOfEncodedElements[1]) else { return nil }
        guard let S = Column.init(indexes: [Int](), bytes: bytesForColumnS) else { return nil }
        // Return
        return (H, S)
    }
    
    private static func encode(_ indexes: [Int]) -> ObvEncoded? {
        let listOfEncodedIndexes = indexes.map() { $0.obvEncode() }
        return listOfEncodedIndexes.obvEncode()
    }
 
}
