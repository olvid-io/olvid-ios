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
import TipKit
import Combine
import ObvSettings
import ObvEngine
import ObvUICoreData


final class OlvidTipManager {
    
    private var cancellables = [AnyCancellable]()
    private var notificationTokens = [NSObjectProtocol]()
    private let obvEngine: ObvEngine

    
    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        
        if #available(iOS 17, *) {
            
            do {
                if ObvUICoreDataConstants.developmentMode {
                    try Tips.configure([.displayFrequency(.immediate)])
                } else {
                    try Tips.configure([.displayFrequency(.hourly)])
                }
                continuouslyUpdateTipParameters()
            } catch {
                assertionFailure()
            }
            
            if ObvUICoreDataConstants.developmentMode {
                // Comment this in dev mode to reflect the production behaviour between app launches
                //OlvidTip.resetTipsUserDefaults()
            }

        }

    }

    
    deinit {
        cancellables.forEach({ $0.cancel() })
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    
    @available(iOS 17.0, *)
    private func continuouslyUpdateTipParameters() {
        
        // We continuously observe the sendMessageShortcutType setting and consider that the user configurer it
        // if set to Cmd+Enter.
        ObvMessengerSettingsObservableObject.shared.$sendMessageShortcutType
            .removeDuplicates()
            .receive(on: OperationQueue.main)
            .sink { value in
                switch value {
                case .enter:
                    break
                case .commandEnter:
                    OlvidTip.KeyboardShortcutForSendingMessage.keyboardShortcutAlreadyConfigured = true
                }
            }
            .store(in: &cancellables)
        
        // When the user changes the doSendReadReceipt global setting, we inform TipKit so as to make sure
        // when don't display the DoSendReadReceipt tip ever again.
        ObvMessengerSettingsObservableObject.shared.$doSendReadReceipt
            .dropFirst()
            .receive(on: OperationQueue.main)
            .sink { _ in
                OlvidTip.DoSendReadReceipt.theDoSendReadReceiptWasSetAtLeastOnce = true
            }
            .store(in: &cancellables)
        
        // If the user has doSendReadReceipt set to true in the settings, it means she already changed this setting at least once.
        if ObvMessengerSettings.Discussions.doSendReadReceipt {
            OlvidTip.DoSendReadReceipt.theDoSendReadReceiptWasSetAtLeastOnce = true
        }
        
        // If a backup key is created, update the CreateBackupKey tip
        notificationTokens.append(ObvEngineNotificationNew.observeNewBackupKeyGenerated(within: NotificationCenter.default) { _, _ in
            OlvidTip.Backup.CreateBackupKey.hasBackupKey = true
            OlvidTip.Backup.ShouldPerformBackup.hasBackupKey = true
            OlvidTip.Backup.ShouldVerifyBackupKey.hasBackupKey = true
        })
                
    }
    
    
    @available(iOS 17.0, *)
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        
        // Query the engine to determine whether the user has a backup key or not. If this is the key, update various tip parameters.
        do {
            let backupKeyInformation = try await obvEngine.getCurrentBackupKeyInformation()
            let hasBackupKey = (backupKeyInformation != nil)
            OlvidTip.Backup.CreateBackupKey.hasBackupKey = hasBackupKey
            OlvidTip.Backup.ShouldPerformBackup.hasBackupKey = hasBackupKey
            OlvidTip.Backup.ShouldVerifyBackupKey.hasBackupKey = hasBackupKey
            if let backupKeyInformation {
                let lastBackupExportTimestamp = backupKeyInformation.lastBackupExportTimestamp ?? Date.distantPast
                OlvidTip.Backup.ShouldPerformBackup.didExportBackupRecently = abs(lastBackupExportTimestamp.timeIntervalSinceNow) < OlvidTip.Backup.ShouldPerformBackup.displayPeriod
                let keyGenerationTimestamp = backupKeyInformation.keyGenerationTimestamp
                OlvidTip.Backup.ShouldVerifyBackupKey.didGenerateBackupKeyEnoughTimeAgo = abs(keyGenerationTimestamp.timeIntervalSinceNow) > OlvidTip.Backup.ShouldVerifyBackupKey.didGenerateBackupKeyPeriod
                let lastSuccessfulKeyVerificationTimestamp = backupKeyInformation.lastSuccessfulKeyVerificationTimestamp ?? Date.distantPast
                OlvidTip.Backup.ShouldVerifyBackupKey.didVerifyBackupKeyRecently = abs(lastSuccessfulKeyVerificationTimestamp.timeIntervalSinceNow) < OlvidTip.Backup.ShouldVerifyBackupKey.verifyBackupKeyPeriod
            } else {
                OlvidTip.Backup.ShouldPerformBackup.didExportBackupRecently = false
            }
        } catch {
            assertionFailure(error.localizedDescription)
        }

        // Query the app database to determine whether the user has at least one contact
        do {
            OlvidTip.Backup.CreateBackupKey.userHasAtLeastOneContact = try await Self.userHasAtLeastOneContact()
        } catch {
            assertionFailure(error.localizedDescription)
        }
        
        // Evaluate whether tips where "recently" displayed
        do {
            let tipWasDisplayedRecently = abs(OlvidTip.Backup.CreateBackupKey.UserDefaults.lastDisplayDate.timeIntervalSinceNow) < OlvidTip.Backup.CreateBackupKey.displayPeriod
            if forTheFirstTime {
                OlvidTip.Backup.CreateBackupKey.tipWasDisplayedRecently = tipWasDisplayedRecently
            } else {
                if !tipWasDisplayedRecently {
                    OlvidTip.Backup.CreateBackupKey.tipWasDisplayedRecently = tipWasDisplayedRecently
                }
            }
        }
        do {
            let tipWasDisplayedRecently = abs(OlvidTip.Backup.ShouldPerformBackup.UserDefaults.lastDisplayDate.timeIntervalSinceNow) < OlvidTip.Backup.ShouldPerformBackup.displayPeriod
            if forTheFirstTime {
                OlvidTip.Backup.ShouldPerformBackup.tipWasDisplayedRecently = tipWasDisplayedRecently
            } else {
                if !tipWasDisplayedRecently {
                    OlvidTip.Backup.ShouldPerformBackup.tipWasDisplayedRecently = tipWasDisplayedRecently
                }
            }
        }
        do {
            let tipWasDisplayedRecently = abs(OlvidTip.Backup.ShouldVerifyBackupKey.UserDefaults.lastDisplayDate.timeIntervalSinceNow) < OlvidTip.Backup.ShouldVerifyBackupKey.displayPeriod
            if forTheFirstTime {
                OlvidTip.Backup.ShouldVerifyBackupKey.tipWasDisplayedRecently = tipWasDisplayedRecently
            } else {
                if !tipWasDisplayedRecently {
                    OlvidTip.Backup.ShouldVerifyBackupKey.tipWasDisplayedRecently = tipWasDisplayedRecently
                }
            }
        }

        // Evaluate whether the user enabled automatic backups
        OlvidTip.Backup.ShouldPerformBackup.isAutomaticBackupEnabled = ObvMessengerSettings.Backup.isAutomaticBackupEnabled
        
    }
    
    

    
}


