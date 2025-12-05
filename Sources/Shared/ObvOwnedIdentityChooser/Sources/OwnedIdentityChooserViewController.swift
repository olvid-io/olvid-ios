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
import ObvDesignSystem



public final class OwnedIdentityChooserViewController: UIHostingController<OwnedIdentityChooserView> {
    
    private let callbackOnViewDidDisappear: (() -> Void)?
    
    public init(currentOwnedCryptoId: ObvCryptoId, actions: OwnedIdentityChooserViewActionsProtocol, dataSource: OwnedIdentityChooserViewDataSource, avatarViewDataSource: ObvAvatarViewDataSource, configuration: OwnedIdentityChooserViewConfiguration, callbackOnViewDidDisappear: (() -> Void)?, toggleToDismiss: Binding<Bool>) {
        self.callbackOnViewDidDisappear = callbackOnViewDidDisappear
        let rootView = OwnedIdentityChooserView(
            currentOwnedCryptoId: currentOwnedCryptoId,
            actions: actions,
            dataSource: dataSource,
            avatarViewDataSource: avatarViewDataSource,
            configuration: configuration,
            toggleToDismiss: toggleToDismiss)
        super.init(rootView: rootView)
    }
    
    deinit {
        debugPrint("Denit OwnedIdentityChooserViewController")
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
 
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        callbackOnViewDidDisappear?()
    }
    
}
