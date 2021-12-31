/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

enum UserNotificationAction: String {
    case accept = "ACCEPT_ACTION"
    case decline = "DECLINE_ACTION"
    case mute = "MUTE_ACTION"
    case callBack = "CALL_BACK_ACTION"
}

extension UserNotificationAction {
    private var title: String {
        switch self {
        case .accept: return CommonString.Word.Accept
        case .decline: return CommonString.Word.Decline
        case .mute: return CommonString.Word.Mute
        case .callBack: return CommonString.Title.callBack
        }
    }

    private var options: UNNotificationActionOptions {
        switch self {
        case .accept: return [.authenticationRequired]
        case .decline: return [.authenticationRequired, .destructive]
        case .mute: return [.authenticationRequired]
        case .callBack: return [.authenticationRequired, .foreground]
        }
    }

    private var icon: ObvSystemIcon {
        switch self {
        case .accept: return .checkmark
        case .decline: return .multiply
        case .mute: return ObvMessengerConstants.muteIcon
        case .callBack: return .phoneFill
        }
    }

    var action: UNNotificationAction {
        if #available(iOS 15.0, *) {
            let actionIcon = UNNotificationActionIcon(systemImageName: icon.systemName)
            return UNNotificationAction(identifier: rawValue, title: title, options: options, icon: actionIcon)
        } else {
            return UNNotificationAction(identifier: rawValue, title: title, options: options)
        }
    }

}
