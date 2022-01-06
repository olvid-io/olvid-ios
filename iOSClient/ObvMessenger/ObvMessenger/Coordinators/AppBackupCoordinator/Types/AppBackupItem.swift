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
import ObvTypes
import SwiftUI


struct AppBackupItem: Codable, Hashable {
    
    let globalSettings: GlobalSettingsBackupItem
    let ownedIdentities: [PersistedObvOwnedIdentityBackupItem]?
    
    enum CodingKeys: String, CodingKey {
        case ownedIdentities = "owned_identities"
        case globalSettings = "settings"
    }
    
    init(ownedIdentities: [PersistedObvOwnedIdentity]) {
        self.globalSettings = GlobalSettingsBackupItem()
        let ownedIdentitiesBackupItems = ownedIdentities.map { $0.backupItem }.filter({ !$0.isEmpty })
        self.ownedIdentities = ownedIdentitiesBackupItems.isEmpty ? nil : ownedIdentitiesBackupItems
    }

}



struct PersistedObvOwnedIdentityBackupItem: Codable, Hashable {
    
    let identity: Data
    let contacts: [PersistedObvContactIdentityBackupItem]?
    let groups: [PersistedContactGroupBackupItem]?
    
    
    var isEmpty: Bool {
        return contacts == nil && groups == nil
    }

    enum CodingKeys: String, CodingKey {
        case identity = "owned_identity"
        case contacts = "contacts"
        case groups = "groups"
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



struct PersistedDiscussionConfigurationBackupItem: Codable, Hashable {
    
    // Local configuration
    
    let sendReadReceipt: Bool?
    let muteNotifications: Bool?
    let muteNotificationsEndDate: Date?
    let autoRead: Bool?
    let retainWipedOutboundMessages: Bool?
    let countBasedRetentionIsActive: Bool?
    let countBasedRetention: Int?
    let timeBasedRetention: TimeInterval?
    let doFetchContentRichURLsMetadata: ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice?
    
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
        doFetchContentRichURLsMetadata == nil
    }
    

    enum CodingKeys: String, CodingKey {
        case sendReadReceipt = "send_read_receipt"
        case muteNotifications = "mute_notifications"
        case muteNotificationsEndDate = "mute_notification_timestamp"
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
    }

    
    init(local: PersistedDiscussionLocalConfiguration, shared: PersistedDiscussionSharedConfiguration) {
        
        self.sendReadReceipt = local.doSendReadReceipt
        self.muteNotifications = local.shouldMuteNotifications ? true : nil
        self.muteNotificationsEndDate = local.currentMuteNotificationsEndDate
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
        try container.encodeIfPresent(autoRead, forKey: .autoRead)
        try container.encodeIfPresent(retainWipedOutboundMessages, forKey: .retainWipedOutboundMessages)
        try container.encodeIfPresent(countBasedRetentionIsActive, forKey: .countBasedRetentionIsActive)
        try container.encodeIfPresent(countBasedRetention, forKey: .countBasedRetention)

        // Specific value to maintain compatibility with Android
        let countBasedRetentionAndroid: Int?
        if let isActive = countBasedRetentionIsActive {
            countBasedRetentionAndroid = isActive ? countBasedRetention ?? ObvMessengerSettings.Discussions.countBasedRetentionPolicy : 0 // 0 means keep everything
        } else if ObvMessengerSettings.Discussions.countBasedRetentionPolicyIsActive {
            countBasedRetentionAndroid = countBasedRetention
        } else {
            countBasedRetentionAndroid = nil
        }
        try container.encodeIfPresent(countBasedRetentionAndroid, forKey: .countBasedRetentionAndroid)
        
        try container.encodeIfPresent(timeBasedRetention?.toSeconds, forKey: .timeBasedRetention)
        try container.encodeIfPresent(doFetchContentRichURLsMetadata?.rawValue, forKey: .doFetchContentRichURLsMetadata)
        
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
        self.autoRead = try values.decodeIfPresent(Bool.self, forKey: .autoRead)
        self.retainWipedOutboundMessages = try values.decodeIfPresent(Bool.self, forKey: .retainWipedOutboundMessages)

        // Complex part concerning countBasedRetention and countBasedRetentionIsActive
        
        let countBasedRetentionIsActive = try values.decodeIfPresent(Bool.self, forKey: .countBasedRetentionIsActive)
        let countBasedRetention = try values.decodeIfPresent(Int.self, forKey: .countBasedRetention)
        if countBasedRetentionIsActive == nil && countBasedRetention == nil {
            self.countBasedRetention = try values.decodeIfPresent(Int.self, forKey: .countBasedRetentionAndroid)
            switch countBasedRetention {
            case .none:
                self.countBasedRetentionIsActive = nil
            case let .some(x) where x <= 0:
                self.countBasedRetentionIsActive = false
            default:
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
        self.sharedSettingsVersion = try values.decodeIfPresent(Int.self, forKey: .sharedSettingsVersion)
        self.existenceDuration = (try values.decodeIfPresent(Int.self, forKey: .existenceDuration))?.secondsToTimeInterval
        self.visibilityDuration = (try values.decodeIfPresent(Int.self, forKey: .visibilityDuration))?.secondsToTimeInterval
        self.readOnce = (try values.decodeIfPresent(Bool.self, forKey: .readOnce))

    }
    
}


struct GlobalSettingsBackupItem: Codable, Hashable {
    
    // Downloads
    
    let maxAttachmentSizeForAutomaticDownload: Int?

    // Interface
    
    let identityColorStyle: AppTheme.IdentityColorStyle?
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
    
    // Privacy
    
    let hideNotificationContent: ObvMessengerSettings.Privacy.HideNotificationContentType?
    
    // VoIP
    
    let isCallKitEnabled: Bool?
    
    // Advanced
    
    let allowCustomKeyboards: Bool?
    
    // BetaConfiguration
    
    let showBetaSettings: Bool?
    
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
        if ObvMessengerSettings.Discussions.countBasedRetentionPolicyIsActive {
            self.countBasedRetentionPolicy = ObvMessengerSettings.Discussions.countBasedRetentionPolicy
        } else {
            self.countBasedRetentionPolicy = 0
        }
        self.timeBasedRetentionPolicy = ObvMessengerSettings.Discussions.timeBasedRetentionPolicy
        self.autoRead = ObvMessengerSettings.Discussions.autoRead
        self.retainWipedOutboundMessages = ObvMessengerSettings.Discussions.retainWipedOutboundMessages
        self.hideNotificationContent = ObvMessengerSettings.Privacy.hideNotificationContent
        self.allowCustomKeyboards = ObvMessengerSettings.Advanced.allowCustomKeyboards
        self.showBetaSettings = ObvMessengerSettings.BetaConfiguration.showBetaSettings
        self.isCallKitEnabled = ObvMessengerSettings.VoIP.isCallKitEnabled
    }
    
    func encode(to encoder: Encoder) throws {
        
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

    }

    
    init(from decoder: Decoder) throws {
        
        let values = try decoder.container(keyedBy: CodingKeys.self)

        self.maxAttachmentSizeForAutomaticDownload = try values.decodeIfPresent(Int.self, forKey: .maxAttachmentSizeForAutomaticDownload)
        if let raw = try values.decodeIfPresent(Int.self, forKey: .identityColorStyle) {
            self.identityColorStyle = AppTheme.IdentityColorStyle(rawValue: raw)
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
