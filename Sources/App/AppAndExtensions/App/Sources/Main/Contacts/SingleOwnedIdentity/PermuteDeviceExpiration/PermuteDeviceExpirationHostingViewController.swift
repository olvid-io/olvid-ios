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

import Foundation
import UIKit
import ObvTypes
import SwiftUI


protocol PermuteDeviceExpirationHostingViewControllerDelegate: PermuteDeviceExpirationViewActionsDelegate {}



final class PermuteDeviceExpirationHostingViewController: UIHostingController<PermuteDeviceExpirationView<PermuteDeviceExpirationViewModel>> {
    
    init(model: PermuteDeviceExpirationViewModel, delegate: PermuteDeviceExpirationHostingViewControllerDelegate) {
        let rootView = PermuteDeviceExpirationView(model: model, actions: delegate)
        super.init(rootView: rootView)
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}





struct PermuteDeviceExpirationViewModel: PermuteDeviceExpirationViewModelProtocol {

    let ownedCryptoId: ObvCryptoId
    let identifierOfDeviceToKeepActive: Data
    let nameOfDeviceToKeepActive: String
    let identifierOfDeviceWithoutExpiration: Data
    let nameOfDeviceWithoutExpiration: String

}
