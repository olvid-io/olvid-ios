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
import ObvSystemIcon


/// How a message is ticked on a Mac — the tick, the room it takes, and the click that makes it. Step 42e.
///
/// **Why a Mac has its own.** A `List` given a selection brings Catalyst's rules with it: a click **replaces** what is chosen and ⌘-click adds to it, which
/// a reader choosing messages to delete should not have to know. Two attempts to change that from outside failed — `allowsMultipleSelection` forced to
/// `true`, and an overlay taking the click before UIKit saw it, which left a dead band beside the list's own circle — and both failed for one reason: **they
/// tried to reinterpret a click while UIKit's selection was still running.**
///
/// So on Catalyst the `List` is given **no** selection at all and this draws the tick instead. There is nothing left to fight: no ⌘ semantics, no
/// active-against-inactive tinting, and no part of the row belonging to somebody else — the dead band was the system circle's own.
///
/// **iOS and iPadOS do not come near this file**, which compiles to its content everywhere else. The platform branch exists in exactly two places, this and
/// the list's selection; everything below the row — the state, the tick, `WhatCanBeDeleted`, the deletion — is common.
///
/// **A plain click toggles**, with no modifier held: a deliberate departure from a platform whose lists all use ⌘, because every row has become a tick box
/// and the reader has already said what they are doing.
///
/// ⇧-click extends a range and is **42e's second stage**, not built here. ⌘-click toggles exactly as a plain click does rather than doing nothing: a reader
/// with the habit will hold it, and a control that is dead under a modifier is the worse outcome.
struct AMessageTickedOnAMac: ViewModifier {

    /// Which message this row is. The tick belongs to it, and so does what a click on the row does.
    let cellIdentifier: SingleDiscussionView.CellIdentifier

    let theReaderIsChoosingMessages: Bool

    @Binding var selectedCellIdentifiers: Set<SingleDiscussionView.CellIdentifier>

    /// What a click on this row means, answered by whoever holds the rows in the order they are drawn — see ``AMessageTickedOnAMac/theClickIsReported``.
    ///
    /// **A report rather than the work**, and the reason is the range: extending needs the rows *as displayed*, which is a thousand identifiers this row has no
    /// business holding and which would be compared per row on every update if it did. The list has it already.
    let theReaderClicked: (SingleDiscussionView.CellIdentifier, Bool) -> Void

    /// Whether this row may be ticked at all.
    ///
    /// The marker saying how many messages arrived is not a message: it sits inside the `ForEach` so that the screen can scroll to it, and on a touch platform it
    /// is `selectionDisabled` for exactly this reason. The sentence about encryption needs no rule — it is outside the `ForEach` and never had a tick.
    private var thisRowMayBeTicked: Bool {
        cellIdentifier != .newMessagesMarker
    }

