/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvAppTypes


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
            ObvMessengerSettingsObservableObject.onTheMainThread {
                ObvMessengerSettingsObservableObject.shared.autoAcceptGroupInviteFrom = (autoAcceptGroupInviteFrom, changeMadeFromAnotherOwnedDevice)
            }
        }
        
        
        public static var hideGroupMemberChangeMessages: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.hideGroupMemberChangeMessages.path) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Key.hideGroupMemberChangeMessages.path)
                ObvMessengerSettingsObservableObject.onTheMainThread {
                    ObvMessengerSettingsObservableObject.shared.hideGroupMemberChangeMessages = newValue
                }
            }
        }
        
    }
    
    public struct Interface {
        
        enum Key: String {
            case contactsSortOrder = "contactsSortOrder"
            case discussionLayoutType = "discussionLayoutType"
            case sentBubbleHueVariesWithScroll = "sentBubbleHueVariesWithScroll"
            case elasticScrollingChosenByTheReader = "elasticScrollingChosenByTheReader"
            case sendMessageShortcutType = "sendMessageShortcutType"
            case hideTrailingURLInMessagesWhenPreviewIsAvailable = "hideTrailingURLInMessagesWhenPreviewIsAvailable"
            case shortenIntroductoryMessage = "shortenIntroductoryMessage"
            
            private var kInterface: String { "interface" }
            
            var path: String {
                [kSettingsKeyPath, kInterface, self.rawValue].joined(separator: ".")
            }
            
        }
        
        
        public enum DiscussionLayoutType: Int, CaseIterable {
            case productionLayout
            /// Entry point of the new, full SwiftUI implementation of the single discussion screen. Keeps the raw value previously used by the
            /// (now removed) list layout, so that a beta tester who selected it lands on the SwiftUI screen.
            case swiftUI
        }
        
        
        public enum SendMessageShortcutType: Int, CaseIterable {
            case enter
            case commandEnter
        }
        
        
        public static var shortenIntroductoryMessage: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.shortenIntroductoryMessage.path) ?? false
            }
            set {
                userDefaults.set(newValue, forKey: Key.shortenIntroductoryMessage.path)
            }
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
                ObvMessengerSettingsObservableObject.onTheMainThread {
                    ObvMessengerSettingsObservableObject.shared.sendMessageShortcutType = newValue
                }
            }
        }
        
        
        /// Which single discussion screen the reader gets.
        ///
        /// **Three rules, and they are all here rather than at the point the screen is built** — a second gate beside `ObvFlowController` would be
        /// two places that can disagree about one question.
        ///
        /// - **Below iOS 18 the answer is always the production screen**, whatever is stored. Step 46f declined iOS 17 on evidence rather than on
        ///   difficulty: every iPhone that runs 17 runs 18, so the whole of that support is three iPads and two MacBook Airs, against a
        ///   touch-panning defect that exists only there.
        /// - **On iOS 18 and above, nothing stored means the SwiftUI screen.** It is the default rather than the opt-in.
        /// - **A value that *is* stored is obeyed**, which is why this reads the defaults as an optional rather than falling back to `0`. Written
        ///   the old way, a reader who deliberately chose the production screen was indistinguishable from one who had never opened the setting,
        ///   and flipping the default would have silently carried them forward again.
        ///
        /// The row that writes it appears only under `showExperimentalFeature` — a development build, TestFlight, or a reader who has activated
        /// beta settings — so in the ordinary App Store build this is a version check and nothing else.
        /// Whether this reader may be *offered* the choice at all.
        ///
        /// **The one place that names the version**, so the setting and the row that writes it cannot disagree about who gets which screen. Below
        /// iOS 18 the answer is no, and the row must not be shown: ``discussionLayoutType`` would go on answering `.productionLayout` while a
        /// pull-down button with `changesSelectionAsPrimaryAction` adopted the selection on its own and displayed *SwiftUI* — a control showing a
        /// value the app does not have.
        public static var discussionLayoutTypeCanBeChosen: Bool {
            if #available(iOS 18.0, *) { return true } else { return false }
        }


        public static var discussionLayoutType: DiscussionLayoutType {
            get {
                guard discussionLayoutTypeCanBeChosen else { return .productionLayout }
                guard let raw = userDefaults.integerOrNil(forKey: Key.discussionLayoutType.path),
                      let storedValue = DiscussionLayoutType(rawValue: raw) else {
                    return .swiftUI
                }
                return storedValue
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Key.discussionLayoutType.path)
            }
        }


        /// Whether a message the reader sent is drawn in a blue that shifts a little with where the bubble sits on the screen, so that scrolling moves the colour
        /// through the discussion.
        ///
        /// **On by default from iOS 26, off before.** See ``sentBubbleHueVariesWithScrollWhenTheReaderHasNotSaid``. The switch is at Settings ▸ Interface ▸
        /// Scrolling effects, shown to every reader rather than among the beta options. It applies to the SwiftUI screen alone; **off gives exactly what is in
        /// production**, which makes it a usable way back rather than a second look to maintain.
        ///
        /// **One field across the transcript, not one colour per bubble, since 2026-09-04.** It filled each bubble with a single colour taken from that bubble's
        /// midpoint, so a tall message was flat and the short one under it jumped; it now samples the field at both edges and cross-fades. That made the effect
        /// about twice as strong at an unchanged amplitude.
        ///
        /// It was off by default while it was an experiment in how that screen looks. **Its cost is accepted rather than known** — decided 2026-08-30.
        /// It is a per-frame consumer, its price on a device has never been measured, and it is not going to be before the first version: a simulator
        /// reports a Mac's frame times, so it can say the effect is correct and not that it is free, and a device walk was judged not worth the delay.
        ///
        /// **It is no longer the only per-frame consumer on this screen**, ``elasticScrolling`` having shipped beside it on 2026-08-30, and the two
        /// are unmeasured together. So a dropped frame reported here cannot be attributed to either without switching *both* off and adding them back
        /// one at a time — which was the precondition this acceptance was written against, now met rather than hypothetical. Both switches are in
        /// Settings ▸ Interface ▸ Scrolling effects, which at least makes that experiment something a reader can perform.
        ///
        /// Read when a discussion screen is created, so changing it shows on the next discussion opened rather than on the one behind the settings.
        public static var sentBubbleHueVariesWithScroll: Bool {
            get {
                userDefaults.boolOrNil(forKey: Key.sentBubbleHueVariesWithScroll.path) ?? sentBubbleHueVariesWithScrollWhenTheReaderHasNotSaid
            }
            set {
                userDefaults.set(newValue, forKey: Key.sentBubbleHueVariesWithScroll.path)
            }
        }


        /// The answer for a reader who has never touched the switch. **On from iOS 26 (macOS 26 on a Mac), off before.** The version stands in for how recent
        /// the device is, and a per-frame effect costs most on an older device. A stored value is obeyed whatever the version.
        private static var sentBubbleHueVariesWithScrollWhenTheReaderHasNotSaid: Bool {
            if #available(iOS 26.0, *) { return true } else { return false }
        }


        /// The answer for a reader who has never touched the switch. **Off on a Mac. On an iPhone or an iPad, on from iOS 27 only.** The version stands in for
        /// how recent the device is: the effect updates every message on screen at every frame of a scroll, which costs most on an older device. See
        /// ``elasticScrolling``.
        private static var elasticScrollingWhenTheReaderHasNotSaid: Bool {
            #if targetEnvironment(macCatalyst)
            return false
            #else
            if #available(iOS 27.0, *) { return true } else { return false }
            #endif
        }


        /// Whether the messages lag a little behind the reader's finger as the transcript is scrolled, and settle when it stops.
        ///
        /// **On by default from iOS 27, off before it and on a Mac.** See ``elasticScrollingWhenTheReaderHasNotSaid``. The model is the one of WWDC 2013
        /// session 217: each message hangs from its anchor by a zero-length spring, and resists in proportion to its distance from the finger.
        ///
        /// **The Mac default is a judgement about a pointer, not about the effect.** TestFlight readers liked it on iOS; on a Mac, with a mouse or a trackpad,
        /// it was not good, and which of the two is not established. Tuning it was not affordable before shipping, so the default stands down there instead.
        ///
        /// **A stored value is obeyed on both**, which is why this reads the defaults as an optional rather than falling back to a literal: a Mac reader who
        /// turns the switch on is obeyed for ever after, and so is an iOS reader who turns it off. That distinction is also why the key changed name on
        /// 2026-09-04 — every TestFlight reader had a stored `true` they had never chosen, and honouring it would have carried the whole of them forward with
        /// the effect running. The old `settings.interface.elasticScrolling` is deleted at launch by `AppMainManager.migrationToV4_4()`.
        ///
        /// **Off entirely when the reader has asked for less movement**, and that is decided where the effect runs rather than here. The settings screen only
        /// *reports* that state — greying its rows and saying why — so that a mistake in the screen can never leave the effect running for somebody who asked
        /// for it to stop, and so the two answers cannot disagree about which is right.
        ///
        /// Read when a discussion screen is created, so changing it shows on the next discussion opened rather than on the one behind the settings.
        public static var elasticScrolling: Bool {
            get {
                userDefaults.boolOrNil(forKey: Key.elasticScrollingChosenByTheReader.path) ?? elasticScrollingWhenTheReaderHasNotSaid
            }
            set {
                userDefaults.set(newValue, forKey: Key.elasticScrollingChosenByTheReader.path)
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
        
        

        
    }
    
    public struct ContactsSuggestions {

        private enum Key: String {
            case onboardingWasShown = "onboardingWasShown"
            case profilesWhoseEntryIsShown = "profilesWhoseEntryIsShown"

            private var kContactsSuggestions: String { "contactsSuggestions" }

            var path: String {
                [kSettingsKeyPath, kContactsSuggestions, self.rawValue].joined(separator: ".")
            }
        }

        /// Whether the onboarding shown the first time the suggestions are opened has been shown already, on this device.
        public static var onboardingWasShown: Bool {
            get { userDefaults.boolOrNil(forKey: Key.onboardingWasShown.path) ?? false }
            set { userDefaults.set(newValue, forKey: Key.onboardingWasShown.path) }
        }

        /// Whether the contacts tab of this profile shows the entry to the suggestions, on this device. Once shown, the entry stays until the deck is
        /// empty, so whether it shows depends on what it did before, and not only on the deck.
        public static func entryIsShown(ownedCryptoId: ObvCryptoId) -> Bool {
            profilesWhoseEntryIsShown.contains(key(of: ownedCryptoId))
        }

        public static func setEntryIsShown(_ isShown: Bool, ownedCryptoId: ObvCryptoId) {
            var profiles = profilesWhoseEntryIsShown
            if isShown {
                profiles.insert(key(of: ownedCryptoId))
            } else {
                profiles.remove(key(of: ownedCryptoId))
            }
            guard profiles != profilesWhoseEntryIsShown else { return }
            userDefaults.set(Array(profiles), forKey: Key.profilesWhoseEntryIsShown.path)
        }

        private static var profilesWhoseEntryIsShown: Set<String> {
            Set(userDefaults.stringArray(forKey: Key.profilesWhoseEntryIsShown.path) ?? [])
        }

        private static func key(of ownedCryptoId: ObvCryptoId) -> String {
            ownedCryptoId.getIdentity().base64EncodedString()
        }

    }


    /// These settings will allow to replace Apple's Tips with an internal implementation
    public struct ObvTips {
        
        private enum Key: String {
            case dateWhenUserDimissedTip = "dateWhenUserDimissedTip"
            
            private var kDiscussions: String { "ObvTips" }

            var path: String {
                [kSettingsKeyPath, kDiscussions, self.rawValue].joined(separator: ".")
            }

        }
        
        public static var dateWhenUserDimissedTip: Date? {
            return userDefaults.dateOrNil(forKey: Key.dateWhenUserDimissedTip.path)
        }
        
        public static func setDateWhenUserDimissedTip(to date: Date) {
            if date > dateWhenUserDimissedTip ?? .distantPast {
                userDefaults.set(date, forKey: Key.dateWhenUserDimissedTip.path)
                ObvMessengerSettingsObservableObject.onTheMainThread {
                    ObvMessengerSettingsObservableObject.shared.dateWhenUserDimissedTip = date
                }
            }
        }
        
        fileprivate static func resetDateWhenUserDimissedTip() {
            userDefaults.set(nil, forKey: Key.dateWhenUserDimissedTip.path)
            ObvMessengerSettingsObservableObject.onTheMainThread {
                ObvMessengerSettingsObservableObject.shared.dateWhenUserDimissedTip = nil
            }
        }
        
        public static var previousTipWasShownLongTimeAgo: Bool {
            guard let dateWhenUserDimissedTip else { return true }
            let timeIntervalSinceNow = abs(dateWhenUserDimissedTip.timeIntervalSinceNow)
            return timeIntervalSinceNow > TimeInterval(hours: 1)
        }
        
    }
    
    public struct Discussions {
        
        private enum Key: String {
            
            case doSendReadReceipt = "doSendReadReceipt"
            case unarchiveDiscussions = "unarchiveDiscussions"
            case visibilityDuration = "visibilityDuration"
            case existenceDuration = "existenceDuration"
            case countBasedRetentionPolicyIsActive = "countBasedRetentionPolicyIsActive"
            case countBasedRetentionPolicy = "countBasedRetentionPolicy"
            case timeBasedRetentionPolicy = "timeBasedRetentionPolicy"
            case autoRead = "autoRead"
            case readOnce = "readOnce"
            case attachLinkPreviewToMessageSent = "attachLinkPreviewToMessageSent"
            case fetchMissingLinkPreviewFromMessageReceived = "fetchMissingLinkPreviewFromMessageReceived"
            case defaultMediaFormat = "defaultMediaFormat"
            case retainWipedOutboundMessages = "retainWipedOutboundMessages"
            case notificationSound = "notificationSound"
            case performInteractionDonation = "performInteractionDonation"
            case globalDiscussionNotificationsOptions = "globalNotificationsOptions"
            case disableAutocorrection = "disableAutocorrection"
            case mediaQualityForSharing = "mediaQualityForSharing"

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
            guard newValue != userDefaults.boolOrNil(forKey: Key.doSendReadReceipt.path) else { return }
            self.doSendReadReceipt = newValue
            ObvMessengerSettingsObservableObject.onTheMainThread {
                ObvMessengerSettingsObservableObject.shared.doSendReadReceipt = (doSendReadReceipt, changeMadeFromAnotherOwnedDevice)
            }
        }
        
        /// Returns `true` iff the user decided whether to send read receipts
        public static var doSendReadReceiptIsSet: Bool {
            return userDefaults.value(forKey: Key.doSendReadReceipt.path) != nil
        }
        
        // MARK: Archive Discussions
        
        public static var isUnarchiveDiscussionsSet: Bool {
            return userDefaults.boolOrNil(forKey: Key.unarchiveDiscussions.path) != nil
        }
        
        public private(set) static var unarchiveDiscussions: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.unarchiveDiscussions.path) ?? true
            }
            set {
                userDefaults.set(newValue, forKey: Key.unarchiveDiscussions.path)
            }
        }
        
        public static func setUnarchiveDiscussions(to newValue: Bool, changeMadeFromAnotherOwnedDevice: Bool) {
            guard newValue != unarchiveDiscussions || !isUnarchiveDiscussionsSet else { return }
            self.unarchiveDiscussions = newValue
            ObvMessengerSettingsObservableObject.onTheMainThread {
                ObvMessengerSettingsObservableObject.shared.unarchiveDiscussions = (unarchiveDiscussions, changeMadeFromAnotherOwnedDevice)
            }
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

        // MARK: Size the media of a sent message are sent at

        /// The size a draft's photos and videos are sent at when the reader has expressed no preference for that particular draft.
        ///
        /// The choice itself lives on each `PersistedDraft`. Changing the size in any draft writes it here too, so the next draft opens on the
        /// size last chosen.
        ///
        /// **``ObvMediaFormat/med`` is the factory default**: a photo leaves as a JPEG, as it always has, and a video leaves lighter, close to
        /// what other messengers send by default. It is also the share extension's "standard" quality. ``ObvMediaFormat/max`` is in the bar.
        ///
        /// An unreadable stored value, such as one written by a later build sharing the app group, falls back to the default.
        public static var defaultMediaFormat: ObvMediaFormat {
            get {
                guard let rawValue = userDefaults.string(forKey: Key.defaultMediaFormat.path) else { return .med }
                return ObvMediaFormat(rawValue: rawValue) ?? .med
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Key.defaultMediaFormat.path)
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
                ObvMessengerSettingsObservableObject.onTheMainThread {
                    ObvMessengerSettingsObservableObject.shared.performInteractionDonation = newValue
                }
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
        
        // MARK: Autocorrection
        
        /// Controls whether autocorrection is disabled in the compose text field.
        ///
        /// When set to `true`, autocorrection will be explicitly disabled in the compose text field.
        /// When set to `false` (default), the system's default autocorrection behavior is used,
        /// which may vary by platform (iOS, iPadOS, macOS).
        public static var autocorrectionType: ObvTextAutocorrectionType {
            get {
                guard let intValue = userDefaults.integerOrNil(forKey: Key.disableAutocorrection.path) else { return .default }
                return .init(rawValue: intValue) ?? .default
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Key.disableAutocorrection.path)
                ObvMessengerSettingsObservableObject.onTheMainThread {
                    ObvMessengerSettingsObservableObject.shared.autocorrectionType = newValue
                }
            }
        }

        // MARK: Media quality when sharing

        /// The quality the share extension sends photos and videos at, remembered from one share to the next.
        ///
        /// `.standard` until the user says otherwise: a share of full-resolution media is expensive for both
        /// ends, and the HD badge is there for the times it is wanted. Written by the share extension process
        /// as soon as the user taps that badge, so a share abandoned without sending still counts as a choice.
        ///
        /// Not a preference the app exposes anywhere, which is why it pokes neither the observable object nor
        /// a notification: nothing reads it in-process, and the app itself never sends media this way.
        public static var mediaQualityForSharing: ObvMediaQuality {
            get {
                let raw = userDefaults.stringOrNil(forKey: Key.mediaQualityForSharing.path) ?? ObvMediaQuality.standard.rawValue
                return ObvMediaQuality(rawValue: raw) ?? .standard
            }
            set {
                userDefaults.set(newValue.rawValue, forKey: Key.mediaQualityForSharing.path)
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
                ObvMessengerSettingsObservableObject.onTheMainThread {
                    ObvMessengerSettingsObservableObject.shared.userDidSetupBackupsAtLeastOnce = newValue
                }
            }
        }
        
        
        public static var dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey: Date? {
            get {
                return userDefaults.dateOrNil(forKey: Key.dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey.path)
            }
            set {
                userDefaults.set(newValue, forKey: Key.dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey.path)
                ObvMessengerSettingsObservableObject.onTheMainThread {
                    ObvMessengerSettingsObservableObject.shared.dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey = newValue
                }
            }
        }
        
    }
    
    
    // MARK: - VoIP
    
    public struct VoIP {
        
        enum Key: String {
            case receiveCallsOnThisDevice = "receiveCallsOnThisDevice"
            case videoSendResolution = "videoSendResolution"
            case useAlternativeTurnServers = "useAlternativeTurnServers"
            
            private var kVoIP: String { "voip" }
            
            var path: String {
                [kSettingsKeyPath, kVoIP, self.rawValue].joined(separator: ".")
            }

        }

        public static var useAlternativeTurnServers: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.useAlternativeTurnServers.path) ?? false
            }
            set {
                guard newValue != useAlternativeTurnServers else { return }
                userDefaults.set(newValue, forKey: Key.useAlternativeTurnServers.path)
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
            ObvTips.resetDateWhenUserDimissedTip()
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
            static let logTranscriptFrames = "settings.advanced.logTranscriptFrames"
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

        /// Whether the discussion screen reports the transcript's geometry **once per presented frame** to the system console.
        ///
        /// **Nothing to do with ``enableRunningLogs``, which is why it is in a section of its own.** That one drives `ObvDisplayableLogs`, the
        /// files a reader can list and share; this one drives an `OSLog` category, which reaches the unified log and can only be read with the
        /// device attached. Routing this into `ObvDisplayableLogs` would look like tidying and would open, seek, write and close a `FileHandle`
        /// **per line, sixty to a hundred and twenty times a second**.
        ///
        /// **Read by `ObvSingleDiscussion` directly from these `UserDefaults`**, that module having no dependency on this one — deliberately, an
        /// instrument that is meant to leave being a poor reason to give a presentation module a settings dependency, or to plumb a debug flag
        /// through the initial values of a production screen. It is read once when the screen's display link starts, so changing it takes effect
        /// on the next entry into a discussion rather than mid-scroll.
        public static var logTranscriptFrames: Bool {
            get {
                return userDefaults.boolOrNil(forKey: Key.logTranscriptFrames) ?? false
            }
            set {
                guard newValue != logTranscriptFrames else { return }
                userDefaults.set(newValue, forKey: Key.logTranscriptFrames)
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
            static let defaultDoubleTapEmoji = "settings.defaultDoubleTapEmoji"
        }
        
        public static var preferredEmojisList: [String] {
            get {
                return userDefaults.stringArray(forKey: Keys.preferredEmojisList) ?? []
            }
            set {
                guard newValue != preferredEmojisList else { return }
                userDefaults.set(newValue, forKey: Keys.preferredEmojisList)
                ObvMessengerSettingsObservableObject.onTheMainThread {
                    ObvMessengerSettingsObservableObject.shared.preferredEmojisList = preferredEmojisList
                }
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
                ObvMessengerSettingsObservableObject.onTheMainThread {
                    ObvMessengerSettingsObservableObject.shared.defaultEmojiButton = defaultEmojiButton
                }
            }
        }

        /// What a double tap on a message received reacts with, at the global level.
        ///
        /// `PersistedDiscussionLocalConfiguration.doubleTapEmoji` overrides it for one discussion, and
        /// `ObvMessengerConstants.defaultDoubleTapEmoji` is the value behind both.
        public private(set) static var defaultDoubleTapEmoji: String? {
            get {
                return userDefaults.stringOrNil(forKey: Keys.defaultDoubleTapEmoji)
            }
            set {
                userDefaults.set(newValue, forKey: Keys.defaultDoubleTapEmoji)
            }
        }

        /// Travels to the user's other owned devices as an `ObvSyncAtom.preferredReaction`, unless it arrived from one.
        public static func setDefaultDoubleTapEmoji(to newValue: String?, changeMadeFromAnotherOwnedDevice: Bool) {
            guard newValue != defaultDoubleTapEmoji else { return }
            self.defaultDoubleTapEmoji = newValue
            ObvMessengerSettingsObservableObject.onTheMainThread {
                ObvMessengerSettingsObservableObject.shared.defaultDoubleTapEmoji = (defaultDoubleTapEmoji, changeMadeFromAnotherOwnedDevice)
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

    /// Runs a change to one of the values below on the main thread.
    ///
    /// **Every property here is `@Published` on an object SwiftUI observes, and SwiftUI's dependency graph is not thread
    /// safe.** These settings are not only written from the interface: one arriving from another owned device is applied by
    /// a background operation, so a write off the main thread is ordinary rather than exceptional, and it corrupts the
    /// graph silently — the process dies later, somewhere with nothing to do with settings. The hop belongs here, where it
    /// cannot be forgotten, rather than at each of the writers.
    ///
    /// Synchronous when already on the main thread, so that a change made by the interface is published in the same turn
    /// it always was.
    fileprivate static func onTheMainThread(_ change: @escaping () -> Void) {
        if Thread.isMainThread {
            change()
        } else {
            DispatchQueue.main.async(execute: change)
        }
    }

    @Published public fileprivate(set) var defaultEmojiButton: String?
    @Published public fileprivate(set) var defaultDoubleTapEmoji: (defaultDoubleTapEmoji: String?, changeMadeFromAnotherOwnedDevice: Bool)
    @Published public fileprivate(set) var preferredEmojisList: [String]
    @Published public fileprivate(set) var doSendReadReceipt: (doSendReadReceipt: Bool, changeMadeFromAnotherOwnedDevice: Bool)
    @Published public fileprivate(set) var unarchiveDiscussions: (unarchiveDiscussions: Bool, changeMadeFromAnotherOwnedDevice: Bool)
    @Published public fileprivate(set) var autoAcceptGroupInviteFrom: (autoAcceptGroupInviteFrom: ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom, changeMadeFromAnotherOwnedDevice: Bool)
    @Published public fileprivate(set) var hideGroupMemberChangeMessages: Bool
    @Published public fileprivate(set) var sendMessageShortcutType: ObvMessengerSettings.Interface.SendMessageShortcutType
    @Published public fileprivate(set) var performInteractionDonation: Bool
    @Published public fileprivate(set) var userDidSetupBackupsAtLeastOnce: Bool
    @Published public fileprivate(set) var dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey: Date?
    @Published public fileprivate(set) var dateWhenUserDimissedTip: Date?
    @Published public fileprivate(set) var autocorrectionType: ObvTextAutocorrectionType
    
    private init() {
        defaultEmojiButton = ObvMessengerSettings.Emoji.defaultEmojiButton
        defaultDoubleTapEmoji = (ObvMessengerSettings.Emoji.defaultDoubleTapEmoji, false)
        preferredEmojisList = ObvMessengerSettings.Emoji.preferredEmojisList
        doSendReadReceipt = (ObvMessengerSettings.Discussions.doSendReadReceipt, false)
        autoAcceptGroupInviteFrom = (ObvMessengerSettings.ContactsAndGroups.autoAcceptGroupInviteFrom, false)
        hideGroupMemberChangeMessages = ObvMessengerSettings.ContactsAndGroups.hideGroupMemberChangeMessages
        sendMessageShortcutType = ObvMessengerSettings.Interface.sendMessageShortcutType
        performInteractionDonation = ObvMessengerSettings.Discussions.performInteractionDonation
        unarchiveDiscussions = (ObvMessengerSettings.Discussions.unarchiveDiscussions, false)
        userDidSetupBackupsAtLeastOnce = ObvMessengerSettings.Backup.userDidSetupBackupsAtLeastOnce
        dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey = ObvMessengerSettings.Backup.dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey
        dateWhenUserDimissedTip = ObvMessengerSettings.ObvTips.dateWhenUserDimissedTip
        self.autocorrectionType = ObvMessengerSettings.Discussions.autocorrectionType
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
            doSendReadReceipt: Discussions.doSendReadReceipt,
            unarchiveOnNotification: Discussions.unarchiveDiscussions,
            preferredReaction: Emoji.defaultDoubleTapEmoji
        )
    }
    
}


public struct GlobalSettingsSyncSnapshotNode: ObvSyncSnapshotNode {

    private let domain: Set<CodingKeys>
    private let autoAcceptGroupInviteFrom: ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom?
    private let doSendReadReceipt: Bool?
    private let unarchiveOnNotification: Bool?
    private let preferredReaction: String?
    
    public let id = Self.generateIdentifier()

    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case autoAcceptGroupInviteFrom = "auto_join_groups"
        case doSendReadReceipt = "send_read_receipt"
        case unarchiveOnNotification = "unarchive_on_notification"
        case preferredReaction = "preferred_reaction"
        case domain = "domain"
    }

    private static let defaultDomain = Set(CodingKeys.allCases.filter({ $0 != .domain }))

    
    init(autoAcceptGroupInviteFrom: ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom,
         doSendReadReceipt: Bool,
         unarchiveOnNotification: Bool,
         preferredReaction: String?
    ) {
        self.autoAcceptGroupInviteFrom = autoAcceptGroupInviteFrom
        self.doSendReadReceipt = doSendReadReceipt
        self.unarchiveOnNotification = unarchiveOnNotification
        self.preferredReaction = preferredReaction
        self.domain = Self.defaultDomain
    }
    
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(domain, forKey: .domain)
        try container.encodeIfPresent(autoAcceptGroupInviteFrom?.rawValue, forKey: .autoAcceptGroupInviteFrom)
        try container.encodeIfPresent(doSendReadReceipt, forKey: .doSendReadReceipt)
        try container.encodeIfPresent(unarchiveOnNotification, forKey: .unarchiveOnNotification)
        try container.encodeIfPresent(preferredReaction, forKey: .preferredReaction)
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
        self.unarchiveOnNotification = try values.decodeIfPresent(Bool.self, forKey: .unarchiveOnNotification)
        self.preferredReaction = try values.decodeIfPresent(String.self, forKey: .preferredReaction)
    }
    
    public func useToUpdateGlobalSettings() {
        
        if domain.contains(.autoAcceptGroupInviteFrom), let autoAcceptGroupInviteFrom {
            ObvMessengerSettings.ContactsAndGroups.setAutoAcceptGroupInviteFrom(to: autoAcceptGroupInviteFrom, changeMadeFromAnotherOwnedDevice: false)
        }
        
        if domain.contains(.doSendReadReceipt), let doSendReadReceipt {
            ObvMessengerSettings.Discussions.setDoSendReadReceipt(to: doSendReadReceipt, changeMadeFromAnotherOwnedDevice: false)
        }
        
        if domain.contains(.unarchiveOnNotification), let unarchiveOnNotification {
            ObvMessengerSettings.Discussions.setUnarchiveDiscussions(to: unarchiveOnNotification, changeMadeFromAnotherOwnedDevice: false)
        }

        // **No `let preferredReaction` here, unlike the three above, and that is what makes a nil transferable.** Nil is a
        // value of its own for this setting — no choice of your own, fall back to the constant — and `encodeIfPresent`
        // leaves the key out when it is nil, so requiring a value would drop exactly that case. What tells "nil" apart from
        // "the sender had never heard of this setting" is the domain: a sender that knows the key always names it there.
        if domain.contains(.preferredReaction) {
            ObvMessengerSettings.Emoji.setDefaultDoubleTapEmoji(to: preferredReaction, changeMadeFromAnotherOwnedDevice: false)
        }

    }
    
    enum ObvError: Error {
        case couldNotDeserializeAutoAcceptGroupInvite
    }
    
}
