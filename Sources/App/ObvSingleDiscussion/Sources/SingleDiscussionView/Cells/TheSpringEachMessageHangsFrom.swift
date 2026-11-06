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
import QuartzCore
import SwiftUI
// TEMPORARY until the scroll-wheel measurement below goes: the state of the scroll view's own pan recogniser.
import UIKit


// MARK: - Notes
//
// **The model is WWDC 2013 session 217's**, *Exploring Scroll Views on iOS 7*. Each message hangs from its anchor by a
// zero-length spring; the anchors travel with the content and the messages resist by an amount proportional to their
// distance from the reader's finger, springing home when the scroll stops.
//
// **It began as a spike on 2026-08-30** and became a setting the next day. Six rounds of tuning went into it, and one
// defect is still outstanding. **Read that defect before changing anything here**: this moves where a
// message is *drawn* while `WhereTheMessagesAre` publishes where it *lays out*, so lifting a message mid-fling puts the
// context menu's copy at the un-offset position.
//
// Switched by `ObvMessengerSettings.Interface.elasticScrolling`, on by default from iOS 27 and off on a Mac, and off entirely under Reduce Motion.

/// Where the transcript's speed and the reader's finger are kept, and **what makes the settle get drawn at all**.
///
/// **This was a lock-protected global read from inside the render closure, and that was wrong in a way only looking
/// could show.** `visualEffect`'s closure re-runs when the geometry it is handed changes — which during a scroll is
/// every frame, and which is why the first version needed no plumbing whatever. The corollary went unstated: **when the
/// content stops moving, nothing re-runs it.** The lag went on decaying where nobody was reading it, and every row
/// stayed frozen at the offset it had on the last moving frame. A gentle scroll re-ran the closures and everything
/// snapped into place, which is exactly how it was reported.
///
/// So the lag is `@Observable` and read in the modifier's `body`. **That is the cost `after-the-first-version.md`
/// predicted** — *the velocity has to be captured from outside, which re-evaluates the modifier every frame even though
/// it does not re-evaluate the cell* — and it is now paid rather than dodged. What re-renders per frame is one small
/// `ViewModifier` body per visible row; what does not is any cell.
///
/// **`@Observable` and not `ObservableObject`**: ``TheGeometryOfTheTranscriptReadPerFrame`` avoids it because the
/// *module's* floor is iOS 16, but this effect is only ever reached through a list that is `#available(iOS 18)`, so 17
/// is guaranteed wherever it runs. The call site in that display link carries the guard.
@available(iOS 17.0, *)
@MainActor @Observable
final class TheSpeedOfTheTranscript {

    /// **One of these per screen, and it used to be a singleton.**
    ///
    /// It was `static let shared` until 2026-09-02, and that is the whole of a defect found on the TestFlight build: a second discussion
    /// pushed on top of a first opened with its last message a little above or below where it belonged, and the error **changed sign when
    /// the two discussions were permuted**. That shape — `something(A) − something(B)` — is what named this object, there being no other
    /// mutable static in the module. ``theContentIsAt(_:)`` keeps one ``whereTheContentWasOnTheLastFrame`` between one producer and one
    /// consumer; with two live screens it was fed by **two** display links, so ``movedThisFrame`` became `offset(D2) − offset(D1)` —
    /// thousands of points across microseconds — the speed saturated, and every band pinned at ``theFurthestAMessageFallsBehind``. A
    /// **drawing** error and not a scroll one, which is why the offset was right and the message still sat off it.
    ///
    /// So it is owned by ``TheGeometryOfTheTranscriptReadPerFrame``, which is the display link that feeds it and is already one per screen.
    /// The reasoning at ``theContentIsAt(_:)``'s call site — that stepping nine springs nobody is watching costs nothing — is still true and
    /// was never the fault: *the object was not merely stepped for nothing, it was fed by two producers*.
    init() {}

    /// **A bank of springs, one per distance from the finger, and the rows read the one that is theirs.**
    ///
    /// This replaced a single scalar scaled per row on 2026-08-30, and the reason is worth keeping because the obvious
    /// version of *per-bubble* would not have fixed anything. **A linear spring settles in a time that does not depend on
    /// how far it starts from home**: a bubble displaced 16pt and one displaced 4pt share a time constant and differ in
    /// arrival only by `τ·ln(4)`, which is precisely what one scalar scaled per row already gives. So giving every bubble
    /// its own spring, all identical, as WWDC 217 describes, would have produced the same spread the reader had just
    /// said was too small.
    ///
    /// What makes a distant message arrive late is a **softer spring**, not a longer journey. So each band carries its
    /// own response, from ``Self.responseUnderTheFinger`` at zero distance to ``Self.responseAWholeScreenAway`` at the far end,
    /// and a row interpolates between the two bands either side of it. That is a deliberate departure from the session's
    /// recipe, in the direction the reader's eye asked for.
    ///
    /// **Nine of them**, which is enough that the interpolation is invisible and few enough that stepping them all costs
    /// nothing: nine springs a frame against ten rows re-rendering anyway.
    private(set) var lagByDistance: [CGFloat] = .init(repeating: 0, count: numberOfBands)

    static let numberOfBands = 9

    /// Where the reader is holding the transcript, in window coordinates — **the point everything else is measured from**.
    ///
    /// Kept from the last frame in which a finger was actually down and used on through the deceleration that follows: a
    /// fling has no grab point of its own, and the one it was released from is the honest anchor for what it does next.
    private(set) var whereTheReaderIsHoldingIt: CGFloat?

