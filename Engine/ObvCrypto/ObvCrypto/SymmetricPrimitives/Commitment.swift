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

public protocol Commitment {
    static func commit(onTag: Data, andValue: Data, with: PRNG) -> (commitment: Data, decommitToken: Data)
    static func open(commitment: Data, onTag: Data, usingDecommitToken: Data) -> Data?
}

final class CommitmentWithSHA256: Commitment {
    
    private static let randomValueLength = 32
    
    static func commit(onTag tag: Data, andValue value: Data, with prng: PRNG) -> (commitment: Data, decommitToken: Data) {
        // Compute d
        var d = Data(value)
        d.append(prng.genBytes(count: CommitmentWithSHA256.randomValueLength))
        // Compute the commitment
        var dataToHash = Data(tag)
        dataToHash.append(d)
        let commitment = SHA256.hash(dataToHash)
        return (commitment, d)
    }
    
    static func open(commitment: Data, onTag tag: Data, usingDecommitToken d: Data) -> Data? {
        var value: Data? = nil
        var dataToHash = Data(tag)
        dataToHash.append(d)
        let computedCommitment = SHA256.hash(dataToHash)
        if commitment == computedCommitment {
            value = Data(d)
            value!.removeLast(CommitmentWithSHA256.randomValueLength)
        }
        return value
    }
    
}
