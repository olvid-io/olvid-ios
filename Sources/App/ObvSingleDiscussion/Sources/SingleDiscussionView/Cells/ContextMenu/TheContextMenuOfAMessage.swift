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


/// Where the reader is in the act of pressing a message: nothing, a finger down, a message lifted, a message on its way back.
///
/// **One enum rather than a handful of booleans**, so that a second press arriving during a dismissal cannot start a second lift, and so that *what is on screen*
/// is answerable by reading one value. Every transition below is guarded by the state it must have come from, which is what makes the guards cheap to read: there
/// is exactly one place each of them can be wrong.
enum TheContextMenuOfAMessage: Equatable {

    /// The discussion as it is almost all of the time.
    case idle

    /// A finger is down on a message and has not yet been there long enough to mean anything.
    case pressing(SingleDiscussionView.CellIdentifier)

    /// A message is up, its copy drawn over the discussion by ``MessageContextMenuOverlay``.
    case lifted(Lifted)

    /// The message is travelling back to where it came from. Nothing may be lifted until it has arrived.
    ///
    /// It carries the same payload as ``lifted``, because the overlay goes on drawing throughout the return: the copy has to travel back to the message it came
    /// out of, and a copy that vanished the instant the reader dismissed it would be a jump rather than a return.
    case dismissing(Lifted)

    /// Everything the overlay needs, settled once when the press was recognised and not asked for again.
    ///
    /// The *offers* above all: they are computed on the main thread against the view context, three of the rules behind them simulating the operation on a child
    /// context, so they are asked for exactly once per press — never per frame, and never per message. See ``WhatAMessageOffers`` and step 21a.
    struct Lifted: Equatable {

        let cellIdentifier: SingleDiscussionView.CellIdentifier

        /// What the message was when it was lifted. The copy is drawn from this, so that the overlay needs no stream of its own.
        let model: SingleDiscussionCellView.Model

        let offers: WhatAMessageOffers

        /// What the reader may react with, asked in the same breath as the offers — see ``TheEmojisOnOffer``.
        let emojis: TheEmojisOnOffer

    }


    /// The message whose copy the overlay draws, and which is therefore hidden in the list — on its way up, while it is up, and on its way back down.
    ///
    /// A message merely being *pressed* is still the real one — it only shrinks a little — which is why this is not simply "the message this state is about".
    var whatTheOverlayHasTaken: Lifted? {
        switch self {
        case .idle, .pressing: return nil
        case .lifted(let lifted), .dismissing(let lifted): return lifted
        }
    }


    /// What the messages of the discussion need to know: which of them is under a finger, and which of them the overlay has taken.
    ///
    /// A message stays hidden for the whole of the dismissal and is only given back once this returns to ``idle`` — never crossfaded with its copy, which is what
    /// produces a double image.
    var asTheMessagesSeeIt: TheMessageBeingLifted {
        switch self {
        case .idle:
            return .none
        case .pressing(let cellIdentifier):
            return .init(beingPressed: cellIdentifier, takenByTheOverlay: nil)
        case .lifted(let lifted), .dismissing(let lifted):
            return .init(beingPressed: nil, takenByTheOverlay: lifted.cellIdentifier)
        }
    }


    /// Whether anything at all is up, which is what freezes the transcript.
    var isUp: Bool {
        self != .idle
    }

}


// MARK: - How it moves


extension TheContextMenuOfAMessage {

    /// How long the copy is given to travel back before the real message is shown again — **on iOS 16 only, and consulted
    /// nowhere else.**
    ///
    /// From iOS 17 the animation reports its own completion and this number takes no part in it. It used to: the dismissal
    /// slept for exactly this long and then took the overlay down, which is a hand-copied duplicate of the animation's
    /// duration and wrong in two ways. It drifts the moment anybody tunes the spring below — and it ignores the animation
    /// altogether, so under Debug ▸ Slow Animations the copy set off on its slow way back and then vanished mid-flight,
    /// this clock having run out while the animation was still running. See `SingleDiscussionView.putTheMessageBack()`.
    ///
    /// **The two must not overlap.** The message is given back on a later frame than the copy's arrival, never at the same
    /// moment: a crossfade between a copy and its original is seen as a double image, which is the one artefact this whole
    /// arrangement exists to avoid. Which is why this is deliberately *longer* than ``theReturn`` takes to settle — about
    /// 0.25s — and why, where it is still used, erring long is the safe direction.
    static let howLongTheReturnTakes: TimeInterval = 0.34

    /// The same, when the reader has asked for less movement. iOS 16 only, as above.
    static let howLongTheReturnTakesWithReducedMotion: TimeInterval = 0.2

    /// The one spring the eye ever sees: the message rising, the card growing out of its corner, the backdrop coming up.
    static let theLift: Animation = .spring(response: 0.35, dampingFraction: 0.75)

    /// The same movement, for a reader who has asked for less of it.
    static let theLiftWithReducedMotion: Animation = .easeOut(duration: 0.2)

    static let theReturn: Animation = .spring(response: 0.32, dampingFraction: 0.82)

    static let theReturnWithReducedMotion: Animation = .easeIn(duration: 0.2)

}


// MARK: - The shadow a held message casts


/// The shadow cast by a copy of a message while something on this screen is holding it above the rest.
///
/// One type for both treatments, because they hand the same copy to one another: choosing *Reply* from the context menu passes the lifted copy to the
/// composition bar's treatment in one frame, with animations disabled. Anything the two ends disagree about is seen in that frame, and written as a literal at
/// each end they did disagree, `0.18/14/6` against `0.08/6/1`. Both ends name a case here instead, and ``SwiftUICore/View/casts(_:)`` draws it, so the
/// compositing is shared too.
struct TheShadowAHeldMessageCasts: Equatable {

    /// How much of `Color.primary` the shadow is. It is `primary` rather than black because both shadows separate a held message from something that resolves
    /// near-black in dark mode — a backdrop in one case, a blur of the discussion in the other — and black over near-black separates nothing. `Color.primary`
    /// is black in light mode and white in the dark, where a held object is read by a halo. `TheButtonBackToTheEnd` uses the same colour for the same reason.
    let opacity: Double
    let radius: CGFloat
    let y: CGFloat

    /// What a message sitting in the transcript casts, and therefore what a copy placed exactly over one must cast in the frame it is placed. Both treatments
    /// begin and end here.
    static let none = Self(opacity: 0, radius: 0, y: 0)

    /// Held clear of the screen by the context menu, over a backdrop, with a card beside it: the message is a long way up and says so.
    static let whileLiftedByTheMenu = Self(opacity: 0.18, radius: 14, y: 6)

    /// Held beside the composition bar, against a blur of the discussion. Shallower than the lift: this message is resting rather than raised, and the shadow
    /// only has to separate the bubble from a blur that can be close to it in colour.
    static let whileHeldBesideTheBar = Self(opacity: 0.08, radius: 6, y: 1)

}


extension View {

    /// Casts ``TheShadowAHeldMessageCasts`` over this view as one shape.
    ///
    /// The `compositingGroup()` is the point of having this at all. Without a compositing boundary SwiftUI applies `.shadow` to every drawn primitive, so the
    /// bubble, the glyphs, the date row, each status icon and the reactions chip each take one: a smudge behind the text instead of a card lifted off the
    /// background. Both callers need the same composite as much as the same numbers, so it is shared here rather than left to each call site.
    ///
    /// The offscreen pass costs one per treatment and not one per row, there being at most one held copy on the screen.
    func casts(_ shadow: TheShadowAHeldMessageCasts) -> some View {
        compositingGroup()
            .shadow(color: .primary.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
    }

}
