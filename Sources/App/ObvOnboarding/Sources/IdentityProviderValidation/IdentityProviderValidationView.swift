/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvJWS
import AppAuth
import ObvSystemIcon
import AuthenticationServices
import ObvTypes


protocol IdentityProviderValidationViewActionsProtocol: AnyObject {
    func discoverKeycloakServer(keycloakServerURL: URL) async throws -> (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration)
    func userWantsToAuthenticateOnKeycloakServer(keycloakConfiguration: ObvKeycloakConfiguration, isConfiguredFromMDM: Bool, keycloakServerKeyAndConfig: (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration)) async throws
}


struct IdentityProviderValidationView: View {
    
    let model: Model
    let actions: IdentityProviderValidationViewActionsProtocol
    @State private var discoveryStatus: KeycloakServerDiscoveryStatus = .toDiscover

    @State private var errorForAlert: Error?
    @State private var isAlertShown = false

    
    struct Model {
        let keycloakConfiguration: ObvKeycloakConfiguration
        let isConfiguredFromMDM: Bool
    }
    
    
    private enum KeycloakServerDiscoveryStatus {
        
        case toDiscover
        case discovering
        case discoveryFailed
        case discovered(keycloakServerKeyAndConfig: (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration))
        
        var isDiscovered: Bool {
            switch self {
            case .toDiscover, .discovering, .discoveryFailed:
                return false
            case .discovered:
                return true
            }
        }
    }

    
    @MainActor
    private func discoverKeycloakServerIfRequired() async {
        switch discoveryStatus {
        case .toDiscover:
            break
        case .discovering, .discoveryFailed, .discovered:
            return
        }
        discoveryStatus = .discovering
        do {
            let keycloakServerKeyAndConfig = try await actions.discoverKeycloakServer(keycloakServerURL: model.keycloakConfiguration.keycloakServerURL)
            discoveryStatus = .discovered(keycloakServerKeyAndConfig: keycloakServerKeyAndConfig)
        } catch {
            discoveryStatus = .discoveryFailed
        }
    }
    
    
    private var systemIcon: SystemIcon {
        discoveryStatus.isDiscovered ? .checkmark : .xmark
    }
    
    private var systemIconColor: UIColor {
        discoveryStatus.isDiscovered ? .systemGreen : .systemRed
    }
    
    private var discoveryStatusLocalizedStringKey: LocalizedStringKey {
        discoveryStatus.isDiscovered ? "IDENTITY_PROVIDER_CONFIGURED_SUCCESS" : "IDENTITY_PROVIDER_CONFIGURED_FAILURE"
    }
    
    
    private func userWantsToAuthenticate(keycloakServerKeyAndConfig: (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration)) async {
        do {
            try await actions.userWantsToAuthenticateOnKeycloakServer(
                keycloakConfiguration: model.keycloakConfiguration,
                isConfiguredFromMDM: model.isConfiguredFromMDM,
                keycloakServerKeyAndConfig: keycloakServerKeyAndConfig)
        } catch {
            // Do not show an alert if the user just cancelled the authentication process
            let nsError = error as NSError
            let errorsToCheck = [nsError] + nsError.underlyingErrors.map({ $0 as NSError })
            for er in errorsToCheck {
                if er.domain == ASWebAuthenticationSessionError.errorDomain && er.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    // No need to show an alert
                    return
                }
            }
            errorForAlert = error
            isAlertShown = true
        }
    }
    
    
    private var authenticationFailureAlertTitle: LocalizedStringKey {
        if let errorForAlert {
            return "KEYCLOAK_AUTHENTICATION_FAILED_ALERT_\((errorForAlert as NSError).localizedDescription)"
        } else {
            return "KEYCLOAK_AUTHENTICATION_FAILED_ALERT"
        }
    }
    
    
    var body: some View {
        
        switch discoveryStatus {
            
        case .toDiscover, .discovering:
            
            DiscoveringInProgressView(isConfiguredFromMDM: model.isConfiguredFromMDM)
                .onAppear {
                    Task { await discoverKeycloakServerIfRequired() }
                }
            
        case .discoveryFailed, .discovered:
            
            ScrollView {
                VStack {
                    
                    NewOnboardingHeaderView(title: "IDENTITY_PROVIDER", subtitle: nil)
                    
                    HStack {
                        Spacer()
                        BigCircledSystemIconView(
                            systemIcon: systemIcon,
                            backgroundColor: systemIconColor)
                        Spacer()
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 32)
                    
                    Text(discoveryStatusLocalizedStringKey)
                        .font(.system(.body, design: .default))
                    
                    Spacer()
                    
                }.padding(.horizontal)
            }
            
            if case .discovered(keycloakServerKeyAndConfig: let config) = discoveryStatus {
                
                Button(action: { Task { await userWantsToAuthenticate(keycloakServerKeyAndConfig: config) } }) {
                    Label("AUTHENTICATE", systemIcon: .personCropCircleBadgeCheckmark)
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                }
                .background(Color.blue01)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()
                .alert(authenticationFailureAlertTitle, isPresented: $isAlertShown) {
                    Button("OK".localizedInThisBundle, role: .cancel) { }
                }
            }
            
        }
        
    }
}


// MARK: - DiscoveringInProgressView

private struct DiscoveringInProgressView: View {
    
    let isConfiguredFromMDM: Bool
    
    var body: some View {
        ProgressView()
        if isConfiguredFromMDM {
            HStack {
                Spacer()
                Text("VALIDATING_ENTERPRISE_CONFIGURATION")
                    .font(.system(.subheadline, design: .default))
                Spacer()
            }
            .padding(.top, 16)
        }
    }
}


// MARK: - BigCircledSystemIconView

private struct BigCircledSystemIconView: View {
    
    let systemIcon: SystemIcon
    let backgroundColor: UIColor
    
    var body: some View {
        Image(systemIcon: systemIcon)
            .font(Font.system(size: 50, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
            .padding(32)
            .background(Circle().fill(Color(backgroundColor)))
            .padding()
            .background(Circle().fill(Color(backgroundColor).opacity(0.2)))
    }
    
}
