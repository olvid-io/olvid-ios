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


public struct UpdateMessageJSON: Codable, Equatable, Hashable {
    
    public let messageToEdit: MessageReferenceJSON
    public let oneToOneIdentifier: OneToOneIdentifierJSON?
    public let groupV1Identifier: GroupV1Identifier?
    public let groupV2Identifier: GroupV2Identifier?
    private let newTextBody: String?
    private let userMentions: [UserMentionJSON]
    public let locationJSON: LocationJSON?
    
    public init(discussionIdentifier: ObvDiscussionIdentifier,
                messageToEdit: MessageReferenceJSON,
                newBodyAndMentions: StringAndUserMentions?,
                locationJSON: LocationJSON?) {
        self.messageToEdit = messageToEdit
        switch discussionIdentifier {
        case .oneToOne(let id):
            self.oneToOneIdentifier = .init(ownedCryptoId: id.ownedCryptoId, contactCryptoId: id.contactCryptoId)
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        case .groupV1(let id):
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = id.groupV1Identifier
            self.groupV2Identifier = nil
        case .groupV2(let id):
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = id.identifier.appGroupIdentifier
        }
        self.newTextBody = newBodyAndMentions?.body
        self.userMentions = newBodyAndMentions?.mentions.map { UserMentionJSON(mentionedCryptoId: $0.mentionedCryptoId, utf16Range: $0.utf16Range) } ?? []
        self.locationJSON = locationJSON
    }
    
    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }
    
    public var newBodyAndMentions: StringAndUserMentions? {
        guard let newTextBody, !newTextBody.isEmpty else { return nil }
        let mentions: [StringAndUserMentions.UserMention] = self.userMentions.map({ .init(mentionedCryptoId: $0.mentionedCryptoId, utf16Range: $0.utf16Range) })
        return .init(body: newTextBody, mentions: mentions)
    }
    
    enum CodingKeys: String, CodingKey {
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
        case body = "body"
        case messageToEdit = "ref"
        case userMentions = "um"
        case oneToOneIdentifier = "o2oi" // For one-to-one discussions
        case serializedLocation = "loc"
    }
    

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(oneToOneIdentifier, forKey: .oneToOneIdentifier)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let groupV2Identifier = groupV2Identifier {
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
        }
        if let newTextBody = newTextBody, !newTextBody.isEmpty {
            try container.encode(newTextBody, forKey: .body)
        }
        try container.encode(messageToEdit, forKey: .messageToEdit)

        if newTextBody != nil, !userMentions.isEmpty {
            try container.encode(userMentions, forKey: .userMentions)
        }

        try container.encodeIfPresent(locationJSON, forKey: .serializedLocation)

    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

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
            // This happens when receiving a message for a one2one discussion from a device running an old version of Olvid, which didn't use to send the oneToOneIdentifier)
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }

        self.locationJSON = try values.decodeIfPresent(LocationJSON.self, forKey: .serializedLocation)
        
        let newTextBody = try values.decodeIfPresent(String.self, forKey: .body)
        self.newTextBody = newTextBody
        self.messageToEdit = try values.decode(MessageReferenceJSON.self, forKey: .messageToEdit)

        self.userMentions = values.decodeIfPresentAndContinueAfterError([UserMentionJSON].self, forKey: .userMentions) ?? []
    }

    
    /// Allows to serialize this request when it must be saved for later in the `RemoteRequestSavedForLater` database
    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    
    /// Allows to deserialize this message when it was saved for later in the `RemoteRequestSavedForLater` database
    public static func jsonDecode(_ data: Data) throws -> UpdateMessageJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(UpdateMessageJSON.self, from: data)
    }
    
    
    /// Expected to be non-nil
    public func getDiscussionIdentifier(ownedCryptoId: ObvCryptoId) -> ObvDiscussionIdentifier? {
        if let oneToOneIdentifier {
            guard let contactIdentifier = oneToOneIdentifier.getContactIdentifier(ownedCryptoId: ownedCryptoId) else { assertionFailure(); return nil }
            return ObvDiscussionIdentifier.oneToOne(id: contactIdentifier)
        } else if let groupV1Identifier {
            let obvGroupV1Identifier = ObvGroupV1Identifier(ownedCryptoId: ownedCryptoId, groupV1Identifier: groupV1Identifier)
            return ObvDiscussionIdentifier.groupV1(id: obvGroupV1Identifier)
        } else if let groupV2Identifier {
            guard let identifier = ObvGroupV2.Identifier(appGroupIdentifier: groupV2Identifier) else { assertionFailure(); return nil }
            let obvGroupV2Identifier = ObvGroupV2Identifier(ownedCryptoId: ownedCryptoId, identifier: identifier)
            return ObvDiscussionIdentifier.groupV2(id: obvGroupV2Identifier)
        } else {
            assertionFailure()
            return nil
        }
    }

}
