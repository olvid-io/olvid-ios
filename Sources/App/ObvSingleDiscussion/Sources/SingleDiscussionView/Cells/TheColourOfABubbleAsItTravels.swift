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


/// The field of blue a message the reader sent travels through: **one ramp anchored to the screen, sampled by every bubble over its own extent** — so the
/// colour moves through the discussion as it is scrolled, and the bottom of one bubble meets the top of the next.
///
/// ## One field, not one colour per bubble
///
/// **This is the whole of the correction made on 2026-09-04.** Until then a bubble was filled with *one* flat colour, taken from where its **midpoint** sat.
/// That is invisible on a one-line message and unmissable on a tall one: a long message was a single blue over its whole height and the short message under it
/// jumped to the blue of a point hundreds of points further down the ramp, a step in the middle of a run of messages that nothing about the messages explained.
/// Apple does not tint bubbles individually — there is one field and each bubble is a window onto it, which is exactly why its bubbles meet.
///
/// **The field is sampled at the two edges and the fill's own alpha does the rest.** ``howFarDownTheScreen(_:whereTheFillIs:_:)`` is affine in y, so a straight
/// top-to-bottom ramp *in the bubble's own space* **is** the field restricted to that bubble. Nothing has to be scaled, offset or positioned in the window: the
/// bubble is drawn twice, filtered at its top edge and at its bottom edge, and the lower draw carries an alpha ramp so that it wins at the bottom and yields at
/// the top. Continuity across bubbles is then by construction rather than by tuning — bubble *n*'s bottom is `f(maxY)` and bubble *n+1*'s top is `f(minY)`, the
/// same function at two values of y 2pt apart within a message and about 8pt apart between cells.
///
/// **Colours are never named**, and that is deliberate. The alternative was to paint a gradient of colours computed from the blue, which means reproducing what
/// `saturation`, `brightness` and `hueRotation` do to a pixel — and the measurement recorded under ``furthestSaturation(inTheScheme:)`` says that is guesswork:
/// from `rgb(33, 91, 203)` the top of the screen measures `48, 106, 201`, where Rec.709 luminance and an additive brightness give `62, 111, 207`. Filtering the
/// fill twice keeps *today's* colours exactly, so the shade at any point of the screen is the shade that was already there. The invariant that follows is worth
/// keeping: **at a bubble's midpoint the field equals the flat colour the effect used to give it**, so a centre pixel must not move.
///
/// **The clamp became per-edge, which is what it always wanted to be.** A message taller than the screen now shows the whole ramp with flat ends, rather than
/// one clamped colour for the lot.
///
/// ## Saturation and brightness together, never one alone
///
/// **`.saturation` is not HSB saturation, and on this blue the two are opposites.** SwiftUI's filter mixes a colour towards **grey of the same
/// luminance**; HSB saturation mixes it towards **white**. On a pale colour they look alike. On this dark blue they do not: measured over a whole
/// screen, the bubble went from `rgb(32, 90, 188)` to `rgb(31, 90, 218)` — red and green did not move at all, being already near that grey, and the
/// whole change landed on the **blue** channel, which carries 7% of the luminance. A change of thirty on the channel the eye weighs least is a change
/// nobody sees, and varying `.saturation` alone was invisible for exactly that reason.
///
/// So `.brightness` puts back the strongest channel that mixing towards grey took away — see ``howMuchOfTheSaturationIsGivenBackAsBrightness``. The
/// result is a pale blue at the top and a deep one at the bottom, with the apparent brightness near constant. **Removing either filter brings the
/// invisible version back.**
///
/// A few degrees of hue ride along, and cannot do much more: past a few degrees a dark blue reads as violet, which is why
/// ``furthestRotation(inTheScheme:)`` is small and ``furthestSaturation(inTheScheme:)`` is the knob that can be turned.
///
/// **Nothing is ever darkened**, which is what makes this safe in dark mode: the top end gets paler rather than the bottom end getting dimmer, so no
/// bubble is taken towards the black page behind it.
///
/// ## Three choices that are load-bearing
///
/// **`visualEffect`, not a computed colour.** It gives a closure the geometry of the view without invalidating layout and without re-evaluating the
/// body of the row. Handing a colour down instead would rebuild cells while the list moves, which is the one thing this screen may not do. Apple
/// demonstrates this exact case in [WWDC24 session 10151](https://developer.apple.com/videos/play/wwdc2024/10151/). It is what makes the two draws affordable:
/// per frame this is two closures of arithmetic instead of one, and no cell is rebuilt by either.
///
/// **Not `scrollTransition`.** Its phases give roughly −1, 0 and 1, which suits something happening at the *edges* of a scroll view, not a difference
/// that grows smoothly down the screen. A `List` also ignores several scroll modifiers in silence already, which is a poor bet to add to.
///
/// **The position is read in `.global`**, not in the scroll view's space. What the eye should notice is where the bubble is *on the screen*, which is
/// what makes the colour appear to stand still while the messages travel through it. Read against the content instead, each bubble would keep its own
/// colour for ever and the effect would disappear.
@available(iOS 17.0, *)
enum TheFieldTheBubblesTravelThrough {

