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

extension PersistedDiscussionConfigurationBackupItem {

    func updateExistingInstance(_ configuration: PersistedDiscussionLocalConfiguration) {

        _ = configuration.setDoSendReadReceipt(to: self.sendReadReceipt)
        if let muteNotificationsEndDate = self.muteNotificationsEndDate {
            configuration.setMuteNotificationsEndDate(with: muteNotificationsEndDate)
        }
        configuration.autoRead = self.autoRead
        configuration.retainWipedOutboundMessages = self.retainWipedOutboundMessages
        configuration.countBasedRetentionIsActive = self.countBasedRetentionIsActive
        configuration.countBasedRetention = self.countBasedRetention
        if let timeBasedRetention = self.timeBasedRetention {
            let rawValue = Int(timeBasedRetention)
            if rawValue == 0 {
                configuration.timeBasedRetention = .none
            } else {
                configuration.timeBasedRetention = DurationOptionAltOverride(rawValue: rawValue) ?? .useAppDefault
            }
        }
        configuration.performInteractionDonation = self.performInteractionDonation
        configuration.update(with: .mentionNotificationMode(mentionNotificationMode))
    }

}
