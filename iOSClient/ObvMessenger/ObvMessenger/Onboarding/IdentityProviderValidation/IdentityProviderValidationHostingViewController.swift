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

import AppAuth
import JWS
import ObvUI
import ObvTypes
import SwiftUI
import UI_SystemIcon
import UI_SystemIcon_SwiftUI


protocol IdentityProviderValidationHostingViewControllerDelegate: AnyObject {
    func newKeycloakUserDetailsAndStuff(_ keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff, keycloakState: ObvKeycloakState) async
    func userWantsToRestoreBackup() async
}

final class IdentityProviderValidationHostingViewController: UIHostingController<IdentityProviderValidationHostingView> {
 
    private let store: IdentityProviderValidationHostingViewStore
    
    init(keycloakConfig: KeycloakConfiguration, isConfiguredFromMDM: Bool, delegate: IdentityProviderValidationHostingViewControllerDelegate) {
        let store = IdentityProviderValidationHostingViewStore(keycloakConfig: keycloakConfig, isConfiguredFromMDM: isConfiguredFromMDM)
        let view = IdentityProviderValidationHostingView(store: store)
        self.store = store
        super.init(rootView: view)
        store.delegate = delegate
    }
 
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = store.isConfiguredFromMDM ? nil : Strings.title
        navigationItem.largeTitleDisplayMode = .never
        
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let questionmarkCircleImage = UIImage(systemIcon: .questionmarkCircle, withConfiguration: symbolConfiguration)
        let questionmarkCircleButton = UIBarButtonItem(image: questionmarkCircleImage, style: UIBarButtonItem.Style.plain, target: self, action: #selector(questionmarkCircleButtonTapped))
        navigationItem.rightBarButtonItem = questionmarkCircleButton
        
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.barStyle = .black
        navigationController?.navigationBar.tintColor = .white
    }
    
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.barStyle = .default
        navigationController?.navigationBar.tintColor = .systemBlue
    }
    
    
    @objc func questionmarkCircleButtonTapped() {
        let view = KeycloakConfigurationDetailsView(keycloakConfig: store.keycloakConfig)
        let vc = UIHostingController(rootView: view)
        if #available(iOS 15, *) {
            vc.sheetPresentationController?.detents = [.medium(), .large()]
            vc.sheetPresentationController?.preferredCornerRadius = 16.0
            vc.sheetPresentationController?.prefersGrabberVisible = true
        }
        present(vc, animated: true)
    }
    
    private struct Strings {
        static let title = NSLocalizedString("IDENTITY_PROVIDER", comment: "")
    }

}


final class IdentityProviderValidationHostingViewStore: ObservableObject {
    
    fileprivate let keycloakConfig: KeycloakConfiguration
    fileprivate let isConfiguredFromMDM: Bool

    fileprivate var delegate: IdentityProviderValidationHostingViewControllerDelegate?
    
    // Nil while validating
    @Published fileprivate var validationStatus: ValidationStatus

    @Published fileprivate var isAlertPresented = false
    @Published fileprivate var alertType = AlertType.none
    
    init(keycloakConfig: KeycloakConfiguration, isConfiguredFromMDM: Bool) {
        self.keycloakConfig = keycloakConfig
        self.isConfiguredFromMDM = isConfiguredFromMDM
        self.validationStatus = .validating
    }
    
    fileprivate enum AlertType {
        case userAuthenticationFailed
        case badKeycloakServerResponse
        case none // Dummy type
    }
    
    enum ValidationStatus {
        case validating
        case validationFailed
        case validated(keycloakServerKeyAndConfig: (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration))
        
        var isValidated: Bool {
            switch self {
            case .validated: return true
            default: return false
            }
        }
    }
    
