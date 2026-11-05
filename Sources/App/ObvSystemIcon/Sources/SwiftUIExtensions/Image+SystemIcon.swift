/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

public extension Image {
    
    init(symbolIcon icon: any SymbolIcon) {
        if let customIcon = icon as? CustomIcon {
            self.init(customIcon: customIcon)
        } else if let systemIcon = icon as? SystemIcon {
            self.init(systemIcon: systemIcon)
        } else {
            assertionFailure()
            self.init(systemIcon: .xmark)
        }
    }

    /// **There is no decorative variant of this**, and asking for one used to draw nothing at all.
    ///
    /// `Image(decorative:)` names an *asset*, so an SF Symbol routed through it looks for an image called "photo" in an
    /// asset catalogue, finds none, and lays out an empty box — silently, since a missing asset is not an error. Two
    /// callers had asked for it and both had been drawing bare backgrounds with no glyph in them.
    ///
    /// A symbol is made decorative by the caller instead, with `.accessibilityHidden(true)`, which an initialiser cannot
    /// do: the modifier returns a `View` and this must return an `Image`.
    init(systemIcon: SystemIcon) {
        self.init(systemName: systemIcon.name)
    }
    
    init(customIcon: CustomIcon, isDecorative: Bool = false) {
        if isDecorative {
            self.init(decorative: customIcon.name, bundle: ObvSystemIconResources.bundle)
        } else {
            self.init(customIcon.name, bundle: ObvSystemIconResources.bundle)
        }
    }

}
