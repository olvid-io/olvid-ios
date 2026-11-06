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


/// The bottom of a message cell: its date row, and the chip of reactions beside it.
///
/// A `Layout` because the two are not in an ordinary stack — the chip is **taller than the row it sits in**, and rises into the bubble above rather than pushing the
/// date away from it. The legacy cells say that with two constraints on a view added over everything (`ReceivedMessageCell`, `SentMessageCell`):
/// `dateRow.trailing == chip.leading - 8` and `dateRow.bottom == chip.bottom - 2`, mirrored on a sent cell. Those are transcribed here, with one rule added that
/// legacy had no need of.
///
/// **The rule legacy did not need.** Its chip is a fixed 30pt, so it could simply be pinned over everything and forgotten. That fixed height is why nothing in it
/// scales with the reader's text size, and it is the one thing this layout exists to remove: here the chip is as tall as its content wants, the **rise into the
/// bubble stays put**, and whatever the chip needs beyond that is reserved — so the date row moves down instead of being overlapped. At the ordinary text size the
/// row comes out exactly the height it is today, and nothing moves.
///
/// **The rise is derived rather than chosen**, which is worth knowing before anyone changes it. Take the legacy numbers: a date row of `.caption` is about 16pt, the
/// chip's bottom is 2pt below it, and the chip is 30pt — so its top lands 30 - 2 - 16 = 12pt above the top of the date row, which is
/// ``MessageBubbleMetrics/gapAboveTheDateRow`` (2) plus ``MessageBubbleMetrics/verticalInset`` (10) above the bubble's bottom edge. In other words the legacy chip is
/// exactly as tall as it can be **without covering a word of the message**: its top sits on the bubble's bottom inset, where the text ends. That is the rule, and
/// ``MessageReactionsChipMetrics/riseIntoTheBubble`` is those two metrics added rather than a 12.
///
/// It takes exactly two subviews, in this order: the date row, then the chip. The chip is free to be empty — a message with no reactions yet, or one that shows none
/// at all — in which case this behaves as though it were not there.
struct TheDateRowAndItsReactions: Layout {

