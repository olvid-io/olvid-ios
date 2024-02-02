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
import SwiftUI
import ObvTypes
import ObvCrypto


protocol OwnedIdentityTransferSummaryViewControllerDelegate: AnyObject {
    
    func userDidCancelOwnedIdentityTransferProtocol(controller: OwnedIdentityTransferSummaryViewController) async
    func userWishesToFinalizeOwnedIdentityTransferFromSourceDevice(controller: OwnedIdentityTransferSummaryViewController, enteredSAS: ObvOwnedIdentityTransferSas, deviceToKeepActive: UID?, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID) async throws
    
}


final class OwnedIdentityTransferSummaryViewController: UIHostingController<OwnedIdentityTransferSummaryView>, OwnedIdentityTransferSummaryViewActionsProtocol {
    
    private var delegate: OwnedIdentityTransferSummaryViewControllerDelegate?
    
    init(model: OwnedIdentityTransferSummaryView.Model, delegate: OwnedIdentityTransferSummaryViewControllerDelegate) {
        let actions = OwnedIdentityTransferSummaryViewActions()
        let view = OwnedIdentityTransferSummaryView(actions: actions, model: model)
        super.init(rootView: view)
        self.delegate = delegate
        actions.delegate = self
    }
    
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        configureNavigation(animated: false)
    }

    
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        configureNavigation(animated: animated)
    }


    private func configureNavigation(animated: Bool) {
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    
    // OwnedIdentityTransferSummaryViewActionsProtocol
    
    func userDidCancelOwnedIdentityTransferProtocol() async {
        await delegate?.userDidCancelOwnedIdentityTransferProtocol(controller: self)
    }
    
    
    func userWishesToFinalizeOwnedIdentityTransferFromSourceDevice(enteredSAS: ObvOwnedIdentityTransferSas, deviceToKeepActive: UID?, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID) async throws {
        try await delegate?.userWishesToFinalizeOwnedIdentityTransferFromSourceDevice(
            controller: self,
            enteredSAS: enteredSAS,
            deviceToKeepActive: deviceToKeepActive,
            ownedCryptoId: ownedCryptoId,
            protocolInstanceUID: protocolInstanceUID)
    }

    
}


private final class OwnedIdentityTransferSummaryViewActions: OwnedIdentityTransferSummaryViewActionsProtocol {
    
    weak var delegate: OwnedIdentityTransferSummaryViewActionsProtocol?
    
    func userDidCancelOwnedIdentityTransferProtocol() async {
        await delegate?.userDidCancelOwnedIdentityTransferProtocol()
    }
    
    
    func userWishesToFinalizeOwnedIdentityTransferFromSourceDevice(enteredSAS: ObvOwnedIdentityTransferSas, deviceToKeepActive: UID?, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID) async throws {
        try await delegate?.userWishesToFinalizeOwnedIdentityTransferFromSourceDevice(
            enteredSAS: enteredSAS,
            deviceToKeepActive: deviceToKeepActive,
            ownedCryptoId: ownedCryptoId,
            protocolInstanceUID: protocolInstanceUID)
    }

}