// MARK: - Helpers

extension OlvidTipManager {
    
    private static func userHasAtLeastOneContact() async throws -> Bool {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let result = try PersistedObvContactIdentity.userHasAtLeastOnContact(within: context)
                    return continuation.resume(returning: result)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
}


// MARK: -
// MARK: - OlvidTip

@available(iOS 17.0, *)
struct OlvidTip {
    
    /// Certain tip requires complex rules that requires to store data in UserDefaults. This is the first element to the key path.
    static private let keyPath = "olvid-tip-manager"
    
    static private let userDefaults = UserDefaults(suiteName: ObvUICoreDataConstants.appGroupIdentifier)!

    fileprivate static func resetTipsUserDefaults() {
        Backup.resetTipsUserDefaults()
    }
    
    /// This tip is intended to be shown in the single discussion view and allows the user to discover the search within a single discussion.
    struct SearchWithinDiscussion: Tip {
        
        var title: Text {
            Text("Search in this discussion")
        }
        
        var message: Text? {
            Text("The search is performed in all messages of this discussion.")
        }
        
        var image: Image? {
            Image(systemIcon: .magnifyingglass)
        }
        
        var options: [TipOption] {[
            // Do not show the tip more than twice
            Tips.MaxDisplayCount(2),
        ]}
    }
    
    
    /// This tip is intended to be shown in the single discussion view and allows the user to learn about the keyboard shortcut that allows to send a message.
    /// It also provides a button allowing the user to navigate to the appropriate setting screen to configure her preferred keyboard shortcut.
    struct KeyboardShortcutForSendingMessage: Tip {
        
