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

import SwiftUI
import os.log
import ObvTypes
import ObvEngine
import CoreData
import OlvidUtils
import ObvUICoreData
import ObvAppCoreConstants
import ObvDesignSystem

@MainActor
protocol SingleContactIdentityViewHostingControllerDelegate: AnyObject {
    func userWantsToNavigateToListOfContactDevicesView(_ contact: PersistedObvContactIdentity, within nav: UINavigationController?)
    func userWantsToNavigateToListOfTrustOriginsView(_ trustOrigins: [ObvTrustOrigin], within nav: UINavigationController?)
    func userWantsToNavigateToSingleGroupView(_ group: DisplayedContactGroup, within nav: UINavigationController?)
    func userWantsToDisplay(persistedDiscussion discussion: PersistedDiscussion)
    func userWantsToInviteContactToOneToOne(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId)
    func userWantsToCancelSentInviteContactToOneToOne(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId)
    func userWantsToSyncOneToOneStatusOfContact(persistedContactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>)
}


final class SingleContactIdentityViewHostingController: UIHostingController<SingleContactIdentityView>, SingleContactIdentityDelegate, SomeSingleContactViewController, ObvErrorMaker, PersonalNoteEditorViewActionsDelegate, EditNicknameAndCustomPictureViewControllerDelegate {
    
