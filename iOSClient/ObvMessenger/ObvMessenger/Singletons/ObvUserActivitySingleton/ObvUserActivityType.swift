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

enum ObvUserActivityType: CustomDebugStringConvertible, Equatable {
    
    case watchLatestDiscussions
    case continueDiscussion(persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
    case displaySingleContact
    case displayContacts
    case displayGroups
    case displaySingleGroup
    case displayInvitations
    case displaySettings // Not used for now
    case other
    
    var persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>? {
        switch self {
        case .continueDiscussion(persistedDiscussionObjectID: let persistedDiscussionObjectID):
            return persistedDiscussionObjectID
        default:
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
        }
    }
    
    var debugDescription: String {
        switch self {
        case .watchLatestDiscussions:
            return "Watch latest discussions"
        case .continueDiscussion(persistedDiscussionObjectID: let persistedDiscussionObjectID):
            return "Continue discussion \(persistedDiscussionObjectID.debugDescription)"
        case .displaySingleContact:
            return "Display single contact"
        case .displayContacts:
            return "Display contacts"
        case .displayGroups:
            return "Display groups"
        case .displaySingleGroup:
            return "Display single group"
        case .displayInvitations:
            return "Display Invitations"
        case .displaySettings:
            return "Display settings"
        case .other:
            return "Other"
        }
    }
    
    static func == (lhs: ObvUserActivityType, rhs: ObvUserActivityType) -> Bool {
        switch lhs {
        case .watchLatestDiscussions:
            switch rhs {
            case .watchLatestDiscussions:
                return true
            default:
                return false
            }
        case .continueDiscussion(let a):
            switch rhs {
            case .continueDiscussion(let b):
                return a == b
            default:
                return false
            }
        case .displaySingleContact:
            switch rhs {
            case .displaySingleContact:
                return true
            default:
                return false
            }
        case .displayContacts:
            switch rhs {
            case .displayContacts:
                return true
            default:
                return false
            }
        case .displayGroups:
            switch rhs {
            case .displayGroups:
                return true
            default:
                return false
            }
        case .displaySingleGroup:
            switch rhs {
            case .displaySingleGroup:
                return true
            default:
                return false
            }
        case .displayInvitations:
            switch rhs {
            case .displayInvitations:
                return true
            default:
                return false
            }
        case .displaySettings:
            switch rhs {
            case .displaySettings:
                return true
            default:
                return false
            }
        case .other:
            switch rhs {
            case .other:
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
