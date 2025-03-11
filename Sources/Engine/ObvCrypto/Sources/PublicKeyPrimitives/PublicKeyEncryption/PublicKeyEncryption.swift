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

// MARK: Protocols

/// This protocol is intended to be implemented by the class PublicKeyEncryption. The objective is to allow the outside world to call the encrypt and decrypt method directly on the class PublicKeyEncryption. Thanks to the fact the public and private keys know which concrete implementation of PublicKeyEncryption they correspond to, the concrete implementation can be transparently called.
public protocol PublicKeyEncryptionCommon {
    static func kemEncrypt(using: PublicKeyForPublicKeyEncryption, with: PRNG) -> (EncryptedData, AuthenticatedEncryptionKey)?
    static func kemDecrypt(_: EncryptedData, using: PrivateKeyForPublicKeyEncryption) -> AuthenticatedEncryptionKey?
    static func kemEncrypt(for: ObvCryptoIdentity, with prng: PRNG) -> (EncryptedData, AuthenticatedEncryptionKey)?
    static func kemDecrypt(_: EncryptedData, for: ObvOwnedCryptoIdentity) -> AuthenticatedEncryptionKey?
    static func encrypt(_: Data, using: PublicKeyForPublicKeyEncryption, and: PRNG) -> EncryptedData?
    static func decrypt(_: EncryptedData, using: PrivateKeyForPublicKeyEncryption) -> Data?
    static func encrypt(_: Data, for: ObvCryptoIdentity, randomizedWith: PRNG) -> EncryptedData?
    static func decrypt(_: EncryptedData, for: ObvOwnedCryptoIdentity) -> Data?
}

extension PublicKeyEncryptionCommon {
    
    public static func encrypt(_ plaintext: Data, for identity: ObvCryptoIdentity, randomizedWith prng: PRNG) -> EncryptedData? {
        return encrypt(plaintext, using: identity.publicKeyForPublicKeyEncryption, and: prng)
    }
    
    public static func decrypt(_ ciphertext: EncryptedData, for identity: ObvOwnedCryptoIdentity) -> Data? {
        return decrypt(ciphertext, using: identity.privateKeyForPublicKeyEncryption)
    }

    public static func kemEncrypt(for identity: ObvCryptoIdentity, with prng: PRNG) -> (EncryptedData, AuthenticatedEncryptionKey)? {
        return kemEncrypt(using: identity.publicKeyForPublicKeyEncryption, with: prng)
    }
    
    public static func kemDecrypt(_ ciphertext: EncryptedData, for identity: ObvOwnedCryptoIdentity) -> AuthenticatedEncryptionKey? {
        return kemDecrypt(ciphertext, using: identity.privateKeyForPublicKeyEncryption)
    }

}


/// A concrete PublicKeyEncryption implementation must not only implement encrypt and decrypt, but must also be able to generate public and private keys. Those keys encapsulate the concrete implementation that generated them.
public protocol PublicKeyEncryptionConcrete: PublicKeyEncryptionCommon {
    static var algorithmImplementationByteId: PublicKeyEncryptionImplementationByteId { get }
    static func generateKeyPair(with: PRNG) -> (PublicKeyForPublicKeyEncryption, PrivateKeyForPublicKeyEncryption)
}

public protocol PublicKeyEncryptionGeneric: PublicKeyEncryptionCommon {
    static func generateKeyPair(for: PublicKeyEncryptionImplementationByteId, with: PRNG) -> (PublicKeyForPublicKeyEncryption, PrivateKeyForPublicKeyEncryption)
}


// MARK: Classes

public final class PublicKeyEncryption: PublicKeyEncryptionGeneric {
    
    public static func generateKeyPair(for implemByteId: PublicKeyEncryptionImplementationByteId, with prng: PRNG) -> (PublicKeyForPublicKeyEncryption, PrivateKeyForPublicKeyEncryption) {
        return implemByteId.algorithmImplementation.generateKeyPair(with: prng)
    }
    
    public static func kemEncrypt(using publicKey: PublicKeyForPublicKeyEncryption, with prng: PRNG) -> (EncryptedData, AuthenticatedEncryptionKey)? {
        return publicKey.algorithmImplementationByteId.algorithmImplementation.kemEncrypt(using: publicKey, with: prng)
    }
    
    public static func kemDecrypt(_ ciphertext: EncryptedData, using privateKey: PrivateKeyForPublicKeyEncryption) -> AuthenticatedEncryptionKey? {
        return privateKey.algorithmImplementationByteId.algorithmImplementation.kemDecrypt(ciphertext, using: privateKey)
    }
    
