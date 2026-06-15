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


public struct DiscussionSharedConfigurationJSON: Codable {
    
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "DiscussionSharedConfigurationJSON")
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { DiscussionSharedConfigurationJSON.makeError(message: message) }

    public let version: Int
    public let expiration: ExpirationJSON
    public let oneToOneIdentifier: OneToOneIdentifierJSON?
    let groupV1Identifier: GroupV1Identifier?
    let groupV2Identifier: GroupV2Identifier?
    
    public init(discussionIdentifier: ObvDiscussionIdentifier, version: Int, expiration: ExpirationJSON) {
        self.version = version
        self.expiration = expiration
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
        case version = "version"
        case expiration = "exp"
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
        case oneToOneIdentifier = "o2oi" // For one-to-one discussions
    }

    init(version: Int, expiration: ExpirationJSON, oneToOneIdentifier: OneToOneIdentifierJSON) {
        self.version = version
        self.expiration = expiration
        self.oneToOneIdentifier = oneToOneIdentifier
        self.groupV1Identifier = nil
        self.groupV2Identifier = nil
    }

    init(version: Int, expiration: ExpirationJSON, groupV1Identifier: GroupV1Identifier) {
        self.version = version
        self.expiration = expiration
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = groupV1Identifier
        self.groupV2Identifier = nil
    }

    init(version: Int, expiration: ExpirationJSON, groupV2Identifier: GroupV2Identifier) {
        self.version = version
        self.expiration = expiration
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = nil
        self.groupV2Identifier = groupV2Identifier
    }

    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func jsonDecode(_ data: Data) throws -> DiscussionSharedConfigurationJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(DiscussionSharedConfigurationJSON.self, from: data)
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
        try container.encode(version, forKey: .version)
        try container.encode(expiration, forKey: .expiration)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try values.decode(Int.self, forKey: .version)
        if let expiration = try values.decodeIfPresent(ExpirationJSON.self, forKey: .expiration) {
            self.expiration = expiration
        } else {
            self.expiration = ExpirationJSON(readOnce: false, visibilityDuration: nil, existenceDuration: nil)
        }
        
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
    }

}
