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

import UIKit


/// Notices that the transcript was scrolled with a **notched wheel** rather than with a trackpad or a finger, and tells
/// ``TheSpeedOfTheTranscript`` so that the elastic scroll can stand aside.
///
/// **Why UIKit is asked rather than the numbers.** The first attempt at this read the offsets: a wheel was supposed to move the content a
/// long way in one frame and then not at all, so counting frames with no movement would name it. Measured on Mac Catalyst on
/// 2026-09-01, it does not: **53 of 113 moving frames during a wheel scroll had no gap at all before them**, so there are no notches to
/// count and the arithmetic cannot tell the two devices apart. `UIScrollTypeMask` is UIKit's own distinction and it is not a heuristic.
///
/// **It is asked per scroll event and not per connected device**, which is what the reader asked for — a Mac with both a mouse and a
/// trackpad keeps the effect on the trackpad — and also the only version that can be built honestly: nothing on Catalyst will say
/// whether a pointing device is a mouse or a trackpad.
///
/// **This recogniser must never claim anything, and three separate properties are what make that true rather than likely.** The failure
/// mode being guarded against is *the wheel no longer scrolls the discussion*, which is far worse than an ugly effect, and what a
/// UIKit recogniser added beside another can do to it is known at length — a `UIDragInteraction` took the long press that opens the
/// context menu, and nothing about it looked wrong. So:
///
/// - `gestureRecognizerShouldBegin` returns **false, always**. The recogniser records what it came to record and then fails, so it never
///   enters the recognised state and never has an event to consume.
/// - `cancelsTouchesInView`, `delaysTouchesBegan` and `delaysTouchesEnded` are all off, so nothing downstream waits on it.
/// - `shouldRecognizeSimultaneouslyWith` returns true, so nothing else has to lose for it to be offered the event.
///
/// **And `allowedScrollTypesMask` is set explicitly, because the default is nothing at all.** Measured on the same run: a freshly
/// constructed `UIPanGestureRecognizer` reports `allowedScrollTypesMask == 0`. A bare probe would therefore have seen **no scroll events
/// whatever** and reported that a wheel had never been used — the silent-instrument trap this project has been caught by more than once,
/// and precisely the thing `the-elastic-scroll.md` said to read off the device rather than assume.
///
/// **`allowedScrollTypesMask` says nothing about touches, and the first version of this took the effect off the iPhone entirely.** A pan
/// recogniser receives touches whether or not it is allowed any scroll types, so on a phone *every finger drag* called
/// `gestureRecognizerShouldBegin` and was recorded as a wheel — and the reader found the effect gone on an iPhone 13 within a minute of
/// the walk. **The Mac hid it completely**, there being no touches on that platform at all, which is the same shape as Mac
/// Catalyst hiding the drag-versus-long-press collision for a fortnight: a platform with no fingers cannot show you what you
/// have done to fingers.
///
/// It is refused twice over now, deliberately, because one of the two is a framework behaviour that would otherwise be assumed:
///
/// - `allowedTouchTypes` is set **empty**, which is the counterpart of the scroll-types mask and should mean no touch ever reaches this.
/// - and `numberOfTouches` must be **nought** for anything to be recorded, which is what a scroll event looks like and what a finger
///   never does. Measured on the Mac: the scroll view's own pan reported `0touch` on every frame of a wheel scroll.
///
/// The second is what makes this correct even if the first turns out not to work the way its documentation reads.
@MainActor
final class TheProbeThatNoticesAWheel: UIPanGestureRecognizer, UIGestureRecognizerDelegate {

    /// **The screen this probe belongs to.** It reports to *that* screen's springs and to no other.
    ///
    /// It reached `TheSpeedOfTheTranscript.shared` until 2026-09-02. One bank of springs between two live discussions is the defect Step 67
    /// is about, and this was one of its two feeds: a wheel used on one screen would have stood the effect down on the other.
    ///
    /// **The screen rather than the springs, and that is what keeps this simple**: ``TheSpeedOfTheTranscript`` does not exist below iOS 17, so
    /// holding one would need the same erasure ``TheGeometryOfTheTranscriptReadPerFrame`` carries, where the screen itself can simply be held.
    /// `weak`, a gesture recogniser outliving nothing.
    private weak var theGeometryItReportsTo: TheGeometryOfTheTranscriptReadPerFrame?

    /// Puts one of these on a scroll view, unless one is already there.
    ///
    /// **Re-asserting rather than installing once**, in the shape `TakesWhateverIsDroppedOnTheMessages` uses for the drop delegate: this
    /// is called on every entry to the discussion, with the same scroll view six times over, so it has to be safe to say repeatedly. The
    /// marker is the class itself, which is also what lets the sweep take off this feature's recogniser and nobody else's — the lesson of
    /// finding 3.
    static func installsItself(on scrollView: UIScrollView, reportingTo theGeometry: TheGeometryOfTheTranscriptReadPerFrame) {
        // **An existing probe is pointed at the caller rather than left alone.** The guard below used to return outright, which was
        // right while there was one bank of springs in the process to report to. Now that each screen owns its own, a probe left holding a
        // screen that has gone would report to nobody at all — and the reference being `weak`, it would do it *silently*, which is the way
        // this screen has lost behaviour more often than any other. Re-pointing it costs one assignment on a path that already runs six times
        // per entry.
        if let alreadyThere = (scrollView.gestureRecognizers ?? []).compactMap({ $0 as? TheProbeThatNoticesAWheel }).first {
            alreadyThere.theGeometryItReportsTo = theGeometry
            return
        }
        let probe = TheProbeThatNoticesAWheel()
        probe.theGeometryItReportsTo = theGeometry
        probe.delegate = probe
        // **Discrete only.** A continuous scroll — a trackpad, a Magic Mouse — is exactly the case that keeps the effect, so there is
        // nothing to learn from being told about one.
        probe.allowedScrollTypesMask = .discrete
        // **No touches, ever** — see the note on the type for what leaving this at its default cost on an iPhone.
        probe.allowedTouchTypes = []
        probe.cancelsTouchesInView = false
        probe.delaysTouchesBegan = false
        probe.delaysTouchesEnded = false
        scrollView.addGestureRecognizer(probe)
    }


    /// **Always false, and the recording is the point.** UIKit asks this when the recogniser is about to recognise, which for a scroll
    /// event is the moment that event arrives — before the scroll view has moved the content, and therefore before the display link
    /// reads the movement. So the answer is known for the *first* notch of a scroll rather than from the second onwards.
    nonisolated func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        MainActor.assumeIsolated {
            if #available(iOS 17.0, *) {
                // **The touch count goes over rather than being tested here**, so that the refusal and the recording are decided and
                // reported in one place — see ``TheSpeedOfTheTranscript/theWheelProbeWasAsked(withTouches:)``. The first version of this
                // tested it here and said nothing, and a silence is what let a phone lose the effect with nothing in the log to say why.
                theGeometryItReportsTo?.theSpeedOfThisTranscript.theWheelProbeWasAsked(withTouches: gestureRecognizer.numberOfTouches)
            }
        }
        return false
    }


    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                       shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

}