    // MARK: - The numbers, arrived at over six rounds on 2026-08-30 and one more on the 31st
    //
    // They were briefly `var`s driven by a tuning panel, which is how they were settled; the panel is gone and they are
    // constants again. Each says which way to turn it and what that costs, because the next person to touch them will
    // be doing it by eye.

    /// The furthest a message is ever drawn from where it lays out, whatever the transcript is doing.
    ///
    /// **Not in WWDC 217's formula at all** — theirs is `scrollDelta × factor` with nothing above it. It exists so an
    /// absurd fling cannot tear the transcript apart, and should therefore sit *above* what an ordinary flick produces
    /// (~30pt in a frame) rather than clipping it, or it is the amplitude control in disguise.
    private static let theFurthestAMessageFallsBehind: CGFloat = 40

    /// Over what distance from the finger a message falls fully behind. **Larger is subtler.** WWDC 217 says 800–1500,
    /// which is iPad-scale: on a phone the furthest *visible* message is only ~400pt from a centred finger, so the
    /// largest factor anything on screen can reach is `halfTheVisibleHeight / this`.
    static let overWhatDistanceAMessageFallsFullyBehind: CGFloat = 450

    /// The spring of a message under the finger. It has no displacement to settle, so this mostly sets how quickly the
    /// messages *near* the finger come home.
    private static let responseUnderTheFinger: CGFloat = 0.20

    /// The spring a whole screen away. **The stagger is the ratio of this to the one above** — equal means everything
    /// arrives together, and much larger means the far messages crawl.
    private static let responseAWholeScreenAway: CGFloat = 0.38

    /// **1.0 is critically damped: no overshoot at all.** Below 1 it bounces, which was tried twice and rejected twice.
    private static let dampingFraction: CGFloat = 1.0

    /// **How far behind a message travels, expressed as time.** A message a whole screen from the finger is drawn where
    /// the content was this many seconds ago; nearer ones a fraction of that.
    ///
    /// **This was `howMuchOfAFramesMovementIsLag`, a fraction of *one frame's* movement, and that was wrong twice
    /// over.** A frame at 60Hz carries about 30pt of a fast fling, so the lag could never exceed ~30pt however high the
    /// cap went — which is why the reader could not get the distant messages to *come from a longer distance* by turning
    /// any knob. And a frame at 120Hz carries half as much, so the whole effect was half as strong on a ProMotion
    /// display: the amplitude was frame-rate dependent while the spring had been carefully normalised to seconds.
    ///
    /// In time, both go away.
    ///
    /// **This is the amplitude at ordinary speeds; ``Self.theFurthestAMessageFallsBehind`` is the amplitude on a hard fling.**
    /// A gentle scroll runs at some 1000pt/s and never reaches the cap, so it is governed entirely by this; a flick runs
    /// at 3000 or more, where `speed × this` exceeds the cap and the cap is the whole of what is seen. Turning one and
    /// not the other changes the effect at one end of the range and leaves the other exactly as it was, which is worth
    /// knowing before wondering why a change did nothing.
    private static let howLongAMessageLagsBehind: CGFloat = 0.022

    /// How long the anchor takes to reach a finger that has just landed somewhere else. Long enough that the change is
    /// a movement rather than a cut, short enough that the first moments of the new drag are still direct.
    private static let howQuicklyTheAnchorFollowsANewTouch: CGFloat = 0.12

    /// Below this much movement in a frame there is nothing to lag behind. Without it the last, jittery frames of a
    /// deceleration drive the springs and the effect moves for no reason.
    private static let leastMovementThatCounts: CGFloat = 1.0



    /// Where the anchor is going, while it is going there. Nil whenever it is already where the finger is.
    private var theAnchorIsTravellingTowards: CGFloat?

    /// Whether every band is at rest, which is what makes an anchor teleport invisible and therefore allowed.
    private var everythingIsHome = true

    /// Each band's own speed, in points per second.
    private var speedByDistance: [CGFloat] = .init(repeating: 0, count: numberOfBands)

    private var whereTheContentWasOnTheLastFrame: CGFloat?
    private var whenTheLastFrameWas: CFTimeInterval?

    // MARK: - TEMPORARY until the wheel is decided on again: the scroll-wheel measurement
    //
    // **The question it was written for has been answered, which is why it carries a condition and the rest of this screen's
    // instruments do not.** The effect was good with a trackpad and bad with a mouse, the explanation on offer being that a notched
    // wheel moves the content a long way in one frame and then not at all for several — so `speed` spikes, `targetAtTheFarEnd`
    // saturates, and the target drops to nought: a kick and a release per notch. This printed the numbers that confirmed it. The
    // answer taken was to remove the effect outright for a wheel rather than to limit it — see ``aWheelHasBeenUsedRecently(_:)``,
    // which is production. So this is kept only against that being revisited, and is the first thing to delete if it is not.

    /// Whether the per-frame line below is wanted, handed over by ``TheGeometryOfTheTranscriptReadPerFrame`` from the setting it
    /// already reads for its own frame report — one switch rather than a second one to forget.
    private var theScrollReportIsAskedFor = false

    /// How many frames in a row the content has not moved at all, since the last line printed. **This is the whole measurement**: a
    /// trackpad should never make this anything but nought, and a wheel between notches should make it several.
    private var framesWithNoMovementAtAll = 0