    /// Where a point of a bubble is between the top of the visible area and the bottom of it: **−1 at the top, 0 in the middle, +1 at the bottom**.
    ///
    /// Nothing here may be expensive: it is asked for twice per visible bubble, on every frame of a scroll. It is arithmetic on two numbers, and the only reason to
    /// give it a name is that the numbers deserve explaining rather than being found inline.
    ///
    /// **Asked of a point rather than of the bubble**, since 2026-09-04 — the two edges are what the field is sampled at. It used to read `midY` itself, which is
    /// how one bubble came to have one colour.
    ///
    /// **Centred on the middle of the visible area**, so a point is shifted one way in the upper half and the other way in the lower. Two things follow, and both are
    /// wanted: the effect reads as the colour standing still while the messages travel through it, rather than as the whole discussion drifting one way; and a message
    /// in the middle of the screen is drawn in *exactly* the production blue, so what the reader compares against is still there.
    ///
    /// **Bounded whatever the geometry says.** A bubble is asked about while it is still off the screen, and a message taller than the screen puts its own edges well
    /// outside it, so this is not naturally between −1 and 1. Left unclamped, a bubble scrolled far above would go on turning into colours that are not blue at all.
    /// Clamping each **edge** separately is what draws a very tall message as the whole ramp with flat ends.
    nonisolated static func howFarDownTheScreen(_ yInTheWindow: Double, whereTheFillIs frameInTheWindow: CGRect, _ geometry: GeometryProxy) -> Double {

        // **The visible area if it can be had, and an assumed screen if it cannot.** `bounds(of: .scrollView)` is the honest way to ask how tall the area is that a
        // bubble travels through — but this list is a `List`, which is backed by a `UICollectionView`, and SwiftUI's scroll-related questions are exactly the ones
        // that quietly answer nothing there: `defaultScrollAnchor`, `scrollTargetLayout` and `contentMargins` are all ignored by a `List`
        // already. So there is a fallback, and it is a working one rather than a switch-off. It cannot silently do nothing, which is the failure that would have
        // been hardest to notice — and note what it does *not* break: every bubble takes the same branch, so the field stays continuous either way and only its
        // extent is wrong. That is precisely why the branch is worth a probe rather than an assumption.
        //
        // **The two paths agree by construction**, which is what this being one shared number bought: the fallback used to be expressed in degrees per point and
        // met the measured path only where a clamp happened to catch it — an agreement at the extremes and nowhere in between, and one that would have had to be
        // re-derived for every axis added. Both are a fraction of the way down something now, and the only difference is what that something is.
        // **`bounds(of:)` answers in this view's *local* space**, where the y asked about is in the window's, so the two were subtracted across spaces — the
        // fraction came out shifted by the fill's own global origin, which is nought at the top of the window and grows all the way down the transcript.
        // What that looked like is everything below mid-screen pinned at maximum saturation. Adding the fill's global origin converts the visible area into
        // the window's space, a local Y of nought being the fill's own top. The same mix, and the same correction, as in
        // ``TheSpringEachMessageHangsFrom/howFarFromTheFinger(_:whereTheReaderIsHoldingIt:overWhatDistance:)``.
        let position: Double
        if let visible = geometry.bounds(of: .scrollView), visible.height > 0 {
            let topOfTheVisibleAreaInTheWindow = visible.minY + frameInTheWindow.minY
            position = (yInTheWindow - topOfTheVisibleAreaInTheWindow) / visible.height * 2 - 1
        } else {
            position = (yInTheWindow - Self.halfOfAnAssumedScreen) / Self.halfOfAnAssumedScreen
        }
        return min(max(position, -1), 1)

    }


