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

import ObvAppCoreConstants
import OSLog
import SwiftUI
import SwiftUIIntrospect
import UIKit


/// Answers, every frame, the questions this screen asks of where the transcript is.
///
/// **What it replaces.** Three of the four `onScrollGeometryChange` on this screen derive a value and write a `@State` with it, and **none of them moves
/// anything**: a gate that decides whether an arriving message is followed, the band a row measures itself against, and whether a button is offered. Reading
/// the geometry per frame instead of being told costs **one frame** — 58 measurements of 59, 8.3ms at 120Hz. For a gate, a band and a button that is not a
/// cost at all, which is why they moved before the rule that writes the offset.
///
/// **The answers are published, never the geometry.** A tick that writes state every frame re-evaluates the body every frame, and this screen's `ForEach`
/// builds every row view when its data changes. So the geometry read on each frame stays private, the three answers are derived here, and a property is
/// written **only when its answer changes** — which is what `onScrollGeometryChange(for: Bool.self)` does internally.
///
/// **Two of them are also written from outside, deliberately.** Opening a discussion knows things the geometry will not report for another frame or two:
/// that the list has just been sent to the end, so the reader *is* at the end, and that the way back is not worth offering. Both are
/// ``theDiscussionHasOpenedOnItsEnd()`` and nothing else — the same two writes, named, in the one place that holds the values.
///
/// **`ObservableObject` and not `@Observable`.** `@Observable` is iOS 17 and this class is not gated: the screen is iOS 18, but the clock runs on every
/// version the module supports, whose floor is **16**. Its notification is coarser, per object rather than per property, so **nothing large may observe it**:
/// the list holds it without observing it, and only small views that draw or react to an answer observe it — see
/// ``SingleDiscussionCellsListView/theHolderOfTheGeometry``.
@MainActor
final class TheGeometryOfTheTranscriptReadPerFrame: ObservableObject {

    /// Whether the reader is close enough to the end that a message they *receive* should bring the end back — Step 44b's gate, at 44c's
    /// tolerance.
    ///
    /// **Read before an arrival lands**, which a per-frame reading gives by construction rather than by care: the frame this was derived from
    /// is the last one *presented*, and a row that has just been inserted has not been presented yet.
    @Published private(set) var theReaderIsAtTheEndOfTheDiscussion = true

    /// Whether the end is far enough below what the reader can see for the way back to be worth offering — half a screen, which is legacy's
    /// own threshold measured from the *top* of the viewport.
    @Published private(set) var theEndIsFarBelowWhatTheReaderCanSee = false

    /// Where, in the list's own coordinate space, a row has to be for the reader to be able to read it.
    ///
    /// **Nothing until the first frame has been read**, so nothing counts as seen before the list has been laid out — which is right: a row
    /// cannot have been read before the screen it is on exists.
    ///
    /// Optional rather than an empty range, which is what this was and which never worked: a `ClosedRange` **is never empty** — `isEmpty` is
    /// `false` by construction, a closed range always holding at least its bound — so the guard reading it was dead code and the `0...0` it
    /// was meant to catch was tested as a real band. What that did was invert the answer at the one moment it is asked most: every row the
    /// reader could actually see reported *not seen*, and the single row straddling `y == 0` — behind the navigation bar, the one place they
    /// cannot see — reported *seen* and was marked read. `nil` makes the absence a case the compiler insists on.
    @Published private(set) var visibleAreaOfTheList: ClosedRange<CGFloat>?

    /// Whether the reader has hold of the transcript — under their finger, or still coasting after it, and legacy's `lastScrollWasManual`.
    ///
    /// **Nothing may be asked of the scroll view while this is true.** Dragging the messages down to dismiss the keyboard makes the bottom inset
    /// shrink about thirty times while the keyboard follows the finger, and answering each of those looked like the messages being snapped to the
    /// end the moment the keyboard began to move. The finger is already moving the messages; there is nothing to correct.
    ///
    /// **Read here rather than from `onScrollPhaseChange`**, which is the fifth and last of the iOS 18 APIs this screen was held by. The three
    /// scroll-view flags map onto its three interesting phases exactly — `isTracking` to `.tracking`, `isDragging` to `.interacting`,
    /// `isDecelerating` to `.decelerating` — and its `.animating` is deliberately excluded by both, that state being *this screen's own* scrolling,
    /// which the rules below have to be allowed to correct while it runs.
    @Published private(set) var isUnderTheReadersFinger = false

    /// How close to the end the reader has to be for a message they *received* to bring the end back.
    ///
    /// **Sixty points, which is the legacy screen's number and not a guess.** `evaluateIfScrollOnNewIncomingMessageShouldBeActive()` computes
    /// `contentSize.height + adjustedContentInset.bottom - (contentOffset.y + frame.size.height)` and compares it against `60.0` — that
    /// expression is ``TheGeometryOfTheTranscript/pointsBelowTheVisibleArea`` term for term.
    ///
    /// It is under half a message, so what it means in practice is *the last message is on screen*. Scroll back by one message and an arrival
    /// no longer takes the reader away from what they were reading.
    ///
    /// **Verified at the boundary on 2026-08-22**, which is what 44f-1 owed: followed at 46.0, 50.7 and 58.3, declined at 70.0, 82.0 and 95.0,
    /// with no inversion across nine arrivals.
    private static let closeEnoughToTheEndToBeFollowed: CGFloat = 60

    /// How far the reader has to be from the end before the way back is offered — **half a screen below what they can see**, which is the
    /// legacy rule in this screen's own terms.
    ///
    /// Legacy compares the *offset* against `contentHeight - 1.5 × pageHeight`, so what its 1.5 screens describe is the **top** of the
    /// viewport, and the button appears once the bottom of the viewport is half a screen above the end of the content. Restated against
    /// ``TheGeometryOfTheTranscript/pointsBelowTheVisibleArea``, that is this constant — and it takes the bottom inset into account, which
    /// legacy's version quietly does not (there is a commented-out `- adjustedContentInset.top` in `configureScrollToBottomButton()` where
    /// somebody wondered).
    ///
    /// **Not the gate above.** That is the neighbouring question and the wrong one here: it turns over within a few points of the end, so the
    /// button would blink in and out on a flick at the end of a discussion. This one is deliberately half a screen coarser.
    private static let screensBelowTheVisibleAreaBeforeTheWayBackIsOffered: CGFloat = 0.5

    private weak var scrollView: UIScrollView?
    private var displayLink: CADisplayLink?

    /// The `List`'s own collection view, for the list to scroll to a row by its index path — see
    /// `SingleDiscussionCellsListView.scrolls(to:anchor:animated:using:)`. Nil until the geometry has started reading.
    var theCollectionView: UICollectionView? { scrollView as? UICollectionView }

    /// **This screen's elastic-scroll springs, owned here because this is what feeds them.**
    ///
    /// It was `TheSpeedOfTheTranscript.shared` until 2026-09-02, and one bank between two live screens is the whole of a defect: two display
    /// links calling ``TheSpeedOfTheTranscript/theContentIsAt(_:)`` against one remembered offset made the frame-to-frame delta
    /// `offset(D2) − offset(D1)`, so a second discussion pushed on a first drew its messages off where they belonged — by an amount that
    /// **changed sign when the two were permuted**. Owned by this object rather than by the view because this object *is* the producer: one
    /// display link, one bank, and a delta that means what it says.
    ///
    /// **Held as `AnyObject` because the type does not exist below iOS 17 and this class's floor is the module's, iOS 16.** A stored property
    /// cannot carry an availability attribute, so the erasure lives here, in this one place, and ``theSpeedOfThisTranscript`` is what everything
    /// else uses. Every call site that reads it already stood inside an `#available` guard for its own reasons, so nothing else moves.
    private var theSpeedOfThisTranscriptErased: AnyObject?

    /// ``theSpeedOfThisTranscriptErased``, under its real name and made on first use.
    ///
    /// **Made lazily rather than in `init`** for the reason the storage is erased at all: `init` is not an `#available` context either. A screen
    /// that never reaches iOS 17 never makes one.
    @available(iOS 17.0, *)
    var theSpeedOfThisTranscript: TheSpeedOfTheTranscript {
        if let alreadyMade = theSpeedOfThisTranscriptErased as? TheSpeedOfTheTranscript { return alreadyMade }
        let made = TheSpeedOfTheTranscript()
        theSpeedOfThisTranscriptErased = made
        return made
    }

    /// A scroll **this screen asked for** that is still moving the transcript, if there is one.
    ///
    /// The sibling of ``isUnderTheReadersFinger``, and it exists for the identical reason: something else is already moving the content, so there is
    /// nothing for the rule below to correct. The finger was the obvious half of that sentence and this is the other half, which took until Step 46g's
    /// walk to be noticed because it fails so much more quietly.
    private var theScrollOfOurOwn: TheScrollOfOurOwn?

    /// Whether the next change of the space below must have its geometry checked **strictly**, a scroll of our own having just finished.
    ///
    /// **This is the whole point of the mechanism, and the in-flight half alone would not do.** `onScrollGeometryChange` does not observe a
    /// `ScrollViewProxy.scrollTo` at all, so the `asItWas` it hands the rule is not the previous frame — it is *the last time the action ran*, which is
    /// before the scroll started. The first change of the space below **after** the scroll is therefore answered from a geometry that may predate it,
    /// and 46k's bound cannot see it once the scroll is short: measured on 2026-08-24, a reply sent from the end left `asItWas.offset` 96pt stale
    /// against a bound of 110, and the rule pulled the reader 166pt off the end and left them there.
    ///
    /// **It asks for agreement, not for a stand-down, and the first version of this got that wrong.** Refusing the first change outright looks safe and
    /// is not: the first change after a scroll is usually the one that matters — a reply quote appearing, the first line of a draft — so a blunt refusal
    /// left the last message behind the composition bar when Reply was tapped, and left a multi-line draft twenty points short because only its *first*
    /// line went unanswered. Both were measured within a minute of shipping it. What separates the fault from those is not that a scroll happened but
    /// that the geometry **disagrees with the scroll view**: the fault reads `was=66433 live=66529`, the healthy cases read `was=62099 live=62099`, to
    /// the point. So this tightens the test rather than skipping it.
    private var theGeometryMustAgreeExactly = false


