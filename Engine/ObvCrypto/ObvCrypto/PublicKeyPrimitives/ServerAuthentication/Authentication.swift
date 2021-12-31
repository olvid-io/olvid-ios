/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

// MARK: Protocols

public protocol AuthenticationCommon {
    static func solve(_: Data, prefixedWith: Data, with: PrivateKeyForAuthentication, and: PublicKeyForAuthentication, using: PRNGService) -> Data?
    static func check(response: Data, toChallenge: Data, prefixedWith: Data, using: PublicKeyForAuthentication) -> Bool
}

public protocol AuthenticationConcrete: AuthenticationCommon {
    static var algorithmImplementationByteId: AuthenticationImplementationByteId { get }
    static func generateKeyPair(with: PRNGService) -> (PublicKeyForAuthentication, PrivateKeyForAuthentication)
}

protocol AuthenticationGeneric: AuthenticationCommon {
    static func generateKeyPair(for: AuthenticationImplementationByteId, with: PRNGService) -> (PublicKeyForAuthentication, PrivateKeyForAuthentication)
    static func solve(_: Data, prefixedWith: Data, for: ObvOwnedCryptoIdentity, using: PRNGService) -> Data?
    static func check(response: Data, toChallenge: Data, prefixedWith: Data, from: ObvCryptoIdentity) -> Bool
}

// MARK: Classes

public final class Authentication: AuthenticationGeneric {
    
    public static func generateKeyPair(for implemByteId: AuthenticationImplementationByteId, with prng: PRNGService) -> (PublicKeyForAuthentication, PrivateKeyForAuthentication) {
        return implemByteId.algorithmImplementation.generateKeyPair(with: prng)
    }
    
    public static func solve(_ challenge: Data, prefixedWith prefix: Data, with privateKey: PrivateKeyForAuthentication, and publicKey: PublicKeyForAuthentication, using prng: PRNGService) -> Data? {
        let algorithmImplementation = privateKey.algorithmImplementationByteId.algorithmImplementation
        return algorithmImplementation.solve(challenge, prefixedWith: prefix, with: privateKey, and: publicKey, using: prng)
    }
    
    public static func solve(_ challenge: Data, prefixedWith prefix: Data, for ownedIdentity: ObvOwnedCryptoIdentity, using prng: PRNGService) -> Data? {
        return solve(challenge, prefixedWith: prefix, with: ownedIdentity.privateKeyForAuthentication, and: ownedIdentity.publicKeyForAuthentication, using: prng)
    }
    
    public static func check(response: Data, toChallenge challenge: Data, prefixedWith prefix: Data, using pk: PublicKeyForAuthentication) -> Bool {
        let algorithmImplementation = pk.algorithmImplementationByteId.algorithmImplementation
        return algorithmImplementation.check(response: response, toChallenge: challenge, prefixedWith: prefix, using: pk)
    }

    public static func check(response: Data, toChallenge challenge: Data, prefixedWith prefix: Data, from identity: ObvCryptoIdentity) -> Bool {
        return check(response: response, toChallenge: challenge, prefixedWith: prefix, using: identity.publicKeyForAuthentication)
    }

}

fileprivate struct AuthenticationFromSignatureOnEdwardsCurveConstants {
    static let lengthOfRandomFormattedChallengeSuffix = 16
}


protocol AuthenticationFromSignatureOnEdwardsCurve: AuthenticationConcrete {
    static var curve: EdwardsCurve { get }
}

extension AuthenticationFromSignatureOnEdwardsCurve {
    
    static func generateKeyPair(with prng: PRNGService) -> (PublicKeyForAuthentication, PrivateKeyForAuthentication) {
        let (scalar, point) = curve.generateRandomScalarAndPoint(withPRNG: prng)
        let publicKey = PublicKeyForAuthenticationFromSignatureOnEdwardsCurve(point: point)!
        let privateKey = PrivateKeyForAuthenticationFromSignatureOnEdwardsCurve(scalar: scalar, curveByteId: curve.byteId)
        return (publicKey, privateKey)
    }

    static func solve(_ challenge: Data, prefixedWith prefix: Data, with _privateKey: PrivateKeyForAuthentication, and _publicKey: PublicKeyForAuthentication, using prng: PRNGService) -> Data? {
        guard let publicKey = _publicKey as? PublicKeyForAuthenticationFromSignatureOnEdwardsCurve else { return nil }
        guard let privateKey = _privateKey as? PrivateKeyForAuthenticationFromSignatureOnEdwardsCurve else { return nil }
        let randomSuffix = prng.genBytes(count: AuthenticationFromSignatureOnEdwardsCurveConstants.lengthOfRandomFormattedChallengeSuffix)
        var formattedChallenge = prefix
        formattedChallenge.append(challenge)
        formattedChallenge.append(randomSuffix)
        guard let signature = Signature.sign(formattedChallenge, with: privateKey.privateKeyForSignatureOnEdwardsCurve, and: publicKey.publicKeyForSignatureOnEdwardsCurve, using: prng) else { return nil }
        var response = randomSuffix
        response.append(signature)
        return response
    }
    
    static func check(response: Data, toChallenge challenge: Data, prefixedWith prefix: Data, using _publicKey: PublicKeyForAuthentication) -> Bool {
        guard let publicKey = _publicKey as? PublicKeyForAuthenticationFromSignatureOnEdwardsCurve else { return false }
        guard response.count > AuthenticationFromSignatureOnEdwardsCurveConstants.lengthOfRandomFormattedChallengeSuffix else { return false }
        let randomSuffix = response[response.startIndex..<response.startIndex + AuthenticationFromSignatureOnEdwardsCurveConstants.lengthOfRandomFormattedChallengeSuffix]
        var formattedChallenge = prefix
        let signature = response[response.startIndex + AuthenticationFromSignatureOnEdwardsCurveConstants.lengthOfRandomFormattedChallengeSuffix..<response.endIndex]
        formattedChallenge.append(challenge)
        formattedChallenge.append(randomSuffix)
        return Signature.verify(signature, on: formattedChallenge, with: publicKey.publicKeyForSignatureOnEdwardsCurve) ?? false
    }

}

final class AuthenticationFromSignatureOnMDC: AuthenticationFromSignatureOnEdwardsCurve {
    static let algorithmImplementationByteId = AuthenticationImplementationByteId.Signature_with_EC_SDSA_with_MDC
    static let curve: EdwardsCurve = CurveMDC()
}

final class AuthenticationFromSignatureOnCurve25519: AuthenticationFromSignatureOnEdwardsCurve {
    static let algorithmImplementationByteId = AuthenticationImplementationByteId.Signature_with_EC_SDSA_with_Curve25519
    static let curve: EdwardsCurve = Curve25519()
}
