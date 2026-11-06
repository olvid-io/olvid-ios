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
import UniformTypeIdentifiers


/// One attachment shown as a card: a square thumbnail, its name, and its size and kind.
///
/// What every attachment that is not drawn as something richer falls back to — a document, an archive, a video, every audio file after the first. Matches
/// `SingleAttachmentView` of the legacy screen, including its 280pt width and the rule that decides its height.
///
/// **The labels decide the height, and the thumbnail is a square of it.** That is the legacy rule, stated in a comment there and implemented with hugging and
/// compression priorities; here it is a `Layout`, for the same reason the legacy code needed those priorities: the thumbnail must not be allowed to say how tall
/// the card is, or the size it happened to be requested at would decide the layout.
///
/// **A tap anywhere in the card opens it**, filename included, which is what `SingleAttachmentView` does by asking its subviews with `acceptTapOutsideBounds: true`
/// — while the viewer flies out of the *thumbnail* alone, `getAllShownHardLink()` handing back the image view. Two rectangles for two jobs, hence the two modifiers.
struct AttachmentCardView: View {

    let attachment: MessageAttachment

    /// The thumbnail if one had already been decoded at the size below. See ``FollowedAttachment/initialImage``.
    let initialImage: CGImage?

    /// Where this card sits in the stack of them, which is the only thing that rounds its thumbnail: the corners belong to the *group*, so the first card is round
    /// at the top of its leading edge, the last at the bottom of it, one card alone at both, and a card in the middle at neither.
    let isTheFirstCard: Bool
    let isTheLastCard: Bool

    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    @Environment(\.attachmentsAreCoveredUntilRead) private var isCovered

    @Environment(\.displayScale) private var displayScale

    /// Resolved here rather than reported as leading and trailing, because a layer knows only left and right — and this is the one tile on the screen whose
    /// rounding is not symmetrical, so it is the only one that has to care which way the reader's language runs.
    @Environment(\.layoutDirection) private var layoutDirection

    private var roundedCornersOfTheThumbnail: AttachmentOnScreen.RoundedCorners {
        let onTheLeadingEdge: AttachmentOnScreen.RoundedCorners = layoutDirection == .rightToLeft ? .right : .left
        var corners: AttachmentOnScreen.RoundedCorners = []
        if isTheFirstCard { corners.insert(onTheLeadingEdge.intersection(.top)) }
        if isTheLastCard { corners.insert(onTheLeadingEdge.subtracting(.top)) }
        return corners
    }

    /// `MessageCellConstants.singleAttachmentViewWidth`.
    static let width = CGFloat(280)

    /// `SingleAttachmentView.sizeForRequestingThumbnail`, and *recommended* rather than exact on the legacy screen too: the square it is drawn in is as tall as
    /// the labels, which the reader's text size decides. One request for every card, whatever they come to, so one decode serves them all.
    static let sizeToRequestForTheThumbnail = CGSize(width: 100, height: 100)

    /// Around the labels, and between them and the thumbnail.
    private static let inset = CGFloat(16)

    /// Between the two labels.
    private static let gapBetweenTheLabels = CGFloat(4)

    /// The phase of the file, hoisted out of ``thumbnail`` because the tap belongs to the *whole card* while the control that outranks it is drawn over the
    /// thumbnail alone: `SingleAttachmentView` asks its subviews with `acceptTapOutsideBounds: true`, so a tap on the filename opens the attachment there too.
    @State private var phaseOfTheFile: AttachmentState.Phase?

    var body: some View {
        SquareThumbnailBesideTheLabels(gap: Self.inset) {
            thumbnail
            labels
        }
        .frame(width: Self.width)
        .background(Color(UIColor.secondarySystemFill))
        .opensTheAttachmentViewer(attachment, phase: phaseOfTheFile, actions: actions)
        // Nothing about dragging here: a message hands over all of its files at once, from the cell — see ``TheAttachmentsOfAMessageDraggedOut``.
    }


    /// Fills the square it is given, whatever that comes to, and shows the card's own fill until there is something to draw — a card needs no placeholder of its
    /// own, unlike an image in a bubble, which has nothing behind it.
    private var thumbnail: some View {
        FollowedAttachment(attachment: attachment,
                           sizeToRequest: Self.sizeToRequestForTheThumbnail,
                           initialImage: initialImage,
                           dataSource: dataSource,
                           actions: actions) { image, phase in
            Color.clear
                .overlay {
                    if let image {
                        Image(decorative: image, scale: displayScale)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipped()
                // The thumbnail alone is what the viewer flies out of and back into, `getAllShownHardLink()` handing back the image view rather than the card.
                .theAttachmentViewerFliesFromHere(attachment,
                                                  showing: image,
                                                  cornerRadius: MessageBubbleMetrics.cornerRadius,
                                                  roundedCorners: roundedCornersOfTheThumbnail,
                                                  actions: actions)
                // Where the phase is known; the tap that needs it is on the card. `task(id:)` rather than `onChange(of:initial:)`, which is iOS 17.
                .task(id: phase) { phaseOfTheFile = phase }
        }
    }


    private var labels: some View {
        VStack(alignment: .leading, spacing: Self.gapBetweenTheLabels) {
            // A covered attachment shows no name: what a file is called says a good deal about what it is, and the reader has not asked yet. Its size and type
            // stay, as they do on the legacy screen.
            Text(verbatim: isCovered ? "" : (attachment.fileName ?? ""))
                .font(.subheadline)
                .foregroundStyle(Color(UIColor.label))
            Text(attachment.sizeAndKind)
                .font(.caption)
                .foregroundStyle(Color(UIColor.secondaryLabel))
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.vertical, Self.inset)
        .padding(.trailing, Self.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }


}


extension MessageAttachment {

    /// "1,2 MB - PDF document", as the legacy screen composes it: the size, then what the system calls this kind of file, and only the size when it has no name
    /// for the kind.
    ///
    /// On ``MessageAttachment`` rather than on a view, being what a card and a document preview both put under their title.
    var sizeAndKind: String {
        var elements = [Int64(fileSize).formatted(.byteCount(style: .file, allowedUnits: .all, spellsOutZero: true, includesActualByteCount: false))]
        if let localizedDescription = UTType(uti)?.localizedDescription {
            elements.append(localizedDescription)
        }
        return elements.joined(separator: " - ")
    }

}


/// Lays a square out beside something that decides how tall both of them are.
///
/// Exactly two subviews: the square first, then what sets the height. The square is given the height as its side, flush to the leading, top and bottom edges;
/// the rest of the width goes to the second.
///
/// No circularity to resolve, and that rests on one fact: what sets the height here is **two single-line labels**, whose height does not depend on the width they
/// are given. Were they allowed to wrap, the height would depend on the width, which would depend on the square's side, which would depend on the height.
struct SquareThumbnailBesideTheLabels: Layout {

    /// Between the square and what follows it.
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { assertionFailure(); return .zero }
        return CGSize(width: proposal.replacingUnspecifiedDimensions().width,
                      height: subviews[1].sizeThatFits(.unspecified).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { assertionFailure(); return }
        let side = bounds.height
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: side, height: side))
        let leadingEdgeOfTheLabels = bounds.minX + side + gap
        subviews[1].place(at: CGPoint(x: leadingEdgeOfTheLabels, y: bounds.midY),
                          anchor: .leading,
                          proposal: ProposedViewSize(width: max(0, bounds.maxX - leadingEdgeOfTheLabels), height: bounds.height))
    }

}
