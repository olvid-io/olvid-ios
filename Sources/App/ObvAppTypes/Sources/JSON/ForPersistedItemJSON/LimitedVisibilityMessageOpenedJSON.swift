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
import ObvTypes
import ObvCrypto


public struct LimitedVisibilityMessageOpenedJSON: Codable {
        
    public let messageReference: MessageReferenceJSON
    public let oneToOneIdentifier: OneToOneIdentifierJSON?
    let groupV1Identifier: GroupV1Identifier?
    let groupV2Identifier: GroupV2Identifier?
    
    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }
    
    
//    
//    public func getDiscussionId(ownedCryptoId: ObvCryptoId) throws -> DiscussionIdentifier {
//        if let groupV1Identifier {
//            return .groupV1(id: .groupV1Identifier(groupV1Identifier: groupV1Identifier))
//        } else if let groupV2Identifier {
//            return .groupV2(id: .groupV2Identifier(groupV2Identifier: groupV2Identifier))
//        } else if let oneToOneIdentifier {
//            guard let contactCryptoId = oneToOneIdentifier.getContactIdentity(ownedIdentity: ownedCryptoId) else {
//                assertionFailure()
//                throw ObvUICoreDataError.couldNotDetermineDiscussionIdentifier
//            }
//            return .oneToOne(id: .contactCryptoId(contactCryptoId: contactCryptoId))
//        } else {
//            throw ObvUICoreDataError.noDiscussionWasSpecified
//        }
//    }
    
    public func getObvDiscussionId(ownedCryptoId: ObvCryptoId) throws -> ObvDiscussionIdentifier {
        if let groupV1Identifier {
            return .groupV1(id: .init(ownedCryptoId: ownedCryptoId, groupV1Identifier: groupV1Identifier))
        } else if let groupV2Identifier {
            guard let identifier = ObvGroupV2.Identifier(appGroupIdentifier: groupV2Identifier) else {
                assertionFailure()
                throw ObvError.couldNotParseGroupIdentifier
            }
            return .groupV2(id: .init(ownedCryptoId: ownedCryptoId, identifier: identifier))
        } else if let oneToOneIdentifier {
            guard let obvContactId = oneToOneIdentifier.getContactIdentifier(ownedCryptoId: ownedCryptoId) else {
                assertionFailure()
                throw ObvError.unexpectedContactIdentifier
            }
            return .oneToOne(id: obvContactId)
        } else {
            throw ObvError.noDiscussionWasSpecified
        }
    }

    enum CodingKeys: String, CodingKey {
        case messageReference = "m"
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
        case oneToOneIdentifier = "o2oi" // For one-to-one discussions
    }

    public init(messageReference: MessageReferenceJSON, oneToOneIdentifier: OneToOneIdentifierJSON) {
        self.messageReference = messageReference
        self.oneToOneIdentifier = oneToOneIdentifier
        self.groupV1Identifier = nil
        self.groupV2Identifier = nil
    }

    public init(messageReference: MessageReferenceJSON, groupV1Identifier: GroupV1Identifier) {
        self.messageReference = messageReference
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = groupV1Identifier
        self.groupV2Identifier = nil
    }

    public init(messageReference: MessageReferenceJSON, groupV2Identifier: GroupV2Identifier) {
        self.messageReference = messageReference
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = nil
        self.groupV2Identifier = groupV2Identifier
    }

    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func jsonDecode(_ data: Data) throws -> ScreenCaptureDetectionJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(ScreenCaptureDetectionJSON.self, from: data)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messageReference, forKey: .messageReference)
        try container.encodeIfPresent(oneToOneIdentifier, forKey: .oneToOneIdentifier)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        try container.encodeIfPresent(groupV2Identifier, forKey: .groupV2Identifier)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        self.messageReference = try values.decode(MessageReferenceJSON.self, forKey: .messageReference)
        
        let oneToOneIdentifier = try values.decodeIfPresent(OneToOneIdentifierJSON.self, forKey: .oneToOneIdentifier)

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let oneToOneIdentifier {
            self.oneToOneIdentifier = oneToOneIdentifier
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        } else if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            throw ObvError.noDiscussionWasSpecified
        }
    }

}


extension LimitedVisibilityMessageOpenedJSON {
    
    enum ObvError: Error {
        case couldNotParseGroupIdentifier
        case unexpectedContactIdentifier
        case noDiscussionWasSpecified
    }
    
}
