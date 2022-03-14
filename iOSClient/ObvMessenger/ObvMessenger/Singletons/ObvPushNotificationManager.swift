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
            userDefaults.set(token, forKey: "io.olvid.ObvPushNotificationManager.push.token")
        }
    }

    var currentVoipToken: Data? {
        get {
            userDefaults.value(forKey: "io.olvid.ObvPushNotificationManager.voip.token") as? Data
        }
        set {
            guard let token = newValue else { return }
            userDefaults.set(token, forKey: "io.olvid.ObvPushNotificationManager.voip.token")
        }
    }

    private var kickOtherDevicesOnNextRegister = false

    // Private variables
    
    private var notificationTokens = [NSObjectProtocol]()

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ObvPushNotificationManager.self))

    private init() {
        observeNotifications()
    }
    
    private func observeNotifications() {
        notificationTokens.append(ObvEngineNotificationNew.observeServerRequiresThisDeviceToRegisterToPushNotifications(within: NotificationCenter.default) { [weak self] (ownedCryptoId) in
            guard let _self = self else { return }
            os_log("Since the server reported that we need to register to push notification, we do so now", log: _self.log, type: .info)
            DispatchQueue.main.async {
                _self.tryToRegisterToPushNotifications()
            }
        })
        notificationTokens.append(ObvMessengerInternalNotification.observeIsCallKitEnabledSettingDidChange(queue: OperationQueue.main) { [weak self] in
            self?.tryToRegisterToPushNotifications()
        })
    }
    
    func doKickOtherDevicesOnNextRegister() {
        assert(Thread.current == Thread.main)
        self.kickOtherDevicesOnNextRegister = true
    }
    
    func tryToRegisterToPushNotifications() {
        assert(Thread.isMainThread)
        guard let obvEngine = self.obvEngine else { assertionFailure(); return }
        let log = self.log
        let tokens: (pushToken: Data, voipToken: Data?)?
        if ObvMessengerConstants.isRunningOnRealDevice {
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
