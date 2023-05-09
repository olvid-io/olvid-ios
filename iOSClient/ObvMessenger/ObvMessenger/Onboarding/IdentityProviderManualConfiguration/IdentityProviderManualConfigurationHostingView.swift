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
import Combine
import JWS
import AppAuth
import ObvTypes
import ObvUI

protocol IdentityProviderManualConfigurationHostingViewDelegate: AnyObject {
    
    func userWantsToValidateManualKeycloakConfiguration(keycloakConfig: KeycloakConfiguration) async
    
}


final class IdentityProviderManualConfigurationHostingView: UIHostingController<IdentityProviderManualConfigurationView> {
    
    private let store: IdentityProviderManualConfigurationViewStore
    
    init(delegate: IdentityProviderManualConfigurationHostingViewDelegate) {
        let store = IdentityProviderManualConfigurationViewStore(delegate: delegate)
        let view = IdentityProviderManualConfigurationView(store: store)
        self.store = store
        super.init(rootView: view)
        title = Strings.title
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = false
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.prefersLargeTitles = true
    }

    private struct Strings {
        static let title = NSLocalizedString("IDENTITY_PROVIDER", comment: "")
    }

}


final class IdentityProviderManualConfigurationViewStore: ObservableObject {
    
    @Published fileprivate var displayedIdentityServerAsString = ""
    @Published fileprivate var displayedClientId = ""
    @Published fileprivate var displayedClientSecret = ""

    @Published fileprivate var validatedServerURL: URL? = nil
    
    private var cancellables = [AnyCancellable]()

    weak var delegate: IdentityProviderManualConfigurationHostingViewDelegate?
    
    @Published private var identityServer: URL?
    @Published private(set) var keycloakConfig: KeycloakConfiguration?
    
    init(delegate: IdentityProviderManualConfigurationHostingViewDelegate?) {
        self.delegate = delegate
        processDisplayedValues()
    }
    
    private func processDisplayedValues() {
        cancellables.append(contentsOf: [
            // When the identity server changes, we invalidate any previously validated server, and check whether the new displayed server can be validated
            self.$displayedIdentityServerAsString.sink(receiveValue: { [weak self] displayedServer in
                if let url = URL(string: displayedServer), UIApplication.shared.canOpenURL(url) {
                    self?.identityServer = url
                } else {
                    self?.identityServer = nil
                }
            }),
            self.$identityServer.combineLatest(self.$displayedClientId).sink { [weak self] (serverURL, clientId) in
                guard let serverURL = serverURL, let displayedClientId = self?.displayedClientId, !clientId.isEmpty else {
                    withAnimation { self?.keycloakConfig = nil }
                    return
                }
                let keycloakConfig = KeycloakConfiguration(serverURL: serverURL, clientId: clientId, clientSecret: displayedClientId)
                guard self?.keycloakConfig != keycloakConfig else { return }
                withAnimation { self?.keycloakConfig = keycloakConfig }
            },
        ])
    }
    
    fileprivate func userWantsToValidateDisplayedServer() {
        guard let keycloakConfig = keycloakConfig else { assertionFailure(); return }
        Task { await delegate?.userWantsToValidateManualKeycloakConfiguration(keycloakConfig: keycloakConfig) }
    }
        
}


struct IdentityProviderManualConfigurationView: View {
    
    @ObservedObject var store: IdentityProviderManualConfigurationViewStore
    
    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .edgesIgnoringSafeArea(.all)
            VStack {
                
                Form {
                    Text("IDENTITY_PROVIDER_OPTION_EXPLANATION")
                        .font(.body)
                    IdentityProviderServerAndOtherTextFields(displayedIdentityServer: $store.displayedIdentityServerAsString,
                                                             displayedClientId: $store.displayedClientId,
                                                             displayedClientSecret: $store.displayedClientSecret)
                }

                OlvidButton(style: .blue,
                            title: Text("VALIDATE_SERVER"),
                            systemIcon: .checkmarkCircle,
                            action: store.userWantsToValidateDisplayedServer)
                    .disabled(store.keycloakConfig == nil)
                    .padding(.bottom, 16)
                    .padding(.horizontal)

            }

        }
    }
}




fileprivate struct IdentityProviderServerAndOtherTextFields: View {
    
    @Binding var displayedIdentityServer: String
    @Binding var displayedClientId: String
    @Binding var displayedClientSecret: String
    let validating: Bool = false

    var body: some View {
        
        // Identity Server URL
        Section(header: Text("IDENTITY_PROVIDER_SERVER")) {
            HStack {
                TextField(LocalizedStringKey("URL"), text: $displayedIdentityServer)
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
                    .disabled(validating)
                if validating {
                    ObvProgressView()
                }
            }
            HStack {
                TextField(LocalizedStringKey("SERVER_CLIENT_ID"), text: $displayedClientId)
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
                    .disabled(validating)
                if validating {
                    ObvProgressView()
                }
            }
            HStack {
                SecureField(LocalizedStringKey("SERVER_CLIENT_SECRET"), text: $displayedClientSecret)
                    .disableAutocorrection(true)
                    .autocapitalization(.allCharacters)
                    .disabled(validating)
                if validating {
                    ObvProgressView()
                }
            }
        }

    }
}






struct IdentityProviderOptionsView_Previews: PreviewProvider {
    
    private static let mockStore = IdentityProviderManualConfigurationViewStore(delegate: nil)
    
    static var previews: some View {
        IdentityProviderManualConfigurationView(store: mockStore)
    }
}
