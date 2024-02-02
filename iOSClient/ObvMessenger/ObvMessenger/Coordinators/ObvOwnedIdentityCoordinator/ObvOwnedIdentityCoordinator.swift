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
import CoreData
import ObvEngine
import CoreDataStack
import ObvTypes
import OlvidUtils
import ObvUICoreData


final class ObvOwnedIdentityCoordinator {
    
    private let obvEngine: ObvEngine
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ObvOwnedIdentityCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    private let coordinatorsQueue: OperationQueue
    private let queueForComposedOperations: OperationQueue
    weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?

    init(obvEngine: ObvEngine, coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue) {
        self.obvEngine = obvEngine
        self.coordinatorsQueue = coordinatorsQueue
        self.queueForComposedOperations = queueForComposedOperations
        listenToNotifications()
    }

    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func listenToNotifications() {
        
        // Engine notifications
        
        observationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeUpdatedOwnedIdentity(within: NotificationCenter.default) { [weak self] ownedIdentity in
                self?.processUpdatedOwnedIdentityNotification(obvOwnedIdentity: ownedIdentity)
            },
            ObvEngineNotificationNew.observeOwnedIdentityWasDeactivated(within: NotificationCenter.default) { [weak self] ownedCryptoId in
                self?.ownedIdentityWasDeactivated(ownedCryptoId: ownedCryptoId)
            },
            ObvEngineNotificationNew.observeOwnedIdentityWasReactivated(within: NotificationCenter.default) { [weak self] ownedCryptoId in
                self?.ownedIdentityWasReactivated(ownedCryptoId: ownedCryptoId)
            },
            ObvEngineNotificationNew.observeNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(within: NotificationCenter.default) { [weak self] (ownedIdentity, apiKeyStatus, apiPermissions, apiKeyExpirationDate) in
                self?.processNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentityNotification(ownedIdentity: ownedIdentity, apiKeyStatus: apiKeyStatus, apiPermissions: apiPermissions, apiKeyExpirationDate: apiKeyExpirationDate)
            },
            ObvEngineNotificationNew.observePublishedPhotoOfOwnedIdentityHasBeenUpdated(within: NotificationCenter.default) { [weak self] ownedIdentity in
                self?.processOwnedIdentityPhotoHasBeenUpdated(ownedIdentity: ownedIdentity)
            },
            ObvEngineNotificationNew.observeOwnedIdentityCapabilitiesWereUpdated(within: NotificationCenter.default) { [weak self] obvOwnedIdentity in
                self?.processOwnedIdentityCapabilitiesWereUpdated(ownedIdentity: obvOwnedIdentity)
            },
            ObvEngineNotificationNew.observeOwnedIdentityWasDeleted(within: NotificationCenter.default) { [weak self] in
                self?.processOwnedIdentityWasDeleted()
            },
            ObvEngineNotificationNew.observeKeycloakSynchronizationRequired(within: NotificationCenter.default) { [weak self] ownedCryptoId in
                Task { [weak self] in await self?.processKeycloakSynchronizationRequired(ownedCryptoId: ownedCryptoId) }
            },
            ObvEngineNotificationNew.observeDeletedObliviousChannelWithRemoteOwnedDevice(within: NotificationCenter.default) { [weak self] in
                self?.syncPersistedObvOwnedDevicesWithEngine()
            },
            ObvEngineNotificationNew.observeNewConfirmedObliviousChannelWithRemoteOwnedDevice(within: NotificationCenter.default) { [weak self] in
                self?.syncPersistedObvOwnedDevicesWithEngine()
            },
            ObvEngineNotificationNew.observeNewRemoteOwnedDevice(within: NotificationCenter.default) { [weak self] in
                self?.syncPersistedObvOwnedDevicesWithEngine()
            },
            ObvEngineNotificationNew.observeAnOwnedDeviceWasUpdated(within: NotificationCenter.default) { [weak self] ownedCryptoId in
                self?.syncPersistedObvOwnedDevicesWithEngine()
            },
            ObvEngineNotificationNew.observeAnOwnedDeviceWasDeleted(within: NotificationCenter.default) { [weak self] ownedCryptoId in
                self?.syncPersistedObvOwnedDevicesWithEngine()
            },
        ])

        // Internal Notifications
        
        observationTokens.append(contentsOf: [
            ObvMessengerCoreDataNotification.observeNewPersistedObvOwnedIdentity { [weak self] (ownedCryptoId, isActive) in
                self?.processNewPersistedObvOwnedIdentity(ownedCryptoId: ownedCryptoId, isActive: isActive)
            },
            ObvMessengerInternalNotification.observeUserWantsToBindOwnedIdentityToKeycloak { (ownedCryptoId, obvKeycloakState, keycloakUserId, completionHandler) in
                Task { [weak self] in
                    await self?.processUserWantsToBindOwnedIdentityToKeycloakNotification(ownedCryptoId: ownedCryptoId, obvKeycloakState: obvKeycloakState, keycloakUserId: keycloakUserId, completionHandler: completionHandler)
                }
            },
            ObvMessengerInternalNotification.observeUserWantsToUnbindOwnedIdentityFromKeycloak { (ownedCryptoId, completionHandler) in
                Task { [weak self] in await self?.processUserWantsToUnbindOwnedIdentityFromKeycloakNotification(ownedCryptoId: ownedCryptoId, completion: completionHandler) }
            },
            ObvMessengerInternalNotification.observeUiRequiresSignedOwnedDetails { [weak self] (ownedIdentityCryptoId, completion) in
                self?.processUiRequiresSignedOwnedDetails(ownedIdentityCryptoId: ownedIdentityCryptoId, completion: completion)
            },
            ObvMessengerInternalNotification.observeUserWantsToHideOwnedIdentity { [weak self] (ownedCryptoId, password) in
                self?.processUserWantsToHideOwnedIdentity(ownedCryptoId: ownedCryptoId, password: password)
            },
            ObvMessengerInternalNotification.observeUserWantsToUnhideOwnedIdentity { [weak self] ownedCryptoId in
                self?.processUserWantsToUnhideOwnedIdentity(ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observeUserWantsToDeleteOwnedIdentityAndHasConfirmed { [weak self] ownedCryptoId, globalOwnedIdentityDeletion in
                self?.processUserWantsToDeleteOwnedIdentityAndHasConfirmed(ownedCryptoId: ownedCryptoId, globalOwnedIdentityDeletion: globalOwnedIdentityDeletion)
            },
            ObvMessengerInternalNotification.observeRecomputeRecomputeBadgeCountForDiscussionsTabForAllOwnedIdentities { [weak self] in
                self?.recomputeBadgeCountsForAllOwnedIdentities()
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdateOwnedCustomDisplayName { [weak self] ownedCryptoId, newCustomDisplayName in
                self?.updateOwnedNickname(ownedCryptoId: ownedCryptoId, newCustomDisplayName: newCustomDisplayName)
            },
            ObvMessengerInternalNotification.observeSingleOwnedIdentityFlowViewControllerDidAppear { [weak self] ownedCryptoId in
                Task { [weak self] in await self?.processSingleOwnedIdentityFlowViewControllerDidAppear(ownedCryptoId: ownedCryptoId) }
            },
            ObvMessengerInternalNotification.observeAllPersistedInvitationCanBeMarkedAsOld { ownedCryptoId in
                Task { [weak self] in await self?.processAllPersistedInvitationCanBeMarkedAsOld(ownedCryptoId: ownedCryptoId) }
            },
        ])
        
    }
    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        if forTheFirstTime {
            recomputeBadgeCountsForAllOwnedIdentities()
            nameCurrentDeviceWithoutSpecifiedName()
        }
    }

}


