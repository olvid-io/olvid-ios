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
import ObvTypes


/// Type used to return the notification content to publish by the app when inserting a `PersistedInvitation`.
///
/// The `ObvUserNotificationContentTypeForInvitation` full case also contains an optional `ObvProtocolMessage`.
/// This is typically used for the notification of a mediator invite: the notification extension publishes a notification by decrypting
/// a protocol message, obtaining an `ObvProtocolMessage` used to determine the notification content. When the app is launched, the protocol is executed, the app is notified, creates a
/// `PersistedInvitation`, which eventually triggers a call to this method that returns a notification content for the same mediator invite (but that has the advantage of providing accept and reject actions).
/// To avoid having two notifications for the same mediator invite, this method returns the `ObvProtocolMessage` that should correspond to the notification published by the notification extension, making
/// it possible for the caller (in practice, the `UserNotificationsCoordinator`) to search a remove the notification posted by the notification extension.
public enum ObvUserNotificationContentTypeForInvitation {
    case silent
    case full(content: UNNotificationContent, toRemove: ObvProtocolMessage?)
}
