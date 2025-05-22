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
import os.log
import CoreData
import ObvEngine
import ObvCoreDataStack
import ObvTypes
import OlvidUtils
import ObvUICoreData
import ObvAppCoreConstants
import ObvKeycloakManager


final class ObvOwnedIdentityCoordinator: OlvidCoordinator {
    
    let obvEngine: ObvEngine
    static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ObvOwnedIdentityCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    let coordinatorsQueue: OperationQueue
    let queueForComposedOperations: OperationQueue
    let queueForSyncHintsComputationOperation: OperationQueue
    weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?

    init(obvEngine: ObvEngine, coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue, queueForSyncHintsComputationOperation: OperationQueue) {
        self.obvEngine = obvEngine
        self.coordinatorsQueue = coordinatorsQueue
        self.queueForComposedOperations = queueForComposedOperations
        self.queueForSyncHintsComputationOperation = queueForSyncHintsComputationOperation
        listenToNotifications()
    }

    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func listenToNotifications() {
        
        Task {
            await PersistedObvOwnedIdentity.addObvObserver(self)
        }
        
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
            ObvEngineNotificationNew.observeKeycloakSynchronizationRequired(within: NotificationCenter.default) { [weak self] ownedCryptoId in
                Task { [weak self] in await self?.processKeycloakSynchronizationRequired(ownedCryptoId: ownedCryptoId) }
            },
            ObvEngineNotificationNew.observeOwnedIdentityWasDeleted(within: NotificationCenter.default) { [weak self] in
                Task { [weak self] in await self?.processOwnedIdentityWasDeleted() }
            },
            ObvEngineNotificationNew.observeOwnedIdentityCapabilitiesWereUpdated(within: NotificationCenter.default) { [weak self] obvOwnedIdentity in
                Task { [weak self] in await self?.processOwnedIdentityCapabilitiesWereUpdated(ownedIdentity: obvOwnedIdentity) }
            },
            ObvEngineNotificationNew.observeAnOwnedDeviceWasDeleted(within: NotificationCenter.default) { [weak self] ownedCryptoId in
                Task { [weak self] in await self?.syncPersistedObvOwnedDevicesWithEngine(ownedCryptoId: ownedCryptoId) }
            },
            ObvEngineNotificationNew.observeDeletedObliviousChannelWithRemoteOwnedDevice(within: NotificationCenter.default) { [weak self] in
                Task { [weak self] in await self?.syncPersistedObvOwnedDevicesWithEngine(ownedCryptoId: nil) }
            },
            ObvEngineNotificationNew.observeNewConfirmedObliviousChannelWithRemoteOwnedDevice(within: NotificationCenter.default) { [weak self] in
                Task { [weak self] in await self?.syncPersistedObvOwnedDevicesWithEngine(ownedCryptoId: nil) }
            },
            ObvEngineNotificationNew.observeNewRemoteOwnedDevice(within: NotificationCenter.default) { [weak self] in
                Task { [weak self] in await self?.syncPersistedObvOwnedDevicesWithEngine(ownedCryptoId: nil) }
            },
            ObvEngineNotificationNew.observeAnOwnedDeviceWasUpdated(within: NotificationCenter.default) { [weak self] ownedCryptoId in
                Task { [weak self] in await self?.syncPersistedObvOwnedDevicesWithEngine(ownedCryptoId: ownedCryptoId) }
            },
        ])

        // Internal Notifications
        
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeUserWantsToBindOwnedIdentityToKeycloak { (ownedCryptoId, obvKeycloakState, keycloakUserId, completionHandler) in
                Task { [weak self] in
                    await self?.processUserWantsToBindOwnedIdentityToKeycloakNotification(ownedCryptoId: ownedCryptoId, obvKeycloakState: obvKeycloakState, keycloakUserId: keycloakUserId, completionHandler: completionHandler)
                }
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
            nameCurrentDeviceWithoutSpecifiedName()
        }
    }

}


// MARK: - Implementing PersistedObvOwnedIdentityObserver

extension ObvOwnedIdentityCoordinator: PersistedObvOwnedIdentityObserver {
    
