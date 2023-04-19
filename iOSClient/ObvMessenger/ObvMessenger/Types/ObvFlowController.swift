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

import UIKit
import ObvEngine
import ObvTypes
import os.log
import CoreData
import ObvCrypto


protocol ObvFlowController: UINavigationController, SingleDiscussionViewControllerDelegate, SingleGroupViewControllerDelegate, SingleGroupV2ViewControllerDelegate, SingleContactIdentityViewHostingControllerDelegate {

    var flowDelegate: ObvFlowControllerDelegate? { get }
    var log: OSLog { get }
    var obvEngine: ObvEngine { get }
    var observationTokens: [NSObjectProtocol] { get set }

    func userWantsToDisplay(persistedDiscussion discussion: PersistedDiscussion)
    func userWantsToDisplay(persistedMessage message: PersistedMessage)
    
}


// MARK: - Showing/Hiding SnackBar

extension ObvFlowController {
    
    func showSnackBar(with category: OlvidSnackBarCategory, currentOwnedCryptoId: ObvCryptoId, completion: @escaping () -> Void) {
    
        removeSnackBar { [weak self] in
            guard let _self = self else { completion(); return }
            guard let firstVC = _self.children.first else { completion(); return }
            let snackBar = OlvidSnackBarView()
            snackBar.alpha = 0.0
            snackBar.configure(with: category, ownedCryptoId: currentOwnedCryptoId)
            firstVC.view.addSubview(snackBar)
            snackBar.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                snackBar.trailingAnchor.constraint(equalTo: firstVC.view.trailingAnchor),
                snackBar.bottomAnchor.constraint(equalTo: firstVC.view.safeAreaLayoutGuide.bottomAnchor),
                snackBar.leadingAnchor.constraint(equalTo: firstVC.view.leadingAnchor),
            ])
            UIView.animate(withDuration: 0.3) {
                snackBar.alpha = 1.0
            } completion: { _ in
                completion()
            }

        }
        
    }
    
    
    func removeSnackBar(completion: @escaping () -> Void) {
        guard let firstVC = children.first else { completion(); return }
        guard let snackBar = firstVC.view.subviews.compactMap({ $0 as? OlvidSnackBarView }).first else {
            completion()
            return
        }
        UIView.animate(withDuration: 0.3) {
            snackBar.alpha = 0.0
        } completion: { _ in
            snackBar.removeFromSuperview()
            completion()
        }

    }
    
}


// MARK: - Implementations of protocol methods

extension ObvFlowController {
    
    func userWantsToDisplay(persistedDiscussion discussion: PersistedDiscussion) {
        userWantsToDisplayImpl(persistedDiscussion: discussion, messageToShow: nil)
    }

    func userWantsToDisplay(persistedMessage message: PersistedMessage) {
        let discussion = message.discussion
        userWantsToDisplayImpl(persistedDiscussion: discussion, messageToShow: message)
    }

    private func userWantsToDisplayImpl(persistedDiscussion discussion: PersistedDiscussion, messageToShow: PersistedMessage?) {
                
        assert(Thread.isMainThread)
        os_log("User wants to display persisted discussion", log: log, type: .info)

        let discussionToDisplay: PersistedDiscussion
        if discussion.managedObjectContext == ObvStack.shared.viewContext {
            discussionToDisplay = discussion
        } else {
            guard let _discussion = try? PersistedDiscussion.get(objectID: discussion.typedObjectID, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                return
            }
            discussionToDisplay = _discussion
        }
        
        let messageToDisplay: PersistedMessage?
        if let messageToShow = messageToShow {
            if messageToShow.managedObjectContext == ObvStack.shared.viewContext {
                messageToDisplay = messageToShow
            } else {
                if let _message = try? PersistedMessage.get(with: messageToShow.typedObjectID, within: ObvStack.shared.viewContext) {
                    messageToDisplay = _message
                } else {
                    assertionFailure()
                    messageToDisplay = nil
                }
            }
        } else {
            messageToDisplay = nil
        }
        
        // Dismiss any presented view controller
        if let presentedViewController = presentedViewController {
            presentedViewController.dismiss(animated: true, completion: { [weak self] in
                self?.popOrPushDiscussionViewController(for: discussionToDisplay, messageToShow: messageToDisplay)
            })
        } else {
            popOrPushDiscussionViewController(for: discussionToDisplay, messageToShow: messageToDisplay)
        }
    }

