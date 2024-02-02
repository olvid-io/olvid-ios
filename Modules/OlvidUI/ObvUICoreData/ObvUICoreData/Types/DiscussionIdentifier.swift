/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import CoreData


public enum DiscussionIdentifier: CustomDebugStringConvertible {
    case oneToOne(id: OneToOneDiscussionIdentifier)
    case groupV1(id: GroupV1DiscussionIdentifier)
    case groupV2(id: GroupV2DiscussionIdentifier)
    
    public var debugDescription: String {
        let prefix = "DiscussionIdentifier"
        let suffix: String
        switch self {
        case .oneToOne(let id):
            suffix = ["oneToOne", id.debugDescription].joined(separator: ".")
        case .groupV1(let id):
            suffix = ["groupV1", id.debugDescription].joined(separator: ".")
        case .groupV2(let id):
            suffix = ["groupV2", id.debugDescription].joined(separator: ".")
        }
        return [prefix, suffix].joined(separator: ".")
    }
    
}


public enum OneToOneDiscussionIdentifier: CustomDebugStringConvertible {
    case objectID(objectID: NSManagedObjectID)
    case contactCryptoId(contactCryptoId: ObvCryptoId)
    
    public var debugDescription: String {
        let prefix = "OneToOneDiscussionIdentifier"
        let suffix: String
        switch self {
        case .objectID:
            suffix = "objectID"
        case .contactCryptoId:
            suffix = "contactCryptoId"
        }
        return [prefix, suffix].joined(separator: ".")
    }
    
}


public enum GroupV1DiscussionIdentifier: CustomDebugStringConvertible {
    case objectID(objectID: NSManagedObjectID)
    case groupV1Identifier(groupV1Identifier: GroupV1Identifier)
    
    public var debugDescription: String {
        let prefix = "GroupV1DiscussionIdentifier"
        let suffix: String
        switch self {
        case .objectID:
            suffix = "objectID"
        case .groupV1Identifier:
            suffix = "groupV1Identifier"
        }
        return [prefix, suffix].joined(separator: ".")
    }
    
}


public enum GroupV2DiscussionIdentifier: CustomDebugStringConvertible {
    case objectID(objectID: NSManagedObjectID)
    case groupV2Identifier(groupV2Identifier: GroupV2Identifier)
    
    public var debugDescription: String {
        let prefix = "GroupV2DiscussionIdentifier"
        let suffix: String
        switch self {
        case .objectID:
            suffix = "objectID"
        case .groupV2Identifier:
            suffix = "groupV2Identifier"
        }
        return [prefix, suffix].joined(separator: ".")
    }
    
}
