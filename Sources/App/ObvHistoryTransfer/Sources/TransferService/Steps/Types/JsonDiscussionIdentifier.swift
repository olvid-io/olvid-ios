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
import ObvAppTypes
import ObvCrypto


public struct JsonDiscussionIdentifier: Sendable, Equatable, Hashable {

    private let type: DiscussionKind
    let identifier: Data
    
    private enum DiscussionKind: Int {
        case oneToOne = 1
        case groupV1 = 2
        case groupV2 = 3
    }
 
    public init(_ discussionIdentifier: ObvDiscussionIdentifier) {
        switch discussionIdentifier {
        case .oneToOne(let contactIdentifier):
            self.type = .oneToOne
            self.identifier = contactIdentifier.contactCryptoId.getIdentity()
        case .groupV1(let groupV1Identifier):
            self.type = .groupV1
            self.identifier = groupV1Identifier.groupV1Identifier.groupOwner.getIdentity() + groupV1Identifier.groupV1Identifier.groupUid.raw
        case .groupV2(let groupV2Identifier):
            self.type = .groupV2
            self.identifier = groupV2Identifier.identifier.appGroupIdentifier
        }
    }
    
    
    func getDiscussionIdentifier(ownedCryptoId: ObvCryptoId) throws -> ObvDiscussionIdentifier {
        switch type {
        case .oneToOne:
            let contactCryptoId = try ObvCryptoId(identity: self.identifier)
            let contactIdentifier = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            return .oneToOne(id: contactIdentifier)
        case .groupV1:
            let lengthForGroupOwnerIdentity = self.identifier.count - UID.length
            guard lengthForGroupOwnerIdentity > 0 else {
                assertionFailure()
                throw ObvError.decodingError
            }
            let groupOwnerIdentity = self.identifier[0..<lengthForGroupOwnerIdentity]
            let groupOwner = try ObvCryptoId(identity: groupOwnerIdentity)
            let rawUID = self.identifier[lengthForGroupOwnerIdentity...]
            guard rawUID.count == UID.length, let groupUID = UID(uid: rawUID) else {
                assertionFailure()
                throw ObvError.decodingError
            }
            return .groupV1(id: .init(ownedCryptoId: ownedCryptoId, groupV1Identifier: .init(groupUid: groupUID, groupOwner: groupOwner)))
        case .groupV2:
            guard let groupV2Identifier = ObvGroupV2.Identifier(appGroupIdentifier: self.identifier) else {
                assertionFailure()
                throw ObvError.decodingError
            }
            return .groupV2(id: .init(ownedCryptoId: ownedCryptoId, identifier: groupV2Identifier))
        }
    }
    
}

extension JsonDiscussionIdentifier: Codable {
    
    enum CodingKeys: String, CodingKey {
        case type = "t"
        case identifier = "id"
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(identifier, forKey: .identifier)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try values.decode(Int.self, forKey: .type)
        guard let type = DiscussionKind(rawValue: rawType) else {
            assertionFailure()
            throw ObvError.decodingError
        }
        self.type = type
        self.identifier = try values.decode(Data.self, forKey: .identifier)
    }
    
}


extension JsonDiscussionIdentifier {
    
    enum ObvError: Error {
        case decodingError
    }
    
}
