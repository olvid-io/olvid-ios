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
import os.log


/// Everything Step 60 adds to the discussion screen: the blur over the transcript, the copy of the message travelling down to the composition bar, and the tap
/// on the background that puts it all away.
///
/// **A modifier of its own**, for the reason ``TheContextMenuOfAMessageOnThisScreen`` is one: inlined, the screen's body has already been large enough once for
/// the Swift type checker to give up on the whole expression and name none of the part that had grown.
///
/// **Applied *before* the composition bar is inserted into the safe area, where the context menu's is applied after.** That one line of difference is what puts
/// the bar on top of the blur rather than under it, which is what legacy achieves with
/// `insertSubview(replyToContainerView, belowSubview: composeMessageContainerView)` — and it matters: the reader is meant to write into that bar while the
/// message sits above it, so the bar must be sharp, tappable and unblurred throughout.
struct TheMessageBesideTheCompositionBarOnThisScreen: ViewModifier {

    /// The state machine, owned by the screen. A binding rather than a value because the screen writes it and this reads it, and both must see the same one.
    @Binding var besideTheBar: TheMessageBesideTheCompositionBar

    /// The one flag every visible movement hangs on. Read only: it is the screen that sets it, inside the single animation the eye sees.
    let theMessageIsDown: Bool

    /// Whether the copy is still in the air, which the screen learns from the journey's own animation. See ``TheMessageHeldBesideTheCompositionBar/whereTheJourneyEnds``.
    let theCopyIsStillOnItsWayDown: Bool

    /// The rows of the discussion, watched for the one case that leaves this with nothing to give back: the message being deleted while it is down.
    let cellIdentifiers: [SingleDiscussionView.CellIdentifier]

    /// Laid out around the copy so that it is laid out in the environment the rows are, for the reason ``TheContextMenuOfAMessageOnThisScreen`` gives at length:
    /// a copy laid out in a *different* environment from its original drifts wherever the two differ.
    let whereTheReaderWantsToGo: WhereTheReaderWantsToGo

    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    /// Puts the message back — what a tap on the background asks for, and what Esc asks for before it asks anything else on this screen.
    let dismiss: () -> Void

    /// Takes it away without animating anything, there being nothing left to animate.
    let dismissAtOnce: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func body(content: Content) -> some View {
        content
            // The anchors resolve in the space of the view this is attached to, which is why the `GeometryReader` and the anchors meet here and not in two places.
            .overlayPreferenceValue(WhereTheMessagesAre.self) { whereTheMessagesAre in
                GeometryReader { proxy in
                    // A `Group`, and not a container: with nothing down this must contribute no subview at all.
                    if let beside = besideTheBar.whatTheOverlayHasTaken, let anchor = whereTheMessagesAre[beside.cellIdentifier] {
                        TheMessageHeldBesideTheCompositionBar(
                            model: beside.model,
                            whereTheMessageCameFrom: proxy[anchor],
                            within: proxy.size,
                            spaceAboveTheMessages: proxy.safeAreaInsets.top,
                            spaceBelowTheMessages: proxy.safeAreaInsets.bottom,
                            down: theMessageIsDown,
                            stillOnItsWayDown: theCopyIsStillOnItsWayDown,
                            handedOver: beside.handedOver,
                            pulledAcrossBy: beside.pulledAcrossBy,
                            theWayItIsLeaving: besideTheBar.theWayItIsLeaving,
                            dataSource: dataSource,
                            actions: actions,
                            dismiss: dismiss)
                        .environment(\.whereTheReaderWantsToGo, whereTheReaderWantsToGo)
                    }
                }
            }
            // Whatever this stands on, changing under it — the geometry, or the message itself being deleted while it is down.
            //
            // **`task(id:)` and not `onChange(of:)`**, which in the two-closure form that reports the old value is iOS 17 while this module is iOS 16. It fires
            // once on appearance as well, with nothing down, which the guard inside makes a no-op.
            .task(id: whatThisStandsOn) {
                guard besideTheBar.isUp else { return }
                dismissAtOnce()
            }
    }


    private var whatThisStandsOn: WhatThisStandsOn {
        .init(horizontalSizeClass: horizontalSizeClass,
              verticalSizeClass: verticalSizeClass,
              theMessageIsStillInTheDiscussion: besideTheBar.whatTheOverlayHasTaken.map { cellIdentifiers.contains($0.cellIdentifier) } ?? true)
    }


    private struct WhatThisStandsOn: Equatable {
        let horizontalSizeClass: UserInterfaceSizeClass?
        let verticalSizeClass: UserInterfaceSizeClass?
        let theMessageIsStillInTheDiscussion: Bool
    }

}


// MARK: - The arc


