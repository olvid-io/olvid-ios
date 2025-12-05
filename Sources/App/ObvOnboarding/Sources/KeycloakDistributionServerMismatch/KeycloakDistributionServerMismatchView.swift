/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvDesignSystem


struct KeycloakDistributionServerMismatchView: View {
    
    let model: Model
    
    struct Model {
        let distributionServerRequiredByKeycloak: URL
        let ownedCryptoIdToBind: ObvCryptoId
    }
    
    var body: some View {
        ScrollView {
            VStack {
                ObvCardView {
                    VStack {
                        
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemIcon: .serverRack)
                                .foregroundStyle(.red)
                            Text("MISMATCH_BETWEEN_KEYCLOAK_DISTRIBUTION_SERVER_AND_EXISTING_PROFILE_DISTRIBUTION_SERVER")
                        }
                                                
                    }
                }
                .padding()
            }
            
        }
        .navigationTitle(String(localizedInThisBundle: "DISTRIBUTION_SERVER_MISMATCH"))
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(UIColor.secondarySystemBackground))
    }
    
}


#if DEBUG

//@MainActor
//private final class ActionsForPreviews: KeycloakDistributionServerMismatchViewActions {
//    
//    func userWantsToLeaveKeycloakDistributionServerMismatchView(_ view: KeycloakDistributionServerMismatchView) {
//        print("User wants to leave KeycloakDistributionServerMismatchView preview")
//    }
//    
//}

extension ObvCryptoId {
    
    @MainActor
    fileprivate static let sampleData: Self =
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)
        
}

@MainActor
private let modelForPreviews: KeycloakDistributionServerMismatchView.Model = .init(
    distributionServerRequiredByKeycloak: URL(string: "https://server.olvid.io")!,
    ownedCryptoIdToBind: .sampleData)

//@MainActor
//private let actionsForPreviews = ActionsForPreviews()

#Preview {
    NavigationStack {
        KeycloakDistributionServerMismatchView(model: modelForPreviews)
    }
}


#endif