    private func buildSingleDiscussionVC(discussion: PersistedDiscussion, messageToShow: PersistedMessage?) -> DiscussionViewController {
        if #available(iOS 15.0, *), !ObvMessengerSettings.Interface.useOldDiscussionInterface {
            let initialScroll: NewSingleDiscussionViewController.InitialScroll
            if let messageToShow = messageToShow {
                initialScroll = .specificMessage(messageToShow)
            } else {
                initialScroll = .newMessageSystemOrLastMessage
            }
            let singleDiscussionVC = NewSingleDiscussionViewController(discussion: discussion, delegate: self, initialScroll: initialScroll)
            singleDiscussionVC.hidesBottomBarWhenPushed = true
            return singleDiscussionVC
        } else {
            let singleDiscussionVC = SingleDiscussionViewController(collectionViewLayout: UICollectionViewLayout())
            singleDiscussionVC.discussion = discussion
            singleDiscussionVC.composeMessageViewDataSource = ComposeMessageDataSourceWithDraft(draft: discussion.draft)
            singleDiscussionVC.composeMessageViewDocumentPickerDelegate = ComposeMessageViewDocumentPickerAdapterWithDraft(draft: discussion.draft)
            singleDiscussionVC.strongComposeMessageViewSendMessageDelegate = ComposeMessageViewSendMessageAdapterWithDraft(draft: discussion.draft)
            singleDiscussionVC.uiApplication = UIApplication.shared
            singleDiscussionVC.delegate = self
            singleDiscussionVC.hidesBottomBarWhenPushed = true
            return singleDiscussionVC
        }
    }
    
    private func popOrPushDiscussionViewController(for discussion: PersistedDiscussion, messageToShow: PersistedMessage?) {
        
        assert(Thread.isMainThread)
        assert(discussion.managedObjectContext == ObvStack.shared.viewContext)

        // Look for an existing SingleDiscussionViewController and pop to it if found
        for vc in children {
            guard let discussionVC = vc as? DiscussionViewController else { continue }
            guard discussionVC.discussionObjectID == discussion.typedObjectID else { continue }
            // If we reach this point, there exists an appropriate SingleDiscussionViewController within the navigation stack, so we pop to this VC and return
            popToViewController(discussionVC, animated: true)
            if let messageToShow = messageToShow {
                discussionVC.scrollTo(message: messageToShow)
            }
            return
        }
        
        os_log("Will instantiate a singleDiscussionVC", log: log, type: .info)
        
        // If we reach this point, we need to push a new SingleDiscussionViewController.

        let discussionVC = buildSingleDiscussionVC(discussion: discussion, messageToShow: messageToShow)
        showDetailViewController(discussionVC, sender: self)

        // There might be some AirDrop'ed files, add them to the discussion draft
        if let airDroppedFileURLs = flowDelegate?.getAndRemoveAirDroppedFileURLs() {
            for url in airDroppedFileURLs {
                discussionVC.addAttachmentFromAirDropFile(at: url)
            }
        }

    }


    func removeGroupViewController(groupUid: UID) {
        var newViewController = [UIViewController]()
        for vc in viewControllers {
            guard let groupVC = vc as? SingleGroupViewController, groupVC.obvContactGroup.groupUid == groupUid else {
                newViewController += [vc]
                continue
            }
            // Skip the view controller
        }
        setViewControllers(newViewController, animated: true)
    }


    /// If a a PersistedGroupV2 gets deleted (e.g., because we were kicked from the group), we want to dismiss any pushed `SingleGroupV2ViewController`.
    private func removeGroupViewController(persistedGroupV2ObjectId: TypeSafeManagedObjectID<PersistedGroupV2>) {
        var newViewController = [UIViewController]()
        for vc in viewControllers {
            guard let groupVC = vc as? SingleGroupV2ViewController, groupVC.persistedGroupV2ObjectID == persistedGroupV2ObjectId else {
                newViewController += [vc]
                continue
            }
            // Skip the view controller
        }
        setViewControllers(newViewController, animated: true)
    }

    
    /// This method should be called from the `viewDidLoad` method of all view controllers (conforming to this protocol) if they are susceptible to push a `SingleGroupV2ViewController` on their navigation stack.
    /// It allows to oberve `PersistedGroupV2WasDeleted` notifications and to update the stack accordingly.
    func observePersistedGroupV2WasDeletedNotifications() {
        observationTokens.append(
            ObvMessengerCoreDataNotification.observePersistedGroupV2WasDeleted(queue: OperationQueue.main) { [weak self] persistedGroupV2ObjectID in
                self?.removeGroupViewController(persistedGroupV2ObjectId: persistedGroupV2ObjectID)
            }
        )
    }

}


