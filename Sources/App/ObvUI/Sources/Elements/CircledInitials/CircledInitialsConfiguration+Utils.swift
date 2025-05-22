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
    
//    public var icon: SystemIcon {
//        switch self {
//        case .contact: return .person
//        case .group, .groupV2: return .person3Fill
//        case .icon(let icon): return icon.icon
//        }
//    }
    
    
    public func contentType(using style: IdentityColorStyle) -> ContentType {
        if let image = self.photo {
            return .picture(image)
        } else if let initials = self.initials {
            return .initial(initials.text, AppTheme.shared.identityColors(for: initials.cryptoId, using: style).text)
        } else if let iconInfo = self.iconInfo(using: style) {
            return .icon(iconInfo.icon, iconInfo.tintColor)
        } else {
            return .none
        }
    }
    
    
//    public func backgroundColor(appTheme: AppTheme, using style: IdentityColorStyle = ObvMessengerSettings.Interface.identityColorStyle) -> UIColor {
//        switch self {
//        case .contact(initial: _, photo: _, showGreenShield: _, showRedShield: _, cryptoId: let cryptoId, tintAdjustementMode: _):
//            return appTheme.identityColors(for: cryptoId, using: style).background
//        case .group(photo: _, groupUid: let groupUid):
//            return appTheme.groupColors(forGroupUid: groupUid, using: style).background
//        case .groupV2(photo: _, groupIdentifier: let groupIdentifier, showGreenShield: _):
//            return appTheme.groupV2Colors(forGroupIdentifier: groupIdentifier).background
//        case .icon:
//            return appTheme.colorScheme.systemFill
//        }
//    }
//
//
//    public func foregroundColor(appTheme: AppTheme, using style: IdentityColorStyle = ObvMessengerSettings.Interface.identityColorStyle) -> UIColor {
//        switch self {
//        case .contact(initial: _, photo: _, showGreenShield: _, showRedShield: _, cryptoId: let cryptoId, tintAdjustementMode: _):
//            return appTheme.identityColors(for: cryptoId, using: style).text
//        case .group(photo: _, groupUid: let groupUid):
//            return appTheme.groupColors(forGroupUid: groupUid, using: style).text
//        case .groupV2(photo: _, groupIdentifier: let groupIdentifier, showGreenShield: _):
//            return appTheme.groupV2Colors(forGroupIdentifier: groupIdentifier).text
//        case .icon:
//            return appTheme.colorScheme.secondaryLabel
//        }
//    }


    private func iconInfo(using style: IdentityColorStyle) -> (icon: SystemIcon, tintColor: UIColor)? {
        return (icon, foregroundColor(appTheme: AppTheme.shared, using: style))
    }
}
