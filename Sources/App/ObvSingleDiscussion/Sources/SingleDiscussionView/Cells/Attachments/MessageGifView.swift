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


/// The animated image of a message, at the size its canvas says it should be drawn at, and nothing at all for a message that has none.
///
/// The numbers are the legacy screen's. `SingleGifView.imageMaxSize` is **241pt** on the longer side, the shorter one scaled by the ratio of the *canvas* — so a
/// square GIF is 241×241, and one twice as wide as it is tall is 241×120.5. `MessageCellConstants.defaultGifViewSize` is **200×150**, which is what a GIF whose
/// file is not here yet occupies; see ``GifInMessage/canvasSize`` for why that ratio cannot be known any sooner than the bytes.
///
/// It is built on ``FollowedAttachment`` rather than on ``ImageAttachmentView``, which is the same thing plus one: the picture it draws is the *frame* the
/// animation has reached, falling back to the still one until the first frame arrives. Everything else — the state control, the progress, the covered
/// presentation — is what every other attachment gets, unchanged.
///
/// **What the frames cost is deliberately not proportional to the length of the animation.** They arrive from the data source, which paces them and decodes as it
/// goes, so this view holds one frame at a time; and they stop the moment the task consuming them is cancelled, which SwiftUI does when the row leaves the
/// screen. A discussion of forty GIFs animates the two or three the reader can see. See ``AnimatedImageDataSource``.
struct MessageGifView: View {

    let gif: GifInMessage?
    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    var body: some View {
        // A `Group`, and **not** a container — the one place on this screen where that is the right choice. A container with nothing in it is still a subview of the
        // cell's stack, which then puts its gap around it: six such views sit between a bubble and the date, so an ordinary text message paid six gaps for parts it
        // does not have. A `Group` contributes nothing at all when its branch is empty, and exactly one view when it is not. (A *row* of the list still needs a real
        // container — see `SingleDiscussionCellView`.)
        Group {
            if let gif {
                // Whether animated images are to play by themselves is the reader's to decide, and only iOS 17 lets them — see ``AnimatedImagePlaybackSetting``.
                AnimatedImagePlaybackSetting { animationsPlayByThemselves in
                    AnimatedImageView(gif: gif,
                                      animatesByItself: animationsPlayByThemselves,
                                      dataSource: dataSource,
                                      actions: actions)
                }
            }
        }
    }

}


/// One animated image, drawn at the shape of its canvas and animated while it is on screen.
private struct AnimatedImageView: View {

    /// Which corners this part joins to another part of the same message — see ``TheColumnOfPartsOfAMessage``. Fully rounded unless the cell says otherwise.
    @Environment(\.cornersOfThisPartOfTheMessage) private var corners

    let gif: GifInMessage
    let animatesByItself: Bool
    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    @Environment(\.displayScale) private var displayScale

    /// Whether this attachment belongs to a message the reader has yet to ask to see. See ``EnvironmentValues/attachmentsAreCoveredUntilRead``.
    @Environment(\.attachmentsAreCoveredUntilRead) private var isCovered

    /// The frame the animation has reached, and nil until it has reached one — which is every moment before the file is here, and every moment for a reader who
    /// has asked animations not to play. The still picture is shown instead, so there is always something to see.
    @State private var currentFrame: CGImage?

    /// `SingleGifView.imageMaxSize`: the longer side of a GIF whose shape is known.
    private static let maxSize = CGFloat(241)

    /// `MessageCellConstants.defaultGifViewSize`: what a GIF whose file has not arrived occupies, there being no ratio to scale by.
    private static let sizeWhileTheShapeIsUnknown = CGSize(width: 200, height: 150)

    private var size: CGSize { Self.size(ofCanvas: gif.canvasSize) }

    private var pixelSize: CGSize { .init(width: size.width * displayScale, height: size.height * displayScale) }

