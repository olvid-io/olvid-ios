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
import ObvTypes
import ObvSettings
import ObvUserNotificationsSounds
import ObvUICoreDataStructs


// MARK: - Thread safe struct

extension PersistedDiscussionLocalConfiguration {

    public func toStructure() -> PersistedDiscussionLocalConfigurationStructure {
        let performInteractionDonation = self.performInteractionDonation ?? ObvMessengerSettings.Discussions.performInteractionDonation
        return .init(notificationSound: notificationSound,
                     performInteractionDonation: performInteractionDonation,
                     muteNotificationsEndDate: muteNotificationsEndDate,
                     mentionNotificationMode: mentionNotificationMode.forStruct)
    }

}


fileprivate extension DiscussionMentionNotificationMode {
    
    var forStruct: PersistedDiscussionLocalConfigurationStructure.DiscussionMentionNotificationMode {
        switch self {
        case .globalDefault: return .globalDefault
        case .neverNotifyWhenDiscussionIsMuted: return .neverNotifyWhenDiscussionIsMuted
        case .alwaysNotifyWhenMentionned: return .alwaysNotifyWhenMentionned
        }
    }
    
}