    /// What the scroll view's own pan recogniser was doing on this frame, kept only so the line below can carry it.
    private var whatThePanWasDoing = ""

    /// Told each frame what the scroll view's own pan recogniser looks like. TEMPORARY, with the report below and on its condition.
    ///
    /// **The pan is worth carrying because it might make the rest unnecessary.** If a wheel and a trackpad put the recogniser into
    /// different states, that is a cleaner test than any arithmetic on the offsets — and `the-elastic-scroll.md` is explicit that
    /// nothing about this recogniser may be assumed, including which scroll types it is allowed to see.
    func theScrollViewsOwnPanIs(_ pan: UIPanGestureRecognizer) {
        #if DEBUG
        guard theScrollReportIsAskedFor else { return }
        whatThePanWasDoing = Self.named(pan.state) + "/\(pan.numberOfTouches)touch/types=\(pan.allowedScrollTypesMask.rawValue)"
        #endif
    }

    /// Said once, when the reading starts, so the per-frame line need not repeat it.
    func reportsEveryScrollingFrame(_ itIsAskedFor: Bool, alongside scrollView: UIScrollView) {
        #if DEBUG
        theScrollReportIsAskedFor = itIsAskedFor
        framesWithNoMovementAtAll = 0
        guard itIsAskedFor else { return }
        // **The default is read off the device rather than off the documentation**, which is what `the-elastic-scroll.md` asks for:
        // whether a bare recogniser sees a wheel at all decides whether the probe it proposes would work at all. A recogniser that
        // is never added to anything is the only honest way to ask, and it cannot disturb the scrolling by construction.
        let bare = UIPanGestureRecognizer()
        let masks = "own=\(scrollView.panGestureRecognizer.allowedScrollTypesMask.rawValue) bare=\(bare.allowedScrollTypesMask.rawValue)"
        let vocabulary = "discrete=\(UIScrollTypeMask.discrete.rawValue) continuous=\(UIScrollTypeMask.continuous.rawValue) all=\(UIScrollTypeMask.all.rawValue)"
        Self.logger.info("the scroll report is ON | allowedScrollTypesMask \(masks, privacy: .public) | \(vocabulary, privacy: .public)")
        #endif
    }


