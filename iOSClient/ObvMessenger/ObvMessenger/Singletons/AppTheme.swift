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
import ObvEngine
import ObvTypes
import ObvCrypto
import ObvUI

// MARK: - Computing colors from identities

extension AppTheme {
    
    enum IdentityColorStyle: Int, CaseIterable, CustomStringConvertible {
        case hue = 0
        case richter = 1
        
        var description: String {
            switch self {
            case .hue: return "Hue"
            case .richter: return "Richter"
            }
        }

    }
    
    static let richterColors: [UIColor] = {
        var index = 0
        var colors = [UIColor]()
        while let color = UIColor(named: "RichterColor\(index)") {
            colors.append(color)
            index += 1
        }
        return colors
    }()
    
    func identityTextColor(for cryptoId: ObvCryptoId, using style: IdentityColorStyle = ObvMessengerSettings.Interface.identityColorStyle) -> UIColor {
        switch style {
        case .hue:
            let hue = hueFromBytes(cryptoId.getIdentity())
            let textColor = UIColor(hue: hue, saturation: 0.82, brightness: 0.68, alpha: 1.0)
            return textColor
        case .richter:
            return richterColorFromBytes(cryptoId.getIdentity())
        }
    }

    
    func identityColors(for cryptoId: ObvCryptoId, using style: IdentityColorStyle = ObvMessengerSettings.Interface.identityColorStyle) -> (background: UIColor, text: UIColor) {
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

    
    func groupColors(forGroupUid groupUid: UID, using style: IdentityColorStyle = ObvMessengerSettings.Interface.identityColorStyle) -> (background: UIColor, text: UIColor) {
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

    func groupV2Colors(forGroupIdentifier groupIdentifier: Data, using style: IdentityColorStyle = .hue) -> (background: UIColor, text: UIColor) {
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


final class ObvSemanticColorScheme {
    
    // See https://developer.apple.com/documentation/uikit/uicolor/ui_element_colors
    
    // Label Colors
    
    /// The color for text labels containing primary content.
    var label: UIColor
    
    /// The color for text labels containing secondary content.
    var secondaryLabel: UIColor
    
    /// The color for text labels containing tertiary content.
    var tertiaryLabel: UIColor
    
    /// The color for text labels containing quaternary content.
    var quaternaryLabel: UIColor
    
    
    // Fill Colors
    
    /// An overlay fill color for thin and small shapes.
    var systemFill: UIColor
    
    /// An overlay fill color for medium-size shapes.
    var secondarySystemFill: UIColor
    
    /// An overlay fill color for large shapes.
    var tertiarySystemFill: UIColor
    
    /// An overlay fill color for large areas containing complex content.
    var quaternarySystemFill: UIColor
    
    
    // Text Colors
    
    /// The color for placeholder text in controls or text views/
    var placeholderText: UIColor
    
    
    // Standard Content Background Colors
    // Use these colors for standard table views and designs that have a white primary background in a light environment.
    
    /// The color for the main background of your interface.
    var systemBackground: UIColor

    /// The color for content layered on top of the main background.
    var secondarySystemBackground: UIColor
    
    /// The color for content layered on top of secondary backgrounds.
    var tertiarySystemBackground: UIColor
    
    /// The color for links
    var link: UIColor
    
    // Constant colors
    
    var obvYellow: UIColor
    
    /// Light blue color of Olivd
    var olvidLight: UIColor
    
    /// Dark blue color of Olvid
    var olvidDark: UIColor
    
    /// Dark Olvid in dark mode, light blue Olvid in light mode
    /// Under iOS12, light blue.
    var adaptiveOlvidBlue: UIColor
    var adaptiveOlvidBlueReversed: UIColor
    
    // Discussion colors
    
    var discussionScreenBackground: UIColor
    
    var sentCellBackground: UIColor
    var sentCellBody: UIColor
    var sentCellLink: UIColor
    var sentCellReplyToBackground: UIColor
    var sentCellReplyToBody: UIColor
    var sentCellReplyToLink: UIColor

    var receivedCellBackground: UIColor
    var receivedCellBody: UIColor
    var receivedCellLink: UIColor
    var receivedCellReplyToBackground: UIColor
    var receivedCellReplyToBody: UIColor

    var newReceivedCellBackground: UIColor
    var newReceivedCellReplyToBackground: UIColor
    
    var tapToRead: UIColor

    var cellDate: UIColor

    var callBarColor: UIColor

    // Old colors
    
    var surfaceDark: UIColor
    var surfaceMedium: UIColor
    var surfaceLight: UIColor

    var blackTextHighEmphasis: UIColor
    var blackTextMediumEmphasis: UIColor

    var whiteTextHighEmphasis: UIColor
    var whiteTextMediumEmphasis: UIColor
    var whiteTextDisabled: UIColor

    var primary900: UIColor
    var primary400: UIColor
    var primary300: UIColor
    var primary700: UIColor
    
    var secondary: UIColor

    var textOnSecondaryHighEmphasis: UIColor
    var textOnSecondaryMediumEmphasis: UIColor
    var textOnSecondaryDisabled: UIColor

    // MISC
    
    var buttonHighlighted: UIColor
    var buttonDisabled: UIColor
    var green: UIColor
    var orange: UIColor
    var purple: UIColor
    var red: UIColor

    
    fileprivate init(with name: AppTheme.Name) {
        switch name {
        case .edmond:

            label = UIColor.label
            secondaryLabel = UIColor.secondaryLabel
            tertiaryLabel = UIColor.tertiaryLabel
            quaternaryLabel = UIColor.quaternaryLabel
            systemFill = UIColor.systemFill
            secondarySystemFill = UIColor.secondarySystemFill
            tertiarySystemFill = UIColor.tertiarySystemFill
            quaternarySystemFill = UIColor.quaternarySystemFill
            placeholderText = UIColor.placeholderText
            systemBackground = UIColor { (traitCollection: UITraitCollection) in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor.systemBackground
                } else {
                    return UIColor.secondarySystemBackground
                }
            }
            secondarySystemBackground = UIColor { (traitCollection: UITraitCollection) in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor.secondarySystemBackground
                } else {
                    return UIColor.systemBackground
                }
            }
            tertiarySystemBackground = UIColor.tertiarySystemBackground
            discussionScreenBackground = UIColor { (traitCollection: UITraitCollection) in
                if traitCollection.userInterfaceStyle == .dark {
                    return .black
                } else {
                    return .white
                }
            }
            receivedCellBackground = UIColor { (traitCollection: UITraitCollection) in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor.secondarySystemBackground
                } else {
                    return UIColor(named: "EdmondSurfaceDark")!
                }
            }
            newReceivedCellBackground = UIColor { (traitCollection: UITraitCollection) in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor.systemFill
                } else {
                    return UIColor(named: "EdmondSurfaceDark")!
                }
            }
            receivedCellBody = UIColor.label
            receivedCellLink = UIColor.secondaryLabel
            receivedCellReplyToBackground = UIColor.tertiarySystemBackground
            newReceivedCellReplyToBackground = UIColor { (traitCollection: UITraitCollection) in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor.systemFill
                } else {
                    return UIColor(named: "EdmondSurfaceDark")!
                }
            }
            receivedCellReplyToBody = UIColor.secondaryLabel
            tapToRead = UIColor.secondaryLabel
            cellDate = UIColor.tertiaryLabel
            sentCellReplyToBackground = UIColor.tertiarySystemBackground
            sentCellReplyToBody = UIColor.secondaryLabel
            sentCellReplyToLink = UIColor.secondaryLabel
            link = UIColor.link
            
            adaptiveOlvidBlue = UIColor { (traitCollection: UITraitCollection) in
                traitCollection.userInterfaceStyle == .dark ? UIColor(named: "OlvidDark")! : UIColor(named: "OlvidLight")!
            }
            adaptiveOlvidBlueReversed = UIColor { (traitCollection: UITraitCollection) in
                traitCollection.userInterfaceStyle == .dark ? UIColor(named: "OlvidLight")! : UIColor(named: "OlvidDark")!
            }
            
            orange = UIColor { (traitCollection: UITraitCollection) in
                traitCollection.userInterfaceStyle == .dark ? UIColor(named: "EdmondSecondary900")! : UIColor(named: "EdmondSecondary800")!
            }
            
            olvidLight = UIColor(named: "OlvidLight")!
            olvidDark = UIColor(named: "OlvidDark")!

            sentCellBackground = UIColor(named: "OldSentCellBackground")!
            sentCellBody = UIColor(named: "EdmondPrimary900")!
            sentCellLink = UIColor(named: "EdmondPrimary700")!
            
            obvYellow = UIColor(named: "EdmondSecondary700")!
            
            // Old colors

            surfaceDark = UIColor(named: "EdmondSurfaceDark")!
            surfaceMedium = UIColor(named: "EdmondSurfaceMedium")!
            surfaceLight = UIColor(named: "EdmondSurfaceLight")!

            blackTextHighEmphasis = UIColor(named: "EdmondBlackTextHighEmphasis")!
            blackTextMediumEmphasis = UIColor(named: "EdmondBlackTextMediumEmphasis")!

            whiteTextHighEmphasis = UIColor(named: "EdmondWhiteTextHighEmphasis")!
            whiteTextMediumEmphasis = UIColor(named: "EdmondWhiteTextMediumEmphasis")!
            whiteTextDisabled = UIColor(named: "EdmondWhiteTextDisabled")!

            primary900 = UIColor(named: "EdmondPrimary800")!
            primary700 = UIColor(named: "EdmondPrimary700")!
            primary400 = UIColor(named: "EdmondPrimary400")!
            primary300 = UIColor(named: "EdmondPrimary300")!

            secondary = UIColor(named: "EdmondSecondary700")!

            textOnSecondaryHighEmphasis = UIColor(named: "EdmondTextOnSecondaryHighEmphasis")!
            textOnSecondaryMediumEmphasis = UIColor(named: "EdmondTextOnSecondaryMediumEmphasis")!
            textOnSecondaryDisabled = UIColor(named: "EdmondTextOnSecondaryDisabled")!

            // MISC
            
            buttonDisabled = UIColor(named: "EdmondSurfaceDark")!
            buttonHighlighted = UIColor(named: "EdmondSecondary600")!
            green = UIColor(named: "EdmondGreen")!
            purple = UIColor(named: "OlvidPurple")!
            red = UIColor(named: "OlvidRed")!
            callBarColor = UIColor(named: "CallBarColor")!
        }
    }
}


final class ObvImages {

    let groupImage: UIImage

    init() {
        self.groupImage = UIImage(systemName: "person.3.fill")!
    }

}
