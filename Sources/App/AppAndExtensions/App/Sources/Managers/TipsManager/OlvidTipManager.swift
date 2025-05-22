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
import ObvAppCoreConstants


final class OlvidTipManager {
    
    private var cancellables = [AnyCancellable]()
    private var notificationTokens = [NSObjectProtocol]()
    private let obvEngine: ObvEngine

    
    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        
        if #available(iOS 17, *) {
            
            do {
                switch ObvAppCoreConstants.appType {
                case .development:
                    try Tips.configure([.displayFrequency(.immediate)])
                case .production:
                    try Tips.configure([.displayFrequency(.hourly)])
                }
                continuouslyUpdateTipParameters()
            } catch {
                assertionFailure()
            }
            
            if ObvAppCoreConstants.appType == .development {
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
        
    }
    
    
    @available(iOS 17.0, *)
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        
        // This was used to configure tips for legacy backups
                
    }
    
}


// MARK: -
// MARK: - OlvidTip

@available(iOS 17.0, *)
struct OlvidTip {
    
    /// Certain tip requires complex rules that requires to store data in UserDefaults. This is the first element to the key path.
    static private let keyPath = "olvid-tip-manager"
    
    static private let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier)!

    fileprivate static func resetTipsUserDefaults() {
        LegacyBackup.resetTipsUserDefaults()
    }
    
    /// This tip is intended to be shown in the single discussion view and allows the user to discover the share location within a single discussion.
    struct ShareLocation: Tip {
        
        var title: Text {
            Text("Share your location")
        }
        
        var message: Text? {
            Text("You can now share your location with the participants of this discussion")
        }
        
        var image: Image? {
            Image(systemIcon: .locationCircle)
        }
        
        var options: [TipOption] {[
            // Do not show the tip more than twice
            Tips.MaxDisplayCount(2),
        ]}
    }

    /// This tip announces the new sent messages and attachments statuses.
//    struct NewSentMessageStatus: Tip {
//        
//        var title: Text {
//            Text("TIP_TITLE_NEW_SENT_MESSAGE_STATUS")
//        }
//        
//        var message: Text? {
//            Text("TIP_MESSAGE_NEW_SENT_MESSAGE_STATUS")
//        }
//        
//        var image: Image? {
//            Image(customIcon: .checkmarkDoubleCircleHalfFill)
//        }
//
//        var options: [TipOption] {[
//            // Do not show the tip more than twice
//            Tips.MaxDisplayCount(2),
//        ]}
//
//    }
    
    /// This tip is intended to be shown in the single discussion view and allows the user to discover the search within a single discussion.
//    struct SearchWithinDiscussion: Tip {
//        
//        var title: Text {
//            Text("Search in this discussion")
//        }
//        
//        var message: Text? {
//            Text("The search is performed in all messages of this discussion.")
//        }
//        
//        var image: Image? {
//            Image(systemIcon: .magnifyingglass)
//        }
//        
//        var options: [TipOption] {[
//            // Do not show the tip more than twice
//            Tips.MaxDisplayCount(2),
//        ]}
//    }
    
    
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
    
    
    struct LegacyBackup {

        static func resetTipsUserDefaults() {
            do {
                let key = [OlvidTip.keyPath, "backup", "create-backup-key", "last-display-date"].joined(separator: ".")
                userDefaults.set(nil, forKey: key)
            }
            do {
                let key = [OlvidTip.keyPath, "backup", "should-perform-backup", "last-display-date"].joined(separator: ".")
                userDefaults.set(nil, forKey: key)
            }
        }

    }
    
}
