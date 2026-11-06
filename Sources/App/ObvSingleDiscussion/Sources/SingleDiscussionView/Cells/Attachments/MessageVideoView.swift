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


/// The video of a message, when it has one: a preview of a frame at the size a lone photograph gets, with a play glyph over the middle of it.
///
/// **Asked for by the reader before TestFlight, and it is not parity.** The legacy screen shows a video as an attachment card and so did this one. A message
/// carrying one photograph reads well and one carrying one video did not, for no better reason than that `public.movie` does not conform to `public.image` and so
/// fell through to the cards.
///
/// **Almost nothing here is new, which is why this file is short.** The picture was already being produced: the data source's QuickLook fallback
/// goes through `QLThumbnailGenerator`, which returns a frame for a video, and the *card* was already drawing it — so only the geometry changed. The tap, the download control,
/// the flight out to the viewer and back, and the placeholder while the file is coming all belong to ``ImageAttachmentView`` and are used unaltered. What this adds
/// is one glyph and one size.
///
/// **The glyph is not a control.** The whole preview is the tap target, exactly as it is for a photograph, so nothing is wired to the glyph at all — see
/// ``ImageAttachmentView/showsAPlayGlyph``, which also says why a `Button` would be wrong twice over.
struct MessageVideoView: View {

    /// Which corners this part joins to another part of the same message — see ``TheColumnOfPartsOfAMessage``. Fully rounded unless the cell says otherwise.
    @Environment(\.cornersOfThisPartOfTheMessage) private var corners

    let video: MessageAttachment?
    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    @Environment(\.displayScale) private var displayScale

    /// The same 200pt a lone photograph gets — `MessageImagesView.sizeAlone`, which is legacy's `SingleImageView.imageSize`. Shared rather than re-chosen: the
    /// whole request was that a video look like a photograph, and two constants that must agree are one constant.
    static let size = MessageImagesView.sizeAlone

    var body: some View {
        // A `Group`, and **not** a container: with nothing to show this must contribute no subview at all, or the cell's stack puts its gap around an empty box.
        // See ``MessageDocumentPreviewView``, which says it at length.
        Group {
            if let video {
                videoPreview(video)
                    .clipShape(MessageBubbleMetrics.shape(corners))
            }
        }
    }


    /// Builds the preview, handing it whatever has already been decoded at that size so that a video the reader has already seen is there on the frame it appears
    /// on. The lookup happens here, and not in the view built, so that nothing is fetched from within a view's initializer.
    private func videoPreview(_ video: MessageAttachment) -> some View {
        let size = CGSize(width: Self.size, height: Self.size)
        let pixelSize = CGSize(width: size.width * displayScale, height: size.height * displayScale)
        return ImageAttachmentView(attachment: video,
                                   size: size,
                                   initialImage: dataSource.cachedImageForAttachment(video, pixelSize: pixelSize),
                                   cornerRadius: MessageBubbleMetrics.cornerRadius,
                                   roundedCorners: .all,
                                   showsAPlayGlyph: true,
                                   dataSource: dataSource,
                                   actions: actions)
            // **What the glyph does not say.** The glyph is hidden from VoiceOver, so this is the only thing that says the preview is a video rather than a
            // photograph — and it is a label on the element that already takes the tap, so a reader hears what it is and what will happen in one place.
            .accessibilityElement(children: .combine)
            // `Text(_:)` and not a bare string: this module's own initialiser resolves the key against `ObvSingleDiscussionResources.bundle` — see
            // `Text+Bundle.swift` — where a `String` would look for it in the app's bundle and show the key.
            .accessibilityLabel(Text("VIDEO_ATTACHMENT"))
    }

}
