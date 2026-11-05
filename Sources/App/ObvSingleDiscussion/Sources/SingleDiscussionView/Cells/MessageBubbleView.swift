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
import ObvSystemIcon
import OlvidUtils


/// Metrics of the cells of a discussion. These values are those of the legacy screen, see `MessageCellConstants` within the app.
enum MessageBubbleMetrics {

    /// `MessageCellConstants.BubbleView.largeCornerRadius`, given to every corner that faces the outside of a message.
    static let cornerRadius: CGFloat = 14

    /// `MessageCellConstants.BubbleView.smallCornerRadius`, given to the corners where two parts of **one message** meet — see
    /// ``TheColumnOfPartsOfAMessage``.
    ///
    /// **The comment that used to be here said something else**, and it was wrong in a way worth recording: it claimed this radius was for "the corners facing the
    /// neighbours of a message within a run of consecutive messages", a feature legacy does not have and nobody has built. Legacy's rule is *within a cell* —
    /// `mainStack.shownArrangedSubviews` are the parts of one message — and reading the comment instead of the code sent the first attempt at this step in the wrong
    /// direction entirely.
    static let smallCornerRadius: CGFloat = 4

    /// `MessageCellConstants.bubbleHorizontalInsets`
    static let horizontalInset: CGFloat = 12

    /// `MessageCellConstants.bubbleVerticalInset`
    static let verticalInset: CGFloat = 10

    /// A bubble never takes more than this fraction of the width available to a cell, as in `ReceivedMessageCell`.
    static let maxWidthRatio: CGFloat = 0.8

    /// The shape of a bubble, and of everything drawn as one — a reply header among them.
    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// Every corner rounded to ``cornerRadius``: what a part standing alone is shaped like, and the value anything drawn outside a message's own column keeps.
    static var allCornersRounded: RectangleCornerRadii {
        .init(topLeading: cornerRadius, bottomLeading: cornerRadius, bottomTrailing: cornerRadius, topTrailing: cornerRadius)
    }

    /// The shape of one part of a message, given the corners it is to have — see ``EnvironmentValues/cornersOfThisPartOfTheMessage``.
    ///
    /// `.continuous`, as every other shape on this screen is: the two styles are visibly different at 14pt, and a part joining another must not change smoothness
    /// as well as radius.
    static func shape(_ corners: RectangleCornerRadii) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: corners, style: .continuous)
    }

    /// `MessageCellConstants.mainStackGap`, used between a bubble and the date below it.
    static let gap: CGFloat = 2

    /// The gap of the horizontal stack holding the date, the edited mark and, on a message sent, its status — 6pt in both legacy cells.
    static let gapWithinTheDateRow: CGFloat = 6

    /// The air between the content of a message and the date under it, which is the legacy 2pt — the same as ``gap``, and kept separate all the same.
    ///
    /// It is separate because it was the first thing suspected when the space under a bubble read as far too large, and it was innocent: what was there was **six**
    /// empty containers, one for each part a message did not have, each taking a gap of its own from the cell's stack. See ``MessageBodyView``. Once that was gone the
    /// legacy value turned out to be right after all, which is worth knowing before anyone tunes this again.
    ///
    /// So, in order: nothing here should ever be negative, and a gap that looks wrong is almost certainly something in the row reserving space it does not draw —
    /// either a container with nothing in it, or an `Image` taller than the line it sits on, which is what ``MessageEditedBadgeView`` explains.
    static let gapAboveTheDateRow: CGFloat = 2

}


/// Keeps its content within a fraction of the width it is offered, and lets it be as narrow as it likes.
///
/// A `Layout` rather than a measurement, because the width available *is* the width proposed: there is nothing to measure, nothing to publish through the
/// environment, and no first frame laid out at a default width before the real one arrives.
///
/// Not `containerRelativeFrame(_:count:span:spacing:)`, which sets an *exact* width and would make every bubble the same width whatever it contains.
struct AtMostAFractionOfTheOfferedWidth: Layout {

    let fraction: CGFloat

    private func proposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        guard let width = proposal.width else { return proposal }
        return ProposedViewSize(width: width * fraction, height: proposal.height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        return subview.sizeThatFits(self.proposal(proposal))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        subview.place(at: bounds.origin, anchor: .topLeading, proposal: self.proposal(proposal))
    }

}


/// Whether a bubble is drawn as one of the reader's own messages or as one they received.
///
/// Declared here rather than nested in ``MessageBubbleView``, which is generic over its content: a type nested in a generic one is parameterised by it, so
/// `MessageBubbleView<A>.Style` and `MessageBubbleView<B>.Style` are different types and neither can be named by a view that merely wants to pass a style on.
enum MessageBubbleStyle {

    case sent
    case received

    var backgroundColor: Color {
        switch self {
        case .sent: return Color(AppTheme.shared.colorScheme.adaptiveOlvidBlue)
        case .received: return Color(AppTheme.shared.colorScheme.newReceivedCellBackground)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .sent: return Color(UIColor.white)
        case .received: return Color(UIColor.label)
        }
    }

    /// A link in the body, and a mention, are drawn in this — white on a message sent, the system's blue on one received, which is what `withStyleForLinks` gives
    /// them on the legacy screen. Underlining comes with it there; here `Text` underlines a link of its own accord.
    var foregroundColorOfALink: Color {
        switch self {
        case .sent: return Color(UIColor.white)
        case .received: return Color(UIColor.systemBlue)
        }
    }

}


