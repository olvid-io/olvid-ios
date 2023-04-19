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
    static private let kSettingsKeyPath = "settings"
    
    struct Downloads {
        
        // In bytes (-1 means unlimited)
        
        static let byteSizes = [0, 1_000_000, 3_000_000, 5_000_000, 10_000_000, 20_000_000, 50_000_000, 100_000_000, -1]
        
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
        
        enum Key: String {
            case identityColorStyle = "identityColorStyle"
            case contactsSortOrder = "contactsSortOrder"
            case useOldDiscussionInterface = "useOldDiscussionInterface"
            case useOldListOfDiscussionsInterface = "useOldListOfDiscussionsInterface"
            case preferredComposeMessageViewActions = "preferredComposeMessageViewActions"
            
            private var kInterface: String { "interface" }
            
            var path: String {
                [kSettingsKeyPath, kInterface, self.rawValue].joined(separator: ".")
            }
            
        }
        
        static var identityColorStyle: AppTheme.IdentityColorStyle {
            get {
                let raw = userDefaults.integerOrNil(forKey: Key.identityColorStyle.path) ?? 0
                return AppTheme.IdentityColorStyle(rawValue: raw) ?? AppTheme.IdentityColorStyle.hue
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Key.identityColorStyle.path)
                ObvMessengerSettingsNotifications.identityColorStyleDidChange.postOnDispatchQueue()
            }
        }
        
        
        static var contactsSortOrder: ContactsSortOrder {
            get {
                let raw = userDefaults.integerOrNil(forKey: Key.contactsSortOrder.path) ?? ContactsSortOrder.byFirstName.rawValue
                return ContactsSortOrder(rawValue: raw) ?? ContactsSortOrder.byFirstName
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Key.contactsSortOrder.path)
                ObvMessengerSettingsNotifications.contactsSortOrderDidChange.postOnDispatchQueue()
            }
        }
        
        
        static var useOldDiscussionInterface: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.useOldDiscussionInterface.path) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Key.useOldDiscussionInterface.path)
            }
        }
        
        static var useOldListOfDiscussionsInterface: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.useOldListOfDiscussionsInterface.path) ?? false
            }
            set {
                guard newValue != useOldListOfDiscussionsInterface else { return }
                userDefaults.set(newValue, forKey: Key.useOldListOfDiscussionsInterface.path)
                ObvMessengerSettingsObservableObject.shared.useOldListOfDiscussionsInterface = useOldListOfDiscussionsInterface
            }
        }
        
        static var preferredComposeMessageViewActions: [NewComposeMessageViewAction] {
            get {
                guard let rawValues = userDefaults.array(forKey: Key.preferredComposeMessageViewActions.path) as? [Int] else { return NewComposeMessageViewAction.defaultActions }
                var actions = rawValues.compactMap({ NewComposeMessageViewAction(rawValue: $0) })
                // Add missing actions (we expect to add all the actions that cannot be reordered)
                let missingActions = NewComposeMessageViewAction.defaultActions.filter({ !actions.contains($0) })
                actions += missingActions
                return actions
            }
            set {
                let newRawValues = newValue.filter({ $0.canBeReordered }).map({ $0.rawValue })
                userDefaults.set(newRawValues, forKey: Key.preferredComposeMessageViewActions.path)
                ObvMessengerSettingsNotifications.preferredComposeMessageViewActionsDidChange.postOnDispatchQueue()
            }
        }
        
    }
    
    struct Discussions {
        
        private struct Keys {
            static let doSendReadReceipt = "settings.discussions.doSendReadReceipt"
            static let doFetchContentRichURLsMetadata = "settings.discussions.doFetchContentRichURLsMetadata"
            static let visibilityDuration = "settings.discussions.visibilityDuration"
            static let existenceDuration = "settings.discussions.existenceDuration"
            static let countBasedRetentionPolicyIsActive = "settings.discussions.countBasedRetentionPolicyIsActive"
            static let countBasedRetentionPolicy = "settings.discussions.countBasedRetentionPolicy"
            static let timeBasedRetentionPolicy = "settings.discussions.timeBasedRetentionPolicy"
            static let autoRead = "settings.discussions.autoRead"
            static let readOnce = "settings.discussions.readOnce"
            static let retainWipedOutboundMessages = "settings.discussions.retainWipedOutboundMessages"
            static let notificationSound = "settings.discussions.notificationSound"
            static let performInteractionDonation = "settings.discussions.performInteractionDonation"
        }
        
        
        // MARK: Read receipts
        
        static var doSendReadReceipt: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Keys.doSendReadReceipt) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Keys.doSendReadReceipt)
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
                let raw = userDefaults.integerOrNil(forKey: Keys.doFetchContentRichURLsMetadata) ?? FetchContentRichURLsMetadataChoice.always.rawValue
                return FetchContentRichURLsMetadataChoice(rawValue: raw) ?? FetchContentRichURLsMetadataChoice.always
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Keys.doFetchContentRichURLsMetadata)
            }
        }
        
        // MARK: Ephemeral messages: read once
        
        static var readOnce: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Keys.readOnce) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Keys.readOnce)
            }
        }
        
        // MARK: Ephemeral messages: visibility duration
        
        static var visibilityDuration: DurationOption {
            get {
                let raw = userDefaults.integerOrNil(forKey: Keys.visibilityDuration) ?? DurationOption.none.rawValue
                return DurationOption(rawValue: raw) ?? .none
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Keys.visibilityDuration)
            }
        }
        
        
        // MARK: Ephemeral messages: existence duration
        
        static var existenceDuration: DurationOption {
            get {
                let raw = userDefaults.integerOrNil(forKey: Keys.existenceDuration) ?? DurationOption.none.rawValue
                return DurationOption(rawValue: raw) ?? .none
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Keys.existenceDuration)
            }
        }
        
        // MARK: Count based retention policy
        
        static var countBasedRetentionPolicyIsActive: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Keys.countBasedRetentionPolicyIsActive) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Keys.countBasedRetentionPolicyIsActive)
            }
        }
        
        static var countBasedRetentionPolicy: Int {
            get {
                return userDefaults.integerOrNil(forKey: Keys.countBasedRetentionPolicy) ?? 100
            }
            set {
                guard newValue >= 0 else { return }
                userDefaults.set(newValue, forKey: Keys.countBasedRetentionPolicy)
            }
        }
        
        // MARK: Time based retention policy
        
        static var timeBasedRetentionPolicy: DurationOptionAlt {
            get {
                let raw = userDefaults.integerOrNil(forKey: Keys.timeBasedRetentionPolicy) ?? DurationOptionAlt.none.rawValue
                return DurationOptionAlt(rawValue: raw) ?? .none
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Keys.timeBasedRetentionPolicy)
            }
        }
        
        // MARK: Ephemeral messages: auto read
        
        static var autoRead: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Keys.autoRead) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Keys.autoRead)
            }
        }
        
        // MARK: Ephemeral messages: auto read
        
        static var retainWipedOutboundMessages: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Keys.retainWipedOutboundMessages) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Keys.retainWipedOutboundMessages)
            }
        }
        
        
        // MARK: Notification Sounds
        
        static var notificationSound: NotificationSound? {
            get {
                guard let soundName = userDefaults.stringOrNil(forKey: Keys.notificationSound) else {
                    return nil
                }
                return NotificationSound.allCases.first { $0.identifier == soundName }
            }
            set {
                if let value = newValue, value != .system {
                    userDefaults.set(value.identifier, forKey: Keys.notificationSound)
                } else {
                    userDefaults.removeObject(forKey: Keys.notificationSound)
                }
            }
        }

        // MARK: Perform Interaction Donation

        static var performInteractionDonation: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Keys.performInteractionDonation) ?? true
            }
            set {
                userDefaults.set(newValue, forKey: Keys.performInteractionDonation)
                ObvMessengerSettingsNotifications.performInteractionDonationSettingDidChange.postOnDispatchQueue()
            }
        }
        
    }
    
    
    // MARK: - Privacy
    
    struct Privacy {
        
        struct Keys {
            static let localAuthenticationPolicy = "settings.privacy.localAuthenticationPolicy"
            static let lockScreenGracePeriod = "settings.privacy.lockScreenGracePeriod"
            static let hideNotificationContent = "settings.privacy.hideNotificationContent"
            
            static let passcodeHashAnsSalt = "settings.privacy.passcodeHashAndSalt"
            static let passcodeIsPassword = "settings.privacy.passcodeIsPassword"
            static let passcodeFailedCount = "settings.privacy.passcodeFailedCount"
            static let passcodeAttempsSessions = "settings.privacy.passcodeAttempsSessions"
            static let lockoutUptime = "settings.privacy.lockoutUptime"
            static let lockoutCleanEphemeral = "settings.privacy.lockoutCleanEphemeral"
            static let userHasBeenLockedOut = "settings.privacy.userHasBeenLockedOut"
        }
        
        // MARK: Local Authentication Policy
        
        static var localAuthenticationPolicy: LocalAuthenticationPolicy {
            get {
                guard let rawPolicy = userDefaults.integerOrNil(forKey: Keys.localAuthenticationPolicy) else {
                    return .none
                }
                guard let policy = LocalAuthenticationPolicy(rawValue: rawPolicy) else {
                    assertionFailure(); return .none
                }
                return policy
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Keys.localAuthenticationPolicy)
            }
        }
        
        // MARK: Passcode
        
        static var passcodeHashAndSalt: (Data, Data)? {
            get {
                guard let passcodeHashAndSaltAsString = userDefaults.stringOrNil(forKey: Keys.passcodeHashAnsSalt) else {
                    return nil
                }
                let components = passcodeHashAndSaltAsString.split(separator: " ")
                guard components.count == 2 else { return nil }
                let passcodeHashAsString = String(components[0])
                let passcodeSaltAsString = String(components[1])
                guard let passcodeHash = Data(base64Encoded: passcodeHashAsString) else { return nil }
                guard let passcodeSalt = Data(base64Encoded: passcodeSaltAsString) else { return nil }
                return (passcodeHash, passcodeSalt)
            }
            set {
                if let (passcodeHash, passcodeSalt) = newValue {
                    let passcodeHashAsString = passcodeHash.base64EncodedString()
                    let passcodeSaltAsString = passcodeSalt.base64EncodedString()
                    let passcodeHashAndSaltAsString = [passcodeHashAsString, passcodeSaltAsString].joined(separator: " ")
                    userDefaults.set(passcodeHashAndSaltAsString, forKey: Keys.passcodeHashAnsSalt)
                } else {
                    userDefaults.removeObject(forKey: Keys.passcodeHashAnsSalt)
                }
            }
        }
        
        static var passcodeIsPassword: Bool {
            get {
                userDefaults.boolOrNil(forKey: Keys.passcodeIsPassword) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Keys.passcodeIsPassword)
            }
        }
        
        /// Count the number of times a subset of the previous passcode was typed for the first time.
        /// 1) the user types "A",
        /// 2) then "B"  -> "AB"
        /// 3) then backslash -> "A", here "A" is a subset of "AB", we count on ``passcodeFailedCount``
        static var passcodeFailedCount: Int {
            get {
                userDefaults.integerOrNil(forKey: Keys.passcodeFailedCount) ?? 0
            }
            set {
                userDefaults.set(newValue, forKey: Keys.passcodeFailedCount)
            }
        }
        
        /// Count the number of first passcode tries, i.e. when the user open a passcode verification view controller and starts to type something
        static var passcodeAttempsSessions: Int {
            get {
                userDefaults.integerOrNil(forKey: Keys.passcodeAttempsSessions) ?? 0
            }
            set {
                userDefaults.set(newValue, forKey: Keys.passcodeAttempsSessions)
            }
        }
        
        static var passcodeAttemptCount: Int {
            // We remove 1 attempt, since we concider the first session as correct.
            passcodeFailedCount + passcodeAttempsSessions - 1
        }
        
        static var lockoutUptime: TimeInterval? {
            get {
                userDefaults.doubleOrNil(forKey: Keys.lockoutUptime)
            }
            set {
                userDefaults.set(newValue, forKey: Keys.lockoutUptime)
            }
        }
        
        static var lockoutCleanEphemeral: Bool {
            get {
                userDefaults.boolOrNil(forKey: Keys.lockoutCleanEphemeral) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Keys.lockoutCleanEphemeral)
            }
        }
        
        static var userHasBeenLockedOut: Bool {
            get {
                userDefaults.boolOrNil(forKey: Keys.userHasBeenLockedOut) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Keys.userHasBeenLockedOut)
            }
        }
        
        // MARK: Lock Screen Grace Period
        
        /// Possible grace periods (in seconds)
        static let gracePeriods: [TimeInterval] = [0, 5, 60, 60*5, 60*15, 60*60]
        
        static var lockScreenGracePeriod: TimeInterval {
            get {
                return userDefaults.doubleOrNil(forKey: Keys.lockScreenGracePeriod) ?? 0
            }
            set {
                userDefaults.set(newValue, forKey: Keys.lockScreenGracePeriod)
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
                let raw = userDefaults.integerOrNil(forKey: Keys.hideNotificationContent) ?? HideNotificationContentType.no.rawValue
                return HideNotificationContentType(rawValue: raw) ?? HideNotificationContentType.no
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Keys.hideNotificationContent)
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
        
        // MARK: - Announcing groups v2
        
        struct AnnouncingGroupsV2 {
            
            fileprivate struct Key {
                static let wasShownAndPermanentlyDismissedByUser = "settings.AnnouncingGroupsV2.wasShownAndPermanentlyDismissedByUser"
            }

            static var wasShownAndPermanentlyDismissedByUser: Bool {
                get {
                    return userDefaults.boolOrNil(forKey: Key.wasShownAndPermanentlyDismissedByUser) ?? false
                }
                set {
                    guard newValue != wasShownAndPermanentlyDismissedByUser else { return }
                    userDefaults.set(newValue, forKey: Key.wasShownAndPermanentlyDismissedByUser)
                }
            }
            
        }

        // Since this key is not used anymore, we only provide a way to remove it from the user defaults
        static func removeSecureCallsInBeta() {
            userDefaults.removeObject(forKey: "settings.alert.showSecureCallsInBeta")
        }
        
        static func resetAllAlerts() {
            removeSecureCallsInBeta()
            userDefaults.removeObject(forKey: AnnouncingGroupsV2.Key.wasShownAndPermanentlyDismissedByUser)
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
        
        static var preferredEmojisList: [String] {
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
    @Published fileprivate(set) var useOldListOfDiscussionsInterface: Bool
    
    private init() {
        defaultEmojiButton = ObvMessengerSettings.Emoji.defaultEmojiButton
        useOldListOfDiscussionsInterface = ObvMessengerSettings.Interface.useOldListOfDiscussionsInterface
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

    var getExtensionFailedToWipeAllEphemeralMessagesBeforeDate: Date? {
        return self.dateOrNil(forKey: ObvMessengerConstants.extensionFailedToWipeAllEphemeralMessagesBeforeDate)
    }

    func setExtensionFailedToWipeAllEphemeralMessagesBeforeDate(with date: Date?) {
        self.setValue(date, forKey: ObvMessengerConstants.extensionFailedToWipeAllEphemeralMessagesBeforeDate)
    }

}
