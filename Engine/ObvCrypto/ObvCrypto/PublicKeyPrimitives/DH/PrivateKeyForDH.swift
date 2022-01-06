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
import BigInt
import ObvEncoder

protocol PrivateKeyForDH: CryptographicKeyForDH {}

extension PrivateKeyForDH {
    func isEqualTo(other: PrivateKeyForDH) -> Bool {
        guard self.algorithmImplementationByteId == other.algorithmImplementationByteId else { return false }
        switch self.algorithmImplementationByteId {
        case .DH_on_MDC,
             .DH_on_Curve25519:
            return self as! PrivateKeyForDHOnEdwardsCurve == other as! PrivateKeyForDHOnEdwardsCurve
        }
    }
}

final class PrivateKeyForDHDecoder: ObvDecoder {
    static func decode(_ encodedKey: ObvEncoded) -> PrivateKeyForDH? {
        guard encodedKey.byteId == .privateKey else { return nil }
        guard let (algorithmClassByteId, implementationByteIdValue, obvDic) = CryptographicKeyDecoder.decode(encodedKey) else { return nil }
        guard algorithmClassByteId == .DH else { return nil }
        guard let implementationByteId = DHImplementationByteId(rawValue: implementationByteIdValue) else { return nil }
        switch implementationByteId {
        case .DH_on_MDC:
            return PrivateKeyForDHOnEdwardsCurve(obvDictionary: obvDic, curveByteId: .MDCByteId)
        case .DH_on_Curve25519:
            return PrivateKeyForDHOnEdwardsCurve(obvDictionary: obvDic, curveByteId: .Curve25519ByteId)
        }
    }
}

struct PrivateKeyForDHOnEdwardsCurve: PrivateKeyForDH, PrivateKeyFromEdwardsCurveScalar {
    
    let scalar: BigInt
    let curveByteId: EdwardsCurveByteId
    
    var algorithmImplementationByteIdValue: UInt8 {
        switch curveByteId {
        case .MDCByteId:
            return DHImplementationByteId.DH_on_MDC.rawValue
        case .Curve25519ByteId:
            return DHImplementationByteId.DH_on_Curve25519.rawValue
        }
    }
    
    init(scalar: BigInt, curveByteId: EdwardsCurveByteId) {
        self.scalar = scalar
        self.curveByteId = curveByteId
    }
}


// Implementing ObvCodable
extension PrivateKeyForDHOnEdwardsCurve {
    init?(_ obvEncoded: ObvEncoded) {
        guard let privateKey = PrivateKeyForDHDecoder.decode(obvEncoded) as? PrivateKeyForDHOnEdwardsCurve else { return nil }
        self = privateKey
    }
}
