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

import OSLog
import SwiftUI
import SwiftUIIntrospect
import UIKit


/// Moves the messages when the space below them changes, so that what the reader was looking at stays where it was, rebuilt as 46d.
///
/// **The keyboard never moves the scroll offset.** SwiftUI answers it with the bottom inset alone — measured over six recordings, the offset
/// identical before and after in every one. So without this rule the keyboard simply covers the bottom of the transcript, and at the end of a
/// discussion the last message goes behind it.
///
/// ## Five rules, and each one was a bug first
///
/// **Compute where the messages go. Never predict it.** The keyboard is 335pt tall and the inset changes by 317, because the home indicator is
/// under the keyboard and the keyboard adds a margin of its own. Writing that as *keyboard + margin − home indicator* is the mistake to avoid:
/// a list of named parts cannot be known to be complete. Read the geometry as it stood before the change instead — and not when the
/// notification arrives, because the scroll view has already taken the first step by then.
///
/// **Write a position, not a difference.** The first version added the change in the inset to the offset it found. Right going up, wrong coming
/// down, the last message landing 301pt behind the composition bar: when the inset shrinks, UIKit's clamp has already moved the content, so
/// subtracting the same amount again counts it twice. An absolute position makes the clamp something this rule agrees with rather than something
/// it must know about. See ``answersAChangeOfWhatCanBeSeen(from:to:on:isUnderTheReadersFinger:arrivingAFrameAtATime:)``.
///
/// **Act only for the keyboard.** The composition bar changes the same number and is answered only at the end of its movement, which is Step 44e.
/// `keyboardWillChangeFrame` arms and `keyboardDidChangeFrame` disarms — two notifications rather than a timer, so nothing guesses when a movement
/// is over. The inset arriving in two steps costs nothing: each step answers from its own *before*, and two steps land where one does.
///
/// **Never while the reader has hold of the transcript.** Dragging the keyboard away changes the inset about thirty times while the finger is
/// already moving the content. Answering those would be a second writer for one event, which is the fault this step exists to prevent.
///
/// **Wherever the reader is, not only at the end.** That is what legacy does, and it removes the need for an "am I at the end" test — a test with
/// a tolerance is what made every earlier version fragile. The end falls out as a special case instead of being one.
///
/// ## Animate a step, track a movement
///
/// The keyboard's inset arrives in **one** step of 317pt, so that is animated. The composition bar's reparameterisation and a keyboard dragged
/// away arrive **per frame**, so those are tracked: hold the content point at the bottom edge on every presented frame and the transcript rides
/// the change instead of jumping to its end. The keyboard's own announcement tells the two apart. Read per frame, the *before* is one frame ago,
/// and there is nothing left to animate.
///
/// **This is not a `ViewModifier`.** It is called by the object that reads the geometry, which already holds the scroll view and already knows
/// whether the reader has hold of it. One object reads, one rule answers, and there is exactly one writer of `contentOffset` — the doctrine of
/// Step 44, structural rather than agreed.
///
/// The cost, which could not be measured in advance: tracking is only as smooth as the frames are punctual. A dropped frame is invisible when a
/// `UIView` animation interpolates through it and would be visible here.
///
/// Five versions of this were wrong before this one, and it replaced two defects.
@MainActor
final class MovesTheMessagesWhenTheSpaceBelowThemChanges {

    /// The keyboard movement now in flight, if there is one: how long it takes and on which curve. Nil between movements.
    private var theMovementOfTheSpaceBelow: TheMovementOfTheSpaceBelow?

    /// How many times this rule has acted within the current keyboard movement.
    ///
    /// The keyboard's inset is delivered **coarsely on iOS 26** — two steps (`84 → 385 → 401`), which the spring rides — but **per-frame on iOS 18**,
    /// ~22 steps one frame apart. Restarting the heavily-overdamped spring every frame is fatal: an overdamped spring barely moves in a single frame, and
    /// it never gets more than one before being replaced, so the presentation sits still through the whole rise and only the final animator, uninterrupted,
    /// produces a late glide — the content reaching its place ~250ms *after* the keyboard settles. Measured on an iPhone SE (iOS 18) 2026-08-25.
    ///
    /// So the first ``springStepsBeforeTracking`` steps are sprung as before, and any beyond that — which only a per-frame delivery ever reaches — are set
    /// outright, so the content rides the keyboard frame-for-frame. iOS 26 never reaches the outright branch, so its behaviour is unchanged by construction.
    private var stepsInThisMovement = 0

