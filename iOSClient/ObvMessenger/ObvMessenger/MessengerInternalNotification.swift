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
import ObvEngine

struct MessengerInternalNotification {
    
    // MARK: - UserRequestedFylePauseDownload
    
    struct UserRequestedFylePauseDownload {
        static let name = NSNotification.Name("MessengerInternalNotification.UserRequestedFylePauseDownload")
        struct Key {
            static let objectID = "objectID" // NSManagedObjectID of a ReceivedFyleMessageJoinWithStatus
        }
        static func parse(_ notification: Notification) -> NSManagedObjectID? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let objectID = userInfo[Key.objectID] as? NSManagedObjectID else { return nil }
            return objectID
        }
    }
    
    
    // MARK: - CreateNewGroup
    
    struct CreateNewGroup {
        static let name = NSNotification.Name("MessengerInternalNotification.CreateNewGroup")
        struct Key {
            static let groupName = "groupName"
            static let groupDescription = "groupDescription"
            static let groupMembersCryptoIds = "groupMembersCryptoIds"
            static let ownedCryptoId = "ownedCryptoId"
            static let photoURL = "photoURL"
        }
        static func parse(_ notification: Notification) -> (groupName: String, groupDescription: String?, groupMembersCryptoIds: Set<ObvCryptoId>, ownedCryptoId: ObvCryptoId, photoURL: URL?)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupName = userInfo[Key.groupName] as? String else { return nil }
            guard let groupDescription = userInfo[Key.groupDescription] as? String? else { return nil }
            guard let groupMembersCryptoIds = userInfo[Key.groupMembersCryptoIds] as? Set<ObvCryptoId> else { return nil }
            guard let ownedCryptoId = userInfo[Key.ownedCryptoId] as? ObvCryptoId else { return nil }
            let photoURL = userInfo[Key.photoURL] as? URL
            return (groupName, groupDescription, groupMembersCryptoIds, ownedCryptoId, photoURL)
        }
    }
    
    
    // MARK: - EditOwnedGroupDetails
    
    struct EditOwnedGroupDetails {
        static let name = NSNotification.Name("MessengerInternalNotification.EditOwnedGroupDetails")
        struct Key {
            static let groupUid = "groupUid"
            static let ownedCryptoId = "ownedCryptoId"
            static let groupName = "groupName"
            static let groupDescription = "groupDescription"
        }
        static func parse(_ notification: Notification) -> (groupUid: UID, ownedCryptoId: ObvCryptoId, groupName: String, groupDescription: String?)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let ownedCryptoId = userInfo[Key.ownedCryptoId] as? ObvCryptoId else { return nil }
            guard let groupName = userInfo[Key.groupName] as? String else { return nil }
            guard let groupDescription = userInfo[Key.groupDescription] as? String? else { return nil }
            return (groupUid, ownedCryptoId, groupName, groupDescription)
        }
    }

    
    // MARK: - InviteContactsToGroupOwned
    
    struct InviteContactsToGroupOwned {
        static let name = NSNotification.Name("MessengerInternalNotification.InviteContactsToGroupOwned")
        struct Key {
            static let groupUid = "groupUid"
            static let ownedCryptoId = "ownedCryptoId"
            static let newGroupMembers = "newGroupMembers"
        }
        static func parse(_ notification: Notification) -> (groupUid: UID, ownedCryptoId: ObvCryptoId, newGroupMembers: Set<ObvCryptoId>)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let ownedCryptoId = userInfo[Key.ownedCryptoId] as? ObvCryptoId else { return nil }
            guard let newGroupMembers = userInfo[Key.newGroupMembers] as? Set<ObvCryptoId> else { return nil }
            return (groupUid, ownedCryptoId, newGroupMembers)
        }
    }

    
    // MARK: - RemoveContactsFromGroupOwned
    
    struct RemoveContactsFromGroupOwned {
        static let name = NSNotification.Name("MessengerInternalNotification.RemoveContactsFromGroupOwned")
        struct Key {
            static let groupUid = "groupUid"
            static let ownedCryptoId = "ownedCryptoId"
            static let removedContacts = "removedContacts"
        }
        static func parse(_ notification: Notification) -> (groupUid: UID, ownedCryptoId: ObvCryptoId, removedContacts: Set<ObvCryptoId>)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let ownedCryptoId = userInfo[Key.ownedCryptoId] as? ObvCryptoId else { return nil }
            guard let removedContacts = userInfo[Key.removedContacts] as? Set<ObvCryptoId> else { return nil }
            return (groupUid, ownedCryptoId, removedContacts)
        }
    }

    // MARK: - ApplicationIconBadgeNumberWasUpdated
    
    struct ApplicationIconBadgeNumberWasUpdated {
        static let name = NSNotification.Name("MessengerInternalNotification.ApplicationIconBadgeNumberWasUpdated")
    }

    
    // MARK: - UserWantsToRefreshDiscussions {
    struct UserWantsToRefreshDiscussions {
        static let name = NSNotification.Name("MessengerInternalNotification.UserWantsToRefreshDiscussions")
        struct Key {
            static let completionHandler = "completionHandler"
        }
        static func parse(_ notification: Notification) -> (() -> Void)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let completionHandler = userInfo[Key.completionHandler] as? () -> Void else { return nil }
            return completionHandler
        }

    }
    
    
    // MARK: - TextFieldDidBeginEditing
    struct TextFieldDidBeginEditing {
        static let name = NSNotification.Name("MessengerInternalNotification.TextFieldDidBeginEditing")
        struct Key {
            static let textField = "textField"
        }
        static func parse(_ notification: Notification) -> UITextField? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let textField = userInfo[Key.textField] as? UITextField else { return nil }
            return textField
        }
    }
    
    
    // MARK: - TextFieldDidBeginEditing
    struct TextFieldDidEndEditing {
        static let name = NSNotification.Name("MessengerInternalNotification.TextFieldDidEndEditing")
        struct Key {
            static let textField = "textField"
        }
        static func parse(_ notification: Notification) -> UITextField? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let textField = userInfo[Key.textField] as? UITextField else { return nil }
            return textField
        }
    }

    
    // MARK: - UserTriedToAccessCameraButAccessIsDenied
    struct UserTriedToAccessCameraButAccessIsDenied {
        static let name = NSNotification.Name("MessengerInternalNotification.UserTriedToAccessCameraButAccessIsDenied")
    }
    
    // MARK: - UserWantsToDeleteOwnedContactGroup

    struct UserWantsToDeleteOwnedContactGroup {
        static let name = NSNotification.Name("MessengerInternalNotification.UserWantsToDeleteOwnedContactGroup")
        struct Key {
            static let groupUid = "groupUid"
            static let ownedCryptoId = "ownedCryptoId"
        }
        static func parse(_ notification: Notification) -> (groupUid: UID, ownedCryptoId: ObvCryptoId)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let ownedCryptoId = userInfo[Key.ownedCryptoId] as? ObvCryptoId else { return nil }
            return (groupUid, ownedCryptoId)
        }
    }

    // MARK: - UserWantsToLeaveJoinedContactGroup
    
    struct UserWantsToLeaveJoinedContactGroup {
        static let name = NSNotification.Name("MessengerInternalNotification.UserWantsToLeaveJoinedContactGroup")
        struct Key {
            static let groupUid = "groupUid"
            static let groupOwner = "groupOwner"
            static let ownedCryptoId = "ownedCryptoId"
            static let sourceView = "sourceView"
        }
        static func parse(_ notification: Notification) -> (groupOwner: ObvCryptoId, groupUid: UID, ownedCryptoId: ObvCryptoId, sourceView: UIView)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let groupUid = userInfo[Key.groupUid] as? UID else { return nil }
            guard let ownedCryptoId = userInfo[Key.ownedCryptoId] as? ObvCryptoId else { return nil }
            guard let groupOwner = userInfo[Key.groupOwner] as? ObvCryptoId else { return nil }
            guard let sourceView = userInfo[Key.sourceView] as? UIView else { return nil }
            return (groupOwner, groupUid, ownedCryptoId, sourceView)
        }
    }

}