    /// What a scroll of our own is doing, watched frame by frame.
    ///
    /// **A stillness test alone cannot end it** — no state of a scroll view distinguishes *has not begun* from *has
    /// finished*, so a naive one answers immediately and the flag drops before the scroll has moved a point. Hence `hasBegunMoving`: stillness only
    /// counts once movement has been seen.
    ///
    /// **And a fixed wait is a race**, which is why the frame count below is a backstop for the one case stillness cannot cover — a scroll to a row
    /// already on screen, which moves nothing at all and would otherwise leave this standing for ever — and not the way an ordinary scroll ends.
    /// Where a scroll of our own is taking the reader — **the one thing about it that Step 57 needs to know**.
    ///
    /// It exists because *the reader was at the end* is a belief that only a **finger** used to be able to overturn, and a jump is not a finger. Tapping the
    /// quote inside a reply, after sending that reply from the end, took the reader 18,084pt up the discussion and `putsTheReaderBackAtTheEnd` brought them
    /// straight back — measured 2026-09-02, `live=1466.5 → 19550.7`, 498ms after the jump landed. The rule stood down *while* the jump was moving, `armed=yes`,
    /// and standing down is not disarming: a guard that skips an action must not skip the bookkeeping the next decision depends on.
    ///
    /// **Why the destination and not merely the fact of a scroll.** Disarming on *any* scroll of our own would remove the safety net Step 57 exists to be: the
    /// entry, the follow after a send and the way back to the end are all programmatic scrolls **towards** the end, and it is precisely them that Step 44b
    /// measured landing short. So the question is not *did we scroll* but *did we take the reader somewhere that is not the end*, and only the caller knows.
    enum WhereAScrollOfOurOwnIsHeaded {
        /// The end of the discussion. Leaves the belief alone: a scroll that lands there re-arms it from the geometry anyway, and one that lands *short* is the
        /// case Step 57 is the net for.
        case theEndOfTheDiscussion
        /// A row somebody asked for — a reply's quote, a search result, the message a notification is about. **This is a decision, exactly as a finger is**, so
        /// it disarms Step 57 and keeps it disarmed until the reader is seen at the end again.
        case aRowTheReaderAskedFor
    }

    private struct TheScrollOfOurOwn {
        var theOffsetOnTheLastFrame: CGFloat
        var hasBegunMoving: Bool
        var framesWithoutMoving: Int
        var framesSinceItWasAsked: Int
        /// Carried for the scroll's whole life so that the belief cannot be re-armed underneath it — see ``WhereAScrollOfOurOwnIsHeaded``.
        let itIsHeadedFor: WhereAScrollOfOurOwnIsHeaded
    }


    /// How still a scroll of our own has to be, having moved at least once, before it counts as finished.
    private static let framesOfStillnessThatEndAScrollOfOurOwn = 3

    /// How closely the geometry must match the scroll view on the first change after a scroll of our own.
    ///
    /// **A hair, and deliberately not a bound.** Everywhere else this rule tolerates a disagreement of the size a change of the space below could
    /// explain, because between two ordinary calls the clamp legitimately moves the offset. Straight after a scroll of our own that reasoning does not
    /// apply: the action's memory either includes the scroll, in which case it matches the scroll view exactly, or it is older than it, in which case it is
    /// worthless whatever the magnitude. Half a point is the same tolerance the rule uses to decide that a movement is real rather than rounding.
    private static let howCloselyTheGeometryMustAgreeAfterAScrollOfOurOwn: CGFloat = 0.5

    /// How long to wait for a scroll of our own to move anything before concluding that it never will.
    ///
    /// Only reached by a scroll that moves nothing — asking for a row already on screen, which is a real case and not a failure. A scroll that moves is
    /// ended by stillness, never by this.
    private static let framesToWaitForAScrollOfOurOwnToBegin = 12


    /// Where the end of the discussion was on the last presented frame, so that the next one can say whether it has moved.
    ///
    /// **Not the offset**, which is where the *reader* is: this is `contentHeight + bottomInset - height`, the greatest offset there is, and the
    /// quantity a deficit is made of. A transcript that grows while the reader stays put moves this and leaves the offset alone — which is exactly
    /// the fault the entry's cover exists to hide, and exactly what a rule watching the offset cannot see.
    /// The geometry from **before** a change that was declined only because the transcript was still settling at its end.
    ///
    /// **A transcript settling with nothing on the glass has exactly one destination.** The finger is off, `UIScrollView` is finishing a bounce or the tail of a
    /// fling that has already reached the end, and nothing the reader can do from here changes where it lands. So a change of the space below that arrives
    /// during one — tapping the composition bar while the discussion is still bouncing — is not a change that should be lost: it is one whose answer is known
    /// and merely early.
    ///
    /// It is answered when the bounce ends rather than during it, deliberately. Acting mid-bounce would put this rule and `UIScrollView`'s own animation on the
    /// same property at the same moment, which is the fault the whole of Step 44 exists to stop repeating; and it costs nothing to wait, a bounce settling in
    /// about a quarter of a second while the keyboard's own animation runs for half of one.
    ///
    /// **The earliest is kept**, not the latest: on iOS 18 a keyboard's inset arrives a frame at a time, so a single tap can be declined a dozen times, and what
    /// the rule needs is the geometry from before any of it. Discarded the moment a finger touches the glass again — the reader is in charge then, and the
    /// memory describes a discussion they have since moved.
    private var whatWasDeclinedWhileTheContentBouncedHome: TheGeometryOfTheTranscript?

    private var whereTheEndOfTheDiscussionWasOnTheLastFrame: CGFloat?


    /// How many presented frames in a row the end of the discussion has not moved — **the evidence behind believing that the transcript has stopped
    /// growing**, in place of a clock.
    ///
    /// **Measured before it was written, 2026-08-28, ten entries over two discussions on an iPhone 13.** The entry's own growth is real and large —
    /// the offset lands twice, `-101 → 17284.7 → 17433.0` in one discussion (+148.3, identical to the decimal in all five entries) and
    /// `-101 → 2405.7 → 3109.3` in a heavier one (+703.6, and +1703.3 on the first entry of its walk) — but it is **complete before this clock takes
    /// its first frame**: frame 1 arrives at 130–150ms and is already exact, `fromTheEnd=0.0`, and across all ten entries the frame report printed
    /// **one line each**, which is to say nothing moved again, ever. The 150ms the entry used to wait before believing a clean sample was insuring
    /// against a movement that had finished a quarter of a second earlier.
    ///
    /// **Deliberately not `@Published`**, like ``scrollsOfOurOwnAskedFor`` and for the same reason: it changes on every frame and nothing draws it.
    /// It is read imperatively, by a caller deciding whether a clean sample may be believed.
    ///
    /// **Nought is the honest answer when this clock is not running.** No scroll view, no display link, no frames — so a caller waiting on this waits
    /// out its own bound instead, which is the behaviour we want from a rule whose evidence has gone missing.
    private(set) var framesSinceTheEndOfTheDiscussionLastMoved = 0


    /// How far the end has to move to count as having moved — the same half point the rest of this object calls real rather than rounding.
    private static let howFarTheEndMustMoveToCount: CGFloat = 0.5



    /// How many scrolls of our own have been asked for since the screen appeared.
    ///
    /// **For a caller that asks a second time after waiting, so it can tell whether somebody else scrolled in between.** Two scrolls on this screen finish by
    /// re-asking — a jump and the way back — and a third joined them in Step 44b's second ask, which waits on a *condition* rather than a clock and so may wait
    /// for the better part of a second. In that window the reader can tap a reply header or the way back, and a re-ask made afterwards would faithfully undo
    /// whichever of those they chose. Comparing this count against the one taken when the first ask was made is the whole test: unchanged means nothing else has
    /// scrolled and the re-ask is still about the movement that started it.
    ///
    /// **Deliberately not `@Published`.** It is read imperatively at the two ends of a wait, and publishing it would re-evaluate the body of a list of hundreds
    /// of rows on every programmatic scroll for a value nothing draws. It is also not per-frame — it is written only where a scroll is asked for.
    private(set) var scrollsOfOurOwnAskedFor = 0

    /// Whether a scroll this screen asked for is still moving the transcript.
    ///
    /// **So that a caller waiting for the end to settle does not mistake its own movement for the fault it is watching for.** Step 44b's second ask samples the
    /// gate; during the follow's own 0.2s animation the reader is legitimately mid-flight and the gate is legitimately shut, so a sample taken then would read as
    /// *the follow failed* and cut the animation short — which is what 44g was reverted for. Read rather than timed, because the settling is already followed
    /// frame by frame here and a duration copied from the animation would be a duplicate that drifts.
    var aScrollOfOurOwnIsStillMoving: Bool { theScrollOfOurOwn != nil }

    /// Whether the last scroll this screen asked for ended without moving anything. Meaningful once ``aScrollOfOurOwnIsStillMoving`` is false.
    ///
    /// A list asked for a row it does not have moves nothing, so this is how the marker's correction tells a marker that has left the list from one that
    /// is only hard to reach. Not `@Published`, for the reason ``scrollsOfOurOwnAskedFor`` is not.
    private(set) var theLastScrollOfOurOwnMovedNothing = false

