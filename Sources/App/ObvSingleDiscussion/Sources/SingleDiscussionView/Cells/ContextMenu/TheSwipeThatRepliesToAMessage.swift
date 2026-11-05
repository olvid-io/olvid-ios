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
import ObvSystemIcon
import OSLog


/// **Pulling a message aside replies to it**, on every platform.
///
/// The fast way to reply, and the way most replies are made in a messenger. Legacy has had it since the beginning, on both `SentMessageCell` and
/// `ReceivedMessageCell`; nothing in the plan mentioned it until somebody asked what was missing.
///
/// ## A `UIPanGestureRecognizer`, not a `DragGesture`, and the reason is the scroll
///
/// This is the one gesture on this screen that **overlaps the scroll directly**. The press, the double tap and the taps inside a bubble all take a touch
/// the list was never going to use; a drag is the list's own. Legacy settles it in two lines of `UIGestureRecognizerDelegate`:
/// `gestureRecognizerShouldBegin` demands that the horizontal velocity beat the vertical, and `shouldRecognizeSimultaneouslyWith` returns `false` so the
/// two never run together. A `DragGesture` can say neither — it has `minimumDistance` and nothing else.
///
/// **Where arbitration matters, this codebase reaches for UIKit**, through `swiftui-introspect` at `.listCell`, as ``TheSecondaryClickOnAMessage`` and
/// ``TheAttachmentsOfAMessageDraggedOut`` do. The precedents all point one way: a `List` claimed every drop before any SwiftUI drop API saw it (26a), a
/// `UIDragInteraction` took the press over one arbitration property (41), and a SwiftUI press cannot win a race it is not in (54).
///
/// ## Parity, and what is ours
///
/// Measured off `SentMessageCell.userDidPan(_:)` and its twin: the threshold is `MessageCellConstants.panLimitForReplyingToMessage`, **80pt**; the haptic
/// fires **as the threshold is crossed**, in either direction, which is what makes a threshold feel like one; the message follows the finger one-for-one
/// with no cap; the spring back is 0.5s at damping 0.5; and each kind moves one way only — **received** is pulled **right**, **sent** is pulled **left**,
/// each away from the edge it hangs from.
///
/// Ours is what is revealed underneath: the reply glyph drawn in the space the message vacates, growing and fading with the pull. It is in a `.background`
/// rather than a `ZStack`, a `Shape` in a stack sizing the stack around it; and it is attached to **`theColumn`** rather than to `MessageItself`, which
/// carries a greedy row-wide frame.
///
/// ## Three things it must not do
///
/// **It stands down while the reader is choosing messages** (42b). Being UIKit's and on the row's own cell, the single `allowsHitTesting` at the top of the
/// content tree does not reach it — but it has an `isEnabled`, so the refusal is made on the recogniser itself.
///
/// **It asks whether this message may be replied to at all**, when the gesture would begin, from the same `WhatAMessageOffers` the menu's Reply entry uses,
/// so the gesture and the menu cannot disagree.
///
/// **On Mac Catalyst it refuses a drag that starts on the body**, that drag belonging to Step 54's text selection. Walked before it was written: the swipe
/// was already losing that race, and the rule makes it a decision rather than a losing the race. See
/// ``WhatASwipeToReplyAsksFor/itStartedOnTextThatCanBeSelected(_:)``.
struct TheSwipeThatRepliesToAMessage: ViewModifier {

    /// **Optional**, for the reason ``AMessageThatCanBeLifted`` gives: something drawn like a message but which is not one carries this and is simply never
    /// pulled aside.
    let cellIdentifier: SingleDiscussionView.CellIdentifier?

    /// Which edge this message hangs from, which decides both the way it may be pulled and where the glyph appears.
    let side: TheSideAMessageHangsFrom

    /// Asked, at the moment the gesture would begin, whether this message may be replied to.
    let dataSource: (any SingleDiscussionCellViewDataSource)?

    /// Told what the swipe asked for, once it has been let go past the threshold. Straight to the actions, as the double tap goes: a completed swipe is
    /// already a decision, where a press is not yet one.
    let actions: any SingleDiscussionCellViewActions

    /// What this message is, carried so that a completed swipe can hand it to the screen, which draws a copy of it beside the composition bar and has
    /// to draw it from something. **Not read back from a cache**, for the two reasons ``PressOnAMessage/heldLongEnough(_:showing:)`` gives.
    let model: SingleDiscussionCellView.Model

    /// Whether the reader is choosing messages, in which case this stands down.
    @Environment(\.theReaderIsChoosingMessages) private var theReaderIsChoosingMessages

    /// How a completed swipe reaches the screen. The reply itself still goes straight to the actions, as it always has; this is the *other* half of
    /// what a reply does here, which only the screen can draw. See ``PressOnAMessage/askedToReplyTo(_:showing:pulledAcrossBy:)``.
    @Environment(\.pressesOnMessages) private var pressesOnMessages

    /// An object rather than plain state: it is written from a UIKit callback, outside any SwiftUI update.
    @StateObject private var theSwipe = WhatASwipeToReplyAsksFor()

