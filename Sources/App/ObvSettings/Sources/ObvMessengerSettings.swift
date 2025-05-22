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
import ObvDesignSystem
import ObvUserNotificationsSounds
import ObvAppCoreConstants


public struct ObvMessengerSettings {
    
    static public let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier)!
    static public let kSettingsKeyPath = "settings"
    
    public struct Downloads {
        
        // In bytes (-1 means unlimited)
        
        public static let byteSizes = [0, 1_000_000, 3_000_000, 5_000_000, 10_000_000, 20_000_000, 50_000_000, 100_000_000, -1]
        
        public static var maxAttachmentSizeForAutomaticDownload: Int {
            get {
                return userDefaults.integerOrNil(forKey: "settings.downloads.maxAttachmentSizeForAutomaticDownload") ?? 10_000_000
            }
            set {
                userDefaults.set(newValue, forKey: "settings.downloads.maxAttachmentSizeForAutomaticDownload")
            }
        }
    }
    
    public struct ContactsAndGroups {
        
        enum Key: String {
            case autoAcceptGroupInviteFrom = "autoAcceptGroupInviteFrom"
            case hideGroupMemberChangeMessages = "hideGroupMemberChangeMessages"
            
            private var kContactsAndGroups: String { "contacts.and.groups" }

            var path: String {
                [kSettingsKeyPath, kContactsAndGroups, self.rawValue].joined(separator: ".")
            }

        }
        
        public enum AutoAcceptGroupInviteFrom: String, CaseIterable, Sendable {
            case everyone = "everyone"
            case oneToOneContactsOnly = "contacts"
            case noOne = "nobody"
        }
        
        public private(set) static var autoAcceptGroupInviteFrom: AutoAcceptGroupInviteFrom {
            get {
                let raw = userDefaults.stringOrNil(forKey: Key.autoAcceptGroupInviteFrom.path) ?? AutoAcceptGroupInviteFrom.oneToOneContactsOnly.rawValue
                return AutoAcceptGroupInviteFrom(rawValue: raw) ?? .oneToOneContactsOnly
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Key.autoAcceptGroupInviteFrom.path)
            }
        }
        
        public static func setAutoAcceptGroupInviteFrom(to newValue: AutoAcceptGroupInviteFrom, changeMadeFromAnotherOwnedDevice: Bool) {
            guard newValue != autoAcceptGroupInviteFrom else { return }
            autoAcceptGroupInviteFrom = newValue
            ObvMessengerSettingsObservableObject.shared.autoAcceptGroupInviteFrom = (autoAcceptGroupInviteFrom, changeMadeFromAnotherOwnedDevice)
        }
        
        
        public static var hideGroupMemberChangeMessages: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.hideGroupMemberChangeMessages.path) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Key.hideGroupMemberChangeMessages.path)
                ObvMessengerSettingsObservableObject.shared.hideGroupMemberChangeMessages = newValue
            }
        }
        
    }
    
    public struct Interface {
        
        enum Key: String {
            case identityColorStyle = "identityColorStyle"
            case contactsSortOrder = "contactsSortOrder"
            case preferredComposeMessageViewActionsOrder = "preferredComposeMessageViewActionsOrder"
            case discussionLayoutType = "discussionLayoutType"
            case sendMessageShortcutType = "sendMessageShortcutType"
            case hideTrailingURLInMessagesWhenPreviewIsAvailable = "hideTrailingURLInMessagesWhenPreviewIsAvailable"
            
            private var kInterface: String { "interface" }
            
            var path: String {
                [kSettingsKeyPath, kInterface, self.rawValue].joined(separator: ".")
            }
            
        }
        
        
        public enum DiscussionLayoutType: Int, CaseIterable {
            case productionLayout
            case listLayout
        }
        
        
        public enum SendMessageShortcutType: Int, CaseIterable {
            case enter
            case commandEnter
        }
        
        
        public static var hideTrailingURLInMessagesWhenPreviewIsAvailable: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.hideTrailingURLInMessagesWhenPreviewIsAvailable.path) ?? true
            }
            set {
                userDefaults.set(newValue, forKey: Key.hideTrailingURLInMessagesWhenPreviewIsAvailable.path)
            }
        }
        
        
        public static var sendMessageShortcutType: SendMessageShortcutType {
            get {
                let raw = userDefaults.integerOrNil(forKey: Key.sendMessageShortcutType.path) ?? 0
                return SendMessageShortcutType(rawValue: raw) ?? SendMessageShortcutType.enter
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Key.sendMessageShortcutType.path)
                ObvMessengerSettingsObservableObject.shared.sendMessageShortcutType = newValue
            }
        }
        
        
        /// This setting, available when beta options are activated, allows to test different layouts of the collection view used for the single discussion view.
        public static var discussionLayoutType: DiscussionLayoutType {
            get {
                let raw = userDefaults.integerOrNil(forKey: Key.discussionLayoutType.path) ?? 0
                return DiscussionLayoutType(rawValue: raw) ?? DiscussionLayoutType.productionLayout
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Key.discussionLayoutType.path)
            }
        }

        
        public static var identityColorStyle: IdentityColorStyle {
            get {
                let raw = userDefaults.integerOrNil(forKey: Key.identityColorStyle.path) ?? 0
                return IdentityColorStyle(rawValue: raw) ?? IdentityColorStyle.hue
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Key.identityColorStyle.path)
                ObvMessengerSettingsNotifications.identityColorStyleDidChange.postOnDispatchQueue()
            }
        }

        
        public static var contactsSortOrder: ContactsSortOrder {
            get {
                let raw = userDefaults.integerOrNil(forKey: Key.contactsSortOrder.path) ?? ContactsSortOrder.byFirstName.rawValue
                return ContactsSortOrder(rawValue: raw) ?? ContactsSortOrder.byFirstName
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Key.contactsSortOrder.path)
                ObvMessengerSettingsNotifications.contactsSortOrderDidChange.postOnDispatchQueue()
            }
        }
        
        
        public static var preferredComposeMessageViewActionsOrder: [NewComposeMessageViewSortableAction] {
            get {
                guard let rawValues = userDefaults.array(forKey: Key.preferredComposeMessageViewActionsOrder.path) as? [Int] else { return NewComposeMessageViewSortableAction.defaultOrder }
                var actions = rawValues.compactMap({ NewComposeMessageViewSortableAction(rawValue: $0) })
                // Add missing actions
                let missingActions = NewComposeMessageViewSortableAction.defaultOrder.filter({ !actions.contains($0) })
                actions += missingActions
                return actions
            }
            set {
                let newRawValues = newValue.map({ $0.rawValue })
                userDefaults.set(newRawValues, forKey: Key.preferredComposeMessageViewActionsOrder.path)
                ObvMessengerSettingsNotifications.preferredComposeMessageViewActionsDidChange.postOnDispatchQueue()
            }
        }
        
    }
    
    public struct Discussions {
        
        private enum Key: String {
            
            case doSendReadReceipt = "doSendReadReceipt"
            case visibilityDuration = "visibilityDuration"
            case existenceDuration = "existenceDuration"
            case countBasedRetentionPolicyIsActive = "countBasedRetentionPolicyIsActive"
            case countBasedRetentionPolicy = "countBasedRetentionPolicy"
            case timeBasedRetentionPolicy = "timeBasedRetentionPolicy"
            case autoRead = "autoRead"
            case readOnce = "readOnce"
            case attachLinkPreviewToMessageSent = "attachLinkPreviewToMessageSent"
            case fetchMissingLinkPreviewFromMessageReceived = "fetchMissingLinkPreviewFromMessageReceived"
            case retainWipedOutboundMessages = "retainWipedOutboundMessages"
            case notificationSound = "notificationSound"
            case performInteractionDonation = "performInteractionDonation"
            case globalDiscussionNotificationsOptions = "globalNotificationsOptions"

            private var kDiscussions: String { "discussions" }
            
            var path: String {
                [kSettingsKeyPath, kDiscussions, self.rawValue].joined(separator: ".")
            }

        }
        
        
        // MARK: Read receipts
        
        public private(set) static var doSendReadReceipt: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.doSendReadReceipt.path) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Key.doSendReadReceipt.path)
            }
        }
        
        public static func setDoSendReadReceipt(to newValue: Bool, changeMadeFromAnotherOwnedDevice: Bool) {
            guard newValue != doSendReadReceipt else { return }
            self.doSendReadReceipt = newValue
            ObvMessengerSettingsObservableObject.shared.doSendReadReceipt = (doSendReadReceipt, changeMadeFromAnotherOwnedDevice)
        }
        
        
        // MARK: Rich link previews
        
        public enum FetchContentRichURLsMetadataChoice: Int, CaseIterable, Identifiable {
            case never = 0
            case withinSentMessagesOnly = 1
            case always = 2
            public var id: Int { rawValue }
        }

        // MARK: Attach link preview
        public static var attachLinkPreviewToMessageSent: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.attachLinkPreviewToMessageSent.path) ?? true
            }
            set {
                userDefaults.set(newValue, forKey: Key.attachLinkPreviewToMessageSent.path)
            }
        }
        
        public static var fetchMissingLinkPreviewFromMessageReceived: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.fetchMissingLinkPreviewFromMessageReceived.path) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Key.fetchMissingLinkPreviewFromMessageReceived.path)
            }
        }
        
        // MARK: Ephemeral messages: read once
        
        public static var readOnce: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.readOnce.path) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Key.readOnce.path)
            }
        }
        
        // MARK: Ephemeral messages: visibility duration
        
        public static var visibilityDuration: TimeInterval? {
            get {
                guard let raw = userDefaults.integerOrNil(forKey: Key.visibilityDuration.path) else { return nil }
                return TimeInterval(raw)
            }
            set {
                // We ensure that a value is always strictly positive. Otherwise,
                // we consider there is no visibility duration.
                if let newValue, newValue > 0  {
                    userDefaults.set(Int(newValue), forKey: Key.visibilityDuration.path)
                } else {
                    userDefaults.set(nil, forKey: Key.visibilityDuration.path)
                }
            }
        }
        
        
        // MARK: Ephemeral messages: existence duration
        
        public static var existenceDuration: TimeInterval? {
            get {
                guard let raw = userDefaults.integerOrNil(forKey: Key.existenceDuration.path) else { return nil }
                return TimeInterval(raw)
            }
            set {
                // We ensure that a value is always strictly positive. Otherwise,
                // we consider there is no existence duration.
                if let newValue, newValue > 0  {
                    userDefaults.set(Int(newValue), forKey: Key.existenceDuration.path)
                } else {
                    userDefaults.set(nil, forKey: Key.existenceDuration.path)
                }
            }
        }
        
        // MARK: Count based retention policy
        
        public static var countBasedRetentionPolicyIsActive: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.countBasedRetentionPolicyIsActive.path) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Key.countBasedRetentionPolicyIsActive.path)
            }
        }
        
        public static var countBasedRetentionPolicy: Int {
            get {
                return userDefaults.integerOrNil(forKey: Key.countBasedRetentionPolicy.path) ?? 100
            }
            set {
                guard newValue >= 0 else { return }
                userDefaults.set(newValue, forKey: Key.countBasedRetentionPolicy.path)
            }
        }
        
        // MARK: Time based retention policy
        
        public static var timeBasedRetentionPolicy: DurationOptionAlt {
            get {
                let raw = userDefaults.integerOrNil(forKey: Key.timeBasedRetentionPolicy.path) ?? DurationOptionAlt.none.rawValue
                return DurationOptionAlt(rawValue: raw) ?? .none
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Key.timeBasedRetentionPolicy.path)
            }
        }
        
        // MARK: Ephemeral messages: auto read
        
        public static var autoRead: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.autoRead.path) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Key.autoRead.path)
            }
        }
        
        // MARK: Ephemeral messages: auto read
        
        public static var retainWipedOutboundMessages: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.retainWipedOutboundMessages.path) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Key.retainWipedOutboundMessages.path)
            }
        }
        
        
        // MARK: Notification Sounds
        
        public static var notificationSound: NotificationSound? {
            get {
                guard let soundName = userDefaults.stringOrNil(forKey: Key.notificationSound.path) else {
                    return nil
                }
                return NotificationSound.allCases.first { $0.identifier == soundName }
            }
            set {
                if let value = newValue, value != .system {
                    userDefaults.set(value.identifier, forKey: Key.notificationSound.path)
                } else {
                    userDefaults.removeObject(forKey: Key.notificationSound.path)
                }
            }
        }

        // MARK: Perform Interaction Donation

        public static var performInteractionDonation: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.performInteractionDonation.path) ?? true
            }
            set {
                userDefaults.set(newValue, forKey: Key.performInteractionDonation.path)
                ObvMessengerSettingsNotifications.performInteractionDonationSettingDidChange.postOnDispatchQueue()
                ObvMessengerSettingsObservableObject.shared.performInteractionDonation = newValue
            }
        }
        
        // MARK: Global notification options related to discussions

        /// List of global notification options related to discussions
        ///
        /// - allowMentionedNotificationWhenDiscussionMuted: Allow notifications when mentioned within a discussion
        public struct NotificationOptions: OptionSet {
            
            /// If we don't have any value that is set, this contains the defaults
            fileprivate static let defaultValue: Self = [.alwaysNotifyWhenMentionnedEvenInMutedDiscussion]
            
            /// Allow notifications when mentioned within a discussion
            public static let alwaysNotifyWhenMentionnedEvenInMutedDiscussion: Self = .init(rawValue: 1 << 0)

            public let rawValue: Int16

            public init(rawValue: Int16) {
                self.rawValue = rawValue
            }
        }

        public static var notificationOptions: NotificationOptions {
            get {
                guard userDefaults.object(forKey: Key.globalDiscussionNotificationsOptions.path) != nil else {
                    return .defaultValue
                }
                return .init(rawValue: Int16(userDefaults.integer(forKey: Key.globalDiscussionNotificationsOptions.path)))
            }
            set {
                if newValue == .defaultValue {
                    userDefaults.set(nil, forKey: Key.globalDiscussionNotificationsOptions.path)
                } else {
                    userDefaults.set(newValue.rawValue, forKey: Key.globalDiscussionNotificationsOptions.path)
                }
            }
        }
        
    }
    
    
    // MARK: - Privacy
    
    public struct Privacy {
        
        enum Key: String {
            case localAuthenticationPolicy = "localAuthenticationPolicy"
            case lockScreenGracePeriod = "lockScreenGracePeriod"
            case hideNotificationContent = "hideNotificationContent"
            
            case hiddenProfileClosePolicy = "hiddenProfileClosePolicy"
            case timeIntervalForBackgroundHiddenProfileClosePolicy = "timeIntervalForBackgroundHiddenProfileClosePolicy"

            case passcodeHashAnsSalt = "passcodeHashAndSalt"
            case passcodeIsPassword = "passcodeIsPassword"
            case passcodeFailedCount = "passcodeFailedCount"
            case passcodeAttempsSessions = "passcodeAttempsSessions"
            case lockoutUptime = "lockoutUptime"
            case lockoutCleanEphemeral = "lockoutCleanEphemeral"
            case userHasBeenLockedOut = "userHasBeenLockedOut"
            
            private var kPrivacy: String { "privacy" }
            
            var path: String {
                [kSettingsKeyPath, kPrivacy, self.rawValue].joined(separator: ".")
            }

        }
        
        // MARK: Hidden profile close policy
        
        public enum HiddenProfileClosePolicy: Int, CaseIterable {
            case manualSwitching = 0
            case screenLock = 1
            case background = 2
        }
        
        public enum TimeIntervalForBackgroundHiddenProfileClosePolicy: TimeInterval, CaseIterable {
            case immediately = 0
            case tenSeconds = 10
            case thirtySeconds = 30
            case oneMinute = 60
            case twoMinutes = 120
            case fiveMinutes = 300
            public var timeInterval: TimeInterval {
                rawValue
            }
        }
        
        public static var hiddenProfileClosePolicy: HiddenProfileClosePolicy {
            get {
                guard let raw = userDefaults.integerOrNil(forKey: Key.hiddenProfileClosePolicy.path) else { return .manualSwitching }
                return HiddenProfileClosePolicy.init(rawValue: raw) ?? .manualSwitching
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Key.hiddenProfileClosePolicy.path)
            }
        }
        
        public static var timeIntervalForBackgroundHiddenProfileClosePolicy: TimeIntervalForBackgroundHiddenProfileClosePolicy {
            get {
                guard let raw = userDefaults.doubleOrNil(forKey: Key.timeIntervalForBackgroundHiddenProfileClosePolicy.path) else { return .immediately }
                return TimeIntervalForBackgroundHiddenProfileClosePolicy.init(rawValue: raw) ?? .immediately
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Key.timeIntervalForBackgroundHiddenProfileClosePolicy.path)
            }
        }
        
        public static var hiddenProfileClosePolicyHasYetToBeSet: Bool {
            return userDefaults.integerOrNil(forKey: Key.hiddenProfileClosePolicy.path) == nil
        }
        
        // MARK: Local Authentication Policy
        
        public static var localAuthenticationPolicy: ObvLocalAuthenticationPolicy {
            get {
                guard let rawPolicy = userDefaults.integerOrNil(forKey: Key.localAuthenticationPolicy.path) else {
                    return .none
                }
                guard let policy = ObvLocalAuthenticationPolicy(rawValue: rawPolicy) else {
                    assertionFailure(); return .none
                }
                return policy
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Key.localAuthenticationPolicy.path)
            }
        }
        
        // MARK: Passcode
        
        public static var passcodeHashAndSalt: (Data, Data)? {
            get {
                guard let passcodeHashAndSaltAsString = userDefaults.stringOrNil(forKey: Key.passcodeHashAnsSalt.path) else {
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
                    userDefaults.set(passcodeHashAndSaltAsString, forKey: Key.passcodeHashAnsSalt.path)
                } else {
                    userDefaults.removeObject(forKey: Key.passcodeHashAnsSalt.path)
                }
            }
        }
        
        public static var passcodeIsPassword: Bool {
            get {
                userDefaults.boolOrNil(forKey: Key.passcodeIsPassword.path) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Key.passcodeIsPassword.path)
            }
        }
        
        /// Count the number of times a subset of the previous passcode was typed for the first time.
        /// 1) the user types "A",
        /// 2) then "B"  -> "AB"
        /// 3) then backslash -> "A", here "A" is a subset of "AB", we count on ``passcodeFailedCount``
        public static var passcodeFailedCount: Int {
            get {
                userDefaults.integerOrNil(forKey: Key.passcodeFailedCount.path) ?? 0
            }
            set {
                userDefaults.set(newValue, forKey: Key.passcodeFailedCount.path)
            }
        }
        
        /// Count the number of first passcode tries, i.e. when the user open a passcode verification view controller and starts to type something
        public static var passcodeAttempsSessions: Int {
            get {
                userDefaults.integerOrNil(forKey: Key.passcodeAttempsSessions.path) ?? 0
            }
            set {
                userDefaults.set(newValue, forKey: Key.passcodeAttempsSessions.path)
            }
        }
        
        public static var passcodeAttemptCount: Int {
            // We remove 1 attempt, since we concider the first session as correct.
            passcodeFailedCount + passcodeAttempsSessions - 1
        }
        
        public static var lockoutUptime: TimeInterval? {
            get {
                userDefaults.doubleOrNil(forKey: Key.lockoutUptime.path)
            }
            set {
                userDefaults.set(newValue, forKey: Key.lockoutUptime.path)
            }
        }
        
        public static var lockoutCleanEphemeral: Bool {
            get {
                userDefaults.boolOrNil(forKey: Key.lockoutCleanEphemeral.path) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Key.lockoutCleanEphemeral.path)
            }
        }
        
        public static var userHasBeenLockedOut: Bool {
            get {
                userDefaults.boolOrNil(forKey: Key.userHasBeenLockedOut.path) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Key.userHasBeenLockedOut.path)
            }
        }
        
        // MARK: Lock Screen Grace Period
        
        /// Possible grace periods (in seconds)
        public static let gracePeriods: [TimeInterval] = [0, 5, 60, 60*5, 60*15, 60*60]
        
        public static var lockScreenGracePeriod: TimeInterval {
            get {
                return userDefaults.doubleOrNil(forKey: Key.lockScreenGracePeriod.path) ?? 0
            }
            set {
                userDefaults.set(newValue, forKey: Key.lockScreenGracePeriod.path)
            }
        }
        
        // MARK: Hide notification content
        
        public enum HideNotificationContentType: Int {
            case no = 0
            case partially = 1
            case completely = 2
        }
        
        public static var hideNotificationContent: HideNotificationContentType {
            get {
                let raw = userDefaults.integerOrNil(forKey: Key.hideNotificationContent.path) ?? HideNotificationContentType.no.rawValue
                return HideNotificationContentType(rawValue: raw) ?? HideNotificationContentType.no
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Key.hideNotificationContent.path)
            }
        }
        
    }
    
    
    // MARK: - Backup
    
    public struct Backup {
        
        enum Key: String {
            // Legacy backups
            case isAutomaticBackupEnabled = "isAutomaticBackupEnabled"
            case isAutomaticCleaningBackupEnabled = "isAutomaticCleaningBackupEnabled"
            // New backups
            case userDidSetupBackupsAtLeastOnce = "userDidSetupBackupsAtLeastOnce"
            case dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey = "dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey"
            
            private var kBackup: String { "backup" }
            
            var path: String {
                [kSettingsKeyPath, kBackup, self.rawValue].joined(separator: ".")
            }

        }

        /// For legacy backups
        public static var isAutomaticBackupEnabled: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.isAutomaticBackupEnabled.path) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Key.isAutomaticBackupEnabled.path)
            }
        }
        
        /// For legacy backups
        public static var isAutomaticCleaningBackupEnabled: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.isAutomaticCleaningBackupEnabled.path) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Key.isAutomaticCleaningBackupEnabled.path)
            }
        }
        
        
        // For new backups
        public static var userDidSetupBackupsAtLeastOnce: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.userDidSetupBackupsAtLeastOnce.path) ?? false
            }
            set {
                guard newValue else { assertionFailure("Once true, this setting cannot be turned back to false"); return }
                userDefaults.set(newValue, forKey: Key.userDidSetupBackupsAtLeastOnce.path)
                ObvMessengerSettingsObservableObject.shared.userDidSetupBackupsAtLeastOnce = newValue
            }
        }
        
        
        public static var dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey: Date? {
            get {
                return userDefaults.dateOrNil(forKey: Key.dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey.path)
            }
            set {
                userDefaults.set(newValue, forKey: Key.dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey.path)
                ObvMessengerSettingsObservableObject.shared.dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey = newValue
            }
        }
        
    }
    
    
    // MARK: - VoIP
    
    public struct VoIP {
        
        enum Key: String {
            case receiveCallsOnThisDevice = "receiveCallsOnThisDevice"
            case videoSendResolution = "videoSendResolution"
            
            private var kVoIP: String { "voip" }
            
            var path: String {
                [kSettingsKeyPath, kVoIP, self.rawValue].joined(separator: ".")
            }

        }

        
        public static var receiveCallsOnThisDevice: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.receiveCallsOnThisDevice.path) ?? true
            }
            set {
                guard newValue != receiveCallsOnThisDevice else { return }
                userDefaults.set(newValue, forKey: Key.receiveCallsOnThisDevice.path)
                ObvMessengerSettingsNotifications.receiveCallsOnThisDeviceSettingDidChange
                    .postOnDispatchQueue()
            }
        }
        
        
        public static var isIncludesCallsInRecentsEnabled: Bool {
            get {
                guard !ObvUICoreDataConstants.targetEnvironmentIsMacCatalyst else { return false }
                return userDefaults.boolOrNil(forKey: "settings.voip.isIncludesCallsInRecentsEnabled") ?? true
            }
            set {
                assert(!ObvUICoreDataConstants.targetEnvironmentIsMacCatalyst)
                guard newValue != isIncludesCallsInRecentsEnabled else { return }
                userDefaults.set(newValue, forKey: "settings.voip.isIncludesCallsInRecentsEnabled")
                ObvMessengerSettingsNotifications.isIncludesCallsInRecentsEnabledSettingDidChange
                    .postOnDispatchQueue()
            }
        }
        
        
        public static let maxaveragebitratePossibleValues: [Int?] = [nil, 8_000, 16_000, 24_000, 32_000]
        
        
        // See https://datatracker.ietf.org/doc/html/draft-spittka-payload-rtp-opus
        public static var maxaveragebitrate: Int? {
            get {
                return userDefaults.integerOrNil(forKey: "settings.voip.maxaveragebitrate")
            }
            set {
                guard newValue != maxaveragebitrate else { return }
                userDefaults.set(newValue, forKey: "settings.voip.maxaveragebitrate")
            }
        }
        
        
        public enum VideoSendResolution: Int, CaseIterable {
            case fullHigh1080 = 1080
            case high720 = 720
            case standard480 = 480
            case low360 = 360
        }
        
        
        public static var videoSendResolution: VideoSendResolution {
            get {
                let rawValue = userDefaults.integerOrNil(forKey: Key.videoSendResolution.path) ?? VideoSendResolution.fullHigh1080.rawValue
                    return VideoSendResolution(rawValue: rawValue) ?? .fullHigh1080
            }
            set {
                guard newValue != videoSendResolution else { return }
                userDefaults.set(newValue.rawValue, forKey: Key.videoSendResolution.path)
            }
        }

        
    }
    
    // MARK: - Alerts
    
    public struct Alert {
        
        // Since this key is not used anymore, we only provide a way to remove it from the user defaults
        public static func removeSecureCallsInBeta() {
            userDefaults.removeObject(forKey: "settings.alert.showSecureCallsInBeta")
        }
        
        public static func resetAllAlerts() {
            removeSecureCallsInBeta()
        }
        
    }
    
    // MARK: - Subscriptions
    
    public struct Subscription {
        
        public static var allowAPIKeyActivationWithBadKeyStatus: Bool {
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
    
    public struct Advanced {
        
        fileprivate struct Key {
            static let allowCustomKeyboards = "settings.advanced.allowCustomKeyboards"
            static let enableRunningLogs = "settings.advanced.enableRunningLogs"
        }

        public static var allowCustomKeyboards: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.allowCustomKeyboards) ?? true
            }
            set {
                guard newValue != allowCustomKeyboards else { return }
                userDefaults.set(newValue, forKey: Key.allowCustomKeyboards)
            }
        }

        public static var enableRunningLogs: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.enableRunningLogs) ?? false
            }
            set {
                guard newValue != enableRunningLogs else { return }
                userDefaults.set(newValue, forKey: Key.enableRunningLogs)
            }
        }

    }
    
    
    // MARK: - Access to advanced settings / beta config (for non TestFlight users)
    
    public struct BetaConfiguration {
        
        public static var showBetaSettings: Bool {
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

    public struct Emoji {

        private struct Keys {
            static let preferredEmojisList = "settings.preferredEmojisList"
            static let defaultEmojiButton = "settings.defaultEmojiButton"
        }
        
        public static var preferredEmojisList: [String] {
            get {
                return userDefaults.stringArray(forKey: Keys.preferredEmojisList) ?? []
            }
            set {
                guard newValue != preferredEmojisList else { return }
                userDefaults.set(newValue, forKey: Keys.preferredEmojisList)
                ObvMessengerSettingsObservableObject.shared.preferredEmojisList = preferredEmojisList
            }
        }
        
        public static let defaultPreferredEmojisList: [String] = ["♥️", "👍", "😉", "😎", "🤩", "😱", "😊", "🎉"]
        
        public static var defaultEmojiButton: String? {
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
    
    public struct MDM {
        
        private struct Key {
            static let mdmConfigurationKey = "com.apple.configuration.managed"
        }
        
        private static let standardUserDefaults = UserDefaults.standard
        public static var configuration: [String: Any]? { standardUserDefaults.dictionary(forKey: Key.mdmConfigurationKey) }
        
        public static var isConfiguredFromMDM: Bool {
            configuration != nil
        }
        
        public struct Configuration {
            
            private struct Key {
                static let URI = "keycloak_configuration_uri"
            }
            
            public static var uri: URL? {
                guard let mdmConfiguration = MDM.configuration else { return nil }
                guard let rawValue = mdmConfiguration[Key.URI] else { assertionFailure(); return nil }
                guard let stringValue = rawValue as? String else { assertionFailure(); return nil }
                guard let value = URL(string: stringValue) else { assertionFailure(); return nil }
                return value
            }
            
        }
        
    }
    
    // MARK: - Minimum and latest iOS App versions sent by the server
    
    public struct AppVersionAvailable {
        
        private struct Key {
            static let minimum = "settings.AppVersionAvailable.minimum"
            static let latest = "settings.AppVersionAvailable.latest"
        }
        
        /// This corresponds to the minimum acceptable iOS build version returned by the server when querying the well known point.
        public static var minimum: Int? {
            get {
                return userDefaults.integerOrNil(forKey: Key.minimum)
            }
            set {
                guard newValue != minimum else { return }
                userDefaults.set(newValue, forKey: Key.minimum)
            }
        }
        
        /// This corresponds to the latest acceptable iOS build version returned by the server when querying the well known point.
        public static var latest: Int? {
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


// MARK: - ObvMessengerPreferredEmojisListObservable

public final class ObvMessengerPreferredEmojisListObservable: ObservableObject {

    public init() {}
    
    @Published public var emojis: [String] = ObvMessengerSettings.Emoji.preferredEmojisList {
        didSet {
            ObvMessengerSettings.Emoji.preferredEmojisList = emojis
        }
    }
    
}

/// This singleton makes it possible to observe certain changes made to the settings.

public final class ObvMessengerSettingsObservableObject: ObservableObject {
    
    public static let shared = ObvMessengerSettingsObservableObject()

    @Published public fileprivate(set) var defaultEmojiButton: String?
    @Published public fileprivate(set) var preferredEmojisList: [String]
    @Published public fileprivate(set) var doSendReadReceipt: (doSendReadReceipt: Bool, changeMadeFromAnotherOwnedDevice: Bool)
    @Published public fileprivate(set) var autoAcceptGroupInviteFrom: (autoAcceptGroupInviteFrom: ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom, changeMadeFromAnotherOwnedDevice: Bool)
    @Published public fileprivate(set) var hideGroupMemberChangeMessages: Bool
    @Published public fileprivate(set) var sendMessageShortcutType: ObvMessengerSettings.Interface.SendMessageShortcutType
    @Published public fileprivate(set) var performInteractionDonation: Bool
    @Published public fileprivate(set) var userDidSetupBackupsAtLeastOnce: Bool
    @Published public fileprivate(set) var dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey: Date?
    
    private init() {
        defaultEmojiButton = ObvMessengerSettings.Emoji.defaultEmojiButton
        preferredEmojisList = ObvMessengerSettings.Emoji.preferredEmojisList
        doSendReadReceipt = (ObvMessengerSettings.Discussions.doSendReadReceipt, false)
        autoAcceptGroupInviteFrom = (ObvMessengerSettings.ContactsAndGroups.autoAcceptGroupInviteFrom, false)
        hideGroupMemberChangeMessages = ObvMessengerSettings.ContactsAndGroups.hideGroupMemberChangeMessages
        sendMessageShortcutType = ObvMessengerSettings.Interface.sendMessageShortcutType
        performInteractionDonation = ObvMessengerSettings.Discussions.performInteractionDonation
        userDidSetupBackupsAtLeastOnce = ObvMessengerSettings.Backup.userDidSetupBackupsAtLeastOnce
        dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey = ObvMessengerSettings.Backup.dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey
    }
    
}

public extension UserDefaults {

    func addObjectsModifiedByShareExtension(_ urlsAndEntityName: [(URL, String)]) {
        var dict = dictionary(forKey: ObvUICoreDataConstants.SharedUserDefaultsKey.objectsModifiedByShareExtension.rawValue) ?? [:]
        for (url, entityName) in urlsAndEntityName {
            dict[url.absoluteString] = entityName
        }
        set(dict, forKey: ObvUICoreDataConstants.SharedUserDefaultsKey.objectsModifiedByShareExtension.rawValue)
    }

    func resetObjectsModifiedByShareExtension() {
        removeObject(forKey: ObvUICoreDataConstants.SharedUserDefaultsKey.objectsModifiedByShareExtension.rawValue)
    }

    var objectsModifiedByShareExtensionURLAndEntityName: [(URL, String)] {
        guard let dict = dictionary(forKey: ObvUICoreDataConstants.SharedUserDefaultsKey.objectsModifiedByShareExtension.rawValue) else {
            return []
        }
        return dict.compactMap { (urlAsString, entityNameAsAny) in
            guard let url = URL(string: urlAsString) else { return nil }
            guard let entityName = entityNameAsAny as? String else { return nil }
            return (url, entityName)
        }
    }

    var getExtensionFailedToWipeAllEphemeralMessagesBeforeDate: Date? {
        return self.dateOrNil(forKey: ObvUICoreDataConstants.SharedUserDefaultsKey.extensionFailedToWipeAllEphemeralMessagesBeforeDate.rawValue)
    }

    func setExtensionFailedToWipeAllEphemeralMessagesBeforeDate(with date: Date?) {
        self.setValue(date, forKey: ObvUICoreDataConstants.SharedUserDefaultsKey.extensionFailedToWipeAllEphemeralMessagesBeforeDate.rawValue)
    }

}



// MARK: - For snapshot purposes

public extension ObvMessengerSettings {
    
    static var syncSnapshotNode: GlobalSettingsSyncSnapshotNode {
        .init(
            autoAcceptGroupInviteFrom: ContactsAndGroups.autoAcceptGroupInviteFrom,
            doSendReadReceipt: Discussions.doSendReadReceipt)
    }
    
}


public struct GlobalSettingsSyncSnapshotNode: ObvSyncSnapshotNode {

    private let domain: Set<CodingKeys>
    private let autoAcceptGroupInviteFrom: ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom?
    private let doSendReadReceipt: Bool?
    
    public let id = Self.generateIdentifier()

    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case autoAcceptGroupInviteFrom = "auto_join_groups"
        case doSendReadReceipt = "send_read_receipt"
        case domain = "domain"
    }

    private static let defaultDomain = Set(CodingKeys.allCases.filter({ $0 != .domain }))

    
    init(autoAcceptGroupInviteFrom: ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom, doSendReadReceipt: Bool) {
        self.autoAcceptGroupInviteFrom = autoAcceptGroupInviteFrom
        self.doSendReadReceipt = doSendReadReceipt
        self.domain = Self.defaultDomain
    }
    
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(domain, forKey: .domain)
        try container.encodeIfPresent(autoAcceptGroupInviteFrom?.rawValue, forKey: .autoAcceptGroupInviteFrom)
        try container.encodeIfPresent(doSendReadReceipt, forKey: .doSendReadReceipt)
    }
    
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rawKeys = try values.decode(Set<String>.self, forKey: .domain)
        self.domain = Set(rawKeys.compactMap({ CodingKeys(rawValue: $0) }))
        if let rawAutoAcceptGroupInviteFrom = try values.decodeIfPresent(String.self, forKey: .autoAcceptGroupInviteFrom),
           let _autoAcceptGroupInviteFrom = ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom(rawValue: rawAutoAcceptGroupInviteFrom) {
            self.autoAcceptGroupInviteFrom = _autoAcceptGroupInviteFrom
        } else {
            self.autoAcceptGroupInviteFrom = nil
        }
        self.doSendReadReceipt = try values.decodeIfPresent(Bool.self, forKey: .doSendReadReceipt)
    }
    
    public func useToUpdateGlobalSettings() {
        
        if domain.contains(.autoAcceptGroupInviteFrom), let autoAcceptGroupInviteFrom {
            ObvMessengerSettings.ContactsAndGroups.setAutoAcceptGroupInviteFrom(to: autoAcceptGroupInviteFrom, changeMadeFromAnotherOwnedDevice: false)
        }
        
        if domain.contains(.doSendReadReceipt), let doSendReadReceipt {
            ObvMessengerSettings.Discussions.setDoSendReadReceipt(to: doSendReadReceipt, changeMadeFromAnotherOwnedDevice: false)
        }
        
    }
    
    enum ObvError: Error {
        case couldNotDeserializeAutoAcceptGroupInvite
    }
    
}