/// The path the copy of the message travels on between its row and the composition bar — Step 60's ornament, added 2026-08-27 at the reader's asking.
///
/// **One number animates, and it is the same number that animated before: how far down the message is.** Everything else — the lean to one side, the swell — is a
/// *function* of that number rather than a second animated quantity. That is the whole design and it was chosen over the obvious alternative, which is a progress
/// value from 0 to 1 with the position interpolated along a Bézier from it.
///
/// **Why not progress.** Step 60's first walk proved that the destination re-resolves *mid-flight*: the composition bar grows its quote panel eighteen
/// milliseconds after the journey begins, and `goesTo` went 579.7 → 509.7 while the message was in the air. With position derived from progress, a destination
/// that moves by 70pt at the halfway mark moves the *message* by 35pt in a single frame — the retarget stops being free and becomes a visible snap. Deriving the
/// ornament from the position instead inverts which quantity pays: the position stays continuous and retargets exactly as it did before, and all a re-resolved
/// destination can perturb is how far along the arc this thinks it is, which is worth a point or two of lean. **The fragile quantity should be the decorative
/// one.**
///
/// **And it is symmetric for nothing.** The way out sets `down` back to false, so the copy travels back up to its row — see
/// ``TheMessageBesideTheCompositionBar/theWayOut``, whose documentation describes a fade instead and is wrong about it. An ornament keyed on *progress* would need
/// to know which way it was going, and the shape of that mistake is known: an animation given a `delay` plays it in both directions, so a staggered
/// entrance becomes an absurd exit. An ornament keyed on *position* has no direction to get wrong. The message bows out on the way down and bows back on the way
/// up because it is at the same height both times.
private struct TheArcTheMessageTravelsOn: ViewModifier, Animatable {

    /// **The animated quantity, and the only one.** Where the top of the copy is, in the overlay's coordinate space.
    var howFarDownItIs: CGFloat

    /// The two ends of the journey, so that ``howFarDownItIs`` can be read as a fraction of it. Not animated: they are re-resolved by the layout, and a change of
    /// either mid-flight is meant to be felt in the ornament rather than in the position.
    let theRowItCameFrom: CGFloat
    let theBandBesideTheBar: CGFloat

    /// Where the message sits across the view at both ends of its journey — the lean is added to this and comes back to nothing.
    let whereItSitsAcross: CGFloat

    /// How far across the copy **starts**, and relaxes out of over the journey — nought whenever there is nothing to relax.
    ///
    /// A swipe lets go of the message eighty-odd points from its row, and the copy is placed over the message rather than over the row. The same shape as
    /// ``relaxesOutOf`` and for the same reason: one more function of the position this already interpolates, so the copy comes back across as it descends
    /// rather than snapping across in the frame it is placed.
    let startsAcrossFrom: CGFloat

    /// How far it leans at the midpoint, signed, and zero for a reader who has asked for less movement.
    let leansBy: CGFloat

    /// How much it swells at the midpoint, as a fraction, and zero for the same reader.
    let swellsBy: CGFloat

    /// The scale the copy **starts** at and relaxes out of over the journey, and 1 whenever there is nothing to relax.
    ///
    /// The context menu hands its copy over at the scale it was drawing it: `1.04` for a message that fitted its band, less for one it had to shrink. Rather than
    /// snapping to the natural size, the copy settles into it as it descends — which costs nothing, being one more function of the position this already
    /// interpolates rather than a second animated quantity.
    let relaxesOutOf: CGFloat

    /// The anchor both scales are taken about: the **top of the message's near edge**, which is what the context menu's own lift uses. They must be the same
    /// anchor or the handover would be a visible jump, a scale about two different points putting the same box in two different places.
    let aboutTheTopOfItsNearEdge: UnitPoint

    /// **`nonisolated`, which is not decoration.** `ViewModifier` is a main-actor-isolated protocol, so a type conforming to it is isolated and every stored
    /// property with it; `Animatable` is not, and SwiftUI interpolates this from wherever it pleases. Without the annotation the build fails outright —
    /// *"conformance of 'TheArcTheMessageTravelsOn' to protocol 'Animatable' crosses into main actor-isolated code and can cause data races"* — and it is safe to
    /// give because this is a value type holding a `CGFloat`: interpolation reads and writes a copy, and nothing here touches shared state.
    nonisolated var animatableData: CGFloat {
        get { howFarDownItIs }
        set { howFarDownItIs = newValue }
    }

    func body(content: Content) -> some View {
        content
            // **`scaleEffect` before `offset`, and never after**, and this is exactly the shape that rule was learnt on: `offset` moves what is
            // drawn and leaves the layout frame behind, so an anchor resolved afterwards is resolved against the position the view *has not* been moved to. The
            // context menu's card had precisely this and grew out of a point somewhere else entirely, further away the further down the screen it was.
            .scaleEffect(theScaleItIsDrawnAt, anchor: aboutTheTopOfItsNearEdge)
            .offset(x: whereItSitsAcross + startsAcrossFrom * (1 - howFarAlong) + leansBy * howFarFromEitherEnd, y: howFarDownItIs)
    }