    /// Whether anything is actually watching the transcript: this clock running, and having been told about at least one frame.
    ///
    /// **The frame is the evidence and the display link alone is not.** A link exists the moment it is made, where a frame having been presented
    /// proves both that it ticked and that there was a scroll view to read when it did — which is the whole of what a caller waiting on this object
    /// needs to know.
    ///
    /// It exists because every wait on this object is a wait for something only this clock can say. ``aScrollOfOurOwnIsStillMoving`` is the clearest
    /// case: the flag is raised where the scroll is asked for and lowered only from a presented frame, so with nothing watching it stays raised for
    /// ever and a caller waiting on it waits out its own backstop for an answer that is not coming.
    var theTranscriptIsBeingRead: Bool { displayLink != nil && frameNumber > 0 }

    /// How far below what the reader can see the end of the discussion is, **read from the scroll view now** rather than as of the last presented frame.
    ///
    /// The number behind ``theReaderIsAtTheEndOfTheDiscussion``, exposed so that a caller standing down can say *by how much* rather than merely *whether* — a
    /// guard that reports its decision without the quantity behind it is only half a probe. Nothing decides anything on this: the gate above is what is tested,
    /// so that this cannot answer a question the gate would answer differently.
    var howFarTheEndIsBelowWhatTheReaderCanSee: CGFloat {
        guard let scrollView else { return 0 }
        return TheGeometryOfTheTranscript(scrollView).pointsBelowTheVisibleArea
    }

    /// Whether the reader is at the very end, read from the scroll view now. See ``TheGeometryOfTheTranscript/theReaderIsAtTheVeryEnd``, which is the one
    /// definition.
    var theReaderIsAtTheVeryEnd: Bool {
        guard let scrollView else { return false }
        return TheGeometryOfTheTranscript(scrollView).theReaderIsAtTheVeryEnd
    }

    /// Whether the reader is at the very top, read from the scroll view now. See ``TheGeometryOfTheTranscript/theReaderIsAtTheVeryTop``.
    var theReaderIsAtTheVeryTop: Bool {
        guard let scrollView else { return false }
        return TheGeometryOfTheTranscript(scrollView).theReaderIsAtTheVeryTop
    }


    // MARK: - Where the unread marker is

    /// The vertical middle of the unread marker's row, in the list's own coordinate space, or nil while that row is not laid out.
    ///
    /// The marker's row reports it as it lays out. Only the entry reads it, to check that the marker is where it was asked to be. **Not `@Published`**: it
    /// changes on every frame of a scroll and nothing draws it.
    private(set) var whereTheMarkerIs: CGFloat?

    /// The frame on which ``whereTheMarkerIs`` last changed.
    private var theFrameTheMarkerLastMovedOn = 0

    /// How many presented frames the marker has not moved for. Rows growing above the screen do not move it, because the list compensates for them. So this
    /// says whether *what the reader would see* has settled, where ``framesSinceTheEndOfTheDiscussionLastMoved`` also counts what they would not.
    var framesSinceTheMarkerLastMoved: Int { frameNumber - theFrameTheMarkerLastMovedOn }

    /// Said by the marker's row whenever its middle moves, and with nil when the row goes.
    func theMarkerIsAt(_ middle: CGFloat?) {
        guard middle != whereTheMarkerIs else { return }
        whereTheMarkerIs = middle
        theFrameTheMarkerLastMovedOn = frameNumber
    }

    /// The middle of what the reader can see, between the bars above and below, in the list's own coordinate space. Nil before the first frame is read.
    var theMiddleOfWhatCanBeSeen: CGFloat? {
        visibleAreaOfTheList.map { ($0.lowerBound + $0.upperBound) / 2 }
    }

    /// **This screen has asked the list to go somewhere.** Called from every programmatic scroll, through
    /// `SingleDiscussionCellsListView.asksForAScrollOfOurOwn(headingFor:_:)`.
    ///
    /// - Parameter whereItIsHeaded: what the scroll is *for*, which decides whether Step 57 goes on believing the reader is at the end. **Not defaulted, and
    ///   deliberately**: the funnel's own note admits it is a convention rather than a guarantee, so the least it can do is make the next caller answer the
    ///   question that was missed here. See ``WhereAScrollOfOurOwnIsHeaded``.
    func aScrollOfOurOwnWasAskedFor(headingFor whereItIsHeaded: WhereAScrollOfOurOwnIsHeaded) {
        scrollsOfOurOwnAskedFor += 1
        // **Disarmed here, at the ask, and not when the scroll lands.** The belief is true *now* — the reader is still at the end, the animation not having
        // started — so anything that waited for the scroll to finish would be reading a frame in which arming is still correct.
        if whereItIsHeaded == .aRowTheReaderAskedFor {
            theReaderWasAtTheVeryEnd = false
        }
        theScrollOfOurOwn = .init(theOffsetOnTheLastFrame: scrollView?.contentOffset.y ?? 0,
                                  hasBegunMoving: false,
                                  framesWithoutMoving: 0,
                                  framesSinceItWasAsked: 0,
                                  itIsHeadedFor: whereItIsHeaded)
    }


    /// Counts the presented frames since the end of the discussion last moved — see ``framesSinceTheEndOfTheDiscussionLastMoved``.
    ///
    /// **This is a stillness test, and a stillness test answers before the movement starts.** It is safe here because of who asks
    /// it: the entry consults it only after ``aScrollOfOurOwnIsStillMoving`` has gone false, so a scroll was asked for and was seen to move. The
    /// movement has begun long before this is read. Anything asking it earlier than that would be walking straight into the trap, so it is worth
    /// saying at the call site rather than here.
    ///
    /// **What that wait does *not* guarantee is this count, and the difference is easy to miss.** It watches the scroll of our own; this counts the
    /// *end*, which a growth moves while leaving the offset alone. That the two agree is measured rather than structural: on the entry's first sample
    /// the count reads exactly three — the threshold — which is why the entry can never take the refusing branch and why that branch has never run.
    /// Put the settle-wait on a different signal and the refusal becomes live and untested the same day, with nothing to announce it. The branch is
    /// not dead code even so: the follow's second ask reaches it, ten samples climbing 13, 22, 31 … 98 on the entry that measured this.
    private func noticesWhetherTheEndOfTheDiscussionHasMoved(_ geometry: TheGeometryOfTheTranscript) {
        let whereTheEndIs = geometry.contentHeight + geometry.bottomInset - geometry.height
        defer { whereTheEndOfTheDiscussionWasOnTheLastFrame = whereTheEndIs }
        guard let whereItWas = whereTheEndOfTheDiscussionWasOnTheLastFrame else {
            // The first frame has nothing to compare against, and claiming stillness from it would be claiming it from no evidence at all.
            framesSinceTheEndOfTheDiscussionLastMoved = 0
            return
        }
        if abs(whereTheEndIs - whereItWas) > Self.howFarTheEndMustMoveToCount {
            framesSinceTheEndOfTheDiscussionLastMoved = 0
        } else {
            framesSinceTheEndOfTheDiscussionLastMoved += 1
        }
    }


    /// Follows a scroll of our own to its end, on the one clock that sees every frame of it whoever caused it.
    private func watchesAScrollOfOurOwn(_ geometry: TheGeometryOfTheTranscript) {

        guard var theScroll = theScrollOfOurOwn else { return }

        theScroll.framesSinceItWasAsked += 1
        let itMovedThisFrame = abs(geometry.offset - theScroll.theOffsetOnTheLastFrame) > 0.5
        theScroll.theOffsetOnTheLastFrame = geometry.offset
        if itMovedThisFrame {
            theScroll.hasBegunMoving = true
            theScroll.framesWithoutMoving = 0
        } else {
            theScroll.framesWithoutMoving += 1
        }

        let itHasSettled = theScroll.hasBegunMoving && theScroll.framesWithoutMoving >= Self.framesOfStillnessThatEndAScrollOfOurOwn
        let itNeverMovedAnything = !theScroll.hasBegunMoving && theScroll.framesSinceItWasAsked >= Self.framesToWaitForAScrollOfOurOwnToBegin

        if itHasSettled {
            // **The debt is owed only by a scroll that moved something.** One that moved nothing leaves `asItWas` describing the truth, and standing
            // down would throw away a correction for no reason.
            theScrollOfOurOwn = nil
            theGeometryMustAgreeExactly = true
            theLastScrollOfOurOwnMovedNothing = false
        } else if itNeverMovedAnything {
            theScrollOfOurOwn = nil
            theLastScrollOfOurOwnMovedNothing = true
        } else {
            theScrollOfOurOwn = theScroll
        }

    }

    /// The one thing on this screen that writes `contentOffset` — see ``MovesTheMessagesWhenTheSpaceBelowThemChanges``. Held here because this is
    /// what holds the scroll view and knows whether the reader has hold of it, and called from
    /// ``theSpaceBelowTheMessagesChanged(from:to:)`` — **by SwiftUI, not by this clock**, since Step 46g.
    private let theMessagesAreMoved = MovesTheMessagesWhenTheSpaceBelowThemChanges()