    func body(content: Content) -> some View {
        content
            // **After whatever scales the message and before nothing.** A `scaleEffect(anchor:)` written *after* an `offset` resolves its anchor
            // against the un-offset position, so the two are not interchangeable. The press's shrink is applied further out, in ``AMessageThatCanBeLifted``,
            // which is the correct side of this.
            .offset(x: theSwipe.howFarTheMessageHasBeenPulled)
            // Behind the message and **not** inside the offset above, so that it stays where it is while the message travels over it. An `offset` moves what is
            // drawn and leaves the layout frame alone, which is exactly what makes this work: the background is laid out in the frame the message would have had.
            .background(alignment: side.whereTheGlyphIsRevealed) {
                theGlyphThePullReveals
            }
            // The same attachment point as the drag out of the discussion and the secondary click, and the same note about the version list applies: it follows
            // the versions the *screen* runs on rather than the ones this needs, so a version missing from it costs no error and simply never attaches anything.
            .introspect(.listCell, on: .iOS(.v18, .v26, .v27)) { cell in
                theSwipe.nowShowing(cellIdentifier: cellIdentifier, side: side, asking: dataSource, telling: actions, showing: model, reporting: pressesOnMessages)
                theSwipe.installsItself(on: cell)
            }
            // **A `task(id:)` rather than the introspection above**, for the reason ``TheAttachmentsOfAMessageDraggedOut`` gives: that closure runs when SwiftUI
            // updates the representable, and whether an environment change alone brings it round again is not something to find out from a bug report.
            .task(id: theReaderIsChoosingMessages) {
                theSwipe.mayBePulledAside(!theReaderIsChoosingMessages)
            }
    }


    /// What appears in the space the message leaves behind: the menu's own Reply glyph, growing with the pull.
    ///
    /// **Drawn from the same icon the menu's entry uses**, `arrowshapeTurnUpLeft2`, so the two ways of replying look like one feature. It fades and grows
    /// together rather than only fading, which is what makes a half-hearted pull read as *not yet* rather than as *nearly*.
    private var theGlyphThePullReveals: some View {
        Image(systemIcon: .arrowshapeTurnUpLeft2)
            .font(.system(size: Self.howBigTheGlyphIs))
            .foregroundStyle(theSwipe.theThresholdIsPassed ? Color.accentColor : Color.secondary)
            .scaleEffect(Self.smallestTheGlyphGets + (1 - Self.smallestTheGlyphGets) * theSwipe.howFarAlongThePullIs)
            .opacity(theSwipe.howFarAlongThePullIs)
            .padding(.horizontal, Self.howFarTheGlyphSitsFromTheEdge)
            .animation(.easeOut(duration: 0.12), value: theSwipe.theThresholdIsPassed)
            // A glyph is not a control: it is drawn in the space the message has left, and a touch there belongs to the row.
            .allowsHitTesting(false)
    }


    /// The metric a fixed-size glyph is given, rather than a text style, a fixed-size container needing fixed-size type. Nothing is withheld by not scaling it:
    /// it repeats what the gesture itself is already saying, and the reply it leads to is reachable from the menu at any Dynamic Type size.
    private static let howBigTheGlyphIs: CGFloat = 22

    /// How small the glyph starts, so that it grows into place rather than simply appearing.
    private static let smallestTheGlyphGets: CGFloat = 0.6

    private static let howFarTheGlyphSitsFromTheEdge: CGFloat = 12

}


/// **The pan this feature installs, as a type of its own** — so that one can be told from any other pan on a cell and taken off.
///
/// It exists because of a defect measured on 2026-08-26, and the measurement is the whole argument for it. ``WhatASwipeToReplyAsksFor`` is a `@StateObject`,
/// so it belongs to the SwiftUI row rather than to the cell; when a cell is recycled by another row it is handed a **fresh** object, which dutifully removes
/// its own previous recogniser — of which it has none — and adds a second beside the one already there. Across 182 installs in one walk: **153 cells carried
/// one pan, 21 carried two, 6 carried three and 2 carried four**, and `replacedItsOwn=true` appeared **not once**, the removal path never having run.
///
/// Two ways that is wrong, depending on whether SwiftUI has released the orphan's owner, and it is worth knowing both because they look nothing alike:
///
/// - **Owner gone.** A recogniser holds its delegate and its target weakly, so the orphan has neither. A nil delegate means `gestureRecognizerShouldBegin`
///   reverts to its default of **`true`** — it begins on any direction, vertical included — and `shouldRecognizeSimultaneouslyWith` to `false`, so it is
///   exclusive. It does nothing and can stop something else doing anything.
/// - **Owner alive**, SwiftUI holding the row a while longer: a live delegate still pointing at the message that cell *used* to show, so a swipe replies to
///   the **wrong message**. That is precisely the fault Step 55 found for its `UIContextMenuInteraction`, by reading a log rather than the code.
///
/// It probably also explains the intermittency the same walk saw before this was found: an ask answering `true` with no `began` ever following it.
final class APanThatRepliesToAMessage: UIPanGestureRecognizer {}


/// What a swipe on one message asks for — see ``TheSwipeThatRepliesToAMessage``.
///
/// The shape of ``WhatASecondaryClickAsksFor`` beside it, and for the same reasons: a cell is reused, so what it shows *now* is pointed at rather than captured,
/// and the recogniser is installed once per cell rather than once per update.
/// **`ObservableObject` and not `@Observable`, deliberately**, which is the same call
/// ``TheGeometryOfTheTranscriptReadPerFrame`` records and for the same reason: `@Observable` is iOS 17 and this module's floor is **16**, and
/// adding a second reason iOS 16 cannot have this screen would decide 46f's question by an implementation detail rather than on its merits. The
/// coarser, per-object notification costs nothing here — the one view that reads this reads both of its published values on every frame of a pull
/// anyway.
@MainActor
final class WhatASwipeToReplyAsksFor: NSObject, ObservableObject {

    /// How far the message is currently drawn from where it belongs — **signed**, so that the view can apply it without knowing which way this message moves.
    @Published private(set) var howFarTheMessageHasBeenPulled: CGFloat = 0

