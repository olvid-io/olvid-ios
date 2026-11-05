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
// For `Image(systemIcon:)`, which draws the play glyph. Raw SF Symbol strings are never written in this codebase.
import ObvSystemIcon


/// One image attached to a message, at the size it is given.
///
/// Three sizes exist, all of them constants of the legacy screen: 200×200 for a message whose only attachment is one image, 120×120 for a tile of the grid
/// shown when there are several, and 241×120 for the wide tile that closes an odd-numbered grid.
///
/// It occupies its full size from the very first frame, before any image has been asked for, and never changes size afterwards. That is deliberate rather than
/// incidental: a row of this list is a self-sizing collection view cell, and a row changing height cannot be animated and moves everything below it.
/// Reserving the space is what keeps a discussion full of photographs from reflowing as they arrive.
///
/// It does **not** round its own corners. Alone it is rounded by the view showing it, and in a grid the rounding belongs to the group, the tiles inside being
/// square and separated by a hairline — as on the legacy screen.
///
/// The image is shown with `Image(decorative:scale:)`, which takes a `CGImage` on every Apple platform, so nothing here needs the platform image type.
struct ImageAttachmentView: View {

    let attachment: MessageAttachment
    let size: CGSize

    /// The image if one had already been decoded at this size when this view was built. See ``FollowedAttachment/initialImage``.
    let initialImage: CGImage?

    /// How round this image's corners are — which this view does not know by itself, the rounding being applied by whoever shows it: a single image is rounded, and
    /// a tile of a grid is square with the *group* rounded around it. Reported so that what flies out of it and back into it is rounded the same way.
    let cornerRadius: CGFloat

    /// **Which** corners that radius applies to. A tile of a grid is clipped by its group, so the corners it appears to have are the ones it happens to
    /// sit under, and only its caller can say which those are: see ``MessageImagesView/theCornersATileOwns(top:bottom:side:)``. `.all` for an image standing alone.
    let roundedCorners: AttachmentOnScreen.RoundedCorners

    /// Whether a play glyph is drawn over the middle of the picture once the file is here, and false for everything but a video.
    ///
    /// **Not a control**, which is the whole of its design: nothing is wired to it, the *whole* preview being the tap target exactly as it is for a photograph. It
    /// says *this is a video*, and the tap it appears to offer is the one the preview already answers. A `Button` here would also be a fault of its own: a button in a
    /// `List` row needs `.buttonStyle(.plain)` or never fires at all.
    var showsAPlayGlyph: Bool = false

    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        FollowedAttachment(attachment: attachment,
                           sizeToRequest: size,
                           initialImage: initialImage,
                           dataSource: dataSource,
                           actions: actions) { image, phase in
            placeholder
                .overlay {
                    if let image {
                        Image(decorative: image, scale: displayScale)
                            .resizable()
                            .scaledToFill()
                    }
                }
                // **Above the picture and below the state control**, which `FollowedAttachment` draws as an overlay outside this. The two never appear together —
                // see ``thePlayGlyph`` — so the order decides nothing that can happen; it says which of them owns the middle.
                .overlay { thePlayGlyph(phase: phase) }
                // Inside the content, where the phase is known — and beneath the state control, which `FollowedAttachment` draws as an overlay above this. The
                // picture tapped and the picture flown from are the same one here, as they are on the legacy screen.
                .opensTheAttachmentViewer(attachment, phase: phase, actions: actions)
                .theAttachmentViewerFliesFromHere(attachment, showing: image, cornerRadius: cornerRadius, roundedCorners: roundedCorners, actions: actions)
                // Nothing about dragging here: a message hands over all of its files at once, from the cell — see ``TheAttachmentsOfAMessageDraggedOut``.
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// The glyph that says a preview is a video.
    ///
    /// **Only once the file is here**, which is the first rule. `AttachmentStateControl` owns the middle of a tile whose file is still coming, so two things
    /// in one centre would be the visible collision — but the real fault is *offering to play something that is absent*. A video is the attachment most
    /// likely to be over the size the reader has set, so that is the common case rather than an edge of it.
    ///
    /// **It is two glyphs, not one**, and the control's own drawing is why:
    ///
    /// - `.uploading` draws a **50pt circle** with the upload's arc around it and no glyph inside, an upload having nothing to press. So a plain
    ///   ``SystemIcon/playFill`` lands inside a circle that is already there, and a circled glyph would put a second circle inside the first.
    /// - `.available` draws `EmptyView()`: the control goes entirely, and a bare glyph would float on an arbitrary photograph with nothing under it. So the
    ///   glyph brings a disc, ``TheDiscAGlyphOverAnAttachmentSitsOn``, at exactly ``AttachmentStateControl/diameter``. **The circle does not appear, it
    ///   stays**: the arc finishes and the ring it was drawn in remains, now holding a play. Same glyph, same size on both sides, so nothing moves or
    ///   resizes when the upload completes — which is the argument for the pair, rather than two shapes being nicer than one.
    ///
    /// **The position is left alone, and that is a decision.** Apple nudges the triangle right of its disc's centre by ~3.4% of the diameter, a
    /// right-pointing triangle's optical centre sitting left of its bounding box. Ours is not centred either: `play.fill`'s ink sits +0.0575 of its drawn box
    /// to the right, which already carries most of it and leaves a residual of **+0.45pt**. It is not applied because **the correction is smaller than the
    /// uncertainty in the term it corrects** — this assumes SwiftUI centres the same box `NSImage` reports, and if it centres the font's em box instead,
    /// adding 0.45pt could as easily double the error as remove it. If it still reads off-centre, **measure it as Apple's was measured** rather than nudging
    /// it by eye.
    ///
    /// **The disc is glass from iOS 26 and never interactive** — `interactive()` was withdrawn after it stopped the download control answering a click on a
    /// Mac, and it would be wrong here anyway: nothing is wired to this glyph, so answering a press would be a lie about it.
    ///
    /// **`.system(size:)` and a frame, not a text style.** The preview is 200pt whatever the Dynamic Type setting, so a glyph that scaled would leave it.
    /// That is only acceptable because the glyph says nothing a reader cannot learn elsewhere: the preview carries a label saying it is a video, and the
    /// glyph is hidden from VoiceOver.
    @ViewBuilder
    private func thePlayGlyph(phase: AttachmentState.Phase?) -> some View {
        // A `Group` with no branch taken contributes no subview at all, which is what an `overlay` wants here.
        Group {
            if showsAPlayGlyph {
                switch phase {
                case .uploading:
                    Image(systemIcon: .playFill)
                        .font(.system(size: Self.sizeOfThePlayGlyph))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 6)
                        .accessibilityHidden(true)
                case .available:
                    // **The same glyph as during the upload, on a disc rather than inside an arc.** It was `playCircleFill` for an afternoon — the reader's own
                    // suggestion, and the right idea — but a symbol that *is* a filled disc cannot also be glass, and it has a fault of its own: the play shape is
                    // **knocked out** of the disc, so on a very light frame the triangle is the frame showing through and reads faintly. A plain glyph on
                    // ``TheDiscAGlyphOverAnAttachmentSitsOn`` is the same picture with the disc made of glass instead of of symbol, and it is the *same disc* the
                    // control's ring was, so nothing moves or resizes at the moment an upload completes.
                    //
                    // **Not interactive glass**: nothing is wired to this, the whole preview being the tap target.
                    Image(systemIcon: .playFill)
                        .font(.system(size: Self.sizeOfThePlayGlyph))
                        .foregroundStyle(.primary)
                        .frame(width: AttachmentStateControl.diameter, height: AttachmentStateControl.diameter)
                        .modifier(TheDiscAGlyphOverAnAttachmentSitsOn())
                        .accessibilityHidden(true)
                default:
                    EmptyView()
                }
            }
        }
    }


