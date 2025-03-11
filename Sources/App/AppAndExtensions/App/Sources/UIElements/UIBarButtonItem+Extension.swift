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

import UIKit

extension UIBarButtonItem {

    static func forClosing(target: Any?, action: Selector?) -> UIBarButtonItem {
        return UIBarButtonItem(barButtonSystemItem: .close, target: target, action: action)
    }

    @available(iOS 14.0, *)
    convenience init(image: UIImage?, style: UIBarButtonItem.Style, title: String, actions: [UIAction]) {
        let button = UIButton(type: .custom)
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(title: title, children: actions)

        button.setImage(image, for: .normal)
        self.init(customView: button)
        self.style = style
    }

    static func space() -> UIBarButtonItem {
        let space = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.fixedSpace, target: nil, action: nil)
        space.width = -16
        return space
    }

}
