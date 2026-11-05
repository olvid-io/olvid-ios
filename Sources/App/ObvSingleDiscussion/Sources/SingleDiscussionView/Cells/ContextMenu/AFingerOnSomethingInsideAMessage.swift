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
// For `OSAllocatedUnfairLock`, which holds the one boolean below — see ``PressesOnMessages`` for why a lock rather than an actor.
import os


/// Whether the finger on a message is on a **control drawn inside it** rather than on the message itself.
///
/// Finding 18 of the 2026-08-30 code review. ``AMessageThatCanBeLifted`` shrinks a message by 3% a tenth of a second after a finger lands on it, and that shrink
/// means one thing: *a long press is beginning; hold and the message will lift*. Inside a message there are controls where holding does no such thing, and there the
/// feedback is a promise the screen cannot keep.
///
/// **Measured on an iPhone 13 on 2026-09-01, holding still for two seconds on each.** Five of them, and the answer was the same five times — the message shrank and
/// the overlay never opened:
///
/// | held on | shrinks | lifts | and instead, on release |
/// |---|---|---|---|
/// | the waveform of a voice message | yes | **no** | seeks to where the finger was |
/// | its play button | yes | **no** | plays |
/// | its speed capsule | yes | **no** | changes the speed |
/// | an answer of a poll | yes | **no** | votes for that answer |
/// | a location's itinerary button | yes | **no** | opens Apple Maps |
///
/// The control was a hold on the body of an ordinary text message, which shrank *and* lifted — so the walk was not a silent no-op, which is the one way a
/// five-row table of *no* could have meant nothing at all.
///
/// **The two mechanisms are different and only the first was in the finding.** The waveform's `DragGesture(minimumDistance: 0)` takes the touch and wins it, so the
/// press never completes. A `Button` is stranger: it neither cancels on a long hold nor lets the press through — the action fires on release however long the finger
/// stayed, and the ancestor's long press is simply never recognised. Whatever the cause, from the reader's side they are one fault, and from ours one fix.
///
/// **What the walk was worth, beyond the five rows.** The finding named the waveform and guessed at *"the two buttons"*; it also read the play button as behaving
/// differently from the rest, which it does not — the shrink is 3% about the near edge and simply hard to see on a control that small. Every one of the five
/// behaved identically, and a probe said so to the millisecond where the eye could not.
///
/// **Why the press cannot simply be narrowed instead.** ``AMessageThatCanBeLifted`` deliberately has **no `contentShape`**, so that the press is felt exactly where
/// the message is drawn and the empty half of a row belongs to nobody. There is no shape subtraction to express *everywhere the message is drawn except these
/// controls*, and there is no location in `onPressingChanged` to test against one. So the controls say so, and this is where they say it.
///
/// **One box per message, and that is what makes it need no identifier.** ``AMessageThatCanBeLifted`` makes one of these and puts it in the environment *for its own
/// content*, so a control can only ever speak about the message it is drawn in. A single screen-wide channel — the shape ``PressesOnMessages`` uses — would have
/// needed a `CellIdentifier` that a waveform does not have and should not be given, and two fingers on two messages could have spoken for each other.
///
/// `Sendable` without an actor, the mutable state being held under a lock: a control may report from wherever a finger is felt.
final class AFingerOnSomethingInsideAMessage: Sendable {

    private let itIsOnAControl = OSAllocatedUnfairLock(initialState: false)

    /// Whether a finger is on a control drawn inside this message right now.
    var thereIsOne: Bool {
        itIsOnAControl.withLock { $0 }
    }

    /// Said by a control as a finger lands on it and again as it leaves.
    func thereIsAFingerOnAControl(_ thereIs: Bool) {
        itIsOnAControl.withLock { $0 = thereIs }
    }

}


extension EnvironmentValues {

    /// How a control drawn inside a message says that the finger on it is on **it**, and not on the message around it — see ``AFingerOnSomethingInsideAMessage``.
    ///
    /// Optional, with nothing as its default, for the reason ``EnvironmentValues/pressesOnMessages`` gives: a control drawn outside this screen — every preview of a
    /// cell, and the poll bubble as the legacy screen hosts it — speaks to nobody rather than to a stand-in.
    var aFingerOnSomethingInsideAMessage: AFingerOnSomethingInsideAMessage? {
        get { self[AFingerOnSomethingInsideAMessageKey.self] }
        set { self[AFingerOnSomethingInsideAMessageKey.self] = newValue }
    }

}


private struct AFingerOnSomethingInsideAMessageKey: EnvironmentKey {
    static let defaultValue: AFingerOnSomethingInsideAMessage? = nil
}


// MARK: - Saying it from a control that already knows

/// Reports a finger on this view, from a boolean the view already has.
///
/// **Driven by a value rather than by a gesture of its own**, which is the whole reason this is cheap: the waveform's
/// ``AudioPlayerView/thereIsAFingerOnTheWaveform`` is a `@GestureState`, set as the touch lands and put back by SwiftUI when the gesture ends **or is cancelled**.
/// That property exists because of finding 9, and it does this finding's work for nothing. A gesture added here would have to arbitrate with the one that is
/// already winning the touch, which is the family of fault met by the drag interaction and the context menu's long press.
private struct AFingerOnThisIsNotAPressOnTheMessage: ViewModifier {

