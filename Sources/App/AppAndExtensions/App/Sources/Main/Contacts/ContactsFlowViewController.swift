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

import UIKit
import os.log
import ObvEngine
import ObvTypes
import ObvUICoreData
import ObvAppCoreConstants


final class ContactsFlowViewController: UINavigationController, ObvFlowController {

    static let errorDomain = "ContactsFlowViewController"
        
    // Variables
    
    private(set) var currentOwnedCryptoId: ObvCryptoId
    let delegatesStack = ObvFlowControllerDelegatesStack()
    let obvEngine: ObvEngine
    var floatingButton: UIButton? // Used on iOS 18+ only, set at the ObvFlowController level
    private var floatingButtonAnimator: FloatingButtonAnimator?

    var observationTokens = [NSObjectProtocol]()

    // Constants
    
    let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ContactsFlowViewController.self))

    // Delegate
    
    weak var flowDelegate: ObvFlowControllerDelegate?

    // MARK: - Factory

    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine) {
        
        self.currentOwnedCryptoId = ownedCryptoId
        self.obvEngine = obvEngine
        
        let allContactsVC = AllContactsViewController(ownedCryptoId: ownedCryptoId, oneToOneStatus: .oneToOne, showExplanation: true, textAboveContactList: nil)
        super.init(rootViewController: allContactsVC)
        
        allContactsVC.delegate = self

        self.delegate = delegatesStack

    }
    
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    

    override var delegate: UINavigationControllerDelegate? {
        get {
            super.delegate
        }
        set {
            guard newValue is ObvFlowControllerDelegatesStack else { assertionFailure(); return }
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
        
        if #available(iOS 18, *) {
            // The tabbar is configured with iOS 18 APIs, we don't need to specify a tabBarItem
        } else {
            let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
            let image = UIImage(systemName: "person", withConfiguration: symbolConfiguration)
            tabBarItem = UITabBarItem(title: nil, image: image, tag: 0)
        }

        delegatesStack.addDelegate(OlvidUserActivitySingleton.shared)

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        navigationBar.standardAppearance = appearance
        
        observeNotificationsImpactingTheNavigationStack()

        // This is required to activate the interactive pop gesture recognizer. Activating this interactive gesture also requires
        // to override gestureRecognizerShouldBegin(_:).
        // See ``https://stackoverflow.com/questions/18946302/uinavigationcontroller-interactive-pop-gesture-not-working``.
        if #available(iOS 18, *) {
            interactivePopGestureRecognizer?.delegate = self
        }

    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if #available(iOS 18, *) {
            addFloatingButtonIfRequired()
            let floatingButtonAnimator = FloatingButtonAnimator(floatingButton: floatingButton)
            self.delegatesStack.addDelegate(floatingButtonAnimator)
            self.floatingButtonAnimator = floatingButtonAnimator
        }
    }

}


// MARK: - UIGestureRecognizerDelegate

extension ContactsFlowViewController: UIGestureRecognizerDelegate {
    
    /// This is only used under iOS18+, in order to be the delegate of the `interactivePopGestureRecognizer`, allowing to activate the interactive pop gesture recognizer.
    /// See ``https://stackoverflow.com/questions/18946302/uinavigationcontroller-interactive-pop-gesture-not-working``.
    @objc func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
    
}


// MARK: - Switching current owned identity

extension ContactsFlowViewController {
    
    @MainActor
    func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        popToRootViewController(animated: false)
        self.currentOwnedCryptoId = newOwnedCryptoId
        guard let allContactsVC = viewControllers.first as? AllContactsViewController else { assertionFailure(); return }
        await allContactsVC.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
    }
    
}


// MARK: - AllContactsViewControllerDelegate

extension ContactsFlowViewController: AllContactsViewControllerDelegate {

    func userDidSelect(_ contact: PersistedObvContactIdentity, within nav: UINavigationController?) {
        let vc: SingleContactIdentityViewHostingController
        do {
            vc = try SingleContactIdentityViewHostingController(contact: contact, obvEngine: obvEngine)
        } catch {
            assertionFailure(error.localizedDescription)
            return
        }
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