    /// The size of the glyph, in **both** phases so that an upload finishing moves nothing — and **derived from Apple's own proportions rather than chosen**.
    ///
    /// It was 28pt, picked as *what `.title` comes to*, and the reader said on 2026-08-27 that the triangle sat wrongly inside its circle. Measuring settled it in
    /// one run and named the fault precisely: **the triangle was 13.2% too tall**, and its position was already very nearly right — which no amount of looking would
    /// have separated.
    ///
    /// The measurement is worth keeping because it can be repeated. `play.circle.fill` and `play.fill` were rendered through `NSImage(systemSymbolName:)` at 512pt
    /// and the pixels read: for the enclosed symbol, the **disc** is 1020px and the triangle — which is a *hole* knocked out of it — is 360×414, giving
    /// ``heightOfApplesTriangleAsAFractionOfItsDisc``; for the bare symbol, the ink is 840px tall, giving ``heightOfPlayFillsInkPerPoint``. A useful by-product:
    /// a `.circle` enclosure's diameter comes out at 510pt for a 512pt point size, so **the enclosure is the point size**, which is what makes the two
    /// measurements comparable.
    private static var sizeOfThePlayGlyph: CGFloat {
        AttachmentStateControl.diameter * heightOfApplesTriangleAsAFractionOfItsDisc / heightOfPlayFillsInkPerPoint
    }

    /// How tall the triangle inside `play.circle.fill` is, as a fraction of that symbol's disc — 414/1020, measured. Its width is 0.353 of the disc, and taking the
    /// **height** as the governing dimension leaves the width 2.1% wide, the bare symbol's ink being a shade squarer than the knocked-out hole.
    private static let heightOfApplesTriangleAsAFractionOfItsDisc: CGFloat = 0.406

    /// How tall `play.fill`'s ink is per point of point size — 840px at 512pt, halved for the 2× bitmap, measured the same way.
    private static let heightOfPlayFillsInkPerPoint: CGFloat = 0.820


    private var placeholder: some View {
        Color.secondary.opacity(0.15)
    }

}
