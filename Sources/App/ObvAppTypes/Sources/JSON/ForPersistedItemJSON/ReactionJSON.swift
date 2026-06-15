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


public struct ReactionJSON: Codable, Sendable {

    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "ReactionJSON")

    public static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    public func makeError(message: String) -> Error { ReactionJSON.makeError(message: message) }

    public let messageReference: MessageReferenceJSON
    public let oneToOneIdentifier: OneToOneIdentifierJSON?
    public let groupV1Identifier: GroupV1Identifier?
    public let groupV2Identifier: GroupV2Identifier?
    public let emoji: String?
    /// Value set when re-sending a `ReactionJSON` to a group v2 member as they switch from pending to non-pending.
    public let originalServerTimestamp: Date?
    
    public init(messageReference: MessageReferenceJSON,
                oneToOneIdentifier: OneToOneIdentifierJSON?,
                groupV1Identifier: GroupV1Identifier?,
                groupV2Identifier: GroupV2Identifier?,
                emoji: String?,
                originalServerTimestamp: Date?) {
        self.messageReference = messageReference
        self.oneToOneIdentifier = oneToOneIdentifier
        self.groupV1Identifier = groupV1Identifier
        self.groupV2Identifier = groupV2Identifier
        self.emoji = emoji
        self.originalServerTimestamp = originalServerTimestamp
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

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
        case emoji = "reac"
        case messageReference = "ref"
        case oneToOneIdentifier = "o2oi" // For one-to-one discussions
        case originalServerTimestamp = "ost"
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
        try container.encodeIfPresent(emoji, forKey: .emoji)
        try container.encode(messageReference, forKey: .messageReference)
        try container.encodeIfPresent(originalServerTimestamp?.epochInMs, forKey: .originalServerTimestamp)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)

        let oneToOneIdentifier = try values.decodeIfPresent(OneToOneIdentifierJSON.self, forKey: .oneToOneIdentifier)
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
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }

        self.emoji = try values.decodeIfPresent(String.self, forKey: .emoji)
        self.messageReference = try values.decode(MessageReferenceJSON.self, forKey: .messageReference)
        
        if let originalServerTimestampInMilliseconds = try values.decodeIfPresent(Int64.self, forKey: .originalServerTimestamp) {
            self.originalServerTimestamp = Date(epochInMs: originalServerTimestampInMilliseconds)
        } else {
            self.originalServerTimestamp = nil
        }

    }

    /// Allows to serialize this request when it must be saved for later in the `RemoteRequestSavedForLater` database
    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    
    /// Allows to deserialize this message when it was saved for later in the `RemoteRequestSavedForLater` database
    public static func jsonDecode(_ data: Data) throws -> ReactionJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(ReactionJSON.self, from: data)
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