    /// How far along the pull is, from nothing to the threshold, clamped at 1 — legacy's `panFractionCompleted`.
    var howFarAlongThePullIs: CGFloat {
        min(1, abs(howFarTheMessageHasBeenPulled) / Self.howFarAMessageIsPulledToReply)
    }

    /// Whether the pull has passed the point at which letting go replies.
    ///
    /// **The haptic lives in this setter and fires as the threshold is *crossed*, in either direction, and never on release** — legacy's `panLimitReached`
    /// `didSet`, guarded on `pan.state != .ended`, and it is what makes the threshold feel like a threshold rather than like a distance. It would be easy to
    /// lose in a rewrite and hard to name afterwards, which is why it is written down in the step.
    @Published private(set) var theThresholdIsPassed = false {
        didSet {
            guard oldValue != theThresholdIsPassed else { return }
            // **Only while the message is actually being moved.** Legacy writes this as `pan.state != .ended`, which lets a *cancelled* gesture knock as it
            // resets — the state is `.cancelled` there, not `.ended`, so the guard passes. Asking for `.changed` instead says what is meant: a threshold makes
            // itself felt when it is crossed under the finger, and at no other time.
            guard pan?.state == .changed else { return }
            feedback.impactOccurred()
            feedback.prepare()
        }
    }

    private var cellIdentifier: SingleDiscussionView.CellIdentifier?
    private var side: TheSideAMessageHangsFrom = .centre
    private weak var dataSource: (any SingleDiscussionCellViewDataSource)?
    private var actions: (any SingleDiscussionCellViewActions)?

    /// What the message is, for Step 60's copy — optional here where it is not on the modifier, this object being made before it is told anything.
    private var model: SingleDiscussionCellView.Model?

    /// Where a completed swipe is reported, so the screen can bring the message down beside the composition bar.
    private var pressesOnMessages: PressesOnMessages?

    /// Kept so that a reused cell is not given a second recogniser, and so that the one this object put on a cell can be taken off when the cell moves on.
    private weak var pan: UIPanGestureRecognizer?

    /// Whether a swipe here may do anything at all — false while the reader is choosing messages, Step 42b.
    ///
    /// Remembered as well as applied, because a cell is reused: the next cell has to be told the same thing, and the only place that knows it at that moment
    /// is here.
    private var mayBePulled = true

    private let feedback = UIImpactFeedbackGenerator()


    /// Points this object at the message the cell shows *now*, cells being reused as the reader scrolls.
    func nowShowing(cellIdentifier: SingleDiscussionView.CellIdentifier?,
                    side: TheSideAMessageHangsFrom,
                    asking dataSource: (any SingleDiscussionCellViewDataSource)?,
                    telling actions: any SingleDiscussionCellViewActions,
                    showing model: SingleDiscussionCellView.Model,
                    reporting pressesOnMessages: PressesOnMessages?) {
        self.cellIdentifier = cellIdentifier
        self.side = side
        self.dataSource = dataSource
        self.actions = actions
        self.model = model
        self.pressesOnMessages = pressesOnMessages
    }


