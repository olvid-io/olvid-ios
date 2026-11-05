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


/// Where the reader is in the act of replying to a message: nothing, a message held beside the composition bar, a message on its way out.
///
/// **A sibling of ``TheContextMenuOfAMessage`` rather than a case of it.** The two are the screen's two full-screen treatments and they may never both be up, but
/// they are not variations of one thing: that one draws a copy with a card of entries under it and clamps the pair into the space available, where this one takes
/// a copy to the bottom of the screen and leaves it there while the reader writes. One enum each, and one guard each refusing while the other is up, says that
/// more plainly than a fifth case would.
///
/// **What legacy does, and where this departs from it**, measured off a screen recording of the shipping app on 2026-08-27 rather than reasoned about:
/// `NewSingleDiscussionViewController.addMessageViewForReplyIfNeeded(from:)` snapshots `cell.viewForTargetedPreview` — the whole `contentView`, so the date
/// travels with the bubble — pins it 10pt above the composition bar, blurs everything behind it and, once it has landed, **hides the navigation bar**. This
/// screen lifts the **message alone**, as Step 21b's context menu does, and leaves the navigation bar where it is: two deliberate departures, taken on
/// 2026-08-27 for consistency with the treatment already on this screen rather than with the one being replaced.
enum TheMessageBesideTheCompositionBar: Equatable {

    /// The discussion as it is almost all of the time.
    case none

    /// A message is down beside the composition bar, the rest of the discussion behind a blur.
    case beside(Beside)

    /// It is on its way out. Nothing may be taken up until it has gone.
    ///
    /// It carries the same payload as ``beside``, because the copy goes on being drawn throughout — a copy that vanished the instant the reader tapped would be
    /// a cut rather than a dismissal — and ``TheWayItLeaves`` for which of the two departures this is.
    case leaving(Beside, TheWayItLeaves)


    /// The two ways the copy goes, which are two different occasions rather than two tastes.
    ///
    /// **Added 2026-08-28, at the reader's asking, after the send was found not to put the message back at all.** With that fixed the send *did* put it back, by
    /// flying the copy home while the sent message arrived at the end of the discussion and the transcript scrolled to meet it — *"it's too much on screen"*.
    /// So a send stops flying anything.
    ///
    /// The distinction is not cosmetic. The ✕, Esc and a tap on the blur are the reader **cancelling**: the copy travelling back to its row is the screen saying
    /// *nothing happened, here is your message again*. A send has **finished the job**, and there is nothing to give back — the reply has become a message. Two
    /// occasions, two departures, and the screen decides which from *why the reply went* rather than from anybody telling it how to animate. See
    /// ``WhatTheCompositionBarAsks``.
    enum TheWayItLeaves: Equatable {

        /// Back to the message's own row, arriving exactly as the real message is un-hidden — so the swap is invisible and there is never a gap in the
        /// transcript. What every reader-initiated dismissal does.
        case travellingHomeToItsRow

        /// Fading where it sits, the copy never moving. What a send does.
        ///
        /// **This is what ``theWayOut``'s documentation has always described** — *"it fades out where it sits"* while *"the original fades back in up in its
        /// row"*, citing legacy's `HidableView.hide()` — and what the code did not do, there being no `opacity` on the copy anywhere. The discrepancy was
        /// recorded on 2026-08-27 and left for the reader to settle; this settles it for the send and leaves the travel where the reader is cancelling.
        ///
        /// **Both halves of that sentence are needed and the first build had only one**, which is worth keeping: a copy that fades where it sits never arrives in
        /// the row, so unless the message is given back as the fade *begins* its place stays blank throughout. See ``asTheMessagesSeeIt``.
        case fadingWhereItSits

    }

    /// Everything the overlay needs, settled once when the reply was asked for and not asked for again.
    struct Beside: Equatable {

        let cellIdentifier: SingleDiscussionView.CellIdentifier

        /// What the message was when it was taken. The copy is drawn from this, so that the overlay needs no stream of its own — and from the model the *cell*
        /// was drawing rather than from `cachedModelOfSingleDiscussionCellView`, for the two reasons ``PressOnAMessage/heldLongEnough(_:showing:)`` gives.
        let model: SingleDiscussionCellView.Model

        /// Where the copy starts, when it does not start from the message's own row: the context menu handing its lifted copy straight over. Nil for
        /// every other way in, the swipe included, where the journey begins where the message already is.
        let handedOver: TheCopyTheMenuHandsOver?

        /// How far **across** its row the message was drawn when the reader let go of it, and nought for every other way in.
        ///
        /// A swipe carries the message aside and the copy is placed over the *message*, not over the row it is about to spring back to. It comes back across as
        /// the journey descends, the way ``TheCopyTheMenuHandsOver/scale`` relaxes over the same journey: one movement rather than a sideways jump at let-go
        /// followed by a drop.
        let pulledAcrossBy: CGFloat

    }


    /// The message whose copy the overlay draws — on its way down, while it is down, and while it goes.
    ///
    /// **Not the same question as whether the real message is hidden**, which is ``asTheMessagesSeeIt``, and the two part company for exactly 0.2s at the end of
    /// a send. See there.
    var whatTheOverlayHasTaken: Beside? {
        switch self {
        case .none: return nil
        case .beside(let beside), .leaving(let beside, _): return beside
        }
    }


