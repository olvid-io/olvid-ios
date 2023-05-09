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
  

import Foundation
import UIKit


// MARK: - CircledInitialsConfiguration
public enum CircledInitialsConfiguration: Hashable {
    public enum ContentType {
        case none
        case icon(SystemIcon, UIColor)
        case initial(String, UIColor)
        case picture(UIImage)
    }
    
    case contact(initial: String, photoURL: URL?, showGreenShield: Bool, showRedShield: Bool, colors: (background: UIColor, text: UIColor))
    case group(photoURL: URL?, colors: (background: UIColor, text: UIColor))
    case icon(_ icon: CircledInitialsIcon)

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .contact(initial: let initial, photoURL: let photoURL, showGreenShield: let showGreenShield, showRedShield: let showRedShield, colors: let colors):
            hasher.combine(initial)
            hasher.combine(photoURL)
            hasher.combine(showGreenShield)
            hasher.combine(showRedShield)
            hasher.combine(colors.text)
            hasher.combine(colors.background)
        case .group(photoURL: let photoURL, colors: let colors):
            hasher.combine(photoURL)
            hasher.combine(colors.text)
            hasher.combine(colors.background)
        case .icon(icon: let icon):
            hasher.combine(icon)
        }
    }

    public static func == (lhs: CircledInitialsConfiguration, rhs: CircledInitialsConfiguration) -> Bool {
        lhs.hashValue == rhs.hashValue
    }

    public func backgroundColor(appTheme: AppTheme) -> UIColor {
        switch self {
        case .contact(_, _, _, _, let colors), .group(_, let colors):
            return colors.background
        case .icon:
            return appTheme.colorScheme.systemFill
        }
    }

    public func foregroundColor(appTheme: AppTheme) -> UIColor {
        switch self {
        case .contact(_, _, _, _, let colors), .group(_, let colors):
            return colors.text
        case .icon:
            return appTheme.colorScheme.secondaryLabel
        }
    }

    public var icon: SystemIcon? {
        switch self {
        case .contact: return nil
        case .group: return .person3Fill
        case .icon(let icon): return icon.icon
        }
    }

    public var photo: UIImage? {
        let url: URL?
        switch self {
        case .contact(initial: _, photoURL: let photoURL, showGreenShield: _, showRedShield: _, colors: _):
            url = photoURL
        case .group(photoURL: let photoURL, colors: _):
            url = photoURL
        case .icon:
            url = nil
        }
        guard let url = url else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    
    public var contentType: ContentType {
        if let image = self.photo {
            return .picture(image)
        } else if let initials = self.initials {
            return .initial(initials.text, initials.color)
        } else if let iconInfo = self.iconInfo {
            return .icon(iconInfo.icon, iconInfo.tintColor)
        } else {
            return .none
        }
    }
    
    public var showGreenShield: Bool {
        switch self {
        case .contact(initial: _, photoURL: _, showGreenShield: let showGreenShield, showRedShield: _, colors: _): return showGreenShield
        default: return false
        }
    }
    
    public var showRedShield: Bool {
        switch self {
        case .contact(initial: _, photoURL: _, showGreenShield: _, showRedShield: let showRedShield, colors: _): return showRedShield
        default: return false
        }
    }
    
    fileprivate var initials: (text: String, color: UIColor)? {
        switch self {
        case .contact(initial: let initial, photoURL: _, showGreenShield: _, showRedShield: _, colors: let colors):
            guard let str = initial.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
            return (String(str), colors.text)
        default: return nil
        }
    }
    
    fileprivate var iconInfo: (icon: SystemIcon, tintColor: UIColor)? {
        guard let icon else { return nil }
        return (icon, foregroundColor(appTheme: AppTheme.shared))
    }
}