    /// Whether an arrival is waiting to be followed — **somebody else owns the scroll for it, so Step 57's branch must not answer it.**
    ///
    /// **This is the boundary `keeping-the-content-in-place.md` draws and it cost a walk to rediscover.** *Must not touch the scrolls somebody
    /// asked for … a message arriving and being followed … the invariant is about not moving when nobody asked. If it ever fights one of these,
    /// the rule is wrong and not the scroll.* Step 57's branch answers a change of `contentHeight` for a reader at the end — and a message
    /// arriving **is** a change of `contentHeight` for a reader at the end. Measured on an iPad on 2026-09-01, three sends with the keyboard up:
    ///
    /// ```
    /// content 722.0→809.0 (+87)  fromTheEnd 0.0→87.0
    /// acted → 501.0                                       ← 87pt in one frame, set outright
    /// the follow's second ask finds the end reached, nothing to correct   ← 157ms later, the owner finds its work done
    /// ```
    ///
    /// The *outcome* was right and the *manner* was not: 87pt instantly where the follow scrolls. Reported as **the content jumps too much**.
    ///
    /// **Not `@Published`**, deliberately: nothing observes it, the rule reads it, and publishing from the list's `onChange` would put a write
    /// into an update pass for no purpose.
    private(set) var anArrivalIsWaitingToBeFollowed = false


    /// Told by the list when it arms or spends ``SingleDiscussionCellsListView/theMessageToScrollToOnceItHasAppeared``.
    ///
    /// **The list is the only thing that can say this**, and it already draws the distinction Step 57 needs: an arrival is a last row *the list did
    /// not previously hold*, which is what separates it from the last message being deleted and from a message elsewhere disappearing. So this
    /// needs no new notion of *arrived* — it borrows the one that already decides whether to follow.
    func saysWhetherAnArrivalIsWaitingToBeFollowed(_ isWaiting: Bool) {
        anArrivalIsWaitingToBeFollowed = isWaiting
    }


    /// The introspection has found the scroll view, which is **also when reading can begin**.
    ///
    /// It is called several times per entry — six, measured — with the same view, so starting on the first and refusing thereafter is what
    /// ``startsReading()``'s guard is for.
    func watches(_ scrollView: UIScrollView) {
        self.scrollView = scrollView
        // **Here because this is where the scroll view arrives**, and safe to say on every one of those six calls — see
        // ``TheProbeThatNoticesAWheel``, which is how the elastic scroll learns to stand aside for a wheel. It answers a question and
        // claims nothing; the properties that make that true rather than likely are named there.
        TheProbeThatNoticesAWheel.installsItself(on: scrollView, reportingTo: self)
        startsReading()
    }


    /// Begins reading, if there is anything to read and nothing is being read already.
    ///
    /// **Called from two places, and it has to be.** `onAppear` is too early — the introspection delivers *after* it, measured at 46a, where a
    /// first version started on appearance alone and read 104 frames without a scroll view. So the arrival of the scroll view starts it too,
    /// and whichever comes second is a no-op. The `onAppear` path is not redundant: re-entering the discussion re-appears with the scroll view
    /// already held, and nothing would deliver it again.
    func startsReading() {
        guard displayLink == nil else { return }
        // **Said out loud, and deliberately not behind `DEBUG`, which is the one difference from the announcement below.** That one explains a report
        // somebody switched on; this one explains a screen that has quietly stopped working on an operating system nobody has built for yet, which is
        // something that happens in the field rather than on a walk. The platform list of an introspection is a *value* and not an availability check,
        // so one that matches nothing installs nothing and says nothing: the scroll view never arrives, this clock never starts, and every rule that
        // reads it is inert while the screen looks merely slow.
        //
        // **It is one half of a pair and is worth nothing alone.** Saying *no scroll view yet* is the ordinary state at `onAppear`, the introspection
        // delivering afterwards. What makes it diagnostic is the line at the end of this method: if reading never begins, this says why.
        guard scrollView != nil else {
            Self.probe.info("🎞 nothing is being read yet: the introspection has not handed over a scroll view. If no line follows saying reading has begun, it never will — check that the platform list of the .introspect(.list) feeding this names the system it is running on.")
            return
        }
        // **Whatever the geometry did while this was not looking is not stillness**, so the count starts again from no evidence rather than from
        // a memory taken before the gap.
        whereTheEndOfTheDiscussionWasOnTheLastFrame = nil
        framesSinceTheEndOfTheDiscussionLastMoved = 0
        theFrameReportIsAskedFor = Self.theSettingSaysToReportEveryFrame()
        // **Unconditional, and that is the whole point of it.** A walk that produces no frames must say *why* — this project has misread a
        // silence as a measurement more times than any other single mistake, and a report that can be switched off is a new way to do it.
        // Behind `DEBUG` with the report it announces — in a Release build there is nothing for it to say. Its own reasoning is unchanged and still
        // right where it applies: **a walk that produces no frames must say why**, this project having misread a silence as a measurement more often
        // than it has made any other mistake.
        #if DEBUG
        Self.probe.info("🎞 frame report \(self.theFrameReportIsAskedFor ? "ON" : "OFF — Settings ▸ Advanced ▸ System console logs", privacy: .public)")
        #endif
        // **TEMPORARY until the scroll-wheel measurement in ``TheSpeedOfTheTranscript`` goes, and with it.** Handed the answer this method has just
        // read rather than reading the setting again: one switch, and a report whose two halves cannot disagree about whether they
        // are on. Said here rather than at the effect because this is the one place that knows both the setting and the scroll view.
        #if DEBUG
        if #available(iOS 17.0, *), let scrollView {
            theSpeedOfThisTranscript.reportsEveryScrollingFrame(theFrameReportIsAskedFor, alongside: scrollView)
        }
        #endif
        let link = CADisplayLink(target: self, selector: #selector(aFrameWasPresented))
        link.add(to: .main, forMode: .common)
        displayLink = link
        // The half that matters — see the guard above. Everything this screen knows about where the transcript is begins here.
        Self.probe.info("🎞 reading has begun: the geometry of the transcript is answered from every presented frame.")
    }


    /// **A display link retains its target**, so it must be stopped when the view goes, or nothing can ever be freed.
    ///
    /// **It is stopped on a teardown and not on a covering, and that was believed the other way round until it was measured.** Leaving the hierarchy
    /// is also what showing a photograph does, in general; on this screen it is not. Measured 2026-08-24: across a session spanning a
    /// photograph opened and closed, **79,231 frames in 1,321.4 seconds — 59.96 Hz with no gap anywhere.** `onDisappear` never fired, so this never
    /// ran, and the clock ticked sixty times a second behind a full-screen presentation nobody could see through.
    ///
    /// The teardown half does work, and the same log proves it: leaving the discussion gave **23.75 seconds with not one frame**, followed by a frame
    /// counter starting again from zero. A new object means the old one was freed, and it could only be freed if this had run.
    ///
    /// **Accepted rather than fixed, 2026-08-25**, because what is missing is an optimisation and not a stop. Behind a photograph nothing moves, so a
    /// tick reads five scalars, finds all four answers unchanged and publishes nothing; `WatchesEveryFrameOfTheTranscript` ran at 120Hz on every
    /// discussion for a week at 46's own reckoning. A `CADisplayLink` also stops being called when the app stops rendering, so backgrounding needs
    /// nothing. And there is no cheap hook to add: this module is told when the *discussion* comes and goes, never when an attachment is shown over it.
    ///
    /// One consequence follows from the clock running and is worth knowing rather than fixing: a message arriving while a photograph is up can still
    /// turn the visible-area band over and be marked as read. The discussion *is* the current one, so that is defensible — but it is a decision made
    /// by this clock rather than by anybody.
    func stopsReading() {
        displayLink?.invalidate()
        displayLink = nil
    }


    /// The discussion has just been sent to its end, so say what the geometry will not say for another frame or two.
    ///
    /// **Both of these were faults once.** The gate is written here because nothing else would say the reader is at the end for a moment, and
    /// until it does a message arriving would be followed — taking the reader away from the very messages they opened the discussion to read.
    /// And the way back is withheld because the list's *first* layout is at the top of the discussion, where the end genuinely is far below, so
    /// the button appeared over a screen the transcript had not been revealed on yet.
    func theDiscussionHasOpenedOnItsEnd() {
        theReaderIsAtTheEndOfTheDiscussion = true
        theEndIsFarBelowWhatTheReaderCanSee = false
        reportsAnAnswerTurningOver("the discussion opened ON ITS END: the gate is OPEN and the way back WITHDRAWN, both said before the geometry could")
    }


    /// The discussion has opened somewhere above its end — on the unread marker.
    ///
    /// Only the gate is said. How far above the end the reader is, is a number only the geometry has, so the way back is left to the next
    /// frame to decide: a wrong `true` there is corrected on the next frame, where a wrong `false` would withhold the button until the reader
    /// scrolled.
    func theDiscussionHasOpenedAboveItsEnd() {
        theReaderIsAtTheEndOfTheDiscussion = false
        reportsAnAnswerTurningOver("the discussion opened ABOVE ITS END, on the unread marker: the gate is SHUT, and the way back is left to the next frame")
    }


