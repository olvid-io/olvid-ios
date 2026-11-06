/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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


public final class ObvCryptoIdentity: NSObject, NSCopying, ObvCodable {
    
    public let serverURL: URL
    public let publicKeyForAuthentication: PublicKeyForAuthentication
    public let publicKeyForPublicKeyEncryption: PublicKeyForPublicKeyEncryption
    
    /// Cached value returned by ``getIdentity()``.
    private let identity: Data
    
    /// The data passed as a input is expected to be structured as follows:
    /// - The URL of a server (or nothing, for the default server), followed by
    /// - A 0x00 byte, followed by
    /// - A compact authentication public key, followed by
    /// - A compact PublicKeyEncryption public key.
    public init?(from identity: Data) {
        let dataElements = identity.split(maxSplits: 1, omittingEmptySubsequences: false) { $0 == 0 }
        guard dataElements.count == 2 else { return nil }
        let serverURLAsData = dataElements[0]
        let compactPublicKeys = dataElements[1]
        // Parse the server
        guard let serverURL = URL(dataRepresentation: serverURLAsData, relativeTo: nil) else { return nil }
        self.serverURL = serverURL
        // The first compact key is the authentication public key
        guard let authImplemByteIdValue: UInt8 = compactPublicKeys.first else { return nil }
        guard let compactAuthPubKeyLength = CompactPublicKeyForAuthenticationExpander.getCompactKeyLength(fromAlgorithmImplementationByteIdValue: authImplemByteIdValue) else { return nil }
        guard compactPublicKeys.count >= compactAuthPubKeyLength else { return nil }
        let rangeForCompactAuthPubKey = compactPublicKeys.startIndex..<compactPublicKeys.startIndex+compactAuthPubKeyLength
        let compactAuthPubKey = compactPublicKeys[rangeForCompactAuthPubKey]
        guard let authPubKey = CompactPublicKeyForAuthenticationExpander.expand(compactKey: compactAuthPubKey) else { return nil }
        self.publicKeyForAuthentication = authPubKey
        // The second compact key is the public key encryption key
        let rangeForCompactPubKeyEncryptionPubKey = compactPublicKeys.startIndex+compactAuthPubKeyLength..<compactPublicKeys.endIndex
        let compactPubKeyEncPubKey = compactPublicKeys[rangeForCompactPubKeyEncryptionPubKey]
        guard let pubKeyEncImplemByteIdValue: UInt8 = compactPubKeyEncPubKey.first else { return nil }
        guard let compactPubKeyEncKeyLength = CompactPublicKeyForPublicKeyEncryptionExpander.getCompactKeyLength(fromAlgorithmImplementationByteIdValue: pubKeyEncImplemByteIdValue) else { return nil }
        guard compactPubKeyEncPubKey.count == compactPubKeyEncKeyLength else { return nil }
        guard let pubKeyEncPubKey = CompactPublicKeyForPublicKeyEncryptionExpander.expand(compactKey: compactPubKeyEncPubKey) else { return nil }
        self.publicKeyForPublicKeyEncryption = pubKeyEncPubKey
        self.identity = Self.makeIdentity(
            serverURL: self.serverURL,
            publicKeyForAuthentication: self.publicKeyForAuthentication,
            publicKeyForPublicKeyEncryption: self.publicKeyForPublicKeyEncryption
        )
    }
    
    public init(serverURL: URL,
                publicKeyForAuthentication: PublicKeyForAuthentication,
                publicKeyForPublicKeyEncryption: PublicKeyForPublicKeyEncryption
    ) {
        self.serverURL = serverURL
        self.publicKeyForAuthentication = publicKeyForAuthentication
        self.publicKeyForPublicKeyEncryption = publicKeyForPublicKeyEncryption
        self.identity = Self.makeIdentity(
            serverURL: self.serverURL,
            publicKeyForAuthentication: self.publicKeyForAuthentication,
            publicKeyForPublicKeyEncryption: self.publicKeyForPublicKeyEncryption
        )
    }
    
    public func getIdentity() -> Data { self.identity }
    
    private static func makeIdentity(
        serverURL: URL,
        publicKeyForAuthentication: PublicKeyForAuthentication,
        publicKeyForPublicKeyEncryption: PublicKeyForPublicKeyEncryption
    ) -> Data {
        var identity = serverURL.dataRepresentation
        identity.append(UInt8(0))
        identity.append(publicKeyForAuthentication.getCompactKey())
        identity.append(publicKeyForPublicKeyEncryption.getCompactKey())
        return identity
    }
    
}

// MARK: - Implementing LosslessStringConvertible

extension ObvCryptoIdentity: LosslessStringConvertible {
    
    /// This is used, in particular, as a `INPersonHandle` value.
    public override var description: String {
        self.getIdentity().hexString()
    }
    
    
    public convenience init?(_ description: String) {
        guard let identity = Data(hexString: description) else { assertionFailure(); return nil }
        self.init(from: identity)
    }

}


// MARK: Implementing Hashable

/// 2018-01-04 : we re-implement hashable due to various issues we encoutered with the default implementation
extension ObvCryptoIdentity {
    
    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(self.getIdentity())
        return hasher.finalize()
    }
    
}


// MARK: Implementing Equatable

/// Replaces the NSObject default implementation
extension ObvCryptoIdentity {
    
    static func == (lhs: ObvCryptoIdentity, rhs: ObvCryptoIdentity) -> Bool { lhs.identity == rhs.identity }
    
    static func != (lhs: ObvCryptoIdentity, rhs: ObvCryptoIdentity) -> Bool { !(lhs == rhs) }
    
    public override func isEqual(_ object: Any?) -> Bool {
        if let o = object as? ObvCryptoIdentity {
            return self == o
        } else {
            return false
        }
    }
    
}


// MARK: Implementing NSCopying

/// This solves a bug we encoutered while using `ObvCryptoIdentity`s with Core Data
extension ObvCryptoIdentity {
    public func copy(with zone: NSZone? = nil) -> Any {
        return ObvCryptoIdentity(serverURL: serverURL,
                                 publicKeyForAuthentication: publicKeyForAuthentication,
                                 publicKeyForPublicKeyEncryption: publicKeyForPublicKeyEncryption)
    }
}


// MARK: Implementing ObvEncodable

extension ObvCryptoIdentity {
    
    public func obvEncode() -> ObvEncoded {
        return self.getIdentity().obvEncode()
    }

}


// MARK: Implementing ObvDecodable

extension ObvCryptoIdentity {
    
    public convenience init?(_ obvEncoded: ObvEncoded) {
        guard let identityAsData = Data(obvEncoded) else { return nil }
        self.init(from: identityAsData)
    }
    
}


// MARK: Overriding the default implementation of CustomDebugStringConvertible

public extension ObvCryptoIdentity {
    
    override var debugDescription: String {
        let identityAsData = getIdentity()
        let rangeLength = min(8, identityAsData.count)
        let range = identityAsData.endIndex-rangeLength..<identityAsData.endIndex
        let description = identityAsData[range].map { String.init(format: "%02hhx", $0) }.joined()
        return description
    }
    
}
