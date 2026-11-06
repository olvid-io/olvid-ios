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
// **Explicitly, though the file compiled without it.** `contentTransitionOniOS16` has always come from here, and was visible only through
// Swift's leaking of one file's imports to the rest of its module — which the language is in the process of taking away. ``ObvProgressRing``
// now comes from here too.
import ObvDesignSystem
import ObvSystemIcon


/// The control shown on an attachment whose file is not here: it says where the attachment stands, and downloads or pauses it.
///
/// Two rules decide everything it shows:
///
/// - **the arc says how much of the file exists**;
/// - **the glyph says what a tap will do**.
///
/// From which "paused at 30%" falls out without being a state of its own — a paused attachment is one waiting to be asked for that happens to have bytes
/// already, so it keeps its arc and offers to resume.
struct AttachmentStateControl: View {

    let phase: AttachmentState.Phase

    /// How much of the file exists, or nil while nothing has been said about it. The arc follows this and nothing else — which is what makes a paused download
    /// keep the arc it had, since a pause changes the phase and not the bytes.
    let fractionCompleted: Double?

    let act: (AttachmentAction) -> Void

    /// `MessageCellConstants.attachmentIconSize` on the legacy screen.
    ///
    /// **Not private since Step 63's second pass**: the circled play glyph of a video whose file is here is drawn at exactly this, because it stands in for *this*
    /// circle — see ``ImageAttachmentView/thePlayGlyph(phase:)``. Two constants that must agree are one constant.
    static let diameter = CGFloat(50)

    private static let lineWidth = CGFloat(3)

    /// The size of the glyph inside the circle. Fixed, for the reason written where it is used, and equal to `.title3` at the default Dynamic
    /// Type setting so that the control is unchanged for anyone who has not asked for larger text.
    private static let glyphSize = CGFloat(20)

    /// Turns for as long as the engine has not answered.
    ///
    /// **It outlives the arc it turns**, which is the whole of the trap: the arc is drawn only while a download is in flight, and this state belongs to the
    /// control around it. So it is driven from ``theEngineHasNotAnsweredYet`` rather than from the arc's own `onAppear` — see there.
    @State private var angleOfTheSpin = Angle.zero

    /// Whether the arc should be turning: the reader has asked, and nothing can yet be said about how far along it is.
    ///
    /// **Two phases and not one.** `.downloading` with no bytes yet is exactly as unmeasurable as `.askedToDownload`, and calling it measurable would take the
    /// trim to nought — a hairline that reads as *stalled* where a turning stub reads as *starting*. ``ObvProgressRing`` draws the same line in the same place, for
    /// the same reason.
    private var theEngineHasNotAnsweredYet: Bool {
        switch phase {
        case .askedToDownload:
            return true
        case .downloading:
            return (fractionCompleted ?? 0) <= 0
        default:
            return false
        }
    }

    /// What the arc of a download in flight shows: the turning stub while there is nothing to measure, and the real fraction once there is.
    private var theTrimOfTheDownloadArc: Double {
        theEngineHasNotAnsweredYet ? fractionOfTheRingDrawnWhileTurning : min(1, max(0, fractionCompleted ?? 0))
    }

    /// How the arc settles: out of the spinner, and between the chunks the bytes arrive in. ``ObvProgressRing`` uses the same, being the same movement.
    private static let theWayTheArcSettles = Animation.easeOut(duration: 0.3)

