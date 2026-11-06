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


/// Mirrors `ScrollBounceBehavior`, which is itself iOS 16.4 and so cannot be named in a signature this app can call.
public enum ObvScrollBounceBehavior {
    case automatic
    case always
    case basedOnSize
}


struct ObvScrollBounceBehaviorModifier: ViewModifier {
    
    private let obvScrollBounceBehavior: ObvScrollBounceBehavior
    private let axes: Axis.Set
    
    init(obvScrollBounceBehavior: ObvScrollBounceBehavior, axes: Axis.Set) {
        self.obvScrollBounceBehavior = obvScrollBounceBehavior
        self.axes = axes
    }
    
    @available(iOS 16.4, *)
    var scrollBounceBehavior: ScrollBounceBehavior {
        switch obvScrollBounceBehavior {
        case .automatic:
            return .automatic
        case .always:
            return .always
        case .basedOnSize:
            return .basedOnSize
        }
    }
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .scrollBounceBehavior(scrollBounceBehavior, axes: axes)
        } else {
            content
        }
    }
    
}


extension View {
    
    public func scrollBounceBehaviorOniOS16Dot4(_ obvScrollBounceBehavior: ObvScrollBounceBehavior, axes: Axis.Set = [.vertical]) -> some View {
        self.modifier(ObvScrollBounceBehaviorModifier(obvScrollBounceBehavior: obvScrollBounceBehavior, axes: axes))
    }
    
}
