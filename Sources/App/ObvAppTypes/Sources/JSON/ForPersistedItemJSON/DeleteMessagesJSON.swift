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


public struct DeleteMessagesJSON: Codable {
    
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "deleteMessagesJSON")

    public static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    public func makeError(message: String) -> Error { DeleteMessagesJSON.makeError(message: message) }

    public let oneToOneIdentifier: OneToOneIdentifierJSON?
    public let groupV1Identifier: GroupV1Identifier?
    public let groupV2Identifier: GroupV2Identifier?
    public let messagesToDelete: [MessageReferenceJSON]

    public init(oneToOneIdentifier: OneToOneIdentifierJSON, messagesToDelete: [MessageReferenceJSON]) {
        self.oneToOneIdentifier = oneToOneIdentifier
        self.groupV1Identifier = nil
        self.groupV2Identifier = nil
        self.messagesToDelete = messagesToDelete
    }
    
    public init(groupV1Identifier: GroupV1Identifier, messagesToDelete: [MessageReferenceJSON]) {
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = groupV1Identifier
        self.groupV2Identifier = nil
        self.messagesToDelete = messagesToDelete
    }

    public init(groupV2Identifier: GroupV2Identifier, messagesToDelete: [MessageReferenceJSON]) {
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = nil
        self.groupV2Identifier = groupV2Identifier
        self.messagesToDelete = messagesToDelete
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
        case groupV2Identifier = "gid2" // For group V2
        case messagesToDelete = "refs"
        case oneToOneIdentifier = "o2oi" // For one-to-one discussions
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
        try container.encode(messagesToDelete, forKey: .messagesToDelete)
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
            // This happens when receiving a message for a one2one discussion from a device running an old version of Olvid, which didn't use to send the oneToOneIdentifier)
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }

        self.messagesToDelete = try values.decode([MessageReferenceJSON].self, forKey: .messagesToDelete)
        
    }

    
    public func getObvDiscussionId(ownedCryptoId: ObvCryptoId) throws -> ObvDiscussionIdentifier {
        if let oneToOneIdentifier {
            guard let contactIdentifier = oneToOneIdentifier.getContactIdentifier(ownedCryptoId: ownedCryptoId) else {
                assertionFailure()
                throw ObvError.unexpectedContactIdentifier
            }
            return ObvDiscussionIdentifier.oneToOne(id: contactIdentifier)
        } else if let groupV1Identifier {
            let obvGroupV1Identifier = ObvGroupV1Identifier(ownedCryptoId: ownedCryptoId, groupV1Identifier: groupV1Identifier)
            return ObvDiscussionIdentifier.groupV1(id: obvGroupV1Identifier)
        } else if let groupV2Identifier {
            guard let identifier = ObvGroupV2.Identifier(appGroupIdentifier: groupV2Identifier) else {
                assertionFailure()
                throw ObvError.couldNotParseGroupIdentifier
            }
            let obvGroupV2Identifier = ObvGroupV2Identifier(ownedCryptoId: ownedCryptoId, identifier: identifier)
            return ObvDiscussionIdentifier.groupV2(id: obvGroupV2Identifier)
        } else {
            assertionFailure()
            throw ObvError.noDiscussionWasSpecified
        }
    }

}


extension DeleteMessagesJSON {
    
    enum ObvError: Error {
        case unexpectedContactIdentifier
        case couldNotParseGroupIdentifier
        case noDiscussionWasSpecified
    }
    
}
