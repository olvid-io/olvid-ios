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


struct ObvSectionIndexLabel<S: StringProtocol>: ViewModifier {
    
    let label: S?
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            return content
                .sectionIndexLabel(label)
        } else {
            return content
        }
    }
    
}


struct ObvListSectionIndexVisibility: ViewModifier {
    
    let visibility: Visibility
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            return content
                .listSectionIndexVisibility(visibility)
        } else {
            return content
        }
    }
    
}

extension View {
    
    /// Wrapper around Apple's `func sectionIndexLabel<S>(_ label: S?) -> some View where S : StringProtocol` API, which is only available on iOS 26+.
    public func sectionIndexLabelOniOS26<S>(_ label: S?) -> some View where S : StringProtocol {
        self.modifier(ObvSectionIndexLabel(label: label))
    }

    public func listSectionIndexVisibilityOniOS26(_ visibility: Visibility) -> some View {
        self.modifier(ObvListSectionIndexVisibility(visibility: visibility))
    }
    
}
