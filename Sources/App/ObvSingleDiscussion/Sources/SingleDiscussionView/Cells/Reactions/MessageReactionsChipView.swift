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
import ObvDesignSystem


/// Metrics of the chip of reactions, from `MultipleReactionsView` and the `ReactionView` inside it.
enum MessageReactionsChipMetrics {

    /// `UIFont.systemFont(ofSize: 14)`, the size of an emoji in the legacy chip. Scaled with the reader's text size here, where legacy could not scale it.
    static let emojiSize: CGFloat = 14

    /// `UIFont.systemFont(ofSize: 12, weight: .bold)`, with the rounded design the legacy chip asks for.
    static let countSize: CGFloat = 12

    /// The gap of the legacy chip's stack, between one reaction and the next. An emoji and its own count are **not** separated: legacy pins the two labels edge to
    /// edge.
    static let gapBetweenReactions: CGFloat = 8

    /// The legacy stack's leading and trailing inset within the chip.
    static let horizontalInset: CGFloat = 6

    /// The legacy stack's top and bottom inset. Legacy then overrides the result with a fixed 26pt height; here it is what the height is *made of*, which is what
    /// lets the chip grow with the text inside it.
    static let verticalInset: CGFloat = 4

    /// The pale ring around the chip: legacy draws two rounded rectangles, the inner one inset by 2 on every side.
    static let border: CGFloat = 2

    /// `dateRow.trailing == chip.leading - 8` in both legacy cells.
    static let gapFromTheDateRow: CGFloat = 8

    /// `dateRow.bottom == chip.bottom - 2` in both legacy cells: the chip hangs this far below the row it sits in.
    static let dropBelowTheDateRow: CGFloat = 2

    /// How far the chip reaches up over the bubble — **derived, not chosen**. See ``TheDateRowAndItsReactions``, which shows that the legacy 30pt chip is exactly as
    /// tall as it can be without covering a word: its top lands on the bubble's bottom inset, where the text ends.
    static var riseIntoTheBubble: CGFloat {
        MessageBubbleMetrics.verticalInset + MessageBubbleMetrics.gapAboveTheDateRow
    }

    /// The most reactions the chip will show before it starts cutting, whatever the width available.
    ///
    /// Not the rule — the width is the rule, and this only bounds how many candidate arrangements are measured. See ``MessageReactionsChipView``.
    static let mostReactionsEverShown: Int = 6

    /// How a chip arrives: from nothing, with a pop.
    ///
    /// **One animation, two callers, and that is the point of it being here.** A chip appears in two quite separate ways —
    /// a reaction reaching ``MessageReactionsChipView``'s stream, and a chip being given back once the context menu's
    /// overlay lets go of its message (`HiddenWhileTheOverlayHasThisMessage`) — and the reader cannot tell which of the
    /// two they are looking at, nor should they. Two constants would have drifted the first time either was tuned; this
    /// one was in fact tuned twice before it was hoisted.
    ///
    /// It used to be `response: 0.5, dampingFraction: 0.5`, which settles in something like 0.64s — twice as long as the
    /// overlay's own `theLift` and plainly slow beside it. The overshoot is what makes it read as a landing, so the
    /// damping is kept low and the response shortened: about 0.35s now, which settles roughly when the rest of the
    /// overlay does.
    static let theArrival: Animation = .spring(response: 0.3, dampingFraction: 0.55)

}


/// The reactions a message has, drawn as a chip beside its date row and tucked into the bottom of its bubble — the legacy `MultipleReactionsView`.
///
/// **One line, always.** The reactions arrive sorted by count, most-used first (`ObvReactionsCountViewModel.init`), and the chip shows as many as fit the width
/// ``TheDateRowAndItsReactions`` leaves it, ending with the number of *people* whose reaction it had to leave out. There is no such rule in the legacy screen or in
/// the design sheet: legacy simply lets the chip grow and run off the side of the cell, which nobody notices until a message collects a dozen different emojis.
///
/// The fitting is a `ViewThatFits` over arrangements rather than a measurement, so there is no frame drawn at the wrong width first. The candidates are tried
/// widest-first and it stops at the first that fits, so the ordinary chip of two or three reactions costs one measurement.
struct MessageReactionsChipView: View {

    /// Nil for a message that shows no reactions at all — one the reader has still to ask to see. It draws nothing and follows nothing, and is still handed to the
    /// layout as a subview, which is what keeps the number of subviews the same for every cell.
    let reactions: ReactionsOfAMessage?

    let dataSource: any SingleDiscussionCellViewDataSource

