/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvUI
import ObvDesignSystem


struct NewKeycloakConfigurationDetailsView: View {
    
    let model: Model
    
    struct Model {
        let keycloakConfiguration: ObvKeycloakConfiguration
    }
    
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        
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
            
            OlvidButtonNew {
                presentationMode.wrappedValue.dismiss()
            } label: {
                Text("BACK")
            }
            .padding(.horizontal)
            
        }
        .padding(.top, 16)
        
    }
    
}