    /// Puts the recogniser on the row's own cell, and re-points it as cells are reused.
    func installsItself(on view: UIView) {
        guard pan?.view !== view else { return }
        // **Two removals, and they cover different cells.** This one follows *this object* to whatever cell it was on before — which the sweep below cannot
        // reach, that looking only at the cell being moved to. It is Step 55's fix for the secondary click, transcribed, and on its own it is not enough:
        // `replacedItsOwn=true` was measured **not once** in 182 installs, this object always being freshly made.
        let itHadOneAlready = pan != nil
        if let pan { pan.view?.removeGestureRecognizer(pan) }
        // **And this one takes off every pan this feature ever put on the cell being moved *to*, not merely the one this object put there.** A `@StateObject`
        // belongs to the SwiftUI row rather than to the cell, so a recycled cell is handed a fresh object and the orphans pile up — measured at **four** on
        // one cell. ``APanThatRepliesToAMessage`` exists so ours can be told from anything else on the cell, the `List`'s own recognisers included, which
        // must not be touched.
        let leftBehind = (view.gestureRecognizers ?? []).compactMap { $0 as? APanThatRepliesToAMessage }
        leftBehind.forEach { view.removeGestureRecognizer($0) }
        let pan = APanThatRepliesToAMessage(target: self, action: #selector(theReaderPulledTheMessage(_:)))
        pan.delegate = self
        pan.isEnabled = mayBePulled
        view.addGestureRecognizer(pan)
        self.pan = pan
        // **Neither of these is written unless it would actually change, and the reason is a warning that was real**: *Publishing changes from within view
        // updates is not allowed, this will cause undefined behavior.* This method is called from the `.introspect(.listCell)` closure, which runs **inside
        // SwiftUI's update pass**, and a `@Published` fires `objectWillChange` on `willSet` **whatever the value** — so writing 0 over 0 was enough to cause
        // it, twice per install, on every row the reader scrolled past.
        //
        // **And the case it was written for does not exist.** The comment here used to say *the cell is reused, so whatever the previous row had been pulled to
        // is not this row's business* — but this object is a `@StateObject`, so it belongs to the **row** and not to the cell, and a recycled cell is handed a
        // *fresh* one. Measured over 224 installs on two platforms: `replacedItsOwn` was true **not once**. A fresh object already holds 0 and false, so this
        // reset only ever published. Where the object does follow its row to another cell, the pull it is carrying **is** that row's business, and the pan being
        // taken off its old cell cancels it and springs it back through the ordinary path.
        //
        // So it is kept as a guard rather than a reset, and deferred out of the update pass for the case that never arises but would be undefined if it did.
        if howFarTheMessageHasBeenPulled != 0 || theThresholdIsPassed {
            Task { @MainActor [weak self] in
                self?.howFarTheMessageHasBeenPulled = 0
                self?.theThresholdIsPassed = false
            }
        }
        // **DEBUG INSTRUMENT.** Says that the recogniser is *there*, which is the half of a silence that reading cannot supply: a
        // gesture that does nothing is equally explained by never being installed and by never being offered the event, which is what cost Step 55 its
        // first mechanism. The two counts are the second question in the same line, and they are what found the accumulation above: `oursOnThisCell` must
        // now always read 1, and `sweptUpOrphans` says the sweep **ran** rather than merely leaving that number alone — a fix whose only evidence is a
        // number that did not change is indistinguishable from a fix that never executes.
        //
        // **`stillLive` is the one that decides how bad the defect was**, and it was added because the two harms were *reasoned* where the accumulation
        // itself was measured. A recogniser holds its delegate weakly, so an orphan whose owner SwiftUI has released reports `nil` — inert, but exclusive,
        // and able to stop something else. One whose owner is still held reports a **live delegate pointing at the message that cell used to show**, which
        // is the wrong-message reply and is a correctness bug rather than a blocked gesture. `stillLive > 0` says which.
        Self.saysWhatItDid("installed", "side=\(side) enabled=\(mayBePulled) replacedItsOwn=\(itHadOneAlready) sweptUpOrphans=\(leftBehind.count) stillLive=\(leftBehind.count { $0.delegate != nil }) oursOnThisCell=\(Self.howManyPansAreOn(view)) cell=\(Self.whichCell(view))")
    }


    /// Says whether this message may be pulled aside — false while the reader is choosing messages, Step 42b.
    func mayBePulledAside(_ mayBePulled: Bool) {
        let itChanged = self.mayBePulled != mayBePulled
        self.mayBePulled = mayBePulled
        pan?.isEnabled = mayBePulled
        // **DEBUG INSTRUMENT, and it was missing.** The select-mode refusal is made on `isEnabled`, and a *disabled* recogniser is never offered an
        // event and never asked whether to begin — so it leaves no trace anywhere, and `mayBePulled=false` can never appear on an ask however long one walks.
        // Step 42b's item was reported as passing on the strength of nothing moving, which is also what a message that was never asked looks like. This is the
        // precondition, reported where it is actually decided.
        Self.saysWhatItDid("may be pulled aside", "mayBePulled=\(mayBePulled) changed=\(itChanged) hasARecogniser=\(pan != nil)")
    }


    @objc private func theReaderPulledTheMessage(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            feedback.prepare()
            // **DEBUG INSTRUMENT.** The gesture actually started, which on Mac Catalyst is the whole question: `shouldBegin` answering `yes` is a
            // permission and this is the event. `under=` is where the reader's finger or pointer was when it did, the text view of Step 54 covering the body
            // alone, so a message may well answer differently along its own height.
            howManyChangesSoFar = 0
            farthestItWasPulled = 0
            Self.saysWhatItDid("began", "side=\(side) startedOn=\(Self.whereItStarted(pan)) nowOver=\(Self.whatIsUnder(pan)) selectionInTheText=\(Self.howMuchTextIsSelectedUnder(pan))")
        case .changed:
            // One for one with the finger and **not clamped**, which is legacy: `min`/`max` against the starting edge stop it moving the wrong way and nothing
            // stops it going far. What is clamped is the reveal, at the threshold.
            let pulled = pan.translation(in: pan.view).x
            howFarTheMessageHasBeenPulled = side.howFarThatPullsIt(pulled)
            let wasPassed = theThresholdIsPassed
            theThresholdIsPassed = abs(howFarTheMessageHasBeenPulled) > Self.howFarAMessageIsPulledToReply
            // **DEBUG INSTRUMENT.** The first movement, and every crossing of the threshold — not every frame. The first says the message moved at
            // all where `began` says only that the gesture did; the crossings are where the knock is meant to be felt, and *that* is the parity detail this
            // step said in advance would be easy to lose and hard to name afterwards.
            howManyChangesSoFar += 1
            farthestItWasPulled = max(farthestItWasPulled, abs(howFarTheMessageHasBeenPulled))
            if howManyChangesSoFar == 1 {
                Self.saysWhatItDid("moved", "side=\(side) pulled=\(Self.rounded(howFarTheMessageHasBeenPulled))")
            }
            if wasPassed != theThresholdIsPassed {
                Self.saysWhatItDid("crossed the threshold", "passed=\(theThresholdIsPassed) pulled=\(Self.rounded(howFarTheMessageHasBeenPulled)) knocked=\(pan.state == .changed)")
            }
        case .ended, .cancelled, .failed:
            // **The three states come back the same way and only one of them replies.** Letting go is a decision the reader made; being cancelled is one made
            // *for* them — an incoming call, a system alert, a drag from the bottom edge, or ``installsItself(on:)`` taking the recogniser off a cell as it is
            // reused mid-pull. A message left past the threshold at that moment is not a message they chose to answer, and quoting it puts words in a draft they
            // never asked for and may not notice. Legacy guards the same way, `if pan.state == .ended, panLimitReached` in `SentMessageCell`.
            let theReaderLetGoOfIt = pan.state == .ended
            let itWasPulledFarEnough = theThresholdIsPassed
            theThresholdIsPassed = false
            let itReplies = itWasPulledFarEnough && theReaderLetGoOfIt

            // Read before the spring takes it away, and carried to the screen so that the copy can be placed over the message where it is actually drawn. The
            // spring runs for all three states, a message having to come home whether the reader let go or the system took the gesture away.
            let pulledAcrossBy = howFarTheMessageHasBeenPulled
            withAnimation(.spring(duration: Self.howLongTheMessageTakesToComeBack, bounce: Self.howMuchItBouncesComingBack)) {
                howFarTheMessageHasBeenPulled = 0
            }
            if itReplies {
                asksToReplyToThisMessage(pulledAcrossBy: pulledAcrossBy)
            }

            // **DEBUG INSTRUMENT.** What the whole pull came to, and — the point of the line — whether a reply was asked for. `selectionInTheText`
            // beside it is what separates Step 40's two Mac outcomes: a swipe that ran *and* left a selection behind is *both happened*, which is what a
            // double-click did before Step 56's edit was withdrawn here.
            Self.saysWhatItDid("let go", "side=\(side) state=\(Self.named(pan.state)) changes=\(howManyChangesSoFar) farthest=\(Self.rounded(farthestItWasPulled)) pulledFarEnough=\(itWasPulledFarEnough) REPLIED=\(itReplies) selectionInTheText=\(Self.howMuchTextIsSelectedUnder(pan))")
        default:
            break
        }
    }


