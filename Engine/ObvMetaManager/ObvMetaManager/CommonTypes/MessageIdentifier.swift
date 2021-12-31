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
import ObvCrypto
import ObvEncoder
import ObvTypes

public struct MessageIdentifier: Equatable, Hashable, CustomDebugStringConvertible {
    
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
 
    public static func == (lhs: MessageIdentifier, rhs: MessageIdentifier) -> Bool {
        return lhs.uid == rhs.uid && lhs.ownedCryptoIdentity == rhs.ownedCryptoIdentity
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.uid)
        hasher.combine(self.ownedCryptoIdentity.getIdentity())
    }
    
    public var debugDescription: String {
        return uid.debugDescription
    }
}

extension MessageIdentifier: Codable {

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
            throw MessageIdentifier.makeError(message: "Decode error")
        }
        self.ownedCryptoIdentity = ownedIdentity
    }
}


extension MessageIdentifier: RawRepresentable {

    public var rawValue: Data {
        let encoder = JSONEncoder()
        return try! encoder.encode(self)
    }

    public init?(rawValue: Data) {
        let decoder = JSONDecoder()
        guard let messageId = try? decoder.decode(MessageIdentifier.self, from: rawValue) else { return nil }
        self = messageId
    }

}


extension MessageIdentifier: LosslessStringConvertible {

    public var description: String {
        return String(data: self.rawValue, encoding: .utf8)!
    }
    
    public init?(_ description: String) {
        guard let rawValue = description.data(using: .utf8) else { assertionFailure(); return nil }
        self.init(rawValue: rawValue)
    }
    
}