    func newPersistedObvOwnedIdentity(ownedCryptoId: ObvTypes.ObvCryptoId, isActive: Bool) async {
        await processNewPersistedObvOwnedIdentity(ownedCryptoId: ownedCryptoId, isActive: isActive)
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

    
    private func nameCurrentDeviceWithoutSpecifiedName() {
        let op1 = NameCurrentDeviceWithoutSpecifiedNameOperation(obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
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

    
    private func processNewPersistedObvOwnedIdentity(ownedCryptoId: ObvCryptoId, isActive: Bool) async {
        await ObvPushNotificationManager.shared.requestRegisterToPushNotificationsForAllActiveOwnedIdentities()
        try? await obvEngine.downloadMessagesAndConnectWebsockets()
        try? obvEngine.setCapabilitiesOfCurrentDeviceForAllOwnedIdentities(ObvMessengerConstants.supportedObvCapabilities)
    }
    

    private func ownedIdentityWasDeactivated(ownedCryptoId: ObvCryptoId) {
        let op1 = UpdateOwnedIdentityAsItWasDeactivatedOperation(ownedCryptoId: ownedCryptoId)
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
    
    
    private func processKeycloakSynchronizationRequired(ownedCryptoId: ObvCryptoId) async {
        do {
            try await KeycloakManagerSingleton.shared.syncAllManagedIdentities()
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    
    private func processOwnedIdentityWasDeleted() async {
        let ops = await getOperationsRequiredToSyncOwnedIdentities(isRestoringSyncSnapshotOrBackup: false)
        await coordinatorsQueue.addAndAwaitOperations(ops)
        ops.forEach { assert($0.isFinished && !$0.isCancelled) }
    }

    
    private func processOwnedIdentityCapabilitiesWereUpdated(ownedIdentity: ObvOwnedIdentity) async {
        let op1 = SyncPersistedObvOwnedIdentityWithEngineOperation(syncType: .syncWithEngine(ownedCryptoId: ownedIdentity.cryptoId), obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
    }

    
    /// Called whenever we receive a notification indicating that a secure channel has been deleted/confirmed with a remote owned device.
    private func syncPersistedObvOwnedDevicesWithEngine(ownedCryptoId: ObvCryptoId?) async {
        
        // If an owned identity is specified, make sure it is properly synced within the app
        if ownedCryptoId != nil {
            let ops = await getOperationsRequiredToSyncOwnedIdentities(isRestoringSyncSnapshotOrBackup: false)
            await coordinatorsQueue.addAndAwaitOperations(ops)
        }
        
        // We know the owned identity exists at the app level, we can sync the owned devices
        let operationsToQueueOnQueueForComposedOperation: [Operation]
        if let ownedCryptoId {
            operationsToQueueOnQueueForComposedOperation = await getOperationsRequiredToSyncOwnedDevices(scope: .ownedDevicesOfOwnedIdentity(ownedCryptoId: ownedCryptoId))
        } else {
            operationsToQueueOnQueueForComposedOperation = await getOperationsRequiredToSyncOwnedDevices(scope: .allOwnedDevices)
        }
        await coordinatorsQueue.addAndAwaitOperations(operationsToQueueOnQueueForComposedOperation)
        
    }

    
    private func processUserWantsToBindOwnedIdentityToKeycloakNotification(ownedCryptoId: ObvCryptoId, obvKeycloakState: ObvKeycloakState, keycloakUserId: String, completionHandler: @escaping (Error?) -> Void) async {
        
        do {
            try await KeycloakManagerSingleton.shared.uploadOwnIdentity(ownedCryptoId: ownedCryptoId, keycloakUserIdAndState: (keycloakUserId, obvKeycloakState))
        } catch let error as KeycloakManager.UploadOwnedIdentityError {
            os_log("Could not upload owned identity to the Keycloak server: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            return completionHandler(error)
        } catch {
            os_log("Could not upload owned identity to the Keycloak server: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure("Unexpected error")
            return completionHandler(error)
        }
        
        completionHandler(nil)
    
        // Last, make sure we always try to perform a sync
        
        try? await KeycloakManagerSingleton.shared.syncAllManagedIdentities()
        
    }

}


// MARK: - Processing user's calls, relayed by the RootViewController

extension ObvOwnedIdentityCoordinator {
    
    func processUserWantsToDeleteOwnedIdentityAndHasConfirmed(ownedCryptoId: ObvCryptoId, globalOwnedIdentityDeletion: Bool) async throws {
        
        let op1 = DetermineHiddenOwnedIdentitiesToDeleteOnOwnedIdentityDeletionRequestOperation(ownedCryptoId: ownedCryptoId)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard let hiddenCryptoIdsToDelete = op1.hiddenCryptoIdsToDelete else {
            assertionFailure()
            throw ObvError.couldNotDetermineHiddenIdentitiesToDelete
        }
        
        for hiddenOwnedCryptoIdToDelete in hiddenCryptoIdsToDelete {
            try await obvEngine.deleteOwnedIdentity(with: hiddenOwnedCryptoIdToDelete, globalOwnedIdentityDeletion: globalOwnedIdentityDeletion)
        }
        
        try await obvEngine.deleteOwnedIdentity(with: ownedCryptoId, globalOwnedIdentityDeletion: globalOwnedIdentityDeletion)

        let ops = await getOperationsRequiredToSyncOwnedIdentities(isRestoringSyncSnapshotOrBackup: false)
        await coordinatorsQueue.addAndAwaitOperations(ops)

    }

    
}


// MARK: - Errors

extension ObvOwnedIdentityCoordinator {
    
    enum ObvError: Error {
        case couldNotDetermineHiddenIdentitiesToDelete
    }
    
}
