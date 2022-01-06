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

import SwiftUI
import os.log
import ObvTypes
import ObvEngine
import CoreData


protocol SingleContactIdentityViewHostingControllerDelegate: AnyObject {
    func userWantsToDisplay(persistedContactGroup: PersistedContactGroup, within nav: UINavigationController?)
    func userWantsToDisplay(persistedDiscussion discussion: PersistedDiscussion)
    func userWantsToEditContactNickname(persistedContactObjectId: NSManagedObjectID)
}

@available(iOS 13, *)
final class SingleContactIdentityViewHostingController: UIHostingController<SingleContactIdentityView>, SingleContactIdentityDelegate, SomeSingleContactViewController {
    
    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "SingleContactIdentityViewHostingController")

    private let contact: SingleContactIdentity
    private var editedSingleContact: SingleContactIdentity? = nil
    private var observationTokens = [NSObjectProtocol]()
    private let persistedObvContactIdentityObjectID: NSManagedObjectID
    let contactCryptoId: ObvCryptoId
    private let ownedIdentityCryptoId: ObvCryptoId?
    private var keyValueObservations = [NSKeyValueObservation]()

    weak var delegate: SingleContactIdentityViewHostingControllerDelegate?
    
    init(contact: PersistedObvContactIdentity, obvEngine: ObvEngine) {
        self.persistedObvContactIdentityObjectID = contact.objectID
        self.contactCryptoId = contact.cryptoId
        self.ownedIdentityCryptoId = contact.ownedIdentity?.cryptoId
        let trustOrigins = SingleContactIdentityViewHostingController.getTrustOriginsOfContact(contact, obvEngine: obvEngine)
        let singleContact = SingleContactIdentity(persistedContact: contact,
                                                  observeChangesMadeToContact: true,
                                                  trustOrigins: trustOrigins,
                                                  fetchGroups: true)
        let view = SingleContactIdentityView(contact: singleContact)
        self.contact = singleContact
        super.init(rootView: view)
        self.contact.delegate = self
        observeViewContextToDismissIfContactGetsDeleted()
        title = contact.customDisplayName ?? contact.identityCoreDetails.getDisplayNameWithStyle(.short)
        keyValueObservations.append(contact.observe(\.customDisplayName) { [weak self] (_, _) in
            self?.title = contact.customDisplayName ?? contact.identityCoreDetails.getDisplayNameWithStyle(.short)
        })
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        keyValueObservations.removeAll()
        guard let ownedIdentityCryptoId = self.ownedIdentityCryptoId else { assertionFailure(); return }
        ObvMessengerInternalNotification.userDidSeeNewDetailsOfContact(contactCryptoId: contactCryptoId, ownedCryptoId: ownedIdentityCryptoId)
            .postOnDispatchQueue()
    }
    
    private static func getTrustOriginsOfContact(_ contact: PersistedObvContactIdentity, obvEngine: ObvEngine) -> [ObvTrustOrigin] {
        assert(Thread.isMainThread)
        let contactCryptoId = contact.cryptoId
        guard let ownedCryptoId = contact.ownedIdentity?.cryptoId else { assertionFailure(); return [] }
        do {
            return try obvEngine.getTrustOriginsOfContactIdentity(with: contactCryptoId, ofOwnedIdentyWith: ownedCryptoId)
        } catch {
            assertionFailure()
            return []
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let ownedIdentityCryptoId = self.ownedIdentityCryptoId else { assertionFailure(); return }
        ObvMessengerInternalNotification.userDidSeeNewDetailsOfContact(contactCryptoId: contactCryptoId, ownedCryptoId: ownedIdentityCryptoId)
            .postOnDispatchQueue()
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc
    func dismissPresentedViewController() {
        presentedViewController?.dismiss(animated: true)
    }

    // MARK: - Implementing SingleContactIdentityDelegate

    func userWantsToPerformAnIntroduction(forContact contact: SingleContactIdentity) {
        assert(Thread.current.isMainThread)
        guard let persistedContact = contact.persistedContact else { assertionFailure(); return }
        guard let ownedIdentity = persistedContact.ownedIdentity else {
            os_log("Could not find owned identity. This is ok if it was just deleted.", log: log, type: .error)
            return
        }
        let contactsPresentationVC = ContactsPresentationViewController(ownedCryptoId: ownedIdentity.cryptoId, presentedContactCryptoId: persistedContact.cryptoId) {
            self.dismissPresentedViewController()
        }
        contactsPresentationVC.title = SingleContactViewController.Strings.contactsTVCTitle(contact.publishedContactDetails?.coreDetails.getDisplayNameWithStyle(.short) ??
                                                                                                persistedContact.identityCoreDetails.getDisplayNameWithStyle(.short))
        present(contactsPresentationVC, animated: true)
    }
    

    func userWantsToDeleteContact(_ contact: SingleContactIdentity, completion: @escaping (Bool) -> Void) {
        guard let obvContactIdentity = contact.persistedContact else { assertionFailure(); return }
        guard let ownedCryptoId = obvContactIdentity.ownedIdentity?.cryptoId else { assertionFailure(); return }
        ObvMessengerInternalNotification.userWantsToDeleteContact(contactCryptoId: obvContactIdentity.cryptoId,
                                                                  ownedCryptoId: ownedCryptoId,
                                                                  viewController: self,
                                                                  completionHandler: completion)
            .postOnDispatchQueue()
    }
    
    
    func userWantsToUpdateTrustedIdentityDetails(ofContact contact: SingleContactIdentity, usingPublishedDetails details: ObvIdentityDetails) {
        assert(Thread.isMainThread)
        guard let persistedContact = contact.persistedContact else { assertionFailure(); return }
        let contactCryptoId = persistedContact.cryptoId
        guard let ownedCryptoId = persistedContact.ownedIdentity?.cryptoId else { assertionFailure(); return }
        do {
            try obvEngine.updateTrustedIdentityDetailsOfContactIdentity(with: contactCryptoId, ofOwnedIdentityWithCryptoId: ownedCryptoId, with: details)
        } catch {
            os_log("Could not update trusted identity details of a contact", log: log, type: .error)
            assertionFailure()
        }
    }
    
    func userWantsToDisplay(persistedContactGroup: PersistedContactGroup) {
        delegate?.userWantsToDisplay(persistedContactGroup: persistedContactGroup, within: navigationController)
    }

    
    func userWantsToDisplay(persistedDiscussion: PersistedDiscussion) {
        delegate?.userWantsToDisplay(persistedDiscussion: persistedDiscussion)
    }
    
    func userWantsToEditContactNickname() {
        assert(Thread.isMainThread)
        guard let persistedContact = contact.persistedContact else { return }
        let trustOrigins = contact.trustOrigins
        editedSingleContact = SingleContactIdentity(persistedContact: persistedContact,
                                                    observeChangesMadeToContact: true,
                                                    trustOrigins: trustOrigins,
                                                    fetchGroups: true)
        let view = EditSingleContactIdentityNicknameNavigationView(singleIdentity: editedSingleContact!, saveAction: {
            self.dismiss(animated: true)
            let nicknameAndPicture = CustomNicknameAndPicture(
                customDisplayName: self.editedSingleContact!.customDisplayName,
                customPhotoURL: self.editedSingleContact!.customPhotoURL)
            ObvMessengerInternalNotification.userWantsToEditContactNicknameAndPicture(
                persistedContactObjectID: persistedContact.objectID,
                nicknameAndPicture: nicknameAndPicture).postOnDispatchQueue()
        }, dismissAction: {
            self.editedSingleContact = nil
            self.dismiss(animated: true)
        })
        let vc = UIHostingController(rootView: view)
        present(vc, animated: true)
    }
    
    // MARK: - Implementing ContactsPresentationViewControllerDelegate for contact introduction

    func userWantsToIntroduce(presentedContactCryptoId: ObvCryptoId, to contacts: Set<ObvCryptoId>, ofOwnedCryptoId ownedCryptoId: ObvCryptoId) {
        guard let otherContact = contacts.first else { return }
        guard otherContact != presentedContactCryptoId else { return }
        presentedViewController?.dismiss(animated: true) {
            ObvMessengerInternalNotification.userWantsToIntroduceContactToAnotherContact(ownedCryptoId: ownedCryptoId, firstContactCryptoId: presentedContactCryptoId, secondContactCryptoIds: contacts)
                .postOnDispatchQueue()
        }
    }

    // MARK: - Observing the view context
    
    /// If the contact gets deleted while we are looking at her `SingleContactIdentityViewHostingController`, we want to dismiss this view.
    /// In this method, we watch deletion of this contact from the view context. If this happens, we pop to the root view controller.
    func observeViewContextToDismissIfContactGetsDeleted() {
        let NotificationName = Notification.Name.NSManagedObjectContextObjectsDidChange
        let persistedObvContactIdentityObjectID = self.persistedObvContactIdentityObjectID
        observationTokens.append(NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { [weak self] (notification) in
            guard Thread.isMainThread else { return }
            guard let context = notification.object as? NSManagedObjectContext else { assertionFailure(); return }
            guard context == ObvStack.shared.viewContext else { return }
            guard let deletedObjects = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> else { return }
            guard !deletedObjects.isEmpty else { return }
            let deletedObjectIDs = deletedObjects.map({ $0.objectID })
            guard deletedObjectIDs.contains(persistedObvContactIdentityObjectID) else { return }
            self?.navigationController?.popToRootViewController(animated: true)
        })
    }
    
}
