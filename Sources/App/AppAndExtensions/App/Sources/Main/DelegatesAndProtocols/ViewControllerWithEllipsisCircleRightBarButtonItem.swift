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
import ObvUICoreData
import ObvSystemIcon


protocol ViewControllerWithEllipsisCircleRightBarButtonItem: UIViewController {}


extension ViewControllerWithEllipsisCircleRightBarButtonItem {
    
    func getConfiguredEllipsisCircleRightBarButtonItem(menu: UIMenu) -> UIBarButtonItem {
        let systemIcon: SystemIcon
        if #available(iOS 26, *) {
            systemIcon = .ellipsis
        } else {
            systemIcon = .ellipsisCircle
        }
        let ellipsisImage = UIImage(systemIcon: systemIcon)
        let ellipsisButton = UIBarButtonItem(
            title: "Menu",
            image: ellipsisImage,
            primaryAction: nil,
            menu: menu)
        return ellipsisButton
    }
    
}