        @Parameter
        static var keyboardShortcutAlreadyConfigured: Bool = false
        
        var title: Text {
            Text("Pressing Enter sends your message")
        }
        
        var message: Text? {
            Text("By default, pressing Enter sends your message. You can customize this shortcut to use Cmd+Enter instead.")
        }

        var image: Image? {
            Image(systemIcon: .paperplaneFill)
        }

        var options: [TipOption] {[
            // Do not show the tip more than twice
            Tips.MaxDisplayCount(2),
            Tips.IgnoresDisplayFrequency(true),
        ]}
        
        var rules: [Rule] {
            #Rule(Self.$keyboardShortcutAlreadyConfigured) {
                $0 == false
            }
        }
        
        var actions: [Action] {
            let configurekeyboardShortcutForSendingMessage = Action(title: String(localized: "CONFIGURE_KEYBOARD_SHORTCUT")) {
                ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .interfaceSettings)
                    .postOnDispatchQueue()
            }
            return [configurekeyboardShortcutForSendingMessage]
        }

    }
    
    
    struct DoSendReadReceipt: Tip {
        
        @Parameter
        static var theDoSendReadReceiptWasSetAtLeastOnce: Bool = false
        
        var title: Text {
            Text("Read receipts")
        }
        
        var message: Text? {
            Text("Turn on read receipts to let your contacts know when you've read their messages. You can adjust this setting anytime.")
        }

        var image: Image? {
            Image(systemIcon: .eye)
        }
        
        var rules: [Rule] {
            // Don't display the tip if the user already changed the doSendReadReceipt setting
            #Rule(Self.$theDoSendReadReceiptWasSetAtLeastOnce) { $0 == false }
        }

        var actions: [Action] {
            let turnOn = Action(title: String(localized: "TURN_ON")) {
                ObvMessengerSettings.Discussions.setDoSendReadReceipt(to: true, changeMadeFromAnotherOwnedDevice: false)
                // Setting this here allows to make sure that the tip won't be displayed, even if the user choice doesn't actually change the existing setting.
                Self.theDoSendReadReceiptWasSetAtLeastOnce = true
            }
            let turnOff = Action(title: String(localized: "DONT_TURN_ON")) {
                ObvMessengerSettings.Discussions.setDoSendReadReceipt(to: false, changeMadeFromAnotherOwnedDevice: false)
                // Setting this here allows to make sure that the tip won't be displayed, even if the user choice doesn't actually change the existing setting.
                Self.theDoSendReadReceiptWasSetAtLeastOnce = true
            }
            return [turnOn, turnOff]
        }
    }
    
    
    struct Backup {
        
        static func resetTipsUserDefaults() {
            CreateBackupKey.UserDefaults.resetAll()
            ShouldPerformBackup.UserDefaults.resetAll()
        }
        
        /// Certain tip requires complex rules that requires to store data in UserDefaults. This is the relevent part of the key path for Backup tips.
        private static let keyPath = "backup"

        struct CreateBackupKey: Tip {
            
            @Parameter
            static var hasBackupKey: Bool? = nil
            
            
            @Parameter
            static var userHasAtLeastOneContact: Bool? = nil
            
            
            @Parameter
            static var tipWasDisplayedRecently: Bool? = nil
            
            /// Don't display the tip more than once every 7 days.
            fileprivate static let displayPeriod = TimeInterval(days: 7)
            
            
            /// This tip requires complex rules that requires to store data in UserDefaults. This is the relevent part of the key path for the complex parameters of this tip.
            private static let keyPath = "create-backup-key"
            
            struct UserDefaults {
                
                enum Key: String {
                    case lastDisplayDate = "last-display-date"
                    var path: String {
                        [OlvidTip.keyPath, OlvidTip.Backup.keyPath, OlvidTip.Backup.CreateBackupKey.keyPath, self.rawValue].joined(separator: ".")
                    }
                }
                
                static var lastDisplayDate: Date {
                    get {
                        userDefaults.dateOrNil(for: Self.Key.lastDisplayDate) ?? .distantPast
                    }
                    set {
                        userDefaults.setDate(newValue, for: Self.Key.lastDisplayDate)
                    }
                }


                static func resetAll() {
                    userDefaults.setDate(nil, for: Self.Key.lastDisplayDate)
                }
                
            }
            
            var title: Text {
                Text("TIP_CREATE_BACKUP_KEY_TITLE")
            }
            
            var message: Text? {
                Text("TIP_CREATE_BACKUP_KEY_MESSAGE")
            }

            var image: Image? {
                Image(systemIcon: .arrowCounterclockwise)
            }

            /// Rules allowing to determine whether we should show the tip encouraging the user to create a backup key.
            /// We display the tip if:
            /// - has no backup key (i.e., backupKeyInformation == nil)
            /// - has at least one contact
            /// - did not dismiss this tip for the past week
            /// Then notify that we should display a OlvidSnackBarCategory.createBackupKey snack bar.
            var rules: [Rule] {
                #Rule(Self.$hasBackupKey) { hasBackupKey in (hasBackupKey != nil) && (hasBackupKey! == false) }
                #Rule(Self.$userHasAtLeastOneContact) { userHasAtLeastOneContact in (userHasAtLeastOneContact != nil) && userHasAtLeastOneContact! }
                #Rule(Self.$tipWasDisplayedRecently) { tipWasDisplayedRecently in (tipWasDisplayedRecently != nil) && tipWasDisplayedRecently! == false }
            }
            
            var actions: [Action] {
                // We assume that this computed variable exactly when the tip is shown on screen.
                UserDefaults.lastDisplayDate = .now
                let configurekeyboardShortcutForSendingMessage = Action(title: String(localized: "CONFIGURE_BACKUPS_BUTTON_TITLE")) {
                    ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .backupSettings)
                        .postOnDispatchQueue()
                }
                return [configurekeyboardShortcutForSendingMessage]
            }

        }
    
        
        struct ShouldPerformBackup: Tip {
            
            @Parameter
            static var hasBackupKey: Bool? = nil

            @Parameter
            static var isAutomaticBackupEnabled: Bool? = nil

            @Parameter
            static var tipWasDisplayedRecently: Bool? = nil
            
            @Parameter
            static var didExportBackupRecently: Bool? = nil
            
            /// Don't display the tip more than once every month
            fileprivate static let displayPeriod = TimeInterval(months: 1)
            
            /// This tip requires complex rules that requires to store data in UserDefaults. This is the relevent part of the key path for the complex parameters of this tip.
            private static let keyPath = "should-perform-backup"
            
            struct UserDefaults {
                
                enum Key: String {
                    case lastDisplayDate = "last-display-date"
                    var path: String {
                        [OlvidTip.keyPath, OlvidTip.Backup.keyPath, OlvidTip.Backup.ShouldPerformBackup.keyPath, self.rawValue].joined(separator: ".")
                    }
                }
                
                static var lastDisplayDate: Date {
                    get {
                        userDefaults.dateOrNil(for: Self.Key.lastDisplayDate) ?? .distantPast
                    }
                    set {
                        userDefaults.setDate(newValue, for: Self.Key.lastDisplayDate)
                    }
                }


                static func resetAll() {
                    userDefaults.setDate(nil, for: Self.Key.lastDisplayDate)
                }
                
            }

            var title: Text {
                Text("TIP_SHOULD_PERFORM_BACKUP_TITLE")
            }
            
            var message: Text? {
                Text("TIP_SHOULD_PERFORM_BACKUP_MESSAGE")
            }

            var image: Image? {
                Image(systemIcon: .arrowCounterclockwise)
            }

            /// Rules allowing to determine whether we should show the tip encouraging the user to perform a manual backup
            /// We display the tip if:
            /// - has a backup key (i.e., backupKeyInformation != nil)
            /// - did not activate automatic backups
            /// - did not dismiss this tip for the past month
            /// - did not export a backup for more than a month
            var rules: [Rule] {
                #Rule(Self.$hasBackupKey) { hasBackupKey in (hasBackupKey != nil) && hasBackupKey! }
                #Rule(Self.$isAutomaticBackupEnabled) { isAutomaticBackupEnabled in (isAutomaticBackupEnabled != nil) && (isAutomaticBackupEnabled! == false) }
                #Rule(Self.$tipWasDisplayedRecently) { tipWasDisplayedRecently in (tipWasDisplayedRecently != nil) && tipWasDisplayedRecently! == false }
                #Rule(Self.$didExportBackupRecently) { didExportBackupRecently in (didExportBackupRecently != nil) && didExportBackupRecently! == false }
            }

            var actions: [Action] {
                // We assume that this computed variable exactly when the tip is shown on screen.
                UserDefaults.lastDisplayDate = .now
                let configurekeyboardShortcutForSendingMessage = Action(title: String(localized: "PERFORM_MANUAL_BACKUP_NOW")) {
                    ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .backupSettings)
                        .postOnDispatchQueue()
                }
                return [configurekeyboardShortcutForSendingMessage]
            }

        }
        
        
        struct ShouldVerifyBackupKey: Tip {
            
            @Parameter
            static var hasBackupKey: Bool? = nil

            
            @Parameter
            static var didVerifyBackupKeyRecently: Bool? = nil

            /// Period of time between two backup key verification
            fileprivate static let verifyBackupKeyPeriod = TimeInterval(months: 3)

            
            @Parameter
            static var didGenerateBackupKeyEnoughTimeAgo: Bool? = nil

            /// Minimum period of time between the key generation date and the first date when we can show the tip
            fileprivate static let didGenerateBackupKeyPeriod = TimeInterval(days: 14)

            
            @Parameter
            static var tipWasDisplayedRecently: Bool? = nil

            /// Don't display the tip more than once every month
            fileprivate static let displayPeriod = TimeInterval(months: 1)
            
            /// This tip requires complex rules that requires to store data in UserDefaults. This is the relevent part of the key path for the complex parameters of this tip.
            private static let keyPath = "should-verify-backup-key"
            
            struct UserDefaults {
                
                enum Key: String {
                    case lastDisplayDate = "last-display-date"
                    var path: String {
                        [OlvidTip.keyPath, OlvidTip.Backup.keyPath, OlvidTip.Backup.ShouldVerifyBackupKey.keyPath, self.rawValue].joined(separator: ".")
                    }
                }
                
                static var lastDisplayDate: Date {
                    get {
                        userDefaults.dateOrNil(for: Self.Key.lastDisplayDate) ?? .distantPast
                    }
                    set {
                        userDefaults.setDate(newValue, for: Self.Key.lastDisplayDate)
                    }
                }


                static func resetAll() {
                    userDefaults.setDate(nil, for: Self.Key.lastDisplayDate)
                }
                
            }

            var title: Text {
                Text("TIP_SHOULD_VERIFY_BACKUP_KEY_TITLE")
            }
            
            var message: Text? {
                Text("TIP_SHOULD_VERIFY_BACKUP_KEY_MESSAGE")
            }

            var image: Image? {
                Image(systemIcon: .arrowCounterclockwise)
            }

            /// Rules allowing to determine whether we should show the tip encouraging the user to verify she "remembers" her backup key
            /// We display the tip if:
            /// - has a backup key (i.e., backupKeyInformation != nil)
            /// - did not verify her backup key for the 3 months
            /// - did generate her key more than a two weeks ago
            /// - did not dismiss this tip for the past month
            var rules: [Rule] {
                #Rule(Self.$hasBackupKey) { hasBackupKey in (hasBackupKey != nil) && hasBackupKey! }
                #Rule(Self.$didVerifyBackupKeyRecently) { didVerifyBackupKeyRecently in (didVerifyBackupKeyRecently != nil) && didVerifyBackupKeyRecently! == false }
                #Rule(Self.$didGenerateBackupKeyEnoughTimeAgo) { didGenerateBackupKeyEnoughTimeAgo in (didGenerateBackupKeyEnoughTimeAgo != nil) && didGenerateBackupKeyEnoughTimeAgo! }
                #Rule(Self.$tipWasDisplayedRecently) { tipWasDisplayedRecently in (tipWasDisplayedRecently != nil) && tipWasDisplayedRecently! == false }
            }

            
            var actions: [Action] {
                // We assume that this computed variable exactly when the tip is shown on screen.
                UserDefaults.lastDisplayDate = .now
                let configurekeyboardShortcutForSendingMessage = Action(title: String(localized: "VERIFY_BACKUP_KEY_NOW")) {
                    ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .backupSettings)
                        .postOnDispatchQueue()
                }
                return [configurekeyboardShortcutForSendingMessage]
            }

        }

    }
    
}
