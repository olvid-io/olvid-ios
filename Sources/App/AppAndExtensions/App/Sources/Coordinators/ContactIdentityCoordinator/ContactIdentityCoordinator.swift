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
import os.log
import CoreData
import ObvEngine
import ObvCoreDataStack
import OlvidUtils
@preconcurrency import ObvTypes
import ObvUICoreData
import ObvSettings
import ObvAppCoreConstants


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
            ObvMessengerInternalNotification.observeUserWantsToDeleteContact { [weak self] contactCryptoId, ownedCryptoId, viewController, completionHandler in
                Task { [weak self] in await self?.processUserWantsToDeleteContact(with: contactCryptoId, ownedCryptoId: ownedCryptoId, viewController: viewController, completionHandler: completionHandler) }
            },
            ObvMessengerInternalNotification.observeUserDidSeeNewDetailsOfContact { [weak self] contactCryptoId, ownedCryptoId in
                self?.processUserDidSeeNewDetailsOfContactNotification(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observeUserWantsToEditContactNicknameAndPicture { [weak self] persistedContactObjectID, customDisplayName, customPhoto in
                self?.updateCustomNicknameAndPictureForContact(persistedContactObjectID: persistedContactObjectID, customDisplayName: customDisplayName, customPhoto: customPhoto)
            },
            ObvMessengerInternalNotification.observeUserWantsToChangeContactsSortOrder { [weak self] ownedCryptoId, sortOrder in
                self?.processUserWantToChangeContactsSortOrderNotification(ownedCryptoId: ownedCryptoId, sortOrder: sortOrder)
            },
            ObvMessengerInternalNotification.observeAViewRequiresObvMutualScanUrl { [weak self] remoteIdentity, ownedCryptoId, completionHandler in
                self?.processAViewRequiresObvMutualScanUrl(remoteIdentity: remoteIdentity, ownedCryptoId: ownedCryptoId, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeUserWantsToStartTrustEstablishmentWithMutualScanProtocol() { [weak self] ownedCryptoId, mutualScanUrl in
                self?.processUserWantsToStartTrustEstablishmentWithMutualScanProtocol(ownedIdentity: ownedCryptoId, mutualScanUrl: mutualScanUrl)
            },
            ObvMessengerInternalNotification.observeObvContactRequest { [weak self] requestUUID, contactCryptoId, ownedCryptoId in
                self?.processObvContactRequest(requestUUID: requestUUID, contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observeUserWantsToUnblockContact { [weak self] ownedCryptoId, contactCryptoId in
                self?.processUserWantsToUnblockContact(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
            },
            ObvMessengerInternalNotification.observeUserWantsToReblockContact { [weak self] ownedCryptoId, contactCryptoId in
                self?.processUserWantsToReblockContact(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
            },
            ObvMessengerInternalNotification.observeUiRequiresSignedContactDetails { [weak self] ownedIdentityCryptoId, contactCryptoId, completion in
                self?.processUiRequiresSignedContactDetails(ownedIdentityCryptoId: ownedIdentityCryptoId, contactCryptoId: contactCryptoId, completion: completion)
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdatePersonalNoteOnContact { [weak self] contactIdentifier, newText in
                self?.processUserWantsToUpdatePersonalNoteOnContact(contactIdentifier: contactIdentifier, newText: newText)
            },
        ])
        
        // Listening to ObvEngine Notification
        
        observationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeDeletedObliviousChannelWithContactDevice(within: NotificationCenter.default) { [weak self] obvContactIdentifier in
                Task { [weak self] in await self?.processDeletedObliviousChannelWithContactDevice(obvContactIdentifier: obvContactIdentifier) }
            },
            ObvEngineNotificationNew.observeNewTrustedContactIdentity(within: NotificationCenter.default) { [weak self] obvContactIdentity in
                Task { [weak self] in await self?.processNewTrustedContactIdentity(obvContactIdentity: obvContactIdentity) }
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
            ObvEngineNotificationNew.observeContactIsActiveChangedWithinEngine(within: NotificationCenter.default) { [weak self] obvContactIdentity in
                self?.processContactIsActiveChangedWithinEngine(obvContactIdentity: obvContactIdentity)
            },
            ObvEngineNotificationNew.observeUpdatedContactIdentity(within: NotificationCenter.default) { [weak self] obvContactIdentity, trustedIdentityDetailsWereUpdated, publishedIdentityDetailsWereUpdated in
                Task { await self?.processUpdatedContactIdentity(obvContactIdentity: obvContactIdentity, trustedIdentityDetailsWereUpdated: trustedIdentityDetailsWereUpdated, publishedIdentityDetailsWereUpdated: publishedIdentityDetailsWereUpdated) }
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
    
    private func processUserDidSeeNewDetailsOfContactNotification(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId) {
        let op1 = processUserDidSeeNewDetailsOfContactOperation(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processObvContactRequest(requestUUID: UUID, contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId) {
        let obvContact: ObvContactIdentity
        do {
            guard let _obvContact = try obvEngine.getContactIdentity(with: contactCryptoId, ofOwnedIdentityWith: ownedCryptoId) else { return }
            obvContact = _obvContact
        } catch {
            os_log("Could not get contact identity of owned identity. This is ok if this contact has just been deleted.", log: Self.log, type: .error)
            return
        }
        
        let op1 = CreateOrUpdatePersistedContactIdentityWithObvContactIdentityOperation(obvContactIdentity: obvContact)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        let blockOp = BlockOperation()
        blockOp.completionBlock = {
            ObvMessengerInternalNotification.obvContactAnswer(requestUUID: requestUUID, obvContact: obvContact)
                .postOnDispatchQueue()
        }
        blockOp.addDependency(composedOp)
        self.coordinatorsQueue.addOperations([composedOp, blockOp], waitUntilFinished: false)
    }

    
    private func processUserWantsToUnblockContact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) {
        do {
            try obvEngine.unblockContactIdentity(with: contactCryptoId, ofOwnedIdentityWithCryptoId: ownedCryptoId)
        } catch {
            os_log("The call to unblockContactIdentity failed: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
        }
    }

    
    private func processUserWantsToReblockContact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) {
        do {
            try obvEngine.reblockContactIdentity(with: contactCryptoId, ofOwnedIdentityWithCryptoId: ownedCryptoId)
        } catch {
            os_log("The call to reblockContactIdentity failed: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
        }
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
    
    
    private func processUserWantsToUpdatePersonalNoteOnContact(contactIdentifier: ObvContactIdentifier, newText: String?) {
        let op1 = UpdatePersonalNoteOnContactOperation(contactIdentifier: contactIdentifier, newText: newText, makeSyncAtomRequest: true, syncAtomRequestDelegate: syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
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
    
    
    private func processUserWantsToDeleteContact(with contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, viewController: UIViewController, completionHandler: ((Bool) -> Void)?, confirmation: ContactDeletionConfirmation = .notConfirmedYet, preferDeleteOverDowngrade: Bool = false) async {
        
        switch confirmation {
            
        case .notConfirmedYet:
            
            // When the user wants to delete a contact, we have 2 main cases to consider :
            // Main case 1: the contact has the .oneToOneContacts capability
            // Main case 2: she does not.

            ObvStack.shared.performBackgroundTask { context in
                
                do {
                    guard let persistedContact = try PersistedObvContactIdentity.get(contactCryptoId: contactCryptoId, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: context) else { return }
                    
                    if persistedContact.supportsCapability(.oneToOneContacts) && !preferDeleteOverDowngrade {
                        
                        // We are in the Main case 1 as the contact supports the oneToOneContacts capability.
                        // In that case, if she is a OneToOne contact, we want to downgrade her to be non-OneToOne.
                        // Otherwise, we are in the same situation as if we were in Main case 2 (as we want to delete the identity).
                        
                        if persistedContact.isOneToOne {
                            
                            let contactName = persistedContact.customDisplayName ?? persistedContact.identityCoreDetails?.getDisplayNameWithStyle(.firstNameThenLastName) ?? persistedContact.fullDisplayName

                            DispatchQueue.main.async {
                                
                                let alert = UIAlertController(title: Strings.AlertDowngradeContact.title,
                                                              message: Strings.AlertDowngradeContact.message(contactName),
                                                              preferredStyleForTraitCollection: viewController.traitCollection)
                                let deleteAction = UIAlertAction(title: Strings.AlertDowngradeContact.confirm, style: .destructive) { [weak self] _ in
                                    Task { [weak self] in
                                        await self?.processUserWantsToDeleteContact(with: contactCryptoId,
                                                                                    ownedCryptoId: ownedCryptoId,
                                                                                    viewController: viewController,
                                                                                    completionHandler: completionHandler,
                                                                                    confirmation: .userConfirmedDowngradeToNonOneToOne)
                                    }
                                }
                                let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: .cancel) { _ in
                                    DispatchQueue.main.async { completionHandler?(false) }
                                }
                                alert.addAction(deleteAction)
                                alert.addAction(cancelAction)
                                
                                viewController.present(alert, animated: true, completion: nil)
                            }
                            
                        } else {

                            Task { [weak self] in
                                await self?.processUserWantsToDeleteContact(with: contactCryptoId,
                                                                            ownedCryptoId: ownedCryptoId,
                                                                            viewController: viewController,
                                                                            completionHandler: completionHandler,
                                                                            confirmation: confirmation,
                                                                            preferDeleteOverDowngrade: true)
                            }
                            
                        }
                        
                    } else {
                        
                        // We are in the Main case 2, either because the contact does not support the oneToOneContacts capability, or because the current user
                        // Wants to fully delete the contct identity. In that case, it's complicated, as we have 3 subcases to consider :
                        // - Subcase 1: If the contact is part of the members of some group, then we cannot delete her and we inform the user using a modal action sheet
                        // - Otherwise :
                        //    - Subcase 2: If the contact is part of the pending members of some group, we inform the user that if she delete the contact, this contact might
                        //      "reapear" in a near future (when she joins the group).
                        //    - Subcase 3: Otherwise, there is no technical reason preventing the contact to be deleted, so we simply ask a confirmation to the user.

                        // Preparing for testing the 3 possible subcases
                        
                        var noCommonGroup = false
                        let noGroupWhereContactIsPending: Bool
                        let contactName: String
                        do {
                            let commonGroupsV1 = try PersistedContactGroup.getAllContactGroups(whereContactIdentitiesInclude: persistedContact, within: context)
                            let pendingGroupsV1 = try PersistedContactGroup.getAllContactGroups(wherePendingMembersInclude: persistedContact, within: context)
                            let commonGroupsV2 = try PersistedGroupV2.getAllPersistedGroupV2(whereContactIdentitiesInclude: persistedContact)
                            noCommonGroup = commonGroupsV1.isEmpty && commonGroupsV2.isEmpty
                            noGroupWhereContactIsPending = pendingGroupsV1.isEmpty
                            contactName = persistedContact.customDisplayName ?? persistedContact.identityCoreDetails?.getDisplayNameWithStyle(.firstNameThenLastName) ?? persistedContact.fullDisplayName
                        }
                        
                        guard noCommonGroup else {
                            // Subcase 1
                            DispatchQueue.main.async {
                                let alert = UIAlertController(title: Strings.AlertCommonGroupOnContactDeletion.title,
                                                              message: Strings.AlertCommonGroupOnContactDeletion.message(contactName), preferredStyle: .alert)
                                let okAction = UIAlertAction(title: CommonString.Word.Ok, style: .default, handler: nil)
                                alert.addAction(okAction)
                                viewController.present(alert, animated: true)
                            }
                            return
                        }
                        
                        DispatchQueue.main.async {
                            let alert: UIAlertController
                            if !noGroupWhereContactIsPending {
                                // Subcase 2
                                alert = UIAlertController(title: Strings.alertDeleteContactTitle,
                                                          message: Strings.AlertCommonGroupWhereContactToDeleteIsPending.message(contactName),
                                                          preferredStyleForTraitCollection: viewController.traitCollection)
                                
                            } else {
                                // Subcase 3
                                alert = UIAlertController(title: Strings.alertDeleteContactTitle,
                                                          message: Strings.alertDeleteContactMessage(contactName),
                                                          preferredStyleForTraitCollection: viewController.traitCollection)
                                
                            }
                            
                            // For both subcases 2 and 3
                            
                            alert.addAction(UIAlertAction(title: Strings.alertActionTitleDeleteContact, style: .destructive, handler: { [weak self] _ in
                                assert(Thread.isMainThread)
                                Task { [weak self] in
                                    await self?.processUserWantsToDeleteContact(with: contactCryptoId,
                                                                                ownedCryptoId: ownedCryptoId,
                                                                                viewController: viewController,
                                                                                completionHandler: completionHandler,
                                                                                confirmation: .userConfirmedFullDeletion)
                                }
                            }))
                            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel, handler: { _ in
                                assert(Thread.isMainThread)
                                completionHandler?(false)
                            }))
                            viewController.present(alert, animated: true, completion: nil)
                        }

                    }
                    
                } catch {
                    os_log("Could not process the user request to delete a contact: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                    assertionFailure()
                }

            }
            
        case .userConfirmedDowngradeToNonOneToOne:
            
            // The user confirmed she wishes to downgrade the contact from OneToOne to non-OneToOne. We do not check whether this makes sense here, this has been
            // Done above, when determining the most appropriate alert to show.
            
            do {
                try obvEngine.downgradeOneToOneContact(ownedIdentity: ownedCryptoId, contactIdentity: contactCryptoId)
            } catch {
                os_log("Fail to downgrade the contact to non-OneToOne: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                DispatchQueue.main.async { completionHandler?(false) }
                return
            }
            DispatchQueue.main.async { completionHandler?(true) }

        case .userConfirmedFullDeletion:
            
            // The user confirmed she wishes to delete the contact identity. We do not check whether this makes sense here, this has been
            // Done above, when determining the most appropriate alert to show.

            do {
                try obvEngine.deleteContactIdentity(with: contactCryptoId, ofOwnedIdentyWith: ownedCryptoId)
                DispatchQueue.main.async { completionHandler?(true) }
            } catch {
                os_log("Fail to delete the contact: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                DispatchQueue.main.async { completionHandler?(false) }
            }
                        
        }

    }


    private func processUpdatedContactIdentity(obvContactIdentity: ObvContactIdentity, trustedIdentityDetailsWereUpdated: Bool, publishedIdentityDetailsWereUpdated: Bool) async {
        
        let op1 = CreateOrUpdatePersistedContactIdentityWithObvContactIdentityOperation(obvContactIdentity: obvContactIdentity)
        let op2 = UpdatePersistedContactIdentityStatusWithInfoFromEngineOperation(obvContactIdentity: obvContactIdentity, trustedIdentityDetailsWereUpdated: trustedIdentityDetailsWereUpdated, publishedIdentityDetailsWereUpdated: publishedIdentityDetailsWereUpdated)
        let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)
        
        guard composedOp.isFinished, !composedOp.isCancelled else {
            assertionFailure()
            return
        }
        
        ObvMessengerInternalNotification.contactIdentityDetailsWereUpdated(contactCryptoId: obvContactIdentity.cryptoId, ownedCryptoId: obvContactIdentity.ownedIdentity.cryptoId)
            .postOnDispatchQueue()

    }


    private func processNewTrustedContactIdentity(obvContactIdentity: ObvContactIdentity) async {
        do {
            let op1 = CreateOrUpdatePersistedContactIdentityWithObvContactIdentityOperation(obvContactIdentity: obvContactIdentity)
            await queueAndAwaitCompositionOfOneContextualOperation(op1: op1)
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


    private func processAViewRequiresObvMutualScanUrl(remoteIdentity: Data, ownedCryptoId: ObvCryptoId, completionHandler: @escaping (ObvMutualScanUrl) -> Void) {
        guard let mutualScanURL = try? obvEngine.computeMutualScanUrl(remoteIdentity: remoteIdentity, ownedCryptoId: ownedCryptoId) else {
            assertionFailure()
            return
        }
        DispatchQueue.main.async {
            completionHandler(mutualScanURL)
        }
    }


    private func processUserWantsToStartTrustEstablishmentWithMutualScanProtocol(ownedIdentity: ObvCryptoId, mutualScanUrl: ObvMutualScanUrl) {
        do {
            try obvEngine.startTrustEstablishmentWithMutualScanProtocol(ownedIdentity: ownedIdentity, mutualScanUrl: mutualScanUrl)
        } catch {
            os_log("Could not start TrustEstablishmentWithMutualScanProtocol: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
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
    
    
    private func processContactIsActiveChangedWithinEngine(obvContactIdentity: ObvContactIdentity) {
        let op1 = CreateOrUpdatePersistedContactIdentityWithObvContactIdentityOperation(obvContactIdentity: obvContactIdentity)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
}
