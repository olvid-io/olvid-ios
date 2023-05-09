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
import CoreData
import ObvEngine
import CoreDataStack
import ObvTypes
import OlvidUtils


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
            ObvEngineNotificationNew.observeOwnedIdentityCapabilitiesWereUpdated(within: NotificationCenter.default) { [weak self] obvOwnedIdentity in
                self?.processOwnedIdentityCapabilitiesWereUpdated(ownedIdentity: obvOwnedIdentity)
            },
            ObvEngineNotificationNew.observeOwnedIdentityWasDeleted(within: NotificationCenter.default) { [weak self] in
                self?.processOwnedIdentityWasDeleted()
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
            },
            ObvMessengerInternalNotification.observeUiRequiresSignedOwnedDetails { [weak self] ownedIdentityCryptoId, completion in
                self?.processUiRequiresSignedOwnedDetails(ownedIdentityCryptoId: ownedIdentityCryptoId, completion: completion)
            },
            ObvMessengerInternalNotification.observeUserWantsToHideOwnedIdentity { [weak self] ownedCryptoId, password in
                self?.processUserWantsToHideOwnedIdentity(ownedCryptoId: ownedCryptoId, password: password)
            },
            ObvMessengerInternalNotification.observeUserWantsToUnhideOwnedIdentity { [weak self] ownedCryptoId in
                self?.processUserWantsToUnhideOwnedIdentity(ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observeUserWantsToDeleteOwnedIdentityAndHasConfirmed { [weak self] ownedCryptoId, notifyContacts in
                self?.processUserWantsToDeleteOwnedIdentityAndHasConfirmed(ownedCryptoId: ownedCryptoId, notifyContacts: notifyContacts)
            },
            ObvMessengerInternalNotification.observeRecomputeNumberOfNewMessagesForAllOwnedIdentities { [weak self] in
                self?.recomputeNumberOfNewMessagesForAllOwnedIdentities()
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdateOwnedCustomDisplayName { [weak self] ownedCryptoId, newCustomDisplayName in
                self?.updateOwnedNickname(ownedCryptoId: ownedCryptoId, newCustomDisplayName: newCustomDisplayName)
            },
        ])
        
    }
    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        if forTheFirstTime {
            recomputeNumberOfNewMessagesForAllOwnedIdentities()
        }
    }

}


extension ObvOwnedIdentityCoordinator {
    
    private func updateOwnedNickname(ownedCryptoId: ObvCryptoId, newCustomDisplayName: String?) {
        let op1 = UpdateOwnedCustomDisplayNameOperation(ownedCryptoId: ownedCryptoId, newCustomDisplayName: newCustomDisplayName)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        if composedOp.isCancelled {
            assertionFailure()
        }
    }

    
    private func recomputeNumberOfNewMessagesForAllOwnedIdentities() {
        let op1 = RefreshNumberOfNewMessagesForAllOwnedIdentitiesOperation()
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        if composedOp.isCancelled {
            assertionFailure()
        }
    }
    
    
    private func processUserWantsToDeleteOwnedIdentityAndHasConfirmed(ownedCryptoId: ObvCryptoId, notifyContacts: Bool) {
        let op1 = DeleteOwnedIdentityOperation(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine, notifyContacts: notifyContacts, delegate: self)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        composedOp.queuePriority = .veryHigh
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        if composedOp.isCancelled {
            assertionFailure()
        }
    }
    
