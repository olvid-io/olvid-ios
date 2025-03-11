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


protocol TransfertProtocolSourceCodeDisplayerViewControllerDelegate: AnyObject {
    
    typealias BlockCancellingOwnedIdentityTransferProtocol = () -> Void
    typealias TransferSessionNumber = Int
    
    /// Called as soon as the view appears.
    /// - Parameters:
    ///   - controller: The `TransfertProtocolSourceCodeDisplayerViewController` instance calling this method.
    ///   - ownedCryptoId: The `ObvCryptoId` of the owned identity.
    ///   - onAvailableSessionNumber: A block called as soon as the session number is available.
    func userWantsToInitiateOwnedIdentityTransferProtocolOnSourceDevice(controller: TransfertProtocolSourceCodeDisplayerViewController, ownedCryptoId: ObvCryptoId, onAvailableSessionNumber: @MainActor @escaping (ObvOwnedIdentityTransferSessionNumber) -> Void, onAvailableSASExpectedOnInput: @MainActor @escaping (ObvOwnedIdentityTransferSas, String, UID) -> Void) async throws
    
    func userDidCancelOwnedIdentityTransferProtocol(controller: TransfertProtocolSourceCodeDisplayerViewController) async
    
    
    /// Called when the engine sent us back the SAS we expect the user to enter on this source device.
    /// - Parameters:
    ///   - controller: The `TransfertProtocolSourceCodeDisplayerViewController` instance calling this method.
    ///   - sasExpectedOnInput: The SAS we expect the user to enter on the next screen of the onboarding
    func sasExpectedOnInputIsAvailable(controller: TransfertProtocolSourceCodeDisplayerViewController, sasExpectedOnInput: ObvOwnedIdentityTransferSas, targetDeviceName: String, ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, protocolInstanceUID: UID) async

}



final class TransfertProtocolSourceCodeDisplayerViewController: UIHostingController<TransfertProtocolSourceCodeDisplayerView> {
    
    private weak var delegate: TransfertProtocolSourceCodeDisplayerViewControllerDelegate?
    
    init(model: TransfertProtocolSourceCodeDisplayerView.Model, delegate: TransfertProtocolSourceCodeDisplayerViewControllerDelegate) {
        let actions = TransfertProtocolSourceCodeDisplayerViewActions()
        let view = TransfertProtocolSourceCodeDisplayerView(
            model: model,
            actions: actions)
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
    
}


extension TransfertProtocolSourceCodeDisplayerViewController: TransfertProtocolSourceCodeDisplayerViewActionsProtocol {

    func userWantsToInitiateOwnedIdentityTransferProtocolOnSourceDevice(ownedCryptoId: ObvTypes.ObvCryptoId, onAvailableSessionNumber: @escaping @MainActor (ObvTypes.ObvOwnedIdentityTransferSessionNumber) -> Void, onAvailableSASExpectedOnInput: @escaping @MainActor (ObvTypes.ObvOwnedIdentityTransferSas, String, ObvCrypto.UID) -> Void) async throws {
        guard let delegate else { throw ObvError.theDelegateIsNil }
        return try await delegate.userWantsToInitiateOwnedIdentityTransferProtocolOnSourceDevice(
            controller: self,
            ownedCryptoId: ownedCryptoId,
            onAvailableSessionNumber: onAvailableSessionNumber,
            onAvailableSASExpectedOnInput: onAvailableSASExpectedOnInput)
    }
    
    
    func sasExpectedOnInputIsAvailable(_ sasExpectedOnInput: ObvOwnedIdentityTransferSas, targetDeviceName: String, ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, protocolInstanceUID: UID) async {
        await delegate?.sasExpectedOnInputIsAvailable(
            controller: self,
            sasExpectedOnInput: sasExpectedOnInput,
            targetDeviceName: targetDeviceName,
            ownedCryptoId: ownedCryptoId,
            ownedDetails: ownedDetails,
            protocolInstanceUID: protocolInstanceUID)
    }

    enum ObvError: Error {
        case theDelegateIsNil
    }
    
}


// MARK: - TransfertProtocolSourceCodeDisplayerViewActions

private final class TransfertProtocolSourceCodeDisplayerViewActions: TransfertProtocolSourceCodeDisplayerViewActionsProtocol {
        
    weak var delegate: TransfertProtocolSourceCodeDisplayerViewActionsProtocol?
    
    func userWantsToInitiateOwnedIdentityTransferProtocolOnSourceDevice(ownedCryptoId: ObvTypes.ObvCryptoId, onAvailableSessionNumber: @escaping @MainActor (ObvTypes.ObvOwnedIdentityTransferSessionNumber) -> Void, onAvailableSASExpectedOnInput: @escaping @MainActor (ObvTypes.ObvOwnedIdentityTransferSas, String, ObvCrypto.UID) -> Void) async throws {
        guard let delegate else { throw ObvError.theDelegateIsNil }
        try await delegate.userWantsToInitiateOwnedIdentityTransferProtocolOnSourceDevice(
            ownedCryptoId: ownedCryptoId,
            onAvailableSessionNumber: onAvailableSessionNumber,
            onAvailableSASExpectedOnInput: onAvailableSASExpectedOnInput)
    }
    
    
    func sasExpectedOnInputIsAvailable(_ sasExpectedOnInput: ObvOwnedIdentityTransferSas, targetDeviceName: String, ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, protocolInstanceUID: UID) async {
        await delegate?.sasExpectedOnInputIsAvailable(
            sasExpectedOnInput,
            targetDeviceName: targetDeviceName,
            ownedCryptoId: ownedCryptoId,
            ownedDetails: ownedDetails,
            protocolInstanceUID: protocolInstanceUID)
    }


    enum ObvError: Error {
        case theDelegateIsNil
    }

}