    /// iOS 26 delivers the keyboard inset in two steps; anything past this many within one movement is a per-frame delivery, tracked outright rather than
    /// sprung. Kept at the measured coarse-step count so the iOS 26 path is untouched.
    private static let springStepsBeforeTracking = 2

    /// The watch on the keyboard, which is taken off when this object goes — see ``TheWatchOnTheKeyboard``, which is where the taking off lives and why.
    private var theWatchOnTheKeyboard: TheWatchOnTheKeyboard?


    /// **Observed here rather than by a view**, since Step 46d: this is the only thing that uses them, and it is no longer a `ViewModifier` that
    /// could carry an `onReceive`.
    /// **The arming must not hop, and that took a challenge to notice.** The first version read the notification's two numbers synchronously — a
    /// `Notification` may not cross an isolation boundary — and then assigned them inside a `Task { @MainActor }`. `onScrollGeometryChange` fires
    /// during SwiftUI's update pass, which is frequently *before* that task runs, so the rule read `theMovementOfTheSpaceBelow` as `nil` and fell
    /// through to `timeTakenToMakeRoomForTheBar`: the keyboard was animated with the composition bar's invented 0.35s ease-in-out.
    ///
    /// Measured on 2026-08-25 after being doubted rather than after being suspected: `keyboard=no` on both steps of a keyboard's own inset, and a
    /// convergence of **19 frames / 317ms with progress 0.445 at its midpoint** — a symmetric curve of the fallback's length, where a keyboard's
    /// decelerating curve would have passed 0.85 by then. And it is a *race*, not a constant failure: earlier logs hold `keyboard=yes` lines, so
    /// which animation the reader got was a coin flip.
    ///
    /// So the assignment is made in the observer itself. Keyboard notifications are posted on the main thread, which is what `assumeIsolated` asserts
    /// — and because asserting is not proving, the hop is kept as a fallback rather than trapping if that is ever untrue. Late is wrong; crashing is
    /// worse.
    /// `nonisolated` deliberately: it is called straight from a notification block, and the point of it is to *not* hop. Were it left
    /// main-actor-isolated the compiler would insert the hop itself, which is the bug.
    private nonisolated func armsOrDisarms(_ theMovement: TheMovementOfTheSpaceBelow?, arming: Bool) {
        let apply: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            // The keyboard posts several `willChangeFrame` notifications for one movement, and the first is the one that describes it.
            if arming {
                guard theMovementOfTheSpaceBelow == nil else { return }
                theMovementOfTheSpaceBelow = theMovement
                stepsInThisMovement = 0
            } else {
                theMovementOfTheSpaceBelow = nil
                stepsInThisMovement = 0
            }
        }
        // **DEBUG INSTRUMENT.** Says what arrived and when, because `keyboard=no` at the rule cannot distinguish *no announcement* from
        // *an announcement this rule filters out* — and a first attempt at this fix was judged against exactly that ambiguity.
        if arming {
            Self.saysWhatItDid("keyboard announced a movement",
                               theMovement.map { String(format: "%.0fms curve=%d", $0.duration * 1000, $0.theCurveAsAnnounced) } ?? "but nothing readable in the notification")
        } else {
            Self.saysWhatItDid("keyboard movement over", "disarmed")
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated { apply() }
        } else {
            assertionFailure("A keyboard notification off the main thread: the arming will be a frame late, which is the fault this method exists to fix.")
            Task { @MainActor in apply() }
        }
    }


    init() {
        theWatchOnTheKeyboard = TheWatchOnTheKeyboard([
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: nil) { [weak self] notification in
                // Read here rather than carried anywhere: a `Notification` may not cross an isolation boundary, and what is wanted from it is two numbers.
                self?.armsOrDisarms(TheMovementOfTheSpaceBelow(notification), arming: true)
            },
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidChangeFrameNotification, object: nil, queue: nil) { [weak self] _ in
                self?.armsOrDisarms(nil, arming: false)
            },
        ])
    }

    /// Answers a change of how much of the discussion can be seen, on the frame it is first seen.
    ///
    /// **Everything is computed from `asItWas`**, the geometry as the previous frame presented it, and nothing is remembered between frames.
    ///
    /// Returns the offset it put the messages at, or nil where it left them alone — **and the caller has to remember it.** The inset of a keyboard arrives in
    /// *two* steps, 84 → 385 → 401, so the rule runs twice; the second run chains from what the previous frame reported, and that was taken **before** this
    /// rule wrote to it. So the geometry it chains from is `offset 52928 with inset 385` — the new inset and the old offset, a mixture that never existed as a
    /// resting state — and the second step lands 285pt out:
    ///
    /// ```
    /// frame 68: inset=385.0 offset=52928.0 fromTheEnd=301.0    ← step one; this writes 53229
    /// frame 69: inset=401.0 offset=53229.0 fromTheEnd= 16.0    ← step two, chaining from a fiction
    /// frame 70: inset=401.0 offset=52944.0 fromTheEnd=301.0    ← and undoing the first
    /// ```
    ///
    /// *Each step answers from its own before, and two steps land where one does* is still the invariant; what breaks it is a *before* that omits what we
    /// ourselves did.
    ///
    /// - Parameter arrivingAFrameAtATime: Whether this change is one step of something delivered **per frame**, which is true only of **Step 46n**'s window
    ///   resize on Catalyst. It decides nothing about *where* the messages go, only how they get there. Defaulted, so every existing caller means what it
    ///   meant.
    /// **Step 57: puts a reader who was at the end back at the end, once the content has stopped moving.**
    ///
    /// The rule above holds *the content point that was at the bottom edge*, which is the right invariant when the viewport changes and the wrong one
    /// when the **content** does: a rewrap makes every message taller, so the point that was at the bottom is no longer the end, and holding it
    /// faithfully preserves the gap rather than closing it. Measured on an iPad on 2026-08-26, a Stage Manager corner drag grew the content 66pt and
    /// left the 60pt gate shut for **507 frames**.
    ///
    /// **It is a separate method, and asked by the clock rather than by SwiftUI, because it answers a different question at a different time.** The
    /// rule above answers *the space below changed, now* and must land in the same frame. This answers *the content has finished moving and the reader
    /// is no longer where they were*, which cannot be known in the frame the movement starts. It is still the one type that writes `contentOffset`,
    /// which is the property Step 46 exists to keep.
    ///
    /// **Once it settles, not per step, and that was the reader's call on 2026-09-01 after walking the alternative.** A per-step version was built and
    /// it worked on the divider; what killed it was measured on the same iPad — the `List` briefly reported a content height **127.5pt** larger than
    /// the one it settled on, and a rule correcting per step chased that spike and was dragged back by the clamp 264ms later, a visible excursion.
    /// Waiting for stillness costs the last message sitting low for the length of the gesture and cannot chase a transient at all, a transient being
    /// movement by definition.
    func putsTheReaderBackAtTheEnd(on scrollView: UIScrollView, from geometry: TheGeometryOfTheTranscript) {

        let theEnd = max(-geometry.topInset, geometry.contentHeight + geometry.bottomInset - geometry.height)
        guard abs(theEnd - scrollView.contentOffset.y) > 0.5 else { return }

        Self.saysWhatItDid("put the reader back at the end, the content having settled",
                           String(format: "live=%.1f → %.1f (fromTheEnd=%.1f, content=%.1f, canSee=%.1f)",
                                  scrollView.contentOffset.y, theEnd, geometry.pointsBelowTheVisibleArea,
                                  geometry.contentHeight, geometry.heightOfWhatCanBeSeen))

        // **Set outright rather than animated.** This is a repair of a position the reader never asked to leave, and the rule above records what
        // animating a repair costs: filmed at the end of a discussion, animating the clamp's 84pt back over 0.35s turned one bad frame into three of
        // the message behind the bar and a dozen of it climbing out.
        scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: theEnd)

    }


    @discardableResult
    func answersAChangeOfWhatCanBeSeen(from asItWas: TheGeometryOfTheTranscript,
                                       to asItIsNow: TheGeometryOfTheTranscript,
                                       on scrollView: UIScrollView,
                                       isUnderTheReadersFinger: Bool,
                                       arrivingAFrameAtATime: Bool = false) -> CGFloat? {

        // **Never while the reader has hold of the transcript.** Dragging down to dismiss the keyboard changes the inset about thirty
        // times while the keyboard follows the finger, and the finger is already moving the content: answering those would be a second
        // writer for one event, which is the fault the whole of Step 44 exists to stop repeating.
        guard !isUnderTheReadersFinger else { return nil }

        // A discussion that fits on the screen has nothing to keep in place, and the rubber band it would fight is `UIScrollView`'s own.
        let theHeightItCanShowNow = asItIsNow.height - asItIsNow.topInset - asItIsNow.bottomInset
        guard asItIsNow.contentHeight > theHeightItCanShowNow else { return nil }

        // **The content point that was at the bottom edge stays at the bottom edge**, which is the whole rule and the one invariant every case falls
        // out of: at the end that point *is* the end, higher up it is the message above the bar, and through SwiftUI's reparameterisation of the
        // list it barely moves.
        //
        // **A geometry that disagrees with the scroll view by more than a clamp could explain is stale, and this rule must not act on it.**
        //
        // `asItWas` is not "the geometry one frame ago". It is *the geometry the last time this action ran*, and `onScrollGeometryChange` does not
        // observe a `ScrollViewProxy.scrollTo` at all — so between two changes of the space below, the reader may have been taken anywhere and this
        // will not have been told. Measured: a message sent from the middle scrolled correctly and settled, then 1.34s later the bar's height
        // changed and this rule was handed an `asItWas.offset` captured 4.5 seconds and **7,900pt** earlier. It put the content back there.
        //
        // **The bound is on the two terms, not on their difference, and that distinction cost a defect.** The first version bounded on
        // `heightOfWhatCanBeSeen` — `height - bottomInset` — reasoning that the clamp can move the offset by at most that change. True of every
        // ordinary movement, false of the case that needs this rule most: **a `safeAreaInset` reparameterisation preserves `heightOfWhatCanBeSeen`
        // by construction** and moves the offset by the whole inset.
        //
        // ```
        // height 472.8 → 874.0   bottomInset 0 → 401   canSee 472.8 → 473.0    the offset moved 401.4
        // ```
        //
        // So the bound came out at ~40 whatever happened, and the guard **declined at every reparameterisation there was** — refusing exactly the
        // repair `PutsTheEndBackWhenTheInsetArrivesLate` exists for, and leaving a sent message 401pt below the screen. Summing `|Δheight|` and
        // `|ΔbottomInset|` is unchanged on every case the guard was validated against and correct on the reparameterisation. (The clamp was not even
        // the mechanism: the greatest offset was 63388.0 before and 63387.7 after, so nothing was clamped — SwiftUI moved the offset itself.)
        //
        // **Declining is the whole of the answer, not half of it.** There is nothing to repair: whoever scrolled put the content where they meant it,
        // and the next change will be handed a geometry that includes it.
        //
        // **It is `asItWas` that goes stale, and only `asItWas`.** The first attempt compared the scroll view against `asItIsNow` and let everything
        // through, `asItIsNow` being the geometry that has just become true.
        let howFarTheGeometryItselfMoved = abs(asItIsNow.height - asItWas.height) + abs(asItIsNow.bottomInset - asItWas.bottomInset)
        let whatThatChangeCouldAccountFor = howFarTheGeometryItselfMoved + Self.toleranceOnAStaleGeometry
        let howFarTheOldGeometryIsFromTheTruth = abs(scrollView.contentOffset.y - asItWas.offset)
        // This refused four times out of four sends while it was reporting itself, out by 6,054 / 10,006 / 11,874 / 12,629pt against a
        // bound of 165, and 210 ordinary movements went through in the same session. Should it ever need watching again, the line it
        // printed on the way out is in the history of Step 46k — and it must be **on the way out**, since a guard that refuses in
        // silence cannot be told apart from a case that never arose.
        guard howFarTheOldGeometryIsFromTheTruth <= whatThatChangeCouldAccountFor else {
            // **DEBUG INSTRUMENT, and it says so on the way out.** A guard that refuses in silence cannot be told apart from a case that
            // never arose — which is not hypothetical here: the walk of 2026-08-24 sent twice from the middle with a keyboard up, both landed
            // correctly, and the log then showed the bar's height had not changed after either scroll, so this was never once asked.
            Self.saysWhatItDid("DECLINED, the geometry it was handed is stale",
                               String(format: "was=%.0f live=%.0f (out by %.0f, the geometry moving could explain %.0f)",
                                      asItWas.offset, scrollView.contentOffset.y,
                                      howFarTheOldGeometryIsFromTheTruth, whatThatChangeCouldAccountFor))
            return nil
        }

        let theContentPointToKeepAtTheBottom = asItWas.offset + asItWas.height - asItWas.bottomInset

        let theHighestItCanGo = -asItIsNow.topInset
        let theLowestItCanGo = max(theHighestItCanGo, asItIsNow.contentHeight + asItIsNow.bottomInset - asItIsNow.height)

        let whereItWouldGo = theContentPointToKeepAtTheBottom - asItIsNow.height + asItIsNow.bottomInset
        let whereTheMessagesGo = min(max(whereItWouldGo, theHighestItCanGo), theLowestItCanGo)

        // Half a point of tolerance, so that a rounding difference is not written back as a movement. It was accused of the 84pt short
        // landing once and cleared by measurement — the clamp had already put the offset where the rule wanted it.
        guard abs(whereTheMessagesGo - asItIsNow.offset) > 0.5 else {
            // **DEBUG INSTRUMENT, and this guard had always refused in silence until it existed.** That silence is why
            // `staying-at-the-end.md` records the reaction chip and the Split View divider as *the rule was never asked* — an inference from the
            // absence of the two lines below, both of which sit **after** this point. `contentHeight` is a member of the geometry the observer
            // watches, so a content-only change does reach here; what it then meets is this guard, and nothing said so.
            Self.saysWhatItDid("declined, there is nothing to move",
                               String(format: "was=%.0f now=%.0f → %.0f (content %.1f→%.1f, canSee %.1f→%.1f, atTheEnd=%@)",
                                      asItWas.offset, asItIsNow.offset, whereTheMessagesGo,
                                      asItWas.contentHeight, asItIsNow.contentHeight,
                                      asItWas.heightOfWhatCanBeSeen, asItIsNow.heightOfWhatCanBeSeen,
                                      asItWas.theReaderIsAtTheVeryEnd ? "YES" : "no"))
            return nil
        }

        // **Animated when the change arrives as a step, set when it arrives a frame at a time**, and which is happening is not a guess: a keyboard
        // movement announces itself with a duration and a curve, and nothing else does. See the rules at the top of this file.
        //
        // Measured 2026-08-23: the keyboard's inset reaches the scroll view in **one step of 317pt**, so there is nothing in it to ride and tracking
        // would collapse into a jump. Dragging the keyboard away is the opposite — the inset steps down per frame — and so is the composition bar's
        // reparameterisation, over `bounds`.
        //
        // **A repair is set outright; a movement of our own is animated.** The test is whether the offset moved *without us* since the geometry was
        // last reported. If it did, somebody else has already put the content somewhere and this is a correction — and a correction that takes a third
        // of a second shows the wrong thing for a third of a second. Filmed at the end of a discussion: animating the clamp's 84pt back over 0.35s
        // turned one bad frame into three of the message sitting behind the bar and a dozen of it climbing out.
        //
        // **The keyboard keeps precedence, deliberately.** At the end of a discussion the clamp moves the offset for the keyboard too, so this test
        // would call every keyboard step a repair and lose the tracking of the keyboard's own duration.
        //
        // **An announcement of no duration is no announcement**, and falls back to this rule's own timing. **Do not remove that filter** — it was
        // removed on 2026-08-25 and put straight back. On the simulator, raising the keyboard with `Cmd+Shift+K` announces `0ms` where tapping the
        // composition bar announces `383ms`, so it looked as though an instant keyboard was being answered over a third of a second. The frames say
        // otherwise: with the offset set outright, the content jumps first and leaves a gap that the keyboard then slides up into over some eight
        // frames. The keyboard animates and simply declines to say so. Matching the observed ~133ms would be a duration hand-copied from one reading
        // of a simulator artefact, `Cmd+Shift+K` being no device behaviour at all.
        let theMovement = theMovementOfTheSpaceBelow.flatMap({ $0.duration > 0 ? $0 : nil })

        // **DEBUG INSTRUMENT, and said here rather than at the top, deliberately.** Everything above this point is a guard that declines; this is the last
        // moment before the offset actually changes. So a line here means a write *is* about to happen, and the pair is what makes either readable:
        // the decline above on its own cannot be distinguished from a rule that refuses everything.
        Self.saysWhatItDid(arrivingAFrameAtATime ? "acted, on a frame of a window resize" : "acted",
                           String(format: "was=%.1f now=%.1f live=%.1f → %.1f (canSee %.1f→%.1f, content %.1f→%.1f, atTheEnd=%@, keyboard=%@)",
                                  asItWas.offset, asItIsNow.offset, scrollView.contentOffset.y, whereTheMessagesGo,
                                  asItWas.heightOfWhatCanBeSeen, asItIsNow.heightOfWhatCanBeSeen,
                                  asItWas.contentHeight, asItIsNow.contentHeight,
                                  asItWas.theReaderIsAtTheVeryEnd ? "YES" : "no",
                                  theMovement.map { String(format: "yes, %.0fms curve=%d", $0.duration * 1000, $0.theCurveAsAnnounced) } ?? "no"))

        // **Step 46n: a change arriving a frame at a time is set outright, and that is not a preference.** The window's edge is under the reader's
        // pointer and moving; animating each step over ``timeTakenToMakeRoomForTheBar`` would leave the content trailing the edge by that much and
        // stack twenty overlapping animations doing it. It is the same reasoning as the iOS 18 keyboard branch below — *a per-frame arrival is
        // itself the animation* — and it is tested first because a resize announces no keyboard and would otherwise fall to the animated `else`.
        if arrivingAFrameAtATime {
            scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: whereTheMessagesGo)
            return whereTheMessagesGo
        }

        let somebodyElseHasMovedTheContent = abs(scrollView.contentOffset.y - asItWas.offset) > 0.5
        guard theMovement != nil || !somebodyElseHasMovedTheContent else {
            scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: whereTheMessagesGo)
            return whereTheMessagesGo
        }

        if theMovement != nil {
            stepsInThisMovement += 1
            if stepsInThisMovement <= Self.springStepsBeforeTracking {
                movesTheMessagesOnTheKeyboardsSpring(to: whereTheMessagesGo, on: scrollView)
            } else {
                // Past the coarse delivery iOS 26 stops at, so this is a per-frame delivery (iOS 18): the keyboard is animating the inset itself, and
                // that per-frame arrival *is* the animation. Stop the overdamped spring — restarted every frame it never accelerates — and ride the
                // keyboard by setting the offset outright, so the presentation tracks it frame-for-frame instead of gliding late once it settles.
                if let theSpringNowRunning {
                    theSpringNowRunning.stopAnimation(false)
                    theSpringNowRunning.finishAnimation(at: .current)
                    self.theSpringNowRunning = nil
                }
                scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: whereTheMessagesGo)
            }
        } else {
            UIView.animate(withDuration: Self.timeTakenToMakeRoomForTheBar,
                           delay: 0,
                           options: [.curveEaseInOut, .beginFromCurrentState]) {
                scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: whereTheMessagesGo)
            }
        }

        return whereTheMessagesGo

    }


    /// The spring the keyboard moves on, in the parameters UIKit names them by.
    ///
    /// **The keyboard's animation is a spring, not a curve, and this is the closest thing to it that can be written down.** It announces curve `7`,
    /// which is not one of the four cases of `UIView.AnimationCurve` and can only be reached by putting the raw value into the high bits of an option
    /// set. That was done here until 2026-08-25, and it *worked* — measured against all three documented curves through a 383ms movement it matched
    /// none of them, an S-curve well ahead of `easeInOut`, well behind `easeOut`, and not linear, which is only explicable if UIKit applies the private
    /// curve. It was abandoned for fragility rather than failure: an undocumented value in an undocumented bit field, whose failure mode is a silently
    /// different animation. `easeOut` was tried in its place and looked worse.
    ///
    /// These are the community's reverse-engineered parameters for the real thing, and they are **heavily overdamped** — critical damping here is
    /// `2√(km)` = 109.5, so a damping of 500 is a ratio of about 4.6, which is why the keyboard glides in and never bounces. The settling time falls
    /// out at roughly half a second, and that agrees with what was measured off the private curve: **530ms of convergence** on the 10:47 recording of
    /// 2026-08-25. Two independent routes to the same number is the reason to trust them.
    ///
    /// **They are still constants we chose rather than values the keyboard told us**, and that is the honest cost of the swap. What is bought for it is
    /// an API that is documented and numbers that are physical: a mismatch shows up as a glide of the wrong weight, which can be reasoned about, where
    /// a wrong enum shows up as nothing at all.
    private static let theKeyboardsSpring = UISpringTimingParameters(mass: 3, stiffness: 1000, damping: 500, initialVelocity: .zero)


    /// The animator now running the keyboard's spring, if there is one — held so that the **second** step of the inset can take over from the first.
    ///
    /// The keyboard's inset arrives in two steps, measured 84 → 385 → 401, so this rule runs twice for one movement. `UIView.animate` had
    /// `.beginFromCurrentState` for that; a `UIViewPropertyAnimator` has to be stopped by hand, or two animators fight over one property.
    private var theSpringNowRunning: UIViewPropertyAnimator?


    /// Moves the messages on the keyboard's own spring.
    ///
    /// **This still copies rather than participates**, and no spring fixes that: our animation begins when `onScrollGeometryChange` fires, some 11ms
    /// after the keyboard's has started, so it finishes 11ms late. The legacy screen matches exactly because it writes `contentInset.bottom` *inside*
    /// the keyboard's animation block and lets the clamp carry the content as part of that one animation — it rides the keyboard, where this screen
    /// copies it, `safeAreaInset` owning the inset here. Closing that is a different rule, and it is where 46i points too.
    private func movesTheMessagesOnTheKeyboardsSpring(to whereTheMessagesGo: CGFloat, on scrollView: UIScrollView) {

        // Stopped at where it has actually reached, so the second step continues from there rather than from the first step's destination — which is
        // what `.beginFromCurrentState` did.
        if let theSpringNowRunning {
            theSpringNowRunning.stopAnimation(false)
            theSpringNowRunning.finishAnimation(at: .current)
        }

        let theSpring = UIViewPropertyAnimator(duration: 0, timingParameters: Self.theKeyboardsSpring)
        theSpring.addAnimations {
            scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: whereTheMessagesGo)
        }
        theSpring.addCompletion { [weak self] _ in
            self?.theSpringNowRunning = nil
        }
        theSpringNowRunning = theSpring
        theSpring.startAnimation()

    }


    /// How long a movement of the space below takes — read from the keyboard's own announcement.
    ///
    /// **The notification is not the trigger**, and never was: it says only that *a change is in flight, on this curve, for this long*. Where the
    /// messages must end up is computed from the geometry, because the scroll view has already taken the first of the inset's two steps by the time
    /// the notification is delivered — measured at 301pt short when a version of this rule read the offset there.
    ///
    /// **44e-bis is absorbed rather than restored.** That distinction — set a repair outright, animate only a movement of our own — existed because a
    /// correction spread over a third of a second is a third of a second of the wrong thing being shown. The branch above now sets by default and
    /// animates only when the keyboard says a movement is in flight, which is the same answer arrived at from the other side.
    /// **DEBUG INSTRUMENT.** What this rule did, on every call that reached a decision — see the two call sites for why both a decline and
    /// an action have to be reported for either to mean anything.
    ///
    /// A category of its own, beside `TranscriptFrames` and `TranscriptAnswers`: this one is the rule's own voice, and it is the only one of the three
    /// that is *not* driven by the display link, so it carries no frame number and has to be lined up by its timestamp.
    ///
    /// **The `🎞` is what makes the three one filter**, and it is there for Xcode's console rather than for the rigs: `log stream` selects on the
    /// *category*, which the scripts do, where Xcode's filter field is a plain substring with no way to say *or*. The three probes that describe where
    /// the transcript is therefore share one sigil — the house convention, `📁` and `🏓` and the rest — and `TranscriptSwipe` and `TranscriptDrop`
    /// deliberately do not have it, being a different question.
    ///
    /// **Nothing at all outside a debug build, arguments included, and that is what the `@autoclosure` is for.** These lines shipped unguarded, and the
    /// report in ``TheSpaceBelowTheMessagesWatchedBySwiftUI`` is made *before* its guard on a geometry that carries the offset — so a ten-argument
    /// `String(format:)` ran on every frame of every scroll. The cost is not the `Logger`, it is what the call sites build to hand it, so guarding the
    /// body alone would fix almost nothing. It also leaves the unified log's fixed-size buffer for everything else this app has to say, `.fault` lines
    /// included. Every call site keeps its wording and its reasons for a walk that needs them again.
    nonisolated static func saysWhatItDid(_ what: @autoclosure () -> String, _ detail: @autoclosure () -> String) {
        #if DEBUG
        // Evaluated into locals first: an `OSLogMessage` interpolation takes its arguments as *escaping* autoclosures, and a non-escaping one may not be
        // captured by one. The two calls happen here either way.
        let whatItDid = what()
        let theDetail = detail()
        Self.rule.info("🎞 \(whatItDid, privacy: .public) | \(theDetail, privacy: .public)")
        #endif
    }


    /// Held rather than built per call, which the line above did on every frame of every scroll. `nonisolated` because the line that reads it is
    /// called from the keyboard's own notification block.
    private nonisolated static let rule = Logger(subsystem: "io.olvid.messenger", category: "TranscriptRule")


    /// How far the geometry handed to this rule may differ from the scroll view, beyond what a clamp explains, before it is treated as stale.
    ///
    /// Generous on purpose. What it must separate is an adjustment of a few points from somebody else's scroll, and the case that
    /// prompted it disagreed by **7,900pt** — so nothing is gained by making this tight, and a tight value would start refusing the rounding
    /// of a self-sizing list. It exists to catch an order of magnitude, not a decimal.
    ///
    /// It is added to `|Δheight| + |ΔbottomInset|` rather than to the difference of the two; see the guard for the reparameterisation that
    /// made the distinction matter.
    private static let toleranceOnAStaleGeometry: CGFloat = 40



    /// How long the messages take to make room for the composition bar, where the bar's change has no movement of its own to follow.
    ///
    /// **Matched to the direction that SwiftUI does animate**, so that adding the first attachment and removing it feel like one gesture rather
    /// than two: the removal reparameterises the list and animates `bounds` back over **384ms**, where the addition steps the inset once and is
    /// over in a frame.
    private static let timeTakenToMakeRoomForTheBar: TimeInterval = 0.35


    private struct TheMovementOfTheSpaceBelow: Equatable {

        let duration: TimeInterval

        /// **Feeds a debug instrument only.** The curve as the keyboard stated it, kept so that the log can say what arrived — it is not used to animate anything,
        /// and a change in what arrives is exactly what this would show.
        let theCurveAsAnnounced: Int

        init?(_ notification: Notification) {
            guard let userInfo = notification.userInfo else { return nil }
            self.duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? 0
            self.theCurveAsAnnounced = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? 0
        }

    }

}


