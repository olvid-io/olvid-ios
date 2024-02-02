/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvSettings


public extension GlobalSettingsBackupItem {

    func updateExistingObvMessengerSettings() {

        // Contacts and groups

        if let value = self.autoAcceptGroupInviteFrom {
            ObvMessengerSettings.ContactsAndGroups.setAutoAcceptGroupInviteFrom(to: value, changeMadeFromAnotherOwnedDevice: false, ownedCryptoId: nil)
        }

        // Downloads

        if let value = self.maxAttachmentSizeForAutomaticDownload {
            ObvMessengerSettings.Downloads.maxAttachmentSizeForAutomaticDownload = value
        }

        // Interface

        if let value = self.identityColorStyle {
            ObvMessengerSettings.Interface.identityColorStyle = value
        }
        if let value = self.contactsSortOrder {
            ObvMessengerSettings.Interface.contactsSortOrder = value
        }

        // Discussions

        if let value = self.sendReadReceipt {
            ObvMessengerSettings.Discussions.setDoSendReadReceipt(to: value, changeMadeFromAnotherOwnedDevice: false, ownedCryptoId: nil)
        }
        if let value = self.doFetchContentRichURLsMetadata {
            ObvMessengerSettings.Discussions.doFetchContentRichURLsMetadata = value
        }
        if let value = self.readOnce {
            ObvMessengerSettings.Discussions.readOnce = value
        }
        if let value = self.visibilityDuration {
            ObvMessengerSettings.Discussions.visibilityDuration = value
        }
        if let value = self.existenceDuration {
            ObvMessengerSettings.Discussions.existenceDuration = value
        }
        if let value = self.countBasedRetentionPolicy, value > 0 {
            ObvMessengerSettings.Discussions.countBasedRetentionPolicyIsActive = true
            ObvMessengerSettings.Discussions.countBasedRetentionPolicy = value
        }
        if let value = self.timeBasedRetentionPolicy {
            ObvMessengerSettings.Discussions.timeBasedRetentionPolicy = value
        }
        if let value = self.autoRead {
            ObvMessengerSettings.Discussions.autoRead = value
        }
        if let value = self.retainWipedOutboundMessages {
            ObvMessengerSettings.Discussions.retainWipedOutboundMessages = value
        }
        if let value = self.performInteractionDonation {
            ObvMessengerSettings.Discussions.performInteractionDonation = value
        }

        if alwaysNotifyWhenMentionnedEvenInMutedDiscussion {
            ObvMessengerSettings.Discussions.notificationOptions.insert(.alwaysNotifyWhenMentionnedEvenInMutedDiscussion)
        } else {
            ObvMessengerSettings.Discussions.notificationOptions.remove(.alwaysNotifyWhenMentionnedEvenInMutedDiscussion)
        }

        // Privacy

        if let value = self.hideNotificationContent {
            ObvMessengerSettings.Privacy.hideNotificationContent = value
        }
        if let value = self.hiddenProfileClosePolicy {
            ObvMessengerSettings.Privacy.hiddenProfileClosePolicy = value
        }
        if let value = self.timeIntervalForBackgroundHiddenProfileClosePolicy {
            ObvMessengerSettings.Privacy.timeIntervalForBackgroundHiddenProfileClosePolicy = value
        }

        // Advanced

        if let value = self.allowCustomKeyboards {
            ObvMessengerSettings.Advanced.allowCustomKeyboards = value
        }

        // BetaConfiguration

        if let value = self.showBetaSettings {
            ObvMessengerSettings.BetaConfiguration.showBetaSettings = value
        }

        // Emoji
        
        if let value = self.preferredEmojisList {
            ObvMessengerSettings.Emoji.preferredEmojisList = value
        }



    }

}