    var body: some View {
        // A single-root container so that this view stays *unary* whichever branch is taken.
        ZStack {
            switch phase {
            case .available:
                EmptyView()
            case .cancelledByServer:
                circle {
                    Image(systemIcon: .exclamationmarkCircle)
                }
            case .downloadable:
                // Paused rather than untouched when there are already bytes, which the arc says and the glyph does not: both offer to fetch the file.
                circle {
                    Image(systemIcon: .arrowDownToLine)
                }
                .overlay { arcSoFar }
                .onTapGesture { act(.resumeDownload) }
            // **One branch and one arc for both**, since 2026-08-31. They were two, identical but for the overlay — a turning stub for one and a progress arc for
            // the other — and the swap between them was a *jump*: two different views, with nothing for SwiftUI to animate between. It is only visible when the
            // first bytes arrive quickly, which is the common case on a fast connection, and it reads as the arc snapping backwards. `ObvProgressRing` had the same
            // fault and the same fix, and its doc paragraph is where the reasoning is written out.
            case .askedToDownload, .downloading:
                circle {
                    Image(systemIcon: .pauseFill)
                }
                .overlay { theArcOfADownloadInFlight }
                .onTapGesture { act(.pauseDownload) }
            case .uploading:
                // **The arc and nothing else**: no glyph to press, because an upload can be neither asked for nor paused. Legacy draws
                // the same ring over the thumbnail for `uploadableOrUploading`, and offers no control there either.
                // **The circle is drawn here rather than through `circle(glyph:)`, and that is not a style choice.** Passing `EmptyView()`
                // as the glyph — an upload has nothing to press — made the whole control disappear: a modifier applied to `EmptyView` is
                // **discarded**, because `EmptyView` contributes no view to the tree. So the `frame` and the `background` inside
                // `circle(glyph:)` were both dropped, there was no 50pt box for the arc to be painted into, and the arc was drawn into
                // nothing. Every other case here passes a real `Image`, which is why only this one vanished.
                //
                // It cost four wrong diagnoses to find, all of them from reading rather than looking: the number was proven to reach this
                // branch with a real fraction while nothing at all was on the screen. What settled it was drawing something opaque.
                ObvProgressRing(fractionCompleted: fractionCompleted, diameter: Self.diameter, lineWidth: Self.lineWidth)
            case .leftBehindByAHistoryTransfer:
                // **No arc and no tap**, as on the legacy screen, where this control has `isUserInteractionEnabled = false`: there is nothing to fetch and no
                // progress to report. The glyph is legacy's `repeatCircle` — the file is elsewhere, and bringing it over means transferring the history again.
                circle {
                    Image(systemIcon: .repeatCircle)
                }
            case .knownOnlyFromANotification:
                // Legacy's `networkSlash`, and no tap: the attachment becomes downloadable by itself once the message it belongs to arrives.
                circle {
                    Image(systemIcon: .networkSlash)
                }
            }
        }
        // On the control rather than on the spinner, so that it is still here to be told when the spinner has gone. See ``theSpinIsDrivenByThePhase()``.
        .task(id: theEngineHasNotAnsweredYet) {
            await theSpinIsDrivenByThePhase()
        }
    }

    /// `.primary` and not white, which is what this was.
    ///
    /// A material adapts to the colour *scheme*, never to what happens to be behind it: in light mode it is light whether it sits on a photograph or on the pale
    /// fill of a document card. A white glyph on it is therefore legible over a photograph and invisible over a card — which is exactly what happened. `.primary`
    /// turns dark or light with the material, so the pair is legible over anything.
    private func circle<Glyph: View>(@ViewBuilder glyph: () -> Glyph) -> some View {
        glyph()
            // **A fixed size, and not `.title3`.** The circle below is a fixed 50pt — legacy's `attachmentIconSize` — so a glyph that grows
            // with Dynamic Type grows inside a container that cannot, and at the larger accessibility sizes the pause, the arrow and the
            // exclamation mark leave their circle. 20pt is what `.title3` measures at the default setting, so nothing changes for a reader
            // who has not asked for larger text.
            //
            // The same argument as for the percentage, and the same justification: every one of these glyphs says something the *arc and the
            // control's presence* already say — that an attachment is waiting, going, or never coming — so a reader who needs larger text is
            // not being denied information, only a smaller drawing of it. Were the whole control to grow instead, the tile it sits on would
            // have to grow with it, and that is the picture, not a control.
            .font(.system(size: Self.glyphSize))
            .foregroundStyle(.primary)
            .frame(width: Self.diameter, height: Self.diameter)
            .modifier(TheDiscAGlyphOverAnAttachmentSitsOn())
            // **The whole disc answers the tap, said outright rather than inherited from whatever draws behind the glyph.**
            //
            // This is the defect the reader found on a Mac on 2026-08-27: the download control stopped starting a download. `.frame(50, 50)` around a 20pt glyph
            // does **not** make the margin tappable — a gesture applied to a layout container reaches the subviews' own shapes, not the box. What made the disc
            // tappable was the `.background(.ultraThinMaterial, in: Circle())` that used to be here: a filled `Circle` is hit-testable, so the material was
            // quietly serving as the tap target. Replacing it with `glassEffect`, which is a visual effect rather than a filled shape, left only the glyph's ink —
            // some 20pt of arrow inside 50pt of circle — so a click a few points off centre reached nothing.
            //
            // The lesson is not about glass. **A hit area that comes from a decoration is an accident**, and it survives exactly as long as nobody changes the
            // decoration; this one had been an accident since the control was written and was found the day the decoration changed. Said explicitly, it no longer
            // depends on what is drawn.
            .contentShape(Circle())
    }

