/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import OlvidUtils
import ObvTypes
import ObvSettings
import ObvAppCoreConstants
import ObvAppCoreConstants


actor ObvPushNotificationManager {
    
    static let shared: ObvPushNotificationManager = {
        let instance = ObvPushNotificationManager()
        Task { await instance.observeNotifications() }
        return instance
    }()
    private let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier)!
    
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


    // Private variables
    
    private var notificationTokens = [NSObjectProtocol]()
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ObvPushNotificationManager.self))

    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func observeNotifications() async {
        let log = self.log
        notificationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeServerRequiresAllActiveOwnedIdentitiesToRegisterToPushNotifications(within: NotificationCenter.default) {
                os_log("Since the server reported that we need to register to push notification, we do so now", log: log, type: .info)
                Task { [weak self] in await self?.requestRegisterToPushNotificationsForAllActiveOwnedIdentities() }
            },
            ObvMessengerSettingsNotifications.observeReceiveCallsOnThisDeviceSettingDidChange { [weak self] in
                Task { [weak self] in await self?.requestRegisterToPushNotificationsForAllActiveOwnedIdentities() }
            },
            ObvEngineNotificationNew.observeEngineRequiresOwnedIdentityToRegisterToPushNotifications(within: NotificationCenter.default) { (ownedCryptoId, performOwnedDeviceDiscoveryOnFinish)  in
                Task { [weak self] in
                    await self?.requestRegisterToPushNotificationsForAllActiveOwnedIdentities()
                    if performOwnedDeviceDiscoveryOnFinish {
                        await self?.startOwnedDeviceDiscoveryProtocol(ownedCryptoId: ownedCryptoId)
                    }
                }
            }
        ])
    }
    
    
    /// This is called in the case where, during a owned device discovery protocol, we realized that the current device is not known to the server. In that case,
    /// we want to register to push notification (so that the current device is known to the server), then restart an owned device discovery to allow the preKey upload mechanism
    /// to be performed.
    private func startOwnedDeviceDiscoveryProtocol(ownedCryptoId: ObvCryptoId) async {
        
        let obvEngine = await NewAppStateManager.shared.waitUntilAppIsInitialized()

        do {
            try await obvEngine.performOwnedDeviceDiscovery(ownedCryptoId: ownedCryptoId)
        } catch {
            os_log("Failed to start owned device discovery protocol: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
        
    }
    

    func requestRegisterToPushNotificationsForAllActiveOwnedIdentities() async {
        
        ObvDisplayableLogs.shared.log("[🚩] ObvPushNotificationManager.requestRegisterToPushNotificationsForAllActiveOwnedIdentities()")

        let obvEngine = await NewAppStateManager.shared.waitUntilAppIsInitialized()
        
        let defaultDeviceNameForFirstRegistration = await UIDevice.current.preciseModel
        
        let tokens: (pushToken: Data, voipToken: Data?)?
        if ObvMessengerConstants.areRemoteNotificationsAvailable {
            if let _currentDeviceToken = currentDeviceToken {
                let voipToken = ObvMessengerSettings.VoIP.receiveCallsOnThisDevice ? currentVoipToken : nil
                tokens = (_currentDeviceToken, voipToken)
            } else {
                tokens = nil
            }
        } else {
            tokens = nil
        }
        
        do {
            os_log("🍎 Will call registerToPushNotificationFor (tokens is %{public}@, voipToken is %{public}@)", log: log, type: .info, tokens == nil ? "nil" : "set", tokens?.voipToken == nil ? "nil" : "set")
            try await obvEngine.requestRegisterToPushNotificationsForAllActiveOwnedIdentities(deviceTokens: tokens, defaultDeviceNameForFirstRegistration: defaultDeviceNameForFirstRegistration)
            os_log("🍎 Youpi, we successfully requested to register to remote push notifications", log: log, type: .info)
        } catch {
            os_log("🍎 We Could not register to push notifications", log: log, type: .fault)
            return
        }

    }
    
    
    func userRequestedReactivationOf(ownedCryptoId: ObvCryptoId, replacedDeviceIdentifier: Data?) async throws {
        
        let obvEngine = await NewAppStateManager.shared.waitUntilAppIsInitialized()
        
        let deviceNameForFirstRegistration = await UIDevice.current.preciseModel
        
        let tokens: (pushToken: Data, voipToken: Data?)?
        if ObvMessengerConstants.areRemoteNotificationsAvailable {
            if let _currentDeviceToken = currentDeviceToken {
                let voipToken = ObvMessengerSettings.VoIP.receiveCallsOnThisDevice ? currentVoipToken : nil
                tokens = (_currentDeviceToken, voipToken)
            } else {
                tokens = nil
            }
        } else {
            tokens = nil
        }

        do {
            try await obvEngine.reactivateOwnedIdentity(ownedCryptoId: ownedCryptoId, deviceTokens: tokens, deviceNameForFirstRegistration: deviceNameForFirstRegistration, replacedDeviceIdentifier: replacedDeviceIdentifier)
        } catch {
            os_log("🍎 We could not reactivate owned identity", log: log, type: .fault)
            throw error
        }
        
        os_log("🍎 Youpi, we successfully reactivated the owned identity", log: log, type: .info)

    }
    
    
    func updateKeycloakPushTopicsIfNeeded(ownedCryptoId: ObvCryptoId, pushTopics: Set<String>) async throws {
        
        let obvEngine = await NewAppStateManager.shared.waitUntilAppIsInitialized()

        let deviceNameForFirstRegistration = await UIDevice.current.preciseModel

        let tokens: (pushToken: Data, voipToken: Data?)?
        if ObvMessengerConstants.areRemoteNotificationsAvailable {
            if let _currentDeviceToken = currentDeviceToken {
                let voipToken = ObvMessengerSettings.VoIP.receiveCallsOnThisDevice ? currentVoipToken : nil
                tokens = (_currentDeviceToken, voipToken)
            } else {
                tokens = nil
            }
        } else {
            tokens = nil
        }

        do {
            try await obvEngine.updateKeycloakPushTopicsIfNeeded(ownedCryptoId: ownedCryptoId, deviceTokens: tokens, deviceNameForFirstRegistration: deviceNameForFirstRegistration, pushTopics: pushTopics)
            os_log("🍎 Youpi, we successfully requested the reactivation of the owned identity", log: log, type: .info)
        } catch {
            os_log("🍎 We could not reactivate owned identity", log: log, type: .fault)
            return
        }

    }
        
}
