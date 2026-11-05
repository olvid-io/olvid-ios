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


/// The images attached to a message: one shown large and alone, or several shown as a grid.
///
/// The grid is the legacy screen's, in `MultipleImagesView`: tiles of 120pt in rows of two, separated by a hairline, so the whole is always as wide as two
/// tiles and the gap between them. When the number of images is **odd**, the last one closes the grid as a single wide tile spanning the full width. Nothing
/// caps the number of rows, as nothing caps it there.
///
/// The corners are rounded here, on the group, rather than on each image — which is what leaves the hairlines running from edge to edge.
struct MessageImagesView: View {

    /// Which corners this part joins to another part of the same message — see ``TheColumnOfPartsOfAMessage``. Fully rounded unless the cell says otherwise.
    @Environment(\.cornersOfThisPartOfTheMessage) private var corners

    let images: [MessageAttachment]
    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    @Environment(\.displayScale) private var displayScale

    /// Read because ``AttachmentOnScreen/RoundedCorners`` is named **left and right** — *"that being what a layer understands"* — while ``corners`` is named leading
    /// and trailing, and an `HStack` mirrors: in a right-to-left layout the first tile of a row is the one on the **right**. The type's own documentation says a
    /// view that mirrors resolves them before reporting; this is the view that mirrors.
    @Environment(\.layoutDirection) private var layoutDirection

    /// `SingleImageView.imageSize` on the legacy screen: the size of the one image of a message that has a single one.
    ///
    /// **Not private since Step 63**: ``MessageVideoView`` shows a video at the same size, the whole of that step's request being that a video look like a
    /// photograph. Two constants that must agree are one constant.
    static let sizeAlone = CGFloat(200)

    /// `HorizontalPairOfImagesView.smallImageSize`: the side of a tile of the grid.
    private static let sizeInGrid = CGFloat(120)

    /// `HorizontalPairOfImagesView.spacing`: a hairline, and not a gap. The images of a message read as one block.
    private static let spacingInGrid = CGFloat(1)

    /// `MultipleImagesView.wideImageWidth`, which is the width of the grid itself: two tiles and the hairline between them.
    private static var widthOfTheGrid: CGFloat { 2 * sizeInGrid + spacingInGrid }

    var body: some View {
        // A `Group`, and **not** a container — the one place on this screen where that is the right choice. A container with nothing in it is still a subview of the
        // cell's stack, which then puts its gap around it: six such views sit between a bubble and the date, so an ordinary text message paid six gaps for parts it
        // does not have. A `Group` contributes nothing at all when its branch is empty, and exactly one view when it is not. (A *row* of the list still needs a real
        // container — see `SingleDiscussionCellView`.)
        Group {
            if let onlyImage = images.first, images.count == 1 {
                // Rounded here, and told so: what flies out of it must be rounded the same way. It owns all four of the group's corners, being the whole of the
                // group — see ``theRadiusFor(_:)`` for the one residual, which is a single radius where the group may have two.
                imageView(onlyImage,
                          size: CGSize(width: Self.sizeAlone, height: Self.sizeAlone),
                          cornerRadius: theRadiusFor(.all),
                          roundedCorners: .all)
                .clipShape(MessageBubbleMetrics.shape(corners))
            } else if images.count > 1 {
                grid
                    .clipShape(MessageBubbleMetrics.shape(corners))
            }
        }
    }

    private var grid: some View {
        VStack(spacing: Self.spacingInGrid) {
            // **Enumerated, because a tile's corners are a fact about its row**. The identity is still the row's first image, exactly as before:
            // `MessageAttachment` is identified by the file *and* its rank, so two identical photographs in one message do not collide, where an index would
            // have made every row's identity change whenever one arrived.
            ForEach(Array(pairs.enumerated()), id: \.element.first.id) { index, pair in
                let top = index == pairs.startIndex
                // The last row of the grid only when nothing closes it below — a wide image, when there is one, is what owns the bottom corners.
                let bottom = index == pairs.index(before: pairs.endIndex) && wideImage == nil
                HStack(spacing: Self.spacingInGrid) {
                    tile(pair.first, top: top, bottom: bottom, side: .start)
                    if let second = pair.second {
                        tile(second, top: top, bottom: bottom, side: .end)
                    }
                }
            }
            if let wideImage {
                // It spans the whole width, so it owns **both** bottom corners — and never a top one: a wide image exists only for an odd number of images, and
                // an odd number reaching the grid at all is three or more, so there is always at least one row of pairs above it.
                let owned = theCornersATileOwns(top: false, bottom: true, side: .both)
                imageView(wideImage,
                          size: CGSize(width: Self.widthOfTheGrid, height: Self.sizeInGrid),
                          cornerRadius: theRadiusFor(owned),
                          roundedCorners: owned)
            }
        }
        .frame(width: Self.widthOfTheGrid)
    }

    private func tile(_ attachment: MessageAttachment, top: Bool, bottom: Bool, side: SideOfTheRow) -> some View {
        let owned = theCornersATileOwns(top: top, bottom: bottom, side: side)
        return imageView(attachment,
                         size: CGSize(width: Self.sizeInGrid, height: Self.sizeInGrid),
                         cornerRadius: theRadiusFor(owned),
                         roundedCorners: owned)
    }