    /// How much of the file exists, and nothing at all while that is unknown or nought — an empty arc and a full circle of background are the same picture, and
    /// a hairline at zero reads as a download that has stalled rather than one that has not begun.
    @ViewBuilder
    private var arcSoFar: some View {
        if let fractionCompleted, fractionCompleted > 0 {
            arc(upTo: fractionCompleted)
                // The bytes arrive in steps of whatever a chunk is; without this the arc jumps between them.
                .animation(.linear(duration: 0.2), value: fractionCompleted)
                .allowsHitTesting(false)
        }
    }


    /// How much of the file exists.
    ///
    /// **Inert**, both arcs and at their one definition, so that neither overlay site can forget it. They are drawn *above* the disc — an `overlay` is — and a
    /// stroked `Shape` is hit-testable along its stroke, so the ring of a paused download was a ring of decoration lying over the thing that answers the tap.
    /// Cheap, correct, and it removes a whole class of suspicion from the defect of 2026-08-27 rather than arguing about how wide a stroke has to be to matter.
    private func arc(upTo fraction: Double, in colour: some ShapeStyle = .primary) -> some View {
        Circle()
            .trim(from: 0, to: fraction)
            .stroke(colour, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
            // From twelve o'clock, clockwise, a `Circle` otherwise starting at three.
            .rotationEffect(.degrees(-90))
    }

    /// The one arc of a download in flight: a gap in the perimeter turning while there is nothing to measure, then the same gap unwinding to twelve o'clock and
    /// filling. **One view throughout**, which is what lets those two be a movement rather than a swap — see the branch that draws it.
    ///
    /// **The turn is not started here**, and that is the first half of the fix of 2026-08-31. It was, from an `onAppear`, and the second appearance drew an arc
    /// that did not turn: ``angleOfTheSpin`` belongs to the control and this arc does not, so by the time the arc came back the angle was already `.degrees(360)`
    /// and `onAppear` wrote 360 over 360 — a change of nothing, which animates nothing. See ``theSpinIsDrivenByThePhase()``.
    private var theArcOfADownloadInFlight: some View {
        arc(upTo: theTrimOfTheDownloadArc)
            .allowsHitTesting(false)
            .rotationEffect(angleOfTheSpin)
            // The bytes arrive in steps of whatever a chunk is; without this the arc jumps between them — and the first step, out of the turning stub, is the
            // largest of them. That first step is why this is an ease rather than the linear 0.2s the paused arc used before the two branches became one.
            .animation(Self.theWayTheArcSettles, value: theTrimOfTheDownloadArc)
            .animation(Self.theWayTheArcSettles, value: theEngineHasNotAnsweredYet)
    }


    /// Turns the arc while the engine has not answered, and **puts the angle back when it has** — which is what makes a second appearance turn like the first,
    /// and what stops the endless turn once there is a real fraction to draw.
    ///
    /// ``ObvProgressRing`` is the model, down to the animated unwind: the arc *stays* and fills, so it must come back to twelve o'clock as part of
    /// the same movement rather than snapping there. Writing `.zero` outright would end the `repeatForever` just as well and would look like a flinch.
    ///
    /// **Applied to the control and not to the arc**, deliberately: the arc exists only in one branch of the phase, so a `.task` on it would never see the phase
    /// leave and the `else` would never run — the same shape of mistake as the `onAppear` this replaces.
    private func theSpinIsDrivenByThePhase() async {
        if theEngineHasNotAnsweredYet {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                angleOfTheSpin = .degrees(360)
            }
        } else {
            withAnimation(Self.theWayTheArcSettles) {
                angleOfTheSpin = .zero
            }
        }
    }

}