    let thereIsAFinger: Bool

    @Environment(\.aFingerOnSomethingInsideAMessage) private var aFingerOnSomethingInsideAMessage

    func body(content: Content) -> some View {
        content
            .onChange(of: thereIsAFinger) { thereIsOne in
                aFingerOnSomethingInsideAMessage?.thereIsAFingerOnAControl(thereIsOne)
            }
            // **A cell may be recycled with a finger still on it**, and a boolean that never comes back would then leave this message unable to be pressed. The
            // press has a backstop of its own — ``AMessageThatCanBeLifted/theTouchIsOver()`` clears the box whatever it holds — so this is the second of two, and
            // deliberately: the failure that matters is a message that can no longer be lifted at all, and one guard for that is not enough.
            .onDisappear {
                if thereIsAFinger { aFingerOnSomethingInsideAMessage?.thereIsAFingerOnAControl(false) }
            }
    }

}


// MARK: - Saying it from a control that does not know, which is every button

/// Reports a finger on this view, from a long press of this view's own that is never held long enough to fire.
///
/// **A `ButtonStyle` reading `configuration.isPressed` was the obvious mechanism and it is measured wrong.** On an iPhone 17 simulator, 2026-09-01, four holds on
/// four different buttons inside a message, agreeing to within 7ms:
///
/// ```
/// T          a finger LANDED ON the message
/// T + 163    the wait is over: a finger is on a control = false, so the press is SAID
/// T + 385    a finger is ON a control inside the message      ← 220ms too late, every time
/// ```
///
/// A button's press state inside this `List` arrives around 385ms after the touch — close enough to
/// ``AMessageThatCanBeLifted/howLongAPressIsHeldBeforeItMeansSomething`` (0.4s) to suspect that is what holds it back. Whatever the cause, it can never beat the
/// tenth of a second the press waits, so the style could not have worked and lengthening the wait to reach it would have left ten milliseconds of margin.
///
/// **And a `DragGesture(minimumDistance: 0)` is not the answer either**, though it does report at touch-down: a SwiftUI drag in a `List` row **blocks the scroll**,
/// which is exactly why a vertical drag on the waveform does not scroll the transcript. On a poll's answers, which cover most of the bubble, that would have taken
/// the reader's ability to scroll there.
///
/// **What is left is the thing already proved to work on this very screen.** `onPressingChanged` of a long press fires at touch-down — the `LANDED` line above is
/// one — and the transcript scrolls over messages perfectly well, so a long press neither reports late nor eats the scroll. This gives the control one of its own
/// with a duration it will never reach, so it never fires and exists only to say when the finger came and went. A scroll cancels it, which reports the finger
/// leaving, which is right.
///
/// Measured again after the change, same simulator, same probe:
///
/// ```
/// T + 0…3ms    a finger is ON a control inside the message      ← was T + 385
/// T + 160      the wait is over: a finger is on a control = true, so the press is WITHHELD
/// ```
///
/// **Five holds on controls, all five withheld; three holds on a poll's question, on a bubble's padding and on a plain message, all three said.** Both halves
/// matter: five withholdings alone read exactly as an opt-out that suppresses everything, and the three said are what rule that out. And the scroll was walked
/// from each of the five controls in turn, which is the assumption this whole mechanism rests on.
private struct AFingerOnThisIsNotAPressOnTheMessageEither: ViewModifier {

    @Environment(\.aFingerOnSomethingInsideAMessage) private var aFingerOnSomethingInsideAMessage

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: Self.longerThanAnybodyWillHold) {
                // Never reached, and nothing would be right here if it were: this gesture is a witness, not an action.
                assertionFailure()
            } onPressingChanged: { pressing in
                aFingerOnSomethingInsideAMessage?.thereIsAFingerOnAControl(pressing)
            }
    }

    /// An hour. `TimeInterval.infinity` was not risked in a framework's timer.
    private static let longerThanAnybodyWillHold: TimeInterval = 3600

}


extension View {

    /// Says that a finger on this view is on **this view** and not on the message around it, so the message does not pretend a long press is beginning — see
    /// ``AFingerOnSomethingInsideAMessage``.
    ///
    /// Given a boolean the view already has: a `@GestureState` of the gesture that is taking the touch anyway.
    func aFingerHereIsNotAPressOnTheMessage(_ thereIsAFinger: Bool) -> some View {
        modifier(AFingerOnThisIsNotAPressOnTheMessage(thereIsAFinger: thereIsAFinger))
    }


    /// The same, for a control that has no such boolean — which is every `Button`. See ``AFingerOnThisIsNotAPressOnTheMessageEither`` for the two mechanisms that
    /// were measured and rejected first, and why this one is the only one of the three that both reports in time and leaves the scroll alone.
    func aFingerHereIsNotAPressOnTheMessage() -> some View {
        modifier(AFingerOnThisIsNotAPressOnTheMessageEither())
    }

}
