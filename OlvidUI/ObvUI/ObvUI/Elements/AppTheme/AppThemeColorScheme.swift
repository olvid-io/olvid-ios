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


public final class AppThemeSemanticColorScheme {
    
    // See https://developer.apple.com/documentation/uikit/uicolor/ui_element_colors
    
    // Label Colors
    
    /// The color for text labels containing primary content.
    public var label: UIColor
    
    /// The color for text labels containing secondary content.
    public var secondaryLabel: UIColor
    
    /// The color for text labels containing tertiary content.
    public var tertiaryLabel: UIColor
    
    /// The color for text labels containing quaternary content.
    public var quaternaryLabel: UIColor
    
    
    // Fill Colors
    
    /// An overlay fill color for thin and small shapes.
    public var systemFill: UIColor
    
    /// An overlay fill color for medium-size shapes.
    public var secondarySystemFill: UIColor
    
    /// An overlay fill color for large shapes.
    public var tertiarySystemFill: UIColor
    
    /// An overlay fill color for large areas containing complex content.
    public var quaternarySystemFill: UIColor
    
    
    // Text Colors
    
    /// The color for placeholder text in controls or text views/
    public var placeholderText: UIColor
    
    
    // Standard Content Background Colors
    // Use these colors for standard table views and designs that have a white primary background in a light environment.
    
    /// The color for the main background of your interface.
    public var systemBackground: UIColor

    /// The color for content layered on top of the main background.
    public var secondarySystemBackground: UIColor
    
    /// The color for content layered on top of secondary backgrounds.
    public var tertiarySystemBackground: UIColor
    
    /// The color for links
    public var link: UIColor
    
    // Constant colors
    
    public var obvYellow: UIColor
    
    /// Light blue color of Olivd
    public var olvidLight: UIColor
    
    /// Dark blue color of Olvid
    public var olvidDark: UIColor
    
    /// Dark Olvid in dark mode, light blue Olvid in light mode
    /// Under iOS12, light blue.
    public var adaptiveOlvidBlue: UIColor
    public var adaptiveOlvidBlueReversed: UIColor
    
    // Discussion colors
    
    public var discussionScreenBackground: UIColor
    
    public var sentCellBackground: UIColor
    public var sentCellBody: UIColor
    public var sentCellLink: UIColor
    public var sentCellReplyToBackground: UIColor
    public var sentCellReplyToBody: UIColor
    public var sentCellReplyToLink: UIColor

    public var receivedCellBackground: UIColor
    public var receivedCellBody: UIColor
    public var receivedCellLink: UIColor
    public var receivedCellReplyToBackground: UIColor
    public var receivedCellReplyToBody: UIColor

    public var newReceivedCellBackground: UIColor
    public var newReceivedCellReplyToBackground: UIColor
    
    public var tapToRead: UIColor

    public var cellDate: UIColor

    public var callBarColor: UIColor

    // Old colors
    
    public var surfaceDark: UIColor
    public var surfaceMedium: UIColor
    public var surfaceLight: UIColor

    public var blackTextHighEmphasis: UIColor
    public var blackTextMediumEmphasis: UIColor

    public var whiteTextHighEmphasis: UIColor
    public var whiteTextMediumEmphasis: UIColor
    public var whiteTextDisabled: UIColor

    public var primary900: UIColor
    public var primary400: UIColor
    public var primary300: UIColor
    public var primary700: UIColor
    
    public var secondary: UIColor

    public var textOnSecondaryHighEmphasis: UIColor
    public var textOnSecondaryMediumEmphasis: UIColor
    public var textOnSecondaryDisabled: UIColor

    // MISC
    