    /// What the reader asks for by tapping the chip: to be shown who reacted.
    let actions: any SingleDiscussionCellViewActions

    /// What this message has been reacted with, as the stream reports it. Empty until it has said anything — and it stays empty for the great majority of messages,
    /// which have no reactions at all.
    @State private var reactionsAndCount: [ObvReactionsCountViewModel.ReactionAndCount]


    init(reactions: ReactionsOfAMessage?, dataSource: any SingleDiscussionCellViewDataSource, actions: any SingleDiscussionCellViewActions) {
        self.reactions = reactions
        self.dataSource = dataSource
        self.actions = actions
        // **Seeded, so that a chip that was already there is drawn on the first frame** — see ``ReactionsOfAMessage/theOnesItAlreadyHad``. `State(initialValue:)`
        // rather than a default, this being a value the stream then owns: the seed sets where it starts and never speaks again, which is the pattern this screen
        // uses everywhere for a view fed by both a seed and a stream.
        _reactionsAndCount = State(initialValue: reactions?.theOnesItAlreadyHad ?? [])
    }

    var body: some View {
        // A container rather than a bare `if`, because it is what carries the stream: a `Group` whose branch is empty has no subview for `.task` to attach to, and
        // the reactions would then never be followed. Empty, it takes no space and the layout treats it as absent.
        // **Tapping it says who reacted**. A `Button` around the whole chip rather than a gesture on it, and
        // `.buttonStyle(.plain)`, without which a button in a `List` row becomes the *row's* button and never fires.
        //
        // No branch on whether there is anything to tap: a chip with no reactions draws nothing, so the button has no area
        // and there is nothing to hit. One shape either way, which is what a row of this list wants.
        Button {
            guard let reactions else { return }
            Task { await actions.userWantsToSeeWhoReactedToAMessage(messageIdentifier: reactions.identifier) }
        } label: {
            theChip
        }
        .buttonStyle(.plain)
        .task(id: reactions?.identifier) { await followsTheReactions() }
    }


    private var theChip: some View {
        VStack(spacing: 0) {
            if !reactionsAndCount.isEmpty {
                ViewThatFits(in: .horizontal) {
                    // Widest first. `nil` shows every reaction there is and no overflow mark; the rest cut to a number and say how many people were cut — except
                    // for a cut that would leave exactly one out, which `chip(showing:)` refuses. If even the last of them does not fit, SwiftUI keeps it — a chip
                    // of one emoji and a count, which is as small as this gets.
                    chip(showing: nil)
                    chip(showing: 6)
                    chip(showing: 5)
                    chip(showing: 4)
                    chip(showing: 3)
                    chip(showing: 2)
                    chip(showing: 1)
                }
                // As the legacy chip appears: from nothing, with a spring. It is drawn outside the flow of the row at the reader's ordinary text size, so nothing
                // moves as it arrives.
                .transition(.scale.combined(with: .opacity))
            }
        }
    }


    /// The chip showing the first `numberOfReactionsShown` reactions, or all of them when nil, with the people it left out counted at the end.
    ///
    /// **A cut that leaves exactly one reaction out is not made.** The overflow mark is as wide as the reaction it stands in
    /// for — `+1` at 12pt against an emoji at 14 — so dropping a single entry buys no width at all and costs the reader the
    /// one thing they wanted to see. Such a candidate is promoted to showing everything, which is a duplicate of the first
    /// candidate and therefore harmless: `ViewThatFits` stops at the first arrangement that fits and never measures the
    /// rest. The consequence is that `+1` can no longer be drawn at all — two entries left out are two people at the least.
    private func chip(showing numberOfReactionsShown: Int?) -> some View {
        let requested = numberOfReactionsShown ?? reactionsAndCount.count
        let shown = Array(reactionsAndCount.prefix(requested >= reactionsAndCount.count - 1 ? reactionsAndCount.count : requested))
        return MessageReactionsChipContentView(
            shown: shown,
            // The number of **people**, and not of emojis: it reads on the same line as the counts beside each emoji, and those are people.
            numberOfFurtherReactions: reactionsAndCount.dropFirst(shown.count).reduce(0, { $0 + $1.count }))
    }


