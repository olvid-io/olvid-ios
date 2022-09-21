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
import UserNotifications

// Defining notification categories.

enum UserNotificationCategory: CaseIterable {
    case acceptInviteCategory
    case newMessageCategory
    case newMessageWithLimitedVisibilityCategory
    case missedCallCategory
    case newReactionCategory

    var identifier: String {
        switch self {
        case .acceptInviteCategory:
            return "acceptInviteCategory"
        case .newMessageCategory:
            return "newMessageCategory"
        case .newMessageWithLimitedVisibilityCategory:
            return "newMessageWithLimitedVisibilityCategory"
        case .missedCallCategory:
            return "missedCallCategory"
        case .newReactionCategory:
            return "newReactionCategory"
        }
    }

    func getCategory() -> UNNotificationCategory {
        switch self {
        case .acceptInviteCategory:
            return UNNotificationCategory(identifier: identifier,
                                          actions: [.accept, .decline],
                                          intentIdentifiers: [],
                                          options: [.customDismissAction])
        case .newMessageCategory:
            return UNNotificationCategory(identifier: identifier,
                                          actions: [.mute, .replyTo, .markAsRead],
                                          intentIdentifiers: [],
                                          options: [.customDismissAction])
        case .newMessageWithLimitedVisibilityCategory:
            return UNNotificationCategory(identifier: identifier,
                                          actions: [.mute],
                                          intentIdentifiers: [],
                                          options: [.customDismissAction])
        case .missedCallCategory:
            return UNNotificationCategory(identifier: identifier,
                                          actions: [.callBack, .sendMessage],
                                          intentIdentifiers: [],
                                          options: [.customDismissAction])
        case .newReactionCategory:
            return UNNotificationCategory(identifier: identifier,
                                          actions: [.mute],
                                          intentIdentifiers: [],
                                          options: [.customDismissAction])
        }
    }
    
}

extension UNNotificationCategory {

    convenience init(identifier: String, actions: [UserNotificationAction], intentIdentifiers: [String], options: UNNotificationCategoryOptions = []) {
        self.init(identifier: identifier, actions: actions.map({ $0.action }), intentIdentifiers: intentIdentifiers, options: options)
    }

}
