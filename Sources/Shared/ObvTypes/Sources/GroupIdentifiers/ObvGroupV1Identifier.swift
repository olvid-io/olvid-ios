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


public struct ObvGroupV1Identifier: Sendable, Hashable {
    
    public let ownedCryptoId: ObvCryptoId
    public let groupV1Identifier: GroupV1Identifier
    
    public init(ownedCryptoId: ObvCryptoId, groupV1Identifier: GroupV1Identifier) {
        self.ownedCryptoId = ownedCryptoId
        self.groupV1Identifier = groupV1Identifier
    }
    
    public enum GroupType {
        case owned
        case joined
    }

    public var groupType: GroupType {
        return ownedCryptoId == groupV1Identifier.groupOwner ? .owned : .joined
    }
    
}


// MARK: - Implementing ObvCodable

extension ObvGroupV1Identifier: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        [ownedCryptoId.obvEncode(), groupV1Identifier.obvEncode()].obvEncode()
    }
    
    public init?(_ obvEncoded: ObvEncoded) {
        do {
            (ownedCryptoId, groupV1Identifier) = try obvEncoded.obvDecode()
        } catch {
            assertionFailure()
            return nil
        }
    }
    
}

// MARK: Implementing codable

/// This implementation is essentially used to implement LossLessStringConvertible
//extension ObvGroupV1Identifier: Codable {
//    
//    enum CodingKeys: String, CodingKey {
//        case ownedCryptoId = "owned_identity"
//        case groupV1Identifier = "gv1i"
//    }
//
//    
//    public func encode(to encoder: Encoder) throws {
//        var container = encoder.container(keyedBy: CodingKeys.self)
//        try container.encode(ownedCryptoId, forKey: .ownedCryptoId)
//        try container.encode(groupV1Identifier, forKey: .groupV1Identifier)
//    }
//
//    
//    public init(from decoder: Decoder) throws {
//        do {
//            let values = try decoder.container(keyedBy: CodingKeys.self)
//            let ownedCryptoId = try values.decode(ObvCryptoId.self, forKey: .ownedCryptoId)
//            let groupV1Identifier = try values.decode(GroupV1Identifier.self, forKey: .groupV1Identifier)
//            self.init(ownedCryptoId: ownedCryptoId, groupV1Identifier: groupV1Identifier)
//        } catch {
//            assertionFailure()
//            throw error
//        }
//    }
//
//    
//    func encodeToJson() throws -> Data {
//        let encoder = JSONEncoder()
//        return try encoder.encode(self)
//    }
//    
//    
//    static func decodeFromJson(data: Data) throws -> Self {
//        let decoder = JSONDecoder()
//        return try decoder.decode(ObvGroupV1Identifier.self, from: data)
//    }
//
//}


// MARK: - GroupV1Identifier

/// 2023-09-23 Type introduced for sync snapshots. It should have been introduced earlier...
public struct GroupV1Identifier: Hashable, Sendable {
    
    public let groupUid: UID
    public let groupOwner: ObvCryptoId
    
    public init(groupUid: UID, groupOwner: ObvCryptoId) {
        self.groupUid = groupUid
        self.groupOwner = groupOwner
    }
    
    var rawData: Data {
        groupOwner.getIdentity() + groupUid.raw
    }
    
    init(rawData: Data) throws {
        guard rawData.count > UID.length else {
            throw ObvError.notEnoughData
        }
        let identity = rawData[0..<(rawData.count-UID.length)]
        self.groupOwner = try ObvCryptoId(identity: identity)
        guard let groupUid = UID(uid: rawData[(rawData.count-UID.length)..<rawData.count]) else {
            throw ObvError.couldNotRecoverGroupUid
        }
        self.groupUid = groupUid
    }
    
    enum ObvError: Error {
        case notEnoughData
        case couldNotRecoverGroupUid
    }
    
}


// MARK: - Implementing ObvCodable

extension GroupV1Identifier: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        [groupUid.obvEncode(), groupOwner.obvEncode()].obvEncode()
    }
    
    public init?(_ obvEncoded: ObvEncoded) {
        do {
            (groupUid, groupOwner) = try obvEncoded.obvDecode()
        } catch {
            assertionFailure()
            return nil
        }
    }
    
}


// MARK: - Implementing LosslessStringConvertible

/// This implementation shall not change, as it is used for sync snapshots. We do *not* leverage the `ObvCodable` conformance here, as we sometimes do for other types.
extension GroupV1Identifier: LosslessStringConvertible {
        
    public var description: String {
        [groupOwner.getIdentity().base64EncodedString(), groupUid.raw.base64EncodedString()].joined(separator: "-")
    }
    
    public init?(_ description: String) {
        let values = description.split(separator: "-")
        guard values.count == 2 else { assertionFailure(); return nil }
        guard let groupOwnerIdentity = Data(base64Encoded: String(values[0])),
              let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
            assertionFailure()
            return nil
        }
        guard let rawUID = Data(base64Encoded: String(values[1])),
                let groupUid = UID(uid: rawUID) else {
            assertionFailure()
            return nil
        }
        self.init(groupUid: groupUid, groupOwner: groupOwner)
    }
    
}


// MARK: Implementing Codable

extension GroupV1Identifier: Codable {
    
    /// This serialization should **not** be changed as it used for long terme storage (typicially, in siri intents).
    /// It is not used to comunicate informations between devices.

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid"
        case groupOwner = "go"
    }

    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupUid.raw, forKey: .groupUid)
        try container.encode(groupOwner.getIdentity(), forKey: .groupOwner)
    }

    
    public init(from decoder: Decoder) throws {
        do {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let groupUidRaw = try values.decode(Data.self, forKey: .groupUid)
            guard let groupUid = UID(uid: groupUidRaw) else {
                throw ObvError.couldNotRecoverGroupUid
            }
            let groupOwnerIdentity = try values.decode(Data.self, forKey: .groupOwner)
            let groupOwner = try ObvCryptoId(identity: groupOwnerIdentity)
            self.init(groupUid: groupUid, groupOwner: groupOwner)
        } catch {
            assertionFailure()
            throw error
        }
    }

}