    /// The swell of the travelling and the relaxation of the handover, in one number because they are one `scaleEffect` about one anchor.
    ///
    /// Both are functions of the position and both are 1 at the end of the journey, so the copy is at exactly its rendered size wherever it comes to rest —
    /// which is what keeps ``TheMessageBesideTheCompositionBar/howMuchItSwellsInFlight``'s promise true of the handover as well.
    private var theScaleItIsDrawnAt: CGFloat {
        let theSwell = 1 + swellsBy * howFarFromEitherEnd
        let theRelaxation = 1 + (relaxesOutOf - 1) * (1 - howFarAlong)
        return theSwell * theRelaxation
    }


    /// Nought at both ends of the journey and one in the middle, so that whatever is multiplied by it is an ornament of the travelling and never of the resting.
    ///
    /// A half-sine, which is the cheapest curve with that property and has no corner at the peak. Both ornaments share it, so what the reader sees is one
    /// movement with two aspects rather than two movements that happen to coincide.
    private var howFarFromEitherEnd: CGFloat {
        sin(CGFloat.pi * howFarAlong)
    }


    /// How far along the journey the message is, clamped.
    ///
    /// The clamp is what keeps the spring's overshoot honest: ``TheMessageBesideTheCompositionBar/theJourneyDown`` is damped hard but not critically, so this can
    /// be handed a value a point or so past the band, and without the clamp `sin` would turn that into a lean back the *other* way at the very end of the
    /// movement.
    ///
    /// **Two ends that coincide answer *arrived*, not *not started*** — the last message of a discussion already sitting where it is going has no journey to be
    /// partway along, so everything written as relaxing over the journey must read as fully relaxed. Both ornaments are nought either way, `sin` vanishing at
    /// both ends, which is why this was harmless until ``startsAcrossFrom``: nought there would have left the copy resting beside the bar still carrying the
    /// whole of the pull, eighty points to the side, for exactly the message a reader is likeliest to answer.
    ///
    /// **And the bound is numerical rather than perceptual, because that answer is not free.** `1` also discards ``startsAcrossFrom`` and ``relaxesOutOf``, so a
    /// journey caught by this guard draws the copy at its row's x rather than where the swipe left it. A bound wide enough to catch a journey that is merely
    /// *short* therefore reintroduces the jump it exists to prevent — and short journeys grow: the band drops some seventy points one render after the copy is
    /// placed, so a copy caught at half a point would snap to its row and spring straight back out to the pull. A hundredth of a point is what it takes not to
    /// divide by nought, and nothing else.
    private var howFarAlong: CGFloat {
        let theWholeJourney = theBandBesideTheBar - theRowItCameFrom
        guard abs(theWholeJourney) > 0.01 else { return 1 }
        // Clamped, so a row that moves under a journey this short is bounded at either end rather than read as a position far outside it.
        return min(1, max(0, (howFarDownItIs - theRowItCameFrom) / theWholeJourney))
    }

}


// MARK: - What is drawn


/// The blur over the discussion, and the copy of the message on its way down to the composition bar.
///
/// **The copy is the very same views the cell draws**, as Step 21b's is and for the same reason: two renderings of one definition cannot drift apart, where a
/// copy written here would drift the first time a bubble changed.
private struct TheMessageHeldBesideTheCompositionBar: View {

    let model: SingleDiscussionCellView.Model

    /// Where the message is in the transcript, resolved live from its anchor. Read for the journey's starting point and, once ``down`` is true, for nothing at
    /// all: the copy's position is then the band's, so the transcript may move underneath — and it does, the composition bar having just grown a quote panel —
    /// without the copy following it.
    let whereTheMessageCameFrom: CGRect

    /// **The content area, and its bottom edge is already the top of the composition bar** — which is the correction of 2026-08-27 and the whole of Step 60's
    /// first walk.
    ///
    /// The first version subtracted ``spaceBelowTheMessages`` from this as well, on the reasoning that a proxy reports the *frame* and the insets have to be taken
    /// off it by hand. It does not: what it reports here is the size **after** the safe area has been taken off, and the insets are reported beside it as what was
    /// removed. So the bar's space was counted twice — the message landed exactly `spaceBelowTheMessages` too high and the blur stopped exactly that far short of
    /// the bar, leaving a band of sharp transcript above it.
    ///
    /// **The proof is arithmetic and it is in the walk's log**: `within + spaceBelow` came out at **758.0 on both readings** — 674 + 84 before the quote panel
    /// appeared and 604 + 154 after it — so the two are one constant split in two, and the screen being 874 tall puts the 116 that is missing in the status bar and
    /// the navigation bar above. This is what measuring what the layout ends up with, rather than trusting what was asked for, is worth; the probe below
    /// existed for exactly this doubt and settled it in one run.
    let within: CGSize

