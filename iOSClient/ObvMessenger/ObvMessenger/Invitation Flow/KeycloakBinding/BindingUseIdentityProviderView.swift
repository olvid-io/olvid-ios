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
import ObvEngine
import ObvTypes
import os.log


final class KeycloakBindingStore {
    
    let keycloakConfig: KeycloakConfiguration
    let installedOlvidAppIsOutdated: () -> Void
    
    init(keycloakConfig: KeycloakConfiguration, installedOlvidAppIsOutdated: @escaping () -> Void) {
        self.keycloakConfig = keycloakConfig
        self.installedOlvidAppIsOutdated = installedOlvidAppIsOutdated
    }
    
    deinit {
        debugPrint("DEINIT")
    }
    
    private static let errorDomain = "KeycloakBindingStore"
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }


    /// This method can throw either a standard `Error` or an error of the following type: `KeycloakManager.GetOwnDetailsError`
    @MainActor
    fileprivate func userWantsToAuthenticate() async throws -> (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff, obvKeycloakState: ObvKeycloakState) {
        let keycloakConfig = self.keycloakConfig
        let (jwks, configuration) = try await KeycloakManagerSingleton.shared.discoverKeycloakServer(for: keycloakConfig.serverURL)
        let authState = try await KeycloakManagerSingleton.shared.authenticate(configuration: configuration, clientId: keycloakConfig.clientId, clientSecret: keycloakConfig.clientSecret, ownedCryptoId: nil)
        let (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff) = try await KeycloakManagerSingleton.shared.getOwnDetails(
            keycloakServer: keycloakConfig.serverURL,
            authState: authState,
            clientSecret: keycloakConfig.clientSecret,
            jwks: jwks,
            latestLocalRevocationListTimestamp: nil)
        if let minimumBuildVersion = keycloakServerRevocationsAndStuff.minimumIOSBuildVersion {
            guard ObvMessengerConstants.bundleVersionAsInt >= minimumBuildVersion else {
                installedOlvidAppIsOutdated()
                throw Self.makeError(message: "Installed Olvid App is outdated")
            }
        }
        
        let rawAuthState = try authState.serialize()
        let obvKeycloakState = ObvKeycloakState(
            keycloakServer: keycloakConfig.serverURL,
            clientId: keycloakConfig.clientId,
            clientSecret: keycloakConfig.clientSecret,
            jwks: jwks,
            rawAuthState: rawAuthState,
            signatureVerificationKey: keycloakUserDetailsAndStuff.serverSignatureVerificationKey,
            latestLocalRevocationListTimestamp: nil)

        return (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff, obvKeycloakState)
        
    }

}



struct BindingUseIdentityProviderView: View {
    
    let ownedCryptoId: ObvCryptoId
    let dismissAction: () -> Void
    let installedOlvidAppIsOutdated: () -> Void
    @State private var store: KeycloakBindingStore
    @State private var showBindingShowIdentityView = false
    @State private var authenticationResult: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff, obvKeycloakState: ObvKeycloakState)? = nil
    @State private var authenticationFailed = false

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: BindingUseIdentityProviderView.self))

    init(keycloakConfig: KeycloakConfiguration, ownedCryptoId: ObvCryptoId, dismissAction: @escaping () -> Void, installedOlvidAppIsOutdated: @escaping () -> Void) {
        self._store = State(initialValue: KeycloakBindingStore(keycloakConfig: keycloakConfig, installedOlvidAppIsOutdated: installedOlvidAppIsOutdated))
        self.ownedCryptoId = ownedCryptoId
        self.dismissAction = dismissAction
        self.installedOlvidAppIsOutdated = installedOlvidAppIsOutdated
    }
    
    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .edgesIgnoringSafeArea(.all)
            VStack(alignment: .leading, spacing: 24) {
                BindingExplanationCardView()
                    .padding(.horizontal)
                    .padding(.top)
                BindingButtonsView(authenticateAction: {
                    Task {
                        do {
                            self.authenticationResult = try await store.userWantsToAuthenticate()
                            assert(Thread.isMainThread)
                            os_log("Will show view displaying identity obtained from keycloak", log: log, type: .info)
                            withAnimation { self.showBindingShowIdentityView = true }
                        } catch {
                            assert(Thread.isMainThread)
                            os_log("Keycloak authentication failed: %{public}@", log: log, type: .error, error.localizedDescription)
                            withAnimation { authenticationFailed = true }
                        }
                    }
                })
                .padding(.horizontal)
                Spacer()
            }
            if let authenticationResult = self.authenticationResult {
                NavigationLink(
                    destination: BindingShowIdentityView(ownedCryptoId: ownedCryptoId,
                                                         keycloakUserDetailsAndStuff: authenticationResult.keycloakUserDetailsAndStuff,
                                                         revocationAllowed: authenticationResult.keycloakServerRevocationsAndStuff.revocationAllowed,
                                                         obvKeycloakState: authenticationResult.obvKeycloakState,
                                                         dismissAction: dismissAction),
                    isActive: $showBindingShowIdentityView,
                    label: { EmptyView() }
                )
            }
        }
        .alert(isPresented: $authenticationFailed) {
            Alert(title: Text("AUTHENTICATION_FAILED"), message: Text("PLEASE_TRY_AGAIN"), dismissButton: Alert.Button.default(Text("Ok")))
        }
    }
    
    
}




fileprivate struct BindingExplanationCardView: View {
    var body: some View {
        ObvCardView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("LABEL_BIND_KEYCLOAK")
                        .font(.headline)
                    Spacer()
                }
                Text("EXPLANATION_KEYCLOAK_UPDATE_NEW")
                Text("PLEASE_CONTACT_ADMIN_FOR_MORE_DETAILS")
            }
            .font(.body)
        }
    }
}




fileprivate struct BindingButtonsView: View {
    
    let authenticateAction: () -> Void

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(spacing: 8) {
            OlvidButton(style: .standard, title: Text("Cancel"), systemIcon: .xmarkCircleFill, action: {
                presentationMode.wrappedValue.dismiss()
            })
            OlvidButton(style: .blue, title: Text("AUTHENTICATE"), systemIcon: .personCropCircleBadgeCheckmark, action: authenticateAction)
        }
    }
}
