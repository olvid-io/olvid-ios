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

final class InvitationsFlowViewController: UINavigationController, ObvFlowController {
    
    private(set) var ownedCryptoId: ObvCryptoId!

    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: InvitationsFlowViewController.self))

    var observationTokens = [NSObjectProtocol]()
    
    weak var flowDelegate: ObvFlowControllerDelegate?
    
    // MARK: - Factory

    // Factory (required because creating a custom init does not work under iOS 12)
    static func create(ownedCryptoId: ObvCryptoId) -> InvitationsFlowViewController {

        let layout = UICollectionViewFlowLayout()
        let invitationsCollectionViewController = InvitationsCollectionViewController(ownedCryptoId: ownedCryptoId, collectionViewLayout: layout)
        let vc = self.init(rootViewController: invitationsCollectionViewController)

        vc.ownedCryptoId = ownedCryptoId

        invitationsCollectionViewController.delegate = vc
        
        vc.title = CommonString.Word.Invitations
        
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let image = UIImage(systemName: "tray.and.arrow.down", withConfiguration: symbolConfiguration)
        vc.tabBarItem = UITabBarItem(title: nil, image: image, tag: 0)
        
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
    }

    
    // Required in order to prevent a crash under iOS 12
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
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
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        navigationBar.standardAppearance = appearance

    }
    
}


// MARK: - InvitationsDelegate

extension InvitationsFlowViewController {

    private func respondToInvitation(dialog: ObvDialog, acceptInvite: Bool) {
        DispatchQueue(label: "RespondingToInvitationDialog").async { [weak self] in
            var localDialog = dialog
            try? localDialog.setResponseToAcceptInvite(acceptInvite: acceptInvite)
            self?.obvEngine.respondTo(localDialog)
        }
    }
    
    private func confirmDigits(dialog: ObvDialog, enteredDigits: String) {
        DispatchQueue(label: "RespondingToConfirmDigitsDialog").async { [weak self] in
            var localDialog = dialog
            guard let sas = enteredDigits.data(using: .utf8) else { return }
            try? localDialog.setResponseToSasExchange(otherSas: sas)
            self?.obvEngine.respondTo(localDialog)
        }
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
