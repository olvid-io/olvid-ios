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

import SwiftUI
import AppAuth
import ObvTypes
import ObvCrypto
import ObvJWS


protocol TransferProtocolTargetShowSasViewActionsProtocol: AnyObject {
    
    func targetDeviceIsShowingSasAndExpectingEndOfProtocol(protocolInstanceUID: UID, onSyncSnapshotReception: @escaping () -> Void, onSuccessfulTransfer: @escaping (ObvCryptoId, Error?) -> Void, onKeycloakAuthenticationNeeded: @escaping (ObvCryptoId, ObvKeycloakConfiguration, ObvKeycloakTransferProofElements) -> Void) async
    func successfulTransferWasPerformedOnThisTargetDevice(transferredOwnedCryptoId: ObvCryptoId, postTransferError: Error?) async
    
    // The following delegate methods are required in case the transfer is restricted
    
    func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(keycloakConfiguration: ObvKeycloakConfiguration, transferProofElements: ObvKeycloakTransferProofElements) async throws -> ObvKeycloakTransferProofAndAuthState
    func userProvidesProofOfAuthenticationOnKeycloakServer(ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID, proof: ObvKeycloakTransferProofAndAuthState) async throws
    
}


struct TransferProtocolTargetShowSasView: View {
    
    let actions: TransferProtocolTargetShowSasViewActionsProtocol
    let model: Model
    
    @State private var isSpinnerShown = false
    
    struct Model {
        let protocolInstanceUID: UID
        let sas: ObvOwnedIdentityTransferSas
    }
    
    private func onAppear() {
        Task {
            await actions.targetDeviceIsShowingSasAndExpectingEndOfProtocol(
                protocolInstanceUID: model.protocolInstanceUID,
                onSyncSnapshotReception: onSyncSnapshotReception,
                onSuccessfulTransfer: onSuccessfulTransfer,
                onKeycloakAuthenticationNeeded: onKeycloakAuthenticationNeeded)
        }
    }
    
    /// Can be nonisolated, since we dispatch on the main thread
    nonisolated
    private func onSyncSnapshotReception() {
        DispatchQueue.main.async {
            isSpinnerShown = true
        }
    }
    

    /// Invoked by the protocol manager on this target device when authentication is required by the source device before sending the snapshot.
    /// This scenario arises specifically when transferring a Keycloak-managed profile, where Keycloak enforces transfer protection.
    /// No need to isolate this method, since it immediately dispatch its work.
    nonisolated
    private func onKeycloakAuthenticationNeeded(_ ownedCryptoId: ObvCryptoId, _ keycloakConfiguration: ObvKeycloakConfiguration, transferProofElements: ObvKeycloakTransferProofElements) {
        Task {
            do {
                let proof = try await actions.userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(keycloakConfiguration: keycloakConfiguration, transferProofElements: transferProofElements)
                try await actions.userProvidesProofOfAuthenticationOnKeycloakServer(ownedCryptoId: ownedCryptoId, protocolInstanceUID: model.protocolInstanceUID, proof: proof)
            } catch {
                assertionFailure()
            }
        }
    }
    
    /// Can be nonisolated, since we dispatch on the main thread
    nonisolated
    private func onSuccessfulTransfer(_ transferredOwnedCryptoId: ObvCryptoId, _ postTransferError: Error?) {
        DispatchQueue.main.async {
            isSpinnerShown = false
            Task {
                // This call will allow to push the last screen for the transfer
                // The postTransferError, if not nil, is the error occuring after a successful restore at the engine level, when something goes wrong at the app leve, or when setting the unexpiring device. We display this error on the last screen, by we cannot do much better.
                await actions.successfulTransferWasPerformedOnThisTargetDevice(transferredOwnedCryptoId: transferredOwnedCryptoId, postTransferError: postTransferError)
            }
        }
    }
    
    
    var body: some View {
        ScrollView {
            VStack {
                
                NewOnboardingHeaderView(title: "OWNED_IDENTITY_TRANSFER_ENTER_CODE_ON_OTHER_DEVICE", subtitle: nil)
                
                OnboardingSasView(sas: model.sas)
                    .padding(.top)
                
                HStack {
                    Text("OWNED_IDENTITY_TRANSFER_TARGET_LAST_STEP")
                    Spacer()
                }
                .padding(.top)
                .font(.body)

                // Show an activity indicator when the snapshot is receive from the source device,
                // and thus processing (restored, register to push notifications, keep device active)
                // on this target device.
                
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.top)
                .opacity(isSpinnerShown ? 1.0 : 0.0)
                                
            }
            .padding(.horizontal)
        }
        .onAppear(perform: onAppear)
    }
    
}


private struct OnboardingSasView: View {
    
    let sas: ObvOwnedIdentityTransferSas
    
    var body: some View {
        HStack {
            ForEach((0..<ObvOwnedIdentityTransferSessionNumber.expectedCount), id: \.self) { index in
                SingleDigitTextField("", text: .constant("\(sas.digits[index])"), actions: nil, model: nil)
                    .disabled(true)
            }
        }
    }
    
}



// MARK: - Previews


struct TransferProtocolTargetShowSasView_Previews: PreviewProvider {
    
    private static let sasForPreviews = try! ObvOwnedIdentityTransferSas(fullSas: "12345678".data(using: .utf8)!)

    private final class ActionsForPreviews: TransferProtocolTargetShowSasViewActionsProtocol {
        
        func targetDeviceIsShowingSasAndExpectingEndOfProtocol(protocolInstanceUID: UID, onSyncSnapshotReception: @escaping () -> Void, onSuccessfulTransfer: @escaping (ObvCryptoId, Error?) -> Void, onKeycloakAuthenticationNeeded: @escaping (ObvCryptoId, ObvKeycloakConfiguration, ObvKeycloakTransferProofElements) -> Void) async {
            try! await Task.sleep(seconds: 0)
            onSyncSnapshotReception()
            try! await Task.sleep(seconds: 0)
        }
        
        
        func successfulTransferWasPerformedOnThisTargetDevice(transferredOwnedCryptoId: ObvCryptoId, postTransferError: Error?) async {}
        
        func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(keycloakConfiguration: ObvKeycloakConfiguration, transferProofElements: ObvKeycloakTransferProofElements) async throws -> ObvKeycloakTransferProofAndAuthState {
            throw NSError(domain: "TransferProtocolTargetShowSasView_Previews", code: 0)
        }
        
        func userProvidesProofOfAuthenticationOnKeycloakServer(ownedCryptoId: ObvTypes.ObvCryptoId, protocolInstanceUID: ObvCrypto.UID, proof: ObvTypes.ObvKeycloakTransferProofAndAuthState) async throws {}

    }
    
    private static let actions = ActionsForPreviews()
    
    static var previews: some View {
        TransferProtocolTargetShowSasView(actions: actions, model: .init(protocolInstanceUID: UID.zero, sas: Self.sasForPreviews))
    }
 
    fileprivate enum ObvError: Error {
        case errorForPreviews
    }
    
}