    private static func named(_ state: UIGestureRecognizer.State) -> String {
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


    /// **A new touch moves the anchor gradually; a continuing drag moves it exactly.**
    ///
    /// Setting it outright on a new touch is a discontinuity in every row at once: the factor each message is scaled by
    /// is its distance from this point, so an anchor that teleports from where the reader lifted to where they touched
    /// **inverts the whole displacement pattern in a single frame** — the rows that were furthest become the nearest.
    /// Reported on 2026-08-30 as *the cells freeze for a fraction of a second, then jump a little*, which is that frame
    /// followed by the springs coming home.
    ///
    /// **Only on a new touch.** While a drag continues the anchor must stay exactly under the finger, or the message
    /// being held stops following it, and direct manipulation is the one thing this effect may not spend.
    func theReaderIsHoldingIt(at pointInTheWindow: CGFloat, isANewTouch: Bool) {
        if isANewTouch, whereTheReaderIsHoldingIt != nil, !everythingIsHome {
            theAnchorIsTravellingTowards = pointInTheWindow
        } else {
            theAnchorIsTravellingTowards = nil
            whereTheReaderIsHoldingIt = pointInTheWindow
        }
    }


    /// Told by the display link where the content is, on every presented frame.
    ///
    /// **In seconds, not in frames.** A spring tuned by eye on a 60Hz iPhone would settle twice as fast on a 120Hz Mac
    /// and be a different effect on each — the class of mistake this plan has been caught by before. `dt` is clamped so
    /// that a stalled frame cannot hand the integrator a step large enough to make it explode.
    func theContentIsAt(_ offset: CGFloat) {

        let now = CACurrentMediaTime()
        defer {
            whereTheContentWasOnTheLastFrame = offset
            whenTheLastFrameWas = now
        }

        guard let whereItWas = whereTheContentWasOnTheLastFrame, let whenItWas = whenTheLastFrameWas else { return }

        // **Two numbers, because two different questions are being asked, and for a fortnight there was one.**
        //
        // ``sinceTheLastFrame`` is how long it has actually been. ``dt`` is the longest step the integrator may take, which is
        // ``longestStepTheSpringMayTake`` — finding 14's clamp, there so a slow frame cannot destabilise the spring.
        //
        // The clamped one was being used for **both**, and measuring a speed with it overstates that speed by exactly the ratio of
        // the true interval to the clamp. Measured on Mac Catalyst on 2026-09-01, scrolling with a mouse wheel: 521pt of content
        // over a true 91ms is 5,700pt/s, and it was reported as **20,840pt/s**. On the entry scroll of a discussion it read
        // **396,560pt/s**. `targetAtTheFarEnd` then pinned at its 40pt cap on 46% of moving frames, which is the lurch the reader
        // reported as *bad with a mouse* — and it needed nothing about the mouse to explain it.
        let sinceTheLastFrame = max(0, now - whenItWas)
        guard sinceTheLastFrame > 0 else { return }
        let dt = min(Self.longestStepTheSpringMayTake, sinceTheLastFrame)

        // **The anchor first**, so that this frame's springs and this frame's rendering agree about where the finger is.
        if let travellingTowards = theAnchorIsTravellingTowards, let itIsAt = whereTheReaderIsHoldingIt {
            let howFar = 1 - exp(-CGFloat(dt) / max(0.001, Self.howQuicklyTheAnchorFollowsANewTouch))
            let next = itIsAt + (travellingTowards - itIsAt) * howFar
            if abs(travellingTowards - next) < 1 {
                whereTheReaderIsHoldingIt = travellingTowards
                theAnchorIsTravellingTowards = nil
            } else {
                whereTheReaderIsHoldingIt = next
            }
        }

        let movedThisFrame = offset - whereItWas

        // **Nothing below a point counts as movement**, and without this the effect *moves for no reason*: the last
        // stretch of a deceleration delivers a jitter of fractions of a point per frame, and a spring driven by that
        // noise rings on its own. A slit-scan of a recording on 2026-08-30 showed exactly that — the settled bands
        // undulating rather than going flat.
        let stillEnough = abs(movedThisFrame) < Self.leastMovementThatCounts

        // **The sign, which was inverted for four rounds and is the whole reason this felt strange.** A message that has
        // not caught up is drawn where it *was*, so its offset has the **same sign as the content's movement**, not the
        // opposite: `contentOffset` rising means the content travels up the screen, and a row left behind is therefore
        // drawn *lower* — a positive `offset(y:)`. Written with a minus here, every message **led** the scroll instead of
        // trailing it, and finished its journey moving the wrong way. The reader found it by watching what the far cells
        // do at the end: *on iMessage the cells finish their movement by going downwards, as if they were late.*
        //
        // **WWDC 217 warns about exactly this** — *Apple's own demo had a min/max sign bug here; the lag must always
        // oppose the scroll, never amplify it* — and that warning was copied into this file two rounds before the bug it
        // describes was noticed. A comment is not a test.
        //
        // The clamp below is the other half of the same warning, and it is symmetric, so it survived the correction: a
        // message may never be displaced further than the content moved.
        // **From the speed, not from the frame.** `movedThisFrame / dt` is points per second, and multiplying by a time
        // gives points — so the amplitude no longer halves on a display that presents twice as often, and it is no
        // longer bounded by what one frame happens to carry.
        // **From the true interval and never from the clamped one** — see the two numbers at the top of this method for what that cost.
        let speed = movedThisFrame / CGFloat(sinceTheLastFrame)
        let wanted = speed * Self.howLongAMessageLagsBehind

        noticesWhetherTheClockCanKeepUp(sinceTheLastFrame)

        // **The cap is now the only limit, and it therefore matters.** WWDC 217's *never move further than the content
        // did* is about the increment a frame adds, which a spring chasing a target satisfies by construction; applying
        // it to the total was what stopped a distant message ever coming from further than a single frame's travel.
        // **Three reasons to draw no lag, and they are different questions.** Nothing moved; a wheel is in use, which is the reader's
        // preference; or the clock is too slow to draw the thing at all. All three take the same *route* — the target goes to nought
        // and each spring settles on its own response — because standing down may never be a switch.
        let aWheelIsInUse = aWheelHasBeenUsedRecently(now)
        let thereIsNothingToLagBehind = stillEnough || aWheelIsInUse || theClockIsTooSlowToDrawTheEffect
        let targetAtTheFarEnd = thereIsNothingToLagBehind ? 0 : max(-Self.theFurthestAMessageFallsBehind, min(Self.theFurthestAMessageFallsBehind, wanted))

        var everyBandIsHome = true
        for band in 0..<Self.numberOfBands {

            let howFarOut = CGFloat(band) / CGFloat(Self.numberOfBands - 1)
            let target = targetAtTheFarEnd * howFarOut
            let response = Self.responseUnderTheFinger + (Self.responseAWholeScreenAway - Self.responseUnderTheFinger) * howFarOut
            let naturalFrequency = 2 * .pi / response

            let stiffness = naturalFrequency * naturalFrequency
            let damping = 2 * Self.dampingFraction * naturalFrequency
            speedByDistance[band] += (stiffness * (target - lagByDistance[band]) - damping * speedByDistance[band]) * dt

            // **The state cannot be trusted to stay finite, so it is checked rather than assumed.**
            //
            // This is an explicit integrator, and its stability depends on the step — see ``longestStepTheSpringMayTake``, which is now inside the limit. It was
            // not always, and the consequence is not a wobble: with the dominant eigenvalue past 1 the lag grows geometrically, reaches `±inf`, and the very
            // next frame computes `stiffness * (target − inf)` and then `inf + (−inf)`, which is **NaN**. From there it never recovers — NaN propagates through
            // `+=`, and the *arrived* test below is `abs(next) < …`, which is **false for NaN**, so the band never comes home. Every visible row is then handed
            // `offset(y: NaN)`, and the app dies in `CALayer.setPosition` the next time SwiftUI updates a clip shape.
            //
            // Which is a crash seen once on Mac Catalyst on 2026-09-01, in `MaskLayer.update(layer:clip:transform:)` during a `List` update, and never
            // reproduced. This was not proven to be its cause. It is written this way so that it cannot be: a band that goes non-finite is put home and says so,
            // and if that crash is ever seen again the log will have ruled this out instead of leaving it a suspect.
            guard speedByDistance[band].isFinite else {
                Self.logger.fault("The spring's speed for band \(band) is not finite. Putting the band home.")
                assertionFailure()
                speedByDistance[band] = 0
                lagByDistance[band] = 0
                continue
            }

            // **Clamped, and to the amplitude this effect is allowed anyway.** `target` was clamped from the first version and the state never was, which is
            // what let a bad frame compound. A message may not be displaced further than ``theFurthestAMessageFallsBehind`` however it got there, so nothing is
            // lost by saying so here — and a step that is somehow too long can no longer do more than saturate.
            let next = min(Self.theFurthestAMessageFallsBehind, max(-Self.theFurthestAMessageFallsBehind, lagByDistance[band] + speedByDistance[band] * dt))

            // **Arrived**, and said so exactly — the position *and* the speed. A value asymptotically approaching zero
            // would re-render every visible row's modifier for the rest of the session; a zero-length spring must be
            // pixel-exact at rest.
            if abs(next) < Self.closeEnoughToHome, abs(speedByDistance[band]) < Self.slowEnoughToBeStopped, abs(target) < Self.closeEnoughToHome {
                speedByDistance[band] = 0
                if lagByDistance[band] != 0 { lagByDistance[band] = 0 }
            } else {
                lagByDistance[band] = next
                everyBandIsHome = false
            }

        }
        everythingIsHome = everyBandIsHome

        reportsThisScrollingFrame(moved: movedThisFrame, sinceTheLastFrame: sinceTheLastFrame, dt: dt, speed: speed, wanted: wanted,
                                  target: targetAtTheFarEnd, stillEnough: stillEnough)

    }


    /// **TEMPORARY, on the condition at the MARK above.** One line per frame in which the content moved, carrying the count of frames it did not move for in between.
    ///
    /// Printed at the end of the step rather than at the start, so it can carry the far band's answer for *this* frame: the kick and
    /// the release are supposed to be visible in that number, and a line reporting the target without its effect would leave the
    /// interesting half out.
    ///
    /// **A frame in which nothing moved prints nothing and is counted instead.** That is not to keep the log short — `still=` is the
    /// measurement. A stream of small movements with `still=0` throughout is a continuous scroll; one large movement followed by
    /// `still=6` is a notch. If the two devices cannot be told apart by it, the heuristic the plan proposes is dead, and that is
    /// worth knowing before it is built rather than after.
    private func reportsThisScrollingFrame(moved: CGFloat, sinceTheLastFrame: CFTimeInterval, dt: CFTimeInterval, speed: CGFloat,
                                          wanted: CGFloat, target: CGFloat, stillEnough: Bool) {

        // **`#if DEBUG` as well as the setting** — decided 2026-09-01 before the TestFlight merge, and the trade is written out at
        // ``TheGeometryOfTheTranscriptReadPerFrame/reportsThisFrame(_:_:)``: nothing extra ships, at the cost of a jank report from TestFlight no longer
        // being answerable from a log. Everything handed in is a scalar the step above computed anyway, so the call site builds nothing to discard.
        #if DEBUG

        guard theScrollReportIsAskedFor else { return }

        guard moved != 0 else {
            framesWithNoMovementAtAll += 1
            return
        }

        let still = framesWithNoMovementAtAll
        framesWithNoMovementAtAll = 0

        let capped = abs(wanted) > Self.theFurthestAMessageFallsBehind ? " CAPPED" : ""
        // **The decision, and the two things it turns on, side by side.** A guard that refuses in silence cannot be told
        // apart from a case that never arose, and the precondition has to be in the log next to the outcome or it gets assumed.
        let line = String(format: "moved=%+.1f since=%.1fms dt=%.1fms still=%d speed=%.0fpt/s wanted=%+.1f target=%+.1f%@ far=%+.2f%@%@",
                          moved, sinceTheLastFrame * 1000, dt * 1000, still, speed, wanted, target, capped,
                          lagByDistance[Self.numberOfBands - 1],
                          stillEnough ? " [below the noise floor]" : "",
                          aWheelHasBeenUsedRecently(CACurrentMediaTime()) ? " STOOD DOWN, a wheel is in use"
                            : (theClockIsTooSlowToDrawTheEffect ? " STOOD DOWN, the clock cannot keep up" : ""))

        Self.logger.info("\(line, privacy: .public) | pan \(self.whatThePanWasDoing, privacy: .public)")

        #endif

    }


    // MARK: - Standing down for a scroll wheel

    /// When a **discrete** scroll — a notched wheel — last moved this transcript, or nil if none has.
    ///
    /// **The reader's preference, asked for on 2026-09-01 having walked the alternative**: the clock-based stand-down below made a
    /// wheel much better and *"I prefer the no-effect situation"* was still the answer. So a wheel now removes the effect outright
    /// rather than merely limiting it.
    ///
    /// **Per scroll event and not per connected device**, which is both what was asked for — *"keep it when it's a trackpad"* — and
    /// the only version that can be built honestly: Catalyst has no dependable way to ask whether a pointing device is a mouse or a
    /// trackpad, where UIKit will say whether a *scroll* was discrete. On a Mac with both, the trackpad keeps the effect.
    private var whenAWheelWasLastUsed: CFTimeInterval?

    /// Said by ``TheProbeThatNoticesAWheel`` every time UIKit asks it whether to begin, whatever the answer.
    ///
    /// **A finger is not a wheel, and that is the second of the probe's two refusals** — the first being `allowedTouchTypes`, which is
    /// documented to keep touches away and was trusted alone for one walk. A scroll event carries no touches; a drag carries at least
    /// one. Measured on the Mac: the scroll view's own pan reported `0touch` on every frame of a wheel scroll.
    ///
    /// **Both outcomes are reported, under the report's one gate.** The version that tested the count inside the probe and logged
    /// nothing is what let the effect vanish from an iPhone 13 with no way to tell *a wheel was wrongly recorded* from *the clock stood
    /// the effect down*, which are different bugs with different answers.
    func theWheelProbeWasAsked(withTouches touches: Int) {
        let itIsAWheel = touches == 0
        if itIsAWheel {
            whenAWheelWasLastUsed = CACurrentMediaTime()
        }
        // **Only the line is guarded.** The recording above it is production behaviour — it is how the effect stands down for a wheel — and the two must
        // not be confused when this instrument comes out: see the issue for the removal, which says so in as many words.
        #if DEBUG
        guard theScrollReportIsAskedFor else { return }
        Self.logger.info("the wheel probe was asked with \(touches, privacy: .public) touches — \(itIsAWheel ? "RECORDED as a wheel" : "refused, this is a finger", privacy: .public)")
        #endif
    }

    /// **Remembered rather than answered per event**, because the two ends are not in step: the probe hears about a notch when the
    /// event arrives, and this is asked on the next presented frame. A window also decides the right thing when a reader switches
    /// device mid-discussion — a few seconds after the last notch the effect comes back for the trackpad, with nothing to reset.
    private func aWheelHasBeenUsedRecently(_ now: CFTimeInterval) -> Bool {
        guard let whenAWheelWasLastUsed else { return false }
        return now - whenAWheelWasLastUsed < Self.howLongAWheelIsRememberedFor
    }

    /// Long enough to cover the gap between notches of a slow, deliberate scroll — measured at 300 to 900ms on 2026-09-01 — and short
    /// enough that a reader who puts the mouse down and uses the trackpad has the effect back within a gesture or two.
    private static let howLongAWheelIsRememberedFor: CFTimeInterval = 3


    // MARK: - Standing down when the clock cannot keep up

    /// Whether the effect is currently standing aside because frames are arriving too far apart to draw it.
    ///
    /// **On the clock, and deliberately not on the input device.** The plan for this was to detect a *discrete* scroll with a
    /// `UIPanGestureRecognizer` whose `allowedScrollTypesMask` is `.discrete`, on the reasoning that a notched wheel moves the
    /// content a long way in one frame and then not at all. Measured on Mac Catalyst on 2026-09-01, that is not what happens: 53 of
    /// 113 moving frames during a wheel scroll had **no gap at all** before them, so there are no notches to count. What there is
    /// instead is a starved clock — an idle tick every **18.0ms** against **93ms median, 304ms at worst** while the wheel scrolls,
    /// which is 11Hz, and 3Hz at its worst.
    ///
    /// At that rate a spring of ``responseUnderTheFinger`` gets three to six steps in its whole life. **There is no smooth motion
    /// available to draw, whatever moved the content**, so the honest thing is to stand aside and let the springs come home.
    ///
    /// Three things this buys over asking the device. It needs no recogniser — and the one the plan proposed would have been
    /// **silent**: a fresh `UIPanGestureRecognizer` reports `allowedScrollTypesMask == 0` on this Mac, seeing no scroll events at
    /// all until somebody remembers to set it. It treats a notchy third-party wheel and a Magic Mouse by what they do rather than by
    /// what they are. And it covers an iPhone whose main thread is busy for a moment, which no scroll-type test would ever see.
    ///
    /// **The threshold is ``longestStepTheSpringMayTake`` and not a number of its own.** That constant already says how long a step
    /// the integrator may honestly take; a frame longer than it is one the spring cannot be stepped through, which is the same
    /// statement. Nothing new to tune, and it moves if that ever does.
    private var theClockIsTooSlowToDrawTheEffect = false

    private var framesInARowTheClockFellBehind = 0
    private var framesInARowTheClockKeptUp = 0

    /// **Not on the strength of one frame, in either direction.** A single late frame happens on any platform and standing the effect
    /// down for it would make the whole thing flicker; coming back the moment one frame is quick would chatter between the two states
    /// for the length of a scroll. So it takes two late frames to stand down and a clear run to come back.
    ///
    /// **Standing down is not a switch**, which is why nothing here touches ``lagByDistance``: zeroing it would snap every message
    /// home in one frame, visibly. What the caller does with this is force the target to nought and let each spring settle on its own
    /// response — the same path a transcript at rest already takes.
    private func noticesWhetherTheClockCanKeepUp(_ sinceTheLastFrame: CFTimeInterval) {

        if sinceTheLastFrame > Self.longestStepTheSpringMayTake {
            framesInARowTheClockKeptUp = 0
            framesInARowTheClockFellBehind += 1
            if framesInARowTheClockFellBehind >= Self.lateFramesBeforeTheEffectStandsAside {
                theClockIsTooSlowToDrawTheEffect = true
            }
        } else {
            framesInARowTheClockFellBehind = 0
            framesInARowTheClockKeptUp += 1
            if framesInARowTheClockKeptUp >= Self.promptFramesBeforeItComesBack {
                theClockIsTooSlowToDrawTheEffect = false
            }
        }

    }

    /// Two, so a single hiccup is not an event.
    private static let lateFramesBeforeTheEffectStandsAside = 2

    /// Ten, which is about a sixth of a second at 60Hz — long enough that the answer is a state of the screen rather than a moment of
    /// it, and short enough that a reader who stops using the wheel gets the effect back within one gesture.
    private static let promptFramesBeforeItComesBack = 10

    /// **Below the stability limit of the integrator below, which `1/30` was not.**
    ///
    /// Semi-implicit Euler on a critically damped spring is stable while `ω·dt < 2√2 − 2 ≈ 0.828`, i.e. `dt < 0.132·response`. The shortest response is
    /// ``responseUnderTheFinger`` at 0.20s, which puts the limit at 26.4ms — where `1/30` permitted 33.3ms. Past it the dominant eigenvalue exceeds 1 in
    /// magnitude *and is negative*, so a slow frame amplifies the lag and flips its sign, and a run of them grows it geometrically.
    ///
    /// Nothing bounded that growth: only `target` was clamped, never the state. See the clamp and the finiteness guard in the loop above for the other two
    /// halves of this, and why they are worth having even now the step is inside the limit.
    private static let longestStepTheSpringMayTake: CFTimeInterval = 1.0 / 40

    /// The finiteness guard in the loop, which must never be taken — and, TEMPORARILY, the scroll-wheel measurement, which logs at
    /// `.info` and therefore needs `--info` on `log show` or `log stream`. The guard is a `.fault` and will be seen either way.
    private static let logger = Logger(subsystem: "io.olvid.messenger", category: "TheSpringEachMessageHangsFrom")

    /// Half a point, which is below what any screen can draw.
    private static let closeEnoughToHome: CGFloat = 0.5

    /// Half a point a second.
    private static let slowEnoughToBeStopped: CGFloat = 0.5

}


/// Draws a **whole message** a little behind where it lays out, by an amount that grows with the transcript's speed and
/// with the message's distance from the reader's finger — so the discussion trails as it moves and settles when it
/// stops.
///
/// **A message is rigid and the spring is between messages.** This goes on the row, not on the bubble: the bubble, the
/// date line under it, the reactions chip and any attachments keep every distance between them, whatever the transcript
/// is doing. Applied to the bubble alone — which is where it was first put — a message springs against its own date,
/// which is not the effect at all.
///
/// **Everything is measured from the finger, and that is what makes it feel caused.** The message under the reader's
/// finger is drawn exactly where it lays out — it *is* what they are holding, so it must follow them perfectly and stop
/// dead when they stop. Every other message lags by an amount growing with its distance from that point, in the **same**
/// direction as each other: opposite the motion, because a row that has not caught up is behind.
///
/// **This replaced a signed position about the middle of the screen**, which put rows above and below the centre moving
/// *opposite ways* — a stretch about a point with no physical meaning, and why the first version read as unrelated to
/// what the reader was doing.
///
/// **`offset` and not `scaleEffect`, and nothing after it.** A `scaleEffect` written after an
/// `offset` resolves its anchor against the un-offset position.
@available(iOS 17.0, *)
struct TheSpringEachMessageHangsFrom: ViewModifier {