    /// The blue at one edge of a fill, as the three filters that make it.
    ///
    /// **One function called twice rather than three lines written twice**: the two draws differ in the edge they ask about and in nothing else, and this is what
    /// keeps them from drifting apart.
    nonisolated fileprivate static func theBlue(of fill: EmptyVisualEffect, atThe edge: TheEdgeOfAFill, _ geometry: GeometryProxy, furthestSaturation: Double, furthestRotation: Double) -> some VisualEffect {

        let frameInTheWindow = geometry.frame(in: .global)
        let yInTheWindow: Double = if Self.bothEdgesAskForTheMiddle {
            frameInTheWindow.midY
        } else {
            switch edge {
            case .theTop: frameInTheWindow.minY
            case .theBottom: frameInTheWindow.maxY
            }
        }
        // **One position, three effects.** All three read the same signed number, so they cannot drift apart and a point in the middle of the screen is drawn in
        // exactly the production blue on every axis at once.
        let howFarDown = Self.howFarDownTheScreen(yInTheWindow, whereTheFillIs: frameInTheWindow, geometry)
        return fill
            .saturation(1 + howFarDown * furthestSaturation)
            // **Not a third axis, and not a look of its own**: it puts back exactly what the line above took off the strongest channel, so that what
            // travels is the colour's purity and not its lightness. Applied after the saturation, which is the order these compose in.
            .brightness(-howFarDown * furthestSaturation * Self.howMuchOfTheSaturationIsGivenBackAsBrightness)
            .hueRotation(.degrees(howFarDown * furthestRotation))

    }


    /// **Turned up far past what anybody would ship, so that it can be seen at all.**
    ///
    /// Set to false for the intended look. The reason for the switch rather than for editing the numbers is that the two questions are different: *does this work* is
    /// answered by a colour nobody could miss, and *is this pleasant* by one most people never notice. Answering the first with the second's numbers is how an effect
    /// gets called broken when it was merely subtle.
    ///
    /// **It earned itself on Mac Catalyst, 2026-08-25**, which is the case for keeping it. At the shipping amplitude the effect was invisible
    /// on a Mac — and *invisible* has two explanations, too subtle and not running, which nothing but this switch separates. Turned on, it was
    /// unmissable, so the effect runs and the amplitude is the whole story. See Step 35 in the plan's index for what that decided.
    ///
    /// It exaggerates **both axes**. It no longer has to exaggerate the fallback separately, that path and the measured one now sharing their arithmetic.
    nonisolated static let exaggeratedSoItCanBeSeen = false

    /// **Flattens the field back to one colour per bubble** — both draws ask about the **middle** of the fill — which is what this screen drew before 2026-09-04.
    ///
    /// **It is the A/B against the previous look, and that is now its whole job.** Turning the setting off gives *no* effect at all, which cannot answer the
    /// question a reader's report will raise: whether the colour is too strong because of its *amplitude* or because it became *continuous*, the two having changed
    /// on the same day and only one of them on purpose. See ``furthestSaturation(inTheScheme:)``, which is the knob if the answer is amplitude.
    ///
    /// **It also settled whether SwiftUI's filters work on premultiplied alpha, and they do not: measured 2026-09-04, the two screenshots were identical.** Had they
    /// been, the additive `brightness` of the ramped draw would have survived its alpha and landed at full strength wherever the ramp is, lifting the whole bubble by
    /// as much as 21 levels rather than only its bottom. Redoing that test needs one more line than this switch — leave the lower draw out altogether, so that the
    /// pair of screenshots differs *only* by the compositing — and it must be run on a bubble near the **bottom** of the screen, the error being proportional to how
    /// far down the screen the bubble is and therefore nought in the middle, where the test would pass whatever were true.
    nonisolated static let bothEdgesAskForTheMiddle = false

