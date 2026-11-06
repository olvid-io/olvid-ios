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
// For `Task.sleep(seconds:)`, the house style being to sleep in seconds rather than nanoseconds.
import OlvidUtils


/// What a message does so that it can be lifted out of the discussion: it says where it is, it answers a long press, and it stands aside once the overlay has
/// taken a copy of it.
///
/// **Applied to the message and not to the row.** The row is the one thing that must never move — a whole row rising on an opaque platter is exactly what
/// `.contextMenu` does and exactly why this screen does not use it. What this wraps is the content of one message: its bubbles, the reply header tucked under
/// them, the badges above them. Its sender, its date and its reactions are the *cell's* and stay where they are.
private struct AMessageThatCanBeLifted: ViewModifier {

    /// **Optional**, so that something drawn like a message but which is not one — the sentence a discussion opens with — carries this modifier and is simply never
    /// lifted. A conditional modifier at the call site would have made the view branch, and a view that branches inside a `List` row is what the rules of this
    /// screen are most careful about.
    let cellIdentifier: SingleDiscussionView.CellIdentifier?

    /// What this message is, carried so that the overlay can draw a copy of it — see ``PressOnAMessage/heldLongEnough(_:showing:)``, which says why it travels with
    /// the press rather than being read back from a cache.
    let model: SingleDiscussionCellView.Model

    let side: TheSideAMessageHangsFrom

    /// Asked, at the moment of a double tap, whether this message may be reacted to and what this reader has already put on it.
    ///
    /// **Optional, and nil for a system message**, which has no data source of its own because it needs nothing from one. Nothing is
    /// lost: a system message can never be reacted to, so a double tap on one has nothing to do in any case.
    let dataSource: (any SingleDiscussionCellViewDataSource)?

    /// Told what a double tap asked for. The long press has a stream of its own, the overlay needing to know about a press before it
    /// has become anything; a double tap is already a decision, so it goes straight to the actions.
    let actions: any SingleDiscussionCellViewActions

    @Environment(\.theMessageBeingLifted) private var theMessageBeingLifted
    @Environment(\.pressesOnMessages) private var pressesOnMessages

    /// The small knock a double tap gives, which is the only feedback it has other than the chip appearing under the message a moment
    /// later. Every reaction path on the legacy screen gives one.
    ///
    /// A `UINotificationFeedbackGenerator` rather than `sensoryFeedback(_:trigger:)`, which needs iOS 17 while this module still
    /// supports 16.
    private let feedback = UINotificationFeedbackGenerator()

    /// Counts out an ordinary tap before this message admits to being pressed — see ``theTouchHasLastedLongEnoughToBeAPress()``. Cancelled the moment the finger
    /// leaves, so a tap says nothing at all.
    @State private var theWaitBeforeSayingItIsAPress: Task<Void, Never>?

    /// Whether the finger is on a control drawn inside this message rather than on the message — see ``AFingerOnSomethingInsideAMessage``, and finding 18 of the
    /// 2026-08-30 review, which is the walk that established there are five such controls and that not one of them can lift a message.
    ///
    /// **One per message, made here and put in the environment for this message's content**, which is what lets a waveform say *this finger is mine* without
    /// knowing which message it is drawn in.
    @State private var whatTheFingerIsReallyOn = AFingerOnSomethingInsideAMessage()

    /// Whether the overlay is drawing this message, in which case the real one draws nothing while keeping its place.
    private var theOverlayHasTakenIt: Bool { cellIdentifier != nil && theMessageBeingLifted.takenByTheOverlay == cellIdentifier }

    private var isUnderAFinger: Bool { cellIdentifier != nil && theMessageBeingLifted.beingPressed == cellIdentifier }

