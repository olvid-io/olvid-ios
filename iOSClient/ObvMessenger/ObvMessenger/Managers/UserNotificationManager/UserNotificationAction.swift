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
import ObvUI
import UserNotifications


enum UserNotificationAction: String {
    case accept = "ACCEPT_ACTION"
    case decline = "DECLINE_ACTION"
    case mute = "MUTE_ACTION"
    case callBack = "CALL_BACK_ACTION"
    case replyTo = "REPLY_TO_ACTION"
    case sendMessage = "SEND_MESSAGE_ACTION"
    case markAsRead = "MARK_AS_READ_ACTION"
}

extension UserNotificationAction {
    private var title: String {
        switch self {
        case .accept: return CommonString.Word.Accept
        case .decline: return CommonString.Word.Decline
        case .mute: return CommonString.Word.Mute
        case .callBack: return CommonString.Title.callBack
        case .replyTo: return CommonString.Word.Reply
        case .sendMessage: return CommonString.Title.sendMessage
        case .markAsRead: return CommonString.Title.markAsRead
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
        case .mute: return ObvMessengerConstants.muteIcon
        case .callBack: return .phoneFill
        case .replyTo: return .arrowshapeTurnUpLeft2
        case .sendMessage: return .arrowshapeTurnUpLeft2
        case .markAsRead: return .envelopeOpenFill
        }
    }

    private var textInput: (buttonTitle: String, placeholder: String)? {
        switch self {
        case .accept, .decline, .mute, .callBack, .markAsRead: return nil
        case .replyTo, .sendMessage: return (CommonString.Word.Send, "Aa")
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

    convenience init(identifier: String, title: String, options: UNNotificationActionOptions = [], icon: SystemIcon) {
        if #available(iOS 15.0, *) {
            let actionIcon = UNNotificationActionIcon(systemImageName: icon.systemName)
            self.init(identifier: identifier, title: title, options: options, icon: actionIcon)
        } else {
            self.init(identifier: identifier, title: title, options: options)
        }
    }

}

extension UNTextInputNotificationAction {

    convenience init(identifier: String, title: String, options: UNNotificationActionOptions = [], icon: SystemIcon, textInputButtonTitle: String, textInputPlaceholder: String) {
        if #available(iOS 15.0, *) {
            let actionIcon = UNNotificationActionIcon(systemImageName: icon.systemName)
            self.init(identifier: identifier, title: title, options: options, icon: actionIcon, textInputButtonTitle: textInputButtonTitle, textInputPlaceholder: textInputPlaceholder)
        } else {
            self.init(identifier: identifier, title: title, options: options, textInputButtonTitle: textInputButtonTitle, textInputPlaceholder: textInputPlaceholder)
        }
    }
}
