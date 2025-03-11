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

import SwiftUI
import UIKit
import AppAuth
import ObvCrypto
import ObvTypes
import ObvJWS


protocol TransferProtocolTargetShowSasViewControllerDelegate: AnyObject {
    
    func targetDeviceIsShowingSasAndExpectingEndOfProtocol(controller: TransferProtocolTargetShowSasViewController, protocolInstanceUID: UID, onSyncSnapshotReception: @escaping () -> Void, onSuccessfulTransfer: @escaping (ObvCryptoId, Error?) -> Void, onKeycloakAuthenticationNeeded: @escaping (ObvCryptoId, ObvKeycloakConfiguration, ObvKeycloakTransferProofElements) -> Void) async
    func successfulTransferWasPerformedOnThisTargetDevice(controller: TransferProtocolTargetShowSasViewController, transferredOwnedCryptoId: ObvCryptoId, postTransferError: Error?) async
    func userDidCancelOwnedIdentityTransferProtocol(controller: TransferProtocolTargetShowSasViewController) async
    
    // The following delegate methods are required in case the transfer is restricted

    func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(controller: TransferProtocolTargetShowSasViewController, keycloakConfiguration: ObvKeycloakConfiguration, transferProofElements: ObvKeycloakTransferProofElements) async throws -> ObvKeycloakTransferProofAndAuthState
    func userProvidesProofOfAuthenticationOnKeycloakServer(controller: TransferProtocolTargetShowSasViewController, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID, proof: ObvKeycloakTransferProofAndAuthState) async throws

}


final class TransferProtocolTargetShowSasViewController: UIHostingController<TransferProtocolTargetShowSasView>, TransferProtocolTargetShowSasViewActionsProtocol {
    
    private weak var delegate: TransferProtocolTargetShowSasViewControllerDelegate?
    
    init(model: TransferProtocolTargetShowSasView.Model, delegate: TransferProtocolTargetShowSasViewControllerDelegate) {
        let actions = TransferProtocolTargetShowSasViewActions()
        let view = TransferProtocolTargetShowSasView(actions: actions, model: model)
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
        // Add a cancel button
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

    
    // TransferProtocolTargetShowSasViewActionsProtocol
    
    func targetDeviceIsShowingSasAndExpectingEndOfProtocol(protocolInstanceUID: UID, onSyncSnapshotReception: @escaping () -> Void, onSuccessfulTransfer: @escaping (ObvCryptoId, Error?) -> Void, onKeycloakAuthenticationNeeded: @escaping (ObvCryptoId, ObvKeycloakConfiguration, ObvKeycloakTransferProofElements) -> Void) async {
        await delegate?.targetDeviceIsShowingSasAndExpectingEndOfProtocol(
            controller: self,
            protocolInstanceUID: protocolInstanceUID,
            onSyncSnapshotReception: onSyncSnapshotReception,
            onSuccessfulTransfer: onSuccessfulTransfer,
            onKeycloakAuthenticationNeeded: onKeycloakAuthenticationNeeded)
    }
    
    
    func successfulTransferWasPerformedOnThisTargetDevice(transferredOwnedCryptoId: ObvCryptoId, postTransferError: Error?) async {
        await delegate?.successfulTransferWasPerformedOnThisTargetDevice(
            controller: self,
            transferredOwnedCryptoId: transferredOwnedCryptoId,
            postTransferError: postTransferError)
    }
    
    
    func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(keycloakConfiguration: ObvKeycloakConfiguration, transferProofElements: ObvKeycloakTransferProofElements) async throws -> ObvKeycloakTransferProofAndAuthState {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(controller: self, keycloakConfiguration: keycloakConfiguration, transferProofElements: transferProofElements)
    }
    
    
    func userProvidesProofOfAuthenticationOnKeycloakServer(ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID, proof: ObvTypes.ObvKeycloakTransferProofAndAuthState) async throws {
        guard let delegate else { assertionFailure(); return }
        try await delegate.userProvidesProofOfAuthenticationOnKeycloakServer(controller: self, ownedCryptoId: ownedCryptoId, protocolInstanceUID: protocolInstanceUID, proof: proof)
    }

    // Errors
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}


fileprivate final class TransferProtocolTargetShowSasViewActions: TransferProtocolTargetShowSasViewActionsProtocol {
    
    weak var delegate: TransferProtocolTargetShowSasViewActionsProtocol?
    
    func targetDeviceIsShowingSasAndExpectingEndOfProtocol(protocolInstanceUID: UID, onSyncSnapshotReception: @escaping () -> Void, onSuccessfulTransfer: @escaping (ObvCryptoId, Error?) -> Void, onKeycloakAuthenticationNeeded: @escaping (ObvCryptoId, ObvKeycloakConfiguration, ObvKeycloakTransferProofElements) -> Void) async {
        await delegate?.targetDeviceIsShowingSasAndExpectingEndOfProtocol(
            protocolInstanceUID: protocolInstanceUID,
            onSyncSnapshotReception: onSyncSnapshotReception,
            onSuccessfulTransfer: onSuccessfulTransfer,
            onKeycloakAuthenticationNeeded: onKeycloakAuthenticationNeeded)
    }
    
    
    func successfulTransferWasPerformedOnThisTargetDevice(transferredOwnedCryptoId: ObvCryptoId, postTransferError: Error?) async {
        await delegate?.successfulTransferWasPerformedOnThisTargetDevice(
            transferredOwnedCryptoId: transferredOwnedCryptoId,
            postTransferError: postTransferError)
    }
    
    
    func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(keycloakConfiguration: ObvKeycloakConfiguration, transferProofElements: ObvKeycloakTransferProofElements) async throws -> ObvKeycloakTransferProofAndAuthState {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(keycloakConfiguration: keycloakConfiguration, transferProofElements: transferProofElements)
    }
    
    
    func userProvidesProofOfAuthenticationOnKeycloakServer(ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID, proof: ObvKeycloakTransferProofAndAuthState) async throws {
        guard let delegate else { assertionFailure(); return }
        try await delegate.userProvidesProofOfAuthenticationOnKeycloakServer(ownedCryptoId: ownedCryptoId, protocolInstanceUID: protocolInstanceUID, proof: proof)
    }
    

    // Errors
    
    enum ObvError: Error {
        case delegateIsNil
    }

}