    /// The most the blue is ever turned, at the very top and the very bottom.
    ///
    /// **Left exactly as it was when saturation was added on 2026-08-28**, and that is the finding rather than an omission: measured against Messages, this was
    /// already at or above Apple's own 6° of total swing. What was wrong was that it had the whole job to itself. See the table above.
    ///
    /// **Dark mode gets less**, and that is not an oversight: the darker blue has less room before a rotation reads as a *different* colour rather than as the same
    /// one differently lit.
    nonisolated static func furthestRotation(inTheScheme scheme: ColorScheme) -> Double {
        switch scheme {
        case .dark: return exaggeratedSoItCanBeSeen ? 60 : 4
        case .light: return exaggeratedSoItCanBeSeen ? 90 : 7
        @unknown default: return exaggeratedSoItCanBeSeen ? 60 : 4
        }
    }

    /// How much more or less saturated the blue is at the very bottom and the very top, as a fraction: `0.15` gives ×0.85 at the top and ×1.15 at the bottom,
    /// with the production blue exactly halfway down the screen.
    ///
    /// **0.15 is Apple's ratio, not a taste.** Messages goes from 52% to 69% saturation down the screen — ×1.33 — which centres on ×0.87 and ×1.15.
    ///
    /// With the brightness above giving back what this takes off the strongest channel, this is what it measures on `rgb(33, 91, 203)`:
    ///
    /// | | top of the screen | bottom of the screen | Apple, same measurement |
    /// |---|---|---|---|
    /// | rgb | 48, 106, 201 | 22, 75, 206 | 119, 194, 247 → 77, 159, 248 |
    /// | saturation | 76% | 89% | 52% → 69% |
    ///
    /// **Less saturated at the top and more at the bottom**, which is Apple's direction and the one that reads correctly: the messages being scrolled towards
    /// are the firmer colour, and the ones travelling away wash out.
    ///
    /// **~~The constant is worth less than half of itself on the screen.~~ Superseded on 2026-09-04, and it is why 0.15 is now right unchanged.** While one bubble
    /// had one colour, what the reader saw was the field sampled at bubble *midpoints*, and those span only about **45%** of the nominal −1…+1 — the topmost sitting
    /// below the navigation bar and the last well above the bottom of the scroll area. So 0.15 was 25 points of saturation at the ends of the range and about 11 on
    /// the screen: it had been measured against Apple's full-screen swing and then applied to less than half of one. A field sampled at the **edges** reaches both
    /// ends, so the constant now delivers what it was calibrated for — which is to say the effect became about twice as strong on the day it became continuous, at
    /// an unchanged number. **Tune against a screenshot, never against the arithmetic.**
    ///
    /// A bolder version exists and was not taken: anchoring the ramp on the bottom rather than centring it, at 0.45, which is what Apple does and which
    /// reached 53% → 71%. Recorded so it need not be rediscovered; it is a matter of taste rather than of correctness.
    ///
    /// Unlike ``furthestRotation(inTheScheme:)`` this has no natural ceiling — a less saturated blue is still blue — so it is the knob to turn. Both schemes
    /// are given the same amount, the ratio being what was measured; the switch is there for when they turn out to want different ones.
    nonisolated static func furthestSaturation(inTheScheme scheme: ColorScheme) -> Double {
        switch scheme {
        case .dark: return exaggeratedSoItCanBeSeen ? 0.6 : 0.15
        case .light: return exaggeratedSoItCanBeSeen ? 0.6 : 0.15
        @unknown default: return exaggeratedSoItCanBeSeen ? 0.6 : 0.15
        }
    }