// MARK: - SingleDiscussionViewControllerDelegate

extension ObvFlowController {
    
    func userTappedTitleOfDiscussion(_ discussion: PersistedDiscussion) {
        
        let vcToPresent: UIViewController
        
        switch try? discussion.kind {
            
        case .oneToOne(withContactIdentity: let contactIdentity):
            
            // In case the title tapped is the one of a one2one discussion, we display the contact sheet of the contact
            guard let contactIdentity = contactIdentity else {
                os_log("Could not find contact identity. This is ok if it has just been deleted.", log: log, type: .error)
                return
            }
            vcToPresent = SingleContactIdentityViewHostingController(contact: contactIdentity, obvEngine: obvEngine)
            (vcToPresent as? SingleContactIdentityViewHostingController)?.delegate = self
            
        case .groupV1(withContactGroup: let contactGroup):
            
            guard let contactGroup = contactGroup else {
                os_log("Could find contact group (this is ok if it was just deleted)", log: log, type: .error)
                return
            }
            guard let singleGroupVC = try? SingleGroupViewController(persistedContactGroup: contactGroup, obvEngine: obvEngine) else { return }
            singleGroupVC.delegate = self
            vcToPresent = singleGroupVC
            
        case .groupV2(withGroup: let group):
            
            guard let group = group else {
                os_log("Could find group V2 (this is ok if it was just deleted)", log: log, type: .error)
                return
            }
            
            guard let singleGroupV2VC = try? SingleGroupV2ViewController(group: group, obvEngine: obvEngine, delegate: self) else { return }
            vcToPresent = singleGroupV2VC

        case .none:
            
            assertionFailure()
            return
            
        }
        
        let closeButton = BlockBarButtonItem.forClosing { [weak self] in self?.presentedViewController?.dismiss(animated: true) }
        vcToPresent.navigationItem.setLeftBarButton(closeButton, animated: false)
        present(UINavigationController(rootViewController: vcToPresent), animated: true)
        
    }
    
    
    func userDidTapOnContactImage(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>) {
        
        assert(Thread.isMainThread)
        
        guard let contactIdentity = try? PersistedObvContactIdentity.get(objectID: contactObjectID, within: ObvStack.shared.viewContext) else {
            os_log("Could not find contact identity. This is ok if it has just been deleted.", log: log, type: .error)
            return
        }

        let vcToPresent = SingleContactIdentityViewHostingController(contact: contactIdentity, obvEngine: obvEngine)
        vcToPresent.delegate = self

        let closeButton = BlockBarButtonItem.forClosing { [weak self] in self?.presentedViewController?.dismiss(animated: true) }
        vcToPresent.navigationItem.setLeftBarButton(closeButton, animated: false)
        present(UINavigationController(rootViewController: vcToPresent), animated: true)

    }
    
