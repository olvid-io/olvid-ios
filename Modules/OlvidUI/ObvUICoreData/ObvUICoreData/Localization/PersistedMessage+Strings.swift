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

extension PersistedMessage {
    public struct Strings {
        public static let noMessageYet = NSLocalizedString("No message yet.", comment: "Subtitle displayed within a discussion cell when there is no message preview to display")
        public static let markAllAsRead = NSLocalizedString("Mark all as read", comment: "Action title")
        
        public static let countAttachments = { (count: Int) in
            return String.localizedStringWithFormat(NSLocalizedString("count attachments", comment: "Number of attachments in message"), count)
        }

        public static let latestDiscussions = NSLocalizedString("Latest Discussions", comment: "Small string used in tab controller to sort by latest discussions")

        public static let unreadEphemeralMessage = NSLocalizedString("UNREAD_EPHEMERAL_MESSAGE", comment: "Subtitle displayed within a discussion cell when the message to preview is an unread ephemeral message")
        
        public static let messageWasWiped = NSLocalizedString("MESSAGE_WAS_WIPED", comment: "Subtitle displayed within a discussion cell when the message to preview is a wiped ephemeral message")
        
        public static let lastMessageWasRemotelyWiped = NSLocalizedString("LAST_MESSAGE_WAS_REMOTELY_WIPED", comment: "Subtitle displayed within a discussion cell when the message to preview was remotely wiped")
        
    }
}
