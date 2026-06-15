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
import ObvJWS
import AppAuth
import ObvSystemIcon
import AuthenticationServices
import ObvTypes
import ObvAppTypes
import ObvDesignSystem
import ObvKeycloakManager


/// Delegate protocol through which `IdentityProviderValidationView` requests actions from its coordinator.
///
/// Marked `@MainActor` because all callbacks originate from SwiftUI button taps and are forwarded
/// to the onboarding flow controller, which lives on the main actor.
@MainActor
protocol IdentityProviderValidationViewActionsProtocol {

    /// Called when the user taps the cancel/dismiss button. Only shown when `Model.showDismissButton` is `true`.
    func userWantsToDismiss(_ view: IdentityProviderValidationView)

    func discoverKeycloakServer(_ view: IdentityProviderValidationView, keycloakServerURL: URL) async throws -> KeycloakServerDiscoveryResult

    func userWantsToAuthenticateOnKeycloakServer(
        _ view: IdentityProviderValidationView,
        keycloakConfiguration: ObvKeycloakConfiguration,
        magicLink: ObvMagicLink?,
        discoveryResult: KeycloakServerDiscoveryResult,
        isConfiguredFromMDM: Bool,
        isBindingExistingProfile: IdentityProviderValidationView.Model.BindingExistingProfile
    ) async throws

}


struct IdentityProviderValidationView: View {
    
    let model: Model
    let actions: IdentityProviderValidationViewActionsProtocol

    @State private var discoveryStatus: KeycloakServerDiscoveryStatus = .toDiscover

    @State private var errorForAlert: Error?
    @State private var isAlertShown = false
    
    @State private var isInvalidMagicLinkAlertShown = false

    
    struct Model {
        let keycloakConfiguration: ObvKeycloakConfiguration
        /// A one-time token embedded in the OlvidURL that opened this screen. When non-nil the
        /// authenticate button exchanges it directly instead of launching a browser OIDC flow.
        let magicLink: ObvMagicLink?
        let isConfiguredFromMDM: Bool
        let isBindingExistingProfile: BindingExistingProfile
        /// When `true`, a cancel button is shown in the navigation bar. Set to `true` when this screen
        /// is presented modally (e.g. binding an existing profile via a deep link), and `false` during
        /// the linear onboarding flow where the user must not be able to skip the step.
        let showDismissButton: Bool
        
        enum BindingExistingProfile {
            case no
            case yes(ownedCryptoId: ObvCryptoId)
        }
        
    }
    
    
    private enum KeycloakServerDiscoveryStatus {
        
        case toDiscover
        case discovering
        case discoveryFailed
        case discovered(discoveryResult: KeycloakServerDiscoveryResult)
        
        var isDiscovered: Bool {
            switch self {
            case .toDiscover, .discovering, .discoveryFailed:
                return false
            case .discovered:
                return true
            }
        }
    }

    
    private func discoverKeycloakServerIfRequired() async {
        switch discoveryStatus {
        case .toDiscover:
            break
        case .discovering, .discoveryFailed, .discovered:
            return
        }
        discoveryStatus = .discovering
        do {
            let discoveryResult = try await actions.discoverKeycloakServer(self, keycloakServerURL: model.keycloakConfiguration.keycloakServerURL)
            discoveryStatus = .discovered(discoveryResult: discoveryResult)
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
    
    @State private var isShowingKeycloakConfigurationDetails = false

    @State private var isAuthenticating: Bool = false
    
    // Synchronous entry point from the button action so SwiftUI can animate `isAuthenticating`
    // before the async work starts. The defer in the Task ensures the flag resets on any exit path.
    private func authenticateButtonTapped(discoveryResult: KeycloakServerDiscoveryResult) {
        withAnimation { isAuthenticating = true }
        Task {
            defer { withAnimation { isAuthenticating = false } }
            await userWantsToAuthenticate(discoveryResult: discoveryResult)
        }
    }
    
    private func userWantsToAuthenticate(discoveryResult: KeycloakServerDiscoveryResult) async {
        do {
            try await actions.userWantsToAuthenticateOnKeycloakServer(
                self,
                keycloakConfiguration: model.keycloakConfiguration,
                magicLink: model.magicLink,
                discoveryResult: discoveryResult,
                isConfiguredFromMDM: model.isConfiguredFromMDM,
                isBindingExistingProfile: model.isBindingExistingProfile)
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
            if let error = error as? KeycloakManager.ObvError {
                switch error {
                case .invalidMagicLink:
                    isInvalidMagicLinkAlertShown = true
                    return
                default:
                    break
                }
            }
            errorForAlert = error
            isAlertShown = true
        }
    }
    
    
    private var authenticationFailureAlertTitle: String {
        if let errorForAlert {
            return String(localizedInThisBundle: "KEYCLOAK_AUTHENTICATION_FAILED_ALERT_\((errorForAlert as NSError).localizedDescription)")
        } else {
            return String(localizedInThisBundle: "KEYCLOAK_AUTHENTICATION_FAILED_ALERT")
        }
    }
    
    private var authenticateButtonTitle: LocalizedStringKey {
        return (model.magicLink == nil) ? "AUTHENTICATE" : "USE_MAGIC_LINK_BUTTON_TITLE"
    }
    
    private var authenticateButtonIcon: SystemIcon {
        return (model.magicLink == nil) ? .personCropCircleBadgeCheckmark : .wandAndSparkles
    }
    
    
    var body: some View {
        
        Group {
            switch discoveryStatus {
                
            case .toDiscover, .discovering:
                
                DiscoveringInProgressView(isConfiguredFromMDM: model.isConfiguredFromMDM)
                
            case .discoveryFailed, .discovered:
                
                ScrollView {
                    VStack {
                        
                        ObvHeaderView(title: "IDENTITY_PROVIDER".localizedInThisBundle,
                                      subtitle: nil)
                        
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
                
                if case .discovered(discoveryResult: let discoveryResult) = discoveryStatus {
                    
                    OlvidButtonNew {
                        authenticateButtonTapped(discoveryResult: discoveryResult)
                    } label: {
                        HStack {
                            if isAuthenticating { ProgressView() }
                            Label { Text(authenticateButtonTitle) } icon: { Image(systemIcon: authenticateButtonIcon) }
                        }
                    }
                    .disabled(isAuthenticating)
                    .padding()
                    .alert(authenticationFailureAlertTitle, isPresented: $isAlertShown) {
                        Button("OK".localizedInThisBundle, role: .cancel) { }
                    }
                    .alert(String(localizedInThisBundle: "INVALID_MAGIC_LINK_ALERT_TITLE"), isPresented: $isInvalidMagicLinkAlertShown, actions: {}) {
                        Text("INVALID_MAGIC_LINK_ALERT_MESSAGE")
                    }
                    
                }
                
            }
        }
        .task(discoverKeycloakServerIfRequired)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingKeycloakConfigurationDetails = true
                } label: {
                    Image(systemIcon: .questionmarkCircle)
                }
            }
            if model.showDismissButton {
                ToolbarItem(placement: .cancellationAction) {
                    ObvButtonWithCancelRole(action: { actions.userWantsToDismiss(self) })
                }
            }
        }
        .sheet(isPresented: $isShowingKeycloakConfigurationDetails) {
            NewKeycloakConfigurationDetailsView(model: .init(keycloakConfiguration: model.keycloakConfiguration))
                .presentationDetents([.medium])
                .presentationCornerRadiusOniOS16Dot4(ObvCardViewParameters.defaultCornerRadius)
                .presentationDragIndicator(.visible)
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