    /// Asks for the same `.reply` the menu's own entry asks for, so there is one reply path and not two, and tells the screen to bring the message down beside
    /// the composition bar.
    ///
    /// **Both in the one breath.** The reply reaching the draft and the copy leaving its row are the two halves of what a reply does here, and anything that
    /// separates them leaves a window in which the bar quotes a message the screen is not holding — where the ✕ finds nothing to put back.
    ///
    /// The copy is reported rather than drawn here for the reason ``PressesOnMessages`` exists: what draws it is the screen, and this is a recogniser several
    /// levels down inside a cell. It carries `pulledAcrossBy` so the copy can be placed over the message as the reader last saw it, the row itself being
    /// eighty-odd points away until the spring above has run.
    private func asksToReplyToThisMessage(pulledAcrossBy: CGFloat) {
        guard let cellIdentifier, let actions else { return }
        Task { await actions.userWantsToActOnMessage(cellIdentifier: cellIdentifier, action: .reply) }
        guard let model else { return }
        pressesOnMessages?.report(.askedToReplyTo(cellIdentifier, showing: model, pulledAcrossBy: pulledAcrossBy))
    }


    /// Whether this message offers a reply at all, asked of the same `WhatAMessageOffers` the menu's entry rests on.
    ///
    /// Read at the moment the gesture would begin rather than held on the cell, which is 21a's rule for the whole of this: what a message offers is computed on
    /// the main thread against the view context, and doing it for every message on screen is precisely what that step exists to avoid.
    private var thisMessageOffersAReply: Bool {
        guard let cellIdentifier, let dataSource else { return false }
        return dataSource.whatTheMessageOffers(cellIdentifier: cellIdentifier).offersToReply
    }


    /// **On Mac Catalyst, a drag that starts on text the reader may select belongs to the text.**
    ///
    /// Step 40 was asked for on every platform with one clause attached: **where it fights text selection, the swipe gives way**. That is the answer Step 54
    /// gave about the press and the double tap, applied to the third gesture rather than argued again.
    ///
    /// **It was already giving way, which is precisely why this exists.** Walked on a Mac Studio: the swipe **cannot complete** on the body — across sixteen
    /// mouse-downs it was asked three times, began **once**, and reached **18.3pt** against a threshold of 80, the text interaction taking the drag outright.
    /// So nothing shipped had to be withdrawn. But it was giving way **because it kept losing, not because we decided it**, and three things follow:
    ///
    /// - that one begin **moved the message 18.3pt while twelve characters were selected**, which reads as jitter under a selection drag, and only the
    ///   threshold kept it from being worse — a threshold is not a guard;
    /// - which recogniser wins **varied between runs**, and the cure for that is to remove the case rather than react faster;
    /// - a race that happens to be lost today is not a property anyone can rely on tomorrow.
    ///
    /// **It refuses on where the drag began**, not on where the pointer is now — the two differ by ~7pt in 12ms by the time a pan asks. It asks for
    /// `isSelectable`, so only Step 54's body claims a drag. Everything else on a message is unaffected: the bubble's padding, an image, the date row and the
    /// reactions chip all swipe cleanly, measured at 310.2, 174.2 and 89.5pt.
    ///
    /// **A message carrying attachments needs nothing here.** A drag anywhere on such a cell lifts its files — Step 41's `UIDragInteraction` — and the pan is
    /// never asked at all, measured over the body with no decision whatever.
    ///
    /// **iOS and iPadOS are untouched**, this being behind the same `targetEnvironment(macCatalyst)` as Steps 54 and 55, and there being no selectable text
    /// view on those platforms for it to find.
    nonisolated static func itStartedOnTextThatCanBeSelected(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        #if targetEnvironment(macCatalyst)
        return MainActor.assumeIsolated {
            guard let cell = gestureRecognizer.view else { return false }
            let now = gestureRecognizer.location(in: cell)
            let travelled = (gestureRecognizer as? UIPanGestureRecognizer)?.translation(in: cell) ?? .zero
            let began = CGPoint(x: now.x - travelled.x, y: now.y - travelled.y)
            guard let hit = cell.hitTest(began, with: nil) else { return false }
            var view: UIView? = hit
            while let current = view {
                if let text = current as? UITextView, text.isSelectable { return true }
                view = current.superview
            }
            return false
        }
        #else
        return false
        #endif
    }


    /// Legacy's `MessageCellConstants.panLimitForReplyingToMessage`.
    private static let howFarAMessageIsPulledToReply: CGFloat = 80

