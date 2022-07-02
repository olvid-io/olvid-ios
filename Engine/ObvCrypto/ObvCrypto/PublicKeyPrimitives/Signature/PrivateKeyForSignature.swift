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

protocol PrivateKeyForSignature: CryptographicKeyForSignature {}

extension PrivateKeyForSignature {
    func isEqualTo(other: PrivateKeyForSignature) -> Bool {
        guard self.algorithmImplementationByteId == other.algorithmImplementationByteId else { return false }
        switch self.algorithmImplementationByteId {
        case .EC_SDSA_with_MDC,
             .EC_SDSA_with_Curve25519:
            return self as! PrivateKeyForSignatureOnEdwardsCurve == other as! PrivateKeyForSignatureOnEdwardsCurve
        }
    }
}

final class PrivateKeyForSignatureDecoder: ObvDecoder {
    static func obvDecode(_ encodedKey: ObvEncoded) -> PrivateKeyForSignature? {
        guard encodedKey.byteId == .privateKey else { return nil }
        guard let (algorithmClassByteId, implementationByteIdValue, obvDic) = CryptographicKeyDecoder.obvDecode(encodedKey) else { return nil }
        guard algorithmClassByteId == .signature else { return nil }
        guard let implementationByteId = SignatureImplementationByteId(rawValue: implementationByteIdValue) else { return nil }
        switch implementationByteId {
        case .EC_SDSA_with_MDC:
            return PrivateKeyForSignatureOnEdwardsCurve(obvDictionary: obvDic, curveByteId: .MDCByteId)
        case .EC_SDSA_with_Curve25519:
            return PrivateKeyForSignatureOnEdwardsCurve(obvDictionary: obvDic, curveByteId: .Curve25519ByteId)
        }
    }
}

struct PrivateKeyForSignatureOnEdwardsCurve: PrivateKeyForSignature, PrivateKeyFromEdwardsCurveScalar {
    
    let scalar: BigInt
    let curveByteId: EdwardsCurveByteId
    
    var algorithmImplementationByteIdValue: UInt8 {
        switch curveByteId {
        case .MDCByteId:
            return SignatureImplementationByteId.EC_SDSA_with_MDC.rawValue
        case .Curve25519ByteId:
            return SignatureImplementationByteId.EC_SDSA_with_Curve25519.rawValue
        }
    }
    
    init(scalar: BigInt, curveByteId: EdwardsCurveByteId) {
        self.scalar = BigInt(scalar)
        self.curveByteId = curveByteId
    }
}


// Implementing ObvCodable
extension PrivateKeyForSignatureOnEdwardsCurve {
    init?(_ obvEncoded: ObvEncoded) {
        guard let privateKey = PrivateKeyForSignatureDecoder.obvDecode(obvEncoded) as? PrivateKeyForSignatureOnEdwardsCurve else { return nil }
        self = privateKey
    }
}
