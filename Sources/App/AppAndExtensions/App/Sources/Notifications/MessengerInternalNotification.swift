/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvCrypto

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
