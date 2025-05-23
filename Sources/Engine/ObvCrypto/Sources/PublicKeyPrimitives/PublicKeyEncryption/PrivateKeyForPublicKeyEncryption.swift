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
import ObvBigInt

public protocol PrivateKeyForPublicKeyEncryption: CryptographicKeyForPublicKeyEncryption {}

extension PrivateKeyForPublicKeyEncryption {
    func isEqualTo(other: PrivateKeyForPublicKeyEncryption) -> Bool {
        guard self.algorithmImplementationByteId == other.algorithmImplementationByteId else { return false }
        switch self.algorithmImplementationByteId {
        case .KEM_ECIES_MDC_and_DEM_CTR_AES_256_then_HMAC_SHA_256,
             .KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256:
            return self as! PrivateKeyForPublicKeyEncryptionOnEdwardsCurve == other as! PrivateKeyForPublicKeyEncryptionOnEdwardsCurve
        }
    }
}

final public class PrivateKeyForPublicKeyEncryptionDecoder: ObvDecoder {
    public static func obvDecode(_ encodedKey: ObvEncoded) -> PrivateKeyForPublicKeyEncryption? {
        guard encodedKey.byteId == .privateKey else { return nil }
        guard let (algorithmClassByteId, implementationByteIdValue, obvDic) = CryptographicKeyDecoder.obvDecode(encodedKey) else { return nil }
        guard algorithmClassByteId == .publicKeyEncryption else { return nil }
        guard let implementationByteId = PublicKeyEncryptionImplementationByteId(rawValue: implementationByteIdValue) else { return nil }
        switch implementationByteId {
        case .KEM_ECIES_MDC_and_DEM_CTR_AES_256_then_HMAC_SHA_256:
            return PrivateKeyForPublicKeyEncryptionOnEdwardsCurve(obvDictionary: obvDic, curveByteId: .MDCByteId)
        case .KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256:
            return PrivateKeyForPublicKeyEncryptionOnEdwardsCurve(obvDictionary: obvDic, curveByteId: .Curve25519ByteId)
        }
    }
    public static func obvDecodeOrThrow(_ encodedKey: ObvEncoded) throws -> PrivateKeyForPublicKeyEncryption {
        guard let key = Self.obvDecode(encodedKey) else { assertionFailure(); throw ObvError.decodingFailed}
        return key
    }
    enum ObvError: Error {
        case decodingFailed
    }
}

struct PrivateKeyForPublicKeyEncryptionOnEdwardsCurve: PrivateKeyForPublicKeyEncryption, PrivateKeyFromEdwardsCurveScalar {
    
    let scalar: BigInt
    let curveByteId: EdwardsCurveByteId
    
    var algorithmImplementationByteIdValue: UInt8 {
        switch curveByteId {
        case .MDCByteId:
            return PublicKeyEncryptionImplementationByteId.KEM_ECIES_MDC_and_DEM_CTR_AES_256_then_HMAC_SHA_256.rawValue
        case .Curve25519ByteId:
            return PublicKeyEncryptionImplementationByteId.KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256.rawValue
        }
    }
    
    init(scalar: BigInt, curveByteId: EdwardsCurveByteId) {
        self.scalar = scalar
        self.curveByteId = curveByteId
    }

}

// Implementing ObvDecodable
extension PrivateKeyForPublicKeyEncryptionOnEdwardsCurve {
    init?(_ obvEncoded: ObvEncoded) {
        guard let privateKey = PrivateKeyForPublicKeyEncryptionDecoder.obvDecode(obvEncoded) as? PrivateKeyForPublicKeyEncryptionOnEdwardsCurve else { return nil }
        self = privateKey
    }
}
