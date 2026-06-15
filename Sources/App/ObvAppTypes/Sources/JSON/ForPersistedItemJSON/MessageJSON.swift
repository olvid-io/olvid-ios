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
import OSLog
import ObvAppCoreConstants
import ObvTypes
import ObvCrypto


public struct MessageJSON: Equatable, Hashable {
    
    public let senderSequenceNumber: Int
    public let senderThreadIdentifier: UUID
    private let rawBody: String?
    public let oneToOneIdentifier: OneToOneIdentifierJSON?
    public let groupV1Identifier: GroupV1Identifier?
    public let groupV2Identifier: GroupV2Identifier?
    public let replyTo: MessageReferenceJSON?
    public let expiration: ExpirationJSON?
    public let location: LocationJSON?
    public let poll: PollJSON?
    
    public let forwarded: Bool
    /// This is the server timestamp received the first time the sender sent infos about this message.
    /// It is used to properly sort messages in Group V2 discussions.
    public let originalServerTimestamp: Date?
    private let userMentions: [UserMentionJSON]

    
    public init(senderSequenceNumber: Int,
                senderThreadIdentifier: UUID,
                bodyAndMentions: StringAndUserMentions?,
                oneToOneIdentifier: OneToOneIdentifierJSON,
                replyTo: MessageReferenceJSON?,
                expiration: ExpirationJSON?,
                location: LocationJSON?,
                forwarded: Bool,
                poll: PollJSON?) {
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.rawBody = bodyAndMentions?.body
        self.oneToOneIdentifier = oneToOneIdentifier
        self.groupV1Identifier = nil
        self.groupV2Identifier = nil
        self.replyTo = replyTo
        self.expiration = expiration
        self.location = location
        self.forwarded = forwarded
        self.originalServerTimestamp = nil // Never set for oneToOne discussions
        self.userMentions = bodyAndMentions?.mentions.map { UserMentionJSON(mentionedCryptoId: $0.mentionedCryptoId, utf16Range: $0.utf16Range) } ?? []
        self.poll = poll
    }

    public init(senderSequenceNumber: Int,
                senderThreadIdentifier: UUID,
                bodyAndMentions: StringAndUserMentions?,
                groupV1Identifier: GroupV1Identifier,
                replyTo: MessageReferenceJSON?,
                expiration: ExpirationJSON?,
                location: LocationJSON?,
                forwarded: Bool,
                poll: PollJSON?) {
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.rawBody = bodyAndMentions?.body
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = groupV1Identifier
        self.groupV2Identifier = nil
        self.replyTo = replyTo
        self.expiration = expiration
        self.location = location
        self.forwarded = forwarded
        self.originalServerTimestamp = nil // Never set for Group V1 discussions
        self.userMentions = bodyAndMentions?.mentions.map { UserMentionJSON(mentionedCryptoId: $0.mentionedCryptoId, utf16Range: $0.utf16Range) } ?? []
        self.poll = poll
    }

    public init(senderSequenceNumber: Int,
                senderThreadIdentifier: UUID,
                bodyAndMentions: StringAndUserMentions?,
                groupV2Identifier: GroupV2Identifier,
                replyTo: MessageReferenceJSON?,
                expiration: ExpirationJSON?,
                location: LocationJSON?,
                forwarded: Bool,
                originalServerTimestamp: Date?,
                poll: PollJSON?) {
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.rawBody = bodyAndMentions?.body
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = nil
        self.groupV2Identifier = groupV2Identifier
        self.replyTo = replyTo
        self.expiration = expiration
        self.location = location
        self.forwarded = forwarded
        self.originalServerTimestamp = originalServerTimestamp
        self.userMentions = bodyAndMentions?.mentions.map { UserMentionJSON(mentionedCryptoId: $0.mentionedCryptoId, utf16Range: $0.utf16Range) } ?? []
        self.poll = poll
    }

}


// MARK: - Public helpers

extension MessageJSON {
    
    public var body: String? {
        rawBody?.replacingOccurrences(of: "\0", with: " ")
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
    
    
    public var bodyAndMentions: StringAndUserMentions? {
        guard let body, !body.isEmpty else { return nil }
        let mentions: [StringAndUserMentions.UserMention] = self.userMentions.map({ .init(mentionedCryptoId: $0.mentionedCryptoId, utf16Range: $0.utf16Range) })
        return .init(body: body, mentions: mentions)
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


// MARK: - Implementing Codable

extension MessageJSON: Codable {
    
    
    enum CodingKeys: String, CodingKey {
        case senderSequenceNumber = "ssn"
        case senderThreadIdentifier = "sti"
        case groupUid = "guid" // For group v1
        case groupOwner = "go" // For group v1
        case groupV2Identifier = "gid2" // For group v2
        case oneToOneIdentifier = "o2oi" // For one-to-one discussions
        case body = "body"
        case replyTo = "re"
        case expiration = "exp"
        case location = "loc"
        case forwarded = "fw"
        case originalServerTimestamp = "ost"
        case userMentions = "um"
        case poll = "p"
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
            try container.encodeIfPresent(originalServerTimestamp?.epochInMs, forKey: .originalServerTimestamp)
        }
        try container.encode(senderSequenceNumber, forKey: .senderSequenceNumber)
        try container.encode(senderThreadIdentifier, forKey: .senderThreadIdentifier)
        if let body = body {
            try container.encode(body, forKey: .body)
        }
        if let replyTo = replyTo {
            try container.encode(replyTo, forKey: .replyTo)
        }
        if let expiration = expiration {
            try container.encode(expiration, forKey: .expiration)
        }
        if let location = location {
            try container.encode(location, forKey: .location)
        }
        
        if let poll = poll {
            try container.encode(poll, forKey: .poll)
        }
        try container.encode(forwarded, forKey: .forwarded)

        if body != nil, !userMentions.isEmpty {
            try container.encode(userMentions, forKey: .userMentions)
        }

    }

    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.senderSequenceNumber = try values.decode(Int.self, forKey: .senderSequenceNumber)
        self.senderThreadIdentifier = try values.decode(UUID.self, forKey: .senderThreadIdentifier)
        let body = try values.decodeIfPresent(String.self, forKey: .body)

        self.rawBody = body

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
                
        self.replyTo = try values.decodeIfPresent(MessageReferenceJSON.self, forKey: .replyTo)
        self.expiration = try values.decodeIfPresent(ExpirationJSON.self, forKey: .expiration)
        self.location = try values.decodeIfPresent(LocationJSON.self, forKey: .location)
        self.forwarded = try values.decodeIfPresent(Bool.self, forKey: .forwarded) ?? false
        self.poll = try values.decodeIfPresent(PollJSON.self, forKey: .poll)
        
        let originalServerTimestampInMilliseconds = try values.decodeIfPresent(Int64.self, forKey: .originalServerTimestamp)
        if groupV2Identifier != nil, let originalServerTimestampInMilliseconds = originalServerTimestampInMilliseconds {
            self.originalServerTimestamp = Date(epochInMs: originalServerTimestampInMilliseconds)
        } else {
            self.originalServerTimestamp = nil
        }

        self.userMentions = values.decodeIfPresentAndContinueAfterError([UserMentionJSON].self, forKey: .userMentions) ?? []

    }

    
    //    func jsonEncode() throws -> Data {
    //        let encoder = JSONEncoder()
    //        return try encoder.encode(self)
    //    }
    //
    //    static func jsonDecode(_ data: Data) throws -> MessageJSON {
    //        let decoder = JSONDecoder()
    //        return try decoder.decode(MessageJSON.self, from: data)
    //    }

}