/// The two block-based observers on the keyboard, held so that they can be **taken off again** — which nothing did until 2026-08-31.
///
/// A block-based observer is not kept alive by the object it captures; it is kept alive by the **token**, which the notification centre holds until it is handed
/// back. So the `[weak self]` in ``MovesTheMessagesWhenTheSpaceBelowThemChanges/init()`` prevents a retain cycle and does nothing whatever about accumulation.
/// One of those objects exists per discussion screen and is freed when the reader leaves it — proven independently by
/// ``TheGeometryOfTheTranscriptReadPerFrame/stopsReading()``'s own measurement, where a new object could only mean the old one had gone — while its two blocks
/// stayed registered for the life of the process. A session that had opened twenty discussions ran forty dead blocks on every keyboard notification, each of them
/// logging a line through ``MovesTheMessagesWhenTheSpaceBelowThemChanges/saysWhatItDid(_:_:)`` before failing its `weak self` unwrap.
///
/// **A holder of its own, rather than an array and a `deinit` on the rule itself**, and the reason is the isolation rather than taste: the rule is `@MainActor`,
/// a global-actor-isolated class's `deinit` is `nonisolated`, and it may not read an isolated stored property of non-`Sendable` type — *"cannot access property
/// 'theWatchOnTheKeyboard' with a non-Sendable type '[any NSObjectProtocol]' from nonisolated deinit"*. This class is isolated to nothing, so its own `deinit`
/// has no such question to answer, and the rule needs no teardown call: letting go of the holder *is* the teardown.
///
/// It is also what makes the fix checkable without new instrumentation — one keyboard movement should produce **one** *keyboard announced a movement* line,
/// however many discussions the session has been through.
private final class TheWatchOnTheKeyboard {

    private let tokens: [NSObjectProtocol]

    init(_ tokens: [NSObjectProtocol]) {
        self.tokens = tokens
    }

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

}
