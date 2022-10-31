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


public final class ObvOwnedCryptoIdentity: NSObject, NSCopying {
    
    public let serverURL: URL
    
    public let publicKeyForAuthentication: PublicKeyForAuthentication
    public let privateKeyForAuthentication: PrivateKeyForAuthentication
    
    public let publicKeyForPublicKeyEncryption: PublicKeyForPublicKeyEncryption
    public let privateKeyForPublicKeyEncryption: PrivateKeyForPublicKeyEncryption
    
    public let secretMACKey: MACKey
    
    public init(serverURL: URL, publicKeyForAuthentication: PublicKeyForAuthentication, publicKeyForPublicKeyEncryption: PublicKeyForPublicKeyEncryption, privateKeyForAuthentication: PrivateKeyForAuthentication, privateKeyForPublicKeyEncryption: PrivateKeyForPublicKeyEncryption, secretMACKey: MACKey) {
        self.serverURL = serverURL
        self.publicKeyForAuthentication = publicKeyForAuthentication
        self.publicKeyForPublicKeyEncryption = publicKeyForPublicKeyEncryption
        self.privateKeyForAuthentication = privateKeyForAuthentication
        self.privateKeyForPublicKeyEncryption = privateKeyForPublicKeyEncryption
        self.secretMACKey = secretMACKey
    }
    
    public static func gen(withServerURL serverURL: URL, forAuthenticationImplementationId authenticationImplementationId: AuthenticationImplementationByteId = .Signature_with_EC_SDSA_with_MDC, andPublicKeyEncryptionImplementationByteId pubEncImplementationId: PublicKeyEncryptionImplementationByteId = .KEM_ECIES_MDC_and_DEM_CTR_AES_256_then_HMAC_SHA_256, using prng: PRNGService, andMacImplementationId macImplementationByteId: MACImplementationByteId = .HMAC_With_SHA256) -> ObvOwnedCryptoIdentity {
        let authenticationImplementation = authenticationImplementationId.algorithmImplementation
        let (pkForAuthentication, skForAuthentication) = authenticationImplementation.generateKeyPair(with: prng)
        let PubKeyEncImplementation = pubEncImplementationId.algorithmImplementation
        let (pkForAnonAuthPubEnc, skForAnonAuthPubEnc) = PubKeyEncImplementation.generateKeyPair(with: prng)
        let MACImplementation = macImplementationByteId.algorithmImplementation
        let secretMACKey = MACImplementation.generateKey(with: prng)
        let identity = ObvOwnedCryptoIdentity(serverURL: serverURL,
                                              publicKeyForAuthentication: pkForAuthentication,
                                              publicKeyForPublicKeyEncryption: pkForAnonAuthPubEnc,
                                              privateKeyForAuthentication: skForAuthentication,
                                              privateKeyForPublicKeyEncryption: skForAnonAuthPubEnc,
                                              secretMACKey: secretMACKey)
        return identity
    }
}

// MARK: Create an ObvIdentity from an ObvOwnedCryptoIdentity
extension ObvOwnedCryptoIdentity {
    public func getObvCryptoIdentity() -> ObvCryptoIdentity {
        return ObvCryptoIdentity(serverURL: serverURL, publicKeyForAuthentication: publicKeyForAuthentication, publicKeyForPublicKeyEncryption: publicKeyForPublicKeyEncryption)
    }
}

// MARK: Leverage ObvIdentity to create a UID describing an identity, computed from the public keys. This UID should not be used
/// as a long term identifier. It is typically used as an UID in operations.
extension ObvOwnedCryptoIdentity {
    public var transientUid: UID {
        return getObvCryptoIdentity().transientUid
    }
}