    func body(content: Content) -> some View {
        content
            // **Handed to the content and to nothing else**, so that a control can only ever say that a finger on it is on *this* message — see
            // ``AFingerOnSomethingInsideAMessage``.
            .environment(\.aFingerOnSomethingInsideAMessage, whatTheFingerIsReallyOn)
            // **First, and above everything else this modifier adds**, so that what is published is where the message *lays out* rather than where it happens to
            // be drawn: the shrink below is a rendering transform, and an anchor taken after it would report a frame 3% too small.
            .anchorPreference(key: WhereTheMessagesAre.self, value: .bounds) { anchor in
                guard let cellIdentifier else { return [:] }
                return [cellIdentifier: anchor]
            }
            // Hidden rather than removed. A message taken out of the row would collapse it, and the whole discussion below would jump by the height of one
            // message at the exact moment the reader is looking at it.
            .opacity(theOverlayHasTakenIt ? 0 : 1)
            // The press being noticed, before it has been held long enough to mean anything. Scaled about the near edge, so a bubble shrinks towards the side it
            // hangs from instead of drifting away from it.
            .scaleEffect(isUnderAFinger ? Self.howMuchAPressedMessageShrinks : 1, anchor: side.nearEdge)
            .animation(.easeOut(duration: 0.12), value: isUnderAFinger)
            // **No `contentShape`, deliberately.** Without one the press is felt where the message is actually drawn, so the empty half of the row beside a short
            // bubble belongs to nobody — which is what a reader expects, and what Messages does. Adding a shape here would make the whole width of every row
            // liftable.
            // **Not on a Mac** — decided 2026-08-26, walking Step 54, and it is the second behaviour withdrawn from that platform the same afternoon.
            //
            // Once the body became a `UITextView` so that it could be selected, a click held on a message opened the menu only when the button was
            // **released**: the Mac's text layer answers the mouse-down itself, beginning a selection, and our press is a SwiftUI gesture that takes no part
            // in UIKit's arbitration — so it cannot win a race it is not in. Disabling the text view's own recognisers did not help, and could not: they are
            // for a finger. Worse, holding after a double-click to extend a selection word by word — which is how anyone selects on a Mac — collided with it.
            //
            // So the press is withdrawn there rather than repaired, on the reader's judgement that *"right click to show the menu + emojis is enough"*. That
            // is only true because **Step 55 made it true this morning**: a secondary click opens the same overlay with the same bar. Nothing on iOS or
            // iPadOS changes, where the press is the only way in and nothing competes for it.
            #if !targetEnvironment(macCatalyst)
            .onLongPressGesture(minimumDuration: Self.howLongAPressIsHeldBeforeItMeansSomething) {
                reportThatItWasHeldLongEnough()
            } onPressingChanged: { pressing in
                if pressing { theTouchHasLastedLongEnoughToBeAPress() } else { theTouchIsOver() }
            }
            #endif
            // **A double tap acts at once, and what it does depends on who wrote the message.** Step 22a, as amended by Step 56. It shows nothing: no overlay, no
            // bar of favourites, and no picker. The long press is what offers a choice.
            //
            // **After the long press in this chain, and that is on purpose.** SwiftUI arbitrates between the two by itself — measured in a spike, where a row's
            // double tap left the taps *inside* the row working and stopped the single tap from firing twice — but a gesture added before the press would be
            // offered the touch first.
            // **And it does not exist on a Mac at all** — decided 2026-08-26, walking Step 54. There a double-click means *select a word*, and the platform
            // does it whatever we ask: the Mac's text layer answers the mouse independently of UIKit's recognisers, so both happened at once — a word
            // selected **and** the message opened for editing. Asked which should give way, the reader chose selection, without hesitation: *"I do want text
            // selection more"*.
            //
            // So this is a **withdrawal on one platform of two shipped behaviours** — 22a's react-with-an-emoji and 56's edit-what-you-sent — and it is
            // worth naming as that rather than as a guard. Both remain the whole of what a double tap means on iOS and iPadOS, where nothing competes for it.
            // What a Mac reader loses is nothing they cannot reach: the menu offers Edit and React, and it is a right-click away since Step 55.
            #if !targetEnvironment(macCatalyst)
            .onTapGesture(count: 2) {
                theDoubleTapMeansWhatThisKindOfMessageAnswersTo()
            }
            #endif
            // **So that VoiceOver never needs the long press at all.** One action rather than one per entry: what a message offers is computed at press time, on
            // the main thread and against the view context, and doing that for every message on screen is precisely what step 21a exists to avoid. This asks for
            // the same menu the press asks for, and the menu then lists everything.
            .accessibilityAction(named: Text("MESSAGE_ACTIONS")) {
                reportThatItWasHeldLongEnough()
            }
            // **And a secondary click asks for it too, on a Mac**. Here rather than at the three cell views, so that whatever the press covers this
            // covers: it reports the same `heldLongEnough` into the same channel, and there is nothing for the two to disagree about. Nothing at all on a touch
            // platform, which ``TheSecondaryClickOnAMessage`` explains is a correctness requirement rather than a scope decision.
            .modifier(TheSecondaryClickOnAMessage(cellIdentifier: cellIdentifier, model: model))
            // **Step 48's hover button is *not* here, and that is the one thing to know before moving it back.** It was, for an hour: this modifier wraps
            // `MessageItself`, which carries a **greedy** frame so that the ephemerality countdown can sit beside the message — so its width is the width of
            // the *row*, 1098pt on a Mac window, and an overlay aligned to its edge lands at the far end of the cell rather than beside the bubble. Seen at
            // once on a screenshot. The button hangs on `theColumn` in each cell view instead, which is *the message's own width* — the same distinction the
            // comment on that property already draws for the jump highlight, and the same one that made this morning's first probe useless.
    }