    /// How much of what ``furthestSaturation(inTheScheme:)`` takes off the blue's strongest channel is handed straight back as brightness.
    ///
    /// **Derived, not chosen.** `.saturation(s)` moves every channel towards the colour's luminance by `1 - s`, so the strongest one — which is what the eye reads
    /// as the colour's brightness — loses `(1 - s) × (strongest - luminance)`. Giving that back leaves the strongest channel where it was and lets the other two
    /// carry the whole change, which is HSB saturation, which is Apple's gradient.
    ///
    /// So this is `(strongest - luminance) / 255` for the Olvid blue, and the two appearances agree closely enough to share one number: **0.54** for `OlvidDark`,
    /// `rgb(0, 68, 200)`, and **0.57** for `OlvidLight`, `rgb(46, 100, 245)`. **Re-derive it if the blue ever changes** — being a few hundredths out is not a
    /// defect, it merely tilts the brightness slightly one way down the screen instead of holding it level.
    ///
    /// It is a few hundredths out, deliberately left so. Against the blue as it is *rendered*, `rgb(33, 91, 203)`, the exact figure is **0.46**, and the difference
    /// shows as the pale end coming out a little brighter as well as a little paler — the strongest channel drifting up by about ten rather than staying pinned.
    /// Whether that reads as air or as a smudge is a thing to look at rather than to calculate; 0.46 is what pins it exactly if it wants pinning.
    nonisolated static let howMuchOfTheSaturationIsGivenBackAsBrightness: Double = 0.55

    /// Used only by the fallback above. Half of a tall phone, so that the middle of the screen is roughly where nothing happens, as it exactly is when the visible
    /// area is known — and so that the top and the bottom of that assumed screen are where the effect reaches its full amount, as they are on the measured path.
    nonisolated static let halfOfAnAssumedScreen: Double = 420

}


/// Which edge of a bubble's fill the field is being sampled at. The ramp between the two is the lower draw's own alpha — see ``TheFieldTheBubblesTravelThrough``.
fileprivate enum TheEdgeOfAFill {
    case theTop
    case theBottom
}


/// A bubble's fill, drawn as its slice of ``TheFieldTheBubblesTravelThrough``.
///
/// **Two draws of one shape, and the lower one carries an alpha ramp.** The upper is opaque and filtered at the top edge; the lower is filled with the same colour
/// fading in from nothing and filtered at the bottom edge, so it wins at the bottom of the bubble and yields at the top. The cross-fade between two finished colours
/// is the field over that bubble, because the field is affine in y.
///
/// **A ramp in the fill rather than a `mask`, and that is the whole reason this owns its shape.** A ramp cannot be imposed on a view that is already filled without
/// masking it, and a mask costs an offscreen composite for every visible sent bubble — the one cost here that grows with the *number* of bubbles rather than with the
/// area of the screen. A `LinearGradient` fill is a native gradient layer and costs nothing of the sort. The price is that this is a view that fills a shape, where
/// it used to be a modifier wrapped round a shape somebody else had filled. If the compositing ever turns out to need the mask after all — see
/// ``TheFieldTheBubblesTravelThrough/bothEdgesAskForTheMiddle`` for the probe that decides it — then a modifier is enough again.
///
/// **`overlay` rather than a `ZStack`**: a `Shape` in a `ZStack` is infinitely flexible and would size the stack to whatever space was offered, where an overlay is
/// sized by the draw beneath it.
///
/// **What two draws cost at the edge, predicted rather than seen.** Stacking two antialiased draws of one silhouette **over-covers its edge pixels**: a pixel the
/// shape covers by `c` ends up covered by `1 - (1 - c)²` where the upper draw is opaque, so a half-covered pixel reads three-quarters covered. Here the upper draw's
/// alpha *is* the ramp, so the excess is nil at the top of a bubble and greatest at the bottom — an edge that gets very slightly harder down each bubble. Three
/// things bound it. It is **one antialiasing pixel**, a third of a point on a 3× screen. The bubble is **already** two stacked draws, the opaque `systemBackground`
/// underlay and the blue, so this is a third rather than a second — though the underlay is invisible against the page it matches, which is why the blue's edge is
/// correct today and this is a new artefact rather than a worse one. And **the remedy is known if it shows**: draw two *rectangles* instead of two shapes, which
/// have no partial coverage of their own, and impose the silhouette **once** with a `mask` over a `compositingGroup`. That buys perfect edges at one offscreen
/// composite per bubble — the cost the ramp exists to avoid, so it is a trade to make on a screenshot and not in advance.
@available(iOS 17.0, *)
struct TheColourOfABubbleAsItTravels<S: Shape>: View {