    @objc private func aFrameWasPresented() {

        guard let scrollView else { return }
        let geometry = TheGeometryOfTheTranscript(scrollView)

        // **The elastic scroll — see ``TheSpringEachMessageHangsFrom``.** Two lines, taken here because this is the one place on
        // the screen that already reads `contentOffset` on every presented frame: a velocity is a subtraction away, and nothing else has to be built
        // or told anything. Written before the guards below, deliberately — those exist to publish *only on a change*, and this is a value that
        // changes on nearly every frame and must not go anywhere near an `@Published`.
        // **Not gated on the setting**, deliberately: this object cannot see the environment, and stepping nine springs
        // nobody is watching is thirty floating-point operations. What the setting turns off is the *modifier*, and with
        // no modifier applied nothing observes the result. One switch, in one place — see ``TheSpringEachMessageHangsFrom``.
        if #available(iOS 17.0, *) {
            // **Where the finger is, before where the content is.** The effect measures every message's lag from the point the reader is holding,
            // so the anchor has to be current for the frame the lag is computed for. Only while a finger is genuinely down: a deceleration has no
            // grab point of its own and goes on using the one it was let go from.
            let pan = scrollView.panGestureRecognizer
            if pan.state == .began || pan.state == .changed, pan.numberOfTouches > 0, let window = scrollView.window {
                theSpeedOfThisTranscript.theReaderIsHoldingIt(at: pan.location(in: window).y, isANewTouch: pan.state == .began)
            }
            // **TEMPORARY until the scroll-wheel measurement goes, and before the step rather than after it**, so the line the step prints describes the frame it was told
            // about. See `the-elastic-scroll.md`, *Before TestFlight*: the effect has to stand down for a scroll wheel, and this is
            // the measurement that says whether a wheel is distinguishable from a trackpad in these numbers at all.
            // **The call is guarded and not only the body**, this one being per frame and existing solely to feed the report below it.
            #if DEBUG
            theSpeedOfThisTranscript.theScrollViewsOwnPanIs(pan)
            #endif
            theSpeedOfThisTranscript.theContentIsAt(geometry.offset)
        }

        // Counted here rather than where it is printed, so that an answer turning over and the frame it turned over in carry the same number —
        // which is the only way to line the two reports up. Every presented frame is counted; only the ones in which something changed are printed.
        frameNumber += 1

        // **Derived every frame, written only on a change.** The guards are the whole of the publishing discipline — see the note at the head
        // of this file for what writing them unconditionally would cost.

        let isAtTheEnd = geometry.pointsBelowTheVisibleArea < Self.closeEnoughToTheEndToBeFollowed
        if theReaderIsAtTheEndOfTheDiscussion != isAtTheEnd {
            theReaderIsAtTheEndOfTheDiscussion = isAtTheEnd
            reportsAnAnswerTurningOver("the gate is now \(isAtTheEnd ? "OPEN, an arrival is followed" : "SHUT, an arrival is not followed") — \(Self.oneDecimal(geometry.pointsBelowTheVisibleArea))pt below the visible area, against \(Self.oneDecimal(Self.closeEnoughToTheEndToBeFollowed))")
        }

        let asFarAsTheWayBackWaits = geometry.height * Self.screensBelowTheVisibleAreaBeforeTheWayBackIsOffered
        let theEndIsFarBelow = geometry.pointsBelowTheVisibleArea > asFarAsTheWayBackWaits
        if theEndIsFarBelowWhatTheReaderCanSee != theEndIsFarBelow {
            theEndIsFarBelowWhatTheReaderCanSee = theEndIsFarBelow
            reportsAnAnswerTurningOver("the way back is now \(theEndIsFarBelow ? "OFFERED" : "WITHDRAWN") — \(Self.oneDecimal(geometry.pointsBelowTheVisibleArea))pt below the visible area, against \(Self.oneDecimal(asFarAsTheWayBackWaits))")
        }

        let bottom = max(geometry.topInset, geometry.height - geometry.bottomInset)
        let theVisibleArea = geometry.topInset...bottom
        if visibleAreaOfTheList != theVisibleArea {
            let asItWas = visibleAreaOfTheList
            visibleAreaOfTheList = theVisibleArea
            let whereItCameFrom = asItWas.map { "\(Self.oneDecimal($0.lowerBound))...\(Self.oneDecimal($0.upperBound))" } ?? "nothing, this being the first frame read"
            reportsAnAnswerTurningOver("what can be read is now \(Self.oneDecimal(theVisibleArea.lowerBound))...\(Self.oneDecimal(theVisibleArea.upperBound)), from \(whereItCameFrom)")
        }

        // Not part of ``TheGeometryOfTheTranscript``, which is *where the transcript is* and nothing else. This is what the reader is doing to it.
        let theFingerIsOnIt = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
        // **A touch throws the memory away.** Whatever was held describes a discussion the reader is about to move, and a rule acting on it afterwards would
        // put them somewhere they did not ask to be — which is the fault the staleness guard downstream exists for, met early and cheaply.
        if scrollView.isTracking { whatWasDeclinedWhileTheContentBouncedHome = nil }


        if isUnderTheReadersFinger != theFingerIsOnIt {
            isUnderTheReadersFinger = theFingerIsOnIt
            reportsAnAnswerTurningOver(theFingerIsOnIt ? "the reader HAS HOLD of the transcript: nothing may be asked of the scroll view" : "the reader HAS LET GO of the transcript")
            // **On the falling edge only**, which is the moment the bounce is over and the offset is where it is going to stay.
            //
            // From the display link and therefore a frame later than `onScrollGeometryChange` would be, which 46g says the rule that writes the offset must not
            // be. It is acceptable *here* and nowhere else: this is not a repair of a frame about to be shown wrong, it is an answer that has been waiting a
            // quarter of a second already, and one more frame of it cannot be seen.
            if !theFingerIsOnIt { answersWhateverWasHeldWhileTheContentBounced(scrollView) }
        }

        noticesWhetherTheEndOfTheDiscussionHasMoved(geometry)

        watchesAScrollOfOurOwn(geometry)

        putsTheReaderBackAtTheEndOnceTheContentHasSettled(geometry)

        #if targetEnvironment(macCatalyst)
        watchesForAWindowBeingResized(geometry)
        #endif

        reportsThisFrame(geometry, theFingerIsOnIt)

