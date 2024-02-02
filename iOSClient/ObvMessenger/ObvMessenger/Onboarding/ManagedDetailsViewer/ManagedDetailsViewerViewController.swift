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
import ObvTypes


protocol ManagedDetailsViewerViewControllerDelegate: AnyObject {
    func userWantsToCreateProfileWithDetailsFromIdentityProvider(controller: ManagedDetailsViewerViewController, keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff), keycloakState: ObvKeycloakState) async
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
        await delegate?.userWantsToCreateProfileWithDetailsFromIdentityProvider(
            controller: self,
            keycloakDetails: keycloakDetails,
            keycloakState: keycloakState)
    }
    
}




private final class ManagedDetailsViewerViewActions: ManagedDetailsViewerViewActionsProtocol {
    
    weak var delegate: ManagedDetailsViewerViewActionsProtocol?
    
    func userWantsToCreateProfileWithDetailsFromIdentityProvider(keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff)) async {
        await delegate?.userWantsToCreateProfileWithDetailsFromIdentityProvider(keycloakDetails: keycloakDetails)
    }
    
}
