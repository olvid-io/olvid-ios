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
import ObvSystemIcon
import ObvUserNotificationsTypes


extension ObvUserNotificationAction {
    
    private var title: String {
        switch self {
        case .accept: return String(localized: "NOTIFICATION_ACTION_TITLE_ACCEPT")
        case .decline: return String(localized: "NOTIFICATION_ACTION_TITLE_DECLINE")
        case .mute: return String(localized: "NOTIFICATION_ACTION_TITLE_MUTE")
        case .callBack: return String(localized: "NOTIFICATION_ACTION_TITLE_CALL_BACK")
        case .replyTo: return String(localized: "NOTIFICATION_ACTION_TITLE_REPLY_TO")
        case .sendMessage: return String(localized: "NOTIFICATION_ACTION_TITLE_SEND_MESSAGE")
        case .markAsRead: return String(localized: "NOTIFICATION_ACTION_TITLE_MARK_AS_READ")
        }
    }

    private var options: UNNotificationActionOptions {
        switch self {
        case .accept: return [.authenticationRequired]
        case .decline: return [.authenticationRequired, .destructive]
        case .mute: return [.authenticationRequired]
        case .callBack: return [.authenticationRequired, .foreground]
        case .replyTo: return [.authenticationRequired]
        case .sendMessage: return [.authenticationRequired]
        case .markAsRead: return [.authenticationRequired]
        }
    }

    private var icon: SystemIcon {
        switch self {
        case .accept: return .checkmark
        case .decline: return .multiply
        case .mute: return .moonZzzFill
        case .callBack: return .phoneFill
        case .replyTo: return .arrowshapeTurnUpLeft2
        case .sendMessage: return .arrowshapeTurnUpLeft2
        case .markAsRead: return .envelopeOpenFill
        }
    }

    private var textInput: (buttonTitle: String, placeholder: String)? {
        switch self {
        case .accept, .decline, .mute, .callBack, .markAsRead: return nil
        case .replyTo, .sendMessage:
            let buttonTitle = String(localized: "BUTTON_TITLE_SEND")
            return (buttonTitle, "Aa")
        }
    }

    var action: UNNotificationAction {
        if let (buttonTitle, placeholder) = textInput {
            return UNTextInputNotificationAction(identifier: rawValue, title: title, options: options, icon: icon, textInputButtonTitle: buttonTitle, textInputPlaceholder: placeholder)
        } else {
            return UNNotificationAction(identifier: rawValue, title: title, options: options, icon: icon)
        }
    }

}

extension UNNotificationAction {

    /// Convenience initializer allowing to specify a `SystemIcon` instead of a system image name.
    convenience init(identifier: String, title: String, options: UNNotificationActionOptions = [], icon: SystemIcon) {
        let actionIcon = UNNotificationActionIcon(systemImageName: icon.name)
        self.init(identifier: identifier, title: title, options: options, icon: actionIcon)
    }

}

extension UNTextInputNotificationAction {

    /// Convenience initializer allowing to specify a `SystemIcon` instead of a system image name.
    convenience init(identifier: String, title: String, options: UNNotificationActionOptions = [], icon: SystemIcon, textInputButtonTitle: String, textInputPlaceholder: String) {
        let actionIcon = UNNotificationActionIcon(systemImageName: icon.name)
        self.init(identifier: identifier, title: title, options: options, icon: actionIcon, textInputButtonTitle: textInputButtonTitle, textInputPlaceholder: textInputPlaceholder)
    }
}


fileprivate extension String {
    
    init(localized keyAndValue: String.LocalizationValue) {
        self.init(localized: keyAndValue, bundle: ObvUserNotificationsCreatorResources.bundle)
    }
    
}
