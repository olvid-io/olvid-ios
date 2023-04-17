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

extension GlobalSettingsBackupItem {

    func updateExistingObvMessengerSettings() {

        // Contacts and groups

        if let value = self.autoAcceptGroupInviteFrom {
            ObvMessengerSettings.ContactsAndGroups.autoAcceptGroupInviteFrom = value
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
        if let value = self.useOldDiscussionInterface {
            ObvMessengerSettings.Interface.useOldDiscussionInterface = value
        }

        // Discussions

        if let value = self.sendReadReceipt {
            ObvMessengerSettings.Discussions.doSendReadReceipt = value
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

        // Privacy

        if let value = self.hideNotificationContent {
            ObvMessengerSettings.Privacy.hideNotificationContent = value
        }

        // VoIP

        if let value = self.isCallKitEnabled {
            ObvMessengerSettings.VoIP.isCallKitEnabled = value
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
