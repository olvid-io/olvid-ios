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


/// One button, revealed when the pointer is over a message, that opens what that message offers, Mac Catalyst only.
///
/// **One button where legacy has two, and that is the transcription rather than a simplification.** Legacy reveals two 30pt circles on hover: `chevron.down`
/// carrying the message's `UIMenu`, and `face.smiling` opening the reactions picker. It needs two because its affordances genuinely are two. **Ours have been
/// one thing since 21d**: a single press produces one overlay carrying the menu *and* the bar of favourite emojis. So two buttons would reproduce legacy's
/// plumbing rather than its intent. This reports `heldLongEnough` into ``PressesOnMessages`` — the same sentence the press and Step 55's secondary click say
/// — for which the overlay, the bar, the lift and the dismissal all come free.
///
/// An **ellipsis**, because on this screen that already means *what this offers*: it is what the navigation bar's own menu is drawn as. `chevron.down` on a
/// bubble means nothing in particular.
///
/// **Why it is worth having.** It is the second door, not a small extra: Step 54 withdrew the press **and** the double tap on this platform, so a secondary click
/// is otherwise the only route to a message's menu — and a reader who tries neither gesture has none.
///
/// **The gating question dissolved on reading.** Legacy hides `face.smiling` when `ownedIdentityIsAllowedToSetReaction` is false, so the obvious rule here
/// was *show it when the message offers anything* — `!offers.isEmpty`. **But asking costs a Core Data query against a child context**, which is exactly what
/// Step 21a exists to keep off the scrolling path, and a pointer crossing a discussion would ask once per row. It does not have to be asked:
/// `whatTheMessageOffers` appends **`.select` unconditionally**, so `offers.isEmpty` is true only for a message that could not be fetched at all — one just
/// deleted. The button is shown whenever the pointer is over a message, and that one case is handled where it belongs: `lift()` asks for the offers, finds
/// them empty, and returns to idle without drawing anything.
struct TheShortcutThatAppearsOnHover: ViewModifier {

    /// **Optional**, for the reason ``AMessageThatCanBeLifted`` gives: something drawn like a message but which is not one carries this modifier and
    /// never shows a button.
    let cellIdentifier: SingleDiscussionView.CellIdentifier?

    /// What this message is, carried so that the overlay can draw a copy of it — as the press and the secondary click carry it, and for the reason
    /// written on ``PressOnAMessage/heldLongEnough(_:showing:)``.
    let model: SingleDiscussionCellView.Model

    /// Which side the message hangs from, so the button can sit on the other one — see ``whereTheButtonSits``.
    let side: TheSideAMessageHangsFrom

    /// Whether the pointer is anywhere on this **row**, which is what decides whether the button is drawn.
    ///
    /// **Not hover on the message, and that distinction is the whole of it.** The first version noticed the pointer on the column, which is where the button
    /// is placed *from* — and the button is placed 40pt **outside** that column, so moving towards it left the region that was keeping it alive and it
    /// vanished on the way. Reported immediately, and unarguable: a control you cannot reach is not a control.
    ///
    /// So the noticing happens on the row and the placing on the column, and the two are joined by a piece of state in the cell view that contains both. See
    /// ``TheRowThatNoticesThePointer``.
    let thePointerIsOverTheRow: Bool

    #if targetEnvironment(macCatalyst)

    @Environment(\.pressesOnMessages) private var pressesOnMessages

    /// Whether the reader is choosing messages, in which case no shortcut is offered.
    ///
    /// The screen already stops the button from being *pressed* in that mode, its one `allowsHitTesting` covering everything in the content tree. This
    /// is about not drawing it at all: a control that appears under the pointer and does nothing is worse than one that never appears.
    @Environment(\.theReaderIsChoosingMessages) private var theReaderIsChoosingMessages

    func body(content: Content) -> some View {
        content
            // **An overlay, so it takes no part in sizing.** A button placed in the layout would change what the message measures, and this screen
            // has just spent a day on a copy three points wider than its message; nothing that appears and disappears may touch a row's height.
            .overlay(alignment: whereTheButtonSits) {
                if thePointerIsOverTheRow, !theReaderIsChoosingMessages, cellIdentifier != nil {
                    theButton
                        // **Its own width *plus* the gap, and the width is the half that was missing.** An overlay aligns the button's edge with the
                        // column's, so the button sits *inside* the message: offsetting by the gap alone pulled ten points of thirty out and left the
                        // rest on the bubble, which is what the first version looked like. `offset` moves what is drawn and not the layout frame, which
                        // is what keeps this from touching the row's height.
                        .offset(x: side == .leading ? Self.howFarFromTheEdge : -Self.howFarFromTheEdge)
                        .transition(.opacity)
                }
            }
    }


