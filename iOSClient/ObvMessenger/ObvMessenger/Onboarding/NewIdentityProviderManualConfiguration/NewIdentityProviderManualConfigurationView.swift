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


protocol NewIdentityProviderManualConfigurationViewActionsProtocol: AnyObject {
    
    func userWantsToValidateManualKeycloakConfiguration(keycloakConfig: Onboarding.KeycloakConfiguration) async
    
}


struct NewIdentityProviderManualConfigurationView: View {

    let actions: NewIdentityProviderManualConfigurationViewActionsProtocol
    
    @State private var url = "";
    @State private var clientId = "";
    @State private var clientSecret = "";

    @State private var currentKeycloakConfig: Onboarding.KeycloakConfiguration?
    @State private var isValidating = false
    
    
    private func resetCurrentKeycloakConfig() {
        self.currentKeycloakConfig = computeKeycloakConfig()
    }
    
    private var isValidateButtonDisabled: Bool {
        isValidating || currentKeycloakConfig == nil
    }
    
    private func computeKeycloakConfig() -> Onboarding.KeycloakConfiguration? {
        let localURL = url.trimmingWhitespacesAndNewlines()
        let localClientId = clientId.trimmingWhitespacesAndNewlines()
        let clientSecret = clientSecret.trimmingWhitespacesAndNewlines()
        guard !localClientId.isEmpty else { return nil }
        guard let url = URL(string: localURL), UIApplication.shared.canOpenURL(url) else {
            return nil
        }
        return .init(keycloakServerURL: url, clientId: localClientId, clientSecret: clientSecret)
    }
    
    @MainActor
    private func validateButtonTapped() async {
        guard let currentKeycloakConfig else { assertionFailure(); return }
        isValidating = true
        await actions.userWantsToValidateManualKeycloakConfiguration(keycloakConfig: currentKeycloakConfig)
        isValidating = false
    }
    
    
    var body: some View {
        ZStack {
            VStack {
                ScrollView {
                    VStack {
                        
                        NewOnboardingHeaderView(
                            title: "CONFIGURE_YOUR_IDENTITY_PROVIDER_MANUALLY",
                            subtitle: "")
                        
                        HStack {
                            Text("IDENTITY_PROVIDER_OPTION_EXPLANATION")
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical)
                        
                        InternalCellView(title: "ONBOARDING_KEYCLOAK_MANUAL_CONFIGURATION_TITLE_URL",
                                         placeholder: "https://...",
                                         text: $url)
                        .onChange(of: url) { _ in resetCurrentKeycloakConfig() }
                        
                        InternalCellView(title: "ONBOARDING_KEYCLOAK_MANUAL_CONFIGURATION_TITLE_CLIENT_ID",
                                         placeholder: "",
                                         text: $clientId)
                        .onChange(of: clientId) { _ in resetCurrentKeycloakConfig() }
                        
                        InternalCellView(title: "ONBOARDING_KEYCLOAK_MANUAL_CONFIGURATION_TITLE_CLIENT_SECRET",
                                         placeholder: "",
                                         text: $clientSecret)
                        .onChange(of: clientSecret) { _ in resetCurrentKeycloakConfig() }
                        
                    }.padding(.horizontal)
                }
                
                InternalButton("VALIDATE_SERVER", action: { Task { await validateButtonTapped() } })
                    .disabled(isValidateButtonDisabled)
                    .padding(.horizontal)
                    .padding(.bottom)
                
            }
            .disabled(isValidating)
            
            if isValidating {
                ProgressView()
                    .controlSize(.large)
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

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
            Label {
                Text(key)
                    .foregroundStyle(.white)
            } icon: {
                Image(systemIcon: .serverRack)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .background(Color("Blue01"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1.0 : 0.6)
    }
    
}


// MARK: InternalCellView

private struct InternalCellView: View {
    
    let title: LocalizedStringKey
    let placeholder: String
    let text: Binding<String>
    
    private let monospacedBodyFont = Font.callout.monospaced()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            TextField(placeholder, text: text)
                .font(monospacedBodyFont)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(Color("TextFieldBackgroundColor"))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack { Spacer() }
        }
    }
    
}


struct NewIdentityProviderManualConfigurationView_Previews: PreviewProvider {
    
    private final class ActionsForPreviews: NewIdentityProviderManualConfigurationViewActionsProtocol {
        
        func userWantsToValidateManualKeycloakConfiguration(keycloakConfig: Onboarding.KeycloakConfiguration) async {
            try! await Task.sleep(seconds: 3)
        }
        
    }
    
    private static let actions = ActionsForPreviews()
    
    static var previews: some View {
        NewIdentityProviderManualConfigurationView(actions: actions)
    }
    
}
