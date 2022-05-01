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
    
    struct ContactsAndGroups {
        
        private struct Keys {
            static let autoAcceptGroupInviteFrom = "settings.contacts.and.groups.autoAcceptGroupInviteFrom"
        }
        
        enum AutoAcceptGroupInviteFrom: String, CaseIterable {
            case everyone = "everyone"
            case oneToOneContactsOnly = "contacts"
            case noOne = "nobody"
            
            var localizedDescription: String {
                switch self {
                case .everyone:
                    return CommonString.Word.Everyone
                case .oneToOneContactsOnly:
                    return CommonString.Word.Contacts
                case .noOne:
                    return CommonString.Word.NoOne
                }
            }
            
        }
        
        static var autoAcceptGroupInviteFrom: AutoAcceptGroupInviteFrom {
            get {
                let raw = userDefaults.stringOrNil(forKey: Keys.autoAcceptGroupInviteFrom) ?? AutoAcceptGroupInviteFrom.oneToOneContactsOnly.rawValue
                return AutoAcceptGroupInviteFrom(rawValue: raw) ?? .oneToOneContactsOnly
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Keys.autoAcceptGroupInviteFrom)
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
                ObvMessengerSettingsNotifications.identityColorStyleDidChange.postOnDispatchQueue()
            }
        }


        static var contactsSortOrder: ContactsSortOrder {
            get {
                let raw = userDefaults.integerOrNil(forKey: Keys.contactsSortOrder) ?? ContactsSortOrder.byFirstName.rawValue
                return ContactsSortOrder(rawValue: raw) ?? ContactsSortOrder.byFirstName
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Keys.contactsSortOrder)
                ObvMessengerSettingsNotifications.contactsSortOrderDidChange.postOnDispatchQueue()
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
                ObvMessengerSettingsNotifications.preferredComposeMessageViewActionsDidChange.postOnDispatchQueue()
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
                ObvMessengerSettingsNotifications.isCallKitEnabledSettingDidChange
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
                ObvMessengerSettingsNotifications.isIncludesCallsInRecentsEnabledSettingDidChange
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
            static let defaultEmojiButton = "settings.defaultEmojiButton"
        }

        static fileprivate(set) var preferredEmojisList: [String] {
            get {
                return userDefaults.stringArray(forKey: Keys.preferredEmojisList) ?? []
            }
            set {
                guard newValue != preferredEmojisList else { return }
                userDefaults.set(newValue, forKey: Keys.preferredEmojisList)
            }
        }

        static var defaultEmojiButton: String? {
            get {
                return userDefaults.stringOrNil(forKey: Keys.defaultEmojiButton)
            }
            set {
                guard newValue != defaultEmojiButton else { return }
                userDefaults.set(newValue, forKey: Keys.defaultEmojiButton)
                ObvMessengerSettingsObservableObject.shared.defaultEmojiButton = defaultEmojiButton
            }
        }
    }

    // MARK: - MDM
    
    struct MDM {
        
        private struct Key {
            static let mdmConfigurationKey = "com.apple.configuration.managed"
        }
        
        private static let standardUserDefaults = UserDefaults.standard
        static var configuration: [String: Any]? { standardUserDefaults.dictionary(forKey: Key.mdmConfigurationKey) }
        
        static var isConfiguredFromMDM: Bool {
            configuration != nil
        }
        
        struct Configuration {
            
            private struct Key {
                static let URI = "keycloak_configuration_uri"
            }
            
            static var uri: URL? {
                guard let mdmConfiguration = MDM.configuration else { return nil }
                guard let rawValue = mdmConfiguration[Key.URI] else { assertionFailure(); return nil }
                guard let stringValue = rawValue as? String else { assertionFailure(); return nil }
                guard let value = URL(string: stringValue) else { assertionFailure(); return nil }
                return value
            }
            
        }
        
    }
    
    // MARK: - Minimum and latest iOS App versions sent by the server
    
    struct AppVersionAvailable {
        
        private struct Key {
            static let minimum = "settings.AppVersionAvailable.minimum"
            static let latest = "settings.AppVersionAvailable.latest"
        }
        
        /// This corresponds to the minimum acceptable iOS build version returned by the server when querying the well known point.
        static var minimum: Int? {
            get {
                return userDefaults.integerOrNil(forKey: Key.minimum)
            }
            set {
                guard newValue != minimum else { return }
                userDefaults.set(newValue, forKey: Key.minimum)
            }
        }

        /// This corresponds to the latest acceptable iOS build version returned by the server when querying the well known point.
        static var latest: Int? {
            get {
                return userDefaults.integerOrNil(forKey: Key.latest)
            }
            set {
                guard newValue != latest else { return }
                userDefaults.set(newValue, forKey: Key.latest)
            }
        }

    }
    
}



final class ObvMessengerPreferredEmojisListObservable: ObservableObject {

    @Published var emojis: [String] = ObvMessengerSettings.Emoji.preferredEmojisList {
        didSet {
            ObvMessengerSettings.Emoji.preferredEmojisList = emojis
        }
    }
    
}

/// This singleton makes it possible to observe certain changes made to the settings.

final class ObvMessengerSettingsObservableObject: ObservableObject {
    
    static let shared = ObvMessengerSettingsObservableObject()

    @Published fileprivate(set) var defaultEmojiButton: String?
    
    private init() {
        defaultEmojiButton = ObvMessengerSettings.Emoji.defaultEmojiButton
    }
    
}

extension UserDefaults {

    func addObjectsModifiedByShareExtension(_ urlsAndEntityName: [(URL, String)]) {
        var dict = dictionary(forKey: ObvMessengerConstants.objectsModifiedByShareExtension) ?? [:]
        for (url, entityName) in urlsAndEntityName {
            dict[url.absoluteString] = entityName
        }
        set(dict, forKey: ObvMessengerConstants.objectsModifiedByShareExtension)
    }

    func resetObjectsModifiedByShareExtension() {
        removeObject(forKey: ObvMessengerConstants.objectsModifiedByShareExtension)
    }

    var objectsModifiedByShareExtensionURLAndEntityName: [(URL, String)] {
        guard let dict = dictionary(forKey: ObvMessengerConstants.objectsModifiedByShareExtension) else {
            return []
        }
        return dict.compactMap { (urlAsString, entityNameAsAny) in
            guard let url = URL(string: urlAsString) else { return nil }
            guard let entityName = entityNameAsAny as? String else { return nil }
            return (url, entityName)
        }
    }

}