    private var isTicked: Bool {
        selectedCellIdentifiers.contains(cellIdentifier)
    }

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        HStack(spacing: Self.roomBetweenTheTickAndTheMessage) {
            // **An `if` and not a container**, so that a row draws no tick and takes no spacing for one when nothing is being chosen. A container holding
            // nothing is still a subview the stack spaces around, which once cost 12pt of air in a message cell.
            if theReaderIsChoosingMessages, thisRowMayBeTicked {
                theTick
            }
            content
        }
        // **The click is taken above the content, never inside it.** 42b takes the message's own gestures out of hit testing while choosing, and this is applied
        // after that — so a click on a photograph ticks the message rather than opening it, while a click anywhere else on the row does the same. Because the
        // tick is *inside* this stack rather than drawn by the `List` beside it, the overlay covers the whole row and there is no band belonging to nobody.
        .overlay {
            if theReaderIsChoosingMessages, thisRowMayBeTicked {
                theClickIsReported
            }
        }
        #else
        content
        #endif
    }


    /// The tick itself — **a filled circle with a white check when chosen, an empty outline when not**, which is what a `List` draws on a touch platform and what
    /// this has to be indistinguishable from.
    ///
    /// **`palette` rendering, and that is what puts a white check on a coloured circle**: a single foreground style would tint the whole glyph, giving a blue
    /// check on a blue circle. The two styles are the check and then the circle, in that order.
    ///
    /// **The empty outline has one layer, and in `palette` mode its only layer takes the *first* style.** So that style is the check's white only when ticked;
    /// unticked, it is the outline's own grey, or the outline is drawn white and cannot be seen in light mode.
    ///
    /// **A fixed footprint, reserved whether it is ticked or not.** The two glyphs are not the same size to the point, and anything that changes size with state
    /// while sharing a row with something else is a thing that can decide the row's height — which on this list has thrown the transcript to the top of a
    /// discussion for half a point. The frame is the same for both, and the symbol is drawn inside it.
    @ViewBuilder
    private var theTick: some View {
        Image(systemIcon: isTicked ? .checkmarkCircleFill : .circle)
            .symbolRenderingMode(.palette)
            .foregroundStyle(isTicked ? Color.white : Color.secondary, isTicked ? Color.accentColor : Color.secondary)
            .font(.system(size: Self.theSizeOfATick))
            .frame(width: Self.theFootprintOfATick, height: Self.theFootprintOfATick)
    }


    /// **The click, and whether ⇧ was held when it was made** — Step 42e's second stage.
    ///
    /// **A `UITapGestureRecognizer` and not `onTapGesture`, and the reason is one missing API.** SwiftUI cannot say that a modifier was held: `Gesture.modifiers(_:)`
    /// exists on macOS and Catalyst's SwiftUI is the iOS family, so there is nothing to ask. A tap recogniser has `modifierFlags`, and this screen reaches for UIKit
    /// wherever a gesture needs something SwiftUI cannot say — ``TheSwipeThatRepliesToAMessage``, ``TheSecondaryClickOnAMessage``, ``TheAttachmentsOfAMessageDraggedOut``.
    ///
    /// **It is the same overlay it replaces, in the same place**, rather than a recogniser on the row's cell — which was the other way to do it and is the one
    /// that would have had to be walked from nothing. Hit testing is unchanged: 42b takes the message's content out of it, this sits above, and a click anywhere
    /// on the row still ticks. What changes is only that the tap is now UIKit's and can be asked what was held.
    ///
    /// **Behind the same `#if` as the representable it builds** — it is referenced only from the Catalyst branch of `body`, but a computed property is compiled
    /// whether or not anything reaches it, and the iOS build said so within a minute of the Mac's succeeding. That is what a second platform's compiler is for.
    #if targetEnvironment(macCatalyst)
    private var theClickIsReported: some View {
        ATapThatKnowsWhatWasHeld { shiftWasHeld in
            theReaderClicked(cellIdentifier, shiftWasHeld)
        }
    }
    #endif


    /// How large the tick is drawn, and the footprint it is given.
    ///
    /// **Both are provisional until they have been held against an iPad**, which is what 42e says to do rather than choose something plausible: the tick has to be
    /// indistinguishable from the one the `List` draws, and that is a comparison and not a number to be reasoned out.
    ///
    /// `system(size:)` rather than a text style, because the footprint is fixed and type that grows would leave it, a fixed-size
    /// container needing fixed-size type. That is only acceptable where the text repeats what is shown another way, and **this is the exception**: a tick is the only thing saying a
    /// message is chosen. So if the accessibility sizes need it, the footprint grows with them rather than the glyph being clipped, and that is a thing to look at
    /// with the sizes turned up.
    private static let theSizeOfATick: CGFloat = 22

    private static let theFootprintOfATick: CGFloat = 24

    /// The gap between the tick and the message beside it.
    ///
    /// **12 and not 8**, judged on a Mac on 2026-08-17: at 8 the tick crowded a *received* message, which is the case that shows it — a sent message hangs from
    /// the far edge and has the width of the screen between the two, so it looks right at any value and says nothing about this number.
    private static let roomBetweenTheTickAndTheMessage: CGFloat = 12

}


#if targetEnvironment(macCatalyst)

/// A click, and whether ⇧ was held as it was made — the one thing `onTapGesture` cannot report. See ``AMessageTickedOnAMac``.
///
/// Deliberately the plainest representable on this screen: a bare `UIView` with one recogniser, no state, and nothing drawn. It occupies the overlay a
/// `Rectangle` used to, so what a click reaches is unchanged and only what is asked of it differs.
private struct ATapThatKnowsWhatWasHeld: UIViewRepresentable {

    let clicked: (Bool) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.theReaderClicked(_:))))
        return view
    }

    /// **Re-pointed rather than rebuilt**, cells being reused: the closure captures the row this modifier is currently for, and a coordinator kept from a
    /// previous row would report the message that row used to show — the fault Step 55 found in a log and Step 40 found again in the same walk.
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.clicked = clicked
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(clicked: clicked)
    }

    @MainActor
    final class Coordinator: NSObject {

        var clicked: (Bool) -> Void

        init(clicked: @escaping (Bool) -> Void) {
            self.clicked = clicked
        }

        /// **⌘ is not asked about, and that is the decision rather than an omission** — a Mac reader with the habit will hold it, and a control that does
        /// nothing under a modifier is the worse outcome. So ⌘-click toggles exactly as a plain click does, which is what this reports.
        @objc func theReaderClicked(_ tap: UITapGestureRecognizer) {
            clicked(tap.modifierFlags.contains(.shift))
        }

    }

}

#endif


extension View {

    /// How a message is ticked on a Mac — see ``AMessageTickedOnAMac``. Nothing at all on a touch platform, where the `List` does it.
    func aMessageTickedOnAMac(_ cellIdentifier: SingleDiscussionView.CellIdentifier,
                              theReaderIsChoosingMessages: Bool,
                              selectedCellIdentifiers: Binding<Set<SingleDiscussionView.CellIdentifier>>,
                              theReaderClicked: @escaping (SingleDiscussionView.CellIdentifier, Bool) -> Void) -> some View {
        modifier(AMessageTickedOnAMac(cellIdentifier: cellIdentifier,
                                      theReaderIsChoosingMessages: theReaderIsChoosingMessages,
                                      selectedCellIdentifiers: selectedCellIdentifiers,
                                      theReaderClicked: theReaderClicked))
    }

}
