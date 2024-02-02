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


public struct ObvContactIdentifier: Hashable, CustomStringConvertible {
    
    public let contactCryptoId: ObvCryptoId
    public let ownedCryptoId: ObvCryptoId
    
    public init(contactCryptoIdentity: ObvCryptoIdentity, ownedCryptoIdentity: ObvCryptoIdentity) {
        assert(contactCryptoIdentity != ownedCryptoIdentity)
        self.contactCryptoId = ObvCryptoId(cryptoIdentity: contactCryptoIdentity)
        self.ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedCryptoIdentity)
    }
    
    public init(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId) {
        assert(contactCryptoId != ownedCryptoId)
        self.contactCryptoId = contactCryptoId
        self.ownedCryptoId = ownedCryptoId
    }

}


// MARK: Implementing CustomStringConvertible

extension ObvContactIdentifier {
    public var description: String {
        return "ObvContactIdentifier<\(contactCryptoId.description), \(ownedCryptoId.description)>"
    }
}


// MARK: - Codable

extension ObvContactIdentifier: Codable {
    
    /// `ObvContactIdentifier` so that `ObvMessage` and `ObvAttachment` can also conform to Codable. This makes it possible to transfer a message from the notification service to the main app.
    /// This serialization should **not** be used within long term storage since we may change it regularly.

    enum CodingKeys: String, CodingKey {
        case contactCryptoId = "contact_crypto_id"
        case ownedCryptoId = "owned_crypto_id"
    }

    public func encodeToJson() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    public static func decodeFromJson(data: Data) throws -> ObvMessage {
        let decoder = JSONDecoder()
        return try decoder.decode(ObvMessage.self, from: data)
    }
}
