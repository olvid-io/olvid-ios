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

import UIKit
import ObvEngine
import ObvTypes
import os.log
import CoreData


protocol ObvFlowController: UINavigationController, SingleDiscussionViewControllerDelegate, SingleContactViewControllerDelegate, SingleGroupViewControllerDelegate, SingleContactIdentityViewHostingControllerDelegate {

    var flowDelegate: ObvFlowControllerDelegate? { get }
    var log: OSLog { get }

    func userWantsToDisplay(persistedDiscussion discussion: PersistedDiscussion)
    
    /// The implementation of this method shoud observe NewLockedPersistedDiscussion and call replaceDiscussionViewController
    func observePersistedDiscussionWasLockedNotifications()
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
                
        assert(Thread.isMainThread)
        assert(discussion.managedObjectContext == ObvStack.shared.viewContext)
        
        os_log("User wants to display persisted discussion", log: log, type: .info)

        // Dismiss any presented view controller
        if let presentedViewController = presentedViewController {
            presentedViewController.dismiss(animated: true, completion: { [weak self] in
                self?.popOrPushDiscussionViewController(for: discussion)
            })
        } else {
            popOrPushDiscussionViewController(for: discussion)
        }

    }

    private func buildSingleDiscussionVC(discussion: PersistedDiscussion) -> DiscussionViewController {
        if #available(iOS 15.0, *), !ObvMessengerSettings.Interface.useOldDiscussionInterface {
            let singleDiscussionVC = NewSingleDiscussionViewController(discussion: discussion, delegate: self)
            singleDiscussionVC.hidesBottomBarWhenPushed = true
            return singleDiscussionVC
        } else {
            let singleDiscussionVC = SingleDiscussionViewController(collectionViewLayout: UICollectionViewLayout())
            singleDiscussionVC.discussion = discussion
            singleDiscussionVC.restrictToLastMessages = false
            singleDiscussionVC.composeMessageViewDataSource = ComposeMessageDataSourceWithDraft(draft: discussion.draft)
            singleDiscussionVC.composeMessageViewDocumentPickerDelegate = ComposeMessageViewDocumentPickerAdapterWithDraft(draft: discussion.draft)
            singleDiscussionVC.strongComposeMessageViewSendMessageDelegate = ComposeMessageViewSendMessageAdapterWithDraft(draft: discussion.draft)
            singleDiscussionVC.uiApplication = UIApplication.shared
            singleDiscussionVC.delegate = self
            singleDiscussionVC.hidesBottomBarWhenPushed = true
            return singleDiscussionVC
        }
    }
    
    private func popOrPushDiscussionViewController(for discussion: PersistedDiscussion) {
        
        assert(Thread.isMainThread)
        assert(discussion.managedObjectContext == ObvStack.shared.viewContext)

        // Look for an existing SingleDiscussionViewController and pop to it if found
        for vc in children {
            guard let discussionVC = vc as? DiscussionViewController else { continue }
            guard discussionVC.discussionObjectID == discussion.typedObjectID else { continue }
            // If we reach this point, there exists an appropriate SingleDiscussionViewController within the navigation stack, so we pop to this VC and return
            popToViewController(discussionVC, animated: true)
            return
        }
        
        os_log("Will instantiate a singleDiscussionVC", log: log, type: .info)
        
        // If we reach this point, we need to push a new SingleDiscussionViewController.

        let discussionVC = buildSingleDiscussionVC(discussion: discussion)
        showDetailViewController(discussionVC, sender: self)

        // There might be some AirDrop'ed files, add them to the discussion draft
        if let airDroppedFileURLs = flowDelegate?.getAndRemoveAirDroppedFileURLs() {
            for url in airDroppedFileURLs {
                discussionVC.addAttachmentFromAirDropFile(at: url)
            }
        }

    }

    func replaceDiscussionViewController(discussionToReplace: TypeSafeURL<PersistedDiscussion>, newDiscussionId: TypeSafeManagedObjectID<PersistedDiscussion>) {
        assert(Thread.isMainThread)
        var newViewController = [UIViewController]()
        for currentVC in viewControllers {
            
            let newVC: UIViewController
            if let discussionVC = currentVC as? DiscussionViewController,
                discussionVC.discussionObjectID.uriRepresentation() == discussionToReplace,
                let discussion = try? PersistedDiscussion.get(objectID: newDiscussionId, within: ObvStack.shared.viewContext) {
                newVC = buildSingleDiscussionVC(discussion: discussion)
            } else {
                newVC = currentVC
            }
            newViewController += [newVC]

        }
        setViewControllers(newViewController, animated: true)
    }

    func removeGroupViewController(groupUid: UID) {
        var newViewController = [UIViewController]()
        for vc in viewControllers {
            guard let groupVC = vc as? SingleGroupViewController, groupVC.obvContactGroup.groupUid == groupUid else {
                newViewController += [vc]
                continue
            }
            /// Skip the view controller
        }
        setViewControllers(newViewController, animated: true)
    }
    
}


// MARK: - SingleDiscussionViewControllerDelegate

extension ObvFlowController {
    
