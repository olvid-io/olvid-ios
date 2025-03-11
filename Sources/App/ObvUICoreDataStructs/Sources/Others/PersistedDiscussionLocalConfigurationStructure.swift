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
import ObvUserNotificationsSounds


public struct PersistedDiscussionLocalConfigurationStructure {

    public let notificationSound: NotificationSound?
    public let performInteractionDonation: Bool
    let muteNotificationsEndDate: Date?
    public let mentionNotificationMode: DiscussionMentionNotificationMode
    
    public var hasValidMuteNotificationsEndDate: Bool {
        guard let muteNotificationsEndDate else { return false }
        return muteNotificationsEndDate > Date.now
    }
    
    public init(notificationSound: NotificationSound?, performInteractionDonation: Bool, muteNotificationsEndDate: Date?, mentionNotificationMode: DiscussionMentionNotificationMode) {
        self.notificationSound = notificationSound
        self.performInteractionDonation = performInteractionDonation
        self.muteNotificationsEndDate = muteNotificationsEndDate
        self.mentionNotificationMode = mentionNotificationMode
    }

    
    public enum DiscussionMentionNotificationMode: CaseIterable, Hashable {
        /// Nothing specified, uses the default setting
        case globalDefault
        /// Never be notified when mentioned
        case neverNotifyWhenDiscussionIsMuted
        /// Always be notified when mentioned (even if the discussion is muted)
        case alwaysNotifyWhenMentionned
    }
}
