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

extension UIImage {

    /** Implements iOS13 constructor with SF Symbols for previous iOS  version

     # Requirements
     SF_`systemName`  must exists in assets.xcassets

     # Adding new symbols
     New SF_symbols can be added into project using nice application `HappyCoding for Xcode` from The app store
     */
    static func makeSystemImage(systemName: String, size: CGFloat?) -> UIImage? {
        if #available(iOS 13, *) {
            if let size = size {
                let largeConfig = UIImage.SymbolConfiguration(pointSize: size)
                return UIImage(systemName: systemName, withConfiguration: largeConfig)
            } else {
                return UIImage(systemName: systemName)
            }
        } else {
            return UIImage(named: "SF_\(systemName)")?.withRenderingMode(.alwaysTemplate)
        }

    }


}

extension UIBarButtonItem {

    static func forClosing(target: Any?, action: Selector?) -> UIBarButtonItem {
        if #available(iOS 13, *) {
            return UIBarButtonItem(barButtonSystemItem: .close, target: target, action: action)
        } else {
            return UIBarButtonItem(barButtonSystemItem: .done, target: target, action: action)
        }
    }

    /** Implements iOS13 constructor with SF Symbols for previous iOS  version

     # Requirements
     SF_`systemName`  must exists in assets.xcassets

     # Adding new symbols
     New SF_symbols can be added into project using nice application `HappyCoding for Xcode` from The app store
     */
    convenience init(systemName: String, style: UIBarButtonItem.Style, target: Any?, action: Selector? = nil) {
        let image = UIImage.makeSystemImage(systemName: systemName, size: 22)
        let button = UIButton(type: .custom)
        button.setImage(image, for: .normal)
        self.init(customView: button)
        self.style = style

        if let action = action {
            button.addTarget(target, action: action, for: .touchUpInside)
        }

        if #available(iOS 13.0, *) {

        } else {
            button.frame = CGRect(x: 0.0, y: 0.0, width: 20, height: 20)

            let currWidth = self.customView?.widthAnchor.constraint(equalToConstant: 24)
            currWidth?.isActive = true
            let currHeight = self.customView?.heightAnchor.constraint(equalToConstant: 24)
            currHeight?.isActive = true
        }
    }

    @available(iOS 14.0, *)
    convenience init(systemName: String, style: UIBarButtonItem.Style, title: String, actions: [UIAction]) {
        let image = UIImage.makeSystemImage(systemName: systemName, size: 22)
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
