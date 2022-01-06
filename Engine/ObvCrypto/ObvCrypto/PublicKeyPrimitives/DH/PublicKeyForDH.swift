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

protocol PublicKeyForDH: CryptographicKeyForDH {}

extension PublicKeyForDH {
    func isEqualTo(other: PublicKeyForDH) -> Bool {
        guard self.algorithmImplementationByteId == other.algorithmImplementationByteId else { return false }
        switch self.algorithmImplementationByteId {
        case .DH_on_MDC,
             .DH_on_Curve25519:
            return self as! PublicKeyForDHOnEdwardsCurve == other as! PublicKeyForDHOnEdwardsCurve
        }
    }
}

final class PublicKeyForDHDecoder: ObvDecoder {
    static func decode(_ encodedPublicKey: ObvEncoded) -> PublicKeyForDH? {
        guard encodedPublicKey.byteId == .publicKey else { return nil }
        guard let (algorithmClassByteId, implementationByteIdValue, obvDic) = CryptographicKeyDecoder.decode(encodedPublicKey) else { return nil }
        guard algorithmClassByteId == .DH else { return nil }
        guard let implementationByteId = DHImplementationByteId(rawValue: implementationByteIdValue) else { return nil }
        switch implementationByteId {
        case .DH_on_MDC:
            return PublicKeyForDHOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: .MDCByteId)
        case .DH_on_Curve25519:
            return PublicKeyForDHOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: .Curve25519ByteId)
        }
    }
}

struct PublicKeyForDHOnEdwardsCurve: PublicKeyForDH, PublicKeyFromEdwardsCurvePoint {
    
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
            return DHImplementationByteId.DH_on_MDC.rawValue
        case .Curve25519ByteId:
            return DHImplementationByteId.DH_on_Curve25519.rawValue
        }
    }
    
    init?(point: PointOnCurve) {
        guard PublicKeyForDHOnEdwardsCurve.isAcceptable(point: point) else { return nil }
        self.point = point
        self._yCoordinate = point.y
        self._curveByteId = point.onCurveWithByteId
    }
    
    init?(yCoordinate y: BigInt, curveByteId: EdwardsCurveByteId) {
        guard PublicKeyForDHOnEdwardsCurve.isAcceptable(yCoordinate: y, onCurveWithByteId: curveByteId) else { return nil }
        self._yCoordinate = y
        self._curveByteId = curveByteId
        point = nil
    }
}

// Implementing ObvCodable
extension PublicKeyForDHOnEdwardsCurve {
    init?(_ obvEncoded: ObvEncoded) {
        guard let publicKey = PublicKeyForDHDecoder.decode(obvEncoded) as? PublicKeyForDHOnEdwardsCurve else { return nil }
        self = publicKey
    }
}