        // **Nothing here writes anything to the scroll view, and that is the point of Step 46g.** The rule that moves the messages was driven from
        // this method between 46d and 46g and is now asked by SwiftUI instead — see ``theSpaceBelowTheMessagesChanged(from:to:)`` for the one frame
        // that decided it. What is left is four answers about where the transcript is, each of which can be a frame late invisibly, and a report.
    }


    // MARK: - Step 57: a rewrap moves the end, and nothing answered it

    /// Whether the reader was at the very end, the last time anything about it could be known.
    ///
    /// **Armed by being there and disarmed only by the reader's own hand**, which is the whole of the logic and is what makes this safe without a
    /// notion of *when the resize began*: being at the end arms it; leaving the end *with a finger on the transcript* disarms it, because that is a
    /// reader choosing where to sit; and leaving the end for any **other** reason leaves it armed, which is precisely the case this exists for.
    private var theReaderWasAtTheVeryEnd = false

    /// **DEBUG INSTRUMENT, and it exists because the first version of this rule refused in four different ways and said nothing.** On the Mac walk of
    /// 2026-09-01 the content grew 38.9pt and then 67.0pt under a reader who was at the end, leaving them 38.8 and **66.8** points off it — the
    /// second shutting the 60pt gate, which is the whole of Step 57's fault — and the rule did not write. Which of the guards refused was not
    /// recoverable from the log, so nothing could be concluded but *the instrument is wrong*, for the second time in one day.
    ///
    /// **One line per episode of being away from the end**, rather than per frame: the reason is a property of the episode, and a line every frame
    /// would bury the rest of this category. Reset when the reader is back at the end.
    private var theReasonForStandingDownHasBeenReported = false

    /// **DEBUG INSTRUMENT, and a token of its own rather than sharing the one above.** The stillness refusal is the ordinary state on the way to acting, so it
    /// comes first and would take the single report of an episode every time, hiding the ownership refusals — including the arrival stand-down, which
    /// took six archives to see once. Two questions, two tokens.
    private var theStillnessRefusalHasBeenReported = false


    /// **Step 57.** A reader who was at the end and is no longer, through no act of their own, is put back once the content has stopped moving.
    ///
    /// The fault, measured on an iPad on 2026-08-26 and again on 2026-09-01: a narrower window rewraps the messages, so the discussion gets taller and
    /// its end moves down — **22pt** on a Split View divider, **66pt** on a Stage Manager corner drag — and the reader is left off the end by exactly
    /// that growth. At 66 the 60pt gate shuts, and stayed shut for **507 frames**, so an arriving message would not have been followed.
    ///
    /// **Why it is here and not in the rule that answers the space below.** That rule holds the content point that was at the bottom edge, which is
    /// right for a viewport change and wrong for a content change; and it is asked by `onScrollGeometryChange`, which cannot say *the content has
    /// finished moving*. This is asked by the clock, where stillness is countable.
    ///
    /// **Once it settles, and that was the reader's decision after walking the alternative.** A per-step version worked on the divider and was
    /// withdrawn: the `List` briefly reported a content height **127.5pt** larger than the one it settled on, and the per-step rule chased that spike
    /// and was pulled back by the clamp 264ms later. **A transient is movement by definition, so waiting for stillness cannot chase one.**
    ///
    /// **Three frames of stillness, which is this object's own number for *has this stopped moving*** —
    /// ``framesOfStillnessThatEndAScrollOfOurOwn``. Shared deliberately: two answers to one question are two rules that can disagree, and it counts
    /// *frames in which the end could have moved and did not*, so a 120Hz screen supplies the evidence sooner rather than waiting out a clock.
    ///
    /// Four things stand it down, and each is somebody else's business: a finger on the transcript, a scroll of our own still moving, an arrival
    /// waiting to be followed — see ``anArrivalIsWaitingToBeFollowed``, and the 87pt snap that taught it — and a discussion short enough to fit, which
    /// has no end to be away from.
    private func putsTheReaderBackAtTheEndOnceTheContentHasSettled(_ geometry: TheGeometryOfTheTranscript) {

        // **Not while a scroll of our own is carrying the reader somewhere they asked for**, or the disarm at the ask is undone on the very next frame. An
        // animated scroll has moved nothing when it begins, so for those first frames the geometry still says *at the very end* — and says it truthfully. The
        // belief may be re-armed only once that scroll is over and the reader is **seen** at the end, which is the frame after it settles if it lands there.
        if geometry.theReaderIsAtTheVeryEnd, theScrollOfOurOwn?.itIsHeadedFor != .aRowTheReaderAskedFor {
            theReaderWasAtTheVeryEnd = true
            theReasonForStandingDownHasBeenReported = false
            theStillnessRefusalHasBeenReported = false
            return
        }

        // A debug instrument, with ``theReasonForStandingDownHasBeenReported`` — every path out of this method now names itself once.
        func standsDown(_ why: String) {
            guard !theReasonForStandingDownHasBeenReported else { return }
            theReasonForStandingDownHasBeenReported = true
            MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid(
                "stood down, \(why)",
                String(format: "fromTheEnd=%.1f content=%.1f canSee=%.1f armed=%@ finger=%@ ourScroll=%@ arrival=%@ endStillFor=%d",
                       geometry.pointsBelowTheVisibleArea, geometry.contentHeight, geometry.heightOfWhatCanBeSeen,
                       theReaderWasAtTheVeryEnd ? "yes" : "NO",
                       isUnderTheReadersFinger ? "yes" : "no",
                       theScrollOfOurOwn == nil ? "no" : "yes",
                       anArrivalIsWaitingToBeFollowed ? "yes" : "no",
                       framesSinceTheEndOfTheDiscussionLastMoved))
        }

        // Not armed: the reader chose where they are, so there is nothing to put back.
        guard theReaderWasAtTheVeryEnd else { return standsDown("the reader was not at the end to begin with") }

        // **The reader's own hand disarms it, and nothing else does.** `isUnderTheReadersFinger` covers the deceleration after a flick as well as the
        // drag itself, so a reader who flings away from the end has decided, and a bounce *at* the end never reaches here — an overscroll reads as a
        // negative distance, which is `theReaderIsAtTheVeryEnd` above.
        if isUnderTheReadersFinger {
            theReaderWasAtTheVeryEnd = false
            standsDown("the reader has hold of the transcript, so they chose this")
            return
        }

        guard let scrollView else { return }

        // A discussion that fits the screen has no end to be away from, and the rubber band it would fight is `UIScrollView`'s own.
        guard geometry.contentHeight > geometry.height - geometry.topInset - geometry.bottomInset else {
            return standsDown("the discussion fits on the screen")
        }

        // Still moving. **This is also the whole of why a transient cannot be chased** — see the 127.5pt spike on this method's doc.
        guard framesSinceTheEndOfTheDiscussionLastMoved >= Self.framesOfStillnessThatEndAScrollOfOurOwn else {
            // **DEBUG INSTRUMENT, and it carries the content height because that is the whole of what it is for.** The claim this rule rests on is that a
            // transient cannot be chased, a transient being movement — the `List` was measured reporting a content height **127.5pt** larger than the
            // one it settled on, withdrawn 264ms later, and the per-step version that preceded this chased it. That claim was an argument from the
            // mechanism until this line existed: a refusal *naming the phantom value it refused on* is the observation.
            if !theStillnessRefusalHasBeenReported {
                theStillnessRefusalHasBeenReported = true
                MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid(
                    "stood down, the end is still moving",
                    String(format: "fromTheEnd=%.1f content=%.1f canSee=%.1f endStillFor=%d",
                           geometry.pointsBelowTheVisibleArea, geometry.contentHeight, geometry.heightOfWhatCanBeSeen,
                           framesSinceTheEndOfTheDiscussionLastMoved))
            }
            return
        }


        // **Everything below here would otherwise have written the offset**, which is why the refusal is worth a line and the guards above are not:
        // a guard that refuses in silence cannot be told apart from a case that never arose, and this one had to be argued from the
        // *absence* of a write on the walk of 2026-09-01 rather than read off the log, which is exactly the position that warns against.
        if anArrivalIsWaitingToBeFollowed {
            return standsDown("an arrival is waiting to be followed")
        }

        guard theScrollOfOurOwn == nil else { return standsDown("a scroll of our own is still moving the transcript") }

        theMessagesAreMoved.putsTheReaderBackAtTheEnd(on: scrollView, from: geometry)

    }


    // MARK: - Step 46n: the one change SwiftUI does not report, on the one platform that has it

    #if targetEnvironment(macCatalyst)

    /// The geometry as the previous presented frame had it, kept **only** for the window-resize rule below.
    ///
    /// It is not a general `asOfTheLastFrame`: 46g removed that deliberately, `onScrollGeometryChange` handing over both the before and the
    /// after so that nothing has to be remembered and the 285pt bug of a chained-but-stale offset cannot arise. This one exists because the
    /// event below is *never* handed over at all.
    private var theGeometryAsOfTheLastFrame: TheGeometryOfTheTranscript?


    /// **Step 46n. A window resized by dragging its edge is never reported, so this clock reports it.**
    ///
    /// `onScrollGeometryChange` runs in SwiftUI's update pass, and **a live resize drag does not run one**. It wakes only when the clamp moves
    /// `contentOffset`, or when a discrete resize forces a layout pass. Measured on a Mac: dragging an edge shorter at the end took `bounds` from
    /// 1165 to 721 with the offset constant and **not one report**, while the zoom button was reported at once and answered correctly.
    ///
    /// **It is not cosmetic.** The reader is left N pt from the end, which shuts the 60pt gate and raises the way-back button, so the next message is
    /// not followed — a send landed 117.5pt short. That same send then provokes the pass that delivers the whole banked change at once, applying
    /// 497pt as one jump onto an innocent action. One root, three faces.
    ///
    /// Three narrowings, each of which keeps 46g intact:
    ///
    /// - **`height` and nothing else.** Every inset change stays on `onScrollGeometryChange`, where 46g's same-frame argument holds and where a
    ///   display link would be a frame late.
    /// - **The same door**, ``theSpaceBelowTheMessagesChanged(from:to:arrivingAFrameAtATime:)``, so every guard applies exactly as it does to
    ///   SwiftUI's own calls.
    /// - **Catalyst only**, so iOS and iPadOS compile to what they compiled to before. Whether an iPad's Split View and Stage Manager are deaf in the
    ///   same way is **not known and is worth measuring**.
    ///
    /// **Two callers for one event are not harmless, and the argument that they were is the instructive part.** It was thought safe by construction:
    /// the rule computes an absolute target, so a second run finds itself already there and declines. The walk disproved it in an hour — on the zoom
    /// button both callers answered and their targets differed by 31pt, because the native observer's `asItWas` is the last time *its* action ran and
    /// this one's is the last presented frame. **An idempotence argument has to name whose memory it rests on.** What makes it safe instead is stated
    /// where it is enforced: whoever is told about a change owns it, and the native observer refreshes this rule's memory on every path it takes.
    private func watchesForAWindowBeingResized(_ geometry: TheGeometryOfTheTranscript) {

        // **Recorded after the rule has had its say, and re-read from the scroll view rather than reusing what was passed in.** The rule writes
        // `contentOffset`, so the geometry handed to this method is already out of date by the time it returns — and a memory that is older than its
        // own write is precisely the fault that put the keyboard 285pt out at 46d, where a second inset step was measured against an offset that
        // had already been replaced. Here it would be worse, because a drag delivers dozens of steps: the error would be the sum of every
        // correction made so far.
        //
        // In a `defer` so that it happens on **every** path, the two guards below included: a guard that skips an action must not
        // skip the bookkeeping the next decision depends on.
        defer { theGeometryAsOfTheLastFrame = scrollView.map { TheGeometryOfTheTranscript($0) } ?? geometry }

        guard let asItWas = theGeometryAsOfTheLastFrame else { return }
        guard asItWas.height != geometry.height else { return }

        // The rule's door is `@available(iOS 18.0, *)` where this clock is not — 46h keeps the display link on every version it supports, and
        // only the writer went back to being iOS 18's. On Catalyst this is macOS 15 and later, so it is not a branch anyone will meet.
        guard #available(iOS 18.0, *) else { return }
        theSpaceBelowTheMessagesChanged(from: asItWas, to: geometry, arrivingAFrameAtATime: true)

    }

    #endif


    /// The rule that writes `contentOffset`, asked by SwiftUI rather than by this clock — **Step 46g**.
    ///
    /// It lived on the display link from 46d until 46g, and the measurement that moved it is worth keeping. The clock is told after a frame is
    /// **presented**, so at the moment the composition bar's reparameterisation ends and the viewport snaps back to its full height, the correction
    /// went out a frame late and one bad frame was shown — `offset=52844` against a maximum of `52928`, 84pt of message. `onScrollGeometryChange`
    /// is told during the update pass, **before the frame is committed**, and the same rule then lands it in the same frame:
    ///
    /// ```
    /// clock:   789.5/0 → 874/84 offset=52844 fromTheEnd=84.0 → offset=52928 fromTheEnd=0    ← 84pt, presented
    /// SwiftUI: 789.5/0 → 874/84 offset=52928 fromTheEnd=0                                   ← no such frame
    /// ```
    ///
    /// That one frame is why the composition bar can animate its height again, and why ``ComposeView`` no longer needs to be told not to.
    ///
    /// It also needs nothing remembered: `onScrollGeometryChange` hands over the geometry as it was *and* as it is, which is the pair the display
    /// link had to keep an `asOfTheLastFrame` for. So the written offset is dropped rather than chained, and the bug that cost the keyboard 285pt —
    /// a second inset step measured against an offset that had already been replaced — cannot arise here at all.
    /// - Parameter arrivingAFrameAtATime: Whether this change is one step of a movement being delivered per frame, which only **Step 46n**'s
    ///   window resize passes. It decides how the rule *moves* rather than where it moves to: a per-frame arrival is itself the animation, so
    ///   animating each step over a quarter of a second would leave the content trailing the window's edge by that much and stack twenty
    ///   overlapping animations doing it. The rule already has this branch for iOS 18's per-frame keyboard.
    @available(iOS 18.0, *)
    func theSpaceBelowTheMessagesChanged(from asItWas: TheGeometryOfTheTranscript, to asItIsNow: TheGeometryOfTheTranscript, arrivingAFrameAtATime: Bool = false) {

        guard let scrollView else { return }

        #if targetEnvironment(macCatalyst)
        // **Step 46n: whoever is told about a change owns it, and the clock answers only what SwiftUI was never told about.**
        //
        // Refreshing the memory here is what stops the two callers answering one event. They do not share an `asItWas` — SwiftUI's is the last
        // time *its* action ran, the clock's is the last presented frame — so when both answer, their targets differ by however far apart those
        // two memories are, and the later writer wins. Measured on the zoom button, 2026-08-25, before this line existed:
        //
        // ```
        // acted                                | was=-95 now=-95 live=-95 → 687     ← SwiftUI, correct
        // acted, on a frame of a window resize | was=-64 now=687 live=687 → 718     ← the clock, 31pt further, 30ms later
        // ```
        //
        // 31pt of disagreement in the memory became 31pt of disagreement in the answer. The idempotence this was expected to have — *an absolute
        // target, so a second run finds itself already there* — holds only between callers reading the same past, and these two do not.
        //
        // In a `defer`, so it happens on the stand-down paths too: a change SwiftUI **declined** deliberately is not one for the clock to
        // second-guess. And re-read from the scroll view rather than taken from `asItIsNow`, because the rule below writes `contentOffset` and
        // the memory must include the write.
        defer { theGeometryAsOfTheLastFrame = TheGeometryOfTheTranscript(scrollView) }
        #endif

        // **Nothing may be asked of the scroll view while a scroll of our own is moving it, and the first change after one must not be answered from
        // a geometry that is older than it.** See ``theScrollOfOurOwn`` and ``theGeometryMustAgreeExactly``; the reason both halves are needed is written there.
        //
        // Said out loud in both branches, because a guard that refuses in silence cannot be told apart from a case that never arose — which is exactly
        // how the fault this closes was missed twice.
        if theScrollOfOurOwn != nil {
            MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid(
                "stood down, a scroll of our own is still moving the transcript",
                String(format: "live=%.0f (canSee %.0f→%.0f)", scrollView.contentOffset.y, asItWas.heightOfWhatCanBeSeen, asItIsNow.heightOfWhatCanBeSeen))
            return
        }

        if theGeometryMustAgreeExactly {
            theGeometryMustAgreeExactly = false
            let howFarTheOldGeometryIsFromTheTruth = abs(scrollView.contentOffset.y - asItWas.offset)
            if howFarTheOldGeometryIsFromTheTruth > Self.howCloselyTheGeometryMustAgreeAfterAScrollOfOurOwn {
                MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid(
                    "stood down, the geometry predates a scroll of our own",
                    String(format: "was=%.0f live=%.0f (out by %.0f, canSee %.0f→%.0f)", asItWas.offset, scrollView.contentOffset.y,
                           howFarTheOldGeometryIsFromTheTruth, asItWas.heightOfWhatCanBeSeen, asItIsNow.heightOfWhatCanBeSeen))
                return
            }
        }

        // **Kept rather than lost, when the reader was already at the end and nothing but the transcript's own settling is in the way.**
        //
        // **The question is asked of `asItWas`, and the first version asked it of the scroll view — which was structurally unanswerable.** It tested
        // `offset > greatestOffset`, a bottom rubber band; but `greatestOffset` is `contentHeight + bottomInset - height`, so by the moment a keyboard's inset is
        // reported the greatest offset has already grown by the keyboard's own height and the content is *short* of it by that much. Measured on an iPhone 13 on
        // 2026-08-30 across a whole walk: **`past` was negative on every line**, −11 to −412, and the branch could not have fired once. What the rule needs to
        // know is not where the content is now but **where it was before this change**, and `asItWas` is exactly that.
        //
        // `!isTracking` and not `!isUnderTheReadersFinger`: a finger on the glass is the case the guard downstream is right about — dragging the keyboard away
        // changes the inset thirty times and the finger is already moving the content. A transcript settling on its own with nothing touching it is not that.
        //
        if isUnderTheReadersFinger, whatWasDeclinedWhileTheContentBouncedHome == nil,
           !scrollView.isTracking, asItWas.pointsBelowTheVisibleArea < Self.closeEnoughToTheEndToBeFollowed {
            whatWasDeclinedWhileTheContentBouncedHome = asItWas
            MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid(
                "held until the transcript settles",
                String(format: "wasBelow=%.1f live=%.0f (canSee %.0f→%.0f)", asItWas.pointsBelowTheVisibleArea, scrollView.contentOffset.y,
                       asItWas.heightOfWhatCanBeSeen, asItIsNow.heightOfWhatCanBeSeen))
        }

        theMessagesAreMoved.answersAChangeOfWhatCanBeSeen(from: asItWas,
                                                          to: asItIsNow,
                                                          on: scrollView,
                                                          isUnderTheReadersFinger: isUnderTheReadersFinger,
                                                          arrivingAFrameAtATime: arrivingAFrameAtATime)
    }


    /// Answers the change that was held while the transcript bounced home, now that it has arrived.
    ///
    /// **The one rule, run late, and not a special case of its own.** What is asked here is exactly what would have been asked at the moment the space below
    /// changed — the same invariant, the same guards, the same staleness bound — with the geometry from before the change and the geometry as it is now. Writing
    /// *go to the end* instead would be a second rule that agrees with the first until the day it does not.
    ///
    /// The staleness guard inside it is what makes this safe rather than merely plausible: `asItWas` is by construction older than usual, and that guard exists
    /// for precisely that, bounding the disagreement by `|Δheight| + |ΔbottomInset|` — which a keyboard's inset makes generous and a rubber band's hundred points
    /// comfortably fit inside.
    private func answersWhateverWasHeldWhileTheContentBounced(_ scrollView: UIScrollView) {
        // Measured on an iPhone 13, 2026-08-30: four for four, the content moved 295pt on the keyboard's own 383ms spring and the gate then read
        // `0.0pt below the visible area`. Note what that walk did *not* exercise — `live` was within 6pt of `was` every time, so the staleness guard
        // downstream was never asked anything hard.

        guard let asItWas = whatWasDeclinedWhileTheContentBouncedHome else { return }
        whatWasDeclinedWhileTheContentBouncedHome = nil

        let asItIsNow = TheGeometryOfTheTranscript(scrollView)
        MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid(
            "the bounce is over, answering what was held",
            String(format: "was=%.0f live=%.0f (canSee %.0f→%.0f)", asItWas.offset, scrollView.contentOffset.y,
                   asItWas.heightOfWhatCanBeSeen, asItIsNow.heightOfWhatCanBeSeen))

        theMessagesAreMoved.answersAChangeOfWhatCanBeSeen(from: asItWas,
                                                          to: asItIsNow,
                                                          on: scrollView,
                                                          isUnderTheReadersFinger: false)

    }


    // MARK: - Reporting every frame, for as long as Step 46d needs it

    /// What was reported last, so that a still screen writes nothing and a value held for twelve frames cannot be mistaken for one held for one.
    private var theLastLineReported: String?
    private var framesSinceSomethingChanged = 0
    private var frameNumber = 0

    private static let probe = Logger(subsystem: "io.olvid.messenger", category: "TranscriptFrames")


    /// Whether this report is wanted, read **once** in ``startsReading()`` rather than per frame — the answer cannot usefully change in the
    /// middle of a scroll, and a report whose shape changes half way through a walk is worse than one that is off.
    private var theFrameReportIsAskedFor = false


    /// **Read straight from the shared `UserDefaults` rather than through `ObvMessengerSettings`**, this module having no dependency on
    /// `ObvSettings` — and an instrument that is meant to leave is a poor reason to give it one, or to plumb a debug flag through the initial
    /// values of a production screen. The key is `ObvMessengerSettings.Advanced.logTranscriptFrames`'s own, and the comment there says why this
    /// report may never be routed into the shareable in-app logs.
    private static func theSettingSaysToReportEveryFrame() -> Bool {
        UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier)?
            .bool(forKey: "settings.advanced.logTranscriptFrames") ?? false
    }


    /// **DEBUG INSTRUMENT, and the one this screen is judged by.** Every presented frame, as `WatchesEveryFrameOfTheTranscript` reported it through the whole of Step 44 — same fields,
    /// same format, so that the walks made then can be compared with the ones made now.
    ///
    /// **It is the instrument 46d is judged by, and a shadow is not.** The rule being written does not *agree* with the one it replaces — the old one
    /// acts twice through an animation and jumps to its end, the new one acts every frame and rides it — so comparing their decisions would show
    /// disagreement by design and prove nothing. What can be judged is the outcome: `fromTheEnd` per presented frame, which is the fault in one
    /// number.
    ///
    /// On the display link this object already runs, rather than a second one: two display links reading the same scroll view a frame apart is the
    /// sort of thing that makes a fault intermittent.
    private func reportsThisFrame(_ geometry: TheGeometryOfTheTranscript, _ theFingerIsOnIt: Bool) {

        // **`#if DEBUG` as well as the setting, decided 2026-09-01 before the TestFlight merge, and the trade is worth naming rather than assuming.** The
        // setting alone was the whole of the gate, so this shipped: a reader who turned Settings ▸ Advanced ▸ System console logs on got a line per
        // presented frame in a Release build, which is what made a tester's dropped-frame report diagnosable — and that argument is written down in
        // `the-elastic-scroll.md`, which calls this screen's second unmeasured per-frame consumer a reason to keep the instrument. **The reader chose the
        // other side of it: nothing extra in a shipped build.** So a jank report from TestFlight now cannot be read off a log, and answering one means a
        // Debug build in the hand. Both halves stay because they answer different questions — the setting keeps a developer's console quiet by default,
        // this keeps the report out of Release entirely.
        //
        // **The call site needs no guard.** Everything handed over is a scalar already computed for the rule above, so there is nothing built to be
        // thrown away — which is the opposite of finding 13's swipe logging, where the cost *was* what the call sites assembled and guarding the body
        // alone would have fixed almost nothing.
        #if DEBUG

        guard theFrameReportIsAskedFor else { return }

        // **`contentOffset` is the model, and during a `UIView.animate` the model is already at its destination.** So a 317pt keyboard step reads as
        // one instantaneous jump in this log whether the reader saw a glide or a snap, and every walk that judged the keyboard by these numbers was
        // judging something nobody was shown. The presentation layer is what was on screen; it is reported next to the model, and `shown=` differing
        // from `offset=` is an animation in flight rather than a fault.
        let whatWasActuallyShown = (scrollView?.layer.presentation()?.bounds.origin.y).map { String(format: " shown=%.1f", $0) } ?? ""

        // **DEBUG INSTRUMENT, written to scope a window resize on an iPad and kept for a reason that outlives that question.** The five scalars this report has always carried are the five
        // ``TheGeometryOfTheTranscript`` holds, and none of them is a width — which is fine on a Mac, where the window drag being measured
        // changes the height. **On an iPad the Split View divider changes the width and nothing else**, so without this the drag would produce a
        // line identical to the previous one, be swallowed by the dedup below, and read as *nothing happened* — which is the substitution
        // to fear twice over: a silent probe is not an answer, and an instrument that reports the wrong thing is worse than one
        // that reports nothing. Read off the scroll view rather than added to the geometry, because that struct is what
        // `onScrollGeometryChange(for:)` compares to decide whether to fire at all, and widening its equality would change when the rule is
        // asked on every platform.
        let width = (scrollView?.bounds.width).map { String(format: " width=%.1f", $0) } ?? ""

        let furthest = max(-geometry.topInset, geometry.contentHeight + geometry.bottomInset - geometry.height)
        let line = String(format: "offset=%.1f%@ content=%.1f bounds=%.1f%@ inset=%.1f fromTheEnd=%.1f%@",
                          geometry.offset, whatWasActuallyShown, geometry.contentHeight, geometry.height, width, geometry.bottomInset,
                          furthest - geometry.offset,
                          theFingerIsOnIt ? " [finger]" : "")

        guard line != theLastLineReported else {
            framesSinceSomethingChanged += 1
            return
        }
        let held = framesSinceSomethingChanged
        framesSinceSomethingChanged = 0
        theLastLineReported = line

        if held > 0 {
            Self.probe.info("🎞 frame \(self.frameNumber, privacy: .public): \(line, privacy: .public) [previous held \(held, privacy: .public) frames]")
        } else {
            Self.probe.info("🎞 frame \(self.frameNumber, privacy: .public): \(line, privacy: .public)")
        }

        #endif

    }


    // MARK: - Reporting the four answers, for as long as Step 46g's walk needs them

    private static let answers = Logger(subsystem: "io.olvid.messenger", category: "TranscriptAnswers")


    /// **Kept until Step 46 closes**, when it comes out with the frame report.
    ///
    /// The four answers are why this display link is still here: 46h declined to move them back to `onScrollGeometryChange` on the grounds that the native
    /// API does not fire during a `ScrollViewProxy.scrollTo`, so the gate would not learn the reader had arrived until something else moved. **An argument of
    /// that shape has to be seen rather than reasoned about**, and until this was written not one of the four said anything.
    ///
    /// **A crossing is the whole of the event**, so this is called where each answer is written and nowhere else. The two calls that are *not* crossings are
    /// the writes made on entry, which bypass the geometry entirely.
    ///
    /// **It has no line saying it is running**, which every probe should have. It did not need one while the frame report was emitted from
    /// the same method on every presented frame: `TranscriptFrames` speaking was the liveness answer for both probes, and silence *here* beside frames
    /// *there* was a value that genuinely did not turn over.
    ///
    /// **That holds only while the frame report is switched on**, and it is now behind `ObvMessengerSettings.Advanced.logTranscriptFrames`. With it off,
    /// `TranscriptFrames` carries one line — the unconditional ON/OFF announcement at ``startsReading()`` — and silence here is unexplained rather than
    /// meaningful, which is the very substitution this comment exists to prevent. **Read the announcement first: if it says OFF, this probe's silence says
    /// nothing at all.**
    ///
    /// A category of its own so neither report drowns the other: the frame log is one line per moving frame, and the finger alone turns over on every frame
    /// of an interactive keyboard dismissal.
    ///
    /// **Nothing at all outside a debug build, the argument included.** Every call site interpolates, and two of the six turn over per frame through an
    /// interactive keyboard dismissal, so the cost is what they build rather than the `Logger`. Safe to defer: each argument reads only values the
    /// caller has already settled, in the same synchronous stretch.
    private func reportsAnAnswerTurningOver(_ whatChanged: @autoclosure () -> String) {
        #if DEBUG
        // Into a local first: an `OSLogMessage` interpolation takes escaping autoclosures, which a non-escaping one may not be captured by.
        let theChange = whatChanged()
        Self.answers.info("🎞 frame \(self.frameNumber, privacy: .public): \(theChange, privacy: .public)")
        #endif
    }


    /// Enough precision to see a half-point and not enough to read as noise — the same shape the frame report prints its five numbers in.
    private static func oneDecimal(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

}


