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
    
    let ownedCryptoId: ObvCryptoId
    let obvEngine: ObvEngine

    var observationTokens = [NSObjectProtocol]()

    // Constants
    
    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ContactsFlowViewController.self))

    // Delegate
    
    weak var flowDelegate: ObvFlowControllerDelegate?

    // MARK: - Factory

    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine) {
        
        self.ownedCryptoId = ownedCryptoId
        self.obvEngine = obvEngine
        
        let allContactsVC = AllContactsViewController(ownedCryptoId: ownedCryptoId, oneToOneStatus: .oneToOne, showExplanation: true)
        super.init(rootViewController: allContactsVC)
        
        allContactsVC.delegate = self

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

    required init?(coder aDecoder: NSCoder) { fatalError("die") }

}

// MARK: - View controller lifecycle

extension ContactsFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = CommonString.Word.Contacts
        
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let image = UIImage(systemName: "person", withConfiguration: symbolConfiguration)
        tabBarItem = UITabBarItem(title: nil, image: image, tag: 0)

        delegate = ObvUserActivitySingleton.shared

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        navigationBar.standardAppearance = appearance
        
        observePersistedGroupV2WasDeletedNotifications()

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