    @MainActor
    fileprivate func userWantsToValidateDisplayedServer() {
        assert(Thread.isMainThread)
        switch validationStatus {
        case .validating:
            break
        case .validationFailed, .validated:
            return // Already validated, happens typically when the user comes back to this view after a successfull authentication
        }
        Task {
            let keycloakServerKeyAndConfig: (ObvJWKSet, OIDServiceConfiguration)
            do {
                keycloakServerKeyAndConfig = try await KeycloakManagerSingleton.shared.discoverKeycloakServer(for: keycloakConfig.serverURL)
            } catch {
                assert(Thread.isMainThread)
                withAnimation { validationStatus = .validationFailed }
                return
            }
            assert(Thread.isMainThread)
            withAnimation { validationStatus = .validated(keycloakServerKeyAndConfig: keycloakServerKeyAndConfig) }
        }
    }

    
    @MainActor
    fileprivate func userWantsToAuthenticate(keycloakServerKeyAndConfig: (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration)) async {
        do {
            let authState = try await KeycloakManagerSingleton.shared.authenticate(configuration: keycloakServerKeyAndConfig.serviceConfig,
                                                                                   clientId: keycloakConfig.clientId,
                                                                                   clientSecret: keycloakConfig.clientSecret,
                                                                                   ownedCryptoId: nil)
            assert(Thread.isMainThread)
            await getOwnedDetailsAfterSucessfullAuthentication(keycloakServerKeyAndConfig: keycloakServerKeyAndConfig, authState: authState)
        } catch {
            assert(Thread.isMainThread)
            alertType = .userAuthenticationFailed
            isAlertPresented = true
            return
        }
    }
    
    
    @MainActor
    private func getOwnedDetailsAfterSucessfullAuthentication(keycloakServerKeyAndConfig: (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration), authState: OIDAuthState) async {
        
        assert(Thread.isMainThread)
        
        let keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff
        let keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff
        do {
            (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff) = try await KeycloakManagerSingleton.shared.getOwnDetails(keycloakServer: keycloakConfig.serverURL,
                                                                                                                                       authState: authState,
                                                                                                                                       clientSecret: keycloakConfig.clientSecret,
                                                                                                                                       jwks: keycloakServerKeyAndConfig.jwks,
                                                                                                                                       latestLocalRevocationListTimestamp: nil)
        } catch let error as KeycloakManager.GetOwnDetailsError {
            switch error {
            case .badResponse:
                alertType = .badKeycloakServerResponse
                isAlertPresented = true
            default:
                // We should be more specific
                alertType = .badKeycloakServerResponse
                isAlertPresented = true
            }
            return
        } catch {
            // We should be more specific
            alertType = .badKeycloakServerResponse
            isAlertPresented = true
            return
        }
        
        assert(Thread.isMainThread)

        if let minimumBuildVersion = keycloakServerRevocationsAndStuff.minimumIOSBuildVersion {
            guard ObvMessengerConstants.bundleVersionAsInt >= minimumBuildVersion else {
                ObvMessengerInternalNotification.installedOlvidAppIsOutdated(presentingViewController: nil)
                    .postOnDispatchQueue()
                return
            }
        }

        guard let rawAuthState = try? authState.serialize() else {
            alertType = .badKeycloakServerResponse
            isAlertPresented = true
            return
        }
        let keycloakState = ObvKeycloakState(
            keycloakServer: keycloakConfig.serverURL,
            clientId: keycloakConfig.clientId,
            clientSecret: keycloakConfig.clientSecret,
            jwks: keycloakServerKeyAndConfig.jwks,
            rawAuthState: rawAuthState,
            signatureVerificationKey: keycloakUserDetailsAndStuff.serverSignatureVerificationKey,
            latestLocalRevocationListTimestamp: nil,
            latestGroupUpdateTimestamp: nil)
        Task { await delegate?.newKeycloakUserDetailsAndStuff(keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: keycloakServerRevocationsAndStuff, keycloakState: keycloakState) }
    }

    func userWantsToRestoreBackup() {
        Task { await delegate?.userWantsToRestoreBackup() }
    }

}


struct IdentityProviderValidationHostingView: View {
    
