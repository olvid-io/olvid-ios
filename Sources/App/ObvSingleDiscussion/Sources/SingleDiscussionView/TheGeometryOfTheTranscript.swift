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
import UIKit


/// Where the transcript is: everything this screen's scrolling rules ever ask of the scroll view, and nothing else.
///
/// **Five scalars, and that is the whole of it.** Measured across the five call sites that hold this screen at iOS 18, these are the only
/// properties of a `ScrollGeometry` any of them reads: the offset, the height of the container, the two insets, and — through
/// ``pointsBelowTheVisibleArea`` — the height of the content. Every one is also a property of `UIScrollView`, which is what makes Step 46
/// possible at all.
///
/// **Its own type rather than Apple's, for one hard reason**: `ScrollGeometry` is iOS 18-only, so it cannot appear in a closure signature
/// shared with iOS 17. Everything else follows from that.
struct TheGeometryOfTheTranscript: Equatable {

    /// How far down the discussion the reader has scrolled.
    let offset: CGFloat

    /// How tall the scroll view is. `containerSize.height` where SwiftUI reports it, `bounds.height` where it is read — **and whether those
    /// two are always the same number is the first thing 46a exists to establish**, everything else resting on it.
    let height: CGFloat

    /// What is kept clear above the messages.
    let topInset: CGFloat

    /// What is kept clear below them, which is whichever bar is at the bottom plus whatever the system leaves under it.
    let bottomInset: CGFloat

    /// How tall the whole discussion is.
    let contentHeight: CGFloat

    /// How much of the discussion the reader can see — the quantity the rule that writes the offset is triggered by.
    ///
    /// **The one to watch, where watching the inset alone was measured missing the largest change of all.** For the keyboard, and for a draft
    /// gaining a line, SwiftUI moves the inset and leaves the height alone. For a big change of the bar it does the opposite — it shortens the
    /// list and zeroes the inset, then animates the height back. This difference is invariant through that: `874 − 209` and `665 − 0` are both
    /// 665.
    var heightOfWhatCanBeSeen: CGFloat {
        height - bottomInset
    }

    /// How far the end of the discussion sits below what the reader can see. Nought at the end; 84 is the last message behind the
    /// composition bar.
    ///
    /// It was an extension on `ScrollGeometry` until Step 46, which is where it always read as though it belonged.
    var pointsBelowTheVisibleArea: CGFloat {
        contentHeight + bottomInset - offset - height
    }

    /// Whether the reader is at the **very** end, and not to be confused with
    /// ``TheGeometryOfTheTranscriptReadPerFrame/theReaderIsAtTheEndOfTheDiscussion``, which is the 60pt gate.
    ///
    /// **Two different questions, and the difference is the whole of Step 57's decision.** The gate asks *is this reader near enough that an
    /// arriving message concerns them*, and is right to be generous. This asks *did they choose to be where they are* — and a reader forty
    /// points up has chosen it, so reusing 60 here would move the transcript under anybody within a screen-inch of the end every time a row
    /// was re-measured. `staying-at-the-end.md` puts it plainly, having measured five members of this family: **the tolerance matters more
    /// than the trigger.**
    ///
    /// One point rather than nought: at the end the offset **is** the clamp's own bound, so every measurement of this state reads exactly
    /// `0.0` — 918 consecutive frames of it in the reaction-chip capture — and the point is for the rounding of a self-sizing list, not for a
    /// margin of judgement.
    ///
    /// **It lives here so that there is one definition.** Two places need it — the door in
    /// ``TheSpaceBelowTheMessagesWatchedBySwiftUI``, which decides whether a content-only change is worth waking the rule for, and the rule
    /// itself, which decides what to hold — and a threshold written twice is a threshold that will disagree with itself.
    var theReaderIsAtTheVeryEnd: Bool {
        pointsBelowTheVisibleArea <= Self.howCloseToAnEdgeCountsAsBeingAtIt
    }

    /// Whether the reader is at the very top, the mirror of ``theReaderIsAtTheVeryEnd``: the offset is then the clamp's other bound, `-topInset`. A discussion
    /// that fits on the screen is at both the very top and the very end.
    var theReaderIsAtTheVeryTop: Bool {
        offset + topInset <= Self.howCloseToAnEdgeCountsAsBeingAtIt
    }

    private static let howCloseToAnEdgeCountsAsBeingAtIt: CGFloat = 1

    // A `withTheMessagesAt(_:)` lived here from 46d to 46g, so that a frame could carry what a rule had just made of it and the next frame could chain
    // from what actually happened rather than from what was read. It went with the clock: `onScrollGeometryChange` hands over both the before and the
    // after, so there is nothing to remember and nothing to get wrong. What it was for is worth knowing anyway — forgetting to chain put the transcript
    // 285pt out on the second of the keyboard's two inset steps.

    private init(offset: CGFloat, height: CGFloat, topInset: CGFloat, bottomInset: CGFloat, contentHeight: CGFloat) {
        self.offset = offset
        self.height = height
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.contentHeight = contentHeight
    }


    /// Read straight off the scroll view, which is what the display link does every frame.
    ///
    /// `adjustedContentInset` and not `contentInset`: the adjusted one is what the scroll view actually clamps against, and it is what
    /// SwiftUI's `contentInsets` corresponds to.
    ///
    /// **`@MainActor` on the initialiser and not on the type**, which stays a plain value anything may hold: it is only the reading of a `UIScrollView` that
    /// belongs to the main actor, and every caller is already there — the per-frame clock, which is `@MainActor` whole. Stated rather than assumed, so the
    /// compiler keeps it true instead of a runtime check discovering otherwise.
    @MainActor
    init(_ scrollView: UIScrollView) {
        self.offset = scrollView.contentOffset.y
        self.height = scrollView.bounds.height
        self.topInset = scrollView.adjustedContentInset.top
        self.bottomInset = scrollView.adjustedContentInset.bottom
        self.contentHeight = scrollView.contentSize.height
    }

}


extension TheGeometryOfTheTranscript {

    /// The same five scalars, as SwiftUI reports them — **back for Step 46g**, the screen having returned to iOS 18.
    ///
    /// An initialiser from a `ScrollGeometry` lived here through Step 46a so that the two accounts could be put side by side, and went with the
    /// shadow at 46b. What it established then is why this exists now: the two agree on the visible height *exactly*, including at the
    /// reparameterisation where their terms differ — so a rule can be moved from one to the other without changing a single number it reads.
    /// The one difference is *when*, and that is the whole of 46g: this arrives before the frame is committed, a display link after it is
    /// presented. See `reading-the-geometry.md`.
    @available(iOS 18.0, *)
    init(_ geometry: ScrollGeometry) {
        self.init(offset: geometry.contentOffset.y,
                  height: geometry.containerSize.height,
                  topInset: geometry.contentInsets.top,
                  bottomInset: geometry.contentInsets.bottom,
                  contentHeight: geometry.contentSize.height)
    }

}
