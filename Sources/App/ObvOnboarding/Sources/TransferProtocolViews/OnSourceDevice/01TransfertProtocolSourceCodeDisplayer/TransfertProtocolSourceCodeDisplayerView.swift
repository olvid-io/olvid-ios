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
import Contacts


protocol TransfertProtocolSourceCodeDisplayerViewActionsProtocol: AnyObject {
    
    typealias BlockCancellingOwnedIdentityTransferProtocol = () -> Void
    typealias TransferSessionNumber = Int
    
    /// Called as soon as the view appears.
    /// - Parameters:
    ///   - ownedCryptoId: The `ObvCryptoId` of the owned identity.
    ///   - onAvailableSessionNumber: A block called as soon as the session number is available.
    func userWantsToInitiateOwnedIdentityTransferProtocolOnSourceDevice(ownedCryptoId: ObvCryptoId, onAvailableSessionNumber: @MainActor @escaping (ObvOwnedIdentityTransferSessionNumber) -> Void, onAvailableSASExpectedOnInput: @MainActor @escaping (ObvOwnedIdentityTransferSas, String, UID) -> Void) async throws
    
    func sasExpectedOnInputIsAvailable(_ sasExpectedOnInput: ObvOwnedIdentityTransferSas, targetDeviceName: String, ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, protocolInstanceUID: UID) async
    
}


struct TransfertProtocolSourceCodeDisplayerView: View {
    
    let model: Model
    let actions: TransfertProtocolSourceCodeDisplayerViewActionsProtocol
    @State private var sessionNumber: ObvOwnedIdentityTransferSessionNumber?
    
    struct Model {
        let ownedCryptoId: ObvCryptoId
        let ownedDetails: CNContact
    }
    
    private func userWantsToStartTransferProtocolAsSourceDevice() {
        Task {
            do {
                try await actions.userWantsToInitiateOwnedIdentityTransferProtocolOnSourceDevice(
                    ownedCryptoId: model.ownedCryptoId,
                    onAvailableSessionNumber: onAvailableSessionNumber,
                    onAvailableSASExpectedOnInput: onAvailableSASExpectedOnInput)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    
    private func onAvailableSASExpectedOnInput(_ sasExpectedOnInput: ObvOwnedIdentityTransferSas, _ targetDeviceName: String, _ protocolInstanceUID: UID) {
        Task {
            await actions.sasExpectedOnInputIsAvailable(sasExpectedOnInput, targetDeviceName: targetDeviceName, ownedCryptoId: model.ownedCryptoId, ownedDetails: model.ownedDetails, protocolInstanceUID: protocolInstanceUID)
        }
    }
    

    private func onAvailableSessionNumber(_ sessionNumber: ObvOwnedIdentityTransferSessionNumber) {
        Task { await setSessionNumber(sessionNumber) }
    }
    
    
    @MainActor
    private func setSessionNumber(_ sessionNumber: ObvOwnedIdentityTransferSessionNumber) async {
        withAnimation {
            self.sessionNumber = sessionNumber
        }
    }
    
    
    var body: some View {
        VStack {
            
            if let sessionNumber {
                
                ScrollView {
                    
                    NewOnboardingHeaderView(title: "OWNED_IDENTITY_TRANSFER_ENTER_CODE_ON_NEW_DEVICE", subtitle: nil)
                    
                    Text("OWNED_IDENTITY_TRANSFER_ENTER_CODE_ON_OTHER_DEVICE_BODY")
                        .font(.body)
                        .padding(.top)
                    
                    SessionNumberView(sessionNumber: sessionNumber)
                        .padding(.top)
                    
                    HStack {
                        Text("PLEASE_NOTE_THIS_CODE_WORKS_ONLY_ONCE")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }.padding(.top)
                    
                }
                
            } else {
                Spacer()
                ProgressView()
                    .onAppear(perform: userWantsToStartTransferProtocolAsSourceDevice)
                Text("OWNED_IDENTITY_TRANSFER_CONTACTING_SERVER")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
            }
                        
        }
        .padding(.horizontal)
    }
    
}


private struct SessionNumberView: View {
    
    let sessionNumber: ObvOwnedIdentityTransferSessionNumber
    
    var body: some View {
        HStack {
            ForEach((0..<ObvOwnedIdentityTransferSessionNumber.expectedCount), id: \.self) { index in
                SingleDigitTextField("", text: .constant("\(sessionNumber.digits[index])"), actions: nil, model: nil)
                    .disabled(true)
            }
        }
    }
    
}



// MARK: - Previews

struct TransfertProtocolSourceCodeDisplayerView_Previews: PreviewProvider {
    
    private static let ownedCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)

    private static let ownedDetails: CNContact = {
        let details = CNMutableContact()
        details.givenName = "Steve"
        return details
    }()
    
    private static let model = TransfertProtocolSourceCodeDisplayerView.Model(ownedCryptoId: ownedCryptoId, ownedDetails: ownedDetails)
    
    private final class ActionsForPreviews: TransfertProtocolSourceCodeDisplayerViewActionsProtocol {
        
        func userWantsToInitiateOwnedIdentityTransferProtocolOnSourceDevice(ownedCryptoId: ObvTypes.ObvCryptoId, onAvailableSessionNumber: @MainActor @escaping (ObvOwnedIdentityTransferSessionNumber) -> Void, onAvailableSASExpectedOnInput: @MainActor @escaping (ObvOwnedIdentityTransferSas, String, UID) -> Void) async throws {
         
            Task {
                try! await Task.sleep(seconds: 0)
                await onAvailableSessionNumber(try! ObvOwnedIdentityTransferSessionNumber(sessionNumber: 112233))
            }
            
        }
        
        func sasExpectedOnInputIsAvailable(_ sasExpectedOnInput: ObvTypes.ObvOwnedIdentityTransferSas, targetDeviceName: String, ownedCryptoId: ObvTypes.ObvCryptoId, ownedDetails: CNContact, protocolInstanceUID: ObvCrypto.UID) async {}

    }
    
    private static let actions = ActionsForPreviews()
    
    static var previews: some View {
        TransfertProtocolSourceCodeDisplayerView(
            model: model,
            actions: actions)
    }
    
}
