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


protocol TransfertProtocolTargetCodeFormViewControllerDelegate: AnyObject {
    func userEnteredTransferSessionNumberOnTargetDevice(controller: TransfertProtocolTargetCodeFormViewController, transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, onIncorrectTransferSessionNumber: @escaping () -> Void, onAvailableSas: @escaping (UID, ObvOwnedIdentityTransferSas) -> Void) async throws
    func sasIsAvailable(controller: TransfertProtocolTargetCodeFormViewController, protocolInstanceUID: UID, sas: ObvOwnedIdentityTransferSas) async
}


final class TransfertProtocolTargetCodeFormViewController: UIHostingController<TransfertProtocolTargetCodeFormView>, TransfertProtocolTargetCodeFormViewActionsProtocol {
    
    private weak var delegate: TransfertProtocolTargetCodeFormViewControllerDelegate?
    
    init(delegate: TransfertProtocolTargetCodeFormViewControllerDelegate) {
        let actions = TransfertProtocolTargetCodeFormViewActions()
        let view = TransfertProtocolTargetCodeFormView(actions: actions)
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

    // TransfertProtocolTargetCodeFormViewActionsProtocol
    
    func userEnteredTransferSessionNumberOnTargetDevice(transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, onIncorrectTransferSessionNumber: @escaping () -> Void, onAvailableSas: @escaping (UID, ObvOwnedIdentityTransferSas) -> Void) async throws {
        try await delegate?.userEnteredTransferSessionNumberOnTargetDevice(
            controller: self,
            transferSessionNumber: transferSessionNumber,
            onIncorrectTransferSessionNumber: onIncorrectTransferSessionNumber,
            onAvailableSas: onAvailableSas)
    }
 
    func sasIsAvailable(protocolInstanceUID: UID, sas: ObvOwnedIdentityTransferSas) async {
        await delegate?.sasIsAvailable(controller: self, protocolInstanceUID: protocolInstanceUID, sas: sas)
    }
    
}


private final class TransfertProtocolTargetCodeFormViewActions: TransfertProtocolTargetCodeFormViewActionsProtocol {
    
    weak var delegate: TransfertProtocolTargetCodeFormViewActionsProtocol?
    
    func userEnteredTransferSessionNumberOnTargetDevice(transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, onIncorrectTransferSessionNumber: @escaping () -> Void, onAvailableSas: @escaping (UID, ObvOwnedIdentityTransferSas) -> Void) async throws {
        try await delegate?.userEnteredTransferSessionNumberOnTargetDevice(
            transferSessionNumber: transferSessionNumber,
            onIncorrectTransferSessionNumber: onIncorrectTransferSessionNumber,
            onAvailableSas: onAvailableSas)
    }
    

    func sasIsAvailable(protocolInstanceUID: UID, sas: ObvOwnedIdentityTransferSas) async {
        await delegate?.sasIsAvailable(protocolInstanceUID: protocolInstanceUID, sas: sas)
    }
    
}
