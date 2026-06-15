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


public enum ObvLocation: Sendable, Equatable {
    
    case send(locationData: ObvLocationData, discussionIdentifier: ObvDiscussionIdentifier)
    case startSharing(locationData: ObvLocationData, discussionIdentifier: ObvDiscussionIdentifier, expirationDate: ObvLocationSharingExpirationDate)
    case updateSharing(locationData: ObvLocationData, sendTo: SharingDestination)
    case endSharing(type: SharingDestination)
    
    public var isEndSharingType: Bool {
        switch self {
        case .endSharing: return true
        default: return false
        }
    }
    
    public enum SharingDestination:Sendable, Equatable {
        
        case all // When used within `endSharing`, this ends location sharing for all profiles
        case discussion(discussionIdentifier: ObvDiscussionIdentifier)
        case discussions(discussionIdentifiers: Set<ObvDiscussionIdentifier>)
        
        public var discussionIdentifiers: Set<ObvDiscussionIdentifier> {
            switch self {
            case .discussion(discussionIdentifier: let discussionIdentifier):
                return Set([discussionIdentifier])
            case .discussions(discussionIdentifiers: let discussionIdentifiers):
                return discussionIdentifiers
            default:
                return Set()
            }
            
        }
    }
    
}


public enum ObvLocationSharingExpirationDate: Equatable, Sendable {
    case never
    case after(date: Date)
}
