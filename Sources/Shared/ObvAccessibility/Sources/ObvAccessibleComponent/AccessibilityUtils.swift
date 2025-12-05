/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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

public extension View {
    @ViewBuilder
    /// Helper for the accessibilityHint view modifier with conditionality, to make it available below iOS 18.0.
    func obvAccessibilityHint(_ hint: LocalizedStringKey, isEnabled: Bool) -> some View {
        
        if #available(iOS 18, *) {
            
            // For iOS 18.0 or higher, we use the conditional accessibilityHint built in SwiftUI.
            self.accessibilityHint(hint, isEnabled: isEnabled)
            
        } else {
            
            // Else, fallback on the old one, handling the conditionnality directly in this view modifier.
            if isEnabled {
                self.accessibilityHint(hint)
            } else {
                self
            }
            
        }
        
    }
}
