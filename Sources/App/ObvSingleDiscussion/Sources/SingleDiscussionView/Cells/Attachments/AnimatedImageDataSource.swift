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


/// The frames of an animated image, at the pace they are meant to be seen.
///
/// A protocol of its own, alongside ``AttachmentProgressDataSource``, ``AudioPlaybackDataSource`` and ``LinkPreviewDataSource``, so that what this screen asks of
/// its app remains legible one question at a time.
@MainActor
public protocol AnimatedImageDataSource: AnyObject {

    /// The frames of an animated attachment, one after another, for as long as the caller keeps listening.
    ///
    /// **A stream, and the pace is the producer's.** Every other picture on this screen is asked for once and arrives once; this one is a *sequence*, and the
    /// interval between two frames is a property of the file — a GIF may hold a frame for two seconds and the next for a fortieth of a second. Putting the clock
    /// on this side of the protocol is what makes that expressible at all: a view that asked for "the frames" and paced them itself would have to be told the
    /// delays, and would then be running a timer on the main actor for every animation on screen.
    ///
    /// Three things are expected of an implementation, and none of them is expressible in the signature:
    ///
    /// - **Bounded memory.** It must not decode every frame and hold them. A long animation at this size is tens of megabytes, several of them on screen at once
    ///   is hundreds, and this is a list the reader scrolls. Decoding as it goes — keeping what fits a budget and re-reading the rest — is what makes an
    ///   animation cost the same whether it has eight frames or eight hundred.
    /// - **Off the main actor.** Every frame is a decode, ten to fifty times a second.
    /// - **It ends when nobody is listening.** The caller stops by cancelling the task that consumes the stream, which terminates it; the decoding must stop
    ///   there and then. This is how an animation stops when its row is scrolled away, and there is no other signal that it should.
    ///
    /// `maxPixelSize` bounds the longer side of each frame, in pixels, as every other picture on this screen is asked for — the frames arrive ready to draw at
    /// the size the row reserved for them.
    ///
    /// A file holding a single frame is welcome to yield it and finish: there is nothing to animate, and a stream that ends is cheaper than one that idles.
    func getAsyncStreamOfFramesForAnimatedImage(_ attachment: MessageAttachment, maxPixelSize: Int) -> AsyncStream<CGImage>

}
