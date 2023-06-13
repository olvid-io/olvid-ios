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
import ObvTypes
import SwiftUI
import ObvCrypto


public struct AppBackupItem: Codable, Hashable {
    
    public let globalSettings: GlobalSettingsBackupItem
    public let ownedIdentities: [PersistedObvOwnedIdentityBackupItem]?
    
    enum CodingKeys: String, CodingKey {
        case ownedIdentities = "owned_identities"
        case globalSettings = "settings"
    }
    
    public init(ownedIdentities: [PersistedObvOwnedIdentity]) {
        self.globalSettings = GlobalSettingsBackupItem()
        let ownedIdentitiesBackupItems = ownedIdentities.map { $0.backupItem }.filter({ !$0.isEmpty })
        self.ownedIdentities = ownedIdentitiesBackupItems.isEmpty ? nil : ownedIdentitiesBackupItems
    }

}



public struct PersistedObvOwnedIdentityBackupItem: Codable, Hashable {
    
    let identity: Data
    let customDisplayName: String?
    let hiddenProfileHash: Data?
    let hiddenProfileSalt: Data?
    let contacts: [PersistedObvContactIdentityBackupItem]?
    let groupsV1: [PersistedContactGroupBackupItem]?
    let groupsV2: [PersistedGroupV2BackupItem]?
    
    var isEmpty: Bool {
        return contacts == nil && groupsV1 == nil && groupsV2 == nil && customDisplayName == nil && hiddenProfileHash == nil && hiddenProfileSalt == nil
    }

    enum CodingKeys: String, CodingKey {
        case identity = "owned_identity"
        case customDisplayName = "custom_name"
        case hiddenProfileHash = "unlock_password"
        case hiddenProfileSalt = "unlock_salt"
        case contacts = "contacts"
        case groupsV1 = "groups"
        case groupsV2 = "groups2"
    }

