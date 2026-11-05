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
import ObvSystemIcon
import OlvidUtils


/// What tapping a message will cost the reader: that it burns once read, and how long they will have with it — the legacy
/// `EphemeralityInformationsView`, and the second half of Step 24b.
///
/// **Not the countdown, which is already built.** ``TheCountdownOfAnEphemeralMessage`` says how much time is *left*, and a message still to be tapped has no
/// visibility clock running, so there is nothing to count. What the reader is missing then is not a number but the terms: read once, and one minute of it.
/// So this exists **only before the tap**, where the countdown is mostly of use after, and both may be on screen at once without saying the same thing.
///
/// **`readingRequiresUserAction` decides it, and nothing else** — as in `ReceivedMessageCell`, which calls `configure` under that test alone. The two flags
/// inside need no test of their own: the property is itself `(readOnce || visibilityDuration != nil) && not yet read`, so a chip that is shown always has at
/// least one thing to say.
///
/// **Received messages only**, as in legacy: a sender knows the terms they chose, and their own message is never waiting to be tapped. The gate is `false`
/// for every sent message anyway, so a sent cell drawing this would show nothing — it does not draw it at all, so that nobody reads its absence as an
/// oversight.
///
/// ## Two deliberate departures from legacy
///
/// **It scales with the reader's text size.** Legacy pins `.caption1` inside a fixed-height chip. This is the **only** way to know these terms — nothing
/// else on this screen says that a message burns when read — so the rule applies in the direction of scaling it, and the chip is made of its
/// content.
///
/// **It does not reach up into the bubble.** The legacy view is drawn 12pt taller than its box and shifted 6pt up, tucking it against the message above.
/// Reproducing that would need a third subview in ``TheDateRowAndItsReactions``, whose contract is two, and a rise measured against a row that is now
/// content-sized rather than a fixed 30pt. So the chip sits in the date row honestly, and a tap-to-read cell is about 6pt taller than the legacy one.
struct WhatWillHappenWhenThisMessageIsRead: View {

    let ephemerality: TheEphemeralityOfAMessage

    var body: some View {
        // A `Group` and not a container: the great majority of messages have nothing to say here, and an empty container would
        // still be given the date row's spacing. See `MessageBodyView`, where six of them once cost 12pt of air.
        Group {
            if ephemerality.readingRequiresUserAction {
                theChip
            }
        }
    }


    private var theChip: some View {
        HStack(spacing: Self.gapBetweenTheTerms) {
            // Each term is a `Text` carrying its symbol as a **glyph**, and not an `Image` beside a `Text`: an image's box is
            // taller than the line of the font it was given, which would make this row taller than a line and put the excess
            // above the baseline the date row is aligned on. See `MessageEditedBadgeView`.
            if ephemerality.readOnce {
                Text(Image(systemIcon: .flameFill))
            }
            if let visibilityDuration = ephemerality.visibilityDuration,
               let formatted = Self.durationFormatter.string(from: visibilityDuration) {
                // `.eyes`, as legacy draws it and as **every** place in the app that means limited visibility draws it:
                // `ExpirationIndicatorView`, the system message of a settings change, the discussion's own settings, the
                // draft's. It is a solid glyph, and denser here than in legacy — which lays it out as a `UIImageView`, whose
                // box is taller than a line of `.caption1`, where this is a glyph on the text's own line. The outline `.eye`
                // is easier to read at this size and is **deliberately not used**: one chip disagreeing with the rest of the
                // app about what limited visibility looks like is the worse fault. There is no third option — SF Symbols has
                // no unfilled relative of `eyes` at all (`CoreGlyphs.bundle/nofill_to_fill.strings` maps `eye` to `eye.fill`
                // and holds no entry for `eyes`) — so this is the icon or the app changes its mind everywhere at once.
                Text(Image(systemIcon: .eyes)) + Text(verbatim: " \(formatted)")
            }
        }
        .font(.caption)
        // The same ink as the date it sits beside, which is what legacy gives both: `.secondaryLabel`.
        .foregroundStyle(MessageTimestampView.foregroundColor)
        .lineLimit(1)
        .padding(.horizontal, Self.horizontalInset)
        .padding(.vertical, Self.verticalInset)
        // A `Capsule`, which is what the legacy 14pt radius amounts to on a chip of this height — the same reading
        // `MessageReactionsChipView` made of its own radii. The fill is translucent in dark mode, which is why the ring around
        // it is an opaque `systemBackground` rather than a stroke: it is what separates the chip from whatever it is drawn
        // against.
        .background { Capsule().fill(Color(UIColor.systemFill)) }
        .padding(Self.border)
        .background { Capsule().fill(Color(UIColor.systemBackground)) }
    }


    /// The 8pt gap of the legacy stack, between the flame and the eye.
    private static let gapBetweenTheTerms: CGFloat = 8

    /// The legacy stack's leading and trailing inset within the inner bubble.
    private static let horizontalInset: CGFloat = 6

    /// The legacy stack's top and bottom inset within the inner bubble.
    private static let verticalInset: CGFloat = 4

    /// The pale ring around the chip: legacy draws two rounded rectangles, the inner inset by 2 on every side.
    private static let border: CGFloat = 2

    /// Made once. A `DateComponentsFormatter` is expensive to build, and the terms of a message do not change while it is on screen.
    private static let durationFormatter = DurationFormatter()

}


#if DEBUG

#Preview {
    // The chip where it really goes: in the date row of a message the reader has still to tap, under the bubble that asks
    // them to. The countdown beside it is the other half of the same step, and the first row is what a message with no
    // limit on its visibility shows — a flame alone.
    VStack(alignment: .leading, spacing: 24) {
        // The offset is a stable identity here only because this sample is a constant that never reorders.
        ForEach(Array(TheEphemeralityOfAMessage.samplesOfAMessageStillToBeTapped.enumerated()), id: \.offset) { _, ephemerality in
            HStack(alignment: .top, spacing: MessageBubbleMetrics.gapWithinTheDateRow) {
                VStack(alignment: .leading, spacing: MessageBubbleMetrics.gapAboveTheDateRow) {
                    MessageBubbleView(style: .received) {
                        Text(verbatim: "Tap to see the message")
                    }
                    HStack(alignment: .firstTextBaseline, spacing: MessageBubbleMetrics.gapWithinTheDateRow) {
                        MessageTimestampView(timestamp: .now)
                        WhatWillHappenWhenThisMessageIsRead(ephemerality: ephemerality)
                    }
                }
                TheCountdownOfAnEphemeralMessage(ephemerality: ephemerality)
            }
        }
    }
    .padding()
}


extension TheEphemeralityOfAMessage {

    /// The three shapes a message still to be tapped comes in: read once, visible for a while, and both — the last of them
    /// also counting an existence down, which is the case where the reader sees the chip and the countdown at once.
    fileprivate static let samplesOfAMessageStillToBeTapped: [Self] = [
        .init(readOnce: true, readingRequiresUserAction: true, visibilityDuration: nil, scheduledVisibilityDestructionDate: nil, scheduledExistenceDestructionDate: nil),
        .init(readOnce: false, readingRequiresUserAction: true, visibilityDuration: 60, scheduledVisibilityDestructionDate: nil, scheduledExistenceDestructionDate: nil),
        .init(readOnce: true, readingRequiresUserAction: true, visibilityDuration: 5 * 60, scheduledVisibilityDestructionDate: nil, scheduledExistenceDestructionDate: Date.now.addingTimeInterval(3 * 3600)),
    ]

}

#endif
