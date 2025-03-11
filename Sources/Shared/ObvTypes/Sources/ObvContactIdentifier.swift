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
import ObvEncoder


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


// MARK: - Implementing ObvCodable, used by LosslessStringConvertible

extension ObvContactIdentifier: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        [ownedCryptoId, contactCryptoId].map({ $0.obvEncode() }).obvEncode()
    }
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let array = [ObvEncoded](obvEncoded) else { assertionFailure(); return nil }
        let contactCryptoId: ObvCryptoId
        let ownedCryptoId: ObvCryptoId
        do {
            (ownedCryptoId, contactCryptoId) = try array.obvDecode()
        } catch {
            assertionFailure()
            return nil
        }
        self.init(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
    }
    
}


// MARK: - Implementing LosslessStringConvertible, leveraging the ObvCodable conformance

extension ObvContactIdentifier: LosslessStringConvertible {
    
    public var description: String {
        self.obvEncode().rawData.hexString()
    }
    
    
    public init?(_ description: String) {
        guard let rawData = Data(hexString: description) else { assertionFailure(); return nil }
        guard let encoded = ObvEncoded(withRawData: rawData) else { assertionFailure(); return nil}
        do {
            self = try encoded.obvDecode()
        } catch {
            assertionFailure()
            return nil
        }
    }

}

// MARK: - Codable

extension ObvContactIdentifier: Codable {
    
    /// This serialization should **not** be changed as it used for long term storage.
    /// It is used for mentions.
    /// It is also used when serializing an NSUserActivity.

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
