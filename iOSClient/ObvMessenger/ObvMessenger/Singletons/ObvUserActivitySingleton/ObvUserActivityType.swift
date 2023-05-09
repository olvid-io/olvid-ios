/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import CoreData
import ObvTypes

enum ObvUserActivityType: CustomDebugStringConvertible, Equatable {
        
    case watchLatestDiscussions(ownedCryptoId: ObvCryptoId)
    case continueDiscussion(ownedCryptoId: ObvCryptoId, discussionPermanentID: DiscussionPermanentID)
    case displaySingleContact(ownedCryptoId: ObvCryptoId, contactPermanentID: ContactPermanentID)
    case displayContacts(ownedCryptoId: ObvCryptoId)
    case displayGroups(ownedCryptoId: ObvCryptoId)
    case displaySingleGroup(ownedCryptoId: ObvCryptoId, displayedContactGroupPermanentID: DisplayedContactGroupPermanentID)
    case displayInvitations(ownedCryptoId: ObvCryptoId)
    case displaySettings(ownedCryptoId: ObvCryptoId) // Not used for now
    case other(ownedCryptoId: ObvCryptoId)
    case unknown
    
    var discussionPermanentID: DiscussionPermanentID? {
        switch self {
        case .continueDiscussion(ownedCryptoId: _, discussionPermanentID: let discussionPermanentID):
            return discussionPermanentID
        default:
            return nil
        }
    }
    
    var ownedCryptoId: ObvCryptoId? {
        switch self {
        case .watchLatestDiscussions(let ownedCryptoId):
            return ownedCryptoId
        case .continueDiscussion(let ownedCryptoId, _):
            return ownedCryptoId
        case .displaySingleContact(let ownedCryptoId, _):
            return ownedCryptoId
        case .displayContacts(let ownedCryptoId):
            return ownedCryptoId
        case .displayGroups(let ownedCryptoId):
            return ownedCryptoId
        case .displaySingleGroup(let ownedCryptoId, _):
            return ownedCryptoId
        case .displayInvitations(let ownedCryptoId):
            return ownedCryptoId
        case .displaySettings(let ownedCryptoId):
            return ownedCryptoId
        case .other(let ownedCryptoId):
            return ownedCryptoId
        case .unknown:
            return nil
        }
    }
    
    // NSUserActivityTypes (as declared in info.plist)
    var nsUserActivityType: String {
        switch self {
        case .watchLatestDiscussions: return "io.olvid.messenger.watchLatestDiscussions"
        case .continueDiscussion: return "io.olvid.messenger.continueDiscussion"
        case .displaySingleContact: return "io.olvid.messenger.displaySingleContact"
        case .displayContacts: return "io.olvid.messenger.displayContacts"
        case .displayGroups: return "io.olvid.messenger.displayGroups"
        case .displayInvitations: return "io.olvid.messenger.displayInvitations"
        case .displaySettings: return "io.olvid.messenger.displaySettings"
        case .displaySingleGroup: return "io.olvid.messenger.displaySingleGroup"
        case .other: return "io.olvid.messenger.other"
        case .unknown: return "io.olvid.messenger.unknown"
        }
    }
    
    var debugDescription: String {
        switch self {
        case .watchLatestDiscussions(ownedCryptoId: let ownedCryptoId):
            return "Watch latest discussions \(ownedCryptoId.debugDescription)"
        case .continueDiscussion(ownedCryptoId: let ownedCryptoId, discussionPermanentID: let discussionPermanentID):
            return "Continue discussion \(ownedCryptoId.debugDescription) \(discussionPermanentID.debugDescription)"
        case .displaySingleContact(ownedCryptoId: let ownedCryptoId, contactPermanentID: let contactPermanentID):
            return "Display single contact \(ownedCryptoId.debugDescription) \(contactPermanentID.debugDescription)"
        case .displayContacts(ownedCryptoId: let ownedCryptoId):
            return "Display contacts \(ownedCryptoId.debugDescription)"
        case .displayGroups(ownedCryptoId: let ownedCryptoId):
            return "Display groups \(ownedCryptoId.debugDescription)"
        case .displaySingleGroup(ownedCryptoId: let ownedCryptoId, displayedContactGroupPermanentID: let displayedContactGroupPermanentID):
            return "Display single group \(ownedCryptoId.debugDescription) \(displayedContactGroupPermanentID.debugDescription)"
        case .displayInvitations(ownedCryptoId: let ownedCryptoId):
            return "Display Invitations \(ownedCryptoId.debugDescription)"
        case .displaySettings(ownedCryptoId: let ownedCryptoId):
            return "Display settings \(ownedCryptoId.debugDescription)"
        case .other(ownedCryptoId: let ownedCryptoId):
            return "Other \(ownedCryptoId.debugDescription)"
        case .unknown:
            return "Unknown"
        }
    }
    
    static func == (lhs: ObvUserActivityType, rhs: ObvUserActivityType) -> Bool {
        switch lhs {
        case .watchLatestDiscussions(let a):
            switch rhs {
            case .watchLatestDiscussions(let b):
                return a == b
            default:
                return false
            }
        case .continueDiscussion(let a1, let a2):
            switch rhs {
            case .continueDiscussion(let b1, let b2):
                return a1 == b1 && a2 == b2
            default:
                return false
            }
        case .displaySingleContact(let a1, let a2):
            switch rhs {
            case .displaySingleContact(let b1, let b2):
                return a1 == b1 && a2 == b2
            default:
                return false
            }
        case .displayContacts(let a):
            switch rhs {
            case .displayContacts(let b):
                return a == b
            default:
                return false
            }
        case .displayGroups(let a):
            switch rhs {
            case .displayGroups(let b):
                return a == b
            default:
                return false
            }
        case .displaySingleGroup(let a1, let a2):
            switch rhs {
            case .displaySingleGroup(let b1, let b2):
                return a1 == b1 && a2 == b2
            default:
                return false
            }
        case .displayInvitations(let a):
            switch rhs {
            case .displayInvitations(let b):
                return a == b
            default:
                return false
            }
        case .displaySettings(let a):
            switch rhs {
            case .displaySettings(let b):
                return a == b
            default:
                return false
            }
        case .other(let a):
            switch rhs {
            case .other(let b):
                return a == b
            default:
                return false
            }
        case .unknown:
            switch rhs {
            case .unknown:
                return true
            default:
                return false
            }
        }
    }
    
    var isContinueDiscussion: Bool {
        switch self {
        case .continueDiscussion:
            return true
        default:
            return false
        }
    }

}
