/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import CoreData
import ObvEngine
import CoreDataStack
import ObvTypes


final class ObvOwnedIdentityCoordinator {
    
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ObvOwnedIdentityCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    private let internalQueue: OperationQueue
    
    init(obvEngine: ObvEngine, operationQueue: OperationQueue) {
        self.obvEngine = obvEngine
        self.internalQueue = operationQueue
        listenToNotifications()
    }

    private func listenToNotifications() {
        
        // Engine notifications
        
        observationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeUpdatedOwnedIdentity(within: NotificationCenter.default, queue: internalQueue) { [weak self] (ownedIdentity) in
                self?.processUpdatedOwnedIdentityNotification(obvOwnedIdentity: ownedIdentity)
            },
            ObvEngineNotificationNew.observeOwnedIdentityWasDeactivated(within: NotificationCenter.default, queue: internalQueue) { [weak self] (ownedCryptoId) in
                self?.ownedIdentityWasDeactivated(ownedCryptoId: ownedCryptoId)
            },
            ObvEngineNotificationNew.observeOwnedIdentityWasReactivated(within: NotificationCenter.default, queue: internalQueue) { [weak self] (ownedCryptoId) in
                self?.ownedIdentityWasReactivated(ownedCryptoId: ownedCryptoId)
            },
            ObvEngineNotificationNew.observeNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(within: NotificationCenter.default, queue: internalQueue) { [weak self] (ownedIdentity, apiKeyStatus, apiPermissions, apiKeyExpirationDate) in
                self?.processNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentityNotification(ownedIdentity: ownedIdentity, apiKeyStatus: apiKeyStatus, apiPermissions: apiPermissions, apiKeyExpirationDate: apiKeyExpirationDate.value)
            },
            ObvEngineNotificationNew.observePublishedPhotoOfOwnedIdentityHasBeenUpdated(within: NotificationCenter.default, queue: internalQueue) { [weak self] ownedIdentity in
                self?.processOwnedIdentityPhotoHasBeenUpdated(ownedIdentity: ownedIdentity)
            },
        ])

        // Internal Notifications
        
        observeNewPersistedObvOwnedIdentityNotifications()
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeUserWantsToBindOwnedIdentityToKeycloak(queue: internalQueue) { [weak self] (ownedCryptoId, obvKeycloakState, keycloakUserId, completionHandler) in
                self?.processUserWantsToBindOwnedIdentityToKeycloakNotification(ownedCryptoId: ownedCryptoId, obvKeycloakState: obvKeycloakState, keycloakUserId: keycloakUserId, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeUserWantsToUnbindOwnedIdentityFromKeycloak(queue: internalQueue) { [weak self] (ownedCryptoId, completionHandler) in
                self?.processUserWantsToUnbindOwnedIdentityFromKeycloakNotification(ownedCryptoId: ownedCryptoId, completion: completionHandler)
            }
        ])
        
    }
}


extension ObvOwnedIdentityCoordinator {
    