    /// What the messages of the discussion need to know, in the one value ``TheContextMenuOfAMessage`` also answers in.
    ///
    /// **Nothing is ever reported as *pressed* here**: a reply is asked for by a gesture that has already finished — a swipe let go of, or an entry chosen from a
    /// menu that is on its way down — so there is no finger to say anything about.
    ///
    /// **The real message is given back the moment a send's fade begins, and that is the crossfade** — added 2026-08-28. Everywhere else the copy is drawn, the
    /// message beneath it is hidden, and the two are one question; ``TheWayItLeaves/fadingWhereItSits`` is the one case where they are not. A copy that fades
    /// where it sits never arrives anywhere, so nothing covers the message's place while it goes — and the first build of this left a message-shaped blank in the
    /// transcript for the length of the fade, which the reader saw at once. Giving the message back at the *start* of the fade instead means the copy dissolves
    /// beside the bar while the message reappears up in its row, both over ``theWayOut``.
    ///
    /// **It is Step 21b's forbidden crossfade, in the one place that rule was always going to allow it.** That rule exists because a copy fading out *over* the
    /// message it came from reads as a double image. These two are at opposite ends of the screen, which is the exception ``theWayOut``'s own documentation
    /// already claimed and legacy already performs — `HidableView.hide()`'s animator puts the original back to `alpha 1` and the snapshot to `alpha 0` inside one
    /// 0.2s block.
    var asTheMessagesSeeIt: TheMessageBeingLifted {
        guard let beside = whatTheOverlayHasTaken, theWayItIsLeaving != .fadingWhereItSits else { return .none }
        return .init(beingPressed: nil, takenByTheOverlay: beside.cellIdentifier)
    }


    /// Whether anything at all is down, which is what refuses a lift and what Esc answers before it answers a search.
    var isUp: Bool {
        self != .none
    }


    /// Whether the copy is on its way out, which is **not** the same question as whether it is down.
    ///
    /// It exists because ``TheMessageHeldBesideTheCompositionBar`` has two resting places rather than one and `down` cannot tell them apart: with Step 64 the
    /// journey may *begin* somewhere other than the message's row — wherever the context menu had carried its copy to — while it must always *end* back at that
    /// row. One flag says which of the two a `down` of false means.
    var isLeaving: Bool {
        theWayItIsLeaving != nil
    }


    /// How the copy is going, or nil while it is not going at all — what the overlay needs in order to know whether to move it or to fade it.
    var theWayItIsLeaving: TheWayItLeaves? {
        switch self {
        case .leaving(_, let theWayItLeaves): return theWayItLeaves
        case .none, .beside: return nil
        }
    }

}


// MARK: - How it moves


extension TheMessageBesideTheCompositionBar {

    /// How far above the composition bar the message comes to rest. Legacy's own constant, and the one number transcribed from it.
    static let howFarAboveTheBar: CGFloat = 10

    /// The journey down, and the blur coming up with it.
    ///
    /// Legacy animates the travel over 0.25s on `curveEaseInOut` and fades its blur in over 0.2s with an animator of its own. One animation here rather than
    /// two: there is nothing to see in the difference, and two animations over one interaction is two things to keep in step.
    ///
    /// **A spring rather than legacy's ease.** Its tempo is deliberately close to legacy's quarter second rather than slow — Step 59 exists because
    /// things on this screen can feel slow, so a longer journey would answer one complaint by making another worse. What the spring buys is the settle at the
    /// end and, more usefully, **velocity preserved through a retarget**: the destination re-resolves mid-flight — measured, `goesTo` going 579.7 → 509.7
    /// eighteen milliseconds in — and an ease would restart from the current value where a spring carries its speed through.
    ///
    /// **The damping is chosen by the ten points.** The message rests ``howFarAboveTheBar`` above the bar, an overshoot spends that gap, and an overshoot is
    /// a *fraction of the distance travelled*, `exp(-πζ/√(1-ζ²))` — which makes the safe damping a question about how far a message can fall on the largest
    /// screen this ships on rather than a matter of taste:
    ///
    /// | `dampingFraction` | overshoot | a 600pt drop, iPhone | a 1000pt drop, iPad |
    /// |---|---|---|---|
    /// | 0.88 | 0.30% | 1.8pt | 3.0pt |
    /// | **0.85** | 0.63% | 3.8pt | 6.3pt |
    /// | 0.80 | 1.5% | 9.1pt | 15pt |
    /// | 0.75 — ``TheContextMenuOfAMessage/theLift``'s | 2.8% | 17pt | 28pt |
    ///
    /// **0.85 is the boldest that clears the gap on both.** Past it the message dips into the bar's region, which is not the tidy occlusion it sounds like:
    /// the bar is given no background, so anything there shows in the gaps around the rounded container and behind the buttons beside it.
    ///
    /// **The bound is not a constant.** It was first written as *a point and a half on the longest drop this screen affords* — true of the iPhone it was
    /// measured on and wrong by nearly two on an iPad. **A quantity that scales with the screen cannot be justified against one screen.**
    static let theJourneyDown: Animation = .spring(response: 0.32, dampingFraction: 0.85)