    @MainActor
    func userSelectedURL(_ url: URL, within vc: UIViewController) {
        flowDelegate?.userSelectedURL(url, within: vc)
    }

}

// MARK: - SingleContactViewControllerDelegate

extension ObvFlowController {

    
    func userWantsToNavigateToSingleGroupView(_ group: DisplayedContactGroup, within nav: UINavigationController?) {
        
        assert(group.groupV1 == nil || group.groupV2 == nil)
        
        let appropriateNav = nav ?? self

        if let groupV1 = group.groupV1 {
            userWantsToNavigateToSingleGroupView(persistedContactGroup: groupV1, within: appropriateNav)
        } else if let groupV2 = group.groupV2 {
            userWantsToNavigateToSingleGroupView(persistedGroupV2: groupV2, within: appropriateNav)
        } else {
            assertionFailure()
        }
        
    }

    
    private func userWantsToNavigateToSingleGroupView(persistedContactGroup: PersistedContactGroup, within nav: UINavigationController) {
                
        for vc in nav.children {
            guard let singleGroupViewController = vc as? SingleGroupViewController else { continue }
            guard singleGroupViewController.persistedContactGroup.objectID == persistedContactGroup.objectID else { continue }
            // If we reach this point, there exists an appropriate SingleGroupViewController within the navigation stack, so we pop to this VC and return
            nav.popToViewController(singleGroupViewController, animated: true)
            return
        }
        // If we reach this point, we could not find an appropriate VC within the navigation stack, so we push a new one
        guard let singleGroupViewController = try? SingleGroupViewController(persistedContactGroup: persistedContactGroup, obvEngine: obvEngine) else { return }
        singleGroupViewController.delegate = self
        nav.pushViewController(singleGroupViewController, animated: true)

    }

    
    private func userWantsToNavigateToSingleGroupView(persistedGroupV2: PersistedGroupV2, within nav: UINavigationController) {
        
        for vc in nav.children {
            guard let singleGroupViewController = vc as? SingleGroupV2ViewController else { continue }
            guard singleGroupViewController.persistedGroupV2ObjectID == persistedGroupV2.typedObjectID else { continue }
            // If we reach this point, there exists an appropriate SingleGroupV2ViewController within the navigation stack, so we pop to this VC and return
            nav.popToViewController(singleGroupViewController, animated: true)
            return
        }
        // If we reach this point, we could not find an appropriate VC within the navigation stack, so we push a new one
        guard let singleGroupViewController = try? SingleGroupV2ViewController(group: persistedGroupV2, obvEngine: obvEngine, delegate: self) else { return }
        nav.pushViewController(singleGroupViewController, animated: true)
        
    }
    
    
    func userWantsToUpdateTrustedIdentityDetailsOfContactIdentity(with contactCryptoId: ObvCryptoId, using newContactIdentityDetails: ObvIdentityDetails) {
        flowDelegate?.userWantsToUpdateTrustedIdentityDetailsOfContactIdentity(with: contactCryptoId, using: newContactIdentityDetails)
    }
    
