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

import Foundation
import SwiftUI
import ObvTypes
import ObvEngine


protocol PermuteDeviceExpirationViewModelProtocol {
    
    var ownedCryptoId: ObvCryptoId { get }
    var identifierOfDeviceToKeepActive: Data { get }
    var nameOfDeviceToKeepActive: String { get }
    var identifierOfDeviceWithoutExpiration: Data { get }
    var nameOfDeviceWithoutExpiration: String { get }
    
}


// MARK: - PermuteDeviceExpirationViewActionsDelegate

protocol PermuteDeviceExpirationViewActionsDelegate {

    func userWantsToCancelAndDismissPermuteDeviceExpirationView() async
    func userWantsToSeeSubscriptionPlansFromPermuteDeviceExpirationView() async
    func userConfirmedFromPermuteDeviceExpirationView(ownedCryptoId: ObvCryptoId, identifierOfDeviceToKeepActive: Data, identifierOfDeviceWithoutExpiration: Data) async
    
}


struct PermuteDeviceExpirationView<Model: PermuteDeviceExpirationViewModelProtocol>: View {
    
    let model: Model
    let actions: PermuteDeviceExpirationViewActionsDelegate

    private func userWantsToCancel() {
        Task {
            await actions.userWantsToCancelAndDismissPermuteDeviceExpirationView()
        }
    }
    
    private func userWantsToSeeSubscriptionPlans() {
        Task {
            await actions.userWantsToSeeSubscriptionPlansFromPermuteDeviceExpirationView()
        }
    }
    
    private func userConfirmed() {
        let ownedCryptoId = model.ownedCryptoId
        let identifierOfDeviceToKeepActive = model.identifierOfDeviceToKeepActive
        let identifierOfDeviceWithoutExpiration = model.identifierOfDeviceWithoutExpiration
        Task {
            await actions.userConfirmedFromPermuteDeviceExpirationView(
                ownedCryptoId: ownedCryptoId,
                identifierOfDeviceToKeepActive: identifierOfDeviceToKeepActive,
                identifierOfDeviceWithoutExpiration: identifierOfDeviceWithoutExpiration)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack {
                
                // Title
                
                Text("PERMUTE_DEVICE_EXPIRATION_CONFIRMATION_ALERT_TITLE")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                .padding(.top, 32)
                
                // Explanation
                
                ObvCardView {
                    HStack {
                        Text("KEEP_DEVICE_\(model.nameOfDeviceToKeepActive)_ACTIVE_AND_ACCEPT_TO_DEACTIVATE_DEVICE_\(model.nameOfDeviceWithoutExpiration)")
                            .font(.body)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                        Spacer()
                    }
                }
                .padding(.vertical, 32)
                
                // Buttons
                
                OlvidButton(style: .blue, title: Text("DEACTIVATE_\(model.nameOfDeviceWithoutExpiration)_AND_ACTIVATE_\(model.nameOfDeviceToKeepActive)"), systemIcon: .arrow2Squarepath, action: userConfirmed)

                OlvidButton(style: .blue, title: Text("See subscription plans"), systemIcon: .flameFill, action: userWantsToSeeSubscriptionPlans)

                OlvidButton(style: .standardWithBlueText, title: Text("Cancel"), action: userWantsToCancel)
                
                Spacer()

            }.padding()
        }
    }
    
}


// MARK: - Previews

struct PermuteDeviceExpirationView_Previews: PreviewProvider {
    
    private struct PermuteDeviceExpirationViewModelForPreviews: PermuteDeviceExpirationViewModelProtocol {
        let ownedCryptoId: ObvCryptoId
        let identifierOfDeviceToKeepActive: Data
        let nameOfDeviceToKeepActive: String
        let identifierOfDeviceWithoutExpiration: Data
        let nameOfDeviceWithoutExpiration: String
    }
    
    private struct PermuteDeviceExpirationViewActionsDelegateForPreviews: PermuteDeviceExpirationViewActionsDelegate {
        func userWantsToCancelAndDismissPermuteDeviceExpirationView() async {}
        func userWantsToSeeSubscriptionPlansFromPermuteDeviceExpirationView() async {}
        func userConfirmedFromPermuteDeviceExpirationView(ownedCryptoId: ObvTypes.ObvCryptoId, identifierOfDeviceToKeepActive: Data, identifierOfDeviceWithoutExpiration: Data) async {}
    }
    
    private static let identityAsURL: URL = URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!
        
    private static let ownedCryptoId = ObvURLIdentity(urlRepresentation: identityAsURL)!.cryptoId

    static var previews: some View {
        Group {
            PermuteDeviceExpirationView(
                model: PermuteDeviceExpirationViewModelForPreviews(
                    ownedCryptoId: ownedCryptoId,
                    identifierOfDeviceToKeepActive: Data(repeating: 0, count: 16),
                    nameOfDeviceToKeepActive: "iPhone 14",
                    identifierOfDeviceWithoutExpiration: Data(repeating: 1, count: 16),
                    nameOfDeviceWithoutExpiration: "iPad Pro"),
                actions: PermuteDeviceExpirationViewActionsDelegateForPreviews())
        }
    }
    
}