#if DEBUG

#Preview {
    VStack(spacing: 24) {
        ForEach(Array([AttachmentState.Phase.downloadable, .askedToDownload, .downloading, .cancelledByServer, .leftBehindByAHistoryTransfer, .knownOnlyFromANotification].enumerated()), id: \.offset) { _, phase in
            AttachmentStateControl(phase: phase, fractionCompleted: 0.3, act: { _ in })
                .frame(width: 120, height: 120)
                .background(Color.secondary.opacity(0.3))
        }
    }
    .padding()
}

#endif


// MARK: - The disc a glyph sits on


/// The 50pt disc under a glyph drawn over an attachment: the download control's, and the play glyph of a video whose file is here.
///
/// **One disc used twice, which is the point rather than tidiness.** When a video finishes uploading, `AttachmentStateControl` draws `EmptyView()` and goes;
/// the play glyph then brings this disc, at the same ``AttachmentStateControl/diameter``, so what the reader sees is a ring becoming a disc rather than one
/// thing leaving and another arriving. Two drawings of that circle could not stay equal.
///
/// **Glass from iOS 26**, following ``TheCircleOfTheButtonBackToTheEnd``. It fixes a real defect: on a Mac in dark mode the download control's disc **could
/// not be seen at all**. The cause is not dark mode by itself — it is `.ultraThinMaterial` over the *flat* placeholder of a video with no file yet,
/// `Color.secondary.opacity(0.15)`, which differs almost not at all in luminance **and has no edge**. The glyph is `.primary` so it showed; the disc did not.
/// Glass carries its own specular edge whatever is behind it, which is what was missing.
///
/// **Before iOS 26 the material stays and gains an edge**, the smallest thing that fixes the cause: the fill was never the problem, the boundary was.
/// Thickening the material would have changed this control over every attachment on the screen to fix one case.
///
/// **`interactive()` was tried and withdrawn**, and it is the prime suspect for a defect found within the hour: on a Mac, tapping the control that downloads
/// an attachment stopped starting the download — on one image and on several, so the fault is this control rather than anything around it.
///
/// The mechanism is a known one, met here from the other side: a UIKit interaction takes the press before a SwiftUI gesture sees it, and interactive
/// glass exists precisely to answer a press. Where it works in this module — ``TheCircleOfTheButtonBackToTheEnd`` — it sits inside a `Button`, so the button
/// owns the gesture and the glass only decorates it. Here the gesture is an `onTapGesture` on the view *around* this modifier.
///
/// **So the glass stays and `interactive()` goes.** What was wanted was an edge that can be seen, which plain glass gives; the press was never handled by
/// glass before, so withdrawing it restores the interaction exactly as it was while keeping the fix. The option not taken is to make this control a real
/// `Button` and let interactive glass decorate its style — the arrangement glass is designed for, but a wider change to something drawn over every
/// attachment, and a `Button` in a `List` row needs `.buttonStyle(.plain)` or it never fires. Worth doing deliberately, not while
/// chasing a regression.
struct TheDiscAGlyphOverAnAttachmentSitsOn: ViewModifier {

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                // The edge the material does not have. `.separator` rather than a hand-mixed opacity: it is the colour the system uses for exactly this and it
                // turns with the scheme, where a fixed one would be the same fault in the other direction.
                //
                // **And it must not be hit-testable**, which is the second fault of the same afternoon: an `overlay` sits *above* the content, so a decorative
                // shape drawn over a 50pt control is a decorative shape drawn over the thing that answers the tap. It was written without this and would have
                // taken the download button away on every system older than 26 — where the glass branch above hid it from the walk entirely.
                .overlay {
                    Circle()
                        .strokeBorder(Color(UIColor.separator), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
        }
    }

}
