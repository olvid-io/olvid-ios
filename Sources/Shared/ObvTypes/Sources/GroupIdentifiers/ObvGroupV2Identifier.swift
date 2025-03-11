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
import ObvEncoder

public struct ObvGroupV2Identifier: Hashable {
    
    public let ownedCryptoId: ObvCryptoId
    public let identifier: ObvGroupV2.Identifier
 
    
    public init(ownedCryptoId: ObvCryptoId, identifier: ObvGroupV2.Identifier) {
        self.ownedCryptoId = ownedCryptoId
        self.identifier = identifier
    }
    
}


// MARK: - Implementing ObvCodable, used by LosslessStringConvertible

extension ObvGroupV2Identifier: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        [ownedCryptoId.obvEncode(), identifier.obvEncode()].obvEncode()
    }
    
    public init?(_ obvEncoded: ObvEncoded) {
        do {
            (ownedCryptoId, identifier) = try obvEncoded.obvDecode()
        } catch {
            assertionFailure()
            return nil
        }
    }
}


// MARK: - Implementing LosslessStringConvertible, leveraging the ObvCodable conformance

extension ObvGroupV2Identifier: LosslessStringConvertible {
    
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


// MARK: - Implementing Codable


extension ObvGroupV2Identifier: Codable {
    
    // The Codable compliance is used within mentions
    
    enum CodingKeys: String, CodingKey {
        case ownedCryptoId = "owned_identity"
        case identifier = "gv2i"
    }
    
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ownedCryptoId, forKey: .ownedCryptoId)
        try container.encode(identifier, forKey: .identifier)
    }

    
    public init(from decoder: Decoder) throws {
        do {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let ownedCryptoId = try values.decode(ObvCryptoId.self, forKey: .ownedCryptoId)
            let identifier = try values.decode(ObvGroupV2.Identifier.self, forKey: .identifier)
            self.init(ownedCryptoId: ownedCryptoId, identifier: identifier)
        } catch {
            assertionFailure()
            throw error
        }
    }

    
    func encodeToJson() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    
    static func decodeFromJson(data: Data) throws -> Self {
        let decoder = JSONDecoder()
        return try decoder.decode(ObvGroupV2Identifier.self, from: data)
    }
    
}


// MARK: LosslessStringConvertible (almost)

//extension ObvGroupV2Identifier {
//    
//    /// Since this getter can throw, we cannot conform to CustomStringConvertible and thus, we cannot conform to LosslessStringConvertible.
//    public var description: String {
//        get throws {
//            try self.encodeToJson().base64EncodedString()
//        }
//    }
//    
//    
//    public init?(_ description: String) {
//        guard let data = Data(base64Encoded: description) else { assertionFailure(); return nil }
//        do {
//            self = try Self.decodeFromJson(data: data)
//        } catch {
//            assertionFailure()
//            return nil
//        }
//    }
//
//}


/// 2023-09-23 Type introduced for sync snapshots. It should have been introduced earlier...
public typealias GroupV2Identifier = Data