    @ObservedObject var store: IdentityProviderValidationHostingViewStore
    
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            Image("SplashScreenBackground")
                .resizable()
                .edgesIgnoringSafeArea(.all)
            VStack(spacing: 0) {
                switch store.validationStatus {
                case .validating:
                    ObvActivityIndicator(isAnimating: .constant(true), style: .large, color: .white)
                    if store.isConfiguredFromMDM {
                        HStack {
                            Spacer()
                            Text("VALIDATING_ENTERPRISE_CONFIGURATION")
                                .font(.system(.subheadline, design: .default))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.top, 16)
                    }
                case .validationFailed, .validated:
                    if store.isConfiguredFromMDM {
                        Image("logo")
                            .resizable()
                            .scaledToFit()
                            .padding(.horizontal)
                            .padding(.bottom, 16)
                            .frame(maxWidth: 300)
                            .transition(.scale)
                    }
                    ScrollView {
                        HStack {
                            Spacer()
                            BigCircledSystemIconView(systemIcon: store.validationStatus.isValidated ? .checkmark : .xmark,
                                                     backgroundColor: store.validationStatus.isValidated ? .green : .red)
                            Spacer()
                        }
                        .padding(.top, 32)
                        .padding(.bottom, 32)
                        Text(store.validationStatus.isValidated ? "IDENTITY_PROVIDER_CONFIGURED_SUCCESS" : "IDENTITY_PROVIDER_CONFIGURED_FAILURE")
                            .font(.system(.body, design: .default))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    if case .validated(keycloakServerKeyAndConfig: let keycloakServerKeyAndConfig) = store.validationStatus {
                        if store.validationStatus.isValidated {
                            VStack {
                                if store.isConfiguredFromMDM {
                                    OlvidButton(style: colorScheme == .dark ? .standard : .standardAlt,
                                                title: Text("Restore a backup"),
                                                systemIcon: .folderCircle,
                                                action: store.userWantsToRestoreBackup)
                                }
                                OlvidButton(style: colorScheme == .dark ? .blue : .white,
                                            title: Text("AUTHENTICATE"),
                                            systemIcon: .personCropCircleBadgeCheckmark,
                                            action: { Task { await store.userWantsToAuthenticate(keycloakServerKeyAndConfig: keycloakServerKeyAndConfig) } })
                                    .padding(.bottom, 16)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .onAppear {
            store.userWantsToValidateDisplayedServer()
        }
        .alert(isPresented: $store.isAlertPresented) {
            switch store.alertType {
            case .userAuthenticationFailed:
                return Alert(title: Text("AUTHENTICATION_FAILED"),
                             message: Text("CHECK_IDENTITY_SERVER_PARAMETERS"),
                             dismissButton: Alert.Button.default(Text("Ok"))
                )
            case .badKeycloakServerResponse:
                return Alert(title: Text("BAD_KEYCLOAK_SERVER_RESPONSE"),
                             dismissButton: Alert.Button.default(Text("Ok"))
                )
            case .none:
                assertionFailure()
                return Alert(title: Text("AUTHENTICATION_FAILED"),
                             message: Text("CHECK_IDENTITY_SERVER_PARAMETERS"),
                             dismissButton: Alert.Button.default(Text("Ok"))
                )
            }
        }
    }
    
}


fileprivate struct KeycloakConfigurationDetailsView: View {
    
    let keycloakConfig: KeycloakConfiguration
    
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
                
            VStack {

                List {
                    Section {
                        ObvSimpleListItemView(
                            title: Text("SERVER_URL"),
                            value: keycloakConfig.serverURL.absoluteString)
                        ObvSimpleListItemView(
                            title: Text("CLIENT_ID"),
                            value: keycloakConfig.clientId)
                        ObvSimpleListItemView(
                            title: Text("CLIENT_SECRET"),
                            value: keycloakConfig.clientSecret)
                    } header: {
                        Text("IDENTITY_PROVIDER_CONFIGURATION")
                    }
                    
                }
                .padding(.bottom, 16)

                OlvidButton(style: .blue,
                            title: Text("Back"),
                            systemIcon: .arrowshapeTurnUpBackwardFill,
                            action: { presentationMode.wrappedValue.dismiss() })
                    .padding(.vertical)
                    .padding(.horizontal, 16)

                
            }
            .padding(.top, 16)

        }
    }
    
}





fileprivate struct BigCircledSystemIconView: View {
    
    let systemIcon: SystemIcon
    let backgroundColor: Color
    
    var body: some View {
        Image(systemIcon: systemIcon)
            .font(Font.system(size: 50, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
            .padding(32)
            .background(Circle().fill(backgroundColor))
            .padding()
            .background(Circle().fill(backgroundColor.opacity(0.2)))
    }
    
}
