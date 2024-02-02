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
import ObvUICoreData
import ObvTypes


protocol AllInvitationsViewControllerDelegate: AnyObject {
    func userWantsToRespondToDialog(controller: AllInvitationsViewController, obvDialog: ObvDialog) async throws
    func userWantsToAbortProtocol(controller: AllInvitationsViewController, obvDialog: ObvTypes.ObvDialog) async throws
    func userWantsToDeleteDialog(controller: AllInvitationsViewController, obvDialog: ObvTypes.ObvDialog) async throws
    func userWantsToDiscussWithContact(controller: AllInvitationsViewController, ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) async throws
}


final class AllInvitationsViewController: ShowOwnedIdentityButtonUIViewController, ViewControllerWithEllipsisCircleRightBarButtonItem {
    
    weak var delegate: AllInvitationsViewControllerDelegate?
    private var viewDidLoadWasCalled = false

    init(ownedCryptoId: ObvCryptoId) {
        super.init(ownedCryptoId: ownedCryptoId, logCategory: "AllInvitationsViewController")
        self.setTitle(CommonString.Word.Invitations)
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        viewDidLoadWasCalled = true
        // Set navigationItem.title instead of title: this prevents showing a title on the tabbar button item
        navigationItem.title = CommonString.Word.Invitations
        navigationItem.rightBarButtonItem = getConfiguredEllipsisCircleRightBarButtonItem()
        addAndConfigureAllInvitationsHostingController()
        definesPresentationContext = true
    }
    
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        ObvMessengerInternalNotification.allPersistedInvitationCanBeMarkedAsOld(ownedCryptoId: currentOwnedCryptoId)
            .postOnDispatchQueue()
    }
    
    // MARK: - Switching current owned identity

    @MainActor
    override func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        await super.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
        guard viewDidLoadWasCalled else { return }
        for multipleContactsHostingViewController in children.compactMap({ $0 as? AllInvitationsHostingController }) {
            multipleContactsHostingViewController.view.removeFromSuperview()
            multipleContactsHostingViewController.willMove(toParent: nil)
            multipleContactsHostingViewController.removeFromParent()
            multipleContactsHostingViewController.didMove(toParent: nil)
        }
        addAndConfigureAllInvitationsHostingController()
    }

    
    /// Called the first time the view is loaded, and each time the user switches her owned identity.
    private func addAndConfigureAllInvitationsHostingController() {
        if let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: currentOwnedCryptoId, within: ObvStack.shared.viewContext) {
            let vc = AllInvitationsHostingController(ownedIdentity: ownedIdentity, delegate: self)
            vc.willMove(toParent: self)
            self.addChild(vc)
            vc.didMove(toParent: self)
            vc.view.translatesAutoresizingMaskIntoConstraints = false
            self.view.insertSubview(vc.view, at: 0)
            self.view.pinAllSidesToSides(of: vc.view)
        }
    }
    
}


// MARK: - AllInvitationsHostingControllerDelegate

extension AllInvitationsViewController: AllInvitationsHostingControllerDelegate {
    
    func userWantsToRespondToDialog(controller: AllInvitationsHostingController, obvDialog: ObvDialog) async throws {
        try await delegate?.userWantsToRespondToDialog(controller: self, obvDialog: obvDialog)
    }
    
    
    func userWantsToAbortProtocol(controller: AllInvitationsHostingController, obvDialog: ObvDialog) async throws {
        try await delegate?.userWantsToAbortProtocol(controller: self, obvDialog: obvDialog)
    }
    
    
    func userWantsToDeleteDialog(controller: AllInvitationsHostingController, obvDialog: ObvDialog) async throws {
        try await delegate?.userWantsToDeleteDialog(controller: self, obvDialog: obvDialog)
    }
    
    func userWantsToDiscussWithContact(controller: AllInvitationsHostingController, ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) async throws {
        try await delegate?.userWantsToDiscussWithContact(controller: self, ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
    }
}