    /// Says what happened to this message, when it is one at all — see ``cellIdentifier``.
    private func report(_ press: (SingleDiscussionView.CellIdentifier) -> PressOnAMessage) {
        guard let cellIdentifier else { return }
        pressesOnMessages?.report(press(cellIdentifier))
    }


    private func reportThatItWasHeldLongEnough() {
        guard let cellIdentifier else { return }
        pressesOnMessages?.report(.heldLongEnough(cellIdentifier, showing: model))
    }


    /// Waits out an ordinary tap before saying that this message is being pressed.
    ///
    /// **A tap is not a press, and it used to look like one.** `onPressingChanged` fires the instant a finger lands, so tapping a photograph to open it shrank the
    /// whole message by 3% on the way — a flinch that reads as a long press beginning and then thinking better of it. A tap lasts sixty to a hundred milliseconds;
    /// waiting longer than that before acknowledging anything means a tap is never acknowledged at all, while a real press still gets its answer some three tenths
    /// of a second before the menu arrives.
    ///
    /// **A duration threshold, which is what a `UILongPressGestureRecognizer`'s `minimumPressDuration` is.** The rule
    /// against timing things with a clock is about *animations* — an animation is done when the
    /// animation says so. This is not that: the length of a touch is the very thing being measured, and a cancellable wait is the honest way to measure it while
    /// the press is a SwiftUI gesture. When the press becomes a UIKit recogniser — Step 41 — `minimumPressDuration` replaces this, and brings `allowableMovement`
    /// with it, which this cannot express.
    private func theTouchHasLastedLongEnoughToBeAPress() {
        theTouchIsOver()
        theWaitBeforeSayingItIsAPress = Task { @MainActor in
            try? await Task.sleep(seconds: Self.howLongATouchLastsBeforeItIsAPress)
            // A cancelled sleep still runs what follows it, so the cancellation has to be looked at rather than trusted to throw — see
            // `SingleDiscussionCellsListView`, where the same `try?` cost a probe its recording window.
            guard !Task.isCancelled else { return }
            // **Nothing is said for a finger on a control drawn inside the message** — finding 18, and see ``AFingerOnSomethingInsideAMessage`` for the five of
            // them and what each one does instead of lifting.
            //
            // **Asked here rather than when the touch landed, and that is what makes it robust.** Two gestures are being delivered the same touch and the order
            // of their callbacks is SwiftUI's business, not ours; by this point a tenth of a second has gone by and whichever speaks first has spoken. Nothing
            // has to be known about the arbitration at all.
            guard !whatTheFingerIsReallyOn.thereIsOne else { return }
            report(PressOnAMessage.began)
        }
    }


    /// The finger has gone, or the press was cancelled — by a scroll, most often. Says so only if this message was ever said to be pressed.
    private func theTouchIsOver() {
        theWaitBeforeSayingItIsAPress?.cancel()
        theWaitBeforeSayingItIsAPress = nil
        // **Cleared unconditionally, as a backstop, and the failure direction is what makes it the right one.** A control that somehow never says its finger has
        // gone would otherwise leave this message unpressable for the life of the screen — a wedge, and the worst thing a gesture can be. Cleared here, the worst
        // a missed report can cost is one message that shrinks when it should not have, which is the behaviour of yesterday and nothing new.
        whatTheFingerIsReallyOn.thereIsAFingerOnAControl(false)
        report(PressOnAMessage.ended)
    }


    /// **A double tap means one thing on a message received and another on one the reader sent**, and a departure worth stating rather than a symmetry
    /// worth preserving.
    ///
    /// Reacting to your own message is rare; **editing** it is what a reader wants and today costs a press and a menu. So a double tap on a sent message opens the
    /// draft for rewriting, and on anything else it reacts.
    ///
    /// **A sent message that cannot be edited answers nothing at all** — wiped, read once, a location still being shared, one sent from another device. Decided
    /// 2026-08-26, and the trade is stated where the question is asked, in ``WhatAMessageOffers/offersToEdit``: one rule with no exceptions, at the cost of a
    /// silence the reader cannot predict from looking at the message. The alternative was to fall back to reacting, which is never silent and makes the same
    /// gesture mean two things on two messages that look alike.
    ///
    /// **A system message reacts rather than edits**, which costs nothing: it can never be reacted to either, so the call below returns at its first guard.
    private func theDoubleTapMeansWhatThisKindOfMessageAnswersTo() {
        switch model {
        case .sentMessage:
            rewritesWhatWasSent()
        case .receivedMessage, .systemMessage:
            reactsWithTheEmojiADoubleTapSends()
        }
    }


