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


/// The ring drawn over an attachment something long is happening to: turning while there is nothing to measure, then filling.
///
/// One arc throughout, so that the move from turning to filling animates: a spinner swapped for a progress arc would be two views, and the
/// first value would arrive as a jump. The turning state means started but not yet measurable, such as an upload before its first byte or
/// a clip queued behind another's export.
///
/// Here in `ObvDesignSystem` because both the discussion screen and the composition bar draw it, and neither depends on the other.
public struct ObvProgressRing: View {

    private let fractionCompleted: Double?
    private let diameter: CGFloat
    private let lineWidth: CGFloat
    private let fontSize: CGFloat

    /// - Parameter fractionCompleted: nil, or a value of nought, makes the ring turn rather than fill. See ``thePercentage``.
    /// - Parameter fontSize: fixed, and not a text style — see the note on ``thePercentage``. The default suits both callers; it is a
    /// parameter so that a third size does not have to make it a fraction of the diameter, which would be a different decision.
    public init(fractionCompleted: Double?, diameter: CGFloat, lineWidth: CGFloat, fontSize: CGFloat = 11) {
        self.fractionCompleted = fractionCompleted
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.fontSize = fontSize
    }

    /// Turns while there is nothing to report, and unwinds to nought when there is.
    @State private var angleOfTheSpin = Angle.zero

    /// Nothing measurable yet: no value, or a value of nought.
    private var isTurning: Bool {
        (fractionCompleted ?? 0) <= 0
    }

    /// What the arc shows: the turning stub while turning, and the real fraction once there is one.
    private var trim: Double {
        isTurning ? fractionOfTheRingDrawnWhileTurning : min(1, max(0, fractionCompleted ?? 0))
    }

    public var body: some View {
        Circle()
            .fill(TheLookOfTheRing.chosen.disc)
            .frame(width: diameter, height: diameter)
            .overlay {
                Circle()
                    .trim(from: 0, to: trim)
                    .stroke(TheLookOfTheRing.chosen.arc, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    // From twelve o'clock, clockwise, a `Circle` otherwise starting at three.
                    .rotationEffect(.degrees(-90))
                    .rotationEffect(angleOfTheSpin)
                    // Whatever is reported arrives in steps — of a chunk of bytes, of a fifth of a second of an export — and without this
                    // the arc jumps between them. The first step, out of the spinner, is the largest of them.
                    .animation(.easeOut(duration: 0.3), value: trim)
                    .animation(.easeOut(duration: 0.3), value: isTurning)
            }
            .overlay {
                thePercentage
            }
            .task(id: isTurning) {
                if isTurning {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        angleOfTheSpin = .degrees(360)
                    }
                } else {
                    // Stops the endless turn *and* brings the arc back to twelve o'clock, so that what fills is a ring starting where a ring
                    // should. Without this the repeating animation goes on running under the fill.
                    withAnimation(.easeOut(duration: 0.3)) {
                        angleOfTheSpin = .zero
                    }
                }
            }
    }

