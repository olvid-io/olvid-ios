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


public extension UIImage {

    convenience init?(symbolIcon: any SymbolIcon, withConfiguration configuration: UIImage.Configuration? = nil) {
        if let customIcon = symbolIcon as? CustomIcon {
            self.init(customIcon: customIcon, withConfiguration: configuration)
            return
        } else if let systemIcon = symbolIcon as? SystemIcon {
            self.init(systemIcon: systemIcon, withConfiguration: configuration)
            return
        }
        return nil
    }

    convenience init?(systemIcon: SystemIcon, withConfiguration configuration: UIImage.Configuration? = nil) {
        self.init(systemName: systemIcon.name, withConfiguration: configuration)
    }
    
    convenience init?(customIcon: CustomIcon, withConfiguration configuration: UIImage.Configuration? = nil) {
        self.init(named: customIcon.name, in: Bundle(for: LocalizableClassForObvSystemIconBundle.self), with: configuration)
    }

}