    private func processUserWantsToUnhideOwnedIdentity(ownedCryptoId: ObvCryptoId) {
        let op1 = UnhideOwnedIdentityOperation(ownedCryptoId: ownedCryptoId)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        composedOp.queuePriority = .veryHigh
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        if composedOp.isCancelled {
            assertionFailure()
        }
    }
    
    
    private func processUserWantsToHideOwnedIdentity(ownedCryptoId: ObvCryptoId, password: String) {
        
        let op1 = HideOwnedIdentityOperation(ownedCryptoId: ownedCryptoId, password: password)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        composedOp.queuePriority = .veryHigh
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        if composedOp.isCancelled {
            ObvMessengerInternalNotification.failedToHideOwnedIdentity(ownedCryptoId: ownedCryptoId)
                .postOnDispatchQueue()
        }

    }
    
    
    private func processUiRequiresSignedOwnedDetails(ownedIdentityCryptoId: ObvCryptoId, completion: @escaping (SignedUserDetails?) -> Void) {
        let log = self.log
        do {
            try obvEngine.getSignedOwnedDetails(ownedIdentity: ownedIdentityCryptoId) { result in
                switch result {
                case .failure(let error):
                    os_log("Failed to obtain signed owned details from engine: %{public}@", log: log, type: .fault, error.localizedDescription)
                    completion(nil)
                case .success(let signedContactDetails):
                    completion(signedContactDetails)
                }
            }
        } catch {
            os_log("The call to processUiRequiresSignedOwnedDetails failed: %{public}@", log: log, type: .fault, error.localizedDescription)
            completion(nil)
        }
    }

    
    private func observeNewPersistedObvOwnedIdentityNotifications() {
        let log = self.log
        let obvEngine = self.obvEngine
        let token = ObvMessengerCoreDataNotification.observeNewPersistedObvOwnedIdentity(queue: internalQueue) { ownedCryptoId in
            os_log("We received an NewPersistedObvOwnedIdentity notification", log: log, type: .info)
            Task { try? await obvEngine.downloadMessagesAndConnectWebsockets() }
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
            Task {
                if ownedIdentityIsActive {
                    await ObvPushNotificationManager.shared.doKickOtherDevicesOnNextRegister()
                }
                await ObvPushNotificationManager.shared.tryToRegisterToPushNotifications()
                // When a new owned identity is created, we request an update of the owned identity capabilities
                do {
                    try obvEngine.setCapabilitiesOfCurrentDeviceForAllOwnedIdentities(ObvMessengerConstants.supportedObvCapabilities)
                } catch {
                    assertionFailure("Could not set capabilities")
                }
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
            do {
                guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedIdentity, within: context) else {
                    return
                }
                persistedOwnedIdentity.set(apiKeyStatus: apiKeyStatus, apiPermissions: apiPermissions, apiKeyExpirationDate: apiKeyExpirationDate)
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
    
    
    private func processOwnedIdentityCapabilitiesWereUpdated(ownedIdentity: ObvOwnedIdentity) {
        assert(OperationQueue.current != internalQueue)
        let op1 = SyncPersistedObvOwnedIdentitiesWithEngineOperation(obvEngine: obvEngine)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        if composedOp.isCancelled {
            assertionFailure()
        }
    }
    
    
    private func processOwnedIdentityWasDeleted() {
        assert(OperationQueue.current != internalQueue)
        let op1 = SyncPersistedObvOwnedIdentitiesWithEngineOperation(obvEngine: obvEngine)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        if composedOp.isCancelled {
            assertionFailure()
        }
    }
    
    
    private func processUserWantsToBindOwnedIdentityToKeycloakNotification(ownedCryptoId: ObvCryptoId, obvKeycloakState: ObvKeycloakState, keycloakUserId: String, completionHandler: @escaping (Bool) -> Void) {
        let log = self.log
        do {
            try obvEngine.bindOwnedIdentityToKeycloak(ownedCryptoId: ownedCryptoId, keycloakState: obvKeycloakState, keycloakUserId: keycloakUserId) { result in
                DispatchQueue.main.async {
                    Task {
                        assert(Thread.isMainThread)
                        switch result {
                        case .failure(let error):
                            os_log("Engine failed to bind owned identity to keycloak server: %{public}@", log: log, type: .fault, error.localizedDescription)
                            assertionFailure()
                            completionHandler(false)
                            return
                        case .success:
                            await KeycloakManagerSingleton.shared.registerKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoId, firstKeycloakBinding: true)
                            do {
                                try await KeycloakManagerSingleton.shared.uploadOwnIdentity(ownedCryptoId: ownedCryptoId)
                            } catch let error as KeycloakManager.UploadOwnedIdentityError {
                                os_log("Could not upload owned identity to the Keycloak server: %{public}@", log: log, type: .fault, error.localizedDescription)
                                completionHandler(false)
                                return
                            } catch {
                                os_log("Could not upload owned identity to the Keycloak server: %{public}@", log: log, type: .fault, error.localizedDescription)
                                assertionFailure("Unexpected error")
                                completionHandler(false)
                                return
                            }
                            completionHandler(true)
                            return
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

    
    private func processUserWantsToUnbindOwnedIdentityFromKeycloakNotification(ownedCryptoId: ObvCryptoId, completion: @MainActor @escaping (Bool) -> Void) {
        Task {
            do {
                try await KeycloakManagerSingleton.shared.unregisterKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoId)
                await completion(true)
            } catch {
                await completion(false)
            }
        }
    }
    
}


// MARK: - DeleteOwnedIdentityOperationDelegate

extension ObvOwnedIdentityCoordinator: DeleteOwnedIdentityOperationDelegate {
    
    func deleteHiddenOwnedIdentityAsTheLastVisibleOwnedIdentityIsBeingDeleted(hiddenOwnedCryptoId: ObvCryptoId, notifyContacts: Bool) {
        // We make sure we are not bloquing the caller to prevent deadlocks
        Task {
            processUserWantsToDeleteOwnedIdentityAndHasConfirmed(ownedCryptoId: hiddenOwnedCryptoId, notifyContacts: notifyContacts)
        }
    }
    
}
