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
    case missedCallCategory

    func getIdentifier() -> String {
        switch self {
        case .acceptInviteCategory:
            return "acceptInviteCategory"
        case .newMessageCategory:
            return "newMessageCategory"
        case .missedCallCategory:
            return "missedCallCategory"
        }
    }
    
    func getCategory() -> UNNotificationCategory {
        switch self {
        case .acceptInviteCategory:
            return UNNotificationCategory(identifier: self.getIdentifier(),
                                          actions: [UserNotificationAction.accept.action, UserNotificationAction.decline.action],
                                          intentIdentifiers: [],
                                          options: [.customDismissAction])
        case .newMessageCategory:
            return UNNotificationCategory(identifier: self.getIdentifier(),
                                          actions: [UserNotificationAction.mute.action],
                                          intentIdentifiers: [],
                                          options: [.customDismissAction])
        case .missedCallCategory:
            return UNNotificationCategory(identifier: self.getIdentifier(),
                                          actions: [UserNotificationAction.callBack.action],
                                          intentIdentifiers: [],
                                          options: [.customDismissAction])
        }
    }
    
}