    /// The same, for a reader who has asked for less movement.
    static let theJourneyDownWithReducedMotion: Animation = .easeOut(duration: 0.2)

    /// Going away: the blur, the copy and the real message all in one, which is exactly what legacy's `HidableView.hide()` does — its `executeOnAnimation` puts
    /// the original back to `alpha 1` and the snapshot to `alpha 0` inside the same 0.2s animator that fades the blur out.
    ///
    /// **And that is a deliberate exception to Step 21b's rule against a crossfade.** That rule exists because a copy fading out *over* the message it came from
    /// is seen as a double image. Here the two are at opposite ends of the screen — the copy at the bar, the message up in the transcript — so what the reader
    /// sees is one thing leaving and another arriving, which is what legacy shows and what the recording of it shows working.
    static let theWayOut: Animation = .easeInOut(duration: 0.2)

    static let theWayOutWithReducedMotion: Animation = .easeOut(duration: 0.15)

    /// How far the message leans toward the middle of the screen at the midpoint of its journey, so that it travels on an arc rather than straight down.
    ///
    /// **Toward the middle, and never away from it.** Leaning outward would have been the more obvious reading of legacy — which re-pins its snapshot to leading
    /// `+10` or trailing `−10` — but a bubble already sitting against its own margin has nowhere to go outward, and a lean that carries it off the edge of the
    /// window is clipped by the window rather than by anything this screen controls. Leaning inward can never do that whichever side the message hangs from.
    ///
    /// **Which side that is comes from the message** — `.sentMessage` hangs trailing and `.receivedMessage` leading, resolved against the layout direction — and
    /// *not* from comparing the anchor's own centre with the view's, which is what this said until the Catalyst walk of 2026-08-27 found the anchor to be a
    /// full-width container rather than a bubble. See ``TheMessageHeldBesideTheCompositionBar/theMessageHangsFromTheLeftOfTheView``, which carries the
    /// measurement and the two faults it caused.
    static let theWidestLean: CGFloat = 18

    /// …and never more than this much of the distance actually travelled, so that a message which barely moves barely leans.
    ///
    /// Without it the lean is a constant, and a constant is wrong at both ends of the range this screen affords: a message at the top of a long discussion falls
    /// most of the screen, where eighteen points is a whisper, and the *last* message of a discussion at its end may fall almost nothing at all, where the same
    /// eighteen points is a lurch sideways for no distance downward.
    static let howMuchOfTheDropTheLeanMayBe: CGFloat = 0.05

    /// How much the message swells as it passes the middle of its journey — the whole of the morphing, and it is deliberately almost nothing.
    ///
    /// Rather less than the 1.04 the context menu's lift grows by, that being a message *picked up and held* where this is one *carried past*. And it is a
    /// transient: the swell is zero at both ends of the journey by construction, so the copy is at exactly its rendered size wherever it comes to rest. That
    /// matters beyond tidiness — a defect found on a Mac on 2026-08-26 was the lifted copy coming back *larger* than the message it came from, and an ornament
    /// that provably ends at 1.0 cannot be the author of that. It also keeps legacy's finding that there is no scale anywhere in
    /// `addMessageViewForReplyIfNeeded(from:)` true of every resting state, and false only in between.
    static let howMuchItSwellsInFlight: CGFloat = 0.03


    /// How long the way out takes, for the iOS 16 branch that has no animation completion to wait on. Longer than ``theWayOut``, erring in the safe direction.
    static let howLongTheWayOutTakes: TimeInterval = 0.3

}


// MARK: - What the context menu hands over


/// The lifted copy of a message, as the context menu is drawing it at the instant the reader chooses *Reply*.
///
/// **Expressed against the message's own anchor, and never in either overlay's coordinates.** The two treatments resolve the *same* anchor, but they do not sit in
/// the same space: the context menu's modifier is applied **after** the composition bar is inserted into the safe area and Step 60's **before** it, so their
/// `GeometryReader`s report different sizes and different origins. Measured on Catalyst, Step 60's content area was 754pt tall inside a 919pt view. An absolute
/// frame handed from one to the other would be wrong by whatever that difference happens to be, and wrong differently on every platform.
///
/// So what travels is a **displacement from the anchor** — how far the menu had carried the copy from where the message actually is — which each side reads in its
/// own space, the anchor being the one thing both of them agree on. That is the rule about expressing a quantity as a difference rather than as a sum of named
/// parts, met in a new place: this one does not need to know what either coordinate space is made of.
struct TheCopyTheMenuHandsOver: Equatable {

    /// How far above the message's own place the copy currently sits — the menu's `whereTheMessage.y` less the anchor's `minY`, so negative when the copy has
    /// risen, which it usually has.
    let carriedBy: CGFloat

    /// The scale the menu is drawing it at: `1.04` for a message that fits, less than one for a message it had to shrink into the band. **Relaxed back to 1 over
    /// the journey down**, so the message settles to its natural size as it descends rather than snapping to it.
    let scale: CGFloat

}