    /// What the status bar and the navigation bar take off the top, so the blur can be **extended** up behind them rather than **moved** up in front of them.
    ///
    /// The first version wrote `ignoresSafeArea(.all, edges: .top)`, which does the second: the blur kept its height and slid up by this much, so it ended that
    /// much short at the bottom on top of the fault above. It matters because the transcript scrolls *under* the navigation bar, which is glass — so an unblurred
    /// strip up there shows sharp messages through it.
    let spaceAboveTheMessages: CGFloat

    /// What the composition bar, its margin and whatever the system keeps below them come to — **read as one quantity, never composed from named parts**.
    ///
    /// That rule was paid for on this screen: the space below the messages was written as *bar*, then *bar + home indicator*, and was
    /// exact on a Mac, 20pt short on an iPad and 333pt short with a keyboard up. A list of parts cannot be known to be complete.
    ///
    /// **Nothing is *placed* from it, and one thing is *sized* from it**: the blur covers the whole of this screen, which is this much further down than
    /// ``within`` reaches. It is also what made the first walk's double-counting legible, the error being exactly this number on both readings.
    let spaceBelowTheMessages: CGFloat

    /// The one flag the eye sees: false places the copy where its journey begins, true takes it to the bar.
    let down: Bool

    /// Whether the copy is still in the air: ``down`` says where it is going, this says whether it has got there. What it decides is whether the destination is
    /// held or read — see ``whereTheJourneyEnds`` — and whether the swipe's sideways start is still read at all.
    let stillOnItsWayDown: Bool

    /// What the context menu handed over, if this is Step 64's way in rather than a swipe — see ``TheCopyTheMenuHandsOver``. It decides three things and only for
    /// the journey **down**: where that journey starts, that the blur is already up rather than fading in, and the scale the copy relaxes out of.
    let handedOver: TheCopyTheMenuHandsOver?

    /// How far across its row the message was drawn when a swipe let go of it — see ``TheMessageBesideTheCompositionBar/Beside/pulledAcrossBy``. Nought for
    /// every other way in, and given to the arc only for the journey **down**: a copy going home must land in the row and never back beside it.
    let pulledAcrossBy: CGFloat

    /// How the copy is going, or nil while it is not going at all — see ``TheMessageBesideTheCompositionBar/TheWayItLeaves``.
    ///
    /// It answers two questions and they are not the same one. **That it is leaving** is what tells a ``down`` of false *going* from a ``down`` of false
    /// *returning*; without it a copy handed over would travel back to the menu's lifted position instead of to its row. **Which way it is leaving** is what
    /// separates a reader cancelling from a send: the first flies the copy home, the second leaves it exactly where it is and fades it.
    let theWayItIsLeaving: TheMessageBesideTheCompositionBar.TheWayItLeaves?

    private var leaving: Bool { theWayItIsLeaving != nil }

    /// The shadow the copy casts: whatever it is standing in for at the start, relaxing to ``TheShadowAHeldMessageCasts/whileHeldBesideTheBar`` as ``down``
    /// animates, and back to nothing as it goes home.
    ///
    /// A function of the journey rather than a constant, because the copy is placed exactly over something already on the screen and inside a transaction with
    /// animations disabled: over a real message casting none when a swipe brings it, over the menu's lifted copy at the handover. A constant matched neither —
    /// it snapped at the handover and grew a shadow out of a bare message on a swipe.
    ///
    /// ``down`` is false on the way out as well as on the way in, so the order of the tests is what sends it home to nothing. A departure that fades where it
    /// sits keeps its shadow and fades with it, `down` still being true.
    private var theShadowItCasts: TheShadowAHeldMessageCasts {
        if down { return .whileHeldBesideTheBar }
        if leaving { return .none }
        return handedOver == nil ? .none : .whileLiftedByTheMenu
    }

    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    let dismiss: () -> Void

    /// The destination the journey is actually flying to, which is ``whereTheMessageGoes`` as it stood when this view last took it.
    ///
    /// **Held rather than read, so that a band which moves mid-flight is taken as a new destination and not as a shove** — and only while there is a flight, the
    /// band being read live once the copy has landed. See ``theJourneyTakesItsNewDestination()`` and ``whereTheJourneyEnds``.
    @State private var theDestinationInUse: CGFloat?

