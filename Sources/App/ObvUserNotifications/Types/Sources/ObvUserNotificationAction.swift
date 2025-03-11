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

public enum ObvUserNotificationAction: String {
    case accept = "ACCEPT_ACTION"
    case decline = "DECLINE_ACTION"
    case mute = "MUTE_ACTION"
    case callBack = "CALL_BACK_ACTION"
    case replyTo = "REPLY_TO_ACTION"
    case sendMessage = "SEND_MESSAGE_ACTION"
    case markAsRead = "MARK_AS_READ_ACTION"
}
