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
import os.log
import ObvEngine
import ObvUICoreData

actor ObvPushNotificationManager {
    
    static let shared: ObvPushNotificationManager = {
        let instance = ObvPushNotificationManager()
        Task { await instance.observeNotifications() }
        return instance
    }()
    private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)!
    
    // API
    
    private(set) var currentDeviceToken: Data? {
        get {
            userDefaults.value(forKey: "io.olvid.ObvPushNotificationManager.push.token") as? Data
        }
        set {
            guard let token = newValue else { return }
            userDefaults.set(token, forKey: "io.olvid.ObvPushNotificationManager.push.token") // User defaults are thread safe
        }
    }
    
    func setCurrentDeviceToken(to newCurrentDeviceToken: Data) {
        self.currentDeviceToken = newCurrentDeviceToken
    }

    private(set) var currentVoipToken: Data? {
        get {
            userDefaults.value(forKey: "io.olvid.ObvPushNotificationManager.voip.token") as? Data
        }
        set {
            guard let token = newValue else { return }
            userDefaults.set(token, forKey: "io.olvid.ObvPushNotificationManager.voip.token")  // User defaults are thread safe
        }
    }
    
    func setCurrentVoipToken(to newCurrentVoipToken: Data?) {
        self.currentVoipToken = newCurrentVoipToken
    }


    private var kickOtherDevicesOnNextRegister = false

    // Private variables
    
    private var notificationTokens = [NSObjectProtocol]()
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ObvPushNotificationManager.self))

    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func observeNotifications() {
        let log = self.log
        notificationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeServerRequiresThisDeviceToRegisterToPushNotifications(within: NotificationCenter.default) { ownedCryptoId in
                os_log("Since the server reported that we need to register to push notification, we do so now", log: log, type: .info)
                Task { [weak self] in await self?.tryToRegisterToPushNotifications() }
            },
            ObvMessengerSettingsNotifications.observeIsCallKitEnabledSettingDidChange { [weak self] in
                Task { [weak self] in await self?.tryToRegisterToPushNotifications() }
            },
        ])
    }
    

    func doKickOtherDevicesOnNextRegister() {
        kickOtherDevicesOnNextRegister = true
    }
    
    
    func tryToRegisterToPushNotifications() async {
        let obvEngine = await NewAppStateManager.shared.waitUntilAppIsInitialized()
        tryToRegisterToPushNotifications(obvEngine: obvEngine)
    }
    
    
    private func tryToRegisterToPushNotifications(obvEngine: ObvEngine) {
        let tokens: (pushToken: Data, voipToken: Data?)?
        if ObvMessengerConstants.areRemoteNotificationsAvailable {
            if let _currentDeviceToken = currentDeviceToken {
                let voipToken = ObvMessengerSettings.VoIP.isCallKitEnabled ? currentVoipToken : nil
                tokens = (_currentDeviceToken, voipToken)
            } else {
                tokens = nil
            }
        } else {
            tokens = nil
        }
        
        do {
            os_log("🍎 Will call registerToPushNotificationFor (tokens is %{public}@, voipToken is %{public}@)", log: log, type: .info, tokens == nil ? "nil" : "set", tokens?.voipToken == nil ? "nil" : "set")
            let log = self.log
            try obvEngine.registerToPushNotificationFor(deviceTokens: tokens, kickOtherDevices: kickOtherDevicesOnNextRegister, useMultiDevice: false) { result in
                switch result {
                case .failure(let error):
                    os_log("🍎 We Could not register to push notifications: %{public}@", log: log, type: .fault, error.localizedDescription)
                case .success:
                    os_log("🍎 Youpi, we successfully subscribed to remote push notifications", log: log, type: .info)
                }
            }
            kickOtherDevicesOnNextRegister = false
        } catch {
            os_log("🍎 We Could not register to push notifications", log: log, type: .fault)
            return
        }
    }
    
}
