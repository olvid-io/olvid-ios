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
import ObvTypes
import UIKit
import ObvCrypto
import UI_SystemIcon
import ObvDesignSystem
import ObvSettings


public enum CircledInitialsConfiguration: Hashable {

    /// Possible tint adjustment modes for the avatar view
    ///
    /// - normal: A normal tint mode
    /// - disabled: A disabled tint mode, for example when a contact hasn't been synced
    public enum TintAdjustementMode {
        /// A normal tint mode
        case normal

        /// A disabled tint mode, for example when a contact hasn't been synced
        case disabled
    }
    
    
    public enum Photo: Equatable, Hashable {
        case url(url: URL?)
        case image(image: UIImage?)
    }

    
    case contact(initial: String, photo: Photo?, showGreenShield: Bool, showRedShield: Bool, cryptoId: ObvCryptoId, tintAdjustementMode: TintAdjustementMode)
    case group(photo: Photo?, groupUid: UID)
    case groupV2(photo: Photo?, groupIdentifier: Data, showGreenShield: Bool)
    case icon(_ icon: CircledInitialsIcon)
    case photo(photo: Photo)

    
    public var photo: UIImage? {
        let photo: Photo?
        switch self {
        case .contact(initial: _, photo: let _photo, showGreenShield: _, showRedShield: _, cryptoId: _, tintAdjustementMode: _):
            photo = _photo
        case .group(photo: let _photo, groupUid: _):
            photo = _photo
        case .groupV2(photo: let _photo, groupIdentifier: _, showGreenShield: _):
            photo = _photo
        case .icon:
            photo = nil
        case .photo(photo: let _photo):
            photo = _photo
        }
        guard let photo else { return nil }
        switch photo {
        case .url(let url):
            guard let url else { return nil }
            return UIImage(contentsOfFile: url.path)
        case .image(let image):
            return image
        }
    }
    
    
    public var circledInitialsIcon: CircledInitialsIcon {
        switch self {
        case .contact:
            return .person
        case .group, .groupV2:
            return .person3Fill
        case .icon(let icon):
            return icon
        case .photo:
            return .person
        }
    }
    
    
    public var showGreenShield: Bool {
        switch self {
        case .contact(initial: _, photo: _, showGreenShield: let showGreenShield, showRedShield: _, cryptoId: _, tintAdjustementMode: _):
            return showGreenShield
        case .groupV2(photo: _, groupIdentifier: _, showGreenShield: let showGreenShield):
            return showGreenShield
        case .group, .icon:
            return false
        case .photo:
            return false
        }
    }
    
    
    public var showRedShield: Bool {
        switch self {
        case .contact(initial: _, photo: _, showGreenShield: _, showRedShield: let showRedShield, cryptoId: _, tintAdjustementMode: _): return showRedShield
        default: return false
        }
    }
    
    
    public var initials: (text: String, cryptoId: ObvCryptoId)? {
        switch self {
        case .contact(initial: let initial, photo: _, showGreenShield: _, showRedShield: _, cryptoId: let cryptoId, tintAdjustementMode: _):
            guard let str = initial.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
            return (String(str), cryptoId)
        default: return nil
        }
    }

    
    public func replacingPhoto(with newPhoto: Photo?) -> Self {
        switch self {
        case .contact(let initial, _, let showGreenShield, let showRedShield, let cryptoId, let tintAdjustementMode):
            return .contact(initial: initial, photo: newPhoto, showGreenShield: showGreenShield, showRedShield: showRedShield, cryptoId: cryptoId, tintAdjustementMode: tintAdjustementMode)
        case .group(_, let groupUid):
            return .group(photo: newPhoto, groupUid: groupUid)
        case .groupV2(_, let groupIdentifier, let showGreenShield):
            return .groupV2(photo: newPhoto, groupIdentifier: groupIdentifier, showGreenShield: showGreenShield)
        case .icon(let icon):
            return .icon(icon)
        case .photo:
            guard let newPhoto else { return .icon(.person) }
            return .photo(photo: newPhoto)
        }
    }
    
    
    public func replacingInitials(with newInitials: String) -> Self {
        switch self {
        case .contact(_, let photo, let showGreenShield, let showRedShield, let cryptoId, let tintAdjustementMode):
            return .contact(initial: newInitials, photo: photo, showGreenShield: showGreenShield, showRedShield: showRedShield, cryptoId: cryptoId, tintAdjustementMode: tintAdjustementMode)
        case .group:
            return self
        case .groupV2:
            return self
        case .icon:
            return self
        case .photo:
            return self
        }
    }
    
    
    public var icon: SystemIcon {
        switch self {
        case .contact: return .person
        case .group, .groupV2: return .person3Fill
        case .icon(let icon): return icon.icon
        case .photo: return .person
        }
    }

    
    public func backgroundColor(appTheme: AppTheme, using style: IdentityColorStyle = ObvMessengerSettings.Interface.identityColorStyle) -> UIColor {
        switch self {
        case .contact(initial: _, photo: _, showGreenShield: _, showRedShield: _, cryptoId: let cryptoId, tintAdjustementMode: _):
            return appTheme.identityColors(for: cryptoId, using: style).background
        case .group(photo: _, groupUid: let groupUid):
            return appTheme.groupColors(forGroupUid: groupUid, using: style).background
        case .groupV2(photo: _, groupIdentifier: let groupIdentifier, showGreenShield: _):
            return appTheme.groupV2Colors(forGroupIdentifier: groupIdentifier).background
        case .icon:
            return appTheme.colorScheme.systemFill
        case .photo:
            return appTheme.colorScheme.systemFill
        }
    }


    public func foregroundColor(appTheme: AppTheme, using style: IdentityColorStyle = ObvMessengerSettings.Interface.identityColorStyle) -> UIColor {
        switch self {
        case .contact(initial: _, photo: _, showGreenShield: _, showRedShield: _, cryptoId: let cryptoId, tintAdjustementMode: _):
            return appTheme.identityColors(for: cryptoId, using: style).text
        case .group(photo: _, groupUid: let groupUid):
            return appTheme.groupColors(forGroupUid: groupUid, using: style).text
        case .groupV2(photo: _, groupIdentifier: let groupIdentifier, showGreenShield: _):
            return appTheme.groupV2Colors(forGroupIdentifier: groupIdentifier).text
        case .icon:
            return appTheme.colorScheme.secondaryLabel
        case .photo:
            return appTheme.colorScheme.secondaryLabel
        }
    }

}
