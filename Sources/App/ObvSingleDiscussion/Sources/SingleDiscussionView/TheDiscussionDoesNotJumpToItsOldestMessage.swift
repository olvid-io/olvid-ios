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
import SwiftUIIntrospect
import UIKit


/// **A tap on the status bar must not throw the reader into the past**.
///
/// iOS scrolls a scroll view to its top when the status bar is tapped, `UIScrollView.scrollsToTop` defaulting to `true`. On most screens that is helpful; on
/// this one the top is the discussion's **oldest** message, so an accidental tap carries the reader thousands of points backwards.
///
/// Legacy sets `collectionView.scrollsToTop = false` in `configureHierarchy()`, unconditional and uncommented — one of the many things a screen built by hand
/// does in passing and a screen built from a `List` inherits the default of.
///
/// **Set unconditionally, as legacy sets it.** Mac Catalyst has no status bar to tap and an iPad has one, so a platform branch would buy nothing and be one
/// more thing to be wrong about.
///
/// **Re-asserted rather than set once**, the rule this screen learnt for `dropDelegate`: the property belongs to a view SwiftUI owns and rebuilds, and a value
/// written once is a value something else may write back. The guard means the write happens only when it changes something.
///
/// **How to know it worked, without a probe.** *Nothing happened* is both the desired outcome and what a missed tap looks like. The app supplies the control:
/// the **discussions list** scrolls to its top on the same tap. So tap the status bar there first, where it should work, then in a discussion, where it should
/// not. One gesture, two screens, and the first proves the second.
struct TheDiscussionDoesNotJumpToItsOldestMessage: ViewModifier {

    func body(content: Content) -> some View {
        content
            // The same attachment point and the same version list as the drop and the per-frame geometry, and the same note applies: it follows the versions the
            // *screen* runs on rather than the ones this needs, so a version missing from it costs no error and simply never attaches anything.
            .introspect(.list, on: .iOS(.v18, .v26, .v27)) { collectionView in
                guard collectionView.scrollsToTop else { return }
                collectionView.scrollsToTop = false
            }
    }

}


extension View {

    /// Stops a tap on the status bar carrying the reader to the oldest message of the discussion — see ``TheDiscussionDoesNotJumpToItsOldestMessage``.
    func theDiscussionDoesNotJumpToItsOldestMessage() -> some View {
        modifier(TheDiscussionDoesNotJumpToItsOldestMessage())
    }

}
