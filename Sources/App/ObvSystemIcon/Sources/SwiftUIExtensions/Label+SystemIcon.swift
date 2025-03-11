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
  

import SwiftUI

public extension Label where Title == Text, Icon == Image {

    init?(_ titleKey: LocalizedStringKey, symbolIcon icon: any SymbolIcon) {
        if let customIcon = icon as? CustomIcon {
            self.init(titleKey, customIcon: customIcon)
        } else if let systemIcon = icon as? SystemIcon {
            self.init(titleKey, systemIcon: systemIcon)
        } else {            
            return nil
        }
    }
    
    init(_ titleKey: LocalizedStringKey, systemIcon icon: SystemIcon) {
        self.init(titleKey, systemImage: icon.name)
    }
    
    init(_ titleKey: LocalizedStringKey, customIcon icon: CustomIcon) {
        self.init(title: {
            Text(titleKey)
        }, icon: {
            Image(customIcon: icon)
        })
    }

}