    /// Which side of the discussion this cell is on, and therefore which edge the date row is pinned to and which way the chip goes: on a message received the date
    /// is at the leading edge and the chip follows it, and on one sent the date is at the trailing edge and the chip precedes it.
    let side: MessageBubbleStyle

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = self.sizes(proposal: proposal, subviews: subviews)
        let widthOffered = proposal.width ?? .infinity
        return CGSize(width: min(sizes.width, widthOffered), height: sizes.height)
    }


    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {

        // **The parent's proposal, and not `bounds.width`.** This is the whole of the chip's `+1` bug, and it is worth saying
        // exactly: the width this layout *reports* is its content width, `dateRow + gap + chip`, so the parent hands that
        // width straight back as `bounds.width` — and a chip proposal derived from it comes out at `bounds.width - dateRow
        // - gap`, which is **precisely the width the chip answered**. The chip is a `ViewThatFits`, so offering it exactly
        // its own ideal width is offering it nothing: any disagreement of a fraction of a point between the two measurement
        // passes and no candidate fits, and then SwiftUI falls back to the **last** one — a single reaction and a `+1`. Two
        // reactions on a message with a screen's width to spare showed one and a `+1`.
        //
        // Measuring with the proposal instead makes the two passes ask the chip the same question, which is what the note
        // below has always claimed and what `bounds.width` quietly prevented.
        //
        // Measured on 2026-08-11, and the numbers are worth keeping because the margin is nil rather than small: for every
        // cell of a real discussion, the width `bounds.width` would have offered came back **exactly** equal to the width
        // the chip had answered — 36.0 against 36.0 for a chip of one reaction, 64.0 against 64.0 for one of two — while
        // the proposal offers 261.67 and 280.33 on the same cells. A `ViewThatFits` asked to fit inside its own ideal width
        // is being asked to fit inside nothing.
        let sizes = self.sizes(proposal: proposal, subviews: subviews)

        // The date row keeps the bottom of the row, whatever the chip does above and below it.
        let xOfTheDateRow: CGFloat
        let xOfTheChip: CGFloat
        switch side {
        case .received:
            xOfTheDateRow = bounds.minX
            xOfTheChip = bounds.minX + sizes.dateRow.width + MessageReactionsChipMetrics.gapFromTheDateRow
        case .sent:
            xOfTheDateRow = bounds.maxX - sizes.dateRow.width
            xOfTheChip = xOfTheDateRow - MessageReactionsChipMetrics.gapFromTheDateRow - sizes.chip.width
        }

        subviews[indexOfTheDateRow].place(at: CGPoint(x: xOfTheDateRow, y: bounds.maxY),
                                          anchor: .bottomLeading,
                                          proposal: .unspecified)

        guard subviews.count > indexOfTheChip else { return }

        // The one place the chip leaves the row: 2pt below it, as in both legacy cells. It lands inside the 4pt of vertical padding every row of
        // `SingleDiscussionCellsListView` carries, so nothing is drawn outside the bounds of the row — which a `List` promises nothing about.
        //
        // Offered the **same width it was measured with**, and not the width it answered: the chip chooses how many reactions to show from what it is proposed, so
        // proposing something else here could have it choose differently at placement than it did at measurement. See the note above `sizes` for what this cost
        // before the two passes agreed.
        subviews[indexOfTheChip].place(at: CGPoint(x: xOfTheChip, y: bounds.maxY + MessageReactionsChipMetrics.dropBelowTheDateRow),
                                       anchor: .bottomLeading,
                                       proposal: .init(width: sizes.widthOfferedToTheChip, height: nil))

    }


    private let indexOfTheDateRow = 0
    private let indexOfTheChip = 1


    /// What the two subviews measure, and what the row therefore is.
    ///
    /// The date row is measured first and at its ideal size — it is the part that must always be readable — and **the chip is offered what is left**. That is what
    /// makes the chip drop its least-used reactions rather than wrap or overflow, and it is why the number it shows depends on the width of the screen and on the
    /// reader's text size rather than on a constant. See ``MessageReactionsChipView``.
    private func sizes(proposal: ProposedViewSize, subviews: Subviews) -> (dateRow: CGSize, chip: CGSize, widthOfferedToTheChip: CGFloat, width: CGFloat, height: CGFloat) {

        let dateRow = subviews[indexOfTheDateRow].sizeThatFits(.unspecified)

        guard subviews.count > indexOfTheChip else {
            return (dateRow: dateRow, chip: .zero, widthOfferedToTheChip: 0, width: dateRow.width, height: dateRow.height)
        }

        let widthOffered = proposal.width ?? .infinity
        let widthLeftForTheChip = max(0, widthOffered - dateRow.width - MessageReactionsChipMetrics.gapFromTheDateRow)
        let chip = subviews[indexOfTheChip].sizeThatFits(.init(width: widthLeftForTheChip, height: nil))

        // A chip with nothing in it takes no space and no gap either, which is the ordinary case: most messages have no reactions.
        guard chip.width > 0, chip.height > 0 else {
            return (dateRow: dateRow, chip: .zero, widthOfferedToTheChip: widthLeftForTheChip, width: dateRow.width, height: dateRow.height)
        }

        let width = dateRow.width + MessageReactionsChipMetrics.gapFromTheDateRow + chip.width

        // The rule this layout exists for: the chip's rise into the bubble is a constant, so a chip taller than the row can absorb makes the *row* taller — the date
        // row moving down — rather than reaching further up over the message.
        let heightTheChipNeeds = chip.height - MessageReactionsChipMetrics.dropBelowTheDateRow - MessageReactionsChipMetrics.riseIntoTheBubble
        let height = max(dateRow.height, heightTheChipNeeds)

        return (dateRow: dateRow, chip: chip, widthOfferedToTheChip: widthLeftForTheChip, width: width, height: height)

    }

}