    /// **This screen's springs, handed in rather than reached for.** One of these per discussion; see ``TheSpeedOfTheTranscript``
    /// for what one between two of them cost.
    ///
    /// Handed down as a parameter and **not put in the environment**, which is what the plan of record suggested. The two settings beside
    /// it travel that way, but they are `Bool`s: this is a type that does not exist below iOS 17, so an environment key for it would have
    /// to be optional, and a missing instance would then draw *nothing* in silence — the failure this screen has been caught by more often
    /// than any other. A parameter cannot go missing, and ``TheMessageHangsFromASpringIfAsked`` is already the availability gate.
    let theSpeed: TheSpeedOfTheTranscript

    func body(content: Content) -> some View {
        // **Read here and not inside the closure**, for the reason ``TheColourOfABubbleAsItTravels`` reads its own
        // amounts here: the closure a `visualEffect` takes is `Sendable`, and this is main-actor state. Reading it in
        // this body is also what subscribes this modifier to it, which is the whole of how the settle gets drawn.
        let lagByDistance = theSpeed.lagByDistance
        let grabbedAt = theSpeed.whereTheReaderIsHoldingIt
        // Read here with the others, and for the same reason: the closure below is `Sendable` and this is main-actor
        // state. Reading it here is also what re-renders this modifier when the panel turns the knob.
        let overWhatDistance = TheSpeedOfTheTranscript.overWhatDistanceAMessageFallsFullyBehind
        return content
            .visualEffect { shape, geometry in
                let howFarOut = Self.howFarFromTheFinger(geometry, whereTheReaderIsHoldingIt: grabbedAt, overWhatDistance: overWhatDistance)
                return shape.offset(y: Self.lag(at: howFarOut, among: lagByDistance))
            }
    }