    /// How long the message takes to come home. Shorter than legacy on purpose, and the one thing on this gesture that is not parity: legacy springs back over
    /// `UIView.animate(withDuration: 0.5, usingSpringWithDamping: 0.5)` (`SentMessageCell.swift:1069`, `ReceivedMessageCell.swift:1146`). Half a second is long
    /// to hold a reader who has already been told, by the knock at the threshold, that the reply is theirs.
    private static let howLongTheMessageTakesToComeBack: TimeInterval = 0.33

    /// How much it overshoots coming home, in the vocabulary `Animation.spring(duration:bounce:)` uses, where `bounce = 1 - dampingFraction`. Legacy's damping
    /// of 0.5 is a bounce of 0.5; this is a damping fraction of 0.67, which comes home more firmly — the same departure as the duration above.
    ///
    /// Less bounce is more damping, so a damping fraction written here would ask for the opposite of what it says.
    private static let howMuchItBouncesComingBack: CGFloat = 0.33


    // MARK: - Debug instruments for the swipe
    //
    // **Not temporary, and they once said they were** — marked for a walk that had finished weeks before, which is an invitation to delete the only
    // instrumentation a gesture this hard to reason about has. A marker names the condition that ends it or it is not a marker: these have none, so
    // they say what they are instead. Nothing of them survives a release build.

    /// How many `.changed` calls this pull has had, so that *the message moved* can be reported once rather than sixty times a second.
    private var howManyChangesSoFar = 0

    /// The farthest this pull ever got, which is what says whether a pull that did not reply came close to it.
    private var farthestItWasPulled: CGFloat = 0

    /// **DEBUG INSTRUMENT** — a category of its own beside `TranscriptFrames`, `TranscriptAnswers`, `TranscriptRule` and `TranscriptDrop`, and it is
    /// carried by `scripts/attach-transcript-frames-local.sh`'s predicate along with them. Not driven by the display link, so it carries no frame number and
    /// has to be lined up by its timestamp, exactly as the rule's own voice does.
    ///
    /// **Nothing at all outside a debug build, arguments included, and that is what the `@autoclosure` is for.** These lines were unguarded and shipped, which
    /// is a finding of the review of 2026-08-30 — but guarding the *body* alone would have fixed almost nothing: the cost is not the `Logger`, it is what the
    /// call sites build to hand it. One ask assembles two `hitTest` traversals and a dozen interpolations, and `gestureRecognizer(_:shouldReceive:)` is asked
    /// **per touch event**. Deferred, none of that is evaluated in a release build, and every call site keeps its wording and its reasons for a walk that needs
    /// them again.
    ///
    /// The pair of them stay one expression each so the message reads the same as it always did.
    nonisolated static func saysWhatItDid(_ what: @autoclosure () -> String, _ detail: @autoclosure () -> String) {
        #if DEBUG
        // Evaluated into locals first: an `OSLogMessage` interpolation takes its arguments as *escaping* autoclosures, and a non-escaping one may not be
        // captured by one. The two calls happen here either way.
        let whatItDid = what()
        let theDetail = detail()
        Logger(subsystem: "io.olvid.messenger", category: "TranscriptSwipe").info("\(whatItDid, privacy: .public) | \(theDetail, privacy: .public)")
        #endif
    }


    /// What is actually under the touch, deepest first — the answer to *where did the drag start*, which on Mac Catalyst is half of Step 40's question.
    ///
    /// The names are the instrument: ``ATextViewWhoseSelectionCanBeSuppressed`` is Step 54's body and covers the body **alone**, so the bubble's padding, an
    /// image, the date row and the reactions chip all report something else — and the answer may differ across one message's own height.
    nonisolated static func whatIsUnder(_ gestureRecognizer: UIGestureRecognizer) -> String {
        MainActor.assumeIsolated {
            guard let cell = gestureRecognizer.view else { return "noView" }
            guard let hit = cell.hitTest(gestureRecognizer.location(in: cell), with: nil) else { return "nothing" }
            var names: [String] = []
            var view: UIView? = hit
            while let current = view, names.count < 4 {
                names.append(String(describing: type(of: current)))
                view = current.superview
            }
            return names.joined(separator: "<")
        }
    }


    /// Where the drag **started**, which is the question Step 40 actually asks and *not* the one ``whatIsUnder(_:)`` answers.
    ///
    /// **The distinction cost a reading.** `whatIsUnder` hit-tests the pointer's position at the moment of the call, and by the time a pan asks whether to
    /// begin the pointer has already travelled — measured at 21:25:29 on the first walk, where a mouse-down over the body reported the *cell* 12ms later,
    /// having moved ~7pt at 619pt/s. A pan does not expose where it started, so this reconstructs it: `location − translation` is the touch-down point, the
    /// translation being measured from exactly there.
    nonisolated static func whereItStarted(_ gestureRecognizer: UIGestureRecognizer) -> String {
        MainActor.assumeIsolated {
            guard let cell = gestureRecognizer.view else { return "noView" }
            let now = gestureRecognizer.location(in: cell)
            let travelled = (gestureRecognizer as? UIPanGestureRecognizer)?.translation(in: cell) ?? .zero
            let began = CGPoint(x: now.x - travelled.x, y: now.y - travelled.y)
            guard let hit = cell.hitTest(began, with: nil) else { return "nothing" }
            var names: [String] = []
            var view: UIView? = hit
            while let current = view, names.count < 4 {
                names.append(String(describing: type(of: current)))
                view = current.superview
            }
            return names.joined(separator: "<")
        }
    }


