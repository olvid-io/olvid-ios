/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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



final class NewInvitationsFlowViewController: UINavigationController, ObvFlowController {
    
    private(set) var currentOwnedCryptoId: ObvCryptoId
    let obvEngine: ObvEngine

    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: NewInvitationsFlowViewController.self))
    static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: NewInvitationsFlowViewController.self))

    static let errorDomain = ""
    
    weak var flowDelegate: ObvFlowControllerDelegate?

    var observationTokens = [NSObjectProtocol]()
    
    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine) {
        self.currentOwnedCryptoId = ownedCryptoId
        self.obvEngine = obvEngine
        let vc = AllInvitationsViewController(ownedCryptoId: ownedCryptoId)
        super.init(rootViewController: vc)
        vc.delegate = self
    }
    
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }

    
    override var delegate: UINavigationControllerDelegate? {
        get {
            super.delegate
        }
        set {
            // The ObvUserActivitySingleton property iff it is the delegate of this UINavigationController
            guard newValue is ObvUserActivitySingleton else { assertionFailure(); return }
            super.delegate = newValue
        }
    }

    
    func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        popToRootViewController(animated: false)
        guard let allInvitationsVC = viewControllers.first as? AllInvitationsViewController else { assertionFailure(); return }
        await allInvitationsVC.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
    }

}


// MARK: - Lifecycle

extension NewInvitationsFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let image = UIImage(systemName: "tray.and.arrow.down", withConfiguration: symbolConfiguration)
        tabBarItem = UITabBarItem(title: nil, image: image, tag: 0)
        
        delegate = ObvUserActivitySingleton.shared

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
