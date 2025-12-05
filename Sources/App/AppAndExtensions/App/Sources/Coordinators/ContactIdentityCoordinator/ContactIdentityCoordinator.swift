/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OSLog
import CoreData
import ObvEngine
import ObvCoreDataStack
import OlvidUtils
@preconcurrency import ObvTypes
import ObvUICoreData
import ObvSettings
import ObvAppCoreConstants
import ObvAppTypes


final class ContactIdentityCoordinator: OlvidCoordinator, ObvErrorMaker, @unchecked Sendable {
    
    let obvEngine: ObvEngine
    static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ContactIdentityCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    let coordinatorsQueue: OperationQueue
    let queueForComposedOperations: OperationQueue
    let queueForSyncHintsComputationOperation: OperationQueue
    weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?

    static let errorDomain = "ContactIdentityCoordinator"
    
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
                        
        // Internal notifications
        
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeUserWantsToEditContactNicknameAndPicture { [weak self] persistedContactObjectID, customDisplayName, customPhoto in
                self?.updateCustomNicknameAndPictureForContact(persistedContactObjectID: persistedContactObjectID, customDisplayName: customDisplayName, customPhoto: customPhoto)
            },
            ObvMessengerInternalNotification.observeUserWantsToChangeContactsSortOrder { [weak self] ownedCryptoId, sortOrder in
                self?.processUserWantToChangeContactsSortOrderNotification(ownedCryptoId: ownedCryptoId, sortOrder: sortOrder)
            },
            ObvMessengerInternalNotification.observeUiRequiresSignedContactDetails { [weak self] ownedIdentityCryptoId, contactCryptoId, completion in
                self?.processUiRequiresSignedContactDetails(ownedIdentityCryptoId: ownedIdentityCryptoId, contactCryptoId: contactCryptoId, completion: completion)
            },
        ])
        
        // Listening to ObvEngine Notification
        
        observationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeDeletedObliviousChannelWithContactDevice(within: NotificationCenter.default) { [weak self] obvContactIdentifier in
                Task { [weak self] in await self?.processDeletedObliviousChannelWithContactDevice(obvContactIdentifier: obvContactIdentifier) }
            },
            ObvEngineNotificationNew.observeNewObliviousChannelWithContactDevice(within: NotificationCenter.default) { [weak self] obvContactIdentifier in
                Task { [weak self] in await self?.processNewObliviousChannelWithContactDevice(obvContactIdentifier: obvContactIdentifier) }
            },
            ObvEngineNotificationNew.observeTrustedPhotoOfContactIdentityHasBeenUpdated(within: NotificationCenter.default) { [weak self] obvContactIdentity in
                self?.processTrustedPhotoOfContactIdentityHasBeenUpdated(obvContactIdentity: obvContactIdentity)
            },
            ObvEngineNotificationNew.observeOwnedIdentityUnbindingFromKeycloakPerformed(within: NotificationCenter.default) { [weak self] ownedIdentity in
                self?.processOwnedIdentityUnbindingFromKeycloakPerformedNotification(ownedIdentity: ownedIdentity)
            },
            ObvEngineNotificationNew.observeCreatedOrUpdatedContactIdentity(within: NotificationCenter.default) { [weak self] obvContactIdentity in
                Task { await self?.processCreatedOrUpdatedContactIdentity(obvContactIdentity: obvContactIdentity) }
            },
            ObvEngineNotificationNew.observeContactWasDeleted(within: NotificationCenter.default) { [weak self] ownedCryptoId, contactCryptoId in
                self?.processContactWasDeleted(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
            },
            ObvEngineNotificationNew.observeNewContactDevice(within: NotificationCenter.default) { [weak self] obvContactIdentifier in
                Task { [weak self] in await self?.processNewContactDevice(obvContactIdentifier: obvContactIdentifier) }
            },
            ObvEngineNotificationNew.observeContactObvCapabilitiesWereUpdated(within: NotificationCenter.default) { [weak self] obvContactIdentity in
                Task { [weak self] in await self?.processContactObvCapabilitiesWereUpdated(obvContactIdentity: obvContactIdentity) }
            },
            ObvEngineNotificationNew.observeUpdatedContactDevice(within: NotificationCenter.default) { [weak self] deviceIdentifier in
                Task { [weak self] in await self?.processUpdatedContactDevice(deviceIdentifier: deviceIdentifier) }
            },
            ObvMessengerCoreDataNotification.observePersistedContactWasInserted { [weak self] contactPermanentID, _, _, _ in
                Task { [weak self] in await self?.processPersistedContactWasInsertedNotification(contactPermanentID: contactPermanentID) }
            },
        ])

    }
    
    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        if forTheFirstTime {
            await recomputeSortKeyOfContactsWithPersonalNoteOperation()
        }
    }

    
    /// This one-time operation recomputes the search keys for all contacts with personal notes, as we introduced storing personal notes in contact search keys on 2024-10-16.
    /// This process is only required to be run once, as subsequent updates to personal notes will automatically trigger search key updates. Running this operation more than once is unnecessary.
    private func recomputeSortKeyOfContactsWithPersonalNoteOperation() async {
        
        guard let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier) else { assertionFailure(); return }

        let key = "ContactIdentityCoordinator.recomputeSortKeyOfContactsWithPersonalNoteOperation"

        guard !userDefaults.bool(forKey: key) else { return }
        
        let op1 = RecomputeSortKeyOfContactsWithPersonalNoteOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            return
        }
        
        userDefaults.set(true, forKey: key)

    }
    
}


