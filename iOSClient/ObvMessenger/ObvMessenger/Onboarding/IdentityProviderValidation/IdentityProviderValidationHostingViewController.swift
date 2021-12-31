/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import JWS
import AppAuth
import ObvTypes

protocol IdentityProviderValidationHostingViewControllerDelegate: AnyObject {
    func newKeycloakUserDetailsAndStuff(_ keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff)
    func newKeycloakState(_ keycloakState: ObvKeycloakState)
}

@available(iOS 13, *)
final class IdentityProviderValidationHostingViewController: UIHostingController<IdentityProviderValidationHostingView>, IdentityProviderValidationHostingViewStoreDelegate {
 
    weak var delegate: IdentityProviderValidationHostingViewControllerDelegate?
    private let keycloakConfig: KeycloakConfiguration
    
    init(keycloakConfig: KeycloakConfiguration, delegate: IdentityProviderValidationHostingViewControllerDelegate) {
        self.keycloakConfig = keycloakConfig
        let store = IdentityProviderValidationHostingViewStore(keycloakConfig: keycloakConfig)
        let view = IdentityProviderValidationHostingView(store: store)
        super.init(rootView: view)
        store.delegate = self
        self.delegate = delegate
    }
 
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Strings.title
        navigationItem.largeTitleDisplayMode = .never
        
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let questionmarkCircleImage = UIImage(systemIcon: .questionmarkCircle, withConfiguration: symbolConfiguration)
        let questionmarkCircleButton = UIBarButtonItem(image: questionmarkCircleImage, style: UIBarButtonItem.Style.plain, target: self, action: #selector(questionmarkCircleButtonTapped))
        navigationItem.rightBarButtonItem = questionmarkCircleButton
    }
    
    @objc func questionmarkCircleButtonTapped() {
        let view = KeycloakConfigurationDetailsView(keycloakConfig: keycloakConfig)
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

    // IdentityProviderValidationHostingViewStore
    
    func newKeycloakState(_ keycloakState: ObvKeycloakState) {
        delegate?.newKeycloakState(keycloakState)
    }

    func newKeycloakUserDetailsAndStuff(_ keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff) {
        delegate?.newKeycloakUserDetailsAndStuff(keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: keycloakServerRevocationsAndStuff)
    }

}


protocol IdentityProviderValidationHostingViewStoreDelegate: UIViewController {
    func newKeycloakUserDetailsAndStuff(_ keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff)
    func newKeycloakState(_ keycloakState: ObvKeycloakState)
}


@available(iOS 13, *)
final class IdentityProviderValidationHostingViewStore: ObservableObject {
    
    fileprivate let keycloakConfig: KeycloakConfiguration

    fileprivate var delegate: IdentityProviderValidationHostingViewStoreDelegate?
    
    // Nil while validating
    @Published fileprivate var validationStatus: ValidationStatus

    @Published fileprivate var isAlertPresented = false
    @Published fileprivate var alertType = AlertType.none
    
