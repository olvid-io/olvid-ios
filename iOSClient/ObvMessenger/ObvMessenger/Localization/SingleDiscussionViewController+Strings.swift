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

extension SingleDiscussionViewController {
    
    struct Strings {
        
        static let whatToDoWithFileTitle = NSLocalizedString("File Management", comment: "Title of alert")
        static let whatToDoWithFileMessage = NSLocalizedString("What do you want to do with this file?", comment: "Message of alert")
        static let whatToDoWithFileActionExport = NSLocalizedString("Export to the system's File App", comment: "Action of alert")
        static let whatToDoWithFileActionDelete = NSLocalizedString("Delete file", comment: "Action of alert")
        
        static let deleteMessageTitle = NSLocalizedString("Delete Message", comment: "Title of alert")
        
        static let deleteFileTitle = NSLocalizedString("Delete File", comment: "Title of alert")
        static let deleteFileMessage = NSLocalizedString("You are about to delete a file.", comment: "Message of alert")
        static let deleteFileActionDelete = NSLocalizedString("Delete file", comment: "Action of alert")
        
        
        static let deleteMessageAndAttachmentsTitle = NSLocalizedString("Delete Message and Attachments", comment: "Title of alert")
        static let deleteMessageAndAttachmentsMessage = { (numberOfAttachedFyles: Int) in
            String.localizedStringWithFormat(NSLocalizedString("You are about to delete a message together with its count attachments", comment: "Message of alert"), numberOfAttachedFyles)
        }
        
        struct Alerts {
            struct WaitingForChannel {
                
                static let title = NSLocalizedString("Your Messages are on hold", comment: "Alert title")
                static let message = NSLocalizedString("Your messages will be automatically sent once a secure channel is established for this discussion. Until then, they will remain on hold.", comment: "Text used within the footer in a discussion.")
            }
            struct WaitingForFirstGroupMember {
                static let title = WaitingForChannel.title
                static let message = NSLocalizedString("Your messages will be automatically sent once a contact accepts to join this group discussion. Until then, they will remain on hold.", comment: "Text used within the footer in a discussion.")
            }
            struct EditSentMessageBody {
                static let title = NSLocalizedString("EDIT_YOUR_MESSAGE", comment: "")
                static let message = NSLocalizedString("UPDATE_YOUR_ALREADY_SENT_MESSAGE", comment: "")
            }
        }
        
        static let sharePhotos = { (count: Int) in
            return String.localizedStringWithFormat(NSLocalizedString("share count photos", comment: "Localized dict string allowing to display a title"), count)
        }

        static let shareAttachments = { (count: Int) in
            return String.localizedStringWithFormat(NSLocalizedString("share count attachments", comment: "Localized dict string allowing to display a title"), count)
        }

        static let mutedNotificationsConfirmation = { (date: String) in String.localizedStringWithFormat(NSLocalizedString("MUTED_NOTIFICATIONS_CONFIRMATION_%@", comment: ""), date)}


    }
    
}