    /// How far this message is from the reader's finger: **0 under it, 1 at ``Self.overWhatDistanceAMessageFallsFullyBehind``
    /// or more**. Never negative — every message lags the same way, and only by how much does it differ.
    ///
    /// **The denominator is the subtlety control, and it was three times too small.** WWDC 217 gives 800–1500pt; the
    /// first two rounds of this spike normalised by *half the visible height*, about 400pt on an iPhone 13, so a message
    /// half a screen from the finger was fully behind where Apple would have it a quarter behind. That, with the
    /// exaggerated amplitude, is most of why those rounds read as too much.
    ///
    /// **The middle of the screen is the fallback and it is a poor one**, used only before the transcript has ever been
    /// touched — a scroll wheel and a Catalyst two-finger swipe drive the content with no finger anywhere, and there the
    /// effect has no anchor it can defend. What to do there is a question this spike raises rather than answers.
    /// **Everything here is in the window's space**, which is the one thing this function has to get right and did not.
    ///
    /// `whereTheReaderIsHoldingIt` is recorded from `theReaderIsHoldingIt(at pointInTheWindow:)`, and the row is read with `frame(in: .global)`, so those two
    /// agree. `bounds(of:)` does **not**: it is documented as the other view's bounds *converted to this view's local space*, so its `midY` was being subtracted
    /// from a window coordinate — leaving the fallback anchor out by this row's own global origin, which is to say by an amount that grows the further down the
    /// transcript the row is. Adding that origin back is the conversion, a local Y of nought being the row's own top.
    ///
    /// It is only the fallback, so the effect is right whenever a finger has touched the transcript, and wrong before that — which is a scroll wheel, and a
    /// Catalyst two-finger swipe, and therefore the whole of the Mac.
    nonisolated private static func howFarFromTheFinger(_ geometry: GeometryProxy, whereTheReaderIsHoldingIt: CGFloat?, overWhatDistance: CGFloat) -> Double {
        guard overWhatDistance > 0 else { return 0 }
        let thisRowInTheWindow = geometry.frame(in: .global)
        let theAnchor: CGFloat
        if let whereTheReaderIsHoldingIt {
            theAnchor = whereTheReaderIsHoldingIt
        } else if let theVisibleArea = geometry.bounds(of: .scrollView) {
            theAnchor = theVisibleArea.midY + thisRowInTheWindow.minY
        } else {
            theAnchor = Self.assumedMiddleOfTheVisibleArea
        }
        let fromTheAnchor = abs(thisRowInTheWindow.midY - theAnchor) / overWhatDistance
        return min(1, fromTheAnchor)
    }