// MARK: - Observing Notifications

extension ContactIdentityCoordinator {
    
    func processUserDidSeeNewDetailsOfContact(contactIdentifier: ObvTypes.ObvContactIdentifier) {
        let op1 = processUserDidSeeNewDetailsOfContactOperation(ownedCryptoId: contactIdentifier.ownedCryptoId, contactCryptoId: contactIdentifier.contactCryptoId)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processUiRequiresSignedContactDetails(ownedIdentityCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId, completion: @escaping (SignedObvKeycloakUserDetails?) -> Void) {
        do {
            try obvEngine.getSignedContactDetails(ownedIdentity: ownedIdentityCryptoId, contactIdentity: contactCryptoId) { result in
                switch result {
                case .failure(let error):
                    os_log("Failed to obtain signed contact details from engine: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                    completion(nil)
                case .success(let signedContactDetails):
                    completion(signedContactDetails)
                }
            }
        } catch {
            os_log("The call to reblockContactIdentity failed: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            completion(nil)
        }
    }
    
    
    /// Updates the personal note associated with a specific contact.
    ///
    /// This method is triggered when the user edits or saves a note for a contact.
    func processUserWantsToUpdatePersonalNoteOnContact(contactIdentifier: ObvContactIdentifier, newText: String?) async throws {
        let op1 = UpdatePersonalNoteOnContactOperation(contactIdentifier: contactIdentifier, newText: newText, makeSyncAtomRequest: true, syncAtomRequestDelegate: syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "UpdatePersonalNoteOnContactOperation cancelled: \(String(describing: op1.reasonForCancel))")
        }

    }


    private func updateCustomNicknameAndPictureForContact(persistedContactObjectID: NSManagedObjectID, customDisplayName: String?, customPhoto: UIImage?) {
        let op1 = UpdateCustomNicknameAndPictureForContactOperation(
            persistedContactObjectID: persistedContactObjectID,
            customDisplayName: customDisplayName,
            customPhoto: .image(image: customPhoto),
            makeSyncAtomRequest: true,
            syncAtomRequestDelegate: syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }    
    
    private enum ContactDeletionConfirmation {
        case userConfirmedDowngradeToNonOneToOne
        case userConfirmedFullDeletion
        case notConfirmedYet
    }
    
    
    /// Updates the app database with the latest contact updates from the engine.
    ///
    /// This method is invoked in the following scenarios:
    /// - When a contact is created or updated in the engine.
    /// - When the user views the details of a specific contact. In this case, the view’s data source receives a stream of `ObvContactIdentity` values from the engine, and this method ensures the displayed information remains consistent with the app database.
    func processCreatedOrUpdatedContactIdentity(obvContactIdentity: ObvContactIdentity) async {
        
        do {
            
            let op1 = CreateOrUpdatePersistedContactIdentityWithObvContactIdentityOperation(obvContactIdentity: obvContactIdentity)
            let op2 = UpdatePersistedContactIdentityStatusWithInfoFromEngineOperation(obvContactIdentity: obvContactIdentity)
            let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
            await self.coordinatorsQueue.addAndAwaitOperation(composedOp)
            
            guard composedOp.isFinished, !composedOp.isCancelled else {
                assertionFailure()
                return
            }
            
        }
        
        do {
            let ops = await getOperationsRequiredToSyncContactDevices(scope: .contactDevicesOfContact(contactIdentifier: obvContactIdentity.contactIdentifier), isRestoringSyncSnapshotOrBackup: false)
            await coordinatorsQueue.addAndAwaitOperations(ops)
        }

    }


    private func processContactWasDeleted(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) {
        let op1 = ProcessContactWasDeletedOperation(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processNewObliviousChannelWithContactDevice(obvContactIdentifier: ObvContactIdentifier) async {
        let ops = await getOperationsRequiredToSyncContactDevices(scope: .contactDevicesOfContact(contactIdentifier: obvContactIdentifier), isRestoringSyncSnapshotOrBackup: false)
        await coordinatorsQueue.addAndAwaitOperations(ops)
    }
 
    
    private func processNewContactDevice(obvContactIdentifier: ObvContactIdentifier) async {
        do {
            // Since this gets called when a contact is added, we also sync the contact
            let ops = await getOperationsRequiredToSyncContacts(scope: .specificContact(contactIdentifier: obvContactIdentifier), isRestoringSyncSnapshotOrBackup: false)
            await coordinatorsQueue.addAndAwaitOperations(ops)
        }
        do {
            let ops = await getOperationsRequiredToSyncContactDevices(scope: .contactDevicesOfContact(contactIdentifier: obvContactIdentifier), isRestoringSyncSnapshotOrBackup: false)
            await coordinatorsQueue.addAndAwaitOperations(ops)
        }
    }

    
    private func processContactObvCapabilitiesWereUpdated(obvContactIdentity: ObvContactIdentity) async {
        let op1 = SyncPersistedObvContactIdentityWithEngineOperation(syncType: .syncWithEngine(contactIdentifier: obvContactIdentity.contactIdentifier, isRestoringSyncSnapshotOrBackup: false), obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
    }

    
    private func processUpdatedContactDevice(deviceIdentifier: ObvContactDeviceIdentifier) async {
        let op1 = SyncPersistedObvContactDeviceWithEngineOperation(syncType: .syncWithEngine(contactDeviceIdentifier: deviceIdentifier, isRestoringSyncSnapshotOrBackup: false), obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
    }

    
    private func processPersistedContactWasInsertedNotification(contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>) async {
        /* When receiving a PersistedContactWasInsertedNotification, we re-sync the groups from the engine. This is required when the following situation occurs :
         * Bob creates a group with Alice and Charlie, who do not know each other. Alice receives a new list of group members including Charlie *before* she includes
         * Charlie in her contacts. In that case, Charlie stays in the list of pending members. Here, we re-sync the groups members, making sure Charlie appears in
         * the list of group members.
         */
        let operationsToQueueOnQueueForComposedOperation = await getOperationsRequiredToSyncGroupsV1(isRestoringSyncSnapshotOrBackup: false)
        await coordinatorsQueue.addAndAwaitOperations(operationsToQueueOnQueueForComposedOperation)
    }
    
    

    private func processDeletedObliviousChannelWithContactDevice(obvContactIdentifier: ObvContactIdentifier) async {
        do {
            // Since this gets called when a contact is deleted, we also sync the contact
            let ops = await getOperationsRequiredToSyncContacts(scope: .specificContact(contactIdentifier: obvContactIdentifier), isRestoringSyncSnapshotOrBackup: false)
            await coordinatorsQueue.addAndAwaitOperations(ops)
        }
        do {
            // Now that the contact is synced, we can sync the contact devices
            let ops = await getOperationsRequiredToSyncContactDevices(scope: .contactDevicesOfContact(contactIdentifier: obvContactIdentifier), isRestoringSyncSnapshotOrBackup: false)
            await coordinatorsQueue.addAndAwaitOperations(ops)
        }
    }

    
    private func processTrustedPhotoOfContactIdentityHasBeenUpdated(obvContactIdentity: ObvContactIdentity) {
        let op1 = ProcessTrustedPhotoOfContactIdentityHasBeenUpdatedOperation(obvContactIdentity: obvContactIdentity)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }


    private func processUserWantToChangeContactsSortOrderNotification(ownedCryptoId: ObvCryptoId, sortOrder: ContactsSortOrder) {
        let op1 = UpdateContactsSortOrderOperation(ownedCryptoId: ownedCryptoId, newSortOrder: sortOrder)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    

    private func processOwnedIdentityUnbindingFromKeycloakPerformedNotification(ownedIdentity: ObvCryptoId) {
        let op1 = UpdateListOfContactsCertifiedByOwnKeycloakOperation(ownedIdentity: ownedIdentity, contactsCertifiedByOwnKeycloak: Set<ObvCryptoId>([]))
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
}
