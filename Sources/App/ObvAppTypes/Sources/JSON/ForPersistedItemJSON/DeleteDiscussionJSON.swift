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


public struct DeleteDiscussionJSON: Codable {
    
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "DeleteDiscussionJSON")

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { DeleteDiscussionJSON.makeError(message: message) }

    public let oneToOneIdentifier: OneToOneIdentifierJSON?
    public let groupV1Identifier: GroupV1Identifier?
    public let groupV2Identifier: GroupV2Identifier?

    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }
    
    public init(discussionIdentifier: ObvDiscussionIdentifier) {
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
    }

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
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

    }


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

}


extension DeleteDiscussionJSON {
    
    enum ObvError: Error {
        case couldNotDetermineDiscussionIdentifier
        case noDiscussionWasSpecified
        case couldNotParseGroupIdentifier
        case unexpectedContactIdentifier
    }
    
}
