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
import ObvTypes
import ObvEngine
import ObvUICoreData
import ObvAppCoreConstants
import ObvUIGroupV1
import ObvUIGroupV2
import ObvSharedDataSources
import ObvAppNavigation


final class NewInvitationsFlowViewController: ObvFlowController {
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "NewInvitationsFlowViewController")
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: NewInvitationsFlowViewController.self))

    private var observationTokens = [NSObjectProtocol]()
    
    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine, dataSources: ObvDataSources) {
        
        super.init(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine, dataSources: dataSources, doAddFloatingButton: true)

        let vc = AllInvitationsViewController(ownedCryptoId: ownedCryptoId,
                                              avatarViewDataSource: dataSources.avatarViewDataSource,
                                              ownedIdentityChooserViewDataSource: dataSources.ownedIdentityChooserViewDataSource)
        vc.delegate = self
        vc.unlockingHiddenProfileDelegate = self

        self.setViewControllers([vc], animated: false)
        
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("die") }

    
    override func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) {
        super.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
        guard let allInvitationsVC = viewControllers.first as? AllInvitationsViewController else { assertionFailure(); return }
        allInvitationsVC.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
    }

}


// MARK: - Lifecycle

extension NewInvitationsFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOS 18, *) {
            // The tabbar is configured with iOS 18 APIs, we don't need to specify a tabBarItem
        } else {
            let image = UIImage(systemIcon: .trayAndArrowDown)
            tabBarItem = UITabBarItem(title: String(localized: "Invitations"), image: image, tag: 3)
        }
        
        // This is required to activate the interactive pop gesture recognizer. Activating this interactive gesture also requires
        // to override gestureRecognizerShouldBegin(_:).
        // See ``https://stackoverflow.com/questions/18946302/uinavigationcontroller-interactive-pop-gesture-not-working``.
        if #available(iOS 17, *) {
            interactivePopGestureRecognizer?.delegate = self
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
              let discussionIdentifier = contact.oneToOneDiscussion?.discussionIdentifier else {
            return
        }
        let deepLink = ObvDeepLink.singleDiscussion(discussionIdentifier: discussionIdentifier)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()
    }

}
