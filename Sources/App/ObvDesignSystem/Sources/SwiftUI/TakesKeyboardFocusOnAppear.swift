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


extension View {

    /// Takes keyboard focus when this view appears, without drawing a focus ring.
    ///
    /// A keyboard shortcut is looked for from the first responder. A presented screen with nothing focusable in it leaves the first responder outside, so
    /// none of its shortcuts is ever found — Esc on its close button included. From iOS 17 only, `focusable()` being unavailable before.
    public func takesKeyboardFocusOnAppear() -> some View {
        modifier(TakesKeyboardFocusOnAppear())
    }

}


private struct TakesKeyboardFocusOnAppear: ViewModifier {

    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .focusable()
                .focusEffectDisabled()
                .focused($isFocused)
                .onAppear { isFocused = true }
        } else {
            content
        }
    }

}
