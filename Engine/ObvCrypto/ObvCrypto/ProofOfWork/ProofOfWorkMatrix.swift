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

struct Matrix {
    
    let columns: [Column]
    
    init?(from seed: Seed) {
        let PRNGType = ObvCryptoSuite.sharedInstance.concretePRNG()
        let prng = PRNGType.init(with: seed)
        let bytes = prng.genBytes(count: ProofOfWorkEngineSyndromeBasedConstants.numberOfBytesPerMatrix)
        var columns = [Column].init()
        var columnIndex = 0
        for i in stride(from: bytes.startIndex, to: bytes.endIndex, by: ProofOfWorkEngineSyndromeBasedConstants.numberOfBytesPerColumn) {
            let localBytes = bytes[i..<i+ProofOfWorkEngineSyndromeBasedConstants.numberOfBytesPerColumn]
            columns.append(Column(indexes: [columnIndex], bytes: localBytes)!)
            columnIndex += 1
        }
        self.columns = columns
    }
}
