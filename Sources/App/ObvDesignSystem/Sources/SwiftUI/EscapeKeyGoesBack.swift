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

    /// Makes Esc run `action` while `isActive`, through a hidden button carrying the cancel shortcut.
    ///
    /// For the root of a `NavigationStack` whose close button is an ``ObvButtonWithCancelRole``: a shortcut on the root stays live under a pushed
    /// screen and wins there, so the root gives its close button the shortcut while its path is empty and this the rest of the time, popping the
    /// path. The two conditions must be complements: two live cancel shortcuts leave it to chance which one fires.
    ///
    /// `isActive` is read again when the key fires, not only when the view renders: the shortcut is withdrawn by the next render, so an Esc
    /// arriving between a pop and that render would otherwise run `action` against a path already empty, which `removeLast` answers by trapping.
    public func escapeKeyPresses(while isActive: @escaping @autoclosure () -> Bool = true, _ action: @escaping () -> Void) -> some View {
        background(Button(action: { if isActive() { action() } }, label: { Text(verbatim: " ").opacity(0) }).keyboardShortcut(isActive() ? .cancelAction : nil).hidden())
    }


    /// For the root of a `NavigationStack`: Esc goes back under a pushed screen and closes the whole stack from the root only, through a
    /// cancel button this adds to the toolbar.
    ///
    /// The two conditions are complements by construction, which is the point of there being one modifier rather than a hidden button and
    /// a button to keep in step: two live cancel shortcuts leave it to chance which one fires.
    public func escapeKeyGoesBackOrCloses(isAtRoot: @escaping @autoclosure () -> Bool, goBack: @escaping () -> Void, close: @escaping () -> Void) -> some View {
        escapeKeyPresses(while: !isAtRoot(), goBack)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ObvButtonWithCancelRole(escapeKeyPressesIt: isAtRoot(), action: close)
                }
            }
    }

}