// MARK: - Putting it on the list

/// Gives ``TheGeometryOfTheTranscriptReadPerFrame`` the list's scroll view, and starts and stops it with the screen.
///
/// A modifier of its own rather than four more lines on `SingleDiscussionCellsListView`'s body, and that is not tidiness: that body already
/// answers *"the compiler is unable to type-check this expression in reasonable time"* when anything in its modifier chain is perturbed.
struct ReadsTheGeometryOfTheTranscriptPerFrame: ViewModifier {

    let theGeometry: TheGeometryOfTheTranscriptReadPerFrame

    func body(content: Content) -> some View {
        content
            .introspect(.list, on: .iOS(.v18, .v26, .v27)) { foundScrollView in
                Task { @MainActor in theGeometry.watches(foundScrollView) }
            }
            .onAppear { theGeometry.startsReading() }
            .onDisappear { theGeometry.stopsReading() }
    }

}


/// Asks SwiftUI to say when the space below the messages changes, and hands the answer to the same rule — **Step 46g**, and see
/// ``TheGeometryOfTheTranscriptReadPerFrame/theRuleIsDrivenByTheDisplayLink``.
///
/// A modifier of its own for the reason the one above is: `SingleDiscussionCellsListView`'s body answers *"the compiler is unable to type-check
/// this expression in reasonable time"* when anything in its modifier chain is perturbed.
@available(iOS 18.0, *)
struct TheSpaceBelowTheMessagesWatchedBySwiftUI: ViewModifier {

