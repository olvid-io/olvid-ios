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
import ObvUIObvCircledInitials
import ObvSystemIcon
import ObvDesignSystem


extension CircledInitialsConfiguration {

    
    public enum ContentType {
        case none
        case icon(SystemIcon, UIColor)
        case initial(String, UIColor)
        case picture(UIImage)
    }
    
    public func contentType() -> ContentType {
        if let image = self.photo {
            return .picture(image)
        } else if let initials = self.initials {
            return .initial(initials.text, AppTheme.shared.identityColors(for: initials.cryptoId).text)
        } else if let iconInfo = self.iconInfo() {
            return .icon(iconInfo.icon, iconInfo.tintColor)
        } else {
            return .none
        }
    }
    
    
    private func iconInfo() -> (icon: SystemIcon, tintColor: UIColor)? {
        return (icon, foregroundColor(appTheme: AppTheme.shared))
    }
}