    public var buttonHighlighted: UIColor
    public var buttonDisabled: UIColor
    public var green: UIColor
    public var orange: UIColor
    public var purple: UIColor
    public var red: UIColor

    
    init(with name: AppTheme.Name) {
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
                    return UIColor.loadColorFromLocalBundle(colorNamed: "EdmondSurfaceDark")!
                }
            }
            newReceivedCellBackground = UIColor { (traitCollection: UITraitCollection) in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor.systemFill
                } else {
                    return UIColor.loadColorFromLocalBundle(colorNamed: "EdmondSurfaceDark")!
                }
            }
            receivedCellBody = UIColor.label
            receivedCellLink = UIColor.secondaryLabel
            receivedCellReplyToBackground = UIColor.tertiarySystemBackground
            newReceivedCellReplyToBackground = UIColor { (traitCollection: UITraitCollection) in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor.systemFill
                } else {
                    return UIColor.loadColorFromLocalBundle(colorNamed: "EdmondSurfaceDark")!
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
                traitCollection.userInterfaceStyle == .dark ? UIColor.loadColorFromLocalBundle(colorNamed: "OlvidDark")! : UIColor.loadColorFromLocalBundle(colorNamed: "OlvidLight")!
            }
            adaptiveOlvidBlueReversed = UIColor { (traitCollection: UITraitCollection) in
                traitCollection.userInterfaceStyle == .dark ? UIColor.loadColorFromLocalBundle(colorNamed: "OlvidLight")! : UIColor.loadColorFromLocalBundle(colorNamed: "OlvidDark")!
            }
            
            orange = UIColor { (traitCollection: UITraitCollection) in
                traitCollection.userInterfaceStyle == .dark ? UIColor.loadColorFromLocalBundle(colorNamed: "EdmondSecondary900")! : UIColor.loadColorFromLocalBundle(colorNamed: "EdmondSecondary800")!
            }
            
            olvidLight = UIColor.loadColorFromLocalBundle(colorNamed: "OlvidLight")!
            olvidDark = UIColor.loadColorFromLocalBundle(colorNamed: "OlvidDark")!

            sentCellBackground = UIColor.loadColorFromLocalBundle(colorNamed: "OldSentCellBackground")!
            sentCellBody = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondPrimary900")!
            sentCellLink = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondPrimary700")!

            obvYellow = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondSecondary700")!

            // Old colors

            surfaceDark = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondSurfaceDark")!
            surfaceMedium = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondSurfaceMedium")!
            surfaceLight = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondSurfaceLight")!

            blackTextHighEmphasis = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondBlackTextHighEmphasis")!
            blackTextMediumEmphasis = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondBlackTextMediumEmphasis")!

            whiteTextHighEmphasis = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondWhiteTextHighEmphasis")!
            whiteTextMediumEmphasis = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondWhiteTextMediumEmphasis")!
            whiteTextDisabled = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondWhiteTextDisabled")!

            primary900 = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondPrimary800")!
            primary700 = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondPrimary700")!
            primary400 = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondPrimary400")!
            primary300 = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondPrimary300")!

            secondary = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondSecondary700")!

            textOnSecondaryHighEmphasis = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondTextOnSecondaryHighEmphasis")!
            textOnSecondaryMediumEmphasis = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondTextOnSecondaryMediumEmphasis")!
            textOnSecondaryDisabled = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondTextOnSecondaryDisabled")!

            // MISC

            buttonDisabled = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondSurfaceDark")!
            buttonHighlighted = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondSecondary600")!
            green = UIColor.loadColorFromLocalBundle(colorNamed: "EdmondGreen")!
            purple = UIColor.loadColorFromLocalBundle(colorNamed: "OlvidPurple")!
            red = UIColor.loadColorFromLocalBundle(colorNamed: "OlvidRed")!
            callBarColor = UIColor.loadColorFromLocalBundle(colorNamed: "CallBarColor")!
        }
    }
}


fileprivate extension UIColor {
    
    static func loadColorFromLocalBundle(colorNamed: String) -> UIColor? {
        UIColor(named: colorNamed, in: Bundle(for: SomeClass.self), compatibleWith: nil)
    }
    
}

class SomeClass {
    
}