// Implementing Equatable (replacing the NSObject default implementation)
extension ObvOwnedCryptoIdentity {
    static func == (lhs: ObvOwnedCryptoIdentity, rhs: ObvOwnedCryptoIdentity) -> Bool {
        guard lhs.publicKeyForAuthentication.isEqualTo(other: rhs.publicKeyForAuthentication) else { return false }
        guard lhs.publicKeyForPublicKeyEncryption.isEqualTo(other: rhs.publicKeyForPublicKeyEncryption) else { return false }
        guard lhs.privateKeyForAuthentication.isEqualTo(other: rhs.privateKeyForAuthentication) else { return false }
        guard lhs.privateKeyForPublicKeyEncryption.isEqualTo(other: rhs.privateKeyForPublicKeyEncryption) else { return false }
        return true
    }
    static func != (lhs: ObvOwnedCryptoIdentity, rhs: ObvOwnedCryptoIdentity) -> Bool {
        return !(lhs == rhs)
    }
    public override func isEqual(_ object: Any?) -> Bool {
        if let o = object as? ObvOwnedCryptoIdentity {
            return self == o
        } else {
            return false
        }
    }
}

// Implementing NSCopying (this solves a bug we encoutered while using `ObvCryptoIdentity`s with Core Data)
extension ObvOwnedCryptoIdentity {
    public func copy(with zone: NSZone? = nil) -> Any {
        return ObvOwnedCryptoIdentity(serverURL: serverURL,
                                      publicKeyForAuthentication: publicKeyForAuthentication,
                                      publicKeyForPublicKeyEncryption: publicKeyForPublicKeyEncryption,
                                      privateKeyForAuthentication: privateKeyForAuthentication,
                                      privateKeyForPublicKeyEncryption: privateKeyForPublicKeyEncryption,
                                      secretMACKey: secretMACKey)
    }
}

extension ObvOwnedCryptoIdentity: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        let listOfEncodedValues = [self.serverURL.obvEncode(),
                                   self.publicKeyForAuthentication.obvEncode(),
                                   self.publicKeyForPublicKeyEncryption.obvEncode(),
                                   self.privateKeyForAuthentication.obvEncode(),
                                   self.privateKeyForPublicKeyEncryption.obvEncode(),
                                   self.secretMACKey.obvEncode()]
        let obvEncoded = listOfEncodedValues.obvEncode()
        return obvEncoded
    }

    public convenience init?(_ encodedList: ObvEncoded) {
        guard let listOfEncodedValues = [ObvEncoded](encodedList) else { return nil }
        guard listOfEncodedValues.count == 6 else { return nil }
        // Extract and decode the encoded values out of the list
        let encodedServer = listOfEncodedValues[0]
        let encodedPublicKeyForAuthentication = listOfEncodedValues[1]
        let encodedPublicKeyForPublicKeyEncryption = listOfEncodedValues[2]
        let encodedPrivateKeyForAuthentication = listOfEncodedValues[3]
        let encodedPrivateKeyForPublicKeyEncryption = listOfEncodedValues[4]
        let encodedsecretMACKey = listOfEncodedValues[5]
        // Decode the extracted values
        guard let serverURL = URL(encodedServer) else { return nil }
        guard let publicKeyForAuthentication = PublicKeyForAuthenticationDecoder.obvDecode(encodedPublicKeyForAuthentication) else { return nil }
        guard let publicKeyForPublicKeyEncryption = PublicKeyForPublicKeyEncryptionDecoder.obvDecode(encodedPublicKeyForPublicKeyEncryption) else { return nil }
        guard let privateKeyForAuthentication = PrivateKeyForAuthenticationDecoder.obvDecode(encodedPrivateKeyForAuthentication) else { return nil }
        guard let privateKeyForPublicKeyEncryption = PrivateKeyForPublicKeyEncryptionDecoder.obvDecode(encodedPrivateKeyForPublicKeyEncryption) else { return nil }
        guard let secretMACKey = MACKeyDecoder.decode(encodedsecretMACKey) else { return nil }
        // Initialize and return a ObvCryptoIdentityObject
        self.init(serverURL: serverURL,
                  publicKeyForAuthentication: publicKeyForAuthentication,
                  publicKeyForPublicKeyEncryption: publicKeyForPublicKeyEncryption,
                  privateKeyForAuthentication: privateKeyForAuthentication,
                  privateKeyForPublicKeyEncryption: privateKeyForPublicKeyEncryption,
                  secretMACKey: secretMACKey)
    }
    
}

/// Implementing a ValueTransformer for an ObvCryptoIdentity. This transformer makes it possible to easily store an identity in Core Data.

