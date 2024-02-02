/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvCrypto
import ObvEncoder


public struct ObvMessageIdentifier: Equatable, Hashable, CustomDebugStringConvertible {
    
    public let uid: UID
    public let ownedCryptoIdentity: ObvCryptoIdentity
    
    public init(ownedCryptoIdentity: ObvCryptoIdentity, uid: UID) {
        self.ownedCryptoIdentity = ownedCryptoIdentity
        self.uid = uid
    }

    public init?(rawOwnedCryptoIdentity: Data, rawUid: Data) {
        guard let ownedCryptoIdentity = ObvCryptoIdentity(from: rawOwnedCryptoIdentity) else { return nil }
        guard let uid = UID(uid: rawUid) else { return nil }
        self.init(ownedCryptoIdentity: ownedCryptoIdentity, uid: uid)
    }
 
    public static func == (lhs: ObvMessageIdentifier, rhs: ObvMessageIdentifier) -> Bool {
        return lhs.uid == rhs.uid && lhs.ownedCryptoIdentity == rhs.ownedCryptoIdentity
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.uid)
        hasher.combine(self.ownedCryptoIdentity.getIdentity())
    }
    
    public var debugDescription: String {
        return uid.debugDescription
    }
    

    public var directoryNameForMessageAttachments: String {
        let sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()
        let rawValue = ownedCryptoIdentity.getIdentity() + uid.raw
        let directoryName = sha256.hash(rawValue)
        return directoryName.hexString()
    }

    
    /// 2023-07-07 This was the old way of computing the name of the directory allowing to store attachments for this message (in upload and download).
    /// This method is not deterministic, leading to potential bug. It is only here for delaing with legacy situations and shall not be used for any other reason.
    /// Use ``directoryNameForMessageAttachments`` instead.
    public var legacyDirectoryNamesForMessageAttachments: Set<String> {
        var namesToReturn = Set<String>()
        let encoder = JSONEncoder()
        let sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()
        do {
            encoder.outputFormatting = .sortedKeys
            if let rawValue = try? encoder.encode(self) {
                let directoryName = sha256.hash(rawValue).hexString()
                namesToReturn.insert(directoryName)
            } else {
                assertionFailure()
            }
        }
        // The previous name was constructed on the basis of a json with the .sortedKeys option.
        // We manually construct the json with reversed keys.
        if let ownedCryptoIdentityValueData = try? encoder.encode(self.ownedCryptoIdentity.getIdentity()),
           let ownedCryptoIdentityValue = String(data: ownedCryptoIdentityValueData, encoding: .utf8),
           let uidRaw = try? encoder.encode(self.uid),
           let uidValue = String(data: uidRaw, encoding: .utf8),
           let rawValue = [
            "{",
            [
                ["\"uid\"", uidValue].joined(separator: ":"),
                ["\"owned_crypto_identity\"", ownedCryptoIdentityValue].joined(separator: ":"),
            ].joined(separator: ","),
            "}",
           ].joined().data(using: .utf8) {
            let directoryName = sha256.hash(rawValue).hexString()
            namesToReturn.insert(directoryName)
        } else {
            assertionFailure()
        }
        return namesToReturn
    }
        
}


extension ObvMessageIdentifier: Codable {

    private static let errorDomain = "MessageIdentifier"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    enum CodingKeys: String, CodingKey {
        case uid = "uid"
        case ownedCryptoIdentity = "owned_crypto_identity"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.ownedCryptoIdentity.getIdentity(), forKey: .ownedCryptoIdentity)
        try container.encode(self.uid, forKey: .uid)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.uid = try values.decode(UID.self, forKey: .uid)
        let identity = try values.decode(Data.self, forKey: .ownedCryptoIdentity)
        guard let ownedIdentity = ObvCryptoIdentity(from: identity) else {
            assertionFailure()
            throw ObvMessageIdentifier.makeError(message: "Decode error")
        }
        self.ownedCryptoIdentity = ownedIdentity
    }
}
