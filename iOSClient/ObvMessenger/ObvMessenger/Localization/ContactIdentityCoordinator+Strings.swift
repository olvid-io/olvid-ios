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


extension ContactIdentityCoordinator {
    
    struct Strings {
        
        static let alertDeleteContactTitle = NSLocalizedString("Delete this contact?", comment: "Alert title")

        static let alertActionTitleDeleteContact = NSLocalizedString("Delete contact", comment: "Action title")

        struct AlertCommonGroupOnContactDeletion {
            static let title = NSLocalizedString("Contact cannot be deleted for now", comment: "Alert title")
            static let message = { (contactName: String) in
                String.localizedStringWithFormat(NSLocalizedString("You cannot remove %@ from your contacts as both of you belong to some common groups. You will need to leave these groups to proceed.", comment: "Alert message"), contactName)
            }
        }

        struct AlertCommonGroupWhereContactToDeleteIsPending {
            static let message = { (contactName: String) in
                String.localizedStringWithFormat(NSLocalizedString("You are about to remove %1$@ from your contacts. You will no longer be able to exchange messages with them.\n\nNote that %1$@ is a pending member in at least one group you belong to. %1$@ might get added back to your contacts in a near future. You may want to leave these groups to avoid this.\n\nReally delete this contact?", comment: "Alert message"), contactName)
            }
        }
        
        static let alertDeleteContactMessage = { (contactName: String) in String.localizedStringWithFormat(NSLocalizedString("You are about to remove %1$@ from your contacts. You will no longer be able to exchange messages with them.\n\nReally delete this contact?", comment: "Alert message"), contactName)}

    }
    
}
