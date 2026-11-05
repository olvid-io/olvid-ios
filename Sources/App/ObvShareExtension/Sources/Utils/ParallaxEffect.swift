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

// MARK: - Scroll Transition Modifiers

private struct OpacityScrollTransitionViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .scrollTransition(.interactive, axis: .horizontal) { view, phase in
                    view
                        .opacity(phase.isIdentity ? 1 : 0.0)
                }
        } else {
            content
        }
    }
}

private struct HorizontalOffsetScrollTransitionViewModifier: ViewModifier {

    let offsetValue: CGFloat

    init(offsetValue: CGFloat = -50.0) {
        self.offsetValue = offsetValue
    }

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .scrollTransition(.interactive, axis: .horizontal) { view, phase in
                    view
                        .offset(x: phase.value * offsetValue)
                }
        } else {
            content
        }
    }
}

extension View {

    func opacityScrollTransition() -> some View {
        modifier(OpacityScrollTransitionViewModifier())
    }

    func horizontalOffsetScrollTransition() -> some View {
        modifier(HorizontalOffsetScrollTransitionViewModifier())
    }

}
