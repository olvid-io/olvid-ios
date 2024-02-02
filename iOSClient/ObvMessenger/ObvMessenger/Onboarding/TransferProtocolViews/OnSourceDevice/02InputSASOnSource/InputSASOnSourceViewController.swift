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
import Contacts


protocol InputSASOnSourceViewControllerDelegate: AnyObject {
    func userEnteredValidSASOnSourceDevice(controller: InputSASOnSourceViewController, enteredSAS: ObvOwnedIdentityTransferSas, ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, protocolInstanceUID: UID, targetDeviceName: String) async throws
    func userDidCancelOwnedIdentityTransferProtocol(controller: InputSASOnSourceViewController) async
}


final class InputSASOnSourceViewController: UIHostingController<InputSASOnSourceView>, InputSASOnSourceViewActionsProtocol {
    
    private weak var delegate: InputSASOnSourceViewControllerDelegate?
    
    init(model: InputSASOnSourceView.Model, delegate: InputSASOnSourceViewControllerDelegate) {
        let actions = InputSASOnSourceViewActions()
        let view = InputSASOnSourceView(actions: actions, model: model)
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
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonTapped))
    }

    
    @objc
    private func cancelButtonTapped() {
        Task { [weak self] in
            guard let self else { return }
            await delegate?.userDidCancelOwnedIdentityTransferProtocol(controller: self)
        }
    }

    // InputSASOnSourceViewActionsProtocol
    
    func userEnteredValidSASOnSourceDevice(enteredSAS: ObvOwnedIdentityTransferSas, ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, protocolInstanceUID: UID, targetDeviceName: String) async throws {
        try await delegate?.userEnteredValidSASOnSourceDevice(
            controller: self,
            enteredSAS: enteredSAS,
            ownedCryptoId: ownedCryptoId,
            ownedDetails: ownedDetails,
            protocolInstanceUID: protocolInstanceUID,
            targetDeviceName: targetDeviceName)
    }
    
}


private final class InputSASOnSourceViewActions: InputSASOnSourceViewActionsProtocol {
    
    weak var delegate: InputSASOnSourceViewActionsProtocol?
    
    func userEnteredValidSASOnSourceDevice(enteredSAS: ObvOwnedIdentityTransferSas, ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, protocolInstanceUID: UID, targetDeviceName: String) async throws {
        try await delegate?.userEnteredValidSASOnSourceDevice(
            enteredSAS: enteredSAS,
            ownedCryptoId: ownedCryptoId,
            ownedDetails: ownedDetails,
            protocolInstanceUID: protocolInstanceUID,
            targetDeviceName: targetDeviceName)
    }

}
