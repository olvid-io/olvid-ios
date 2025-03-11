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
import ObvTypes
import ObvEngine
import ObvUICoreData
import ObvAppCoreConstants



final class NewInvitationsFlowViewController: UINavigationController, ObvFlowController {
    
    private(set) var currentOwnedCryptoId: ObvCryptoId
    let delegatesStack = ObvFlowControllerDelegatesStack()
    let obvEngine: ObvEngine
    var floatingButton: UIButton? // Used on iOS 18+ only, set at the ObvFlowController level
    private var floatingButtonAnimator: FloatingButtonAnimator?

    let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: NewInvitationsFlowViewController.self))
    static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: NewInvitationsFlowViewController.self))

    static let errorDomain = ""
    
    weak var flowDelegate: ObvFlowControllerDelegate?

    var observationTokens = [NSObjectProtocol]()
    
    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine) {
        self.currentOwnedCryptoId = ownedCryptoId
        self.obvEngine = obvEngine
        let vc = AllInvitationsViewController(ownedCryptoId: ownedCryptoId)
        super.init(rootViewController: vc)
        vc.delegate = self
        self.delegate = delegatesStack
    }
    
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }

    
    override var delegate: UINavigationControllerDelegate? {
        get {
            super.delegate
        }
        set {
            guard newValue is ObvFlowControllerDelegatesStack else { assertionFailure(); return }
            super.delegate = newValue
        }
    }

    
    func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        popToRootViewController(animated: false)
        self.currentOwnedCryptoId = newOwnedCryptoId
        guard let allInvitationsVC = viewControllers.first as? AllInvitationsViewController else { assertionFailure(); return }
        await allInvitationsVC.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
    }

}


// MARK: - Lifecycle

extension NewInvitationsFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOS 18, *) {
            // The tabbar is configured with iOS 18 APIs, we don't need to specify a tabBarItem
        } else {
            let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
            let image = UIImage(systemName: "tray.and.arrow.down", withConfiguration: symbolConfiguration)
            tabBarItem = UITabBarItem(title: nil, image: image, tag: 0)
        }
        
        delegatesStack.addDelegate(OlvidUserActivitySingleton.shared)

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

extension NewInvitationsFlowViewController: UIGestureRecognizerDelegate {
    
    /// This is only used under iOS18+, in order to be the delegate of the `interactivePopGestureRecognizer`, allowing to activate the interactive pop gesture recognizer.
    /// See ``https://stackoverflow.com/questions/18946302/uinavigationcontroller-interactive-pop-gesture-not-working``.
    @objc func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
    
}


// MARK: - AllInvitationsViewControllerDelegate

extension NewInvitationsFlowViewController: AllInvitationsViewControllerDelegate {
    
    func userWantsToRespondToDialog(controller: AllInvitationsViewController, obvDialog: ObvDialog) async throws {
        try await obvEngine.respondTo(obvDialog)
    }

    func userWantsToAbortProtocol(controller: AllInvitationsViewController, obvDialog: ObvTypes.ObvDialog) async throws {
        try obvEngine.abortProtocol(associatedTo: obvDialog)
    }

    func userWantsToDeleteDialog(controller: AllInvitationsViewController, obvDialog: ObvDialog) async throws {
        try obvEngine.deleteDialog(with: obvDialog.uuid)
    }
    
    @MainActor
    func userWantsToDiscussWithContact(controller: AllInvitationsViewController, ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) async throws {
        guard let contact = try? PersistedObvContactIdentity.get(contactCryptoId: contactCryptoId,
                                                                 ownedIdentityCryptoId: ownedCryptoId,
                                                                 whereOneToOneStatusIs: .oneToOne,
                                                                 within: ObvStack.shared.viewContext),
              let discussionId = contact.oneToOneDiscussion?.discussionPermanentID else {
            return
        }
        let deepLink = ObvDeepLink.singleDiscussion(ownedCryptoId: ownedCryptoId, objectPermanentID: discussionId)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()
    }

}
