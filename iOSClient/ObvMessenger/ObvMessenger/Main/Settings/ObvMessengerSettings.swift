/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


struct ObvMessengerSettings {
    
    static private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)!
    
    struct Downloads {
        
        // In bytes
        
        static let byteSizes = [0, 1_000_000, 3_000_000, 5_000_000, 10_000_000, 20_000_000, 50_000_000, 100_000_000]
        
        static var maxAttachmentSizeForAutomaticDownload: Int {
            get {
                return userDefaults.integerOrNil(forKey: "settings.downloads.maxAttachmentSizeForAutomaticDownload") ?? 10_000_000
            }
            set {
                userDefaults.set(newValue, forKey: "settings.downloads.maxAttachmentSizeForAutomaticDownload")
            }
        }
    }
    
    struct Interface {

        private struct Keys {
            static let identityColorStyle = "settings.interface.identityColorStyle"
            static let contactsSortOrder = "settings.interface.contactsSortOrder"
            static let useOldDiscussionInterface = "settings.interface.useOldDiscussionInterface"
            static let preferredComposeMessageViewActions = "settings.interface.preferredComposeMessageViewActions"
        }
        
        static var identityColorStyle: AppTheme.IdentityColorStyle {
            get {
                let raw = userDefaults.integerOrNil(forKey: Keys.identityColorStyle) ?? 0
                return AppTheme.IdentityColorStyle(rawValue: raw) ?? AppTheme.IdentityColorStyle.hue
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Keys.identityColorStyle)
                ObvMessengerInternalNotification.identityColorStyleDidChange.postOnDispatchQueue()
            }
        }


        static var contactsSortOrder: ContactsSortOrder {
            get {
                let raw = userDefaults.integerOrNil(forKey: Keys.contactsSortOrder) ?? ContactsSortOrder.byFirstName.rawValue
                return ContactsSortOrder(rawValue: raw) ?? ContactsSortOrder.byFirstName
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Keys.contactsSortOrder)
                ObvMessengerInternalNotification.contactsSortOrderDidChange.postOnDispatchQueue()
            }
        }
        
        
        static var useOldDiscussionInterface: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Keys.useOldDiscussionInterface) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Keys.useOldDiscussionInterface)
            }
        }

        static var preferredComposeMessageViewActions: [NewComposeMessageViewAction] {
            get {
                guard let rawValues = userDefaults.array(forKey: Keys.preferredComposeMessageViewActions) as? [Int] else { return NewComposeMessageViewAction.defaultActions }
                var actions = rawValues.compactMap({ NewComposeMessageViewAction(rawValue: $0) })
                // Add missing actions (we expect to add all the actions that cannot be reordered)
                let missingActions = NewComposeMessageViewAction.defaultActions.filter({ !actions.contains($0) })
                actions += missingActions
                return actions
            }
            set {
                let newRawValues = newValue.filter({ $0.canBeReordered }).map({ $0.rawValue })
                userDefaults.set(newRawValues, forKey: Keys.preferredComposeMessageViewActions)
                ObvMessengerInternalNotification.preferredComposeMessageViewActionsDidChange.postOnDispatchQueue()
            }
        }
        
    }
    
    struct Discussions {
        
        // MARK: Read receipts
                
        static var doSendReadReceipt: Bool {
            get {
                return userDefaults.boolOrNil(forKey: "settings.discussions.doSendReadReceipt") ?? false
            }
            set {
                userDefaults.set(newValue, forKey: "settings.discussions.doSendReadReceipt")
            }
        }
        
        // MARK: Rich link previews
        
        enum FetchContentRichURLsMetadataChoice: Int, CaseIterable, Identifiable {
            case never = 0
            case withinSentMessagesOnly = 1
            case always = 2
            var id: Int { rawValue }
       }

        
        static var doFetchContentRichURLsMetadata: FetchContentRichURLsMetadataChoice {
            get {
                let raw = userDefaults.integerOrNil(forKey: "settings.discussions.doFetchContentRichURLsMetadata") ?? FetchContentRichURLsMetadataChoice.always.rawValue
                return FetchContentRichURLsMetadataChoice(rawValue: raw) ?? FetchContentRichURLsMetadataChoice.always
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: "settings.discussions.doFetchContentRichURLsMetadata")
            }
        }

        // MARK: Ephemeral messages: read once
        
        static var readOnce: Bool {
            get {
                return userDefaults.boolOrNil(forKey: "settings.discussions.readOnce") ?? false
            }
            set {
                userDefaults.set(newValue, forKey: "settings.discussions.readOnce")
            }
        }

        // MARK: Ephemeral messages: visibility duration
        
        static var visibilityDuration: DurationOption {
            get {
                let raw = userDefaults.integerOrNil(forKey: "settings.discussions.visibilityDuration") ?? DurationOption.none.rawValue
                return DurationOption(rawValue: raw) ?? .none
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: "settings.discussions.visibilityDuration")
            }
        }

        
        // MARK: Ephemeral messages: existence duration
        
        static var existenceDuration: DurationOption {
            get {
                let raw = userDefaults.integerOrNil(forKey: "settings.discussions.existenceDuration") ?? DurationOption.none.rawValue
                return DurationOption(rawValue: raw) ?? .none
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: "settings.discussions.existenceDuration")
            }
        }

        // MARK: Count based retention policy
        
        static var countBasedRetentionPolicyIsActive: Bool {
            get {
                return userDefaults.boolOrNil(forKey: "settings.discussions.countBasedRetentionPolicyIsActive") ?? false
            }
            set {
                userDefaults.set(newValue, forKey: "settings.discussions.countBasedRetentionPolicyIsActive")
            }
        }

        static var countBasedRetentionPolicy: Int {
            get {
                return userDefaults.integerOrNil(forKey: "settings.discussions.countBasedRetentionPolicy") ?? 100
            }
            set {
                guard newValue >= 0 else { return }
                userDefaults.set(newValue, forKey: "settings.discussions.countBasedRetentionPolicy")
            }
        }

        // MARK: Time based retention policy
        
        static var timeBasedRetentionPolicy: DurationOptionAlt {
            get {
                let raw = userDefaults.integerOrNil(forKey: "settings.discussions.timeBasedRetentionPolicy") ?? DurationOptionAlt.none.rawValue
                return DurationOptionAlt(rawValue: raw) ?? .none
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: "settings.discussions.timeBasedRetentionPolicy")
            }
        }

        // MARK: Ephemeral messages: auto read

        static var autoRead: Bool {
            get {
                return userDefaults.boolOrNil(forKey: "settings.discussions.autoRead") ?? false
            }
            set {
                userDefaults.set(newValue, forKey: "settings.discussions.autoRead")
            }
        }

        // MARK: Ephemeral messages: auto read

        static var retainWipedOutboundMessages: Bool {
            get {
                return userDefaults.boolOrNil(forKey: "settings.discussions.retainWipedOutboundMessages") ?? false
            }
            set {
                userDefaults.set(newValue, forKey: "settings.discussions.retainWipedOutboundMessages")
            }
        }

    }
    
    
    // MARK: - Privacy
    
    struct Privacy {
        
        // MARK: Lock screen
        
        static var lockScreen: Bool {
            get {
                return userDefaults.boolOrNil(forKey: "settings.privacy.lockScreen") ?? false
            }
            set {
                userDefaults.set(newValue, forKey: "settings.privacy.lockScreen")
            }
        }
        
        /// Possible grace periods (in seconds)
        static let gracePeriods: [TimeInterval] = [0, 5, 60, 60*5, 60*15, 60*60]
        
        static var lockScreenGracePeriod: TimeInterval {
            get {
                return userDefaults.doubleOrNil(forKey: "settings.privacy.lockScreenGracePeriod") ?? 0
            }
            set {
                userDefaults.set(newValue, forKey: "settings.privacy.lockScreenGracePeriod")
            }
        }

        // MARK: Hide notification content
        
        enum HideNotificationContentType: Int {
            case no = 0
            case partially = 1
            case completely = 2
        }
        
        static var hideNotificationContent: HideNotificationContentType {
            get {
                let raw = userDefaults.integerOrNil(forKey: "settings.privacy.hideNotificationContent") ?? HideNotificationContentType.no.rawValue
                return HideNotificationContentType(rawValue: raw) ?? HideNotificationContentType.no
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: "settings.privacy.hideNotificationContent")
            }
        }
        
    }
    
    
    // MARK: - Backup
    
    struct Backup {
        
        static var isAutomaticBackupEnabled: Bool {
            get {
                return userDefaults.boolOrNil(forKey: "settings.backup.isAutomaticBackupEnabled") ?? false
            }
            set {
                userDefaults.set(newValue, forKey: "settings.backup.isAutomaticBackupEnabled")
            }
        }

        static var isAutomaticCleaningBackupEnabled: Bool {
            get {
                return userDefaults.boolOrNil(forKey: "settings.backup.isAutomaticCleaningBackupEnabled") ?? false
            }
            set {
                userDefaults.set(newValue, forKey: "settings.backup.isAutomaticCleaningBackupEnabled")
            }
        }

    }
    
    
    // MARK: - VoIP
    
    struct VoIP {

        static var isCallKitEnabled: Bool {
            get {
                guard ObvMessengerConstants.isRunningOnRealDevice else { return false }
                return userDefaults.boolOrNil(forKey: "settings.voip.isCallKitEnabled") ?? true
            }
            set {
                guard ObvMessengerConstants.isRunningOnRealDevice else { return }
                guard newValue != isCallKitEnabled else { return }
                userDefaults.set(newValue, forKey: "settings.voip.isCallKitEnabled")
                ObvMessengerInternalNotification.isCallKitEnabledSettingDidChange
                    .postOnDispatchQueue()
            }
        }

        static var isIncludesCallsInRecentsEnabled: Bool {
            get {
                return userDefaults.boolOrNil(forKey: "settings.voip.isIncludesCallsInRecentsEnabled") ?? true
            }
            set {
                guard newValue != isIncludesCallsInRecentsEnabled else { return }
                userDefaults.set(newValue, forKey: "settings.voip.isIncludesCallsInRecentsEnabled")
                ObvMessengerInternalNotification.isIncludesCallsInRecentsEnabledSettingDidChange
                    .postOnDispatchQueue()
            }
        }

        static let maxaveragebitratePossibleValues: [Int?] = [nil, 8_000, 16_000, 24_000, 32_000]
        
        // See https://datatracker.ietf.org/doc/html/draft-spittka-payload-rtp-opus
        static var maxaveragebitrate: Int? {
            get {
                return userDefaults.integerOrNil(forKey: "settings.voip.maxaveragebitrate")
            }
            set {
                guard newValue != maxaveragebitrate else { return }
                userDefaults.set(newValue, forKey: "settings.voip.maxaveragebitrate")
            }
        }

    }
    
    // MARK: - Alerts
    
    struct Alert {
        
        // Since this key is not used anymore, we only provide a way to remove it from the user defaults
        static func removeSecureCallsInBeta() {
            userDefaults.removeObject(forKey: "settings.alert.showSecureCallsInBeta")
        }
        
        static func resetAllAlerts() {
            removeSecureCallsInBeta()
        }
        
    }
    
    // MARK: - Subscriptions
    
    struct Subscription {
        
        static var allowAPIKeyActivationWithBadKeyStatus: Bool {
            get {
                return userDefaults.boolOrNil(forKey: "settings.subscription.allowAPIKeyActivationWithBadKeyStatus") ?? false
            }
            set {
                guard newValue != allowAPIKeyActivationWithBadKeyStatus else { return }
                userDefaults.set(newValue, forKey: "settings.subscription.allowAPIKeyActivationWithBadKeyStatus")
            }
        }
        
    }
    
    
    // MARK: - Advanced
    
    struct Advanced {
        
        static var allowCustomKeyboards: Bool {
            get {
                return userDefaults.boolOrNil(forKey: "settings.advanced.allowCustomKeyboards") ?? true
            }
            set {
                guard newValue != allowCustomKeyboards else { return }
                userDefaults.set(newValue, forKey: "settings.advanced.allowCustomKeyboards")
            }
        }
        
    }
    
    // MARK: - Access to advanced settings / beta config (for non TestFlight users)
    
    struct BetaConfiguration {
        
        static var showBetaSettings: Bool {
            get {
                return userDefaults.boolOrNil(forKey: "settings.beta.showBetaSettings") ?? false
            }
            set {
                guard newValue != showBetaSettings else { return }
                if newValue {
                    userDefaults.set(newValue, forKey: "settings.beta.showBetaSettings")
                } else {
                    userDefaults.set(nil, forKey: "settings.beta.showBetaSettings")
                }
            }
        }

    }

    // MARK: - Emojis

    struct Emoji {

        private struct Keys {
            static let preferredEmojisList = "settings.preferredEmojisList"
        }

        static var preferredEmojisList: [String] {
            get {
                return userDefaults.stringArray(forKey: Keys.preferredEmojisList) ?? []
            }
            set {
                guard newValue != preferredEmojisList else { return }
                userDefaults.set(newValue, forKey: Keys.preferredEmojisList)
            }
        }
    }

}


