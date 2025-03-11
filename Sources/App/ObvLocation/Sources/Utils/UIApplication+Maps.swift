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
import ObvUICoreData

extension UIApplication {
    
    @MainActor
    public func userWantsToOpenMapAt(latitude: Double, longitude: Double, address: String?, within viewController: UIViewController) async {
        guard !MapOptions.availableApps.isEmpty else { return } // No App available for opening a map
        
        if MapOptions.availableApps.count == 1, let app = MapOptions.availableApps.first { // Only one app available, we open the app directly.
            app.openAt(latitude: latitude, longitude: longitude, address: address)
        } else { // There is more than one, we ask user which app he wants to use.
            let alert = MapOptions.mapAlertControllerAt(latitude: latitude, longitude: longitude, address: address)
            
            viewController.present(alert, animated: true)
        }
    }
}