    private func observeNewPersistedObvOwnedIdentityNotifications() {
        let log = self.log
        let token = ObvMessengerInternalNotification.observeNewPersistedObvOwnedIdentity(queue: internalQueue) { ownedCryptoId in
            os_log("We received an NewPersistedObvOwnedIdentity notification", log: log, type: .info)
            // Fetch the owned identity from DB. If it is active, we want to kick other devices on next register to push notifications.
            // This works because:
            // Case 1: the owned identity is new, created on this device, and the kick does nothing
            // Case 2: the owned identity was restored from a backup, and we *do* want to kick other devices
            var ownedIdentityIsActive: Bool?
            ObvStack.shared.performBackgroundTaskAndWait { context in
                do {
                    guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else {
                        os_log("Could not register to push notification since no owned identity could be found", log: log, type: .fault)
                        assertionFailure()
                        return
                    }
                    ownedIdentityIsActive = ownedIdentity.isActive
                } catch {
                    os_log("Failed to register to push notification on owned identity creation: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
            }
            guard let ownedIdentityIsActive = ownedIdentityIsActive else { assertionFailure(); return }
            DispatchQueue.main.async {
                if ownedIdentityIsActive {
                    ObvPushNotificationManager.shared.doKickOtherDevicesOnNextRegister()
                }
                ObvPushNotificationManager.shared.tryToRegisterToPushNotifications()
            }
        }
        observationTokens.append(token)
    }
    

    private func ownedIdentityWasDeactivated(ownedCryptoId: ObvCryptoId) {
        assert(OperationQueue.current == internalQueue)
        let log = self.log
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            guard let persistedObvOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else {
                os_log("Could not get persisted owned identity", log: log, type: .error)
                assertionFailure()
                return
            }
            persistedObvOwnedIdentity.deactivate()
            do {
                try context.save(logOnFailure: log)
            } catch let error {
                os_log("Could not deactivate owned identity at the app level %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
    }

    
    private func ownedIdentityWasReactivated(ownedCryptoId: ObvCryptoId) {
        assert(OperationQueue.current == internalQueue)
        let log = self.log
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            guard let persistedObvOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else {
                os_log("Could not get persisted owned identity", log: log, type: .error)
                assertionFailure()
                return
            }
            persistedObvOwnedIdentity.activate()
            do {
                try context.save(logOnFailure: log)
            } catch let error {
                os_log("Could not activate owned identity at the app level %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
    }

    
    /// We update the PersistedObvOwnedIdentity each time we receive a notification from the engine indicating that the published details of the corresponding ObvOwnedIdentity have changed.
    private func processUpdatedOwnedIdentityNotification(obvOwnedIdentity: ObvOwnedIdentity) {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            guard let persistedObvOwnedIdentity = try? PersistedObvOwnedIdentity.get(persisted: obvOwnedIdentity, within: context) else {
                os_log("Could not get persisted owned identity", log: log, type: .error)
                return
            }

            do {
                try persistedObvOwnedIdentity.update(with: obvOwnedIdentity)
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could not update PersistedObvOwnedIdentity", log: log, type: .error)
            }
            
        }

    }
    
    private func processNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentityNotification(ownedIdentity: ObvCryptoId, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?) {
        let log = self.log
        ObvStack.shared.performBackgroundTask { (context) in
            guard let persistedOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedIdentity, within: context) else {
                os_log("Could not get owned identity", log: log, type: .fault)
                assertionFailure()
                return
            }
            persistedOwnedIdentity.set(apiKeyStatus: apiKeyStatus, apiPermissions: apiPermissions, apiKeyExpirationDate: apiKeyExpirationDate)
            do {
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could not save api key status, permissions, and expiration date: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }

    }


    private func processOwnedIdentityPhotoHasBeenUpdated(ownedIdentity: ObvOwnedIdentity) {
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            guard let persistedOwnedIdentity = try? PersistedObvOwnedIdentity.get(persisted: ownedIdentity, within: context) else { return }
            persistedOwnedIdentity.updatePhotoURL(with: ownedIdentity.publishedIdentityDetails.photoURL)
            do {
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could set the newPublishedDetails flag on a persisted contact", log: log, type: .fault)
            }
        }
    }
    
    
    private func processUserWantsToBindOwnedIdentityToKeycloakNotification(ownedCryptoId: ObvCryptoId, obvKeycloakState: ObvKeycloakState, keycloakUserId: String, completionHandler: @escaping (Bool) -> Void) {
        let log = self.log
        do {
            try obvEngine.bindOwnedIdentityToKeycloak(ownedCryptoId: ownedCryptoId, keycloakState: obvKeycloakState, keycloakUserId: keycloakUserId) { result in
                switch result {
                case .failure(let error):
                    os_log("Engine failed to bind owned identity to keycloak server: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    completionHandler(false)
                    return
                case .success:
                    KeycloakManager.shared.registerKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoId, firstKeycloakBinding: true)
                    KeycloakManager.shared.uploadOwnIdentity(ownedCryptoId: ownedCryptoId) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .failure(let error):
                                os_log("Could not upload owned identity to the Keycloak server", log: log, type: .fault, error.localizedDescription)
                                completionHandler(false)
                            case .success:
                                completionHandler(true)
                            }
                        }
                    }
                    
                }
            }
        } catch {
            os_log("The call to bindOwnedIdentityToKeycloak failed: %{public}@", log: log, type: .fault, error.localizedDescription)
            completionHandler(false)
            assertionFailure()
        }

    }

    
    private func processUserWantsToUnbindOwnedIdentityFromKeycloakNotification(ownedCryptoId: ObvCryptoId, completion: @escaping (Bool) -> Void) {
        KeycloakManager.shared.unregisterKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoId) { result in
            switch result {
            case .failure:
                completion(false)
            case .success:
                completion(true)
            }
        }
    }
    
}