    static func makeError(message: String) -> Error { NSError(domain: "PersistedObvOwnedIdentityBackupItem", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

}



struct PersistedObvContactIdentityBackupItem: Codable, Hashable {
    
    let identity: Data
    let customDisplayName: String?
    let note: String?
    let discussionConfigurationBackupItem: PersistedDiscussionConfigurationBackupItem?
    
    var isEmpty: Bool {
        customDisplayName == nil && note == nil && discussionConfigurationBackupItem == nil
    }
    
    enum CodingKeys: String, CodingKey {
        case identity = "contact_identity"
        case customDisplayName = "custom_name"
        case note = "personal_note"
        case discussionConfigurationBackupItem = "discussion_customization"
    }

    static func makeError(message: String) -> Error { NSError(domain: "PersistedObvContactIdentityBackupItem", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

}



struct PersistedContactGroupBackupItem: Codable, Hashable {
    
    let groupUid: UID
    let groupOwnerIdentity: Data
    let discussionConfigurationBackupItem: PersistedDiscussionConfigurationBackupItem?

    
    var isEmpty: Bool {
        return discussionConfigurationBackupItem == nil
    }

    
    enum CodingKeys: String, CodingKey {
        case groupUid = "group_uid"
        case groupOwnerIdentity = "group_owner_identity"
        case discussionConfigurationBackupItem = "discussion_customization"
    }
    
    
    init(groupUid: UID, groupOwnerIdentity: Data, discussionConfigurationBackupItem: PersistedDiscussionConfigurationBackupItem?) {
        self.groupUid = groupUid
        self.groupOwnerIdentity = groupOwnerIdentity
        self.discussionConfigurationBackupItem = discussionConfigurationBackupItem
    }
    
    func encode(to encoder: Encoder) throws {
        
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(groupUid.raw, forKey: .groupUid)
        try container.encode(groupOwnerIdentity, forKey: .groupOwnerIdentity)
        try container.encodeIfPresent(discussionConfigurationBackupItem, forKey: .discussionConfigurationBackupItem)

    }
    
    
    init(from decoder: Decoder) throws {

        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        guard let groupUid = try values.decode(Data.self, forKey: .groupUid).toUID else { throw PersistedContactGroupBackupItem.makeError(message: "Could not parse groupUid") }
        self.groupUid = groupUid
        self.groupOwnerIdentity = try values.decode(Data.self, forKey: .groupOwnerIdentity)
        self.discussionConfigurationBackupItem = try values.decodeIfPresent(PersistedDiscussionConfigurationBackupItem.self, forKey: .discussionConfigurationBackupItem)
        
    }
    
    
    private static func makeError(message: String) -> Error { NSError(domain: "PersistedContactGroupBackupItem", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

}


struct PersistedGroupV2BackupItem: Codable, Hashable {
    
    let groupIdentifier: Data
    let customName: String?
    let discussionConfigurationBackupItem: PersistedDiscussionConfigurationBackupItem?

    enum CodingKeys: String, CodingKey {
        case groupIdentifier = "group_identifier"
        case customName = "custom_name"
        case discussionConfigurationBackupItem = "discussion_customization"
    }

    init(groupIdentifier: Data, customName: String?, discussionConfigurationBackupItem: PersistedDiscussionConfigurationBackupItem?) {
        self.groupIdentifier = groupIdentifier
        self.customName = customName
        self.discussionConfigurationBackupItem = discussionConfigurationBackupItem
    }
    
    func encode(to encoder: Encoder) throws {
        
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(groupIdentifier, forKey: .groupIdentifier)
        try container.encodeIfPresent(customName, forKey: .customName)
        try container.encodeIfPresent(discussionConfigurationBackupItem, forKey: .discussionConfigurationBackupItem)

    }

    init(from decoder: Decoder) throws {

        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        self.groupIdentifier = try values.decode(Data.self, forKey: .groupIdentifier)
        self.customName = try values.decodeIfPresent(String.self, forKey: .customName)
        self.discussionConfigurationBackupItem = try values.decodeIfPresent(PersistedDiscussionConfigurationBackupItem.self, forKey: .discussionConfigurationBackupItem)
        
    }

}



struct PersistedDiscussionConfigurationBackupItem: Codable, Hashable {
    
    // Local configuration
    
    let sendReadReceipt: Bool?
    let muteNotifications: Bool?
    let muteNotificationsEndDate: Date?
    /// The notification mode associated to this discussion
    /// Derived from ``PersistedDiscussionLocalConfiguration/mentionNotificationMode``
    let mentionNotificationMode: DiscussionMentionNotificationMode
    let autoRead: Bool?
    let retainWipedOutboundMessages: Bool?
    let countBasedRetentionIsActive: Bool?
    let countBasedRetention: Int?
    let timeBasedRetention: TimeInterval?
    let doFetchContentRichURLsMetadata: ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice?
    let performInteractionDonation: Bool?
    
    // Shared configuration
    
    let sharedSettingsVersion: Int?
    let existenceDuration: TimeInterval?
    let visibilityDuration: TimeInterval?
    let readOnce: Bool?
    
    
    var isEmpty: Bool {
        sendReadReceipt == nil &&
        muteNotifications == nil &&
        muteNotificationsEndDate == nil &&
        autoRead == nil &&
        retainWipedOutboundMessages == nil &&
        countBasedRetention == nil &&
        countBasedRetentionIsActive == nil &&
        timeBasedRetention == nil &&
        (sharedSettingsVersion == nil || existenceDuration == nil && visibilityDuration == nil && readOnce == nil) &&
        doFetchContentRichURLsMetadata == nil &&
        performInteractionDonation == nil &&
        mentionNotificationMode == .globalDefault
    }
    

    enum CodingKeys: String, CodingKey {
        case sendReadReceipt = "send_read_receipt"
        case muteNotifications = "mute_notifications"
        case muteNotificationsEndDate = "mute_notification_timestamp"
        case mentionNotificationMode = "mention_notification_mode"
        case autoRead = "auto_open_limited_visibility"
        case retainWipedOutboundMessages = "retain_wiped_outbound"
        case countBasedRetentionIsActive = "retention_count_is_active"
        case countBasedRetentionAndroid = "retention_count"
        case countBasedRetention = "retention_count_ios"
        case timeBasedRetention = "retention_duration"
        case sharedSettingsVersion = "shared_settings_version"
        case existenceDuration = "settings_existence_duration"
        case visibilityDuration = "settings_visibility_duration"
        case readOnce = "settings_read_once"
        case doFetchContentRichURLsMetadata = "do_fetch_content_rich_urls_metadata"
        case backupSourcePlatform = "backup_source_platform"
        case performInteractionDonation = "perform_interaction_donation"
    }

    
    init(local: PersistedDiscussionLocalConfiguration, shared: PersistedDiscussionSharedConfiguration) {
        
        self.sendReadReceipt = local.doSendReadReceipt
        self.muteNotifications = local.hasNotificationsMuted ? true : nil
        self.muteNotificationsEndDate = local.currentMuteNotificationsEndDate
        self.mentionNotificationMode = local.mentionNotificationMode
        self.autoRead = local.autoRead
        self.retainWipedOutboundMessages = local.retainWipedOutboundMessages
        self.countBasedRetentionIsActive = local.countBasedRetentionIsActive
        self.countBasedRetention = local.countBasedRetention
        switch local.timeBasedRetention {
        case .useAppDefault:
            self.timeBasedRetention = nil
        case .none:
            self.timeBasedRetention = 0 // 0 means keep everything
        default:
            self.timeBasedRetention = local.timeBasedRetention.timeInterval
        }
        self.doFetchContentRichURLsMetadata = local.doFetchContentRichURLsMetadata
        self.performInteractionDonation = local.performInteractionDonation

        self.sharedSettingsVersion = shared.version == 0 ? nil : shared.version
        self.existenceDuration = shared.existenceDuration
        self.visibilityDuration = shared.visibilityDuration
        self.readOnce = shared.readOnce ? true : nil
        
    }
    
    
    func encode(to encoder: Encoder) throws {
        
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(sendReadReceipt, forKey: .sendReadReceipt)
        try container.encodeIfPresent(muteNotifications, forKey: .muteNotifications)
        try container.encodeIfPresent(muteNotificationsEndDate?.epochInMs, forKey: .muteNotificationsEndDate)
        try container.encode(mentionNotificationMode, forKey: .mentionNotificationMode)
        try container.encodeIfPresent(autoRead, forKey: .autoRead)
        try container.encodeIfPresent(retainWipedOutboundMessages, forKey: .retainWipedOutboundMessages)
        
        try container.encodeIfPresent(countBasedRetentionIsActive, forKey: .countBasedRetentionIsActive)
        try container.encodeIfPresent(countBasedRetention, forKey: .countBasedRetention)

        // Specific value to maintain compatibility with Android
        let countBasedRetentionAndroid: Int?
        if let countBasedRetentionIsActive {
            countBasedRetentionAndroid = countBasedRetentionIsActive ? (countBasedRetention ?? ObvMessengerSettings.Discussions.countBasedRetentionPolicy) : 0 // 0 means keep everything
        } else if ObvMessengerSettings.Discussions.countBasedRetentionPolicyIsActive {
            countBasedRetentionAndroid = countBasedRetention
        } else {
            countBasedRetentionAndroid = nil
        }
        try container.encodeIfPresent(countBasedRetentionAndroid, forKey: .countBasedRetentionAndroid)
        
        try container.encodeIfPresent(timeBasedRetention?.toSeconds, forKey: .timeBasedRetention)
        try container.encodeIfPresent(doFetchContentRichURLsMetadata?.rawValue, forKey: .doFetchContentRichURLsMetadata)
        try container.encodeIfPresent(performInteractionDonation, forKey: .performInteractionDonation)

        try container.encodeIfPresent(sharedSettingsVersion, forKey: .sharedSettingsVersion)
        try container.encodeIfPresent(existenceDuration?.toSeconds, forKey: .existenceDuration)
        try container.encodeIfPresent(visibilityDuration?.toSeconds, forKey: .visibilityDuration)
        try container.encodeIfPresent(readOnce, forKey: .readOnce)
        
    }
    

    init(from decoder: Decoder) throws {

        let values = try decoder.container(keyedBy: CodingKeys.self)

        self.sendReadReceipt = try values.decodeIfPresent(Bool.self, forKey: .sendReadReceipt)
        self.muteNotifications = try values.decodeIfPresent(Bool.self, forKey: .muteNotifications)
        if let raw = try values.decodeIfPresent(Int64.self, forKey: .muteNotificationsEndDate) {
            self.muteNotificationsEndDate = Date(epochInMs: raw)
        } else {
            self.muteNotificationsEndDate = nil
        }

        do {
            if let value = try values.decodeIfPresent(DiscussionMentionNotificationMode.self, forKey: .mentionNotificationMode) {
                mentionNotificationMode = value
            } else { // fallback to ``DiscussionMentionNotificationMode/default`` if we don't have the value defined
                mentionNotificationMode = .globalDefault
            }
        } catch {
            assertionFailure("Could not decode the DiscussionMentionNotificationMode: \(error.localizedDescription)")
            mentionNotificationMode = .globalDefault
        }

        self.autoRead = try values.decodeIfPresent(Bool.self, forKey: .autoRead)
        self.retainWipedOutboundMessages = try values.decodeIfPresent(Bool.self, forKey: .retainWipedOutboundMessages)

        // Complex part concerning countBasedRetention and countBasedRetentionIsActive
        
        let countBasedRetentionIsActive = try values.decodeIfPresent(Bool.self, forKey: .countBasedRetentionIsActive)
        let countBasedRetention = try values.decodeIfPresent(Int.self, forKey: .countBasedRetention)
        if countBasedRetentionIsActive == nil && countBasedRetention == nil {
            let countBasedRetention = try values.decodeIfPresent(Int.self, forKey: .countBasedRetentionAndroid)
            switch countBasedRetention {
            case .none:
                self.countBasedRetention = nil
                self.countBasedRetentionIsActive = nil
            case let .some(x) where x <= 0:
                self.countBasedRetention = nil
                self.countBasedRetentionIsActive = false
            default:
                self.countBasedRetention = countBasedRetention
                self.countBasedRetentionIsActive = true
            }
        } else {
            self.countBasedRetention = countBasedRetention
            self.countBasedRetentionIsActive = countBasedRetentionIsActive
        }
        
        self.timeBasedRetention = (try values.decodeIfPresent(Int.self, forKey: .timeBasedRetention))?.secondsToTimeInterval
        if let raw = try values.decodeIfPresent(Int.self, forKey: .doFetchContentRichURLsMetadata) {
            self.doFetchContentRichURLsMetadata = ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice(rawValue: raw)
        } else {
            self.doFetchContentRichURLsMetadata = nil
        }
        self.performInteractionDonation = try values.decodeIfPresent(Bool.self, forKey: .performInteractionDonation)

        self.sharedSettingsVersion = try values.decodeIfPresent(Int.self, forKey: .sharedSettingsVersion)
        self.existenceDuration = (try values.decodeIfPresent(Int.self, forKey: .existenceDuration))?.secondsToTimeInterval
        self.visibilityDuration = (try values.decodeIfPresent(Int.self, forKey: .visibilityDuration))?.secondsToTimeInterval
        self.readOnce = (try values.decodeIfPresent(Bool.self, forKey: .readOnce))

    }
    
}


public struct GlobalSettingsBackupItem: Codable, Hashable {
    
    // ContactsAndGroups

    let autoAcceptGroupInviteFrom: ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom?

    // Downloads

    let maxAttachmentSizeForAutomaticDownload: Int?

    // Interface
    
    let identityColorStyle: IdentityColorStyle?
    let contactsSortOrder: ContactsSortOrder?
    let useOldDiscussionInterface: Bool?

    // Discussions
    
    let sendReadReceipt: Bool?
    let doFetchContentRichURLsMetadata: ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice?
    let readOnce: Bool?
    let visibilityDuration: DurationOption?
    let existenceDuration: DurationOption?
    let countBasedRetentionPolicy: Int?
    let timeBasedRetentionPolicy: DurationOptionAlt?
    let autoRead: Bool?
    let retainWipedOutboundMessages: Bool?
    let performInteractionDonation: Bool?
    let alwaysNotifyWhenMentionnedEvenInMutedDiscussion: Bool

    // Privacy
    
    let hideNotificationContent: ObvMessengerSettings.Privacy.HideNotificationContentType?
    let hiddenProfileClosePolicy: ObvMessengerSettings.Privacy.HiddenProfileClosePolicy?
    let timeIntervalForBackgroundHiddenProfileClosePolicy: ObvMessengerSettings.Privacy.TimeIntervalForBackgroundHiddenProfileClosePolicy?

    // VoIP
    
    let isCallKitEnabled: Bool?
    
    // Advanced
    
    let allowCustomKeyboards: Bool?
    
    // BetaConfiguration
    
    let showBetaSettings: Bool?

    // Emoji

    let preferredEmojisList: [String]?

    var isEmpty: Bool {
        false // We always want to attach global configurations to the app backup data
    }
    
    enum CodingKeys: String, CodingKey {
        case maxAttachmentSizeForAutomaticDownload = "auto_download_size"
        case identityColorStyle = "identity_color_style_ios"
        case contactsSortOrder = "contact_sort_last_name"
        case useOldDiscussionInterface = "use_old_discussion_interface_ios"
        case sendReadReceipt = "send_read_receipt"
        case doFetchContentRichURLsMetadata = "do_fetch_content_rich_urls_metadata_ios"
        case readOnce = "default_read_once"
        case visibilityDuration = "default_visibility_duration"
        case existenceDuration = "default_existence_duration"
        case countBasedRetentionPolicy = "default_retention_count"
        case timeBasedRetentionPolicy = "default_retention_duration"
        case autoRead = "auto_open_limited_visibility"
        case retainWipedOutboundMessages = "retain_wiped_outbound"
        case hideNotificationContent = "hide_notification_contents_ios"
        case hideNotificationContentAndroid = "hide_notification_contents"
        case allowCustomKeyboards = "allow_custom_keyboards"
        case showBetaSettings = "beta"
        case isCallKitEnabled = "is_call_kit_enabled"
        case autoAcceptGroupInviteFrom = "auto_join_groups"
        case preferredEmojisList = "preferred_reactions"
        case performInteractionDonation = "perform_interaction_donation"
        case hiddenProfileClosePolicy = "hidden_profile_policy"
        case timeIntervalForBackgroundHiddenProfileClosePolicy = "hidden_profile_background_grace"
        case alwaysNotifyWhenMentionnedEvenInMutedDiscussion = "always_notify_when_mentionned_even_in_muted_discussion"
    }

    private var hideNotificationContentAndroid: Bool? {
        switch self.hideNotificationContent {
        case .none:
            return nil
        case .no:
            return false
        case .completely, .partially:
            return true
        }
    }
    
    init() {
        self.maxAttachmentSizeForAutomaticDownload = ObvMessengerSettings.Downloads.maxAttachmentSizeForAutomaticDownload
        self.identityColorStyle = ObvMessengerSettings.Interface.identityColorStyle
        self.contactsSortOrder = ObvMessengerSettings.Interface.contactsSortOrder
        self.useOldDiscussionInterface = ObvMessengerSettings.Interface.useOldDiscussionInterface
        self.sendReadReceipt = ObvMessengerSettings.Discussions.doSendReadReceipt
        self.doFetchContentRichURLsMetadata = ObvMessengerSettings.Discussions.doFetchContentRichURLsMetadata
        self.readOnce = ObvMessengerSettings.Discussions.readOnce
        self.visibilityDuration = ObvMessengerSettings.Discussions.visibilityDuration
        self.existenceDuration = ObvMessengerSettings.Discussions.existenceDuration
        self.countBasedRetentionPolicy = ObvMessengerSettings.Discussions.countBasedRetentionPolicyIsActive ? ObvMessengerSettings.Discussions.countBasedRetentionPolicy : nil
        self.timeBasedRetentionPolicy = ObvMessengerSettings.Discussions.timeBasedRetentionPolicy
        self.autoRead = ObvMessengerSettings.Discussions.autoRead
        self.retainWipedOutboundMessages = ObvMessengerSettings.Discussions.retainWipedOutboundMessages
        self.performInteractionDonation = ObvMessengerSettings.Discussions.performInteractionDonation
        self.hideNotificationContent = ObvMessengerSettings.Privacy.hideNotificationContent
        self.allowCustomKeyboards = ObvMessengerSettings.Advanced.allowCustomKeyboards
        self.showBetaSettings = ObvMessengerSettings.BetaConfiguration.showBetaSettings
        self.isCallKitEnabled = ObvMessengerSettings.VoIP.isCallKitEnabled
        self.autoAcceptGroupInviteFrom = ObvMessengerSettings.ContactsAndGroups.autoAcceptGroupInviteFrom
        self.preferredEmojisList = ObvMessengerSettings.Emoji.preferredEmojisList
        self.hiddenProfileClosePolicy = ObvMessengerSettings.Privacy.hiddenProfileClosePolicy
        self.timeIntervalForBackgroundHiddenProfileClosePolicy = ObvMessengerSettings.Privacy.timeIntervalForBackgroundHiddenProfileClosePolicy
        self.alwaysNotifyWhenMentionnedEvenInMutedDiscussion = ObvMessengerSettings.Discussions.notificationOptions.contains(.alwaysNotifyWhenMentionnedEvenInMutedDiscussion)
    }
    
    public func encode(to encoder: Encoder) throws {
        
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(maxAttachmentSizeForAutomaticDownload, forKey: .maxAttachmentSizeForAutomaticDownload)
        try container.encodeIfPresent(identityColorStyle?.rawValue, forKey: .identityColorStyle)
        try container.encodeIfPresent(contactsSortOrder == .byLastName, forKey: .contactsSortOrder)
        try container.encodeIfPresent(useOldDiscussionInterface, forKey: .useOldDiscussionInterface)
        try container.encodeIfPresent(sendReadReceipt, forKey: .sendReadReceipt)
        try container.encodeIfPresent(doFetchContentRichURLsMetadata?.rawValue, forKey: .doFetchContentRichURLsMetadata)
        try container.encodeIfPresent(readOnce, forKey: .readOnce)
        try container.encodeIfPresent(visibilityDuration?.timeInterval?.toSeconds ?? 0, forKey: .visibilityDuration)
        try container.encodeIfPresent(existenceDuration?.timeInterval?.toSeconds ?? 0, forKey: .existenceDuration)
        try container.encodeIfPresent(countBasedRetentionPolicy, forKey: .countBasedRetentionPolicy)
        try container.encodeIfPresent(timeBasedRetentionPolicy?.timeInterval?.toSeconds, forKey: .timeBasedRetentionPolicy)
        try container.encodeIfPresent(autoRead, forKey: .autoRead)
        try container.encodeIfPresent(retainWipedOutboundMessages, forKey: .retainWipedOutboundMessages)
        try container.encodeIfPresent(hideNotificationContent?.rawValue, forKey: .hideNotificationContent)
        try container.encodeIfPresent(hideNotificationContentAndroid, forKey: .hideNotificationContentAndroid)
        try container.encodeIfPresent(allowCustomKeyboards, forKey: .allowCustomKeyboards)
        try container.encodeIfPresent(showBetaSettings, forKey: .showBetaSettings)
        try container.encodeIfPresent(isCallKitEnabled, forKey: .isCallKitEnabled)
        try container.encodeIfPresent(autoAcceptGroupInviteFrom?.rawValue, forKey: .autoAcceptGroupInviteFrom)
        try container.encodeIfPresent(preferredEmojisList, forKey: .preferredEmojisList)
        try container.encodeIfPresent(performInteractionDonation, forKey: .performInteractionDonation)
        try container.encodeIfPresent(hiddenProfileClosePolicy?.intValueForBackup, forKey: .hiddenProfileClosePolicy)
        try container.encodeIfPresent(timeIntervalForBackgroundHiddenProfileClosePolicy?.rawValue, forKey: .timeIntervalForBackgroundHiddenProfileClosePolicy)
        try container.encode(alwaysNotifyWhenMentionnedEvenInMutedDiscussion, forKey: .alwaysNotifyWhenMentionnedEvenInMutedDiscussion)
    }

    
    public init(from decoder: Decoder) throws {
        
        let values = try decoder.container(keyedBy: CodingKeys.self)

        self.maxAttachmentSizeForAutomaticDownload = try values.decodeIfPresent(Int.self, forKey: .maxAttachmentSizeForAutomaticDownload)
        if let raw = try values.decodeIfPresent(Int.self, forKey: .identityColorStyle) {
            self.identityColorStyle = IdentityColorStyle(rawValue: raw)
        } else {
            self.identityColorStyle = nil
        }
        if let byLastName = try values.decodeIfPresent(Bool.self, forKey: .contactsSortOrder) {
            self.contactsSortOrder = byLastName ? .byLastName : .byFirstName
        } else {
            self.contactsSortOrder = nil
        }
        self.useOldDiscussionInterface = try values.decodeIfPresent(Bool.self, forKey: .useOldDiscussionInterface)
        self.sendReadReceipt = try values.decodeIfPresent(Bool.self, forKey: .sendReadReceipt)
        if let raw = try values.decodeIfPresent(Int.self, forKey: .doFetchContentRichURLsMetadata) {
            self.doFetchContentRichURLsMetadata = ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice(rawValue: raw)
        } else {
            self.doFetchContentRichURLsMetadata = nil
        }
        self.readOnce = try values.decodeIfPresent(Bool.self, forKey: .readOnce)
        if let raw = try values.decodeIfPresent(Int.self, forKey: .visibilityDuration) {
            self.visibilityDuration = DurationOption(rawValue: raw)
        } else {
            self.visibilityDuration = nil
        }
        if let raw = try values.decodeIfPresent(Int.self, forKey: .existenceDuration) {
            self.existenceDuration = DurationOption(rawValue: raw)
        } else {
            self.existenceDuration = nil
        }
        // For countBasedRetentionPolicy, note that a value nil and 0 are eventuall equivalent when restoring this setting, see ``updateExistingObvMessengerSettings()``
        self.countBasedRetentionPolicy = try values.decodeIfPresent(Int.self, forKey: .countBasedRetentionPolicy)
        if let raw = try values.decodeIfPresent(Int.self, forKey: .timeBasedRetentionPolicy) {
            self.timeBasedRetentionPolicy = DurationOptionAlt(rawValue: raw)
        } else {
            self.timeBasedRetentionPolicy = nil
        }
        self.autoRead = try values.decodeIfPresent(Bool.self, forKey: .autoRead)
        self.retainWipedOutboundMessages = try values.decodeIfPresent(Bool.self, forKey: .retainWipedOutboundMessages)
        if let raw = try values.decodeIfPresent(Int.self, forKey: .hideNotificationContent) {
            self.hideNotificationContent = ObvMessengerSettings.Privacy.HideNotificationContentType(rawValue: raw)
        } else if let bool = try values.decodeIfPresent(Bool.self, forKey: .hideNotificationContentAndroid) {
            self.hideNotificationContent = bool ? .completely : .no
        } else {
            self.hideNotificationContent = nil
        }
        self.allowCustomKeyboards = try values.decodeIfPresent(Bool.self, forKey: .allowCustomKeyboards)
        self.showBetaSettings = try values.decodeIfPresent(Bool.self, forKey: .showBetaSettings)
        self.isCallKitEnabled = try values.decodeIfPresent(Bool.self, forKey: .isCallKitEnabled)
        if let rawValue = try values.decodeIfPresent(String.self, forKey: .autoAcceptGroupInviteFrom) {
            self.autoAcceptGroupInviteFrom = ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom(rawValue: rawValue)
        } else {
            self.autoAcceptGroupInviteFrom = nil
        }
        self.preferredEmojisList = try values.decodeIfPresent([String].self, forKey: .preferredEmojisList)
        self.performInteractionDonation = try values.decodeIfPresent(Bool.self, forKey: .performInteractionDonation)
        if let hiddenProfileClosePolicyBackupIntValue = try values.decodeIfPresent(Int.self, forKey: .hiddenProfileClosePolicy) {
            if let hiddenProfileClosePolicy = ObvMessengerSettings.Privacy.HiddenProfileClosePolicy(fromBackupIntValue: hiddenProfileClosePolicyBackupIntValue) {
                self.hiddenProfileClosePolicy = hiddenProfileClosePolicy
            } else {
                self.hiddenProfileClosePolicy = nil
            }
        } else {
            self.hiddenProfileClosePolicy = nil
        }
        if let timeIntervalForBackgroundHiddenProfileClosePolicyIntValue = try values.decodeIfPresent(Int.self, forKey: .timeIntervalForBackgroundHiddenProfileClosePolicy) {
            let timeIntervalForBackgroundHiddenProfileClosePolicyRawValue = TimeInterval(timeIntervalForBackgroundHiddenProfileClosePolicyIntValue)
            if let timeIntervalForBackgroundHiddenProfileClosePolicy = ObvMessengerSettings.Privacy.TimeIntervalForBackgroundHiddenProfileClosePolicy(rawValue: timeIntervalForBackgroundHiddenProfileClosePolicyRawValue) {
                self.timeIntervalForBackgroundHiddenProfileClosePolicy = timeIntervalForBackgroundHiddenProfileClosePolicy
            } else {
                self.timeIntervalForBackgroundHiddenProfileClosePolicy = nil
            }
        } else {
            self.timeIntervalForBackgroundHiddenProfileClosePolicy = nil
        }
        if let alwaysNotifyWhenMentionnedEvenInMutedDiscussion = try values.decodeIfPresent(Bool.self, forKey: .alwaysNotifyWhenMentionnedEvenInMutedDiscussion) {
            self.alwaysNotifyWhenMentionnedEvenInMutedDiscussion = alwaysNotifyWhenMentionnedEvenInMutedDiscussion
        } else {
            self.alwaysNotifyWhenMentionnedEvenInMutedDiscussion = ObvMessengerSettings.Discussions.notificationOptions.contains(.alwaysNotifyWhenMentionnedEvenInMutedDiscussion)
        }
    }
}



fileprivate extension Int {
    var secondsToTimeInterval: TimeInterval {
        TimeInterval(self)
    }
}


fileprivate extension Data {
    var toUID: UID? {
        UID(uid: self)
    }
}


fileprivate extension ObvMessengerSettings.Privacy.HiddenProfileClosePolicy {
    
    var intValueForBackup: Int {
        switch self {
        case .manualSwitching: return 2
        case .screenLock: return 1
        case .background: return 3
        }
    }
    
    init?(fromBackupIntValue intValue: Int) {
        switch intValue {
        case -1:
            return nil
        case 1: self = .screenLock
        case 2: self = .manualSwitching
        case 3: self = .background
        default:
            assertionFailure()
            return nil
        }
    }
    
}