    var body: some View {
        // The lookup happens here, and not in the view built, so that nothing is fetched from within a view's initializer.
        FollowedAttachment(attachment: gif.attachment,
                           sizeToRequest: size,
                           initialImage: dataSource.cachedImageForAttachment(gif.attachment, pixelSize: pixelSize),
                           dataSource: dataSource,
                           actions: actions) { stillImage, phase in
            picture(currentFrame ?? stillImage)
                // Asks for the frames the moment the file is here, and not before — and asks again if the row is re-used for another attachment, or if the size
                // it is drawn at changes. Cancelled by SwiftUI when this view goes away, which is what stops an animation that has scrolled off the screen.
                .task(id: TaskIdentity(attachment: gif.attachment.id, animates: animates(given: phase), maxPixelSize: maxPixelSize)) {
                    await animate(given: phase)
                }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .clipShape(MessageBubbleMetrics.shape(corners))
    }


    private func picture(_ image: CGImage?) -> some View {
        Color.secondary.opacity(0.15)
            .overlay {
                if let image {
                    Image(decorative: image, scale: displayScale)
                        .resizable()
                        .scaledToFill()
                }
            }
    }


    /// Whether this animation is to run: its file has to be here, the reader has to have asked to see the message, and animated images have to be allowed to play
    /// by themselves. A covered message shows nothing of its pictures, still or moving — see ``FollowedAttachment``.
    private func animates(given phase: AttachmentState.Phase?) -> Bool {
        guard animatesByItself, !isCovered else { return false }
        return phase == .available
    }


    /// The longer side, in pixels, which is how the frames are asked for: they arrive ready to draw at the size the row reserved.
    private var maxPixelSize: Int { Int(max(pixelSize.width, pixelSize.height).rounded()) }


    private func animate(given phase: AttachmentState.Phase?) async {
        guard animates(given: phase) else {
            // So that a message whose animation must not run, or which has just been covered again, is not left on whichever frame it had reached.
            currentFrame = nil
            return
        }
        for await frame in dataSource.getAsyncStreamOfFramesForAnimatedImage(gif.attachment, maxPixelSize: maxPixelSize) {
            currentFrame = frame
        }
    }


    /// The size a GIF of that canvas is drawn at: 241pt on its longer side, the shorter scaled by the ratio, exactly as `SingleGifView` computes it.
    ///
    /// A canvas of zero in either direction is treated as no canvas at all rather than divided by — a file can say anything, and a `CGSize` from a header is only
    /// what the file claims.
    private static func size(ofCanvas canvasSize: CGSize?) -> CGSize {
        guard let canvasSize, canvasSize.width > 0, canvasSize.height > 0 else {
            return sizeWhileTheShapeIsUnknown
        }
        return CGSize(width: maxSize * min(1, canvasSize.width / canvasSize.height),
                      height: maxSize * min(1, canvasSize.height / canvasSize.width))
    }


    /// What makes the request worth making again.
    private struct TaskIdentity: Hashable {
        let attachment: MessageAttachment.ID
        let animates: Bool
        let maxPixelSize: Int
    }

}


/// Reads whether the reader lets animated images play by themselves, and hands the answer to what it wraps.
///
/// **Settings → Accessibility → Motion → Auto-Play Animated Images**, which exists from iOS 17 and is read through
/// `EnvironmentValues.accessibilityPlayAnimatedImages`. On iOS 16 there is no such setting to honour, and animations play.
///
/// A view of its own only because of that availability: an `@Environment` property cannot be declared conditionally, so the one that reads an iOS 17 key lives in
/// a type that is itself iOS 17. Reading the whole environment with `@Environment(\.self)` would avoid it at the cost of making every row that holds an animation
/// depend on every environment value there is.
private struct AnimatedImagePlaybackSetting<Content: View>: View {

    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        // A single root whichever branch is taken, as everything in a row of this list must be.
        VStack(spacing: 0) {
            if #available(iOS 17.0, *) {
                AnimatedImagePlaybackSettingReader(content: content)
            } else {
                content(true)
            }
        }
    }

}


@available(iOS 17.0, *)
private struct AnimatedImagePlaybackSettingReader<Content: View>: View {

    @Environment(\.accessibilityPlayAnimatedImages) private var accessibilityPlayAnimatedImages

    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(accessibilityPlayAnimatedImages)
    }

}