    /// Follows the reactions of this message for as long as the cell is on screen, rather than taking their first count: anyone may react at any moment, and a
    /// reaction is written without the message being touched — so nothing else on this screen would ever say so.
    private func followsTheReactions() async {
        guard let reactions else { return }
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfReactionsCountViewModel(messageIdentifier: reactions.identifier)
            defer { dataSource.finishAsyncStreamOfReactionsCountViewModel(streamUUID: streamUUID) }
            var theFirstOneHasArrived = false
            for await model in stream {
                // **The first value is not a change, and animating it was wrong.** It is this chip *appearing with its
                // cell* — on entering the discussion, or on scrolling back to a message — and there was nothing on screen
                // for it to animate from. A screenful of chips springing out of nothing as a discussion opens reads as the
                // list moving, which is the very thing `SingleDiscussionCellView` refuses to do with its own model for the
                // same reason. Every value after it is a reaction genuinely arriving, somebody having pressed something,
                // and that is worth showing.
                //
                // The first value is often `[]` — most messages have no reactions — and that counts: the reader's own
                // reaction is then the *second*, and springs in as it should.
                guard theFirstOneHasArrived else {
                    reactionsAndCount = model.reactionsAndCount
                    theFirstOneHasArrived = true
                    continue
                }
                withAnimation(MessageReactionsChipMetrics.theArrival) {
                    reactionsAndCount = model.reactionsAndCount
                }
            }
        } catch {
            assertionFailure()
        }
    }

}


// MARK: - The chip itself, for one arrangement of the reactions

private struct MessageReactionsChipContentView: View {

    /// The reactions this arrangement draws, most-used first.
    let shown: [ObvReactionsCountViewModel.ReactionAndCount]

    /// How many people reacted with something this arrangement leaves out, and zero when it leaves out nothing.
    let numberOfFurtherReactions: Int

    /// The legacy point sizes, made to follow the reader's text size — which is the whole reason the chip is laid out rather than pinned. See
    /// ``TheDateRowAndItsReactions``.
    @ScaledMetric(relativeTo: .body) private var emojiSize: CGFloat = MessageReactionsChipMetrics.emojiSize
    @ScaledMetric(relativeTo: .caption) private var countSize: CGFloat = MessageReactionsChipMetrics.countSize

    var body: some View {
        HStack(spacing: MessageReactionsChipMetrics.gapBetweenReactions) {
            ForEach(shown) { reactionAndCount in
                HStack(spacing: 0) {
                    Text(String(reactionAndCount.emoji))
                        .font(.system(size: emojiSize))
                    // A count of one is not written, as in the legacy chip: the emoji alone already says that somebody reacted.
                    if reactionAndCount.count > 1 {
                        count(reactionAndCount.count, prefixedByAPlus: false)
                    }
                }
            }
            if numberOfFurtherReactions > 0 {
                count(numberOfFurtherReactions, prefixedByAPlus: true)
            }
        }
        // Nothing here may ever wrap: what does not fit is dropped by the arrangement, not folded onto a second line.
        .lineLimit(1)
        .padding(.horizontal, MessageReactionsChipMetrics.horizontalInset)
        .padding(.vertical, MessageReactionsChipMetrics.verticalInset)
        // A `Capsule`, which is what the legacy radii amount to: 13 on a 26pt bubble, 15 on the 30pt one around it.
        //
        // The inner fill is the **received** bubble's colour on both sides of the discussion, as in legacy, and it is translucent in dark mode — which is why the ring
        // around it is opaque `systemBackground` rather than a stroke. That is also what separates the chip from the bubble it is drawn over.
        .background { Capsule().fill(Color(AppTheme.shared.colorScheme.newReceivedCellBackground)) }
        .padding(MessageReactionsChipMetrics.border)
        .background { Capsule().fill(Color(UIColor.systemBackground)) }
    }


    private func count(_ count: Int, prefixedByAPlus: Bool) -> some View {
        Text(verbatim: prefixedByAPlus ? "+\(count)" : "\(count)")
            .font(.system(size: countSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color(UIColor.secondaryLabel))
    }

}


#if DEBUG

#Preview {
    // The chip as it is really laid out: beside a date row, over the bottom of a bubble.
    VStack(alignment: .leading, spacing: 24) {
        ForEach([1, 2, 3, 12], id: \.self) { numberOfReactions in
            VStack(alignment: .leading, spacing: MessageBubbleMetrics.gapAboveTheDateRow) {
                MessageBubbleView(style: .received) {
                    Text(verbatim: "A message somebody felt strongly about.")
                }
                TheDateRowAndItsReactions(side: .received) {
                    MessageTimestampView(timestamp: .now)
                    MessageReactionsChipContentView(
                        shown: Array(ObvReactionsCountViewModel.ReactionAndCount.sampleData.prefix(numberOfReactions)),
                        numberOfFurtherReactions: 0)
                }
            }
        }
    }
    .padding()
}

#endif