    /// How many characters of Step 54's text view are selected, if the touch is over one at all — `noTextView` where it is not.
    ///
    /// **This is what separates Step 40's two Mac outcomes.** *It never begins* leaves no `began` line at all; *both happen* leaves one with a selection
    /// beside it. Reading it at `began` and again at `let go` gives the pair, so a selection that was already there is not mistaken for one the swipe made.
    nonisolated static func howMuchTextIsSelectedUnder(_ gestureRecognizer: UIGestureRecognizer) -> String {
        MainActor.assumeIsolated {
            guard let cell = gestureRecognizer.view else { return "noView" }
            guard let hit = cell.hitTest(gestureRecognizer.location(in: cell), with: nil) else { return "noTextView" }
            var view: UIView? = hit
            while let current = view {
                if let text = current as? UITextView { return "\(text.selectedRange.length)chars" }
                view = current.superview
            }
            return "noTextView"
        }
    }


    /// How many pan recognisers are on this cell — one per object that ever installed on it. This object removes its own and cannot remove another's, so a
    /// number above one on a reused cell is a fault rather than a curiosity, and it is the same fault Step 55 found in the log for the secondary click.
    nonisolated static func howManyPansAreOn(_ view: UIView) -> Int {
        // Reaching a view's recognisers is the main actor's business, and this is `nonisolated` like every other helper here — so the promise is made
        // explicitly, exactly as ``howMuchTextIsSelectedUnder(_:)`` above makes it. It holds: the only thing that asks is `installsItself(on:)`, on a
        // class that is `@MainActor` whole.
        MainActor.assumeIsolated {
            (view.gestureRecognizers ?? []).filter { $0 is APanThatRepliesToAMessage }.count
        }
    }


    nonisolated static func whichCell(_ view: UIView) -> String {
        String(UInt(bitPattern: ObjectIdentifier(view).hashValue) & 0xffff, radix: 16)
    }


    nonisolated static func rounded(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }


    nonisolated static func named(_ state: UIGestureRecognizer.State) -> String {
        switch state {
        case .possible: return "possible"
        case .began: return "began"
        case .changed: return "changed"
        case .ended: return "ended"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        @unknown default: return "unknown"
        }
    }

}


// MARK: - UIGestureRecognizerDelegate

extension WhatASwipeToReplyAsksFor: UIGestureRecognizerDelegate {

    /// **The two lines that let this coexist with the scroll**, both of them legacy's.
    ///
    /// The gesture begins only when the reader is moving more sideways than up or down, and only towards the side this kind of message may go. Everything else
    /// is left to the list, which is why an ordinary scroll that happens to start on a message is unaffected — the recogniser refuses at `began` and never
    /// competes.
    ///
    /// It also refuses a message that offers no reply, so nothing moves that could not act on the movement — and, on Mac Catalyst, a drag that starts on
    /// text the reader may select. See ``itStartedOnTextThatCanBeSelected(_:)``.
    ///
    /// **The tests are ordered by what they cost, cheapest first, and each one refuses on its own.** This is asked on the first frame of **every** drag that
    /// begins on a message, which is every scroll of the discussion — so what it does before it can say no is on the scrolling path.
    ///
    /// It used to bind all five terms up front, so that one log line could carry every one of them. Two of the five are not cheap. `thisMessageOffersAReply`
    /// builds a child `NSManagedObjectContext` **on the main thread**, and `itStartedOnTextThatCanBeSelected(_:)` walks a `hitTest` — and both ran on the first
    /// frame of an ordinary vertical scroll, which two comparisons on a velocity already in hand would have refused. Step 21a exists to keep exactly that
    /// question off the screen's hot paths, and this was asking it there.
    ///
    /// **What was lost is the single line carrying every term, and it is not lost in the way that matters.** The reason it was written that way — that
    /// a guard refusing in silence cannot be told apart from a case that never arose — is served better by each refusal saying which test refused, and it
    /// is one code path in both configurations rather than an eager one under `DEBUG` and a short-circuiting one in release. The terms an early exit never
    /// reaches are the terms it did not need.
    nonisolated func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        MainActor.assumeIsolated {

            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }

            // Free: the mode, which the screen has already decided.
            guard mayBePulled else {
                Self.saysWhatItDid("asked whether to begin", "ANSWER=false side=\(side) refusedOn=mayBePulled")
                return false
            }

            // Two comparisons on a velocity we are holding, and between them they refuse every ordinary scroll.
            let velocity = pan.velocity(in: pan.view)
            let theRightWay = side.isTheWayThisMessageMoves(velocity.x)
            let moreSidewaysThanNot = abs(velocity.x) > abs(velocity.y)
            guard theRightWay, moreSidewaysThanNot else {
                Self.saysWhatItDid("asked whether to begin", "ANSWER=false side=\(side) refusedOn=theVelocity vx=\(Self.rounded(velocity.x)) vy=\(Self.rounded(velocity.y)) theRightWay=\(theRightWay) moreSideways=\(moreSidewaysThanNot)")
                return false
            }

            // A `hitTest`, and nothing at all off Mac Catalyst.
            guard !Self.itStartedOnTextThatCanBeSelected(pan) else {
                Self.saysWhatItDid("asked whether to begin", "ANSWER=false side=\(side) refusedOn=onTheText startedOn=\(Self.whereItStarted(pan))")
                return false
            }

            // **Core Data, and therefore last.** Only a pan that is already sideways, the right way, and not on selectable text ever asks what this message
            // offers — which is a small fraction of the drags this method sees.
            guard thisMessageOffersAReply else {
                Self.saysWhatItDid("asked whether to begin", "ANSWER=false side=\(side) refusedOn=offersAReply")
                return false
            }

