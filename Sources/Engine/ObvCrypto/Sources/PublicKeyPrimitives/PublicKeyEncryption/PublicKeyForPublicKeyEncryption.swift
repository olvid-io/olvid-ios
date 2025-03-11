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
import ObvBigInt


public protocol PublicKeyForPublicKeyEncryption: CryptographicKeyForPublicKeyEncryption, CompactableCryptographicKey {}

extension PublicKeyForPublicKeyEncryption {
    func isEqualTo(other: PublicKeyForPublicKeyEncryption) -> Bool {
        guard self.algorithmImplementationByteId == other.algorithmImplementationByteId else { return false }
        switch self.algorithmImplementationByteId {
        case .KEM_ECIES_MDC_and_DEM_CTR_AES_256_then_HMAC_SHA_256,
             .KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256:
            return self as! PublicKeyForPublicKeyEncryptionOnEdwardsCurve == other as! PublicKeyForPublicKeyEncryptionOnEdwardsCurve
        }
    }
}

final public class PublicKeyForPublicKeyEncryptionDecoder: ObvDecoder {
    public static func obvDecode(_ encodedPublicKey: ObvEncoded) -> PublicKeyForPublicKeyEncryption? {
        guard encodedPublicKey.byteId == .publicKey else { return nil }
        guard let (algorithmClassByteId, implementationByteIdValue, obvDic) = CryptographicKeyDecoder.obvDecode(encodedPublicKey) else { return nil }
        guard algorithmClassByteId == .publicKeyEncryption else { return nil }
        guard let implementationByteId = PublicKeyEncryptionImplementationByteId(rawValue: implementationByteIdValue) else { return nil }
        switch implementationByteId {
        case .KEM_ECIES_MDC_and_DEM_CTR_AES_256_then_HMAC_SHA_256:
            return PublicKeyForPublicKeyEncryptionOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: .MDCByteId)
        case .KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256:
            return PublicKeyForPublicKeyEncryptionOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: .Curve25519ByteId)
        }
    }
    public static func obvDecodeCompactKey(_ encodedCompactPublicKey: ObvEncoded) -> PublicKeyForPublicKeyEncryption? {
        guard let compactKey: Data = try? encodedCompactPublicKey.obvDecode() else { assertionFailure(); return nil }
        guard let encryptionKey = CompactPublicKeyForPublicKeyEncryptionExpander.expand(compactKey: compactKey) else { assertionFailure(); return nil }
        return encryptionKey
    }
}

final class CompactPublicKeyForPublicKeyEncryptionExpander: CompactCryptographicKeyExpander {
    
    static func expand(compactKey: Data) -> PublicKeyForPublicKeyEncryption? {
        guard let implementationByteIdValue: UInt8 = compactKey.first else { return nil }
        guard let implementationByteId = PublicKeyEncryptionImplementationByteId(rawValue: implementationByteIdValue) else { return nil }
        switch implementationByteId {
        case .KEM_ECIES_MDC_and_DEM_CTR_AES_256_then_HMAC_SHA_256,
                .KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256:
            return PublicKeyForPublicKeyEncryptionOnEdwardsCurve(fromCompactKey: compactKey)
        }
    }
    
    static func getCompactKeyLength(fromAlgorithmImplementationByteIdValue implementationByteIdValue: UInt8) -> Int? {
        guard let implementationByteId = PublicKeyEncryptionImplementationByteId(rawValue: implementationByteIdValue) else { return nil }
        switch implementationByteId {
        case .KEM_ECIES_MDC_and_DEM_CTR_AES_256_then_HMAC_SHA_256,
             .KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256:
            return PublicKeyForPublicKeyEncryptionOnEdwardsCurve.getCompactKeyLength(fromAlgorithmImplementationByteId: implementationByteId)
        }
    }
    
}


struct PublicKeyForPublicKeyEncryptionOnEdwardsCurve: PublicKeyForPublicKeyEncryption, PublicKeyFromEdwardsCurvePoint {
    
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
            return PublicKeyEncryptionImplementationByteId.KEM_ECIES_MDC_and_DEM_CTR_AES_256_then_HMAC_SHA_256.rawValue
        case .Curve25519ByteId:
            return PublicKeyEncryptionImplementationByteId.KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256.rawValue
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
extension PublicKeyForPublicKeyEncryptionOnEdwardsCurve {
    init?(_ obvEncoded: ObvEncoded) {
        guard let publicKey = PublicKeyForPublicKeyEncryptionDecoder.obvDecode(obvEncoded) as? PublicKeyForPublicKeyEncryptionOnEdwardsCurve else { return nil }
        self = publicKey
    }
}

// Implementing CompactableCryptographicKey
extension PublicKeyForPublicKeyEncryptionOnEdwardsCurve {
    
    init?(fromCompactKey compactKey: Data) {
        guard let implementationByteIdValue: UInt8 = compactKey.first else { return nil }
        guard let implementationByteId = PublicKeyEncryptionImplementationByteId(rawValue: implementationByteIdValue) else { return nil }
        guard let algorithmImplementation = implementationByteId.algorithmImplementation as? ECIESwithEdwardsCurveandDEMwithCTRAES256thenHMACSHA256.Type else { return nil }
        let expectedCompactKeyLength = 1 + algorithmImplementation.curve.parameters.p.byteSize()
        guard compactKey.count == expectedCompactKeyLength else { return nil }
        let curveByteId = algorithmImplementation.curve.byteId
        let yCoordinateAsData = compactKey[compactKey.startIndex+1..<compactKey.endIndex]
        let encodedY = ObvEncoded(byteId: .unsignedBigInt, innerData: yCoordinateAsData)
        guard let yCoordinate = BigInt(encodedY) else { return nil }
        self.init(yCoordinate: yCoordinate, curveByteId: curveByteId)
    }
    
    static func getCompactKeyLength(fromAlgorithmImplementationByteIdValue value: UInt8) -> Int? {
        guard let implementationByteId = PublicKeyEncryptionImplementationByteId(rawValue: value) else { return nil }
        guard let algorithmImplementation = implementationByteId.algorithmImplementation as? ECIESwithEdwardsCurveandDEMwithCTRAES256thenHMACSHA256.Type else { return nil }
        let expectedCompactKeyLength = 1 + algorithmImplementation.curve.parameters.p.byteSize()
        return expectedCompactKeyLength
    }
    
    static func getCompactKeyLength(fromAlgorithmImplementationByteId implemByteId: PublicKeyEncryptionImplementationByteId) -> Int {
        return getCompactKeyLength(fromAlgorithmImplementationByteIdValue: implemByteId.rawValue)!
    }

}