/// The rounded container of the content of a sent or received message.
///
/// **Its fill is laid over the page's own colour**, which makes the bubble opaque, and that is not cosmetic: the received bubble's colour is `systemFill` in dark mode
/// — a translucent white — so anything drawn *behind* the bubble showed through it, and where the two overlapped the two alphas added up to a pale seam. That is what a
/// reply header tucked under a bubble looked like. Over the page and over nothing else the composite is unchanged, so this is invisible everywhere else.
struct MessageBubbleView<Content: View>: View {

    let style: MessageBubbleStyle
    @ViewBuilder let content: () -> Content

    /// Whether a message sent shifts its blue with where it sits on the screen. Off unless it has been turned on among the beta options.
    @Environment(\.sentBubbleHueVariesWithScroll) private var sentBubbleHueVariesWithScroll

    /// Whether *this* bubble does: only a message the reader sent, a hue rotation on the grey of a message received reading as a colour cast rather than as a shimmer.
    private var theColourTravels: Bool {
        sentBubbleHueVariesWithScroll && style == .sent
    }

    /// Which corners this bubble joins to another part of the same message, if any — see ``TheColumnOfPartsOfAMessage``. Fully rounded unless a cell says otherwise.
    @Environment(\.cornersOfThisPartOfTheMessage) private var corners

    var body: some View {
        content()
            .foregroundStyle(style.foregroundColor)
            .padding(.horizontal, MessageBubbleMetrics.horizontalInset)
            .padding(.vertical, MessageBubbleMetrics.verticalInset)
            .background {
                MessageBubbleMetrics.shape(corners)
                    .fill(Color(UIColor.systemBackground))
                    // **The coloured shape alone travels**, never the cell and never the opaque shape under it: applied to the cell the effect would carry the
                    // text, the avatar, the date and the status indicator with it, and applied underneath it would tint the window showing through the bubble.
                    //
                    // **It fills that shape rather than wrapping a filled one**, since 2026-09-04: the field is drawn as two draws of this silhouette with an
                    // alpha ramp between them, and a ramp cannot be imposed on a fill somebody else has already made without masking it. With the setting off it
                    // fills the shape once with the flat blue and puts **no** `visualEffect` in the render tree at all, so what is in production is what is drawn,
                    // to the pixel and to the frame. See ``TheFieldTheBubblesTravelThrough``.
                    .overlay {
                        TheColourTravelsIfAsked(asked: theColourTravels,
                                                shape: MessageBubbleMetrics.shape(corners),
                                                colour: style.backgroundColor)
                    }
            }
    }

}


/// The mark that a message was edited after it left its sender, shown in the date row beside the date — the `editedStatusImageView` of the legacy cells.
///
/// **Whether it is shown at all is not this view's business**, and it is not simply `isEdited`: a message that is wiped, one that has still to be asked for and a
/// location never say they were edited. The two legacy cells disagreed on that rule and this screen unifies them on the received one — see
/// `SingleDiscussionViewAppDataSource.isShownAsEdited(_:)`, which is where it is written down.
///
/// One icon for both sides of the discussion, where legacy draws `pencil.circle` on a message sent and `pencil.circle.fill` on one received. That difference says
/// nothing — the same fact about the same kind of thing — so this takes the received one, as the suppression rule does.
struct MessageEditedBadgeView: View {

    var body: some View {
        // A `Text` holding an image, and **not an `Image`**: an image is laid out as an image, whose box is taller than a line of `.caption`, and in a row aligned on
        // the baseline that excess height goes *above* it — pushing the date away from the bubble by more than the gap between them. Inside a `Text` the symbol is a
        // glyph on the line like any other, so the row is exactly one line box tall whatever it carries.
        Text(Image(systemIcon: .pencil(.circleFill)))
            .font(.caption)
            // The date's own colour, not the secondary label: see ``MessageTimestampView/foregroundColor``.
            .foregroundStyle(MessageTimestampView.foregroundColor)
    }

}


/// The date at which a message was sent or received, shown *under* its bubble, as in the legacy screen.
struct MessageTimestampView: View {

    /// The ink of the whole date row — this date, the edited mark beside it, and the status of a message sent.
    ///
    /// **One colour for the three**, because they read as a single line and anything else shows as one of them being wrong. Held here because the date is what the row
    /// is *about*: whatever else joins it takes its colour from what it sits beside.
    ///
    /// The **secondary** label, which is what both legacy cells give all three. This screen drew its dates in `AppTheme`'s `cellDate` — the *tertiary* label — from
    /// its first cell until it was read on a real screen and found too faint. Nothing else used `cellDate`, on either screen.
    ///
    /// A dynamic colour, and that is the point of naming one rather than a grey: the system darkens the secondary label against a light background and lightens it
    /// against a dark one, so the contrast holds in both appearances with nothing here to say about it.
    static var foregroundColor: Color {
        Color(UIColor.secondaryLabel)
    }

    let timestamp: Date

    var body: some View {
        // The date is formatted here, from a Date, and not in the data source: a string built when the model is created would go stale as time passes,
        // whereas this recomputes whenever the cell is rendered.
        Text(verbatim: timestamp.formattedForOlvidMessage())
            .font(.caption)
            .foregroundStyle(Self.foregroundColor)
    }

}
