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
  

import Foundation
import ObvTypes
import UIKit


extension UIViewController {
    
    /// Returns the scene activation state if a window can be found for this view controller's view.
    /// If no such window can be found (which means this view controller if off screen), this propery is `nil`.
    @MainActor
    var windowSceneActivationState: UIWindowScene.ActivationState? {
        guard let windowScene = self.view.window?.windowScene else { return nil }
        return windowScene.activationState
    }
    
}
