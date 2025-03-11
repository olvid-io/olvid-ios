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
import ObvUserNotificationsTypes


extension ObvUserNotificationCategoryIdentifier {
    
    /// Call this method at launch time (typically, in the `UserNotificationsManager`) to register all the actionable notification types.
    /// Later, when creating/updating a notification content, use the ``categoryIdentifier`` to define the category of the notification, so as to define the
    /// set of user actions it should present to the user.
    public static func setAllNotificationCategories(on notificationCenter: UNUserNotificationCenter) {
        let allUNNotificationCategories = Set(Self.allCases.map { $0.unNotificationCategory})
        notificationCenter.setNotificationCategories(allUNNotificationCategories)
    }

    
    private var unNotificationCategory: UNNotificationCategory {
        switch self {
        case .minimal:
            let actions = [ObvUserNotificationAction]()
            return UNNotificationCategory(identifier: categoryIdentifier,
                                          actions: actions,
                                          intentIdentifiers: [],
                                          options: [.allowInCarPlay])
        case .acceptInvite:
            return UNNotificationCategory(identifier: categoryIdentifier,
                                          actions: [.accept, .decline],
                                          intentIdentifiers: [],
                                          options: [.allowInCarPlay])
        case .newMessage:
            return UNNotificationCategory(identifier: categoryIdentifier,
                                          actions: [.mute, .replyTo, .markAsRead],
                                          intentIdentifiers: [],
                                          options: [.customDismissAction, .allowInCarPlay])
        case .newMessageWithLimitedVisibility:
            return UNNotificationCategory(identifier: categoryIdentifier,
                                          actions: [.mute],
                                          intentIdentifiers: [],
                                          options: [.customDismissAction, .allowInCarPlay])
        case .newMessageWithHiddenContent:
            let actions = [ObvUserNotificationAction]()
            return UNNotificationCategory(identifier: categoryIdentifier,
                                          actions: actions,
                                          intentIdentifiers: [],
                                          options: [.customDismissAction, .allowInCarPlay])
        case .missedCall:
            return UNNotificationCategory(identifier: categoryIdentifier,
                                          actions: [.callBack, .sendMessage],
                                          intentIdentifiers: [],
                                          options: [.allowInCarPlay])
        case .newReaction:
            return UNNotificationCategory(identifier: categoryIdentifier,
                                          actions: [.mute],
                                          intentIdentifiers: [],
                                          options: [.customDismissAction, .allowInCarPlay])
        case .invitationWithNoAction:
            let actions = [ObvUserNotificationAction]()
            return UNNotificationCategory(identifier: categoryIdentifier,
                                          actions: actions,
                                          intentIdentifiers: [],
                                          options: [.allowInCarPlay])
        case .postUserNotificationAsAnotherCallParticipantStartedCamera:
            let actions = [ObvUserNotificationAction]()
            return UNNotificationCategory(identifier: categoryIdentifier,
                                          actions: actions,
                                          intentIdentifiers: [],
                                          options: [])
        case .rejectedIncomingCallBecauseOfDeniedRecordPermission:
            let actions = [ObvUserNotificationAction]()
            return UNNotificationCategory(identifier: categoryIdentifier,
                                          actions: actions,
                                          intentIdentifiers: [],
                                          options: [])
        case .protocolMessage:
            let actions = [ObvUserNotificationAction]()
            return UNNotificationCategory(identifier: categoryIdentifier,
                                          actions: actions,
                                          intentIdentifiers: [],
                                          options: [])
        }
    }

    
}


extension UNNotificationCategory {

    /// Convenience initializer allowing to specify a `ObvUserNotificationAction` instead of a `UNNotificationAction`.
    convenience init(identifier: String, actions: [ObvUserNotificationAction], intentIdentifiers: [String], options: UNNotificationCategoryOptions = []) {
        self.init(identifier: identifier, actions: actions.map({ $0.action }), intentIdentifiers: intentIdentifiers, options: options)
    }

}
