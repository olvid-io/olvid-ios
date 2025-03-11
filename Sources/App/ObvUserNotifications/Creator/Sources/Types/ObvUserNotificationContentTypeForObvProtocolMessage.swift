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


public enum ObvUserNotificationContentTypeForObvProtocolMessage {
    
    case silent
    case silentWithUpdatedBadgeCount(content: UNNotificationContent)
    case minimal(content: UNNotificationContent)

    case addProtocolMessage(content: UNNotificationContent)

    
    public var content: UNNotificationContent {
        switch self {
        case .silent:
            return UNNotificationContent()
        case .silentWithUpdatedBadgeCount(content: let content):
            return content
        case .minimal(let content):
            return content
        case .addProtocolMessage(content: let content):
            return content
        }
    }

    
    public func withUpdatedBadgeCount(_ badgeCount: Int) -> Self {
        switch self {
        case .silent, .silentWithUpdatedBadgeCount:
            let mutableContent = UNMutableNotificationContent()
            mutableContent.badge = NSNumber(value: badgeCount)
            return .silentWithUpdatedBadgeCount(content: mutableContent)
        case .minimal(content: let content):
            let mutableContent = content.mutableCopy() as! UNMutableNotificationContent
            mutableContent.badge = NSNumber(value: badgeCount)
            return .minimal(content: mutableContent)
        case .addProtocolMessage(content: let content):
            let mutableContent = content.mutableCopy() as! UNMutableNotificationContent
            mutableContent.badge = NSNumber(value: badgeCount)
            return .addProtocolMessage(content: mutableContent)
        }
    }

}