    /// Opens what the reader sent for rewriting, if it may be rewritten at all.
    ///
    /// **The same question the menu asks, asked the same way** — `whatTheMessageOffers`, at the moment of the gesture and against the view context — so the
    /// gesture and the menu can never disagree about whether this message may be edited. It then asks for the identical action the menu's entry asks for, so
    /// there is one edit path and not two.
    private func rewritesWhatWasSent() {
        guard let cellIdentifier, let dataSource else { return }
        guard dataSource.whatTheMessageOffers(cellIdentifier: cellIdentifier).offersToEdit else { return }
        feedback.notificationOccurred(.success)
        Task { await actions.userWantsToActOnMessage(cellIdentifier: cellIdentifier, action: .edit) }
    }


    /// Reacts to this message with the emoji a double tap sends, or takes that reaction off again.
    ///
    /// **The same two questions the long press asks, asked the same way**, so the two gestures can never disagree about what a
    /// message allows: `whatTheMessageOffers` says whether this message may be reacted to at all, and `whatTheReaderMayReactWith`
    /// says what this reader has already put on it. Both are answered at the moment of the gesture, against the view context, which
    /// is why they are not carried in the cell's model.
    ///
    /// **It toggles.** Double-tapping a message the reader has already reacted to with this same emoji removes the reaction, exactly
    /// as tapping the chosen emoji in the bar does. A different emoji is replaced.
    ///
    /// Nothing happens at all on a message that may not be reacted to: a system message, a wiped one, one still to be revealed.
    private func reactsWithTheEmojiADoubleTapSends() {

        guard let cellIdentifier, let dataSource else { return }
        guard dataSource.whatTheMessageOffers(cellIdentifier: cellIdentifier).offersToReact else { return }

        let emojis = dataSource.whatTheReaderMayReactWith(cellIdentifier: cellIdentifier)
        guard let theEmojiADoubleTapSends = emojis.theEmojiADoubleTapSends else { assertionFailure(); return }

        let emoji: String? = (emojis.theReadersOwn == theEmojiADoubleTapSends) ? nil : theEmojiADoubleTapSends

        feedback.notificationOccurred(.success)
        Task { await actions.userWantsToActOnMessage(cellIdentifier: cellIdentifier, action: .reactWith(emoji: emoji)) }

    }


    /// How long a press is held before the message is lifted.
    ///
    /// Between the system's own context menu and the 0.5s the legacy screen gives its Catalyst recogniser. Short enough not to feel like waiting, long enough that
    /// scrolling with a lazy thumb does not lift a message on the way past.
    private static let howLongAPressIsHeldBeforeItMeansSomething: TimeInterval = 0.4

    /// Enough to be felt and not enough to be read as a movement.
    private static let howMuchAPressedMessageShrinks: CGFloat = 0.97

    /// How long a finger stays down before it is a press rather than a tap — see ``theTouchHasLastedLongEnoughToBeAPress()``.
    ///
    /// Longer than an ordinary tap, which is sixty to a hundred milliseconds, and far short of the four tenths the menu waits for, so the acknowledgement still
    /// arrives well before the lift.
    private static let howLongATouchLastsBeforeItIsAPress: TimeInterval = 0.15

}


/// Hidden for as long as the overlay is drawing a copy of this message.
///
/// **The reactions chip needs this and nothing else in the cell does**, because the chip is the one thing outside the
/// lifted message that *overlaps* it: it rises 12pt into the bubble — `riseIntoTheBubble`, derived in step 20a — so it sits
/// in exactly the region the copy occupies. While the copy is up the chip is underneath it, dimmed and partly occluded, and
/// the instant the overlay goes it is fully visible and in front. Nothing has moved; what the reader sees is a chip
/// crossing from behind the bubble to on top of it. **Choosing a reaction makes it worst**, the chip changing while it is
/// hidden, so the new reaction appears to arrive from behind the message.
///
/// Hidden with the message and given back with it, in the same frames, so a message lands *with* its new reaction — which
/// is what should be conveyed.
///
/// `opacity` and not a removal, as for the message itself: `TheDateRowAndItsReactions` reserves the chip's height, and
/// taking the chip out of the layout would move the date row.
private struct HiddenWhileTheOverlayHasThisMessage: ViewModifier {

