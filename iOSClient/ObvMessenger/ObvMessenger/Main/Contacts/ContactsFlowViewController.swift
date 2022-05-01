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
import os.log
import ObvEngine
import ObvTypes


final class ContactsFlowViewController: UINavigationController, ObvFlowController {
    
    // Variables
    
    private(set) var ownedCryptoId: ObvCryptoId!

    private var observationTokens = [NSObjectProtocol]()

    // Constants
    
    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ContactsFlowViewController.self))

    // Delegate
    
    weak var flowDelegate: ObvFlowControllerDelegate?

    // MARK: - Factory

    // Factory (required because creating a custom init does not work under iOS 12)
    static func create(ownedCryptoId: ObvCryptoId) -> ContactsFlowViewController {

        let allContactsVC = AllContactsViewController(ownedCryptoId: ownedCryptoId, oneToOneStatus: .oneToOne, showExplanation: true)
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
        observationTokens.append(ObvMessengerCoreDataNotification.observeNewLockedPersistedDiscussion(queue: OperationQueue.main) { [weak self] (previousDiscussionUriRepresentation, newLockedDiscussionId) in
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

    func userDidSelect(_ contact: PersistedObvContactIdentity, within nav: UINavigationController?) {
        let vc = SingleContactIdentityViewHostingController(contact: contact, obvEngine: obvEngine)
        vc.delegate = self
        if let nav = nav {
            nav.pushViewController(vc, animated: true)
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