            Self.saysWhatItDid("asked whether to begin", "ANSWER=true side=\(side) vx=\(Self.rounded(velocity.x)) vy=\(Self.rounded(velocity.y)) startedOn=\(Self.whereItStarted(pan)) nowOver=\(Self.whatIsUnder(pan))")
            return true
        }
    }


    /// **DEBUG INSTRUMENT, and it answers nothing about behaviour**: it returns what the default returns. It exists because it is asked *before*
    /// ``gestureRecognizerShouldBegin(_:)`` is, so a silence in the two of them together separates the one thing reading cannot — a recogniser that was
    /// **never offered the event** from one that was offered it and refused. That is the whole of Step 40's Mac question: if the text layer answers the
    /// mouse-down itself, neither line appears over the body while both appear over the padding a few points away.
    ///
    /// **Not compiled at all outside a debug build.** An unimplemented `gestureRecognizer(_:shouldReceive:)` means *yes*, which is exactly what this returns,
    /// so leaving it out changes no behaviour — and it is asked **per touch event**, so leaving it in costs a delegate dispatch on the busiest path there is
    /// for the sake of a line nobody can read in a release build.
    #if DEBUG
    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
        MainActor.assumeIsolated {
            // `onTheText` is carried **here** as well as on the ask, and that is the point of this line rather than a decoration: `shouldBegin` is reached
            // only when the pan actually recognises, which on the body it mostly does not — so a walk of the text refusal produces the *right outcome* with
            // the guard never consulted. For any test of a guard, report the guard's decision, and check that the circumstance it needs
            // actually arose. This is the circumstance; the ask is the decision. Counting the two separately is what tells them apart.
            Self.saysWhatItDid("offered an event", "side=\(side) kind=\(event.type.rawValue)/\(String(describing: event.buttonMask)) onTheText=\(Self.itStartedOnTextThatCanBeSelected(gestureRecognizer)) under=\(Self.whatIsUnder(gestureRecognizer))")
        }
        return true
    }
    #endif


    /// **The back swipe wins, and a message received is what collides with it.**
    ///
    /// A received message is pulled **right**, hangs from the leading edge, and this recogniser is on the *whole cell* — so it covers the strip along the
    /// left of the screen where `interactivePopGestureRecognizer` lives, and a rightward drag begun there is both *go back* and *reply to this*. A message
    /// sent is pulled left and meets nothing, there being no gesture on the trailing edge.
    ///
    /// **Requiring failure rather than testing a distance**, and the difference matters: UIKit decides whether the touch was an edge swipe, so no zone width
    /// is hardcoded here and none can drift from the platform's. When the touch did not start at the edge the screen-edge recogniser fails at once and this
    /// one proceeds, so the cost is a moment's wait in the strip and nothing anywhere else.
    ///
    /// **Legacy does not do this**, its pan carrying no failure requirement and its `shouldRequireFailureOf` being about a tap and a double tap. So this is a
    /// departure rather than parity, and it is one because the platform's own gesture must win: a reader who cannot leave a discussion has lost more than a
    /// shortcut to a reply.
    ///
    /// **The class test is reported rather than trusted.** `interactivePopGestureRecognizer` is typed as a plain `UIGestureRecognizer` and its concrete class
    /// is private, so that it answers to `UIScreenEdgePanGestureRecognizer` is an assumption until a log says it does — which is what the line below is for.
    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        let itIsTheEdge = otherGestureRecognizer is UIScreenEdgePanGestureRecognizer
        // **DEBUG INSTRUMENT.** Says what this pan is actually being weighed against, because the fix above rests on a class the SDK does not
        // promise. If the pop gesture never appears here as a `UIScreenEdgePan…`, the test is a no-op and the conflict is unfixed — and a no-op that
        // compiles is indistinguishable from a fix that works, which is this session's most repeated lesson.
        MainActor.assumeIsolated {
            Self.saysWhatItDid("weighed against another recogniser", "requiresItToFail=\(itIsTheEdge) other=\(String(describing: type(of: otherGestureRecognizer))) onView=\(String(describing: type(of: otherGestureRecognizer.view)))")
        }
        return itIsTheEdge
    }


    /// **`false`, which is legacy's answer and the whole of the arbitration.** The comment on legacy's own line says `true` would allow the cell and the
    /// collection view to pan at once; what that looks like is a message sliding sideways while the discussion scrolls under it.
    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

}


extension TheSideAMessageHangsFrom {

    /// Whether a horizontal velocity is the way this kind of message may be pulled: a message **received** hangs from the leading edge and is pulled to the
    /// **right**; one **sent** hangs from the trailing edge and is pulled to the **left**. Each goes away from its own edge, which is legacy's
    /// `gestureRecognizerShouldBegin` in both cells — `velocity.x > 0` there and `velocity.x < 0` here.
    func isTheWayThisMessageMoves(_ horizontalVelocity: CGFloat) -> Bool {
        switch self {
        case .leading: return horizontalVelocity > 0
        case .trailing: return horizontalVelocity < 0
        case .centre: return false
        }
    }


    /// How far a translation actually pulls this message, which is *not* the translation: a pull the wrong way moves nothing at all. Legacy expresses the same
    /// thing as `min(minX, minX + translation.x)` in a sent cell and `max(…)` in a received one.
    func howFarThatPullsIt(_ horizontalTranslation: CGFloat) -> CGFloat {
        switch self {
        case .leading: return max(0, horizontalTranslation)
        case .trailing: return min(0, horizontalTranslation)
        case .centre: return 0
        }
    }


    /// Where the glyph is revealed: in the space the message vacates, which is the edge it hangs from.
    var whereTheGlyphIsRevealed: Alignment {
        switch self {
        case .leading: return .leading
        case .trailing: return .trailing
        case .centre: return .center
        }
    }

}
