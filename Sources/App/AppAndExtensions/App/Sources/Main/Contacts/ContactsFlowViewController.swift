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

import UIKit
import OSLog
import ObvEngine
import ObvTypes
import ObvUICoreData
import ObvAppCoreConstants
import ObvUIGroupV1
import ObvUIGroupV2
import ObvSharedDataSources
import ObvSingleContact
import ObvAppNavigation


final class ContactsFlowViewController: ObvFlowController {
        
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ContactsFlowViewController")
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ContactsFlowViewController.self))

    private var observationTokens = [NSObjectProtocol]()

    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine, dataSources: ObvDataSources) {
        
        super.init(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine, dataSources: dataSources, doAddFloatingButton: true)

        let allContactsVC = AllContactsViewController(ownedCryptoId: ownedCryptoId,
                                                      oneToOneStatus: .oneToOne,
                                                      showExplanation: true,
                                                      textAboveContactList: nil,
                                                      avatarViewDataSource: dataSources.avatarViewDataSource,
                                                      ownedIdentityChooserViewDataSource: dataSources.ownedIdentityChooserViewDataSource)
        
        allContactsVC.delegate = self
        allContactsVC.unlockingHiddenProfileDelegate = self
        
        self.setViewControllers([allContactsVC], animated: false)

    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }
    
    // MARK: - Switching current owned identity

    override func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) {
        popToRootViewController(animated: false)
        self.currentOwnedCryptoId = newOwnedCryptoId
        guard let allContactsVC = viewControllers.first as? AllContactsViewController else { assertionFailure(); return }
        allContactsVC.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
    }
        
}


// MARK: - View controller lifecycle

extension ContactsFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = CommonString.Word.Contacts
        
        if #available(iOS 18, *) {
            // The tabbar is configured with iOS 18 APIs, we don't need to specify a tabBarItem
        } else {
            let image = UIImage(systemIcon: .person)
            tabBarItem = UITabBarItem(title: String(localized: "Contacts"), image: image, tag: 1)
        }

        if #available(iOS 26, *) {
            // We don't change the appearance under iOS 26
        } else {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            navigationBar.standardAppearance = appearance
        }
        
        //observeNotificationsImpactingTheNavigationStack()

        // This is required to activate the interactive pop gesture recognizer. Activating this interactive gesture also requires
        // to override gestureRecognizerShouldBegin(_:).
        // See ``https://stackoverflow.com/questions/18946302/uinavigationcontroller-interactive-pop-gesture-not-working``.
        if #available(iOS 17, *) {
            interactivePopGestureRecognizer?.delegate = self
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

// MARK: - AllContactsViewControllerDelegate

extension ContactsFlowViewController: AllContactsViewControllerDelegate {

    func userDidSelectContact(_ vc: AllContactsViewController, withContactIdentifier contactIdentifier: ObvContactIdentifier, within navigationController: UINavigationController?) {
        assert(navigationController == nil || navigationController == self || self.presentedViewController == navigationController, "We simplified the underlying API. The navigationController is now discarded.")
        self.userWantsToNavigateToSingleContactView(contactIdentifier: contactIdentifier)
    }

    func userDidDeselectContact(_ vc: AllContactsViewController, withContactIdentifier contactIdentifier: ObvContactIdentifier) {
        // We do nothing
    }
    
    @objc
    func dismissPresentedViewController() {
        presentedViewController?.dismiss(animated: true)
    }

}
