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


public final class AppTheme {
    
    public static let shared = AppTheme(with: .edmond)
    
    public static let appleBadgeRedColor = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
    public static let appleTableSeparatorColor = UIColor { (traitCollection: UITraitCollection) in
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor(red: 0.24, green: 0.24, blue: 0.26, alpha: 1.0)
        } else {
            return UIColor(red: 0.78, green: 0.78, blue: 0.8, alpha: 1.0)

        }
    }
    
    public static let appleTableSeparatorHeight: CGFloat = 0.33
    
    public enum Name {
        case edmond
    }
    
    private let name: Name
    
    public let colorScheme: AppThemeSemanticColorScheme
    public let images: AppThemeImages = AppThemeImages()
    public let icons: AppThemeIcons = AppThemeIcons()
    
    private init(with name: Name) {
        self.name = name
        self.colorScheme = AppThemeSemanticColorScheme(with: name)
        self.adaptTabBarAppearance()
    }
    
    public func restoreDefaultNavigationBarAppearance() {
        let navigationBarAppearance = UINavigationBar.appearance()
        navigationBarAppearance.isTranslucent = true
        navigationBarAppearance.barTintColor = nil
        navigationBarAppearance.tintColor = nil
    }
    
    public func adaptTabBarAppearance() {

        UINavigationBar.appearance(whenContainedInInstancesOf: [UIDocumentBrowserViewController.self]).tintColor = nil // We cannot customize the background color of a UIDocumentBrowserViewController, so we set back the button color
    }

}

