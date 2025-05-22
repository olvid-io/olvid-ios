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
import ObvDesignSystem


protocol InputSASOnSourceViewActionsProtocol: AnyObject {
    func userEnteredValidSASOnSourceDevice(enteredSAS: ObvOwnedIdentityTransferSas, ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, protocolInstanceUID: UID, targetDeviceName: String) async throws
}


struct InputSASOnSourceView: View, SessionNumberTextFieldActionsProtocol {
    
    private enum AlertType {
        case userEnteredIncorrectSAS
        case seriousError
    }

    let actions: InputSASOnSourceViewActionsProtocol
    let model: Model
    
    @State private var shownAlert: AlertType? = nil
    @State private var userEnteredValidSAS = false
    
    struct Model {
        let sasExpectedOnInput: ObvOwnedIdentityTransferSas
        let targetDeviceName: String
        let ownedCryptoId: ObvCryptoId
        let ownedDetails: CNContact
        let protocolInstanceUID: UID
    }
    
    
    private func alertTitle(for alertType: AlertType) -> LocalizedStringKey {
        switch alertType {
        case .userEnteredIncorrectSAS:
            return "OWNED_IDENTITY_TRANSFER_INCORRECT_TRANSFER_SESSION_NUMBER"
        case .seriousError:
            return "OWNED_IDENTITY_TRANSFER_INCORRECT_SERIOUS_ERROR"
        }
    }

    // SessionNumberTextFieldActionsProtocol
    
    func userEnteredSessionNumber(sessionNumber: String) async {
        guard let data = sessionNumber.data(using: .utf8) else { assertionFailure(); return }
        guard let enteredSAS = try? ObvOwnedIdentityTransferSas(fullSas: data) else { assertionFailure(); return }
        if enteredSAS == model.sasExpectedOnInput {
            shownAlert = nil
            userEnteredValidSAS = true
            Task {
                do {
                    try await actions.userEnteredValidSASOnSourceDevice(
                        enteredSAS: enteredSAS,
                        ownedCryptoId: model.ownedCryptoId,
                        ownedDetails: model.ownedDetails,
                        protocolInstanceUID: model.protocolInstanceUID,
                        targetDeviceName: model.targetDeviceName)
                } catch {
                    shownAlert = .seriousError
                }
            }
        } else {
            shownAlert = .userEnteredIncorrectSAS
        }
    }
    
    
    func userIsTypingSessionNumber() {
        shownAlert = nil
    }
    


    var body: some View {
        ScrollView {
            VStack {
                
                ObvHeaderView(
                    title: "OWNED_IDENTITY_TRANSFER_ENTER_CODE_FROM_NEW_DEVICE".localizedInThisBundle,
                    subtitle: nil)
                
                SessionNumberTextField(actions: self, model: .init(mode: .enterSessionNumber))
                    .padding(.top)
                    .disabled(userEnteredValidSAS)
                
                if let shownAlert {
                    HStack {
                        Label(
                            title: { Text(alertTitle(for: shownAlert)) },
                            icon: {
                                Image(systemIcon: .xmarkCircle)
                                    .renderingMode(.template)
                                    .foregroundColor(Color(.systemRed))
                            })
                        Spacer()
                    }
                }

                if userEnteredValidSAS {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
                
            }
            .padding(.horizontal)
        }
    }
}



struct InputSASOnSourceView_Previews: PreviewProvider {
    
    private static let sas = "12345678".data(using: .utf8)!
    
    private final class ActionsForPreviews: InputSASOnSourceViewActionsProtocol {
        func userEnteredValidSASOnSourceDevice(enteredSAS: ObvTypes.ObvOwnedIdentityTransferSas, ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, protocolInstanceUID: UID, targetDeviceName: String) async throws {}
    }
    
    private static let ownedCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)

    private static let actions = ActionsForPreviews()
    
    private static let ownedDetails: CNContact = {
        let details = CNMutableContact()
        details.givenName = "Steve"
        return details
    }()

    static var previews: some View {
        InputSASOnSourceView(actions: actions, model: .init(sasExpectedOnInput: try! .init(fullSas: sas), targetDeviceName: "Name of new device", ownedCryptoId: ownedCryptoId, ownedDetails: ownedDetails, protocolInstanceUID: UID.zero))
    }
    
}
