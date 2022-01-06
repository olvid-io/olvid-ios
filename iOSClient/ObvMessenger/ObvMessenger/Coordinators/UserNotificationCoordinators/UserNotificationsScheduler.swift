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
import os.log

final class UserNotificationsScheduler {
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "UserNotificationsScheduler")

    static func scheduleNotification(notificationId: ObvUserNotificationIdentifier, notificationContent: UNNotificationContent, notificationCenter: UNUserNotificationCenter) {
        
        let identifier = notificationId.getIdentifier()
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        let request = UNNotificationRequest(identifier: identifier, content: notificationContent, trigger: trigger)
        os_log("Adding user notification with identifier %{public}@", log: log, type: .info, identifier)
        notificationCenter.add(request)
        
    }

    static func filteredScheduleNotification(discussion: PersistedDiscussion, notificationId: ObvUserNotificationIdentifier, notificationContent: UNNotificationContent, notificationCenter: UNUserNotificationCenter) {
        guard !discussion.shouldMuteNotifications else { return }

        scheduleNotification(notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter)
    }

    
    static func removeAllNotificationWithIdentifier(_ identifier: ObvUserNotificationIdentifier, notificationCenter: UNUserNotificationCenter) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier.getIdentifier()])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier.getIdentifier()])
    }
    
}
