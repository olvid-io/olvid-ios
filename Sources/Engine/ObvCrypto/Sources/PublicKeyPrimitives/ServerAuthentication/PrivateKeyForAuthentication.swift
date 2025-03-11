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
import ObvBigInt
import ObvEncoder

public protocol PrivateKeyForAuthentication: CryptographicKeyForAuthentication {}

extension PrivateKeyForAuthentication {
    func isEqualTo(other: PrivateKeyForAuthentication) -> Bool {
        guard self.algorithmImplementationByteId == other.algorithmImplementationByteId else { return false }
        switch self.algorithmImplementationByteId {
        case .Signature_with_EC_SDSA_with_MDC,
             .Signature_with_EC_SDSA_with_Curve25519:
            return self as! PrivateKeyForAuthenticationFromSignatureOnEdwardsCurve == other as! PrivateKeyForAuthenticationFromSignatureOnEdwardsCurve
        }
    }
}

public final class PrivateKeyForAuthenticationDecoder: ObvDecoder {
    public static func obvDecode(_ encodedKey: ObvEncoded) -> PrivateKeyForAuthentication? {
        guard encodedKey.byteId == .privateKey else { return nil }
        guard let (algorithmClassByteId, implementationByteIdValue, obvDic) = CryptographicKeyDecoder.obvDecode(encodedKey) else { return nil }
        guard algorithmClassByteId == .authentication else { return nil }
        guard let implementationByteId = AuthenticationImplementationByteId(rawValue: implementationByteIdValue) else { return nil }
        switch implementationByteId {
        case .Signature_with_EC_SDSA_with_MDC:
            return PrivateKeyForAuthenticationFromSignatureOnEdwardsCurve(obvDictionary: obvDic, curveByteId: .MDCByteId)
        case .Signature_with_EC_SDSA_with_Curve25519:
            return PrivateKeyForAuthenticationFromSignatureOnEdwardsCurve(obvDictionary: obvDic, curveByteId: .Curve25519ByteId)
        }
    }
    public static func obvDecodeOrThrow(_ encodedKey: ObvEncoded) throws -> PrivateKeyForAuthentication {
        guard let key = Self.obvDecode(encodedKey) else { assertionFailure(); throw ObvError.decodingFailed}
        return key
    }
    enum ObvError: Error {
        case decodingFailed
    }
}

struct PrivateKeyForAuthenticationFromSignatureOnEdwardsCurve: PrivateKeyForAuthentication, PrivateKeyFromEdwardsCurveScalar {
    
    let privateKeyForSignatureOnEdwardsCurve: PrivateKeyForSignatureOnEdwardsCurve
    
    var scalar: BigInt {
        return privateKeyForSignatureOnEdwardsCurve.scalar
    }
    
    var curveByteId: EdwardsCurveByteId {
        return privateKeyForSignatureOnEdwardsCurve.curveByteId
    }
    
    var algorithmImplementationByteIdValue: UInt8 {
        let signatureImplementationByteId = privateKeyForSignatureOnEdwardsCurve.algorithmImplementationByteId
        switch signatureImplementationByteId {
        case .EC_SDSA_with_MDC:
            return AuthenticationImplementationByteId.Signature_with_EC_SDSA_with_MDC.rawValue
        case .EC_SDSA_with_Curve25519:
            return AuthenticationImplementationByteId.Signature_with_EC_SDSA_with_Curve25519.rawValue
        }
    }
    
    init(scalar: BigInt, curveByteId: EdwardsCurveByteId) {
        privateKeyForSignatureOnEdwardsCurve = PrivateKeyForSignatureOnEdwardsCurve(scalar: scalar, curveByteId: curveByteId)
    }
}

// Implementing ObvCodable
extension PrivateKeyForAuthenticationFromSignatureOnEdwardsCurve {
    init?(_ obvEncoded: ObvEncoded) {
        guard let privateKey = PrivateKeyForAuthenticationDecoder.obvDecode(obvEncoded) as? PrivateKeyForAuthenticationFromSignatureOnEdwardsCurve else { return nil }
        self = privateKey
    }
}
