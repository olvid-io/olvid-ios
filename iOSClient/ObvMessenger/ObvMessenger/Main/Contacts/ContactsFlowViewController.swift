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
import os.log
import ObvEngine
import ObvTypes


final class ContactsFlowViewController: UINavigationController, ObvFlowController {
    
    // Variables
    
    private(set) var ownedCryptoId: ObvCryptoId!

    private var observationTokens = [NSObjectProtocol]()

    // Constants
    
    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    // Delegate
    
    weak var flowDelegate: ObvFlowControllerDelegate?

    // MARK: - Factory

    // Factory (required because creating a custom init does not work under iOS 12)
    static func create(ownedCryptoId: ObvCryptoId) -> ContactsFlowViewController {

        let allContactsVC = AllContactsViewController(ownedCryptoId: ownedCryptoId)
        let vc = self.init(rootViewController: allContactsVC)

        vc.ownedCryptoId = ownedCryptoId

        allContactsVC.delegate = vc

        vc.title = CommonString.Word.Contacts
        
        if #available(iOS 13, *) {
            let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
            let image = UIImage(systemName: "person", withConfiguration: symbolConfiguration)
            vc.tabBarItem = UITabBarItem(title: nil, image: image, tag: 0)
        } else {
            let iconImage = UIImage(named: "tabbar_icon_contacts")
            vc.tabBarItem = UITabBarItem(title: CommonString.Word.Contacts, image: iconImage, tag: 0)
        }

        vc.delegate = ObvUserActivitySingleton.shared

        return vc
    }
    

    override var delegate: UINavigationControllerDelegate? {
        get {
            super.delegate
        }
        set {
            // The ObvUserActivitySingleton properly iff it is the delegate of this UINavigationController
            guard newValue is ObvUserActivitySingleton else { assertionFailure(); return }
            super.delegate = newValue
        }
    }

    
    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        observePersistedDiscussionWasLockedNotifications()
    }
        
    // Required in order to prevent a crash under iOS 12
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }

    func observePersistedDiscussionWasLockedNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeNewLockedPersistedDiscussion(queue: OperationQueue.main) { [weak self] (previousDiscussionUriRepresentation, newLockedDiscussionId) in
            guard let _self = self else { return }
            _self.replaceDiscussionViewController(discussionToReplace: previousDiscussionUriRepresentation, newDiscussionId: newLockedDiscussionId)
        })
    }

}

// MARK: - View controller lifecycle

extension ContactsFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOS 13, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            navigationBar.standardAppearance = appearance
        }
        
    }
    
}


// MARK: - AllContactsViewControllerDelegate

extension ContactsFlowViewController: AllContactsViewControllerDelegate {

    func userDidSelectOwnedIdentity() {
        assertionFailure("This is a legacy delegate method that should never be called")
        guard let persistedObvOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: self.ownedCryptoId, within: ObvStack.shared.viewContext) else { return }
        let singleOwnedIdentityViewController = SingleIdentityViewController(persistedObvOwnedIdentity: persistedObvOwnedIdentity)
        singleOwnedIdentityViewController.delegate = self
        singleOwnedIdentityViewController.navigationItem.largeTitleDisplayMode = .never
        pushViewController(singleOwnedIdentityViewController, animated: true)
    }
    
    func userDidSelect(_ contact: PersistedObvContactIdentity, within nav: UINavigationController?) {
        if #available(iOS 13, *) {
            let vc = SingleContactIdentityViewHostingController(contact: contact, obvEngine: obvEngine)
            vc.delegate = self
            if let nav = nav {
                nav.pushViewController(vc, animated: true)
            }
        } else {
            guard let singleContactViewController = try? SingleContactViewController(persistedObvContactIdentity: contact) else { return }
            singleContactViewController.delegate = self
            singleContactViewController.navigationItem.largeTitleDisplayMode = .never
            if let nav = nav {
                nav.pushViewController(singleContactViewController, animated: true)
            }
        }
    }

    func userDidDeselect(_: PersistedObvContactIdentity) {
        // We do nothing
    }
    
    @objc
    func dismissPresentedViewController() {
        presentedViewController?.dismiss(animated: true)
    }

}


// MARK: - SingleOwnedIdentityViewControllerDelegate

// Should only be used under iOS12 or less
extension ContactsFlowViewController: SingleOwnedIdentityViewControllerDelegate {

    func editOwnedPublishedIdentityDetails() {
        
        if #available(iOS 13, *) {
            assertionFailure()
        }
        
        guard let obvOwnedIdentity = try? obvEngine.getOwnedIdentity(with: ownedCryptoId) else { return }

        assert(obvOwnedIdentity.signedUserDetails == nil)
        assert(!obvOwnedIdentity.isKeycloakManaged)

        let details = obvOwnedIdentity.publishedIdentityDetails.coreDetails
        let photoURL = obvOwnedIdentity.publishedIdentityDetails.photoURL
        let displaynameMaker = DisplaynameStruct(firstName: details.firstName,
                                                 lastName: details.lastName,
                                                 company: details.company,
                                                 position: details.position,
                                                 photoURL: photoURL)
        let displayNameChooserViewController = DisplayNameChooserViewController(displaynameMaker: displaynameMaker,
                                                                                completionHandlerOnSave: userWantsToSaveOwnedIdentityDetails,
                                                                                serverAndAPIKey: nil)
        
        let nav = ObvNavigationController(rootViewController: displayNameChooserViewController)
        displayNameChooserViewController.navigationItem.leftBarButtonItem = UIBarButtonItem.forClosing(target: self, action: #selector(dismissDisplayNameChooserViewController))
        self.present(nav, animated: true)
        
    }
    
    
    private func userWantsToSaveOwnedIdentityDetails(displaynameMaker: DisplaynameStruct) {
        defer { dismissDisplayNameChooserViewController() }
        guard displaynameMaker.isValid, let newCoreIdentityDetails = displaynameMaker.identityDetails else { return }
        
        do {
            let obvOwnedIdentity = try obvEngine.getOwnedIdentity(with: ownedCryptoId)
            let publishedDetails = obvOwnedIdentity.publishedIdentityDetails
            let newDetails = ObvIdentityDetails(coreDetails: newCoreIdentityDetails,
                                                photoURL: publishedDetails.photoURL)
            try obvEngine.updatePublishedIdentityDetailsOfOwnedIdentity(with: ownedCryptoId, with: newDetails)
        } catch {
            os_log("Could not update owned identity latest details", log: log, type: .error)
        }
        
    }
    
    @objc private func dismissDisplayNameChooserViewController() {
        presentedViewController?.view.endEditing(true)
        presentedViewController?.dismiss(animated: true)
    }
    
}