    let cellIdentifier: SingleDiscussionView.CellIdentifier?

    @Environment(\.theMessageBeingLifted) private var theMessageBeingLifted

    private var theOverlayHasIt: Bool { cellIdentifier != nil && theMessageBeingLifted.takenByTheOverlay == cellIdentifier }

    /// Whether the chip is standing aside — its **own** state, and not the environment value read directly.
    ///
    /// It has to be, and the reason is worth keeping: `giveTheMessageBack()` gives the message back inside a transaction
    /// with `disablesAnimations`, which it must, the copy's removal and the message's un-hide being the crossfade this whole
    /// arrangement exists to avoid. **A `.animation(_:value:)` modifier does not override that** — tried, and the chip
    /// snapped back exactly as before, while the same modifier animated perfectly whenever the chip appeared for any other
    /// reason. So the chip's return has to happen in a transaction of its *own*, opened after the suppressed one, which is
    /// what state and the task below are for.
    @State private var isStandingAside = false

    func body(content: Content) -> some View {
        content
            .opacity(isStandingAside ? 0 : 1)
            .scaleEffect(isStandingAside ? Self.howSmallItComesBackFrom : 1)
            // **The two directions are not symmetrical.** Going, at once: nothing may be seen to leave, the message beside
            // it having gone in the same frame. Coming back, a small spring — a reaction is a thing that *lands*, and a snap
            // read as it arriving fully formed out of nowhere.
            //
            // One frame late on the way in, `task(id:)` running after the update that hid the message. At that instant the
            // copy is already drawn over the chip's place and the backdrop is coming up over the rest, so what could show
            // is a sliver for 16ms. Worth knowing; not worth a second mechanism unless it is ever seen.
            .task(id: theOverlayHasIt) {
                guard isStandingAside != theOverlayHasIt else { return }
                if theOverlayHasIt {
                    var atOnce = Transaction()
                    atOnce.disablesAnimations = true
                    withTransaction(atOnce) { isStandingAside = true }
                } else {
                    withAnimation(Self.theWayBack) { isStandingAside = false }
                }
            }
    }


    /// **The same arrival a chip has when one lands on its own**, and deliberately not something quieter.
    ///
    /// This was a tight `spring(response: 0.25, dampingFraction: 0.7)` from 85%, on the reasoning that the chip was
    /// *returning* rather than arriving and should merely settle. Logged against the real thing, that reasoning was wrong
    /// in a way worth keeping: a reaction the reader adds reaches the chip's own stream **while the chip is hidden** — 566ms
    /// before it is revealed, measured — so `MessageReactionsChipView`'s `.transition(.scale.combined(with: .opacity))`
    /// plays out in full behind `opacity 0` and is thrown away. All that was left to see was the settle, which is far too
    /// quiet to read as anything.
    ///
    /// So the reveal takes over the arrival's job, and takes its numbers too: one vocabulary for a chip appearing, whether
    /// it appears by itself or from behind a lifted message.
    private static let theWayBack: Animation = MessageReactionsChipMetrics.theArrival

    /// From nothing, as `.scale` does — see ``theWayBack`` for why this is an arrival and not a settle.
    private static let howSmallItComesBackFrom: CGFloat = 0

}


extension View {

    /// Draws nothing for as long as the context menu's overlay is showing a copy of this message — see
    /// ``HiddenWhileTheOverlayHasThisMessage``, which is about the reactions chip and says why only it needs this.
    func hiddenWhileTheOverlayHasThisMessage(_ cellIdentifier: SingleDiscussionView.CellIdentifier?) -> some View {
        modifier(HiddenWhileTheOverlayHasThisMessage(cellIdentifier: cellIdentifier))
    }


    /// Marks this view as the content of a message that the reader may lift out of the discussion — see ``AMessageThatCanBeLifted``.
    ///
    /// Applied to the *message*: everything it draws, and nothing the cell draws around it.
    func canBeLiftedOutOfTheDiscussion(_ cellIdentifier: SingleDiscussionView.CellIdentifier?, showing model: SingleDiscussionCellView.Model, hangingFrom side: TheSideAMessageHangsFrom, dataSource: (any SingleDiscussionCellViewDataSource)?, actions: any SingleDiscussionCellViewActions) -> some View {
        modifier(AMessageThatCanBeLifted(cellIdentifier: cellIdentifier, model: model, side: side, dataSource: dataSource, actions: actions))
    }

}
