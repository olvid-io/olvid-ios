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


public enum ObvContentTransition {
    case identity
    case interpolate
    case numericTextCountsDown(countsDown: Bool = false)
    case numericText(value: Double)
    case opacity
    case symbolEffect
}


struct ObvContentTransitions: ViewModifier {
    
    private let obvContentTransition: ObvContentTransition
    
    init(obvContentTransition: ObvContentTransition) {
        self.obvContentTransition = obvContentTransition
    }
    
    @available(iOS 16, *)
    var contentTransition: ContentTransition {
        switch obvContentTransition {
        case .identity:
            return .identity
        case .interpolate:
            return .interpolate
        case .opacity:
            return .opacity
        case .symbolEffect:
            if #available(iOS 17, *) {
                return .symbolEffect
            } else {
                return .identity
            }
        case .numericTextCountsDown(countsDown: let countsDown):
            return .numericText(countsDown: countsDown)
        case .numericText(value: let value):
            if #available(iOS 17, *) {
                return .numericText(value: value)
            } else {
                return .numericText()
            }
        }
    }
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .contentTransition(contentTransition)
        } else {
            content
        }
    }

}


extension View {
    
    public func contentTransitionOniOS16(_ obvContentTransition: ObvContentTransition) -> some View {
        self.modifier(ObvContentTransitions(obvContentTransition: obvContentTransition))
    }
    
}
