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


extension UIViewController {
    
    func defaultMenu() -> UIMenu {
        var menuElements: [UIMenuElement] = [
            UIAction(title: NSLocalizedString("SHOW_SETTINGS_SCREEN", comment: ""),
                     image: UIImage(systemIcon: .gear)) { _ in
                         ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .settings)
                             .postOnDispatchQueue()
                     },
        ]
        
        if #available(iOS 17.0, *) {
            menuElements.append(UIAction(title: NSLocalizedString("STORAGE_MANAGEMENT", comment: ""),
                                         image: UIImage(systemIcon: .externaldriveFill)) { _ in
                ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .storageManagementSettings)
                    .postOnDispatchQueue()
            })
        }
        let menu = UIMenu(title: "", children: menuElements)
        return menu
    }

}