extension ObvOwnedIdentityCoordinator {
    
    /// When the `SingleOwnedIdentityFlowViewController` is presented to the user, we want to refresh the list of devices.
    /// To do so, we always perform an owned device discovery.
    private func processSingleOwnedIdentityFlowViewControllerDidAppear(ownedCryptoId: ObvCryptoId) async {
        do {
            try await obvEngine.performOwnedDeviceDiscovery(ownedCryptoId: ownedCryptoId)
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }
    
    
    private func processAllPersistedInvitationCanBeMarkedAsOld(ownedCryptoId: ObvCryptoId) async {
        let op1 = MarkAllPersistedInvitationAsOldOperation(ownedCryptoId: ownedCryptoId)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    
    private func updateOwnedNickname(ownedCryptoId: ObvCryptoId, newCustomDisplayName: String?) {
        let op1 = UpdateOwnedCustomDisplayNameOperation(ownedCryptoId: ownedCryptoId, newCustomDisplayName: newCustomDisplayName, makeSyncAtomRequest: true, syncAtomRequestDelegate: syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    
    private func recomputeBadgeCountsForAllOwnedIdentities() {
        let op1 = RefreshBadgeCountsForAllOwnedIdentitiesOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func nameCurrentDeviceWithoutSpecifiedName() {
        let op1 = NameCurrentDeviceWithoutSpecifiedNameOperation(obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processUserWantsToDeleteOwnedIdentityAndHasConfirmed(ownedCryptoId: ObvCryptoId, globalOwnedIdentityDeletion: Bool) {
        let op1 = DeleteOwnedIdentityOperation(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine, globalOwnedIdentityDeletion: globalOwnedIdentityDeletion, delegate: self)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processUserWantsToUnhideOwnedIdentity(ownedCryptoId: ObvCryptoId) {
        let op1 = UnhideOwnedIdentityOperation(ownedCryptoId: ownedCryptoId)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processUserWantsToHideOwnedIdentity(ownedCryptoId: ObvCryptoId, password: String) {
        let op1 = HideOwnedIdentityOperation(ownedCryptoId: ownedCryptoId, password: password)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processUiRequiresSignedOwnedDetails(ownedIdentityCryptoId: ObvCryptoId, completion: @escaping (SignedObvKeycloakUserDetails?) -> Void) {
        do {
            try obvEngine.getSignedOwnedDetails(ownedIdentity: ownedIdentityCryptoId) { result in
                switch result {
                case .failure(let error):
                    os_log("Failed to obtain signed owned details from engine: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                    completion(nil)
                case .success(let signedContactDetails):
                    completion(signedContactDetails)
                }
            }
        } catch {
            os_log("The call to processUiRequiresSignedOwnedDetails failed: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            completion(nil)
        }
    }

    
    private func processNewPersistedObvOwnedIdentity(ownedCryptoId: ObvCryptoId, isActive: Bool) {
        Task {
            await ObvPushNotificationManager.shared.requestRegisterToPushNotificationsForAllActiveOwnedIdentities()
            try? await obvEngine.downloadMessagesAndConnectWebsockets()
            try? obvEngine.setCapabilitiesOfCurrentDeviceForAllOwnedIdentities(ObvMessengerConstants.supportedObvCapabilities)
        }
    }
    

    private func ownedIdentityWasDeactivated(ownedCryptoId: ObvCryptoId) {
        let op1 = UpdateOwnedIdentityAsItWasDeactivatedOperation(ownedCryptoId: ownedCryptoId)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    
    /// Called whenever we receive a notification indicating that a secure channel has been deleted/confirmed with a remote owned device.
    private func syncPersistedObvOwnedDevicesWithEngine() {
        let op1 = SyncPersistedObvOwnedDevicesWithEngineOperation(obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    
    private func ownedIdentityWasReactivated(ownedCryptoId: ObvCryptoId) {
        let op1 = UpdateOwnedIdentityAsItWasReactivatedOperation(ownedCryptoId: ownedCryptoId)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    
    /// We update the PersistedObvOwnedIdentity each time we receive a notification from the engine indicating that the published details of the corresponding ObvOwnedIdentity have changed.
    private func processUpdatedOwnedIdentityNotification(obvOwnedIdentity: ObvOwnedIdentity) {
        let op1 = UpdateOwnedIdentityOperation(obvOwnedIdentity: obvOwnedIdentity)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentityNotification(ownedIdentity: ObvCryptoId, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?) {
        let op1 = UpdateAPIKeyStatusAndPermissionsOfOwnedIdentityOperation(ownedCryptoId: ownedIdentity, apiKeyStatus: apiKeyStatus, apiPermissions: apiPermissions, apiKeyExpirationDate: apiKeyExpirationDate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }


    private func processOwnedIdentityPhotoHasBeenUpdated(ownedIdentity: ObvOwnedIdentity) {
        let op1 = UpdateProfilePictureOfOwnedIdentityOperation(obvOwnedIdentity: ownedIdentity)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processOwnedIdentityCapabilitiesWereUpdated(ownedIdentity: ObvOwnedIdentity) {
        let op1 = SyncPersistedObvOwnedIdentitiesWithEngineOperation(obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processOwnedIdentityWasDeleted() {
        let op1 = SyncPersistedObvOwnedIdentitiesWithEngineOperation(obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processKeycloakSynchronizationRequired(ownedCryptoId: ObvCryptoId) async {
        do {
            try await KeycloakManagerSingleton.shared.syncAllManagedIdentities()
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    
    private func processUserWantsToBindOwnedIdentityToKeycloakNotification(ownedCryptoId: ObvCryptoId, obvKeycloakState: ObvKeycloakState, keycloakUserId: String, completionHandler: @escaping (Bool) -> Void) async {
        
        do {
            try await obvEngine.bindOwnedIdentityToKeycloak(ownedCryptoId: ownedCryptoId, keycloakState: obvKeycloakState, keycloakUserId: keycloakUserId)
        } catch {
            os_log("The call to bindOwnedIdentityToKeycloak failed: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            completionHandler(false)
            return
        }

        await KeycloakManagerSingleton.shared.registerKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoId, firstKeycloakBinding: true)
        
        do {
            try await KeycloakManagerSingleton.shared.uploadOwnIdentity(ownedCryptoId: ownedCryptoId)
        } catch let error as KeycloakManager.UploadOwnedIdentityError {
            os_log("Could not upload owned identity to the Keycloak server: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            completionHandler(false)
            return
        } catch {
            os_log("Could not upload owned identity to the Keycloak server: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure("Unexpected error")
            completionHandler(false)
            return
        }
        
        completionHandler(true)
    
        // Last, make sure we always try to perform a sync
        
        try? await KeycloakManagerSingleton.shared.syncAllManagedIdentities()
        
    }

    
    private func processUserWantsToUnbindOwnedIdentityFromKeycloakNotification(ownedCryptoId: ObvCryptoId, completion: @MainActor @escaping (Bool) -> Void) async {
        do {
            try await KeycloakManagerSingleton.shared.unregisterKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoId)
            await completion(true)
        } catch {
            await completion(false)
        }
    }
    
}


// MARK: - DeleteOwnedIdentityOperationDelegate

extension ObvOwnedIdentityCoordinator: DeleteOwnedIdentityOperationDelegate {
    
    func deleteHiddenOwnedIdentityAsTheLastVisibleOwnedIdentityIsBeingDeleted(hiddenOwnedCryptoId: ObvCryptoId, globalOwnedIdentityDeletion: Bool) {
        processUserWantsToDeleteOwnedIdentityAndHasConfirmed(ownedCryptoId: hiddenOwnedCryptoId, globalOwnedIdentityDeletion: globalOwnedIdentityDeletion)
    }
    
}


// MARK: - Helpers

extension ObvOwnedIdentityCoordinator {
    
    private func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>) -> CompositionOfOneContextualOperation<T> {
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp
    }
    
}
