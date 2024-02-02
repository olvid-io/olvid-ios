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
import ObvTypes
import ObvCrypto


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


// MARK: - Computing colors from identities

extension AppTheme {
        
    static let richterColors: [UIColor] = {
        var index = 0
        var colors = [UIColor]()
        while let color = UIColor(named: "RichterColor\(index)") {
            colors.append(color)
            index += 1
        }
        return colors
    }()
    

    //public func identityColors(for cryptoId: ObvCryptoId, using style: IdentityColorStyle = ObvMessengerSettings.Interface.identityColorStyle) -> (background: UIColor, text: UIColor) {
    public func identityColors(for cryptoId: ObvCryptoId, using style: IdentityColorStyle) -> (background: UIColor, text: UIColor) {
        switch style {
        case .hue:
            let hue = hueFromBytes(cryptoId.getIdentity())
            let text = UIColor(hue: hue, saturation: 0.46, brightness: 0.91, alpha: 1.0)
            let background = UIColor(hue: hue, saturation: 0.16, brightness: 0.98, alpha: 1.0)
            return (background, text)
        case .richter:
            let text = UIColor.white.withAlphaComponent(0.8)
            let background = richterColorFromBytes(cryptoId.getIdentity())
            return (background, text)
        }
    }

    
    //public func groupColors(forGroupUid groupUid: UID, using style: IdentityColorStyle = ObvMessengerSettings.Interface.identityColorStyle) -> (background: UIColor, text: UIColor) {
    public func groupColors(forGroupUid groupUid: UID, using style: IdentityColorStyle) -> (background: UIColor, text: UIColor) {
        switch style {
        case .hue:
            let hue = hueFromBytes(groupUid.raw)
            let text = UIColor(hue: hue, saturation: 0.46, brightness: 0.91, alpha: 1.0)
            let background = UIColor(hue: hue, saturation: 0.16, brightness: 0.98, alpha: 1.0)
            return (background, text)
        case .richter:
            let text = UIColor.white.withAlphaComponent(0.8)
            let background = richterColorFromBytes(groupUid.raw)
            return (background, text)
        }
    }

    public func groupV2Colors(forGroupIdentifier groupIdentifier: Data, using style: IdentityColorStyle = .hue) -> (background: UIColor, text: UIColor) {
        switch style {
        case .hue:
            let hue = hueFromBytes(groupIdentifier)
            let text = UIColor(hue: hue, saturation: 0.46, brightness: 0.91, alpha: 1.0)
            let background = UIColor(hue: hue, saturation: 0.16, brightness: 0.98, alpha: 1.0)
            return (background, text)
        case .richter:
            let text = UIColor.white.withAlphaComponent(0.8)
            let background = richterColorFromBytes(groupIdentifier)
            return (background, text)
        }
    }

    private func bytesValue(_ bytes: Data) -> Int {
        return bytes.reduce(1 as Int) { (31 * ($0 as Int) + Int($1)) & 0xff }
    }

    private func hueFromBytes(_ bytes: Data) -> CGFloat {
        let fourBitsValue = bytesValue(bytes)
        let hue = CGFloat(fourBitsValue) / 256.0
        return hue
    }
    
    private func richterColorFromBytes(_ bytes: Data) -> UIColor {
        let bitsValue = bytesValue(bytes)
        let index = bitsValue % AppTheme.richterColors.count
        let color = AppTheme.richterColors[index]
        return color
    }
    

}

