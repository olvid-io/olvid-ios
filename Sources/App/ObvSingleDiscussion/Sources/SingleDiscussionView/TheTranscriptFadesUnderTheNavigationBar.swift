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


/// **The transcript passes under the navigation bar behind a fade, rather than being cut off against a line.**
///
/// A scroll view's top edge effect is what draws the wash behind the bar, and it has two looks: `soft`, a fade the messages read through, and `hard`,
/// which the system describes as *a hard cutoff and dividing line*. Asked for neither, the system chooses — and the choice it makes changed between
/// iOS 26 and iOS 27. The messages used to travel under a fade and now meet a rule.
///
/// **The visible fault is not the look but the moment it arrives.** An edge effect exists only once there is content beneath the bar, and a discussion
/// opens with the list at its *top*, where there is none: the bar is clear, the entry then scrolls to the last message, the messages pass underneath, and
/// the effect switches on. Under a fade that transition is barely a transition; under a hard cutoff a bar that was transparent acquires a background and
/// a line, a moment after the discussion opens. **The cover cannot hide it** — the navigation bar is UIKit's and draws above anything this screen puts
/// down, which is stated where the cover is built.
///
/// **Asked for rather than inherited**, which is the whole of the change: the two systems disagree about what `automatic` means here, so the screen says
/// which one it wants and neither gets to decide. That it *is* the automatic resolution rather than something this app configures was checked — nothing
/// on the way to this screen sets a bar appearance from iOS 26 onwards.
///
/// **A modifier of its own rather than a line on the list**, for the reason its two neighbours give: `SingleDiscussionCellsListView`'s chain answers
/// *"the compiler is unable to type-check this expression in reasonable time"* when it is perturbed.
struct TheTranscriptFadesUnderTheNavigationBar: ViewModifier {

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }

}


extension View {

    /// Asks for a fade where the messages pass under the navigation bar — see ``TheTranscriptFadesUnderTheNavigationBar``.
    func theTranscriptFadesUnderTheNavigationBar() -> some View {
        modifier(TheTranscriptFadesUnderTheNavigationBar())
    }

}
