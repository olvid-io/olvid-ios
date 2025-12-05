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


public enum ObvPresentationDetent : Hashable, Sendable {
    case medium
    case large
    case fraction(_ fraction: CGFloat)
    case height(_ height: CGFloat)
}

struct ObvPresentationDetents: ViewModifier {
    
    let obvDetents: Set<ObvPresentationDetent>
    
    init(_ obvDetents: Set<ObvPresentationDetent>) {
        self.obvDetents = obvDetents
    }
    
    
    @available(iOS 16.0, *)
    private var detents: Set<PresentationDetent> {
        var detents = Set<PresentationDetent>()
        for obvDetent in obvDetents {
            switch obvDetent {
            case .medium:
                detents.insert(.medium)
            case .large:
                detents.insert(.large)
            case .fraction(let fraction):
                detents.insert(.fraction(fraction))
            case .height(let height):
                detents.insert(.height(height))
            }
        }
        return detents
    }
    
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents(detents)
        } else {
            content
        }
    }
    
}


extension View {
    
    /// Wrapper around Apple's `presentationDetents(_ detents: Set<PresentationDetent>)` API, which
    /// is onylavailable on iOS16+.
    public func presentationDetentsOniOS16(_ obvDetents: Set<ObvPresentationDetent>) -> some View {
        self.modifier(ObvPresentationDetents(obvDetents))
    }
    
}