    /// **WWDC 217's own range is 800–1500, larger being subtler — and on a phone the low end of it is already very
    /// quiet.** The visible area of an iPhone 13 is about 800pt, so with the finger in the middle of the screen the
    /// furthest *visible* message is only 400pt away: at 1000 that is a factor of 0.4, and against any sensible cap it
    /// comes to a couple of points. Their range was given for iPad-sized content, where 1500pt of separation exists to
    /// be had.
    ///
    /// `nonisolated` because the only thing that reads it is the `Sendable` closure of a `visualEffect`, as with everything else that closure touches. Safe to
    /// give: an immutable `CGFloat`.
    nonisolated private static let assumedMiddleOfTheVisibleArea: CGFloat = 400


    /// This message's own lag, read from the bank of springs and **interpolated between the two bands either side of
    /// it** — without which nine springs would show as nine visible steps as a message travels away from the finger.
    ///
    /// Arithmetic on an array of nine, in a closure asked for every visible message on every presented frame. Nothing
    /// here may be more expensive than that.
    nonisolated private static func lag(at howFarOut: Double, among lagByDistance: [CGFloat]) -> CGFloat {
        guard lagByDistance.count > 1 else { return lagByDistance.first ?? 0 }
        let position = max(0, min(1, howFarOut)) * Double(lagByDistance.count - 1)
        let below = Int(position)
        guard below < lagByDistance.count - 1 else { return lagByDistance[lagByDistance.count - 1] }
        let howFarBetweenThem = CGFloat(position - Double(below))
        return lagByDistance[below] + (lagByDistance[below + 1] - lagByDistance[below]) * howFarBetweenThem
    }

}


extension EnvironmentValues {