    let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "SingleContactIdentityViewHostingController")
    static let errorDomain = "SingleContactIdentityViewHostingController"
    
    let currentOwnedCryptoId: ObvCryptoId
    let contactPermanentID: ContactPermanentID
    private let contact: SingleContactIdentity
    private var observationTokens = [NSObjectProtocol]()
    private let persistedObvContactIdentityObjectID: NSManagedObjectID
    let contactCryptoId: ObvCryptoId
    private let ownedIdentityCryptoId: ObvCryptoId?
    private var keyValueObservations = [NSKeyValueObservation]()
    private let obvEngine: ObvEngine

    weak var delegate: SingleContactIdentityViewHostingControllerDelegate?
    
    init(contact: PersistedObvContactIdentity, obvEngine: ObvEngine) throws {
        guard let ownCryptoId = contact.ownedIdentity?.cryptoId else {
            throw Self.makeError(message: "Could not determine owned identity")
        }
        let contactObjectPermanentID = try contact.objectPermanentID
        self.currentOwnedCryptoId = ownCryptoId
        self.contactPermanentID = contactObjectPermanentID
        self.persistedObvContactIdentityObjectID = contact.objectID
        self.contactCryptoId = contact.cryptoId
        self.ownedIdentityCryptoId = contact.ownedIdentity?.cryptoId
        self.obvEngine = obvEngine
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
        title = contact.customDisplayName ?? contact.identityCoreDetails?.getDisplayNameWithStyle(.short) ?? contact.fullDisplayName
        keyValueObservations.append(contact.observe(\.customDisplayName) { [weak self] (_, _) in
            self?.title = contact.customDisplayName ?? contact.identityCoreDetails?.getDisplayNameWithStyle(.short) ?? contact.fullDisplayName
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
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        addRightBarButtonMenu()

    }
    
    
    private func addRightBarButtonMenu() {
        
        let actionEditNote = UIAction(
            title: NSLocalizedString("EDIT_PERSONAL_NOTE", comment: ""),
            image: UIImage(systemIcon: .pencil(.none)),
            handler: userWantsToShowPersonalNoteEditor)
        
        let actionEditNicknameAndCustomPhoto = UIAction(
            title: NSLocalizedString("EDIT_NICKNAME_AND_CUSTOM_PHOTO", comment: ""),
            image: UIImage(systemIcon: .camera(.none)),
            handler: { [weak self] _ in self?.userWantsToEditContactNickname() }
        )
        
        let menu = UIMenu(children: [actionEditNote, actionEditNicknameAndCustomPhoto])
        
        let barButtonItem = UIBarButtonItem(image: UIImage(systemIcon: .ellipsisCircle), menu: menu)
        
        navigationItem.rightBarButtonItems = [barButtonItem]
    }
    
    
    private func userWantsToShowPersonalNoteEditor(_ action: UIAction) {
        guard let contact = try? PersistedObvContactIdentity.get(
            contactCryptoId: contactCryptoId,
            ownedIdentityCryptoId: currentOwnedCryptoId,
            whereOneToOneStatusIs: .any,
            within: ObvStack.shared.viewContext) else { return }
        let personalNote = contact.note
        let viewControllerToPresent = PersonalNoteEditorHostingController(model: .init(initialText: personalNote), actions: self)
        if let sheet = viewControllerToPresent.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            sheet.preferredCornerRadius = 16.0
        }
        present(viewControllerToPresent, animated: true, completion: nil)
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let ownedIdentityCryptoId = self.ownedIdentityCryptoId else { assertionFailure(); return }
        ObvMessengerInternalNotification.userDidSeeNewDetailsOfContact(contactCryptoId: contactCryptoId, ownedCryptoId: ownedIdentityCryptoId)
            .postOnDispatchQueue()
        let obvContactIdentifier = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedIdentityCryptoId)
        ObvMessengerInternalNotification.resyncContactIdentityDevicesWithEngine(obvContactIdentifier: obvContactIdentifier)
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
        contactsPresentationVC.title = CommonString.Title.introduceTo(contact.publishedContactDetails?.coreDetails.getDisplayNameWithStyle(.short) ??
                                                                      persistedContact.identityCoreDetails?.getDisplayNameWithStyle(.short) ?? persistedContact.fullDisplayName)
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
        let obvEngine = self.obvEngine
        let log = self.log
        Task.detached {
            do {
                try await obvEngine.updateTrustedIdentityDetailsOfContactIdentity(with: contactCryptoId, ofOwnedIdentityWithCryptoId: ownedCryptoId, with: details)
            } catch {
                os_log("Could not update trusted identity details of a contact", log: log, type: .error)
                assertionFailure()
            }
        }
    }

    
    func userWantsToNavigateToSingleGroupView(_ group: DisplayedContactGroup) {
        delegate?.userWantsToNavigateToSingleGroupView(group, within: navigationController)
    }

    
    func userWantsToNavigateToListOfContactDevicesView(_ contact: PersistedObvContactIdentity) {
        delegate?.userWantsToNavigateToListOfContactDevicesView(contact, within: navigationController)
    }

    func userWantsToNavigateToListOfTrustOriginsView(trustOrigins: [ObvTrustOrigin]) {
        delegate?.userWantsToNavigateToListOfTrustOriginsView(trustOrigins, within: navigationController)
    }
    
    func userWantsToDisplay(persistedDiscussion: PersistedDiscussion) {
        delegate?.userWantsToDisplay(persistedDiscussion: persistedDiscussion)
    }
    
    func userWantsToEditContactNickname() {
        assert(Thread.isMainThread)
        guard let persistedContact = contact.persistedContact else { return }
        guard let contactIdentifier = try? persistedContact.contactIdentifier else { assertionFailure(); return }
        guard let contactInitial = persistedContact.circledInitialsConfiguration.initials?.text else { assertionFailure(); return }
        let contactPhoto: UIImage?
        if let url = persistedContact.photoURL {
            contactPhoto = UIImage(contentsOfFile: url.path)
        } else {
            contactPhoto = nil
        }
        let currentCustomPhoto: UIImage?
        if let url = persistedContact.customPhotoURL {
            currentCustomPhoto = UIImage(contentsOfFile: url.path)
        } else {
            currentCustomPhoto = nil
        }
        let currentNickname = persistedContact.customDisplayName ?? ""
        let vc = EditNicknameAndCustomPictureViewController(
            model: .init(identifier: .contact(contactIdentifier: contactIdentifier),
                         currentInitials: contactInitial,
                         defaultPhoto: contactPhoto,
                         currentCustomPhoto: currentCustomPhoto,
                         currentNickname: currentNickname),
            delegate: self)
        presentOnTop(vc, animated: true)
    }
    
    func userWantsToInviteContactToOneToOne() {
        guard let ownedCryptoId = contact.persistedContact?.ownedIdentity?.cryptoId,
              let contactCryptoId = contact.persistedContact?.cryptoId else {
            return
        }
        delegate?.userWantsToInviteContactToOneToOne(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
    }
    
    func userWantsToCancelSentInviteContactToOneToOne() {
        guard let persistedContact = contact.persistedContact else { return }
        guard let ownedIdentity = persistedContact.ownedIdentity else { return }
        delegate?.userWantsToCancelSentInviteContactToOneToOne(ownedCryptoId: ownedIdentity.cryptoId, contactCryptoId: persistedContact.cryptoId)
    }
    
    func userWantsToSyncOneToOneStatusOfContact() {
        guard let persistedContact = contact.persistedContact else { return }
        delegate?.userWantsToSyncOneToOneStatusOfContact(persistedContactObjectID: persistedContact.typedObjectID)
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
    
    
    // MARK: - PersonalNoteEditorViewActionsDelegate
    
    func userWantsToDismissPersonalNoteEditorView() async {
        guard presentedViewController is PersonalNoteEditorHostingController else { return }
        presentedViewController?.dismiss(animated: true)
    }
    
    
    @MainActor
    func userWantsToUpdatePersonalNote(with newText: String?) async {
        let contactIdentifier = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: currentOwnedCryptoId)
        ObvMessengerInternalNotification.userWantsToUpdatePersonalNoteOnContact(contactIdentifier: contactIdentifier, newText: newText)
            .postOnDispatchQueue()
        presentedViewController?.dismiss(animated: true)
    }

    
    // MARK: - EditNicknameAndCustomPictureViewControllerDelegate
    
    @MainActor
    func userWantsToSaveNicknameAndCustomPicture(controller: EditNicknameAndCustomPictureViewController, identifier: EditNicknameAndCustomPictureView.Model.IdentifierKind, nickname: String, customPhoto: UIImage?) async {
        let contactIdentifier: ObvContactIdentifier
        switch identifier {
        case .groupV2:
            assertionFailure("The controller is expected to be configured with an identifier corresponding to the contact shown by this view controller")
            return
        case .contact(let _contactIdentifier):
            contactIdentifier = _contactIdentifier
        }
        controller.dismiss(animated: true)
        guard let persistedContact = contact.persistedContact else { return }
        guard contactIdentifier == (try? persistedContact.contactIdentifier) else { assertionFailure(); return }
        let sanitizedNickname = nickname.trimmingWhitespacesAndNewlines()
        let newNickname = sanitizedNickname.isEmpty ? nil : sanitizedNickname
        ObvMessengerInternalNotification.userWantsToEditContactNicknameAndPicture(
            persistedContactObjectID: persistedContact.objectID,
            customDisplayName: newNickname,
            customPhoto: customPhoto)
        .postOnDispatchQueue()
    }
    
    
    @MainActor
    func userWantsToDismissEditNicknameAndCustomPictureViewController(controller: EditNicknameAndCustomPictureViewController) async {
        controller.dismiss(animated: true)
    }
    

}
