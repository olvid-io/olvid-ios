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
import ObvCrypto


public struct ObvContactIdentifier: Hashable {
    
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


// MARK: - Codable

extension ObvContactIdentifier: Codable {
    
    /// Making `ObvContactIdentifier` conform to `Codable` so that `ObvMessage` and `ObvAttachment` can also conform to `Codable`. 
    /// This makes it possible to transfer a message from the notification service to the main app.
    /// This serialization should **not** be used within long term storage since we may change it regularly.

    enum CodingKeys: String, CodingKey {
        case contactCryptoId = "contact_crypto_id"
        case ownedCryptoId = "owned_crypto_id"
    }

    public func encodeToJson() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    public static func decodeFromJson(data: Data) throws -> ObvContactIdentifier {
        let decoder = JSONDecoder()
        return try decoder.decode(ObvContactIdentifier.self, from: data)
    }
}


// MARK: - LosslessStringConvertible

extension ObvContactIdentifier: LosslessStringConvertible, CustomStringConvertible {

    private static let separator: Character = "|"
    
    /// This serialization should **not** be used within long term storage since we may change it regularly.
    public init?(_ description: String) {
        let splits = description.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0 == Self.separator })
        guard splits.count == 2,
              let ownedCryptoId = ObvCryptoId(String(splits[0])),
              let contactCryptoId = ObvCryptoId(String(splits[1])) 
        else {
            assertionFailure()
            return nil
        }
        self = .init(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
    }
    
    
    /// This serialization should **not** be used within long term storage since we may change it regularly.
    public var description: String {
        [ownedCryptoId, contactCryptoId]
            .map { $0.description }
            .joined(separator: String(Self.separator))
    }
    
}
