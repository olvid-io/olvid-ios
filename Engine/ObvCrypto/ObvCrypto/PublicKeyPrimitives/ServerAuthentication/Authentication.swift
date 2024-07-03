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
import BigInt
import ObvEncoder

// MARK: Protocols

public protocol AuthenticationCommon {
    static func solve(_: Data, prefixedWith: Data, with: PrivateKeyForAuthentication, and: PublicKeyForAuthentication, using: PRNGService) throws -> Data?
    static func solve(_: Data, prefixedWith: Data, with: PrivateKeyForAuthentication, using: PRNGService) throws -> Data?
    static func check(response: Data, toChallenge: Data, prefixedWith: Data, using: PublicKeyForAuthentication) throws -> Bool
    static func areKeysMatching(publicKey: PublicKeyForAuthentication, privateKey: PrivateKeyForAuthentication) -> Bool
}

public protocol AuthenticationConcrete: AuthenticationCommon {
    static var algorithmImplementationByteId: AuthenticationImplementationByteId { get }
    static func generateKeyPair(with: PRNGService) -> (PublicKeyForAuthentication, PrivateKeyForAuthentication)
}

protocol AuthenticationGeneric: AuthenticationCommon {
    static func generateKeyPair(for: AuthenticationImplementationByteId, with: PRNGService) -> (PublicKeyForAuthentication, PrivateKeyForAuthentication)
    static func solve(_: Data, prefixedWith: Data, for: ObvOwnedCryptoIdentity, using: PRNGService) throws -> Data?
    static func check(response: Data, toChallenge: Data, prefixedWith: Data, from: ObvCryptoIdentity) throws -> Bool
}

// MARK: Classes

public final class Authentication: AuthenticationGeneric {
    
    public static func generateKeyPair(for implemByteId: AuthenticationImplementationByteId, with prng: PRNGService) -> (PublicKeyForAuthentication, PrivateKeyForAuthentication) {
        return implemByteId.algorithmImplementation.generateKeyPair(with: prng)
    }
    
    public static func solve(_ challenge: Data, prefixedWith prefix: Data, with privateKey: PrivateKeyForAuthentication, and publicKey: PublicKeyForAuthentication, using prng: PRNGService) throws -> Data? {
        let algorithmImplementation = privateKey.algorithmImplementationByteId.algorithmImplementation
        return try algorithmImplementation.solve(challenge, prefixedWith: prefix, with: privateKey, and: publicKey, using: prng)
    }
    
    public static func solve(_ challenge: Data, prefixedWith prefix: Data, for ownedIdentity: ObvOwnedCryptoIdentity, using prng: PRNGService) throws -> Data? {
        return try solve(challenge, prefixedWith: prefix, with: ownedIdentity.privateKeyForAuthentication, and: ownedIdentity.publicKeyForAuthentication, using: prng)
    }
    
    public static func solve(_ challenge: Data, prefixedWith prefix: Data, with privateKey: PrivateKeyForAuthentication, using prng: PRNGService) throws -> Data? {
        let algorithmImplementation = privateKey.algorithmImplementationByteId.algorithmImplementation
        return try algorithmImplementation.solve(challenge, prefixedWith: prefix, with: privateKey, using: prng)
    }
    
    public static func check(response: Data, toChallenge challenge: Data, prefixedWith prefix: Data, using pk: PublicKeyForAuthentication) throws -> Bool {
        let algorithmImplementation = pk.algorithmImplementationByteId.algorithmImplementation
        return try algorithmImplementation.check(response: response, toChallenge: challenge, prefixedWith: prefix, using: pk)
    }

    public static func check(response: Data, toChallenge challenge: Data, prefixedWith prefix: Data, from identity: ObvCryptoIdentity) throws -> Bool {
        return try check(response: response, toChallenge: challenge, prefixedWith: prefix, using: identity.publicKeyForAuthentication)
    }

