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

final class ObvPushNotificationManager {
    
    static let shared = ObvPushNotificationManager()
    private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)!
    
    weak var obvEngine: ObvEngine?
    
    // API
    
    var currentDeviceToken: Data? {
        get {
            userDefaults.value(forKey: "io.olvid.ObvPushNotificationManager.push.token") as? Data
        }
        set {
            guard let token = newValue else { return }
            userDefaults.set(token, forKey: "io.olvid.ObvPushNotificationManager.push.token") // User defaults are thread safe
        }
    }

    var currentVoipToken: Data? {
        get {
            userDefaults.value(forKey: "io.olvid.ObvPushNotificationManager.voip.token") as? Data
        }
        set {
            guard let token = newValue else { return }
            userDefaults.set(token, forKey: "io.olvid.ObvPushNotificationManager.voip.token")  // User defaults are thread safe
        }
    }

    private var kickOtherDevicesOnNextRegister = false

    // Private variables
    
    private var notificationTokens = [NSObjectProtocol]()
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ObvPushNotificationManager.self))
    private let internalQueue = OperationQueue.createSerialQueue(name: "ObvPushNotificationManager internal queue")

    
    private init() {
        observeNotifications()
    }
    
    
    private func observeNotifications() {
        notificationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeServerRequiresThisDeviceToRegisterToPushNotifications(within: NotificationCenter.default) { [weak self] (ownedCryptoId) in
                guard let _self = self else { return }
                os_log("Since the server reported that we need to register to push notification, we do so now", log: _self.log, type: .info)
                _self.tryToRegisterToPushNotifications()
            },
            ObvMessengerSettingsNotifications.observeIsCallKitEnabledSettingDidChange { [weak self] in
                self?.tryToRegisterToPushNotifications()
            },
        ])
    }
    

    func doKickOtherDevicesOnNextRegister() {
        internalQueue.addOperation { [weak self] in
            self?.kickOtherDevicesOnNextRegister = true
        }
    }
    
    
    func tryToRegisterToPushNotifications() {
        internalQueue.addOperation { [weak self] in
            guard let _self = self else { return }
            guard let obvEngine = _self.obvEngine else { assertionFailure(); return }
            let log = _self.log
            let tokens: (pushToken: Data, voipToken: Data?)?
            if ObvMessengerConstants.isRunningOnRealDevice {
                if let _currentDeviceToken = _self.currentDeviceToken {
                    let voipToken = ObvMessengerSettings.VoIP.isCallKitEnabled ? _self.currentVoipToken : nil
                    tokens = (_currentDeviceToken, voipToken)
                } else {
                    tokens = nil
                }
            } else {
                tokens = nil
            }
            
            do {
                os_log("🍎 Will call registerToPushNotificationFor (tokens is %{public}@, voipToken is %{public}@)", log: log, type: .info, tokens == nil ? "nil" : "set", tokens?.voipToken == nil ? "nil" : "set")
                try obvEngine.registerToPushNotificationFor(deviceTokens: tokens, kickOtherDevices: _self.kickOtherDevicesOnNextRegister, useMultiDevice: false) { result in
                    switch result {
                    case .failure(let error):
                        os_log("🍎 We Could not register to push notifications: %{public}@", log: log, type: .fault, error.localizedDescription)
                    case .success:
                        os_log("🍎 Youpi, we successfully subscribed to remote push notifications", log: log, type: .info)
                    }
                }
                _self.kickOtherDevicesOnNextRegister = false
            } catch {
                os_log("🍎 We Could not register to push notifications", log: log, type: .fault)
                return
            }
        }
    }
    
}
