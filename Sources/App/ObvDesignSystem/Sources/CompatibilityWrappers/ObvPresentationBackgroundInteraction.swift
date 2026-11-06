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


public enum ObvPresentationBackgroundInteraction {
    case automatic
    case enabled
    case enabledUpThrough(detent: PresentationDetent)
    case disabled
}

private struct ObvPresentationBackgroundInteractionViewModifier: ViewModifier {
    
    let interaction: ObvPresentationBackgroundInteraction
        
    public func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            switch interaction {
            case .automatic:
                content
                    .presentationBackgroundInteraction(.automatic)
            case .enabled:
                content
                    .presentationBackgroundInteraction(.enabled)
            case .enabledUpThrough(let detent):
                content
                    .presentationBackgroundInteraction(.enabled(upThrough: detent))
            case .disabled:
                content
                    .presentationBackgroundInteraction(.disabled)
            }
        } else {
            content
        }
    }

}


extension View {
    
    /// Wrapper around Apple's `presentationBackgroundInteraction(_ interaction: PresentationBackgroundInteraction)` API, which is only available on iOS 16.4+.
    public func presentationBackgroundInteractionOniOS16Dot4(_ interaction: ObvPresentationBackgroundInteraction) -> some View {
        self.modifier(ObvPresentationBackgroundInteractionViewModifier(interaction: interaction))
    }
    
}
