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
import JOSESwift

public struct ObvJWKSet {

    fileprivate let jWKSet: JWKSet

    public init(data: Data) throws {
        self.jWKSet = try JWKSet(data: data)
    }

    public func jsonData() -> Data? {
        return jWKSet.jsonData()
    }
}


public struct ObvJWK: Equatable {
        
    private static let errorDomain = "ObvJWK"
    private static func makeError(message: String, error: Error? = nil) -> Error {
        NSError(domain: ObvJWK.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

    fileprivate let jwk: JWK
    
    fileprivate init(jwk: JWK) {
        self.jwk = jwk
    }
    
    public func encode() throws -> Data {
        guard let rawData = jwk.jsonData() else {
            throw ObvJWK.makeError(message: "Could not encode ObvJWK", error: nil)
        }
        return rawData
    }

    public static func decode(rawObvJWK: Data) throws -> Self {
        let decoder = JSONDecoder()
        if let rsaPublicKey = try? decoder.decode(RSAPublicKey.self, from: rawObvJWK) {
            return self.init(jwk: rsaPublicKey)
        } else if let ecPublicKey = try? decoder.decode(ECPublicKey.self, from: rawObvJWK) {
            return self.init(jwk: ecPublicKey)
        } else {
            throw ObvJWK.makeError(message: "Could not decode data", error: nil)
        }
    }

    
    public static func == (lhs: ObvJWK, rhs: ObvJWK) -> Bool {
        do {
            let lhsThumbprint = try lhs.jwk.thumbprint(algorithm: .SHA256)
            let rhsThumbprint = try rhs.jwk.thumbprint(algorithm: .SHA256)
            return lhsThumbprint == rhsThumbprint
        } catch {
            assertionFailure()
            return false
        }
    }

}


public final class JWSUtil {

    private static let errorDomain = "JWSUtil"
    private static func makeError(message: String, error: Error? = nil) -> Error {
        NSError(domain: JWSUtil.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

    public static func verifySignature(jwksData: Data, signature: String) throws -> (payload: Data, signatureVerificationKey: ObvJWK) {
        let jwks = try ObvJWKSet(data: jwksData)
        return try verifySignature(jwks: jwks, signature: signature)
    }

    public static func verifySignature(jwks: ObvJWKSet, signature: String) throws -> (payload: Data, signatureVerificationKey: ObvJWK) {

        let jwkSet = jwks.jWKSet
        // Build JWS from signature
        let jws = try JWS(compactSerialization: signature)

        // Find the key used by the signature
        guard let kid = jws.header.kid else {
            throw makeError(message: "Unable to find kid")
        }
        guard let jwk = jwkSet.first(where: { $0["kid"] == kid }) else {
            throw makeError(message: "Unable to find jwk key")
        }
        
        return try verifySignature(signatureVerificationKey: ObvJWK(jwk: jwk), signature: signature)

    }
    
    public static func verifySignature(signatureVerificationKey: ObvJWK, signature: String) throws -> (payload: Data, signatureVerificationKey: ObvJWK) {
        
        let jwk = signatureVerificationKey.jwk
        let jws = try JWS(compactSerialization: signature)

        guard let jwkData = jwk.jsonData() else {
            throw makeError(message: "Unable to convert jwk as jsonData")
        }

        guard let signatureAlgorithm = jws.header.algorithm else {
            throw makeError(message: "Unable to find the signature algorithm")
        }

        // Construct Verifier
        var verifier: Verifier?
        // Build instance of Key from JWT and convert it into apple type type SecKey from RSAPublicKey
        switch jwk.keyType {
        case .RSA:
            let rsaPublicKey = try RSAPublicKey(data: jwkData)
            let rsaSecKey = try rsaPublicKey.converted(to: SecKey.self)
            verifier = Verifier(verifyingAlgorithm: signatureAlgorithm, publicKey: rsaSecKey)
        case .OCT:
            // We do not support symmetric keys
            throw JWSUtil.makeError(message: "Unsuported key type")
        case .EC:
            let ecPublicKey = try ECPublicKey(data: jwkData)
            let ecSecKey = try ecPublicKey.converted(to: SecKey.self)
            verifier = Verifier(verifyingAlgorithm: signatureAlgorithm, publicKey: ecSecKey)
        }

        // Check signature
        if let verifier = verifier {
            _ = try jws.validate(using: verifier)
            return (jws.payload.data(), ObvJWK(jwk: jwk))
        } else {
            throw makeError(message: "Unable to build Verifier")
        }

    }

}


/// This is how ObvJWK used to be implemented before v0.9.15. We use this class within the Identity Manager to parse backups made with older versions of the app.
public struct ObvJWKLegacy: Decodable {
        
    private static let errorDomain = "ObvJWKLegacy"
    private static func makeError(message: String, error: Error? = nil) -> Error {
        NSError(domain: ObvJWKLegacy.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

    fileprivate let jwk: JWK
    
    enum CodingKeys: String, CodingKey {
        case jwk = "jwk"
        case keyType = "keyType"
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let jwkData = try values.decode(Data.self, forKey: .jwk)
        let keyTypeAsString = try values.decode(String.self, forKey: .keyType)
        guard let keyType = JWKKeyType(rawValue: keyTypeAsString) else { throw ObvJWKLegacy.makeError(message: "Could not parse key type") }
        switch keyType {
        case .RSA:
            jwk = try RSAPublicKey(data: jwkData)
        case .OCT:
            // We do not support symmetric keys
            throw ObvJWKLegacy.makeError(message: "Unsuported key type")
        case .EC:
            jwk = try ECPublicKey(data: jwkData)
        }
    }

    public static func decode(rawObvJWKLegacy: Data) throws -> Self {
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: rawObvJWKLegacy)
    }

    public func updateToObvJWK() -> ObvJWK {
        return ObvJWK(jwk: self.jwk)
    }

}