    /// Where a tile sits across its row. ``both`` is the wide image that closes an odd grid, which is a row to itself.
    private enum SideOfTheRow {
        case start
        case end
        case both
    }


    /// Which of the group's corners a tile is the one clipped by.
    ///
    /// **A tile has no corners of its own**, and that is the whole difficulty of this step. The tiles are drawn square and the group carries
    /// `.clipShape(MessageBubbleMetrics.shape(corners))`, so a tile at an outer corner is not *rounded* — it is **clipped by an ancestor**. There is nothing on the
    /// tile to read, so what it appears to have has to be worked out from where it sits, which only this view knows.
    ///
    /// Resolved to left and right here rather than left to the caller: see ``layoutDirection``.
    private func theCornersATileOwns(top: Bool, bottom: Bool, side: SideOfTheRow) -> AttachmentOnScreen.RoundedCorners {

        let theStartIsOnTheLeft = layoutDirection != .rightToLeft
        let theLeftIsMine: Bool
        let theRightIsMine: Bool
        switch side {
        case .start: theLeftIsMine = theStartIsOnTheLeft;  theRightIsMine = !theStartIsOnTheLeft
        case .end:   theLeftIsMine = !theStartIsOnTheLeft; theRightIsMine = theStartIsOnTheLeft
        case .both:  theLeftIsMine = true;                 theRightIsMine = true
        }

        var owned: AttachmentOnScreen.RoundedCorners = []
        if top, theLeftIsMine { owned.insert(.topLeft) }
        if top, theRightIsMine { owned.insert(.topRight) }
        if bottom, theLeftIsMine { owned.insert(.bottomLeft) }
        if bottom, theRightIsMine { owned.insert(.bottomRight) }
        return owned

    }


    /// The radius to fly those corners at: the **largest** of the group's radii among the corners owned.
    ///
    /// **A part of a message has no square corners** — ``TheColumnOfPartsOfAMessage/corners(of:)`` gives every corner either
    /// ``MessageBubbleMetrics/cornerRadius`` (14) or ``MessageBubbleMetrics/smallCornerRadius`` (4), the small one where two parts of *one* message meet. So there
    /// is nothing to intersect away here, only a radius to choose.
    ///
    /// **And a choice has to be made, because a layer has one radius.** `CALayer` offers `cornerRadius` plus a `CACornerMask` and nothing uneven, so a tile owning
    /// a 14 corner *and* a 4 corner — the left-hand tile of a two-image grid whose part joins another below it — cannot have both. The largest is taken
    /// deliberately: the large radius faces the **discussion's background**, where a wrong corner is plainly visible, while the small one faces the neighbouring
    /// part of the same message, drawn in the same fill, where ten points of error is very nearly invisible. So the visible corner is exact and the hidden one is
    /// approximate, for the length of the flight.
    private func theRadiusFor(_ owned: AttachmentOnScreen.RoundedCorners) -> CGFloat {
        let mirrored = layoutDirection == .rightToLeft
        var radius: CGFloat = 0
        if owned.contains(.topLeft) { radius = max(radius, mirrored ? corners.topTrailing : corners.topLeading) }
        if owned.contains(.topRight) { radius = max(radius, mirrored ? corners.topLeading : corners.topTrailing) }
        if owned.contains(.bottomLeft) { radius = max(radius, mirrored ? corners.bottomTrailing : corners.bottomLeading) }
        if owned.contains(.bottomRight) { radius = max(radius, mirrored ? corners.bottomLeading : corners.bottomTrailing) }
        return radius
    }


    /// Builds one image, handing it whatever has already been decoded at that size so that a photograph the reader has already seen is there on the frame it
    /// appears on. The lookup happens here, and not in the view built, so that nothing is fetched from within a view's initializer.
    private func imageView(_ attachment: MessageAttachment, size: CGSize, cornerRadius: CGFloat, roundedCorners: AttachmentOnScreen.RoundedCorners) -> some View {
        let pixelSize = CGSize(width: size.width * displayScale, height: size.height * displayScale)
        return ImageAttachmentView(attachment: attachment,
                                   size: size,
                                   initialImage: dataSource.cachedImageForAttachment(attachment, pixelSize: pixelSize),
                                   cornerRadius: cornerRadius,
                                   roundedCorners: roundedCorners,
                                   dataSource: dataSource,
                                   actions: actions)
    }

    /// The last image, when there is an odd number of them: it closes the grid as a wide tile rather than leaving a gap beside it.
    private var wideImage: MessageAttachment? {
        images.count.isMultiple(of: 2) ? nil : images.last
    }

    /// The images shown two by two, which is every image but the wide one.
    private var pairs: [Pair] {
        let imagesInPairs = wideImage == nil ? images : images.dropLast()
        return stride(from: 0, to: imagesInPairs.count, by: 2).map { index in
            Pair(first: imagesInPairs[index],
                 second: index + 1 < imagesInPairs.count ? imagesInPairs[index + 1] : nil)
        }
    }

    /// A row of the grid. Identified by its first image, `MessageAttachment` being identified by the file it shows *and* its rank in the message, so two
    /// identical photographs attached to one message do not collide.
    private struct Pair {
        let first: MessageAttachment
        let second: MessageAttachment?
    }

}
