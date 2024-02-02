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

import UIKit
import SwiftUI
import JWS
import AppAuth


protocol IdentityProviderValidationViewControllerDelegate: AnyObject {
    func discoverKeycloakServer(controller: IdentityProviderValidationViewController, keycloakServerURL: URL) async throws -> (jwks: JWS.ObvJWKSet, serviceConfig: OIDServiceConfiguration)
    func userWantsToAuthenticateOnKeycloakServer(controller: IdentityProviderValidationViewController, keycloakConfiguration: Onboarding.KeycloakConfiguration, isConfiguredFromMDM: Bool, keycloakServerKeyAndConfig: (jwks: JWS.ObvJWKSet, serviceConfig: OIDServiceConfiguration)) async throws
}


final class IdentityProviderValidationViewController: UIHostingController<IdentityProviderValidationView>, IdentityProviderValidationViewActionsProtocol {
    
    private weak var delegate: IdentityProviderValidationViewControllerDelegate?
    
    private let keycloakConfiguration: Onboarding.KeycloakConfiguration
    
    init(model: IdentityProviderValidationView.Model, delegate: IdentityProviderValidationViewControllerDelegate) {
        self.keycloakConfiguration = model.keycloakConfiguration
        let actions = IdentityProviderValidationViewActions()
        let view = IdentityProviderValidationView(model: model, actions: actions)
        super.init(rootView: view)
        self.delegate = delegate
        actions.delegate = self
    }
    
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation(animated: false)
    }
    
    
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        configureNavigation(animated: animated)
    }

    
    private func configureNavigation(animated: Bool) {
        // If Olvid is configured via an MDM, we don't want to allow the user to go back.
        // Otherwise, we do.
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.setNavigationBarHidden(false, animated: animated)
        // Configure a bar button item allowing to show the keycloak configuration details
        let image = UIImage(systemIcon: .questionmarkCircle)
        let barButton = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(questionmarkCircleButtonTapped))
        navigationItem.rightBarButtonItem = barButton
    }
    
    
    @objc func questionmarkCircleButtonTapped() {
        let view = NewKeycloakConfigurationDetailsView(model: .init(keycloakConfiguration: self.keycloakConfiguration))
        let vc = UIHostingController(rootView: view)
        vc.sheetPresentationController?.detents = [.medium(), .large()]
        vc.sheetPresentationController?.preferredCornerRadius = 16.0
        vc.sheetPresentationController?.prefersGrabberVisible = true
        present(vc, animated: true)
    }


    
    // IdentityProviderValidationViewActionsProtocol
    
    func discoverKeycloakServer(keycloakServerURL: URL) async throws -> (jwks: JWS.ObvJWKSet, serviceConfig: OIDServiceConfiguration) {
        guard let delegate else { throw ObvError.theDelegateIsNotSet }
        return try await delegate.discoverKeycloakServer(controller: self, keycloakServerURL: keycloakServerURL)
    }
    
    
    func userWantsToAuthenticateOnKeycloakServer(keycloakConfiguration: Onboarding.KeycloakConfiguration, isConfiguredFromMDM: Bool, keycloakServerKeyAndConfig: (jwks: JWS.ObvJWKSet, serviceConfig: OIDServiceConfiguration)) async throws {
        guard let delegate else { throw ObvError.theDelegateIsNotSet }
        return try await delegate.userWantsToAuthenticateOnKeycloakServer(
            controller: self,
            keycloakConfiguration: keycloakConfiguration,
            isConfiguredFromMDM: isConfiguredFromMDM,
            keycloakServerKeyAndConfig: keycloakServerKeyAndConfig)
    }
    
    
    // Errors
    
    enum ObvError: Error {
        case theDelegateIsNotSet
    }

}


private final class IdentityProviderValidationViewActions: IdentityProviderValidationViewActionsProtocol {
        
    weak var delegate: IdentityProviderValidationViewActionsProtocol?
    
    func discoverKeycloakServer(keycloakServerURL: URL) async throws -> (jwks: JWS.ObvJWKSet, serviceConfig: OIDServiceConfiguration) {
        guard let delegate else { throw ObvError.theDelegateIsNotSet }
        return try await delegate.discoverKeycloakServer(keycloakServerURL: keycloakServerURL)
    }
    
    func userWantsToAuthenticateOnKeycloakServer(keycloakConfiguration: Onboarding.KeycloakConfiguration, isConfiguredFromMDM: Bool, keycloakServerKeyAndConfig: (jwks: JWS.ObvJWKSet, serviceConfig: OIDServiceConfiguration)) async throws {
        guard let delegate else { throw ObvError.theDelegateIsNotSet }
        try await delegate.userWantsToAuthenticateOnKeycloakServer(keycloakConfiguration: keycloakConfiguration, isConfiguredFromMDM: isConfiguredFromMDM, keycloakServerKeyAndConfig: keycloakServerKeyAndConfig)
    }

    enum ObvError: Error {
        case theDelegateIsNotSet
    }
    
}