    /// Whether the messages lag behind the scroll — `ObvMessengerSettings.Interface.elasticScrolling`, read by the app and
    /// handed down through ``SingleDiscussionView/InitialValues``, exactly as the colour effect's own flag is.
    ///
    /// In the environment rather than in a cell's model for the reason the colour's is: a model is `NSCache`d per message,
    /// and this is a property of the screen rather than of any message on it.
    var elasticScrolling: Bool {
        get { self[ElasticScrollingKey.self] }
        set { self[ElasticScrollingKey.self] = newValue }
    }

}


private struct ElasticScrollingKey: EnvironmentKey {
    /// **`true`, unlike the colour's default of `false`**, and the difference is deliberate: this is on in production, so a
    /// preview or a test that says nothing should get what a reader gets.
    static let defaultValue: Bool = true
}


/// Applies ``TheSpringEachMessageHangsFrom``, or nothing whatever — the shape ``TheColourTravelsIfAsked`` already has, so
/// that with the setting off there is **no** `visualEffect` in the render tree at all.
@available(iOS 17.0, *)
struct TheMessageHangsFromASpringIfAsked: ViewModifier {

    let asked: Bool

    /// **This screen's springs.** Carried through this gate rather than reached for as a singleton; see ``TheSpeedOfTheTranscript``.
    ///
    /// **The availability lives on this type now, where it used to be a condition inside ``body``.** That costs nothing — the only thing that
    /// applies this modifier is ``SingleDiscussionCellsListView``, which is `@available(iOS 18.0, *)` outright — and it buys the parameter above
    /// its real type, so no call site has to erase one and no branch can silently fail to find it.
    let theSpeed: TheSpeedOfTheTranscript

    /// **Off entirely for a reader who has asked for less movement.** An effect whose whole content is movement has
    /// nothing to offer them, and WWDC 217's own advice and the parked entry both say so.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if asked, !reduceMotion {
            content.modifier(TheSpringEachMessageHangsFrom(theSpeed: theSpeed))
        } else {
            content
        }
    }

}