    let theGeometry: TheGeometryOfTheTranscriptReadPerFrame

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: TheGeometryOfTheTranscript.self) { geometry in
                TheGeometryOfTheTranscript(geometry)
            } action: { asItWas, asItIsNow in
                // **DEBUG INSTRUMENT, and it reports before the guard on purpose.** A window resize on a real Mac was
                // measured leaving the transcript 100pt above its end with this rule saying nothing at all — and *nothing at all* has two
                // explanations that no amount of reading separates: the closure was never called, or it was called and the guard below sent it
                // home. A silent probe is not an answer until you have proved it runs.
                MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid(
                    "SwiftUI reported the geometry",
                    String(format: "canSee %.1f→%.1f (height %.1f→%.1f, inset %.1f→%.1f, offset %.1f→%.1f, content %.1f→%.1f, fromTheEnd %.1f→%.1f)",
                           asItWas.heightOfWhatCanBeSeen, asItIsNow.heightOfWhatCanBeSeen,
                           asItWas.height, asItIsNow.height,
                           asItWas.bottomInset, asItIsNow.bottomInset,
                           asItWas.offset, asItIsNow.offset,
                           asItWas.contentHeight, asItIsNow.contentHeight,
                           asItWas.pointsBelowTheVisibleArea, asItIsNow.pointsBelowTheVisibleArea))
                // The one quantity this rule has always answered, and the reason it is safe to answer: the reader's finger cannot change how much
                // can be seen — scrolling moves the offset — and **neither can our own write**, so the feedback that once oscillated between two
                // offsets and locked the screen is impossible by construction rather than prevented by a guard.
                //
                // **Step 57 was tried here and belongs elsewhere.** A rewrap grows the content without touching the height or the inset, so this
                // guard turns the rule away — measured on an iPad on 2026-09-01, a Split View divider drag gave **dozens of reports and not one
                // call**, `canSee 764.0→764.0` on every one, while the last message slid down behind the composition bar. A second door was opened
                // here for a content-only change and it worked; it was withdrawn because Step 57's answer is *once the content settles*, which no
                // door in an update pass can say. See ``putsTheReaderBackAtTheEndOnceTheContentHasSettled(_:)``, on the clock.
                guard asItWas.heightOfWhatCanBeSeen != asItIsNow.heightOfWhatCanBeSeen else { return }
                theGeometry.theSpaceBelowTheMessagesChanged(from: asItWas, to: asItIsNow)
            }
    }

}
