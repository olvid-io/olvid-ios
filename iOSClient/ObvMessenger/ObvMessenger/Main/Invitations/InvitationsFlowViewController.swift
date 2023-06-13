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
import ObvTypes
import ObvEngine
import ObvUICoreData

final class InvitationsFlowViewController: UINavigationController, ObvFlowController {
    
    private(set) var currentOwnedCryptoId: ObvCryptoId
    let obvEngine: ObvEngine

    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: InvitationsFlowViewController.self))

    var observationTokens = [NSObjectProtocol]()
    
    static let errorDomain = "InvitationsFlowViewController"

    weak var flowDelegate: ObvFlowControllerDelegate?
    
    // MARK: - Factory

    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine) {
        
        self.currentOwnedCryptoId = ownedCryptoId
        self.obvEngine = obvEngine

        let layout = UICollectionViewFlowLayout()
        let invitationsCollectionViewController = InvitationsCollectionViewController(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine, collectionViewLayout: layout)
        super.init(rootViewController: invitationsCollectionViewController)

        invitationsCollectionViewController.delegate = self

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

    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

}

// MARK: - Lifecycle

extension InvitationsFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = CommonString.Word.Invitations
        
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let image = UIImage(systemName: "tray.and.arrow.down", withConfiguration: symbolConfiguration)
        tabBarItem = UITabBarItem(title: nil, image: image, tag: 0)
        
        delegate = ObvUserActivitySingleton.shared

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        navigationBar.standardAppearance = appearance

    }
    
}


// MARK: - Switching current owned identity

extension InvitationsFlowViewController {
    
    @MainActor
    func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        popToRootViewController(animated: false)
        guard let invitationsCollectionViewController = viewControllers.first as? InvitationsCollectionViewController else { assertionFailure(); return }
        await invitationsCollectionViewController.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
    }
    
}


// MARK: - InvitationsDelegate

extension InvitationsFlowViewController {

    private func respondToInvitation(dialog: ObvDialog, acceptInvite: Bool) {
        var localDialog = dialog
        do {
            try localDialog.setResponseToAcceptInvite(acceptInvite: acceptInvite)
        } catch {
            assertionFailure()
            return
        }
        obvEngine.respondTo(localDialog)
    }
    
    private func confirmDigits(dialog: ObvDialog, enteredDigits: String) {
        var localDialog = dialog
        guard let sas = enteredDigits.data(using: .utf8) else { return }
        try? localDialog.setResponseToSasExchange(otherSas: sas)
        obvEngine.respondTo(localDialog)
    }
}


// MARK: - InvitationsCollectionViewControllerDelegate

extension InvitationsFlowViewController: InvitationsCollectionViewControllerDelegate {

    func performTrustEstablishmentProtocolOfRemoteIdentity(remoteCryptoId: ObvCryptoId, remoteFullDisplayName: String) {
        flowDelegate?.performTrustEstablishmentProtocolOfRemoteIdentity(remoteCryptoId: remoteCryptoId, remoteFullDisplayName: remoteFullDisplayName)
    }
    
    func rePerformTrustEstablishmentProtocolOfContactIdentity(contactCryptoId: ObvCryptoId, contactFullDisplayName: String) {
        flowDelegate?.rePerformTrustEstablishmentProtocolOfContactIdentity(contactCryptoId: contactCryptoId, contactFullDisplayName: contactFullDisplayName)
    }
}