    init(keycloakConfig: KeycloakConfiguration) {
        self.keycloakConfig = keycloakConfig
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
    
    fileprivate func userWantsToValidateDisplayedServer() {
        assert(Thread.isMainThread)
        switch validationStatus {
        case .validating:
            break
        case .validationFailed, .validated:
            return // Already validated, happens typically when the user comes back to this view after a successfull authentication
        }
        KeycloakManager.shared.discoverKeycloakServer(for: keycloakConfig.serverURL) { result in
            DispatchQueue.main.async { [weak self] in
                switch result {
                case .success(let keycloakServerKeyAndConfig):
                    withAnimation {
                        self?.validationStatus = .validated(keycloakServerKeyAndConfig: keycloakServerKeyAndConfig)
                    }
                case .failure:
                    withAnimation {
                        self?.validationStatus = .validationFailed
                    }
                }
            }
        }
    }

    fileprivate func userWantsToAuthenticate(keycloakServerKeyAndConfig: (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration)) {
        assert(Thread.isMainThread)
        KeycloakManager.shared.authenticate(configuration: keycloakServerKeyAndConfig.serviceConfig,
                                            clientId: keycloakConfig.clientId,
                                            clientSecret: keycloakConfig.clientSecret,
                                            ownedCryptoId: nil) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .failure:
                    self?.alertType = .userAuthenticationFailed
                    self?.isAlertPresented = true
                case .success(let authState):
                    self?.getOwnedDetailsAfterSucessfullAuthentication(keycloakServerKeyAndConfig: keycloakServerKeyAndConfig, authState: authState)
                }
            }
        }
    }
    
    
    private func getOwnedDetailsAfterSucessfullAuthentication(keycloakServerKeyAndConfig: (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration), authState: OIDAuthState) {
        assert(Thread.isMainThread)
        KeycloakManager.shared.getOwnDetails(keycloakServer: keycloakConfig.serverURL,
                                             authState: authState,
                                             clientSecret: keycloakConfig.clientSecret,
                                             jwks: keycloakServerKeyAndConfig.jwks,
                                             latestLocalRevocationListTimestamp: nil) { result in
            DispatchQueue.main.async { [weak self] in
                guard let _self = self else { return }
                switch result {
                case .failure(let error):
                    switch error {
                    case .badResponse:
                        self?.alertType = .badKeycloakServerResponse
                        self?.isAlertPresented = true
                    default:
                        // We should be more specific
                        self?.alertType = .badKeycloakServerResponse
                        self?.isAlertPresented = true
                    }
                case .success(let (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff)):
                    
                    if let minimumBuildVersion = keycloakServerRevocationsAndStuff.minimumIOSBuildVersion {
                        guard ObvMessengerConstants.bundleVersionAsInt >= minimumBuildVersion else {
                            ObvMessengerInternalNotification.installedOlvidAppIsOutdated(presentingViewController: nil)
                                .postOnDispatchQueue()
                            return
                        }
                    }
                    
                    let rawAuthState = authState.serialize
                    let keycloakState = ObvKeycloakState(
                        keycloakServer: _self.keycloakConfig.serverURL,
                        clientId: _self.keycloakConfig.clientId,
                        clientSecret: _self.keycloakConfig.clientSecret,
                        jwks: keycloakServerKeyAndConfig.jwks,
                        rawAuthState: rawAuthState,
                        signatureVerificationKey: keycloakUserDetailsAndStuff.serverSignatureVerificationKey,
                        latestLocalRevocationListTimestamp: nil)
                    self?.delegate?.newKeycloakState(keycloakState)
                    self?.delegate?.newKeycloakUserDetailsAndStuff(keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: keycloakServerRevocationsAndStuff)
                }
            }
        }
    }

}


@available(iOS 13, *)
struct IdentityProviderValidationHostingView: View {
    
    @ObservedObject var store: IdentityProviderValidationHostingViewStore
    
    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .edgesIgnoringSafeArea(.all)
            VStack(spacing: 0) {
                switch store.validationStatus {
                case .validating:
                    ObvActivityIndicator(isAnimating: .constant(true), style: .large)
                case .validationFailed, .validated:
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
                        .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                    Spacer()
                    if case .validated(keycloakServerKeyAndConfig: let keycloakServerKeyAndConfig) = store.validationStatus {
                        if store.validationStatus.isValidated {
                            OlvidButton(style: .blue,
                                        title: Text("AUTHENTICATE"),
                                        systemIcon: .personCropCircleBadgeCheckmark,
                                        action: { store.userWantsToAuthenticate(keycloakServerKeyAndConfig: keycloakServerKeyAndConfig) })
                                .padding(.bottom, 16)
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


@available(iOS 13, *)
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
                            title: Text("BACK"),
                            systemIcon: .arrowshapeTurnUpBackwardFill,
                            action: { presentationMode.wrappedValue.dismiss() })
                    .padding(.vertical)
                    .padding(.horizontal, 16)

                
            }
            .padding(.top, 16)

        }
    }
    
}





@available(iOS 13, *)
fileprivate struct BigCircledSystemIconView: View {
    
    let systemIcon: ObvSystemIcon
    let backgroundColor: Color
    
    var body: some View {
        Image(systemIcon: systemIcon)
            .font(Font.system(size: 64, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
            .padding(32)
            .background(Circle().fill(backgroundColor))
            .padding()
            .background(Circle().fill(backgroundColor.opacity(0.2)))
    }
    
}
