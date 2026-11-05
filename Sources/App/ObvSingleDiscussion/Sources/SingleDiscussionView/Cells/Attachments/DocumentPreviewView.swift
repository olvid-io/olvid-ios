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


/// The first document attached to a message, shown as the top of its first page.
///
/// Matches `SinglePDFView` of the legacy screen — 280pt wide, a preview at most 192pt tall, the filename and the size beneath it — and is given to any paginated
/// document rather than to PDFs alone. See ``FyleMessageJoinWithStatus/isDocumentType`` for which kinds those are and why.
///
/// **The preview is a crop, not a fitted thumbnail.** The legacy screen asks for `cropBottom(mandatoryWidth:maxHeight:)`: the page fills the width, and whatever
/// does not fit in 192pt is cut off the bottom. A fitted thumbnail would show a whole page shrunk inside the box with bars either side, which is not the same
/// picture at all. So the image fills and is clipped, aligned to the top.
///
/// It occupies its full height from the first frame, whether or not there is anything to show in it — as every attachment on this screen does: a row that changes height moves everything
/// below it and cannot be animated.
struct DocumentPreviewView: View {

    let document: MessageAttachment

    /// The image if one had already been decoded at the size below. See ``FollowedAttachment/initialImage``.
    let initialImage: CGImage?

    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    @Environment(\.attachmentsAreCoveredUntilRead) private var isCovered

    @Environment(\.displayScale) private var displayScale

    /// `SinglePDFView.singlePDFViewWidth`.
    static let width = CGFloat(280)

    /// `SinglePDFView.singlePDFPreviewMaxHeight`.
    private static let heightOfThePreview = CGFloat(192)

    /// What is asked for, which is neither the width nor the height of what is drawn.
    ///
    /// `kCGImageSourceThumbnailMaxPixelSize` bounds the **larger** dimension, and a page is taller than it is wide — by about √2 for A4 — so asking for 280 would
    /// return a page only 198 wide and leave the crop nothing to fill with. Asking for 400 gives a portrait page its 280 points of width; a landscape one is
    /// over-served, which costs a little memory on the few documents a discussion holds and nothing else.
    static var sizeToRequestForThePreview: CGSize {
        CGSize(width: 400, height: 400)
    }

    /// Beside the labels. Narrower above and below them than a card's, which is 16 all round.
    private static let horizontalInsetOfTheLabels = CGFloat(16)
    private static let verticalInsetOfTheLabels = CGFloat(8)

    /// Between the two labels.
    private static let gapBetweenTheLabels = CGFloat(4)

    /// `SinglePDFView.imageBorderWidth`. The preview is inset by this on three sides, and what shows through is the fill behind it — a hairline frame around the
    /// page, which is what tells a white page from the white of the screen.
    private static let borderWidth = CGFloat(1)

    /// The preview's own corners, each one point tighter than the corner it sits inside — `largeCornerRadius` above, where it meets the outside of the card, and
    /// `smallCornerRadius` below, where it meets the labels.
    private static let cornerRadiusAtTheTop = MessageBubbleMetrics.cornerRadius - borderWidth
    private static let cornerRadiusAtTheBottom = CGFloat(4) - borderWidth

    var body: some View {
        VStack(spacing: 0) {
            preview
                .padding(.top, Self.borderWidth)
                .padding(.horizontal, Self.borderWidth)
            labels
        }
        .frame(width: Self.width)
        .background(Color(UIColor.secondarySystemFill))
    }


    private var preview: some View {
        FollowedAttachment(attachment: document,
                           sizeToRequest: Self.sizeToRequestForThePreview,
                           initialImage: initialImage,
                           dataSource: dataSource,
                           actions: actions) { image, phase in
            Color.clear
                .overlay(alignment: .top) {
                    if let image {
                        Image(decorative: image, scale: displayScale)
                            .resizable()
                            .scaledToFill()
                    }
                }
                // The preview, and not the card around it: `SinglePDFView` asks only its image view whether it was tapped, so the filename beneath opens nothing.
                .opensTheAttachmentViewer(document, phase: phase, actions: actions)
                // **From the top**, which is what `cropBottom` means and what this tile draws: a stand-in that centred the page flew the *middle* of it back into
                // a tile showing its head. The radius is the one at the top, the two at the bottom being 3pt and indistinguishable from square in flight.
                .theAttachmentViewerFliesFromHere(document,
                                                  showing: image,
                                                  cornerRadius: Self.cornerRadiusAtTheTop,
                                                  roundedCorners: .top,
                                                  crop: .fromTheTop,
                                                  actions: actions)
        }
        // Lighter than the card behind it, as on the legacy screen, so that a page which is itself white does not merge into the fill around it.
        .background(Color(UIColor.tertiarySystemFill))
        .frame(width: Self.width - 2 * Self.borderWidth, height: Self.heightOfThePreview)
        // The page fills the width and is cut off at the bottom, which is what `cropBottom` means.
        .clipShape(.rect(topLeadingRadius: Self.cornerRadiusAtTheTop,
                         bottomLeadingRadius: Self.cornerRadiusAtTheBottom,
                         bottomTrailingRadius: Self.cornerRadiusAtTheBottom,
                         topTrailingRadius: Self.cornerRadiusAtTheTop,
                         style: .continuous))
    }


    /// The title may run to **two** lines here, where a card's is limited to one: a document has room for it, and the name of one is usually what tells it apart
    /// from the others. `SinglePDFView.titleLabel.numberOfLines` is 2 on the legacy screen for the same reason.
    private var labels: some View {
        VStack(alignment: .leading, spacing: Self.gapBetweenTheLabels) {
            // See `AttachmentCardView`: a covered attachment keeps its size and its type, and loses its name.
            Text(verbatim: isCovered ? "" : (document.fileName ?? ""))
                .font(.subheadline)
                .foregroundStyle(Color(UIColor.label))
                .lineLimit(2)
            Text(document.sizeAndKind)
                .font(.caption)
                .foregroundStyle(Color(UIColor.secondaryLabel))
                .lineLimit(1)
        }
        .truncationMode(.tail)
        .padding(.horizontal, Self.horizontalInsetOfTheLabels)
        .padding(.vertical, Self.verticalInsetOfTheLabels)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}
