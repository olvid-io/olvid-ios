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


/// Says which message a jump landed on.
///
/// **Four ways to arrive somewhere, and all four used to arrive in silence**: the message a reply answers, a search result, a notification, and the way back
/// to the end. The list scrolls, the scroll ends, and nothing says *this one*. Legacy answers with a pulse in `scrollToItemAtIndexPath`: the cell grows and
/// springs back a tenth of a second after its second scroll. So does this.
///
/// **The message grows and springs back.** Under **Reduce Motion** it takes a colour and lets it fade, movement being what must be spared. (The colour wash
/// was also built as an alternative to the pulse and judged on a device; the pulse won, and the wash survives only where motion must not happen.)
///
/// ## Four departures from legacy, each deliberate
///
/// **It emphasises the message, not the whole row.** ``SentMessageCellView/MessageItself`` is what a press shrinks and what the context menu lifts, so it is
/// the vocabulary for *this message*; the sender, the date and the reactions add nothing. It is applied to the message's **column** rather than to
/// `MessageItself`, which carries a greedy frame so the countdown can sit beside the bubble — applied there, the effect spanned the row and read as a
/// highlighted row rather than a message.
///
/// **It grows about the near edge, not the centre.** A bubble may take 80% of the width, so growing it about its centre pushes it into the row's margin.
/// Anchored at the edge it hangs from — the anchor the press shrink already uses — the outer edge stays put and the growth goes where there is room.
///
/// **It waits longer, and lasts longer.** Legacy's tenth of a second was measured here as too soon to see: it played while the eye was still travelling with
/// the scroll. The wait is the list's, in ``SingleDiscussionCellsListView``.
///
/// **It is a little larger than legacy's, and bouncier**, both settled by looking at it on an iPhone.
///
/// **It fires even when nothing scrolled.** A jump to a message already on screen moves the list not at all, and that is exactly when a reader most needs
/// telling which message was meant. It is driven by *arriving*, not by scrolling: the list says which row it landed on and how many jumps have happened, so a
/// repeat of the same row still emphasises it.
struct TheMessageAJumpLandedOn: ViewModifier {

    /// Which row this is, or nothing for something drawn like a message that is not one. Never emphasised then.
    let cellIdentifier: SingleDiscussionView.CellIdentifier?

    /// The edge this message hangs from, which is the anchor the pulse grows about.
    let side: TheSideAMessageHangsFrom

    @Environment(\.theRowAJumpLandedOn) private var theRowAJumpLandedOn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scale: CGFloat = 1
    @State private var wash: Double = 0

    /// How many washes this message has been given, so a fade scheduled for one arrival cannot cut short the colour of the next — see ``theWash()``.
    @State private var theWashesSoFar = 0

    func body(content: Content) -> some View {
        content
            // **Over the bubble, not behind it.** A tint laid *behind* a message is invisible: a bubble is opaque, deliberately so — see ``MessageBubbleView``,
            // where the fill is laid over the page's own colour precisely to stop anything showing through. So the colour goes on top, faint enough to read as the
            // bubble changing colour rather than as something covering it.
            //
            // An overlay takes no part in sizing, so this cannot change the row's height — which on this screen is a thing to be careful about.
            .overlay {
                MessageBubbleMetrics.shape
                    .fill(Self.theColourOfTheWash)
                    .opacity(wash)
                    .allowsHitTesting(false)
            }
            // A rendering transform: nothing is re-measured, and no row can make the list re-lay itself out on account of this.
            .scaleEffect(scale, anchor: side.nearEdge)
            .onChange(of: theRowAJumpLandedOn) { landedOn in
                guard let cellIdentifier, landedOn.row == cellIdentifier else { return }
                saysThisIsTheOne()
            }
    }


    /// Says *this one*, in whichever of the two ways is in force.
    private func saysThisIsTheOne() {
        if reduceMotion {
            theWash()
        } else {
            thePulse()
        }
    }


    /// The message takes a colour and lets it fade — the Reduce Motion answer, where the pulse must not happen.
    ///
    /// **The two halves must be in two transactions, and writing them as one drew nothing at all.** This was
    /// `wash = howStrongTheWashIs` followed immediately by `withAnimation { wash = 0 }`, in the same synchronous block: SwiftUI coalesces both writes into one
    /// update and interpolates from the last **rendered** value, which is 0, to 0. So the animation ran, and ran between two identical values, and a reader with
    /// Reduce Motion on got no indication whatever of which message a jump had landed on — the one group of readers least able to follow an unannounced scroll,
    /// and the failure invisible to everyone else.
    ///
    /// The shape is ``AMessageThatCanBeLifted``'s practice: what must appear at once goes
    /// in a transaction with `disablesAnimations`, and what must animate goes in a transaction of its own, one turn of the main actor later.
    private func theWash() {
        theWashesSoFar += 1
        let thisWash = theWashesSoFar
        var atOnce = Transaction()
        atOnce.disablesAnimations = true
        withTransaction(atOnce) { wash = Self.howStrongTheWashIs }
        Task { @MainActor in
            // **Guarded on the state it belongs to**, which is the other half of the same rule: a second jump onto this message lays a fresh colour on, and this
            // fade — scheduled for the first — would otherwise start from full and cut it short. `@State` is read through its storage, so this sees the value as
            // it is now rather than as it was when the closure was made.
            guard theWashesSoFar == thisWash else { return }
            withAnimation(.easeIn(duration: Self.howLongTheWashTakesToGo)) { wash = 0 }
        }
    }


