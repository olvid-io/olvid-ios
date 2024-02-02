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
import ObvTypes
import ObvCrypto


protocol TransferProtocolTargetShowSasViewActionsProtocol: AnyObject {
    func targetDeviceIsShowingSasAndExpectingEndOfProtocol(protocolInstanceUID: UID, onSyncSnapshotReception: @escaping () -> Void, onSuccessfulTransfer: @escaping (ObvCryptoId, Error?) -> Void) async
    func successfulTransferWasPerformedOnThisTargetDevice(transferredOwnedCryptoId: ObvCryptoId, postTransferError: Error?) async
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
                onSuccessfulTransfer: onSuccessfulTransfer)
        }
    }
    
    
    private func onSyncSnapshotReception() {
        DispatchQueue.main.async {
            isSpinnerShown = true
        }
    }
    
    
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
        
        func targetDeviceIsShowingSasAndExpectingEndOfProtocol(protocolInstanceUID: UID, onSyncSnapshotReception: @escaping () -> Void, onSuccessfulTransfer: @escaping (ObvCryptoId, Error?) -> Void) async {
            try! await Task.sleep(seconds: 0)
            onSyncSnapshotReception()
            try! await Task.sleep(seconds: 0)
        }
        
        
        func successfulTransferWasPerformedOnThisTargetDevice(transferredOwnedCryptoId: ObvCryptoId, postTransferError: Error?) async {}
        
    }
    
    private static let actions = ActionsForPreviews()
    
    static var previews: some View {
        TransferProtocolTargetShowSasView(actions: actions, model: .init(protocolInstanceUID: UID.zero, sas: Self.sasForPreviews))
    }
 
    fileprivate enum ObvError: Error {
        case errorForPreviews
    }
    
}
