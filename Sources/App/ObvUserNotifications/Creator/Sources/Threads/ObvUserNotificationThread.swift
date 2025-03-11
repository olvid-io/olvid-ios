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
import UserNotifications
import ObvAppTypes


/// This enum is used to define specific user notification threads. Typically, we want to group all received message notifications depending by discussion.
/// Certain notifications, such as "missed call" notifications are too important, and don't happen very often, so we don't define a thread for them.
enum ObvUserNotificationThread {
    
    case minimal
    case discussion(ObvDiscussionIdentifier)
    
    var threadIdentifier: String {
        switch self {
        case .minimal:
            return ["ObvUserNotificationThread", "threadIdentifier", "minimal"].joined(separator: ".")
        case .discussion(let discussionIdentifier):
            return ["ObvUserNotificationThread", "threadIdentifier", discussionIdentifier.description].joined(separator: ".")
        }
    }
    
}
