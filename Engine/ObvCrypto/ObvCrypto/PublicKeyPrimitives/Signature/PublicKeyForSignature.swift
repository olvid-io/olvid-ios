/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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

protocol PublicKeyForSignature: CryptographicKeyForSignature {}

extension PublicKeyForSignature {
    func isEqualTo(other: PublicKeyForSignature) -> Bool {
        guard self.algorithmImplementationByteId == other.algorithmImplementationByteId else { return false }
        switch self.algorithmImplementationByteId {
        case .EC_SDSA_with_MDC,
             .EC_SDSA_with_Curve25519:
            return self as! PublicKeyForSignatureOnEdwardsCurve == other as! PublicKeyForSignatureOnEdwardsCurve
        }
    }
}

final class PublicKeyForSignatureDecoder: ObvDecoder {
    static func obvDecode(_ encodedPublicKey: ObvEncoded) -> PublicKeyForSignature? {
        guard encodedPublicKey.byteId == .publicKey else { return nil }
        guard let (algorithmClassByteId, implementationByteIdValue, obvDic) = CryptographicKeyDecoder.obvDecode(encodedPublicKey) else { return nil }
        guard algorithmClassByteId == .signature else { return nil }
        guard let implementationByteId = SignatureImplementationByteId(rawValue: implementationByteIdValue) else { return nil }
        switch implementationByteId {
        case .EC_SDSA_with_MDC:
            return PublicKeyForSignatureOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: .MDCByteId)
        case .EC_SDSA_with_Curve25519:
            return PublicKeyForSignatureOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: .Curve25519ByteId)
        }
    }
}

struct PublicKeyForSignatureOnEdwardsCurve: PublicKeyForSignature, PublicKeyFromEdwardsCurvePoint {
    
    let point: PointOnCurve?
    
    private let _yCoordinate: BigInt
    var yCoordinate: BigInt {
        return point?.y ?? _yCoordinate
    }
    
    private let _curveByteId: EdwardsCurveByteId
    var curveByteId: EdwardsCurveByteId {
        return point?.onCurveWithByteId ?? _curveByteId
    }
    
    var algorithmImplementationByteIdValue: UInt8 {
        switch curveByteId {
        case .MDCByteId:
            return SignatureImplementationByteId.EC_SDSA_with_MDC.rawValue
        case .Curve25519ByteId:
            return SignatureImplementationByteId.EC_SDSA_with_Curve25519.rawValue
        }
    }
    
    init?(point: PointOnCurve) {
        //guard !PublicKeyForDHOnEdwardsCurve.isLowOrderPoint(point) else { return nil }
        self.point = point
        self._yCoordinate = point.y
        self._curveByteId = point.onCurveWithByteId
    }
    
    init?(yCoordinate y: BigInt, curveByteId: EdwardsCurveByteId) {
        //guard !PublicKeyForDHOnEdwardsCurve.isLowOrderPoint(yCoordinate: y, onCurveWithByteId: curveByteId) else { return nil }
        self._yCoordinate = y
        self._curveByteId = curveByteId
        point = nil
    }
}

// Implementing ObvDecodable
extension PublicKeyForSignatureOnEdwardsCurve {
    init?(_ obvEncoded: ObvEncoded) {
        guard let publicKey = PublicKeyForSignatureDecoder.obvDecode(obvEncoded) as? PublicKeyForSignatureOnEdwardsCurve else { return nil }
        self = publicKey
    }
}
