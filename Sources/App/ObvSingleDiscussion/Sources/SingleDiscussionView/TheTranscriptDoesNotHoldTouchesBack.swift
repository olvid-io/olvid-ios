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


/// **A touch inside a message reaches it at once, rather than after the scroll view has thought about it**.
///
/// `UIScrollView.delaysContentTouches` defaults to `true`: the scroll view holds `touchesBegan` back from its content for about 150ms while it decides
/// whether the touch is the start of a scroll. Legacy sets it to `false` in `configureHierarchy()`; a screen built from a `List` inherits the default.
///
/// **What it costs, stated precisely, because "every tap is slower" overstates it.** A tap fires on touch *up*, so where the finger rests longer than the
/// delay the action is not late — what is late is the *acknowledgement*: a highlight, a press being felt, a scrubber taking hold. Where the finger is
/// quicker than the delay, the touches arrive in a burst and the response is late. So the honest claim is **the acknowledgement of any touch is late, and
/// the response to a brisk one**, not that every tap is slower.
///
/// **Why turning it off is safe here.** The classic hazard is that a drag beginning on a content view is swallowed by that view instead of scrolling.
/// UIKit's escape hatch is `touchesShouldCancelInContentView(_:)`, which answers `false` for `UIControl` subclasses and **`true` for everything else** — so
/// a scroll view full of `UIButton`s can genuinely lose the scroll. The content here is SwiftUI hosted in views that are not `UIControl`s, so the default
/// answer is `true` and the scroll view may still take the drag away.
///
/// **It changes nothing about gesture arbitration** — only *when* touches begin to be delivered, not who wins. That was reasoning, and this screen's record
/// on reasoning about arbitration is poor, so a walk was asked for rather than concluded from this comment. It came back clean on 2026-08-27: taps inside a
/// bubble, the long press, Step 40's swipe, the drag-out, and a scroll begun with the finger down on a bubble.
///
/// **Re-asserted rather than set once**, the rule this screen learnt for `dropDelegate`: the property belongs to a view SwiftUI owns and rebuilds, and a
/// value written once is a value something else may write back.
struct TheTranscriptDoesNotHoldTouchesBack: ViewModifier {

    func body(content: Content) -> some View {
        content
            // The same attachment point and the same version list as the drop, the per-frame geometry and Step 61, and the same note applies: it follows the
            // versions the *screen* runs on rather than the ones this needs, so a version missing from it costs no error and simply never attaches anything.
            .introspect(.list, on: .iOS(.v18, .v26, .v27)) { collectionView in
                guard collectionView.delaysContentTouches else { return }
                collectionView.delaysContentTouches = false
            }
    }

}


extension View {

    /// Stops the transcript holding a touch back from the message it landed on — see ``TheTranscriptDoesNotHoldTouchesBack``.
    func theTranscriptDoesNotHoldTouchesBack() -> some View {
        modifier(TheTranscriptDoesNotHoldTouchesBack())
    }

}
