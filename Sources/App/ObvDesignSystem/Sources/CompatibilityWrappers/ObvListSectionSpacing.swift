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


public enum ObvListSectionSpacing {
    case `default`
    case compact
    case custom(_ spacing: CGFloat)

    @available(iOS 17.0, *)
    var listSectionSpacing: SwiftUI.ListSectionSpacing {
        switch self {
        case .default: return .default
        case .compact: return .compact
        case .custom(let spacing): return .custom(spacing)
        }
    }
    
}

struct ObvListSectionSpacingViewModifier: ViewModifier {
    
    let obvListSectionSpacing: ObvListSectionSpacing
    
    
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            return content
                .listSectionSpacing(obvListSectionSpacing.listSectionSpacing)
        } else {
            return content
        }
    }
    
}

extension View {
    
    /// Wrapper around Apple's `listSectionSpacing(_ spacing: ListSectionSpacing)` API, which is only available on iOS 17+.
    public func listSectionSpacingOniOS17(_ obvListSectionSpacing: ObvListSectionSpacing) -> some View {
        self.modifier(ObvListSectionSpacingViewModifier(obvListSectionSpacing: obvListSectionSpacing))
    }
    
}