    /// **What switches the arc and the swell off entirely**, leaving a straight drop on the shorter curve
    /// ``TheMessageBesideTheCompositionBar/theJourneyDownWithReducedMotion``. Read here rather than passed in, this being the only view that draws them.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Read because ``TheSideAMessageHangsFrom`` is *semantic* — leading or trailing — while a `UnitPoint` and an offset are **absolute**, and the two part
    /// company in a right-to-left layout.
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        ZStack(alignment: .topLeading) {

            theBlurOverTheDiscussion

            theCopyOfTheMessage
                // ``TheSideAMessageHangsFrom/alignment``, which is what the context menu's copy uses — the two must agree or the handover of Step 64 would be a
                // visible shift. A no-op wherever the anchor is already the content's own width.
                .frame(width: whereTheMessageCameFrom.width, height: whereTheMessageCameFrom.height, alignment: side.alignment)
                .modifier(TheArcTheMessageTravelsOn(
                    howFarDownItIs: down ? whereTheJourneyEnds : whereTheJourneyRestsWhenItIsNotDown,
                    theRowItCameFrom: whereTheJourneyBegins,
                    theBandBesideTheBar: whereTheJourneyEnds,
                    whereItSitsAcross: whereTheMessageCameFrom.minX,
                    // **Not switched off by Reduce Motion**, unlike the lean and the swell below. Those are ornaments of the travelling; this is where the copy
                    // actually starts, and nought here would put back the sideways jump at let-go for the reader least able to absorb it.
                    //
                    // **And read only while the copy is in the air**, this term being scaled by `1 - howFarAlong`. Landed, ``TheArcTheMessageTravelsOn/howFarDownItIs``
                    // interpolates where ``TheArcTheMessageTravelsOn/theBandBesideTheBar`` takes its new value at once, so a band moving *down* — a keyboard
                    // dismissed — drops that fraction below 1 and slides a resting copy back towards the pull, tens of points for a message near the bar. The
                    // journey begins in the same turn as the placement, so nothing is taken off the swipe's own start; on iOS 16, which holds no destination
                    // either, it is nought throughout.
                    startsAcrossFrom: (leaving || !stillOnItsWayDown) ? 0 : pulledAcrossBy,
                    leansBy: howFarTheMessageLeans,
                    swellsBy: reduceMotion ? 0 : TheMessageBesideTheCompositionBar.howMuchItSwellsInFlight,
                    relaxesOutOf: leaving ? 1 : (handedOver?.scale ?? 1),
                    aboutTheTopOfItsNearEdge: side.topOfTheNearEdge))
                // Separates the bubble from the blur behind it, which can be close to it in colour. A function of the journey and not a constant — see
                // ``theShadowItCasts``.
                //
                // After the arc, which is the half of matching the menu that naming the numbers does not do. The menu casts its shadow after
                // `scaleEffect(scaleOfTheCopy)`, so its radius and offset are in screen space. Written before the arc the shadow goes inside
                // `theScaleItIsDrawnAt` instead: the two ends then agree on the numbers and still draw `14` against `14 × scale`, a shadow changing by the
                // handover's own 4% in the frame that must be invisible, swelling with the copy in flight and resampling the compositing group's raster. A
                // translation does not affect a shadow, so being after the arc's `offset` as well as its `scaleEffect` costs nothing.
                .casts(theShadowItCasts)
                // Inert, as Step 21b's copy is: a tap that reached it would play a recording or open a photograph from behind the blur, where a tap falling
                // through to the blur behind puts the message back — which is what legacy does too, its snapshot and its blur view both being
                // `isUserInteractionEnabled = false` so that the touch reaches the `HidableView` beneath them.
                // **The one thing a send changes, and the reason the copy needs no journey.** Nought only while fading where it sits; the travelling departure
                // never touches it, the copy arriving in its own row at full opacity exactly as the real message is un-hidden. Written after the arc rather than
                // inside it because opacity is not a function of the position — it is the whole of this departure, where the arc's ornaments are decorations of
                // the other one.
                .opacity(theCopyIsStillShowing ? 1 : 0)
                .allowsHitTesting(false)

        }
        // Nothing behind this exists for VoiceOver while it is up, and the escape gesture puts the message back.
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, dismiss)
        // **The modifier is gated, not only the body.** `.task(id:)` cancels and starts a Task on every change of its id, and this id carries the
        // geometry — so through a keyboard movement it churns a task per frame, which costs more than the line it exists to print.
        #if DEBUG
        .task(id: whatThePlacementRestsOn) { reportsWhatItWasGiven() }
        #endif
        // **The journey keeps one destination for its whole flight** — see ``theJourneyTakesItsNewDestination()``, which is what this screen does instead of
        // letting the band move under an animation already in the air.
        .task(id: whereTheMessageGoes) { theJourneyTakesItsNewDestination() }
    }


    /// What separates the message being replied to from the discussion it came out of.
    ///
    /// **The whole of the view this screen occupies, the composition bar's own region included** — and the bar is nonetheless sharp, tappable and writable,
    /// because that comes from the **z-order** and not from where this stops: the modifier is applied before the bar is inserted into the safe area, so the bar
    /// draws on top of this. Legacy is the same arrangement down to the constraints — `replyToContainerView` is pinned to all four edges of `view` and inserted
    /// `belowSubview: composeMessageContainerView`.
    ///
    /// **The first version stopped at the top of the bar**, giving those two independent things one reason between them, and it cost the third fault of this
    /// family — all three of them on 2026-08-27, this one found on an iPhone 13: an unblurred band across the bottom of the screen. **It is not a mismatch of
    /// colour.** The bar is deliberately given no background — see ``SingleDiscussionView``'s safe-area inset, *"the messages are meant to be seen through the
    /// bar"* — so what that band shows is the transcript's own background, and a message scrolling into it while the reply is up is shown **sharp** through the
    /// glass. It is exactly the fault the first walk found *above* the bar, met below it.
    ///
    /// `.regularMaterial`, which is what Step 21b's backdrop uses — legacy uses `.systemUltraThinMaterialDark`, a hardcoded dark variant. The two treatments on
    /// this screen matching each other was preferred to either of them matching legacy.
    private var theBlurOverTheDiscussion: some View {
        Rectangle()
            .fill(.regularMaterial)
            // The three quantities the proxy split this view into, put back together: up behind the navigation bar and down behind the composition bar. **Not a
            // guess at what the screen is made of** — the rule against composing a quantity from named parts is about a list that cannot be known to be
            // complete, where this is the *inverse* of a decomposition the proxy performs, and the first walk's own two readings confirm it to the point:
            // `116 + 604 + 154` and `116 + 674 + 84` are both 874, the height of the iPhone 17 it was measured on.
            //
            // A height and an offset rather than `ignoresSafeArea`, which slides a view of fixed height into the safe area instead of growing it into it — and
            // rather than a `Shape` left to size itself, which in a `ZStack` would size the stack and carry the copy's placement with it.
            .frame(height: spaceAboveTheMessages + within.height + spaceBelowTheMessages)
            .offset(y: -spaceAboveTheMessages)
            // **Already opaque when the message was handed over**. The context menu's own backdrop is taken away in the very same frame this appears,
            // and both are `.regularMaterial`, so a swap at full opacity cannot be seen where a **crossfade could**: two materials over one another are visibly
            // darker than either, which is why this is a swap and not a fade.
            .opacity(theBlurIsUp ? 1 : 0)
            .onTapGesture { dismiss() }
    }


    @ViewBuilder
    private var theCopyOfTheMessage: some View {
        Group {
            switch model {
            case .sentMessage(let model):
                SentMessageCellView.MessageItself(model: model, dataSource: dataSource, actions: actions)
            case .receivedMessage(let model):
                ReceivedMessageCellView.MessageItself(model: model, dataSource: dataSource, actions: actions)
            case .systemMessage(let model):
                SystemMessageCellView.MessageItself(model: model)
            }
        }
    }


    /// Where the journey begins: the message's own row **as it is drawn**, or wherever the context menu had carried its copy to.
    ///
    /// Read **only** while going down. See ``whereTheJourneyRestsWhenItIsNotDown`` for the other half, and ``leaving`` for why one flag cannot serve both.
    ///
    private var whereTheJourneyBegins: CGFloat {
        whereTheMessageCameFrom.minY + (handedOver?.carriedBy ?? 0)
    }


    /// Where the copy sits when it is not down, which is **two different places**: the start of the journey on the way in, and the message's own row on the way
    /// out. A copy handed over must go home to the row and never back to the menu's lifted position, which it has no business remembering.
    private var whereTheJourneyRestsWhenItIsNotDown: CGFloat {
        leaving ? whereTheMessageCameFrom.minY : whereTheJourneyBegins
    }


    /// Whether the copy is drawn at all.
    ///
    /// Only ``TheMessageBesideTheCompositionBar/TheWayItLeaves/fadingWhereItSits`` ever takes it away, and it does so over the same ``theWayOut`` the blur fades
    /// on — so what the reader sees on a send is one thing dissolving rather than two things moving.
    ///
    /// **The real message is given back in the same frame this starts**, so the fade here and the message reappearing in its row are one crossfade rather than a
    /// gap followed by a pop — see ``TheMessageBesideTheCompositionBar/asTheMessagesSeeIt``, which is where that is decided and why it is safe here of all
    /// places.
    private var theCopyIsStillShowing: Bool {
        theWayItIsLeaving != .fadingWhereItSits
    }


    /// Whether the blur is showing. Up with the journey, or up **from the first frame** when the menu handed its own backdrop over, and down on the way out.
    private var theBlurIsUp: Bool {
        guard !leaving else { return false }
        return down || handedOver != nil
    }


    /// Which side this message hangs from — `SingleDiscussionCellView.Model.theSideItHangsFrom`, which already existed and which the context menu's lift already
    /// uses for its own anchor. Reached for here after a first version of the arc had reinvented it, badly.
    private var side: TheSideAMessageHangsFrom {
        model.theSideItHangsFrom
    }


    /// How far the message leans on its way, signed: positive is to the right of where it started, negative to the left.
    ///
    /// **Toward the middle of the view, whichever side it hangs from**, and scaled down for a short journey. See
    /// ``TheMessageBesideTheCompositionBar/theWidestLean`` for why inward rather than outward, and
    /// ``TheMessageBesideTheCompositionBar/howMuchOfTheDropTheLeanMayBe`` for why it is a fraction of the drop rather than a constant.
    private var howFarTheMessageLeans: CGFloat {
        guard !reduceMotion, let onTheLeft = theMessageHangsFromTheLeftOfTheView else { return 0 }
        let theWholeDrop = abs(whereTheMessageGoes - whereTheJourneyBegins)
        let theWidest = min(TheMessageBesideTheCompositionBar.theWidestLean,
                            theWholeDrop * TheMessageBesideTheCompositionBar.howMuchOfTheDropTheLeanMayBe)
        // Inward is away from the side it hangs from, which is the whole of the lean's direction.
        return onTheLeft ? theWidest : -theWidest
    }


    /// Which side of the view the message hangs from, resolved to an absolute one. Nil for a message that hangs from neither.
    ///
    /// **The correction of the Catalyst walk, 2026-08-27.** The first version compared the anchor's own centre with the view's, and its stated virtue was that it
    /// needed to know nothing about *sent* or *received*. That avoidance is exactly what broke it: **the anchor is not the bubble but a full-width container
    /// holding it** — measured on a Mac at `1098×42`, and a one-line message is not eleven hundred points wide. Such a container is centred by construction, so
    /// the comparison is borderline on every platform and its answer can flip from frame to frame; in the same log a window resize took the width from 1098 to
    /// 644 with both sides of the comparison moving together.
    ///
    /// Two things rested on it, and both were wrong rather than merely imprecise. The lean's direction was arbitrary. And the swell, anchored at `UnitPoint(x: 0)`
    /// of a 1098-wide container, **slides** a trailing-hung bubble sideways by 3% of that width — some thirty points — instead of growing it.
    ///
    /// Asking the model is correct *and* robust to the container: a bubble hugs its own side of one, so a swell anchored at that side grows the bubble almost in
    /// place whatever the container's width turns out to be. The lesson is the one this screen keeps re-learning from the other direction — a geometric test that
    /// needs no domain knowledge is elegant only while the geometry means what you assumed.
    private var theMessageHangsFromTheLeftOfTheView: Bool? {
        let theLeadingEdgeIsOnTheLeft = layoutDirection == .leftToRight
        switch side {
        case .leading: return theLeadingEdgeIsOnTheLeft
        case .trailing: return !theLeadingEdgeIsOnTheLeft
        case .centre: return nil
        }
    }


    /// Where the message comes to rest: its bottom edge ``TheMessageBesideTheCompositionBar/howFarAboveTheBar`` above the top of the composition bar.
    ///
    /// Clamped at the top rather than scaled, which is where this and the context menu part company: 21b divides a band between a message and a card and scales
    /// the message to what is left, because a menu the reader cannot reach is useless. Here there is nothing under the message to be pushed off the screen, so a
    /// message taller than the space simply starts at the top of it — which is what legacy does, its snapshot being pinned at its rendered size with no scale
    /// anywhere in `addMessageViewForReplyIfNeeded(from:)`.
    private var whereTheMessageGoes: CGFloat {
        // ``within`` **is** the distance down to the composition bar; nothing of the space below the messages is subtracted here. See ``within``.
        let theBottomOfTheBand = within.height - TheMessageBesideTheCompositionBar.howFarAboveTheBar
        return max(0, theBottomOfTheBand - whereTheMessageCameFrom.height)
    }


    /// **DEBUG INSTRUMENT.** Nothing outside a debug build: the `.task(id:)` that drives it is gated too, that modifier restarting a Task on every
    /// change of its id and this id carrying the geometry.
    ///
    /// The two numbers this whole placement rests on are ``within`` and ``spaceBelowTheMessages``, and neither was known before it was built: what a
    /// `GeometryReader` inside an `overlayPreferenceValue` reports for the *safe area* — with the composition bar inserted into it by a later modifier — is
    /// exactly the kind of quantity this screen has been wrong about repeatedly, and the rule it learnt is to measure what the layout actually ends up with
    /// rather than trust what was asked for. So this says what it was given, on the way in and on the way out, whether or not anything looks wrong.
    /// **Everything the report is about**, so the probe follows the geometry and not only the flag.
    ///
    /// **`band` and `goesTo` are two numbers on purpose**: the first is where the copy would go if it read the layout, the second where it is actually flying.
    /// They agree except while the destination is held, which is the window every retargeting question is about — reporting only one of them describes the copy
    /// correctly in every case but the one being diagnosed.
    ///
    /// The first version was `task(id: down)`, which fires twice per reply and then never again — so the walk's log held the values at the *instant the journey
    /// began* and none of the values it rested at. That is what made the first reading of it confusing: the entry pair was `674/84`, taken before the quote panel
    /// had appeared, while the message was actually placed from the resting pair `604/154`. A probe that reports a moving quantity must be keyed on the quantity.
    #if DEBUG
    private var whatThePlacementRestsOn: WhatThePlacementRestsOn {
        .init(down: down, inTheAir: stillOnItsWayDown, within: within.height, above: spaceAboveTheMessages, below: spaceBelowTheMessages, goesTo: whereTheMessageGoes)
    }


    private struct WhatThePlacementRestsOn: Equatable {
        let down: Bool
        /// Keyed on as well as reported: landing changes which of the two destinations is flown to without the band moving at all, so a probe watching the
        /// geometry alone would never report the frame the copy stops being held.
        let inTheAir: Bool
        let within: CGFloat
        let above: CGFloat
        let below: CGFloat
        let goesTo: CGFloat
    }
    #endif


    /// Where the journey is flying to: the destination it took while it is still in the air, and the band itself once it has landed.
    ///
    /// **The hold is for the flight and for nothing else.** A band that moves under an animation already in the air is *added* to the copy's position rather than
    /// retargeting it, which is the 70pt shove the quote panel used to give it — so in the air the copy flies to what it last took. Landed, the copy is not
    /// moving at all and what moves the band is the keyboard or a line added to the draft: read live, the copy is carried by that animation, where a destination
    /// of its own runs a spring of ours a frame behind it and trails the bar the whole way down.
    ///
    /// **A copy that is leaving keeps whatever it had**, which is what stops a send — the quote panel dropping as the reply is consumed — from sliding a copy
    /// that is meant to fade where it sits.
    private var whereTheJourneyEnds: CGFloat {
        guard stillOnItsWayDown || leaving else { return whereTheMessageGoes }
        return theDestinationInUse ?? whereTheMessageGoes
    }


    /// Takes a new destination, **inside an animation of its own**.
    ///
    /// The band moves one render after the copy is placed — a reply grows the composition bar's quote panel, which shortens the content area, measured as
    /// `623.7 → 553.7` on 2026-09-20. Read straight off the layout, that change reaches ``TheArcTheMessageTravelsOn/howFarDownItIs`` while the journey is
    /// already in the air, and SwiftUI answers it by adding the change to the copy's position rather than by retargeting: the copy was pulled the whole 70pt
    /// **backwards** in one frame, above the message it stood in for, and had to spring out of it.
    ///
    /// Holding the destination in state and moving it here says *this is where you are going now* rather than *you are 70pt further back than you thought*.
    ///
    /// **The first one is not animated**, there being no journey yet to retarget — only a value being learnt.
    ///
    /// **Nothing is retargeted once the copy is leaving.** A send consumes the reply, so the composition bar drops its quote panel and the band moves back down
    /// by the 70pt it moved up — and a copy fading where it sits, which is documented never to move, would spring into the bar's region as it faded.
    private func theJourneyTakesItsNewDestination() {
        guard !leaving else { return }
        guard theDestinationInUse != whereTheMessageGoes else { return }
        // **Recorded rather than moved to whenever there is no journey in the air**, which covers both the value being learnt at placement and every change the
        // band makes after the copy has landed. Nothing reads it then — see ``whereTheJourneyEnds`` — and keeping it current is what gives a departure a fresh
        // value to freeze on.
        guard stillOnItsWayDown, theDestinationInUse != nil else {
            theDestinationInUse = whereTheMessageGoes
            return
        }
        withAnimation(reduceMotion ? TheMessageBesideTheCompositionBar.theJourneyDownWithReducedMotion : TheMessageBesideTheCompositionBar.theJourneyDown) {
            theDestinationInUse = whereTheMessageGoes
        }
    }


    #if DEBUG
    private func reportsWhatItWasGiven() {
        Logger(subsystem: "io.olvid.messenger", category: "TranscriptRule")
            .info("\("beside the bar", privacy: .public) | \(String(format: "down=%@ inTheAir=%@ within=%.1f×%.1f spaceAbove=%.1f spaceBelow=%.1f (within+below=%.1f wholeView=%.1f) cameFrom=(%.1f, %.1f, %.1f×%.1f) beginsAt=%.1f band=%.1f goesTo=%.1f bottomLandsAt=%.1f", down ? "yes" : "no", stillOnItsWayDown ? "yes" : "no", within.width, within.height, spaceAboveTheMessages, spaceBelowTheMessages, within.height + spaceBelowTheMessages, spaceAboveTheMessages + within.height + spaceBelowTheMessages, whereTheMessageCameFrom.minX, whereTheMessageCameFrom.minY, whereTheMessageCameFrom.width, whereTheMessageCameFrom.height, whereTheJourneyBegins, whereTheMessageGoes, whereTheJourneyEnds, whereTheJourneyEnds + whereTheMessageCameFrom.height), privacy: .public)")
    }
    #endif

}