    /// How far along it is, in words, inside the ring — and **nothing at all while the ring is still turning**: a percentage of nought says
    /// *stuck*, where a turning ring says *starting*.
    ///
    /// The digits roll rather than cut, through `contentTransitionOniOS16(.numericText(value:))` — the same effect this app gives the badge
    /// counting unread messages, `ObvBadgeNumberOfNewMessages`, and the count on a reactions chip. It needs the value to change **inside an
    /// animation** to play, which is what the `animation(_:value:)` below it provides.
    @ViewBuilder
    private var thePercentage: some View {
        // A `Group`, not a container: while the ring turns this must take no space and draw nothing.
        Group {
            if !isTurning, let fractionCompleted {
                let clamped = min(1, max(0, fractionCompleted))
                // **`.formatted(.percent)` rather than a number with a `%` stuck on the end**, which is the difference between `45%` and
                // `45 %`: French puts a space before the sign and English does not, and hard-coding either is wrong in the other. The
                // rolling digits are unaffected, `numericText` being driven by the *value* rather than by the string.
                Text(verbatim: clamped.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .contentTransitionOniOS16(.numericText(value: (clamped * 100).rounded()))
                    // **A fixed size, and not a text style.** The ring around this cannot grow, so a font that grows with Dynamic Type grows
                    // inside a container that does not, and "100 %" leaves the circle at the larger settings. `.system(size:)` does not
                    // scale; `.caption2` does, which is what was here first.
                    //
                    // Not scaling text is normally a fault, and it is defensible here for one reason: the number **repeats what the ring
                    // already shows**. A reader who cannot read 11pt still sees how far along it is, so nothing is withheld from them —
                    // which would not be true of a label that was the only way to know something.
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(TheLookOfTheRing.chosen.arc)
                    .lineLimit(1)
                    // Shrinks rather than truncates. A percentage reading `10…` would be worse than one that is briefly small, and it is
                    // only that wide at the very end — the one moment nobody needs to read it precisely.
                    .minimumScaleFactor(0.6)
                    .frame(width: widthAvailableInsideTheRing)
                    .animation(.easeOut(duration: 0.3), value: clamped)
            }
        }
    }


    /// The widest the number may be: the diameter, less the stroke on both sides, less a little air on both sides.
    ///
    /// **The number is laid out against the ring's *inner* width and not against its frame**, which is the whole of what stops the two
    /// touching. At 50pt there is room to spare and this changes nothing; at the 34pt the composition bar draws, `100 %` runs into the
    /// stroke without it. A ring that is safe at one size and not at another is a trap for whoever picks the third.
    private var widthAvailableInsideTheRing: CGFloat {
        max(diameter - 2 * (lineWidth + Self.airBetweenTheNumberAndTheStroke), 1)
    }

    private static let airBetweenTheNumberAndTheStroke: CGFloat = 3

}


/// How the ring is drawn: white on a dark scrim. The ring sits over any photo, and a scrim is dark whatever the photo and the appearance,
/// so white on it always reads; white on a material would vanish in light mode. The other cases are kept to make trying them easy.
private enum TheLookOfTheRing {

    case accent
    case whiteOnAScrim
    case primary
    case secondary

    static let chosen: TheLookOfTheRing = .whiteOnAScrim

    /// What the arc is drawn in.
    var arc: AnyShapeStyle {
        switch self {
        case .accent: return AnyShapeStyle(Color.accentColor)
        case .whiteOnAScrim: return AnyShapeStyle(Color.white)
        case .primary: return AnyShapeStyle(.primary)
        case .secondary: return AnyShapeStyle(.secondary)
        }
    }

    /// What it is drawn on. **A dark scrim rather than a material for the white candidate**, deliberately: a material follows the appearance,
    /// so white on it disappears in light mode, whereas a scrim is dark whatever the photograph and whatever the appearance.
    var disc: AnyShapeStyle {
        switch self {
        case .whiteOnAScrim: return AnyShapeStyle(Color.black.opacity(0.35))
        case .accent, .primary, .secondary: return AnyShapeStyle(.ultraThinMaterial)
        }
    }

}


/// How much of the ring is drawn while it is turning — enough of a gap in the perimeter to be seen going round, and short of anything a reader could mistake for
/// progress.
///
/// Shared by ``ObvProgressRing`` and the download arc of the discussion screen's attachment control, which draw the same idiom and must agree.
public let fractionOfTheRingDrawnWhileTurning = 0.15


#if DEBUG

/// Both sizes this is drawn at, and the states that are easy to get wrong: nothing to report, nought, and the end.
#Preview {
    VStack(spacing: 28) {
        ForEach([CGFloat(50), CGFloat(34)], id: \.self) { diameter in
            HStack(spacing: 20) {
                ObvProgressRing(fractionCompleted: nil, diameter: diameter, lineWidth: 3)
                ObvProgressRing(fractionCompleted: 0, diameter: diameter, lineWidth: 3)
                ObvProgressRing(fractionCompleted: 0.07, diameter: diameter, lineWidth: 3)
                ObvProgressRing(fractionCompleted: 0.42, diameter: diameter, lineWidth: 3)
                ObvProgressRing(fractionCompleted: 1, diameter: diameter, lineWidth: 3)
            }
        }
    }
    .padding()
    .background(Color.gray)
}

#endif