    /// The message grows, and springs back.
    ///
    /// **Two animations, and the second waits for the first to stop moving.** The first version took the size *instantly* and only sprang on the way back, to avoid
    /// sequencing — and it popped rather than moved: a tenth of the bubble appearing between one frame and the next reads as a flicker, not as a message putting its
    /// hand up. Growing takes a moment, and then the spring's overshoot carries it home.
    ///
    /// **`completionCriteria: .removed`, not a `Task.sleep` matched to the growth.** The
    /// reason is exactly this shape: a hand-copied duration drifts the moment
    /// anyone tunes the curve, and under Debug ▸ Slow Animations the second animation would start while the first was still running.
    private func thePulse() {
        guard #available(iOS 17.0, *) else {
            // Never reached: this screen's list requires iOS 18. Present so the file compiles at the module's deployment target, and honest about what it gives —
            // the pop that the sequencing above exists to avoid.
            scale = Self.howMuchTheMessageGrows
            withAnimation(.spring(duration: Self.howLongTheMessageTakesToSettle, bounce: Self.howMuchThePulseOvershoots)) { scale = 1 }
            return
        }
        withAnimation(.easeOut(duration: Self.howLongTheMessageTakesToGrow), completionCriteria: .removed) {
            scale = Self.howMuchTheMessageGrows
        } completion: {
            withAnimation(.spring(duration: Self.howLongTheMessageTakesToSettle, bounce: Self.howMuchThePulseOvershoots)) { scale = 1 }
        }
    }


    /// **Turned up to be looked at, 2026-08-16.** Legacy's own value is `1.1` — `CGAffineTransform(scaleX: 1.1, y: 1.1)` — and this is deliberately past it, to
    /// see how much is too much. A tenth reads very differently on a one-line bubble and on a tall one, which is why the number wants judging on real messages
    /// rather than choosing.
    private static let howMuchTheMessageGrows: CGFloat = 1.18

    /// **Quick, but not instant.** Legacy takes 0.3s over this; the movement wants to be brisk enough to read as a gesture rather than as a slow inflation, and long
    /// enough that the eye catches it happening at all.
    private static let howLongTheMessageTakesToGrow: TimeInterval = 0.15

    /// The way back, where the life is. Slower than the growth, so the shape of the whole thing is a quick reach and an unhurried settle.
    private static let howLongTheMessageTakesToSettle: TimeInterval = 0.7

    /// How far it goes past its own size on the way home. Legacy springs with a damping of 0.5, which is bouncy by any measure; this is a little less, so the
    /// message settles rather than wobbles. **Turned up past that, 2026-08-16**, along with the growth: at `0.6` it wobbles on purpose.
    private static let howMuchThePulseOvershoots: Double = 0.6

    /// Faint: this tints a bubble, it does not select one, and the bubble under it is already coloured.
    private static let howStrongTheWashIs: Double = 0.30

    /// **Slower than the pulse, that being the point of it.** With an ease-*in*, which starts slowly: the colour holds while the reader's eye arrives and then goes
    /// quickly, rather than beginning to fade at the moment it appears.
    private static let howLongTheWashTakesToGo: TimeInterval = 2

    /// The accent the rest of this screen marks things with, laid over the bubble.
    private static let theColourOfTheWash = Color.accentColor

}


extension View {

    /// Says *this one* when a jump lands on this message — see ``TheMessageAJumpLandedOn``.
    func emphasisedWhenAJumpLandsOnIt(_ cellIdentifier: SingleDiscussionView.CellIdentifier?, hangingFrom side: TheSideAMessageHangsFrom) -> some View {
        modifier(TheMessageAJumpLandedOn(cellIdentifier: cellIdentifier, side: side))
    }

}


// MARK: - What the list says

/// Which row a jump has just landed on, and how many jumps there have been — see ``TheMessageAJumpLandedOn``.
///
/// **The count is what lets the same message be emphasised twice.** A reader who taps the same reply header again, or steps back onto a search result they have
/// already seen, has arrived again and must be told again; a value carrying only the row would compare equal and say nothing.
struct TheRowAJumpLandedOn: Equatable {

    let row: SingleDiscussionView.CellIdentifier?

    /// Incremented on every arrival, so that landing twice on one row is two events.
    let jumps: Int

    static let none = Self(row: nil, jumps: 0)

    func landedOn(_ row: SingleDiscussionView.CellIdentifier) -> Self {
        .init(row: row, jumps: jumps + 1)
    }

}


extension EnvironmentValues {

    /// Which row a jump has just landed on — see ``TheRowAJumpLandedOn``.
    ///
    /// **Written rarely, which is what makes the environment acceptable here.** Every cell is rebuilt when this changes, at some 8µs each; a jump is a thing a
    /// reader does now and then, so that is a cost paid on an event rather than on the scrolling path.
    var theRowAJumpLandedOn: TheRowAJumpLandedOn {
        get { self[TheRowAJumpLandedOnKey.self] }
        set { self[TheRowAJumpLandedOnKey.self] = newValue }
    }

}


private struct TheRowAJumpLandedOnKey: EnvironmentKey {
    static let defaultValue: TheRowAJumpLandedOn = .none
}