    public static func encrypt(_ plaintext: Data, using publicKey: PublicKeyForPublicKeyEncryption, and prng: PRNG) -> EncryptedData? {
        return publicKey.algorithmImplementationByteId.algorithmImplementation.encrypt(plaintext, using: publicKey, and: prng)
    }

    public static func decrypt(_ ciphertext: EncryptedData, using privateKey: PrivateKeyForPublicKeyEncryption) -> Data? {
        return privateKey.algorithmImplementationByteId.algorithmImplementation.decrypt(ciphertext, using: privateKey)
    }
}

protocol ECIESwithEdwardsCurveandDEMwithCTRAES256thenHMACSHA256: PublicKeyEncryptionConcrete {
    static var curve: EdwardsCurve { get }
}

extension ECIESwithEdwardsCurveandDEMwithCTRAES256thenHMACSHA256 {

    private static var KEM: KEM_ECIES256KEM512.Type {
        switch algorithmImplementationByteId {
        case .KEM_ECIES_MDC_and_DEM_CTR_AES_256_then_HMAC_SHA_256:
            return KEM_ECIES256KEM512_WithMDC.self as KEM_ECIES256KEM512.Type
        case .KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256:
            return KEM_ECIES256KEM512_WithCurve25519.self as KEM_ECIES256KEM512.Type
        }
    }

    static func generateKeyPair(with prng: PRNG) -> (PublicKeyForPublicKeyEncryption, PrivateKeyForPublicKeyEncryption) {
        return KEM.generateKeyPair(with: prng)
    }
    
    static func generateKeyPairForBackupKey(with prng: PRNG) -> (PublicKeyForPublicKeyEncryption, PrivateKeyForPublicKeyEncryption) {
        return KEM.generateKeyPairForBackupKey(with: prng)
    }

    static func kemEncrypt(using publicKey: PublicKeyForPublicKeyEncryption, with prng: PRNG) -> (EncryptedData, AuthenticatedEncryptionKey)? {
        let result = KEM.encrypt(using: publicKey, with: prng) {
            AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key(data: $0)!
        }
        guard let result else { assertionFailure(); return nil }
        return (result.0, result.1 as AuthenticatedEncryptionKey)
    }
    
    static func kemDecrypt(_ ciphertext: EncryptedData, using privateKey: PrivateKeyForPublicKeyEncryption) -> AuthenticatedEncryptionKey? {
        return KEM.decrypt(ciphertext, using: privateKey, { AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key(data: $0)! })
    }
    
    static func encrypt(_ plaintext: Data, using publicKey: PublicKeyForPublicKeyEncryption, and prng: PRNG) -> EncryptedData? {
        let result = KEM.encrypt(using: publicKey, with: prng) { AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key(data: $0)! }
        guard let result else { assertionFailure(); return nil }
        let (c0, key) = (result.0, result.1)
        let c1 = try! AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256.encrypt(plaintext, with: key, and: prng)
        let ciphertext = EncryptedData.byAppending(c1: c0, c2: c1)
        return ciphertext
    }

    static func decrypt(_ ciphertext: EncryptedData, using privateKey: PrivateKeyForPublicKeyEncryption) -> Data? {
        guard ciphertext.count >= KEM.length else { return nil }
        let c0 = ciphertext[ciphertext.startIndex..<ciphertext.startIndex+KEM.length]
        let c1 = ciphertext[ciphertext.startIndex+KEM.length..<ciphertext.endIndex]
        guard let key = KEM.decrypt(c0, using: privateKey, { AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key(data: $0)! }) else { return nil }
        let plaintext = try? AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256.decrypt(c1, with: key)
        return plaintext
    }
}

final class ECIESwithMDCandDEMwithCTRAES256thenHMACSHA256: ECIESwithEdwardsCurveandDEMwithCTRAES256thenHMACSHA256 {
    static var curve: EdwardsCurve = CurveMDC()
    static let algorithmImplementationByteId = PublicKeyEncryptionImplementationByteId.KEM_ECIES_MDC_and_DEM_CTR_AES_256_then_HMAC_SHA_256
}

final class ECIESwithCurve25519andDEMwithCTRAES256thenHMACSHA256: ECIESwithEdwardsCurveandDEMwithCTRAES256thenHMACSHA256 {
    static var curve: EdwardsCurve = Curve25519()
    static let algorithmImplementationByteId = PublicKeyEncryptionImplementationByteId.KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256
}