    /// The silhouette to fill — the bubble's own, so that this draws exactly what the flat fill drew.
    let shape: S

    /// The blue, unfiltered. Never taken apart: the filters do the travelling and this is only ever handed to a fill.
    let colour: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Read **outside** the closures, on purpose and not merely for tidiness: the closure a `visualEffect` takes is `Sendable`, and the appearance is main-actor
        // state, so reaching for it in there is an isolation error rather than a style question. The amounts are settled here; the closures do arithmetic.
        let furthestRotation = TheFieldTheBubblesTravelThrough.furthestRotation(inTheScheme: colorScheme)
        let furthestSaturation = TheFieldTheBubblesTravelThrough.furthestSaturation(inTheScheme: colorScheme)
        return shape
            .fill(colour)
            .visualEffect { fill, geometry in
                TheFieldTheBubblesTravelThrough.theBlue(of: fill, atThe: .theTop, geometry, furthestSaturation: furthestSaturation, furthestRotation: furthestRotation)
            }
            .overlay {
                shape
                    .fill(LinearGradient(colors: [colour.opacity(0), colour], startPoint: .top, endPoint: .bottom))
                    .visualEffect { fill, geometry in
                        TheFieldTheBubblesTravelThrough.theBlue(of: fill, atThe: .theBottom, geometry, furthestSaturation: furthestSaturation, furthestRotation: furthestRotation)
                    }
            }
    }

}


/// Fills a bubble's shape with its slice of ``TheFieldTheBubblesTravelThrough``, or with the flat blue and nothing whatever.
///
/// The branch is here rather than at the call site so that a bubble's body stays one expression, and so that "nothing whatever" is written down once: with the
/// setting off, no `visualEffect` reaches the render tree, the shape is filled exactly once, and a scroll costs exactly what it costs in production.
struct TheColourTravelsIfAsked<S: Shape>: View {

    let asked: Bool
    let shape: S
    let colour: Color

    /// **Off entirely for a reader who has asked for less movement**, as the elastic scroll beside it is.
    ///
    /// Strictly a colour shift is not motion, and a purist would leave it running. What decides it is that the settings
    /// screen tells the reader *why* the switches are inert, and *one of these two is off because of your accessibility
    /// setting and the other is not* is not a sentence anybody can write clearly. The check lives here, where the effect
    /// runs, and the settings screen only reports it — so a mistake there cannot leave this running for somebody who
    /// asked for it to stop.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if asked, !reduceMotion {
            // `visualEffect` is iOS 17, which this file compiles below. Nothing is lost: the list these bubbles are drawn in is iOS 18 already.
            if #available(iOS 17.0, *) {
                TheColourOfABubbleAsItTravels(shape: shape, colour: colour)
            } else {
                shape.fill(colour)
            }
        } else {
            shape.fill(colour)
        }
    }

}


extension EnvironmentValues {

    /// Whether a message sent is drawn in a blue that moves with the scroll. See ``TheFieldTheBubblesTravelThrough``.
    ///
    /// **A setting of the app's, read once when the screen is created** and carried down from there — **on unless somebody has turned it off**, in
    /// Settings ▸ Interface ▸ Scrolling effects, since 2026-08-29. It was a beta-only look before that, and several comments went on saying so for a week; *off* is
    /// what production used to be and is now what a reader has to ask for. It is in the environment rather than in a cell's model for the reason the search term is:
    /// the models are held in an `NSCache` keyed on the message, and this is not a property of any message.
    ///
    /// The key's own default is `false`, and that is not the setting's: it is what a bubble drawn outside this screen gets — a preview, the copy the context menu
    /// lifts before the environment reaches it — where doing nothing is the right answer.
    var sentBubbleHueVariesWithScroll: Bool {
        get { self[SentBubbleHueVariesWithScrollKey.self] }
        set { self[SentBubbleHueVariesWithScrollKey.self] = newValue }
    }

}


private struct SentBubbleHueVariesWithScrollKey: EnvironmentKey {
    static let defaultValue: Bool = false
}



