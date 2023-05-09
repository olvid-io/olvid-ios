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

import ObvUI
import UIKit


final class BlockBarButtonItem: UIBarButtonItem {
    
    private var actionHandler: (() -> Void)?

    
    convenience init(title: String?, style: UIBarButtonItem.Style, actionHandler: (() -> Void)?) {
        self.init(title: title, style: style, target: nil, action: #selector(barButtonItemPressed))
        self.target = self
        self.actionHandler = actionHandler
    }
    
    convenience init(image: UIImage?, style: UIBarButtonItem.Style, actionHandler: (() -> Void)?) {
        self.init(image: image, style: style, target: nil, action: #selector(barButtonItemPressed))
        self.target = self
        self.actionHandler = actionHandler
    }
    
    convenience init(barButtonSystemItem systemItem: UIBarButtonItem.SystemItem, actionHandler: (() -> Void)?) {
        self.init(barButtonSystemItem: systemItem, target: nil, action: #selector(barButtonItemPressed))
        self.target = self
        self.actionHandler = actionHandler
    }

    convenience init(systemIcon: SystemIcon, actionHandler: (() -> Void)?) {
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18.0, weight: .bold)
        let image = UIImage(systemIcon: systemIcon, withConfiguration: symbolConfiguration)
        self.init(image: image, style: .plain, target: nil, action: #selector(barButtonItemPressed))
        self.target = self
        self.actionHandler = actionHandler
    }
    
    static func forClosing(actionHandler: (() -> Void)?) -> UIBarButtonItem {
        return BlockBarButtonItem(barButtonSystemItem: .close, actionHandler: actionHandler)
    }

    @objc func barButtonItemPressed(sender: UIBarButtonItem) {
        actionHandler?()
    }
    
}
