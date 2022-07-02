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

protocol PrivateKeyFromEdwardsCurveScalar: CryptographicKey, Equatable {
    
    var scalar: BigInt { get }
    var curveByteId: EdwardsCurveByteId { get }
    var curve: EdwardsCurve { get }
    
    init?(obvDictionary: ObvDictionary, curveByteId: EdwardsCurveByteId)
    init?(scalar: BigInt, curveByteId: EdwardsCurveByteId)

}

extension PrivateKeyFromEdwardsCurveScalar {
    
    init?(obvDictionary obvDic: ObvDictionary, curveByteId: EdwardsCurveByteId) {
        guard let encodedScalar = obvDic[PointOnCurve.ObvDictionaryKey.forScalar.data] else { return nil }
        guard let scalar = BigInt(encodedScalar) else { return nil }
        self.init(scalar: scalar, curveByteId: curveByteId)
    }
    
    var curve: EdwardsCurve {
        return curveByteId.curve
    }
    
    var correspondingObvEncodedByteId: ByteIdOfObvEncoded {
        return .privateKey
    }

}

// Implementing Equatable
extension PrivateKeyFromEdwardsCurveScalar {
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.algorithmClass == rhs.algorithmClass else { return false }
        guard lhs.algorithmImplementationByteIdValue == rhs.algorithmImplementationByteIdValue else { return false }
        guard lhs.curveByteId == rhs.curveByteId else { return false }
        guard lhs.scalar == rhs.scalar else { return false }
        return true
    }
}

extension PrivateKeyFromEdwardsCurveScalar {
    var obvDictionaryOfInternalElements: ObvDictionary {
        return [PointOnCurve.ObvDictionaryKey.forScalar.data: self.scalar.obvEncode()]
    }
}
