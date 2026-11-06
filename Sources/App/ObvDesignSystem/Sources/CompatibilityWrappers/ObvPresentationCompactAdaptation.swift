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


/// Mirrors `PresentationAdaptation`, which is itself iOS 16.4 and so cannot be named in a signature this app can call.
public enum ObvPresentationAdaptation {
    case automatic
    case none
    case popover
    case sheet
    case fullScreenCover
}


struct ObvPresentationCompactAdaptationModifier: ViewModifier {
    
    private let obvPresentationAdaptation: ObvPresentationAdaptation
    
    init(obvPresentationAdaptation: ObvPresentationAdaptation) {
        self.obvPresentationAdaptation = obvPresentationAdaptation
    }
    
    @available(iOS 16.4, *)
    var presentationAdaptation: PresentationAdaptation {
        switch obvPresentationAdaptation {
        case .automatic: return .automatic
        case .none: return .none
        case .popover: return .popover
        case .sheet: return .sheet
        case .fullScreenCover: return .fullScreenCover
        }
    }
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationCompactAdaptation(presentationAdaptation)
        } else {
            content
        }
    }
    
}


extension View {
    
    /// Says what a presentation should become in a compact size class. Without it, a popover on an iPhone silently turns
    /// into a sheet, which is a different control with a different meaning: `.popover` keeps it anchored to what opened it.
    public func presentationCompactAdaptationOniOS16Dot4(_ obvPresentationAdaptation: ObvPresentationAdaptation) -> some View {
        self.modifier(ObvPresentationCompactAdaptationModifier(obvPresentationAdaptation: obvPresentationAdaptation))
    }
    
}