    public static func areKeysMatching(publicKey: PublicKeyForAuthentication, privateKey: PrivateKeyForAuthentication) -> Bool {
        guard publicKey.algorithmClass == privateKey.algorithmClass,
              publicKey.algorithmImplementationByteId == privateKey.algorithmImplementationByteId else { return false }
        let algorithmImplementation = privateKey.algorithmImplementationByteId.algorithmImplementation
        return algorithmImplementation.areKeysMatching(publicKey: publicKey, privateKey: privateKey)
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
        let (scalar, point) = curve.generateRandomScalarAndHighOrderPoint(withPRNG: prng)
        let publicKey = PublicKeyForAuthenticationFromSignatureOnEdwardsCurve(point: point)!
        let privateKey = PrivateKeyForAuthenticationFromSignatureOnEdwardsCurve(scalar: scalar, curveByteId: curve.byteId)
        return (publicKey, privateKey)
    }

    static func solve(_ challenge: Data, prefixedWith prefix: Data, with _privateKey: PrivateKeyForAuthentication, and _publicKey: PublicKeyForAuthentication, using prng: PRNGService) -> Data? {
        guard let publicKey = _publicKey as? PublicKeyForAuthenticationFromSignatureOnEdwardsCurve else { return nil }
        guard let privateKey = _privateKey as? PrivateKeyForAuthenticationFromSignatureOnEdwardsCurve else { return nil }
        guard !publicKey.isLowOrderPoint else {
            assertionFailure()
            return nil
        }
        let randomSuffix = prng.genBytes(count: AuthenticationFromSignatureOnEdwardsCurveConstants.lengthOfRandomFormattedChallengeSuffix)
        var formattedChallenge = prefix
        formattedChallenge.append(challenge)
        formattedChallenge.append(randomSuffix)
        guard let signature = Signature.sign(formattedChallenge, with: privateKey.privateKeyForSignatureOnEdwardsCurve, and: publicKey.publicKeyForSignatureOnEdwardsCurve, using: prng) else { return nil }
        var response = randomSuffix
        response.append(signature)
        return response
    }

    static func solve(_ challenge: Data, prefixedWith prefix: Data, with _privateKey: PrivateKeyForAuthentication, using prng: PRNGService) throws -> Data? {
        guard let privateKey = _privateKey as? PrivateKeyForAuthenticationFromSignatureOnEdwardsCurve,
              let point = curve.scalarMultiplication(scalar: privateKey.scalar, point: privateKey.curve.parameters.G),
              let publicKey = PublicKeyForAuthenticationFromSignatureOnEdwardsCurve(point: point) else { assertionFailure(); return nil }
        let response = try solve(challenge, prefixedWith: prefix, with: privateKey, and: publicKey, using: prng)
        return response
    }

    static func check(response: Data, toChallenge challenge: Data, prefixedWith prefix: Data, using _publicKey: PublicKeyForAuthentication) -> Bool {
        guard let publicKey = _publicKey as? PublicKeyForAuthenticationFromSignatureOnEdwardsCurve else { return false }
        guard !publicKey.isLowOrderPoint else {
            assertionFailure()
            return false
        }
        guard response.count > AuthenticationFromSignatureOnEdwardsCurveConstants.lengthOfRandomFormattedChallengeSuffix else { return false }
        let randomSuffix = response[response.startIndex..<response.startIndex + AuthenticationFromSignatureOnEdwardsCurveConstants.lengthOfRandomFormattedChallengeSuffix]
        var formattedChallenge = prefix
        let signature = response[response.startIndex + AuthenticationFromSignatureOnEdwardsCurveConstants.lengthOfRandomFormattedChallengeSuffix..<response.endIndex]
        formattedChallenge.append(challenge)
        formattedChallenge.append(randomSuffix)
        return (try? Signature.verify(signature, on: formattedChallenge, with: publicKey.publicKeyForSignatureOnEdwardsCurve)) ?? false
    }

    static func areKeysMatching(publicKey: PublicKeyForAuthentication, privateKey: PrivateKeyForAuthentication) -> Bool {
        guard let publicKey = publicKey as? PublicKeyForAuthenticationFromSignatureOnEdwardsCurve else { assertionFailure(); return false }
        guard let privateKey = privateKey as? PrivateKeyForAuthenticationFromSignatureOnEdwardsCurve else { assertionFailure(); return false }
        guard publicKey.algorithmClass == privateKey.algorithmClass,
              publicKey.algorithmImplementationByteId == privateKey.algorithmImplementationByteId,
              publicKey.curveByteId == privateKey.curveByteId else { return false }
        let computedPoint = curve.scalarMultiplication(scalar: privateKey.scalar, point: privateKey.curve.parameters.G)
        return publicKey.point == computedPoint
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
