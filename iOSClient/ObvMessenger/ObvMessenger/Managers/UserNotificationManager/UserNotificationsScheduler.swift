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

        assert(notificationContent.userInfo[UserNotificationKeys.id] != nil, "You must call setThreadAndCategory on notification creation")
        
        let identifier = notificationId.getIdentifier()
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        let request = UNNotificationRequest(identifier: identifier, content: notificationContent, trigger: trigger)
        os_log("Adding user notification with identifier %{public}@", log: log, type: .info, identifier)
        notificationCenter.add(request)
        
    }

    static func filteredScheduleNotification(discussionKind: PersistedDiscussion.StructureKind, notificationId: ObvUserNotificationIdentifier, notificationContent: UNNotificationContent, notificationCenter: UNUserNotificationCenter) {
        guard !discussionKind.localConfiguration.shouldMuteNotifications else { return }

        scheduleNotification(notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter)
    }

    
    static func removeAllNotificationWithIdentifier(_ identifier: ObvUserNotificationIdentifier, notificationCenter: UNUserNotificationCenter) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier.getIdentifier()])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier.getIdentifier()])
    }

    // MARK: - Reactions Notifications Utils

    static func findAllReactionsNotificationRequestAddedByExtension(with identifier: String, in requests: [UNNotificationRequest]) -> [String] {
        var identifiers = [String]()
        for request in requests {
            guard request.content.userInfo[UserNotificationKeys.id] as? Int == ObvUserNotificationID.newReaction.rawValue else { continue }
            guard let reactionIdentifierForNotification = request.content.userInfo[UserNotificationKeys.reactionIdentifierForNotification] as? String else { assertionFailure(); continue }
            guard reactionIdentifierForNotification != request.identifier else {
                // The request identifier is equal to the reactionIdentifierForNotification, it's meen that this extension was added by the app and not by the extension.
                continue
            }
            if reactionIdentifierForNotification == identifier {
                identifiers += [request.identifier]
            }
        }
        return identifiers
    }

    static func removeReactionNotificationsAddedByExtension(with identifier: ObvUserNotificationIdentifier, notificationCenter: UNUserNotificationCenter) async {

        // If the reaction was scheduled from the notification extension, the identifier in request is an UUID. We need to read the identifier from the reactionIdentifierForNotification in userInfo.

        let pendingReactionIdentifiersForNotification = findAllReactionsNotificationRequestAddedByExtension(with: identifier.getIdentifier(), in: await notificationCenter.pendingNotificationRequests())
        os_log("😀 Remove %{public}@ pending notification(s) added by the notification extension", log: log, type: .info, String(pendingReactionIdentifiersForNotification.count))
        notificationCenter.removePendingNotificationRequests(withIdentifiers: pendingReactionIdentifiersForNotification)

        let deliveredReactionIdentifiersForNotification = findAllReactionsNotificationRequestAddedByExtension(with: identifier.getIdentifier(), in: await notificationCenter.deliveredNotifications().map { $0.request})
        os_log("😀 Remove %{public}@ delivered notification(s) added by the notification extension", log: log,
               type: .info, String(deliveredReactionIdentifiersForNotification.count))
        notificationCenter.removeDeliveredNotifications(withIdentifiers: deliveredReactionIdentifiersForNotification)
    }

    static func getAllReactionsTimestampAddedByExtension(with identifier: ObvUserNotificationIdentifier, notificationCenter: UNUserNotificationCenter) -> [Date] {
        var timestamps = [Date]()
        func update(_ requests: [UNNotificationRequest]) {
            for request in requests {
                guard request.content.userInfo[UserNotificationKeys.id] as? Int == ObvUserNotificationID.newReaction.rawValue else { continue }
                guard let timestamp = request.content.userInfo[UserNotificationKeys.reactionTimestamp] as? Date else { assertionFailure(); continue }
                guard let reactionIdentifierForNotification = request.content.userInfo[UserNotificationKeys.reactionIdentifierForNotification] as? String else { assertionFailure(); continue }
                guard reactionIdentifierForNotification != request.identifier else {
                    // The request identifier is equal to the reactionIdentifierForNotification, it's meen that this extension was added by the app and not by the extension.
                    continue
                }
                guard identifier.getIdentifier() == reactionIdentifierForNotification else { continue }
                timestamps += [timestamp]
            }
        }
        let group = DispatchGroup()
        do {
            group.enter()
            notificationCenter.getPendingNotificationRequests { pendingNotificationsRequests in
                update(pendingNotificationsRequests)
                group.leave()
            }
        }
        do {
            group.enter()
            notificationCenter.getDeliveredNotifications { deliveredNotifications in
                let deliveredNotificationsRequests = deliveredNotifications.map { $0.request }
                update(deliveredNotificationsRequests)
                group.leave()
            }
        }
        group.wait()
        return timestamps
    }
}
