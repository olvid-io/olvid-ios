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

public protocol PublicKeyForAuthentication: CryptographicKeyForAuthentication, CompactableCryptographicKey {}


extension PublicKeyForAuthentication {
    func isEqualTo(other: PublicKeyForAuthentication) -> Bool {
        guard self.algorithmImplementationByteId == other.algorithmImplementationByteId else { return false }
        switch self.algorithmImplementationByteId {
        case .Signature_with_EC_SDSA_with_MDC,
             .Signature_with_EC_SDSA_with_Curve25519:
            return self as! PublicKeyForAuthenticationFromSignatureOnEdwardsCurve == other as! PublicKeyForAuthenticationFromSignatureOnEdwardsCurve
        }
    }
}

public final class PublicKeyForAuthenticationDecoder: ObvDecoder {
    public static func obvDecode(_ encodedPublicKey: ObvEncoded) -> PublicKeyForAuthentication? {
        guard encodedPublicKey.byteId == .publicKey else { return nil }
        guard let (algorithmClassByteId, implementationByteIdValue, obvDic) = CryptographicKeyDecoder.obvDecode(encodedPublicKey) else { return nil }
        guard algorithmClassByteId == .authentication else { return nil }
        guard let implementationByteId = AuthenticationImplementationByteId(rawValue: implementationByteIdValue) else { return nil }
        switch implementationByteId {
        case .Signature_with_EC_SDSA_with_MDC:
            return PublicKeyForAuthenticationFromSignatureOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: .MDCByteId)
        case .Signature_with_EC_SDSA_with_Curve25519:
            return PublicKeyForAuthenticationFromSignatureOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: .Curve25519ByteId)
        }
    }
}


// Since a PublicKeyForAuthentication implements CompactableCryptographicKey, we need a simple way to recover a PublicKeyForAuthentication from a compact key. This is what this class does.
final class CompactPublicKeyForAuthenticationExpander: CompactCryptographicKeyExpander {
    
    static func expand(compactKey: Data) -> PublicKeyForAuthentication? {
        guard let implementationByteIdValue: UInt8 = compactKey.first else { return nil }
        guard let implementationByteId = AuthenticationImplementationByteId(rawValue: implementationByteIdValue) else { return nil }
        switch implementationByteId {
        case .Signature_with_EC_SDSA_with_MDC,
             .Signature_with_EC_SDSA_with_Curve25519:
            return PublicKeyForAuthenticationFromSignatureOnEdwardsCurve(fromCompactKey: compactKey)
        }
    }
    
    static func getCompactKeyLength(fromAlgorithmImplementationByteIdValue implementationByteIdValue: UInt8) -> Int? {
        guard let implementationByteId = AuthenticationImplementationByteId(rawValue: implementationByteIdValue) else { return nil }
        switch implementationByteId {
        case .Signature_with_EC_SDSA_with_MDC,
             .Signature_with_EC_SDSA_with_Curve25519:
            return PublicKeyForAuthenticationFromSignatureOnEdwardsCurve.getCompactKeyLength(fromAlgorithmImplementationByteId: implementationByteId)
        }
    }
}


struct PublicKeyForAuthenticationFromSignatureOnEdwardsCurve: PublicKeyForAuthentication, PublicKeyFromEdwardsCurvePoint {
    
    let publicKeyForSignatureOnEdwardsCurve: PublicKeyForSignatureOnEdwardsCurve
    
    init?(yCoordinate y: BigInt, curveByteId: EdwardsCurveByteId) {
        guard let pubKey = PublicKeyForSignatureOnEdwardsCurve.init(yCoordinate: y, curveByteId: curveByteId) else { return nil }
        publicKeyForSignatureOnEdwardsCurve = pubKey
    }
    
    init?(point: PointOnCurve) {
        guard let pubKey = PublicKeyForSignatureOnEdwardsCurve(point: point) else { return nil }
        publicKeyForSignatureOnEdwardsCurve = pubKey
    }
    
    var point: PointOnCurve? {
        return publicKeyForSignatureOnEdwardsCurve.point
    }
    
    var yCoordinate: BigInt {
        return publicKeyForSignatureOnEdwardsCurve.yCoordinate
    }
    
    var curveByteId: EdwardsCurveByteId {
        return publicKeyForSignatureOnEdwardsCurve.curveByteId
    }
    
    var algorithmImplementationByteIdValue: UInt8 {
        let signatureImplementationByteId = publicKeyForSignatureOnEdwardsCurve.algorithmImplementationByteId
        switch signatureImplementationByteId {
        case .EC_SDSA_with_MDC:
            return AuthenticationImplementationByteId.Signature_with_EC_SDSA_with_MDC.rawValue
        case .EC_SDSA_with_Curve25519:
            return AuthenticationImplementationByteId.Signature_with_EC_SDSA_with_Curve25519.rawValue
        }
    }
    
}

// Implementing ObvDecodable
extension PublicKeyForAuthenticationFromSignatureOnEdwardsCurve {
    init?(_ obvEncoded: ObvEncoded) {
        guard let publicKey = PublicKeyForAuthenticationDecoder.obvDecode(obvEncoded) as? PublicKeyForAuthenticationFromSignatureOnEdwardsCurve else { return nil }
        self = publicKey
    }
}
    


// Implementing DecompactableCryptographicKey
extension PublicKeyForAuthenticationFromSignatureOnEdwardsCurve {
    
    init?(fromCompactKey compactKey: Data) {
        guard let implementationByteIdValue: UInt8 = compactKey.first else { return nil }
        guard let implementationByteId = AuthenticationImplementationByteId(rawValue: implementationByteIdValue) else { return nil }
        guard let algorithmImplementation = implementationByteId.algorithmImplementation as? AuthenticationFromSignatureOnEdwardsCurve.Type else { return nil }
        let expectedCompactKeyLength = 1 + algorithmImplementation.curve.parameters.p.byteSize()
        guard compactKey.count == expectedCompactKeyLength else { return nil }
        let curveByteId = algorithmImplementation.curve.byteId
        let yCoordinateAsData = compactKey[compactKey.startIndex+1..<compactKey.endIndex]
        let encodedY = ObvEncoded(byteId: .unsignedBigInt, innerData: yCoordinateAsData)
        guard let yCoordinate = BigInt(encodedY) else { return nil }
        self.init(yCoordinate: yCoordinate, curveByteId: curveByteId)
    }
    
    static func getCompactKeyLength(fromAlgorithmImplementationByteIdValue value: UInt8) -> Int? {
        guard let implementationByteId = AuthenticationImplementationByteId(rawValue: value) else { return nil }
        guard let algorithmImplementation = implementationByteId.algorithmImplementation as? AuthenticationFromSignatureOnEdwardsCurve.Type else { return nil }
        let expectedCompactKeyLength = 1 + algorithmImplementation.curve.parameters.p.byteSize()
        return expectedCompactKeyLength
    }
    
    static func getCompactKeyLength(fromAlgorithmImplementationByteId implemByteId: AuthenticationImplementationByteId) -> Int {
        return getCompactKeyLength(fromAlgorithmImplementationByteIdValue: implemByteId.rawValue)!
    }

}
