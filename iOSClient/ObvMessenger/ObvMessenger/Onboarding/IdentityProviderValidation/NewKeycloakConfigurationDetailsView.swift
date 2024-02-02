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


struct NewKeycloakConfigurationDetailsView: View {
    
    let model: Model
    
    struct Model {
        let keycloakConfiguration: Onboarding.KeycloakConfiguration
    }
    
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        
        ZStack {
            
            Color(UIColor.secondarySystemBackground)
                .edgesIgnoringSafeArea(.all)

            VStack {
                
                List {
                    Section {
                        ObvSimpleListItemView(
                            title: Text("SERVER_URL"),
                            value: model.keycloakConfiguration.keycloakServerURL.absoluteString)
                        ObvSimpleListItemView(
                            title: Text("CLIENT_ID"),
                            value: model.keycloakConfiguration.clientId)
                        ObvSimpleListItemView(
                            title: Text("CLIENT_SECRET"),
                            value: model.keycloakConfiguration.clientSecret)
                    } header: {
                        Text("IDENTITY_PROVIDER_CONFIGURATION")
                    }
                    
                }
                .padding(.bottom, 16)
                
                InternalButton("Back", action: { presentationMode.wrappedValue.dismiss() })
                    .padding()
                
                
            }
            .padding(.top, 16)
        }
        
    }
    
}


private struct InternalButton: View {
    
    private let key: LocalizedStringKey
    private let action: () -> Void
    @Environment(\.isEnabled) var isEnabled
    
    init(_ key: LocalizedStringKey, action: @escaping () -> Void) {
        self.key = key
        self.action = action
    }
        
    var body: some View {
        Button(action: action) {
            Text(key)
                .foregroundStyle(.white)
                .padding(.horizontal, 26)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
        }
        .background(Color("Blue01"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1.0 : 0.6)
    }
    
}