    func userWantsToEditContactNickname(persistedContactObjectId: NSManagedObjectID) {
        assert(Thread.isMainThread)
        
        guard let persistedObvContactIdentity = try? PersistedObvContactIdentity.get(objectID: persistedContactObjectId, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        
        let title = NSLocalizedString("Set Contact Nickname", comment: "")
        let message = NSLocalizedString("This nickname will only be visible to you and used instead of your contact name within the Olvid interface.", comment: "UIAlertController message")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.font = UIFont.preferredFont(forTextStyle: UIFont.TextStyle.headline)
            textField.autocapitalizationType = .words
            if let customDisplayName = persistedObvContactIdentity.customDisplayName {
                textField.text = customDisplayName
            } else {
                textField.text = persistedObvContactIdentity.identityCoreDetails?.getDisplayNameWithStyle(.firstNameThenLastName) ?? persistedObvContactIdentity.fullDisplayName
            }
        }
        guard let textField = alert.textFields?.first else { return }
        let removeNicknameAction = UIAlertAction(title: CommonString.removeNickname, style: .destructive) { [weak self] (_) in
            self?.setContactNickname(to: nil, persistedContactObjectId: persistedContactObjectId)
        }
        let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: UIAlertAction.Style.cancel)
        let okAction = UIAlertAction(title: CommonString.Word.Ok, style: UIAlertAction.Style.default) { [weak self] (action) in
            if let newNickname = textField.text, !newNickname.isEmpty {
                self?.setContactNickname(to: newNickname, persistedContactObjectId: persistedContactObjectId)
            } else {
                self?.setContactNickname(to: nil, persistedContactObjectId: persistedContactObjectId)
            }
        }
        alert.addAction(removeNicknameAction)
        alert.addAction(cancelAction)
        alert.addAction(okAction)
        if let presentedViewController = self.presentedViewController {
            presentedViewController.present(alert, animated: true)
        } else {
            self.present(alert, animated: true, completion: nil)
        }

    }
    
    
    private func setContactNickname(to newNickname: String?, persistedContactObjectId: NSManagedObjectID) {
        ObvStack.shared.performBackgroundTask { [weak self] (context) in
            guard let _self = self else { return }
            do {
                guard let writableContact = try PersistedObvContactIdentity.get(objectID: persistedContactObjectId, within: context) else { assertionFailure(); return }
                try writableContact.setCustomDisplayName(to: newNickname)
                try context.save(logOnFailure: _self.log)
            } catch {
                os_log("Could not remove contact custom display name", log: _self.log, type: .error)
            }
        }
    }

    
    func userWantsToInviteContactToOneToOne(persistedContactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>) {
        let log = self.log
        ObvStack.shared.performBackgroundTask { [weak self] (context) in
            do {
                guard let contact = try PersistedObvContactIdentity.get(objectID: persistedContactObjectID, within: context) else { assertionFailure(); return }
                assert(!contact.isOneToOne)
                guard let ownedIdentity = contact.ownedIdentity else { assertionFailure(); return }
                try self?.obvEngine.sendOneToOneInvitation(ownedIdentity: ownedIdentity.cryptoId, contactIdentity: contact.cryptoId)
            } catch {
                os_log("Could not invite contact to OneToOne: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
    }
    
    
    func userWantsToCancelSentInviteContactToOneToOne(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) {
        let log = self.log
        ObvStack.shared.performBackgroundTask { [weak self] (context) in
            do {
                guard let oneToOneInvitationSent = try PersistedInvitationOneToOneInvitationSent.get(fromOwnedIdentity: ownedCryptoId,
                                                                                                     toContact: contactCryptoId,
                                                                                                     within: context) else {
                    assertionFailure(); return
                }
                guard var dialog = oneToOneInvitationSent.obvDialog else { assertionFailure(); return }
                try dialog.cancelOneToOneInvitationSent()
                self?.obvEngine.respondTo(dialog)
            } catch {
                os_log("Could not invite contact to OneToOne: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
    }
    
    
    func userWantsToSyncOneToOneStatusOfContact(persistedContactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>) {
        let log = self.log
        ObvStack.shared.performBackgroundTask { [weak self] (context) in
            do {
                guard let _self = self else { return }
                guard let contact = try PersistedObvContactIdentity.get(objectID: persistedContactObjectID, within: context) else { assertionFailure(); return }
                guard let ownedIdentity = contact.ownedIdentity else { assertionFailure(); return }
                let ownedCryptoId = ownedIdentity.cryptoId
                let contactToSync = contact.cryptoId
                Task {
                    do {
                        try await _self.obvEngine.requestOneStatusSyncRequest(ownedIdentity: ownedCryptoId, contactsToSync: Set([contactToSync]))
                    } catch {
                        os_log("Could not sync contact OneToOne status: %{public}@", log: log, type: .fault, error.localizedDescription)
                        assertionFailure()
                    }
                }
            } catch {
                os_log("Could not sync contact OneToOne status: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
    }
    
}


// MARK: - SingleGroupViewControllerDelegate, SingleGroupV2ViewControllerDelegate

extension ObvFlowController {
    
    func userWantsToDisplay(persistedContact: PersistedObvContactIdentity, within nav: UINavigationController?) {
        
        let appropriateNav = nav ?? self

        for vc in appropriateNav.children {
            guard let singleContactIdentityViewHostingController = vc as? SingleContactIdentityViewHostingController else { continue }
            guard singleContactIdentityViewHostingController.contactCryptoId == persistedContact.cryptoId else { continue }
            // If we reach this point, there exists an appropriate SingleContactViewController within the navigation stack, so we pop to this VC and return
            appropriateNav.popToViewController(singleContactIdentityViewHostingController, animated: true)
            return
        }
        // If we reach this point, we could not find an appropriate VC within the navigation stack, so we push a new one
        let vcToPush = SingleContactIdentityViewHostingController(contact: persistedContact, obvEngine: obvEngine)
        vcToPush.delegate = self
        appropriateNav.pushViewController(vcToPush, animated: true)
        
    }

    
    func userWantsToCloneGroup(displayedContactGroupObjectID: TypeSafeManagedObjectID<DisplayedContactGroup>) {

        assert(Thread.isMainThread)

        guard let displayedContactGroup = try? DisplayedContactGroup.get(objectID: displayedContactGroupObjectID.objectID, within: ObvStack.shared.viewContext) else { return }
        
        let ownedCryptoId: ObvCryptoId
        let initialGroupMembers: Set<ObvCryptoId>
        let originalGroupName: String?
        let initialGroupDescription: String?
        let originalPhotoURL: URL?
        
        switch displayedContactGroup.group {
        case .none:
            return
            
        case .groupV2(group: let group):
            
            guard let _ownedCryptoId = try? group.ownCryptoId else { assertionFailure(); return }
            ownedCryptoId = _ownedCryptoId
            initialGroupMembers = Set(group.contactsAmongOtherPendingAndNonPendingMembers.map({ $0.cryptoId }))
            originalGroupName = group.trustedName
            initialGroupDescription = group.trustedDescription?.mapToNilIfZeroLength()
            if let url = group.trustedPhotoURL, FileManager.default.fileExists(atPath: url.path) {
                originalPhotoURL = url
            } else {
                originalPhotoURL = nil
            }
            
        case .groupV1(group: let group):
            
            guard let ownedIdentity = group.ownedIdentity else { assertionFailure(); return }
            ownedCryptoId = ownedIdentity.cryptoId
            // Get a list of contacts that need to be included in the cloned group
            let candidates: Set<PersistedObvContactIdentity>
            do {
                let contactsAmongPendingMembers = Set(group.pendingMembers
                    .map({ $0.cryptoId })
                    .compactMap({ try? PersistedObvContactIdentity.get(cryptoId: $0, ownedIdentity: ownedIdentity, whereOneToOneStatusIs: .any) }))
                candidates = group.contactIdentities.union(contactsAmongPendingMembers)
            }
            // Check that all the candidates have the appropriate capability
            let candidatesNotSupportingGroupV2 = candidates.filter({ !$0.supportsCapability(.groupsV2) })
            guard candidatesNotSupportingGroupV2.isEmpty else {
                displayAlertWhenTryingToCloneGroupV1WithMembersNotSupportingGroupsV2(contactsNotSupportingGroupV2: candidatesNotSupportingGroupV2)
                return
            }
            initialGroupMembers = Set(candidates.map({ $0.cryptoId }))
            originalGroupName = group.groupName.mapToNilIfZeroLength()
            initialGroupDescription = nil // The description of a group v1 is only available at the engine level, we don't fetch it here
            if let url = group.displayPhotoURL, FileManager.default.fileExists(atPath: url.path) {
                originalPhotoURL = url
            } else {
                originalPhotoURL = nil
            }
        }

        let initialGroupName: String?
        if let originalGroupName = originalGroupName, !originalGroupName.isEmpty {
            initialGroupName = CommonString.clonedGroupNameFromOriginalName(originalGroupName)
        } else {
            initialGroupName = nil
        }
                
        let initialPhotoURL: URL?
        if let originalPhotoURL = originalPhotoURL {
            // ObvMessengerConstants.containerURL.forProfilePicturesCache.path
            let randomFilename = UUID().uuidString
            let randomFileURL = ObvMessengerConstants.containerURL.forProfilePicturesCache.appendingPathComponent(randomFilename, isDirectory: false)
            do {
                try FileManager.default.copyItem(at: originalPhotoURL, to: randomFileURL)
                initialPhotoURL = randomFileURL
            } catch {
                assertionFailure()
                initialPhotoURL = nil
            }
        } else {
            initialPhotoURL = nil
        }
        
        let groupCreationFlowVC = GroupEditionFlowViewController(
            ownedCryptoId: ownedCryptoId,
            editionType: .cloneGroup(initialGroupMembers: initialGroupMembers, initialGroupName: initialGroupName, initialGroupDescription: initialGroupDescription, initialPhotoURL: initialPhotoURL),
            obvEngine: obvEngine)

        if let presentedViewController = presentedViewController {
            presentedViewController.dismiss(animated: true) { [weak self] in
                self?.present(groupCreationFlowVC, animated: true)
            }
        } else {
            present(groupCreationFlowVC, animated: true)
        }

    }
    
    
    private func displayAlertWhenTryingToCloneGroupV1WithMembersNotSupportingGroupsV2(contactsNotSupportingGroupV2: Set<PersistedObvContactIdentity>) {
        
        
        let arrrayOfMemberNames = contactsNotSupportingGroupV2.map({ $0.displayedCustomDisplayNameOrFirstNameOrLastName ?? $0.customOrNormalDisplayName })
        let allMemberNames = ListFormatter.localizedString(byJoining: arrrayOfMemberNames)
        let title = NSLocalizedString("SOME_GROUP_MEMBERS_MUST_UPGRADE", comment: "")
        let message = String.localizedStringWithFormat(NSLocalizedString("FOLLOWING_MEMBERS_MUST_UPGRADE_BEFORE_CREATING_GROUP_V2_%@", comment: ""), allMemberNames)
        
        let alert = UIAlertController.init(title: title,
                                           message: message,
                                           preferredStyle: .alert)
        
        alert.addAction(.init(title: CommonString.Word.Ok, style: .cancel))
        
        present(alert, animated: true)
        
    }

}


// MARK: - ObvFlowControllerDelegate

protocol ObvFlowControllerDelegate: AnyObject {

    func getAndRemoveAirDroppedFileURLs() -> [URL]
    @MainActor func userSelectedURL(_ url: URL, within viewController: UIViewController)
    func performTrustEstablishmentProtocolOfRemoteIdentity(remoteCryptoId: ObvCryptoId, remoteFullDisplayName: String)
    func rePerformTrustEstablishmentProtocolOfContactIdentity(contactCryptoId: ObvCryptoId, contactFullDisplayName: String)
    func userWantsToUpdateTrustedIdentityDetailsOfContactIdentity(with: ObvCryptoId, using: ObvIdentityDetails)
    func userAskedToRefreshDiscussions(completionHandler: @escaping () -> Void)

}
