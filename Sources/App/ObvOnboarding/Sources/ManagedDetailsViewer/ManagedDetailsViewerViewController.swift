/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvTypes
import ObvKeycloakManager


protocol ManagedDetailsViewerViewControllerDelegate: AnyObject {
    func userWantsToCreateProfileOrBindExistingProfileWithIdentityProvider(_ vc: ManagedDetailsViewerViewController, bindExistingOrCreate: BindExistingOrCreateNewProfile, keycloakDetails: (keycloakUserDetailsAndStuff: ObvKeycloakManager.KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: ObvKeycloakManager.KeycloakServerRevocationsAndStuff), keycloakState: ObvKeycloakState) async
}

enum BindExistingOrCreateNewProfile {
    case bindExistingProfile(existingOwnedCryptoIdToBind: ObvTypes.ObvCryptoId)
    case createNewProfile
}

final class ManagedDetailsViewerViewController: UIHostingController<ManagedDetailsViewerView>, ManagedDetailsViewerViewActionsProtocol {
    
    private weak var delegate: ManagedDetailsViewerViewControllerDelegate?
    
    /// The following value is not used in this VC (or in the View). We store it so as to send them back in the delegate method
    private let keycloakState: ObvKeycloakState
    
    init(model: ManagedDetailsViewerView.Model, keycloakState: ObvKeycloakState, delegate: ManagedDetailsViewerViewControllerDelegate) {
        self.keycloakState = keycloakState
        let actions = ManagedDetailsViewerViewActions()
        let view = ManagedDetailsViewerView(actions: actions, model: model)
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
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // ManagedDetailsViewerViewActionsProtocol
    
    @MainActor
    func userWantsToCreateProfileWithDetailsFromIdentityProvider(keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff)) async {
        await delegate?.userWantsToCreateProfileOrBindExistingProfileWithIdentityProvider(
            self,
            bindExistingOrCreate: .createNewProfile,
            keycloakDetails: keycloakDetails,
            keycloakState: keycloakState)
    }
    
    func userWantsToBindExistingProfileWithKeycloak(existingOwnedCryptoIdToBind: ObvTypes.ObvCryptoId, keycloakDetails: (keycloakUserDetailsAndStuff: ObvKeycloakManager.KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: ObvKeycloakManager.KeycloakServerRevocationsAndStuff)) async {
        await delegate?.userWantsToCreateProfileOrBindExistingProfileWithIdentityProvider(
            self,
            bindExistingOrCreate: .bindExistingProfile(existingOwnedCryptoIdToBind: existingOwnedCryptoIdToBind),
            keycloakDetails: keycloakDetails,
            keycloakState: keycloakState)
    }
    
}




private final class ManagedDetailsViewerViewActions: ManagedDetailsViewerViewActionsProtocol {
        
    weak var delegate: ManagedDetailsViewerViewActionsProtocol?
    
    func userWantsToCreateProfileWithDetailsFromIdentityProvider(keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff)) async {
        await delegate?.userWantsToCreateProfileWithDetailsFromIdentityProvider(keycloakDetails: keycloakDetails)
    }
    
    func userWantsToBindExistingProfileWithKeycloak(existingOwnedCryptoIdToBind: ObvTypes.ObvCryptoId, keycloakDetails: (keycloakUserDetailsAndStuff: ObvKeycloakManager.KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: ObvKeycloakManager.KeycloakServerRevocationsAndStuff)) async {
        await delegate?.userWantsToBindExistingProfileWithKeycloak(existingOwnedCryptoIdToBind: existingOwnedCryptoIdToBind, keycloakDetails: keycloakDetails)
    }

}
