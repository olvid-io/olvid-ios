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
import OlvidUtils
import ObvTypes

final class ContactIdentityCoordinator {
    
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ContactIdentityCoordinator.self))
    private var currentOwnedCryptoId: ObvCryptoId?
    private var observationTokens = [NSObjectProtocol]()
    private let internalQueue: OperationQueue
    
    private static let errorDomain = String(describing: ContactIdentityCoordinator.self)
    
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    init(obvEngine: ObvEngine, operationQueue: OperationQueue) {
        self.obvEngine = obvEngine
        self.internalQueue = operationQueue
        listenToNotifications()
    }
    
    private func listenToNotifications() {
                        
        // Internal notifications
        
        observeCurrentOwnedCryptoIdChangedNotifications()
        observeUserWantsToDeleteContactNotifications()

        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeResyncContactIdentityDevicesWithEngine { [weak self] (contactCryptoId, ownedCryptoId) in
                self?.processResyncContactIdentityDevicesWithEngineNotification(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observeResyncContactIdentityDetailsStatusWithEngine(queue: internalQueue) { [weak self] (contactCryptoId, ownedCryptoId) in
                self?.processResyncContactIdentityDetailsStatusWithEngineNotification(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observeUserDidSeeNewDetailsOfContact(queue: internalQueue) { [weak self] (contactCryptoId, ownedCryptoId) in
                self?.processUserDidSeeNewDetailsOfContactNotification(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observeUserWantsToEditContactNicknameAndPicture(queue: internalQueue) { [weak self] (persistedContactObjectID, nicknameAndPicture) in
                self?.updateCustomNicknameAndPictureForContact(persistedContactObjectID: persistedContactObjectID, nicknameAndPicture: nicknameAndPicture)
            },
            ObvMessengerInternalNotification.observeUserWantsToChangeContactsSortOrder() { [weak self] (ownedCryptoId, sortOrder) in
                self?.processUserWantToChangeContactsSortOrderNotification(ownedCryptoId: ownedCryptoId, sortOrder: sortOrder)
            },
            ObvMessengerInternalNotification.observeAViewRequiresObvMutualScanUrl() { [weak self] remoteIdentity, ownedCryptoId, completionHandler in
                self?.processAViewRequiresObvMutualScanUrl(remoteIdentity: remoteIdentity, ownedCryptoId: ownedCryptoId, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeUserWantsToStartTrustEstablishmentWithMutualScanProtocol() { [weak self] ownedCryptoId, mutualScanUrl in
                self?.processUserWantsToStartTrustEstablishmentWithMutualScanProtocol(ownedIdentity: ownedCryptoId, mutualScanUrl: mutualScanUrl)
            },
            ObvMessengerInternalNotification.observeObvContactRequest() { [weak self] requestUUID, contactCryptoId, ownedCryptoId in
                self?.processObvContactRequest(requestUUID: requestUUID, contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observeUserWantsToUnblockContact() { [weak self] ownedCryptoId, contactCryptoId in
                self?.processUserWantsToUnblockContact(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
            },
            ObvMessengerInternalNotification.observeUserWantsToReblockContact() { [weak self] ownedCryptoId, contactCryptoId in
                self?.processUserWantsToReblockContact(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
            },
            ObvMessengerInternalNotification.observeUiRequiresSignedContactDetails() { [weak self] (ownedIdentityCryptoId, contactCryptoId, completion) in
                self?.processUiRequiresSignedContactDetails(ownedIdentityCryptoId: ownedIdentityCryptoId, contactCryptoId: contactCryptoId, completion: completion)
            },
        ])
        
        // Listening to ObvEngine Notification
        
        observeNewTrustedContactIdentity()
        observeContactWasDeletedNotifications()
        observeNewObliviousChannelWithContactDeviceNotifications()
        observeDeletedObliviousChannelWithContactDevice()

        observationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeTrustedPhotoOfContactIdentityHasBeenUpdated(within: NotificationCenter.default, queue: internalQueue) { [weak self] obvContactIdentity in
                self?.processTrustedPhotoOfContactIdentityHasBeenUpdated(obvContactIdentity: obvContactIdentity)
            },
            ObvEngineNotificationNew.observeUpdatedSetOfContactsCertifiedByOwnKeycloak(within: NotificationCenter.default) { [weak self] (ownedIdentity, contactsCertifiedByOwnKeycloak) in
                self?.processUpdatedSetOfContactsCertifiedByOwnKeycloakNotification(ownedIdentity: ownedIdentity, contactsCertifiedByOwnKeycloak: contactsCertifiedByOwnKeycloak)
            },
            ObvEngineNotificationNew.observeOwnedIdentityUnbindingFromKeycloakPerformed(within: NotificationCenter.default) { [weak self] (ownedIdentity, result) in
                self?.processOwnedIdentityUnbindingFromKeycloakPerformedNotification(ownedIdentity: ownedIdentity, result: result)
            },
            ObvEngineNotificationNew.observeContactIsActiveChangedWithinEngine(within: NotificationCenter.default) { [weak self] obvContactIdentity in
                self?.processContactIsActiveChangedWithinEngine(obvContactIdentity: obvContactIdentity)
            },
            ObvEngineNotificationNew.observeUpdatedContactIdentity(within: NotificationCenter.default) { [weak self] (obvContactIdentity, trustedIdentityDetailsWereUpdated, publishedIdentityDetailsWereUpdated) in
                self?.processUpdatedContactIdentity(obvContactIdentity: obvContactIdentity, trustedIdentityDetailsWereUpdated: trustedIdentityDetailsWereUpdated, publishedIdentityDetailsWereUpdated: publishedIdentityDetailsWereUpdated)
            },
            ObvEngineNotificationNew.observeContactObvCapabilitiesWereUpdated(within: NotificationCenter.default) { [weak self] (obvContactIdentity) in
                self?.processContactObvCapabilitiesWereUpdated(obvContactIdentity: obvContactIdentity)
            },
        ])
     
        observeAppStateChangedNotifications()

    }
    
}

// MARK: - Bootstrap

extension ContactIdentityCoordinator {
    
    private func observeAppStateChangedNotifications() {
        let log = self.log
        observationTokens.append(ObvMessengerInternalNotification.observeAppStateChanged() { [weak self] (previousState, currentState) in
            if currentState.isInitializedAndActive {
                do {
                    try self?.obvEngine.requestSetOfContactsCertifiedByOwnKeycloakForAllOwnedCryptoIds()
                } catch {
                    os_log("Could not bootstrap list of all contactact certified by same keycloak server as owned identity", log: log, type: .fault)
                }
            }
        })
    }    
}

// MARK: - Observing Notifications

extension ContactIdentityCoordinator {
    
    private func processUserDidSeeNewDetailsOfContactNotification(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId) {
        assert(OperationQueue.current == internalQueue)
        let log = self.log
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            guard let persistedContactIdentity = try? PersistedObvContactIdentity.get(contactCryptoId: contactCryptoId, ownedIdentityCryptoId: ownedCryptoId, within: context) else {
                os_log("Could not get the persisted obv contact identity. This is ok if the contact has just been deleted.", log: log, type: .error)
                return
            }
            guard persistedContactIdentity.status == .unseenPublishedDetails else { return }
            persistedContactIdentity.setContactStatus(to: .seenPublishedDetails)
            do {
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could not update the newPublishedDetails flag of a contact: %{public}@", log: log, type: .error, error.localizedDescription)
            }
        }
    }
    
    
    private func processObvContactRequest(requestUUID: UUID, contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId) {
        
        let obvContact: ObvContactIdentity
        do {
            obvContact = try obvEngine.getContactIdentity(with: contactCryptoId, ofOwnedIdentityWith: ownedCryptoId)
        } catch {
            os_log("Could not get contact identity of owned identity. This is ok if this contact has just been deleted.", log: log, type: .error)
            return
        }
        
        let op1 = UpdatePersistedContactIdentityWithObvContactIdentityOperation(obvContactIdentity: obvContact)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        
        ObvMessengerInternalNotification.obvContactAnswer(requestUUID: requestUUID, obvContact: obvContact)
            .postOnDispatchQueue()
    }

    
    private func processUserWantsToUnblockContact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) {
        do {
            try obvEngine.unblockContactIdentity(with: contactCryptoId, ofOwnedIdentityWithCryptoId: ownedCryptoId)
        } catch {
            os_log("The call to unblockContactIdentity failed: %{public}@", log: log, type: .fault, error.localizedDescription)
        }
    }

    
    private func processUserWantsToReblockContact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) {
        do {
            try obvEngine.reblockContactIdentity(with: contactCryptoId, ofOwnedIdentityWithCryptoId: ownedCryptoId)
        } catch {
            os_log("The call to reblockContactIdentity failed: %{public}@", log: log, type: .fault, error.localizedDescription)
        }
    }
    
    
    private func processUiRequiresSignedContactDetails(ownedIdentityCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId, completion: @escaping (SignedUserDetails?) -> Void) {
        let log = self.log
        do {
            try obvEngine.getSignedContactDetails(ownedIdentity: ownedIdentityCryptoId, contactIdentity: contactCryptoId) { result in
                switch result {
                case .failure(let error):
                    os_log("Failed to obtain signed contact details from engine: %{public}@", log: log, type: .fault, error.localizedDescription)
                    completion(nil)
                case .success(let signedContactDetails):
                    completion(signedContactDetails)
                }
            }
        } catch {
            os_log("The call to reblockContactIdentity failed: %{public}@", log: log, type: .fault, error.localizedDescription)
            completion(nil)
        }
    }

    
    private func updateCustomNicknameAndPictureForContact(persistedContactObjectID: NSManagedObjectID, nicknameAndPicture: CustomNicknameAndPicture) {
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            do {
                guard let writableContact = try PersistedObvContactIdentity.get(objectID: persistedContactObjectID, within: context) else { assertionFailure(); return }
                try writableContact.setCustomDisplayName(to: nicknameAndPicture.customDisplayName)
                writableContact.setCustomPhotoURL(with: nicknameAndPicture.customPhotoURL)
                try context.save(logOnFailure: self.log)
            } catch {
                os_log("Could not remove contact custom display name", log: self.log, type: .error)
            }
        }
    }


    private func observeCurrentOwnedCryptoIdChangedNotifications() {
        let token = ObvMessengerInternalNotification.observeCurrentOwnedCryptoIdChanged(queue: internalQueue) { [weak self] (newOwnedCryptoId, apiKey) in
            self?.currentOwnedCryptoId = newOwnedCryptoId
        }
        observationTokens.append(token)
    }
    
    
    private func observeUserWantsToDeleteContactNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToDeleteContact(queue: internalQueue) { [weak self] (contactCryptoId, ownedCryptoId, viewController, completionHandler) in
            DispatchQueue.main.async {
                self?.userWantsToDeleteContact(with: contactCryptoId, ownedCryptoId: ownedCryptoId, viewController: viewController, completionHandler: completionHandler, confirmed: false)
            }
        })
    }
    
    
    private func processResyncContactIdentityDevicesWithEngineNotification(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId) {
        
        let engineContactDevices: Set<ObvContactDevice>
        do {
            engineContactDevices = try obvEngine.getAllObliviousChannelsEstablishedWithContactIdentity(with: contactCryptoId, ofOwnedIdentyWith: ownedCryptoId)
        } catch {
            os_log("Could not get all Oblivious Channels established with contact. Could not sync with engine.", log: log, type: .fault)
            assert(false)
            return
        }
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            guard let persistedOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else {
                os_log("Could not get the persisted owned identity", log: log, type: .fault)
                assert(false)
                return
            }
            
            guard let persistedContactIdentity = try? PersistedObvContactIdentity.get(cryptoId: contactCryptoId, ownedIdentity: persistedOwnedIdentity) else {
                os_log("Could not get the persisted obv contact identity", log: log, type: .fault)
                assert(false)
                return
            }
            
            let localContactDevicesIdentifiers = Set(persistedContactIdentity.devices.map { $0.identifier })
            let missingDevices = engineContactDevices.filter { !localContactDevicesIdentifiers.contains($0.identifier) }
            for missingDevice in missingDevices {
                _ = PersistedObvContactDevice(obvContactDevice: missingDevice, within: context)
            }
            
            let engineContactDeviceIdentifiers = engineContactDevices.map { $0.identifier }
            let identifiersOfDevicesToRemove = localContactDevicesIdentifiers.filter { !engineContactDeviceIdentifiers.contains($0) }
            for contactDeviceIdentifier in identifiersOfDevicesToRemove {
                do {
                    try PersistedObvContactDevice.delete(contactDeviceIdentifier: contactDeviceIdentifier, contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId, within: context)
                } catch {
                    os_log("Could not delete persisted device during sync with engine", log: log, type: .fault)
                    assert(false)
                    return
                }
            }
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could not re-sync contact devices with engine", log: log, type: .fault)
            }

        }
    }
    
    
    private func processResyncContactIdentityDetailsStatusWithEngineNotification(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId) {
        assert(OperationQueue.current == internalQueue)

        let obvContactIdentity: ObvContactIdentity
        do {
            obvContactIdentity = try obvEngine.getContactIdentity(with: contactCryptoId, ofOwnedIdentityWith: ownedCryptoId)
        } catch {
            os_log("While trying to re-sync a persisted contact, we could not find her in the engine", log: log, type: .fault)
            assert(false)
            return
        }
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            guard let persistedContactIdentity = try? PersistedObvContactIdentity.get(persisted: obvContactIdentity, within: context) else { return }
            guard let receivedPublishedDetails = obvContactIdentity.publishedIdentityDetails else { return }
            if obvContactIdentity.trustedIdentityDetails == receivedPublishedDetails {                
                persistedContactIdentity.setContactStatus(to: .noNewPublishedDetails)
            } else {
                persistedContactIdentity.setContactStatus(to: .unseenPublishedDetails)
            }
            do {
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could set the newPublishedDetails flag on a persisted contact", log: log, type: .fault)
            }
        }
        
    }
    
    
    private func userWantsToDeleteContact(with contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, viewController: UIViewController, completionHandler: ((Bool) -> Void)?, confirmed: Bool) {
        
        assert(Thread.isMainThread)
        
        guard self.currentOwnedCryptoId == ownedCryptoId else { return }
        
        // When the user wants to delete a contact, we have 3 cases to consider :
        // - Case 1: If the contact is part of the members of some group, then we cannot delete her and we inform the user using a modal action sheet
        // - Otherwise :
        //    - Case 2: If the contact is part of the pending members of some group, we inform the user that if she delete the contact, this contact might
        //      "reapear" in a near future (when she joins the group).
        //    - Case 3: Otherwise, there is no technical reason preventing the contact to be deleted, so we simply ask a confirmation to the user.
        
        if confirmed {
            DispatchQueue(label: "DeleteContact").async { [weak self] in
                guard let _self = self else { return }
                do {
                    try _self.obvEngine.deleteContactIdentity(with: contactCryptoId, ofOwnedIdentyWith: ownedCryptoId)
                } catch {
                    os_log("Could not delete contact identity", log: _self.log, type: .fault)
                    DispatchQueue.main.async {
                        completionHandler?(false)
                    }
                    return
                }
                os_log("The contact was deleted from the engine", log: _self.log, type: .debug)
                DispatchQueue.main.async {
                    completionHandler?(true)
                }
            }
        } else {
            
            // Preparing for testing the 3 possible cases
            
            var noCommonGroup = false
            var noGroupWhereContactIsPending = false
            var contactName = ""
            ObvStack.shared.performBackgroundTaskAndWait { (context) in
                
                guard let persistedOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else { return }
                guard let persistedContact = try? PersistedObvContactIdentity.get(cryptoId: contactCryptoId, ownedIdentity: persistedOwnedIdentity) else { return }
                guard let commonGroups = try? PersistedContactGroup.getAllContactGroups(whereContactIdentitiesInclude: persistedContact, within: context) else { return }
                guard let pendingGroups = try? PersistedContactGroup.getAllContactGroups(wherePendingMembersInclude: persistedContact, within: context) else { return }
                noCommonGroup = commonGroups.isEmpty
                noGroupWhereContactIsPending = pendingGroups.isEmpty
                contactName = persistedContact.customDisplayName ?? persistedContact.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
                
            }
            
            guard noCommonGroup else {
                
                // Case 1
                
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: Strings.AlertCommonGroupOnContactDeletion.title,
                                                  message: Strings.AlertCommonGroupOnContactDeletion.message(contactName), preferredStyle: .alert)
                    let okAction = UIAlertAction(title: CommonString.Word.Ok, style: .default, handler: nil)
                    alert.addAction(okAction)
                    viewController.present(alert, animated: true)
                }
                return
            }
            
            let alert: UIAlertController
            if !noGroupWhereContactIsPending {
                // Case 2
                alert = UIAlertController(title: Strings.alertDeleteContactTitle,
                                          message: Strings.AlertCommonGroupWhereContactToDeleteIsPending.message(contactName),
                                          preferredStyleForTraitCollection: viewController.traitCollection)
                
            } else {
                // Case 3
                alert = UIAlertController(title: Strings.alertDeleteContactTitle,
                                          message: Strings.alertDeleteContactMessage(contactName),
                                          preferredStyleForTraitCollection: viewController.traitCollection)

            }
            
            // For both cases 2 and 3
            
            alert.addAction(UIAlertAction(title: Strings.alertActionTitleDeleteContact, style: .destructive, handler: { [weak self] _ in
                self?.userWantsToDeleteContact(with: contactCryptoId, ownedCryptoId: ownedCryptoId, viewController: viewController, completionHandler: completionHandler, confirmed: true)
            }))
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel, handler: { _ in
                DispatchQueue.main.async {
                    completionHandler?(false)
                }
            }))
            DispatchQueue.main.async {
                viewController.present(alert, animated: true, completion: nil)
            }

        }
    }


    private func processUpdatedContactIdentity(obvContactIdentity: ObvContactIdentity, trustedIdentityDetailsWereUpdated: Bool, publishedIdentityDetailsWereUpdated: Bool) {
        assert(OperationQueue.current != internalQueue) // Prevent a deadlock
        let op1 = UpdatePersistedContactIdentityWithObvContactIdentityOperation(obvContactIdentity: obvContactIdentity)
        let op2 = UpdatePersistedContactIdentityStatusWithInfoFromEngineOperation(obvContactIdentity: obvContactIdentity, trustedIdentityDetailsWereUpdated: trustedIdentityDetailsWereUpdated, publishedIdentityDetailsWereUpdated: publishedIdentityDetailsWereUpdated)
        let composedOp = CompositionOfTwoContextualOperations(op1: op1, op2: op2, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        if !composedOp.isCancelled {
            ObvMessengerInternalNotification.contactIdentityDetailsWereUpdated(contactCryptoId: obvContactIdentity.cryptoId, ownedCryptoId: obvContactIdentity.ownedIdentity.cryptoId)
                .postOnDispatchQueue()
        }
    }
        
    
    private func processContactObvCapabilitiesWereUpdated(obvContactIdentity: ObvContactIdentity) {
        let op1 = SyncPersistedObvContactIdentitiesWithEngineOperation(obvEngine: obvEngine)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        if composedOp.isCancelled {
            assertionFailure()
        }
    }
    
    
    private func observeNewTrustedContactIdentity() {
        let NotificationType = ObvEngineNotification.NewTrustedContactIdentity.self
        let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: internalQueue) { [weak self] (notification) in
            guard let obvContactIdentity = NotificationType.parse(notification) else { return }
            ObvStack.shared.performBackgroundTaskAndWait { [weak self] (context) in
                guard let _self = self else { return }
                _self.addObvPersistedContactIdentity(obvContactIdentity: obvContactIdentity, within: context)
                do {
                    try context.save(logOnFailure: _self.log)
                } catch {
                    os_log("We could not add new contact identity", log: _self.log, type: .fault)
                    return
                }
                os_log("A new contact identity %@ is available", log: _self.log, type: .info, obvContactIdentity.description)
            }
        }
        observationTokens.append(token)
    }

    
    private func addObvPersistedContactIdentity(obvContactIdentity: ObvContactIdentity, within context: NSManagedObjectContext) {
        guard (try? PersistedObvContactIdentity.get(persisted: obvContactIdentity, within: context)) == nil else { return }
        _ = PersistedObvContactIdentity(contactIdentity: obvContactIdentity, within: context)
    }
    
    
    private func observeContactWasDeletedNotifications() {
        let log = self.log
        let token = ObvEngineNotificationNew.observeContactWasDeleted(within: NotificationCenter.default, queue: internalQueue) { [weak self] (contactIdentity) in
            guard let _self = self else { return }
            do {
                try ObvStack.shared.performBackgroundTaskAndWaitOrThrow { (context) in
                    context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
                    try _self.deleteObvPersistedContactIdentity(withCryptoId: contactIdentity.cryptoId, ofOwnedIdentityWithCryptoId: contactIdentity.ownedIdentity.cryptoId, within: context)
                    try context.save(logOnFailure: log)
                }
            } catch {
                os_log("Could not delete the contact identity", log: log, type: .fault)
            }
        }
        observationTokens.append(token)
    }
    
    
    /// When a new channel is created with a contact device:
    /// - we create a contact device
    /// - we send the one-to-one discussion shared settings to the contact (well, we notify that it should be sent)
    private func observeNewObliviousChannelWithContactDeviceNotifications() {
        let log = self.log
        observationTokens.append(ObvEngineNotificationNew.observeNewObliviousChannelWithContactDevice(within: NotificationCenter.default, queue: internalQueue) { (contactDevice) in
            
            var discussionObjectID: NSManagedObjectID?
            
            ObvStack.shared.performBackgroundTaskAndWait { (context) in
                
                guard PersistedObvContactDevice(obvContactDevice: contactDevice, within: context) != nil else {
                    os_log("We could not create a device for a contact identity", log: log, type: .fault)
                    assertionFailure()
                    return
                }
                
                let contact: PersistedObvContactIdentity
                do {
                    guard let _contact = try PersistedObvContactIdentity.get(persisted: contactDevice.contactIdentity, within: context) else {
                        os_log("We could not find the contact identity associated with the new channel", log: log, type: .fault)
                        assertionFailure()
                        return
                    }
                    contact = _contact
                } catch {
                    os_log("We could not get the contact identity associated with the new channel: %{public}@", log: log, type: .fault, error.localizedDescription)
                    return
                }
                
                discussionObjectID = contact.oneToOneDiscussion.objectID
                
                do {
                    try context.save(logOnFailure: log)
                } catch {
                    os_log("We could not add a device for a contact identity", log: log, type: .fault)
                    assert(false)
                    return
                }
            }
            
            if let objectID = discussionObjectID {
                ObvMessengerInternalNotification.persistedDiscussionSharedConfigurationShouldBeSent(persistedDiscussionObjectID: objectID)
                    .postOnDispatchQueue()
            }

        })

    }
 
    
    private func observeDeletedObliviousChannelWithContactDevice() {
        let log = self.log
        let NotificationType = ObvEngineNotification.DeletedObliviousChannelWithContactDevice.self
        let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: internalQueue) { (notification) in
            guard let contactDevice = NotificationType.parse(notification) else { return }
            ObvStack.shared.performBackgroundTaskAndWait { (context) in
                do {
                    try PersistedObvContactDevice.delete(contactDeviceIdentifier: contactDevice.identifier, contactCryptoId: contactDevice.contactIdentity.cryptoId, ownedCryptoId: contactDevice.contactIdentity.ownedIdentity.cryptoId, within: context)
                    try context.save(logOnFailure: log)
                } catch {
                    os_log("We could not delete a device for a contact identity", log: log, type: .fault)
                    return
                }
                os_log("A contact device was deleted", log: log, type: .info)
            }
        }
        observationTokens.append(token)
    }

    
    private func processTrustedPhotoOfContactIdentityHasBeenUpdated(obvContactIdentity: ObvContactIdentity) {
        let log = self.log
        ObvStack.shared.performBackgroundTaskAndWait { context in
            guard let persistedContactIdentity = try? PersistedObvContactIdentity.get(persisted: obvContactIdentity, within: context) else { return }
            persistedContactIdentity.updatePhotoURL(with: obvContactIdentity.trustedIdentityDetails.photoURL)
            do {
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could set the updated PhotoURL on a persisted contact", log: log, type: .fault)
            }
        }
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
            os_log("Could not start TrustEstablishmentWithMutualScanProtocol: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    
    
    private func processUserWantToChangeContactsSortOrderNotification(ownedCryptoId: ObvCryptoId, sortOrder: ContactsSortOrder) {
        assert(OperationQueue.current != internalQueue) // Prevent a deadlock
        let op = UpdateContactsSortOrderOperation(ownedCryptoId: ownedCryptoId, newSortOrder: sortOrder, log: log)
        internalQueue.addOperations([op], waitUntilFinished: true)
        op.logReasonIfCancelled(log: log)
    }
    
    
    private func processUpdatedSetOfContactsCertifiedByOwnKeycloakNotification(ownedIdentity: ObvCryptoId, contactsCertifiedByOwnKeycloak: Set<ObvCryptoId>) {
        assert(OperationQueue.current != internalQueue) // Prevent a deadlock
        let op = UpdateListOfContactsCertifiedByOwnKeycloakOperation(ownedIdentity: ownedIdentity, contactsCertifiedByOwnKeycloak: contactsCertifiedByOwnKeycloak)
        internalQueue.addOperations([op], waitUntilFinished: true)
        op.logReasonIfCancelled(log: log)
    }
    
    
    private func processOwnedIdentityUnbindingFromKeycloakPerformedNotification(ownedIdentity: ObvCryptoId, result: Result<Void,Error>) {
        assert(OperationQueue.current != internalQueue) // Prevent a deadlock
        let op = UpdateListOfContactsCertifiedByOwnKeycloakOperation(ownedIdentity: ownedIdentity, contactsCertifiedByOwnKeycloak: Set<ObvCryptoId>([]))
        internalQueue.addOperations([op], waitUntilFinished: true)
        op.logReasonIfCancelled(log: log)
    }
    
    
    private func processContactIsActiveChangedWithinEngine(obvContactIdentity: ObvContactIdentity) {
        assert(OperationQueue.current != internalQueue) // Prevent a deadlock
        let op1 = UpdatePersistedContactIdentityWithObvContactIdentityOperation(obvContactIdentity: obvContactIdentity)
        let op = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([op], waitUntilFinished: true)
        op.logReasonIfCancelled(log: log)
    }
    
}


// MARK: - Helpers

extension ContactIdentityCoordinator {
    
    private func deleteObvPersistedContactIdentity(withCryptoId contactCryptoId: ObvCryptoId, ofOwnedIdentityWithCryptoId ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
        
        guard let persistedContactIdentity = try PersistedObvContactIdentity.get(contactCryptoId: contactCryptoId, ownedIdentityCryptoId: ownedCryptoId, within: context) else {
            os_log("Could not find persisted contact identity", log: log, type: .error)
            throw makeError(message: "Could not find persisted contact identity")
        }

        // When a contact is deleted, we lock the one2one we have we this contact and, only then, we delete the contact.
        // Note that we do not access the discussion using the persistedContactIdentity to prevent crashing if the discussion
        // Does not exists in DB.
        
        if let oneToOneDiscussion = try PersistedOneToOneDiscussion.get(objectID: persistedContactIdentity.oneToOneDiscussion.objectID, within: context) as? PersistedOneToOneDiscussion {
            guard let persistedDiscussionOneToOneLocked = PersistedDiscussionOneToOneLocked(persistedOneToOneDiscussionToLock: oneToOneDiscussion) else {
                os_log("Could not lock the persisted oneToOne discussion", log: log, type: .error)
                throw makeError(message: "Could not lock the persisted oneToOne discussion")
            }
            
            _ = try PersistedMessageSystem(.contactWasDeleted, optionalContactIdentity: nil, optionalCallLogItem: nil, discussion: persistedDiscussionOneToOneLocked)
        }
        
        
        context.delete(persistedContactIdentity)
        
    }
        
}
