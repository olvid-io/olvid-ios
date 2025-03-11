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
import ObvCrypto
import ObvTypes
import ObvAppTypes
import ObvUserNotificationsTypes


/// When an `ObvMessage` for a received message or a reaction on a sent message is received by the notification or by the app, the `ObvUserNotificationContentCreator` processes the `ObvMessage` and returns one of this enum values.
public enum ObvUserNotificationContentTypeForObvMessage {

    case silent
    case silentWithUpdatedBadgeCount(content: UNNotificationContent)
    case minimal(content: UNNotificationContent)

    case addReceivedMessage(content: UNNotificationContent, messageAppIdentifier: ObvMessageAppIdentifier, userNotificationCategory: ObvUserNotificationCategoryIdentifier, contactDeviceUIDs: Set<UID>)
    case removeReceivedMessages(content: UNNotificationContent, messageAppIdentifiers: [ObvMessageAppIdentifier])
    case updateReceivedMessage(content: UNNotificationContent, messageAppIdentifier: ObvMessageAppIdentifier)

    case addReactionOnSentMessage(content: UNNotificationContent, sentMessageReactedTo: ObvMessageAppIdentifier, reactor: ObvContactIdentifier, userNotificationCategory: ObvUserNotificationCategoryIdentifier)
    case removeReactionOnSentMessage(content: UNNotificationContent, sentMessageReactedTo: ObvMessageAppIdentifier, reactor: ObvContactIdentifier)

    case removePreviousNotificationsBasedOnObvDiscussionIdentifier(content: UNNotificationContent, obvDiscussionIdentifier: ObvDiscussionIdentifier)

    public var content: UNNotificationContent {
        switch self {
        case .silent:
            return UNNotificationContent()
        case .silentWithUpdatedBadgeCount(content: let content):
            return content
        case .minimal(let content):
            return content
        case .addReceivedMessage(content: let content, messageAppIdentifier: _, userNotificationCategory: _, contactDeviceUIDs: _):
            return content
        case .removeReceivedMessages(content: let content, messageAppIdentifiers: _):
            return content
        case .updateReceivedMessage(content: let content, messageAppIdentifier: _):
            return content
        case .addReactionOnSentMessage(content: let content, sentMessageReactedTo: _, reactor: _, userNotificationCategory: _):
            return content
        case .removeReactionOnSentMessage(content: let content, sentMessageReactedTo:_, reactor: _):
            return content
        case .removePreviousNotificationsBasedOnObvDiscussionIdentifier(content: let content, obvDiscussionIdentifier: _):
            return content
        }
    }
    
    
    public func withUpdatedBadgeCount(_ badgeCount: Int) -> Self {
        
        let mutableContent = content.mutableCopy() as! UNMutableNotificationContent
        mutableContent.badge = NSNumber(value: badgeCount)

        switch self {
        case .silent:
            return .silentWithUpdatedBadgeCount(content: mutableContent)
        case .silentWithUpdatedBadgeCount(content: _):
            return .silentWithUpdatedBadgeCount(content: mutableContent)
        case .minimal(content: _):
            return .minimal(content: mutableContent)
        case .addReceivedMessage(content: _, messageAppIdentifier: let messageAppIdentifier, userNotificationCategory: let userNotificationCategory, contactDeviceUIDs: let contactDeviceUIDs):
            return .addReceivedMessage(content: mutableContent, messageAppIdentifier: messageAppIdentifier, userNotificationCategory: userNotificationCategory, contactDeviceUIDs: contactDeviceUIDs)
        case .removeReceivedMessages(content: _, messageAppIdentifiers: let messageAppIdentifiers):
            return .removeReceivedMessages(content: mutableContent, messageAppIdentifiers: messageAppIdentifiers)
        case .updateReceivedMessage(content: _, messageAppIdentifier: let messageAppIdentifier):
            return .updateReceivedMessage(content: mutableContent, messageAppIdentifier: messageAppIdentifier)
        case .addReactionOnSentMessage(content: _, sentMessageReactedTo: let sentMessageReactedTo, reactor: let reactor, userNotificationCategory: let userNotificationCategory):
            return .addReactionOnSentMessage(content: mutableContent, sentMessageReactedTo: sentMessageReactedTo, reactor: reactor, userNotificationCategory: userNotificationCategory)
        case .removeReactionOnSentMessage(content: _, sentMessageReactedTo: let sentMessageReactedTo, reactor: let reactor):
            return .removeReactionOnSentMessage(content: mutableContent, sentMessageReactedTo: sentMessageReactedTo, reactor: reactor)
        case .removePreviousNotificationsBasedOnObvDiscussionIdentifier(content: _, obvDiscussionIdentifier: let obvDiscussionIdentifier):
            return .removePreviousNotificationsBasedOnObvDiscussionIdentifier(content: mutableContent, obvDiscussionIdentifier: obvDiscussionIdentifier)
        }
            
    }
    
    
    public var mutableContent: UNMutableNotificationContent {
        content.mutableCopy() as! UNMutableNotificationContent
    }
    
}
