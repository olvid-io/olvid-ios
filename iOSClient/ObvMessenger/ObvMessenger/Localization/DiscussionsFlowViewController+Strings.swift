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
import ObvUICoreData

extension DiscussionsFlowViewController {

    struct Strings {
        
        struct Alert {
            
            struct ConfirmAllDeletionOfAllMessages {
                static let title = NSLocalizedString("DELETE_ALL_MESSAGES", comment: "Alert title")
                static let message = NSLocalizedString("THIS_ACTION_IS_IRREVERSIBLE", comment: "Alert message")
                static func actionTitle(for deletionType: DeletionType, ownedIdentityHasHasAnotherDeviceWithChannel: Bool, multipleContacts: Bool) -> String {
                    switch deletionType {
                    case .fromThisDeviceOnly:
                        return NSLocalizedString("DELETE_DISCUSSION_FROM_THIS_DEVICE_ONLY", comment: "Alert button title")
                    case .fromAllOwnedDevices:
                        return NSLocalizedString("DELETE_DISCUSSION_FROM_ALL_OWNED_DEVICES", comment: "Alert button title")
                    case .fromAllOwnedDevicesAndAllContactDevices:
                        switch (ownedIdentityHasHasAnotherDeviceWithChannel, multipleContacts) {
                        case (false, false):
                            return NSLocalizedString("DELETE_DISCUSSION_FROM_THIS_DEVICE_AND_CONTACT_DEVICES", comment: "Alert button title")
                        case (false, true):
                            return NSLocalizedString("DELETE_DISCUSSION_FROM_THIS_DEVICE_AND_ALL_CONTACTS_DEVICES", comment: "Alert button title")
                        case (true, false):
                            return NSLocalizedString("DELETE_DISCUSSION_FROM_ALL_OWNED_DEVICES_AND_CONTACT_DEVICES", comment: "Alert button title")
                        case (true, true):
                            return NSLocalizedString("DELETE_DISCUSSION_FROM_ALL_OWNED_DEVICES_AND_ALL_CONTACTS_DEVICES", comment: "Alert button title")
                        }
                    }
                }
            }
            
        }
        
        
        struct AlertConfirmAllDiscussionMessagesDeletionGlobally {
            static let title = NSLocalizedString("Delete all messages for all users?", comment: "Alert title")
            static let message = NSLocalizedString("DELETE_ALL_MSGS_ON_ALL_DEVICES__ACTION_IRREVERSIBLE", comment: "Alert message")
            static let actionDeleteAllGlobally = NSLocalizedString("Delete all messages for all users", comment: "Alert action title")
        }
    }

    
}
