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

import UIKit
import SwiftUI
import ObvTypes


protocol NewIdentityProviderManualConfigurationViewControllerDelegate: AnyObject {
    func userWantsToValidateManualKeycloakConfiguration(controller: NewIdentityProviderManualConfigurationViewController, keycloakConfig: ObvKeycloakConfiguration) async
}


final class NewIdentityProviderManualConfigurationViewController: UIHostingController<NewIdentityProviderManualConfigurationView>, NewIdentityProviderManualConfigurationViewActionsProtocol {
    
    private weak var delegate: NewIdentityProviderManualConfigurationViewControllerDelegate?
    
    init(delegate: NewIdentityProviderManualConfigurationViewControllerDelegate) {
        let actions = NewIdentityProviderManualConfigurationViewActions()
        let view = NewIdentityProviderManualConfigurationView(actions: actions)
        super.init(rootView: view)
        self.delegate = delegate
        actions.delegate = self
    }
    
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    // NewIdentityProviderManualConfigurationViewActionsProtocol
    
    func userWantsToValidateManualKeycloakConfiguration(keycloakConfig: ObvKeycloakConfiguration) async {
        await delegate?.userWantsToValidateManualKeycloakConfiguration(controller: self, keycloakConfig: keycloakConfig)
    }

}


private final class NewIdentityProviderManualConfigurationViewActions: NewIdentityProviderManualConfigurationViewActionsProtocol {
    
    weak var delegate: NewIdentityProviderManualConfigurationViewActionsProtocol?
    
    func userWantsToValidateManualKeycloakConfiguration(keycloakConfig: ObvKeycloakConfiguration) async {
        await delegate?.userWantsToValidateManualKeycloakConfiguration(keycloakConfig: keycloakConfig)
    }

    
}