public class ObvOwnedCryptoIdentityTransformer: ValueTransformer {
    
    override public class func transformedValueClass() -> AnyClass {
        return ObvOwnedCryptoIdentity.self
    }
    
    override public class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    /// Transform an ObvCryptoIdentity into an instance of Data (which actually is the raw representation of an ObvEncoded object)
    override public func transformedValue(_ value: Any?) -> Any? {
        guard let obvCryptoIdentity = value as? ObvOwnedCryptoIdentity else { return nil }
        let obvEncoded = obvCryptoIdentity.obvEncode()
        return obvEncoded.rawData
    }
    
    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        guard let encodedList = ObvEncoded(withRawData: data) else { return nil }
        return ObvOwnedCryptoIdentity(encodedList)
    }
}

public extension NSValueTransformerName {
    static let obvOwnedCryptoIdentityTransformerName = NSValueTransformerName(rawValue: "ObvOwnedCryptoIdentityTransformer")
}

// MARK: - For backup purposes

extension ObvOwnedCryptoIdentity {
    
    public var privateBackupItem: ObvOwnedCryptoIdentityPrivateBackupItem {
        return ObvOwnedCryptoIdentityPrivateBackupItem(obvOwnedCryptoIdentity: self)
    }
    
}

public struct ObvOwnedCryptoIdentityPrivateBackupItem: Codable, Hashable {
    
    private let rawPrivateKeyForAuthentication: Data
    private let rawPrivateKeyForPublicKeyEncryption: Data
    private let rawSecretMACKey: Data

    fileprivate init(obvOwnedCryptoIdentity: ObvOwnedCryptoIdentity) {
        self.rawPrivateKeyForAuthentication = obvOwnedCryptoIdentity.privateKeyForAuthentication.obvEncode().rawData
        self.rawPrivateKeyForPublicKeyEncryption = obvOwnedCryptoIdentity.privateKeyForPublicKeyEncryption.obvEncode().rawData
        self.rawSecretMACKey = obvOwnedCryptoIdentity.secretMACKey.obvEncode().rawData
    }
    
    enum CodingKeys: String, CodingKey {
            case rawPrivateKeyForAuthentication = "server_authentication_private_key"
            case rawPrivateKeyForPublicKeyEncryption = "encryption_private_key"
            case rawSecretMACKey = "mac_key"
    }

    private var privateKeyForAuthentication: PrivateKeyForAuthentication? {
        guard let encoded = ObvEncoded(withRawData: rawPrivateKeyForAuthentication) else { return nil }
        return PrivateKeyForAuthenticationDecoder.obvDecode(encoded)
    }

    private var privateKeyForPublicKeyEncryption: PrivateKeyForPublicKeyEncryption? {
        guard let encoded = ObvEncoded(withRawData: rawPrivateKeyForPublicKeyEncryption) else { return nil }
        return PrivateKeyForPublicKeyEncryptionDecoder.obvDecode(encoded)
    }
    
    private var secretMACKey: MACKey? {
        guard let encoded = ObvEncoded(withRawData: rawSecretMACKey) else { return nil }
        return MACKeyDecoder.decode(encoded)
    }
    
    public func getOwnedIdentity(cryptoIdentity: ObvCryptoIdentity) -> ObvOwnedCryptoIdentity? {
        guard let privateKeyForAuthentication = self.privateKeyForAuthentication else { return nil }
        guard let privateKeyForPublicKeyEncryption = self.privateKeyForPublicKeyEncryption else { return nil }
        guard let secretMACKey = self.secretMACKey else { return nil }
        return ObvOwnedCryptoIdentity(serverURL: cryptoIdentity.serverURL,
                                      publicKeyForAuthentication: cryptoIdentity.publicKeyForAuthentication,
                                      publicKeyForPublicKeyEncryption: cryptoIdentity.publicKeyForPublicKeyEncryption,
                                      privateKeyForAuthentication: privateKeyForAuthentication,
                                      privateKeyForPublicKeyEncryption: privateKeyForPublicKeyEncryption,
                                      secretMACKey: secretMACKey)
    }
    
    
}