@available(iOS 13.0, *)
final class ObvMessengerDownloadSettingsObservable: ObservableObject {

    @Published var chosenIndex: Int = ObvMessengerSettings.Downloads.byteSizes.firstIndex(of: ObvMessengerSettings.Downloads.maxAttachmentSizeForAutomaticDownload) ?? 0 {
        didSet {
            ObvMessengerSettings.Downloads.maxAttachmentSizeForAutomaticDownload = ObvMessengerSettings.Downloads.byteSizes[chosenIndex]
        }
    }
    
}


@available(iOS 13.0, *)
final class ObvMessengerInterfaceSettingsObservable: ObservableObject {

    @Published var preferredComposeMessageViewActions: [NewComposeMessageViewAction] = ObvMessengerSettings.Interface.preferredComposeMessageViewActions {
        didSet {
            ObvMessengerSettings.Interface.preferredComposeMessageViewActions = preferredComposeMessageViewActions
        }
    }
}

@available(iOS 13.0, *)
final class ObvMessengerPreferredEmojisListObservable: ObservableObject {

    @Published var emojis: [String] = ObvMessengerSettings.Emoji.preferredEmojisList {
        didSet {
            ObvMessengerSettings.Emoji.preferredEmojisList = emojis
        }
    }
    
}


// MARK: - For Backup purposes

extension GlobalSettingsBackupItem {
    
    func updateExistingObvMessengerSettings() {
        
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
        
    }
    
}