    func userTappedTitleOfDiscussion(_ discussion: PersistedDiscussion) {
        
        let vcToPresent: UIViewController
        if let oneToOneDiscussion = discussion as? PersistedOneToOneDiscussion {
            
            // In case the title tapped is the one of a one2one discussion, we display the contact sheet of the contact
            
            guard let contactIdentity = oneToOneDiscussion.contactIdentity else {
                os_log("Could not find contact identity. This is ok if it has just been deleted.", log: log, type: .error)
                return
            }

            if #available(iOS 13, *) {
                vcToPresent = SingleContactIdentityViewHostingController(contact: contactIdentity, obvEngine: obvEngine)
                (vcToPresent as? SingleContactIdentityViewHostingController)?.delegate = self
            } else {
                guard let singleContactVC = try? SingleContactViewController(persistedObvContactIdentity: contactIdentity) else { return }
                singleContactVC.delegate = self
                vcToPresent = singleContactVC
            }

        } else if let groupDiscussion = discussion as? PersistedGroupDiscussion {
            
            guard let contactGroup = groupDiscussion.contactGroup else {
                os_log("Could find contact group (this is ok if it was just deleted)", log: log, type: .error)
                return
            }
            guard let singleGroupVC = try? SingleGroupViewController(persistedContactGroup: contactGroup) else { return }
            singleGroupVC.delegate = self
            vcToPresent = singleGroupVC
            
        } else {
            
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

        let vcToPresent: UIViewController
        if #available(iOS 13, *) {
            vcToPresent = SingleContactIdentityViewHostingController(contact: contactIdentity, obvEngine: obvEngine)
            (vcToPresent as? SingleContactIdentityViewHostingController)?.delegate = self
        } else {
            guard let singleContactVC = try? SingleContactViewController(persistedObvContactIdentity: contactIdentity) else { return }
            singleContactVC.delegate = self
            vcToPresent = singleContactVC
        }

        let closeButton = BlockBarButtonItem.forClosing { [weak self] in self?.presentedViewController?.dismiss(animated: true) }
        vcToPresent.navigationItem.setLeftBarButton(closeButton, animated: false)
        present(UINavigationController(rootViewController: vcToPresent), animated: true)

    }
    
    
    func userSelectedURL(_ url: URL, within vc: UIViewController) {
        flowDelegate?.userSelectedURL(url, within: vc)
    }

}

// MARK: - SingleContactViewControllerDelegate

extension ObvFlowController {

    func userWantsToDisplay(persistedContactGroup: PersistedContactGroup, within nav: UINavigationController?) {
        
        let appropriateNav = nav ?? self
        
        for vc in appropriateNav.children {
            guard let singleGroupViewController = vc as? SingleGroupViewController else { continue }
            guard singleGroupViewController.persistedContactGroup.objectID == persistedContactGroup.objectID else { continue }
            // If we reach this point, there exists an appropriate SingleGroupViewController within the navigation stack, so we pop to this VC and return
            appropriateNav.popToViewController(singleGroupViewController, animated: true)
            return
        }
        // If we reach this point, we could not find an appropriate VC within the navigation stack, so we push a new one
        guard let singleGroupViewController = try? SingleGroupViewController(persistedContactGroup: persistedContactGroup) else { return }
        singleGroupViewController.delegate = self
        appropriateNav.pushViewController(singleGroupViewController, animated: true)

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
                textField.text = persistedObvContactIdentity.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
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

}


// MARK: - SingleGroupViewControllerDelegate

extension ObvFlowController {
    
    func userWantsToDisplay(persistedContact: PersistedObvContactIdentity, within nav: UINavigationController?) {
        
        let appropriateNav = nav ?? self

        for vc in appropriateNav.children {
            if #available(iOS 13, *) {
                guard let singleContactIdentityViewHostingController = vc as? SingleContactIdentityViewHostingController else { continue }
                guard singleContactIdentityViewHostingController.contactCryptoId == persistedContact.cryptoId else { continue }
                // If we reach this point, there exists an appropriate SingleContactViewController within the navigation stack, so we pop to this VC and return
                appropriateNav.popToViewController(singleContactIdentityViewHostingController, animated: true)
                return
            } else {
                guard let singleContactViewController = vc as? SingleContactViewController else { continue }
                guard singleContactViewController.persistedObvContactIdentity.cryptoId == persistedContact.cryptoId else { continue }
                // If we reach this point, there exists an appropriate SingleContactViewController within the navigation stack, so we pop to this VC and return
                appropriateNav.popToViewController(singleContactViewController, animated: true)
                return
            }
        }
        // If we reach this point, we could not find an appropriate VC within the navigation stack, so we push a new one
        let vcToPush: UIViewController
        if #available(iOS 13, *) {
            vcToPush = SingleContactIdentityViewHostingController(contact: persistedContact, obvEngine: obvEngine)
            (vcToPush as? SingleContactIdentityViewHostingController)?.delegate = self
        } else {
            guard let singleContactViewController = try? SingleContactViewController(persistedObvContactIdentity: persistedContact) else { return }
            singleContactViewController.delegate = self
            vcToPush = singleContactViewController
        }
        appropriateNav.pushViewController(vcToPush, animated: true)
        
    }

}


// MARK: - ObvFlowControllerDelegate

protocol ObvFlowControllerDelegate: AnyObject {

    func getAndRemoveAirDroppedFileURLs() -> [URL]
    func userSelectedURL(_ url: URL, within viewController: UIViewController)
    func performTrustEstablishmentProtocolOfRemoteIdentity(remoteCryptoId: ObvCryptoId, remoteFullDisplayName: String)
    func rePerformTrustEstablishmentProtocolOfContactIdentity(contactCryptoId: ObvCryptoId, contactFullDisplayName: String)
    func userWantsToUpdateTrustedIdentityDetailsOfContactIdentity(with: ObvCryptoId, using: ObvIdentityDetails)
    func userAskedToRefreshDiscussions(completionHandler: @escaping () -> Void)

}