    /// **A glyph on a surface of its own, and not `ellipsis.circle.fill`.** The first version was that symbol drawn in `secondaryLabel`, and it was
    /// close to invisible in dark mode — reported on sight. A secondary label is *meant* to recede, which is the wrong instruction for the only control
    /// a message has; and a symbol's own filled circle takes the same colour family as its glyph, so there is nothing to raise it off the page.
    ///
    /// So: a 30pt circle — **legacy's own size** — on a solid adaptive surface, with the glyph in `.primary`, which is near-white in dark mode by
    /// definition rather than by luck.
    ///
    /// **A material was tried first and is not used**, which is worth a line: a blur takes its lightness from whatever is behind it, so the same control
    /// read differently over a blue bubble and over the page, and the glyph on top of it came out grey where it should have been white. A control that must
    /// be legible everywhere is better served by a surface that does not consult its surroundings. The hairline stays, for the light appearance where the
    /// surface and the page are close together.
    private var theButton: some View {
        Button {
            guard let cellIdentifier else { return }
            pressesOnMessages?.report(.heldLongEnough(cellIdentifier, showing: model))
        } label: {
            Image(systemIcon: .ellipsis)
                .font(.system(size: Self.howBigTheGlyphIs, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: Self.howBigTheButtonIs, height: Self.howBigTheButtonIs)
                .background {
                    Circle()
                        .fill(Color(UIColor.secondarySystemBackground))
                        .overlay {
                            Circle().strokeBorder(Color(UIColor.separator), lineWidth: 0.5)
                        }
                }
        }
        // **Without this it never fires.** A `Button` inside a `List` row with the automatic style becomes the *row's* button — the cell
        // takes the click and the action does not run. Every button in this discussion carries it.
        .buttonStyle(.plain)
        .accessibilityLabel(Text("MESSAGE_ACTIONS"))
    }


    /// Which corner of the message the button is drawn against: the edge **facing the middle of the screen**, which is the one the message does not
    /// hang from.
    ///
    /// Legacy places its pair 10pt clear of the bubble's *leading* edge for both kinds of cell. That is right for a message sent, which hangs trailing,
    /// and wrong here for one received: ours hang hard against the leading margin, so a button 10pt further out would sit off the edge of the window.
    /// Reading the side the message hangs from and taking the other one is the same rule for both, and never leaves the screen.
    ///
    /// Vertically at the **top**, not the middle: legacy centres on its middle *popable subview*, a notion this screen has no equivalent of, and a
    /// message may be many times taller than the button. The top edge is where the eye already is, and it is where the reply header and the badges are,
    /// so the button lands beside the beginning of the message rather than halfway down a paragraph.
    private var whereTheButtonSits: Alignment {
        switch side {
        case .leading: return .topTrailing
        case .trailing: return .topLeading
        case .centre: return .top
        }
    }


    #else

    func body(content: Content) -> some View {
        content
    }

    #endif


    /// Legacy's 10pt of air between the button and the bubble, kept.
    private static let howFarClearOfTheBubble: CGFloat = 10

    /// How far the button is offset from the message's edge: **clear of it entirely**, hence its own width as well as the gap.
    private static var howFarFromTheEdge: CGFloat { howBigTheButtonIs + howFarClearOfTheBubble }

    /// Legacy's own 30pt circle, kept.
    private static let howBigTheButtonIs: CGFloat = 30

    /// The glyph inside it.
    ///
    /// `.system(size:)` rather than a text style, which is allowed exactly here: this is a **fixed-size container**, and a glyph that grew with
    /// Dynamic Type would leave the circle. What the button offers is reachable another way — the right click of Step 55 — so nothing is withheld from a
    /// reader who has asked for larger text.
    private static let howBigTheGlyphIs: CGFloat = 15

    /// Long enough not to flicker as the pointer crosses a row, short enough to feel like a response.
    fileprivate static let howLongItTakesToAppear: TimeInterval = 0.12

}


/// Notices the pointer anywhere on a **row**, so that ``TheShortcutThatAppearsOnHover`` can be reached, Mac Catalyst only.
///
/// **The other half of the pair, and it exists because of one usability fault.** The button is drawn from the message's own column and offset clear of
/// it; if the *noticing* is done on that same column, the pointer leaves it on the way to the button and the button goes. So the row notices and the
/// column places, joined by one piece of state in the cell view that contains both.
///
/// **A whole row is hover-detectable and a stack is not.** The cell's stack is greedy in width but its empty half draws nothing, and SwiftUI hit-tests
/// what is drawn — the same fact that has a bubble's own tap living in a `.background` behind its content, because `Text` is not hit-testable. So a
/// `contentShape` is needed for the pointer to be noticed beside a short message.
///
/// **That shape is safe here in a way it would not be on a touch platform.** A `contentShape` over a whole row makes every row
/// liftable; what makes this different is that on Catalyst there are **no SwiftUI gestures left on a message** — Step 54 withdrew the press and the
/// double tap, and what remains is UIKit's, on the cell rather than in the content. Nothing here can be mis-targeted because there is nothing left to
/// target. It is compiled nowhere else.
struct TheRowThatNoticesThePointer: ViewModifier {

    @Binding var thePointerIsOverTheRow: Bool

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
            .contentShape(Rectangle())
            .onHover { isOver in
                withAnimation(.easeOut(duration: TheShortcutThatAppearsOnHover.howLongItTakesToAppear)) {
                    thePointerIsOverTheRow = isOver
                }
            }
        #else
        content
        #endif
    }

}
