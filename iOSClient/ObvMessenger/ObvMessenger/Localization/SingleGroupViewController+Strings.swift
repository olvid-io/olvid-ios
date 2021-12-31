/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

extension SingleGroupViewController {
    
    struct Strings {
        
        static let members = NSLocalizedString("Members", comment: "Stack view title")
        static let pendingMembers = NSLocalizedString("Pending members", comment: "Stack view title")

        struct GroupName {
            static let title = NSLocalizedString("Set Group Name", comment: "Alert title")
        }

        struct OlvidCardChooser {
            static let title = NSLocalizedString("New group details", comment: "Title")
            static let body = NSLocalizedString("The group owner published a new version of Group Card. Both the old and new versions are shown below.\n\nClick to update the group informations with the new version.", comment: "Body")
        }

        static let groupCard = NSLocalizedString("Group Card", comment: "Olvid card corner text")
        static let groupCardUnpublished = NSLocalizedString("Group Card - Unpublished Draft", comment: "Olvid card corner text")
        static let groupCardPublished = NSLocalizedString("Group Card - Published", comment: "Olvid card corner text")
        static let groupCardNew = NSLocalizedString("Group Card - New", comment: "Olvid card corner text")
        static let groupCardOnPhone = NSLocalizedString("Group Card - On My iPhone", comment: "Olvid card corner text")
        
        static let addMembers = NSLocalizedString("Invite Members", comment: "Button title for inviting new members to an owned contact group")
        
        static let removeMembers = NSLocalizedString("Remove Members", comment: "Button title for removing members from an owned contact groupe")

        struct reinviteContact {
            static let title = NSLocalizedString("Reinvite contact?", comment: "Alert title")
            static let message = NSLocalizedString("Do you want to send a new invitation to your contact?", comment: "Alert message")
            
        }
        
        struct refreshGroupButton {
            static let title = NSLocalizedString("Refresh group", comment: "Button title")
        }
    }
    
}
