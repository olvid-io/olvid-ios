/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import ObvEngine


struct BetaConfigurationActivationView: View {
    
    let betaConfiguration: BetaConfiguration
    let dismissAction: () -> Void

    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .edgesIgnoringSafeArea(.all)
            ScrollView {
                VStack {
                    HStack(alignment: .firstTextBaseline) {
                        Text("SETTINGS_UPDATE_TITLE")
                            .font(.title)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    Spacer()
                    ObvCardView {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack { Spacer() } // Force full width
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: betaConfiguration.beta ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(betaConfiguration.beta ? .green : .gray)
                                Text("ACCESS_TO_ADVANCED_SETTINGS")
                            }
                        }
                        .font(.body)
                    }
                    .padding(.bottom, 16)
                    VStack {
                        OlvidButton(style: .standard, title: Text("Cancel"), systemIcon: .xmarkCircleFill, action: dismissAction)
                            .padding(.bottom, 4)
                        OlvidButton(style: .blue, title: Text("Update"), systemIcon: .checkmarkCircleFill) {
                            ObvMessengerSettings.BetaConfiguration.showBetaSettings = betaConfiguration.beta
                            dismissAction()
                            
                        }
                    }
                }
                .padding()
            }
        }
    }
    
}


struct BetaConfigurationActivationView_Previews: PreviewProvider {
    
    private static let betaConfiguration = BetaConfiguration(beta: true)
    
    static var previews: some View {
        Group {
            NavigationView {
                BetaConfigurationActivationView(betaConfiguration: betaConfiguration,
                                                dismissAction: {})
            }
            .environment(\.colorScheme, .dark)
        }
    }
}
