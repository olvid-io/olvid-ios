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

import Foundation
import CoreGraphics


/// The animated image of a message, and the shape of its canvas when that shape is already known.
///
/// Not a `MessageAttachment` alone, and this is the whole point of the type: a GIF is the **one attachment on this screen whose size is not a constant**. A
/// photograph is drawn at 200×200 and a tile of a grid at 120×120 whatever the pixels turn out to be, so a view can reserve its space before asking for
/// anything; a GIF is drawn at 241pt on its longer side with the shorter one scaled by the ratio of its canvas, which is a property of the file.
///
/// ``canvasSize`` is therefore optional, and what it is optional *about* is worth being precise on, because it decides whether this screen ever reflows:
///
/// - **The file is here** — every GIF the reader sent, and every one they have received and downloaded. The ratio is then read from the file's header, off the
///   main thread, while this model is being built, so the very first frame the row is drawn on already has its true size and **nothing moves afterwards**. This
///   is better than the legacy screen, which reserves 200×150 and resizes even for a file it already has.
/// - **The file is not here** — a received GIF the reader has not asked for yet. The ratio is then not knowable *at all*, and 200×150 is the honest answer. It
///   is not merely unread from somewhere: an attachment announces itself with a `FyleMetadata`, which carries a name, a hash and a MIME type and nothing
///   geometric; and the small blob that stands in for an image on its way is a **centered square crop** downsized to 40×40 pixels, so the one picture that
///   exists before the file destroys the very ratio wanted here. The sender has it and throws it away.
///
/// So the resize that remains happens exactly once per file, at the moment its bytes arrive — which is the moment the reader asked for them, on the row under
/// their finger — never while it is being scrolled past.
public struct GifInMessage: Hashable, Sendable {

    /// The file itself, asked for and followed exactly as any other attachment is — the state control, the progress and the picture all come from the same
    /// machinery every other attachment uses.
    public let attachment: MessageAttachment

    /// The size of the GIF's canvas, **in pixels**, and nil while the file it is a property of is not here.
    ///
    /// Only its *ratio* is ever used: the view scales it to the size the legacy screen draws a GIF at. It is the canvas that is measured and not the first
    /// frame, an animated image being allowed to hold frames smaller than the canvas they are composed onto — a GIF whose first frame is a corner of the
    /// picture would otherwise be drawn at the shape of that corner.
    public let canvasSize: CGSize?

    public init(attachment: MessageAttachment, canvasSize: CGSize?) {
        self.attachment = attachment
        self.canvasSize = canvasSize
    }

}
