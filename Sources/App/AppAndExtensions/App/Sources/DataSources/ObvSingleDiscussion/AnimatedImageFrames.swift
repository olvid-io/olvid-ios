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
import ImageIO
import OSLog
import ObvAppCoreConstants


/// Plays an animated image file — a GIF or an animated WebP — as a stream of frames, paced as the file asks.
///
/// This is what answers `AnimatedImageDataSource` for the single discussion screen, and it is a type of its own because the interesting part is not the decoding
/// but *what it refuses to do*: it never holds the whole animation.
///
/// Where the legacy screen decodes every frame of a GIF, builds a `UIImage.animatedImage(with:duration:)` out of them and hands that to a `UIImageView`, this
/// walks the file one frame at a time. Two consequences, and both were the point:
///
/// - **Memory does not grow with the length of the animation.** A frame at the size a bubble draws it is around two megabytes on a 3× screen, so a hundred-frame
///   GIF is two hundred megabytes held at once — for one message, in a list the reader is scrolling. Here what is held is the frame being shown, the one being
///   prepared, and whatever fits ``cacheBudget``.
/// - **The pace is the file's.** `UIImage.animatedImage(with:duration:)` takes a *total* duration and divides it evenly, so a GIF that holds one frame for two
///   seconds and flicks through the next ten plays as a uniform slideshow. Each frame here waits exactly what it says it waits.
///
/// It also avoids `CGAnimateImageAtURLWithBlock`, which would do the pacing for us: that is the API the legacy screen moved *away* from, its own comment reading
/// "this method crashes under iOS 16.4".
struct AnimatedImageFrames {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: AnimatedImageFrames.self))

    /// How much of one animation may be kept decoded. Reached by a long animation and never by a short one, which is the whole point of a budget rather than a
    /// frame count: it is bytes that matter, and a frame's size depends on the screen and on the shape of the canvas.
    ///
    /// A short GIF — the overwhelming majority — therefore decodes once and then loops out of memory, costing nothing per frame afterwards. A long one keeps its
    /// first frames and re-reads the rest from the file on every pass, which is work, but bounded work.
    private static let cacheBudget = 8 * 1024 * 1024

    /// What a frame waits when the file does not say, or says something no viewer honours. A delay below ``shortestHonouredDelay`` means "as fast as possible",
    /// which every browser has always rendered as a tenth of a second instead.
    private static let defaultDelay: TimeInterval = 0.1

    /// Below this, a stated delay is treated as unstated. GIFs written by tools that meant "no delay" are extremely common, and honouring the zero would spin
    /// them as fast as the decoder can go. The number is WebKit's — `if (duration < 0.011) duration = 0.100`.
    private static let shortestHonouredDelay: TimeInterval = 0.011

    /// The frames of the animated image at `fileURL`, in order, looping, each held for as long as it asks to be held.
    ///
    /// The stream ends of its own accord for a file holding a single frame — there is nothing to animate — and otherwise runs until the consumer stops listening.
    /// Cancelling the task that consumes it is what stops the decoding: `onTermination` cancels the producer.
    ///
    /// - Parameters:
    ///   - fileURL: the file to read. A `Fyle` is stored under the hexadecimal of its own hash, so its name says nothing about what it is, which is what `uti` is
    ///     for.
    ///   - uti: what the file is, passed to ImageIO as a hint. Only a hint: ImageIO reads the magic bytes, so a wrong UTI costs nothing.
    ///   - maxPixelSize: bounds the longer side of every frame. The frames are decoded to what will be drawn, never to full resolution.
    static func stream(fileURL: URL, uti: String, maxPixelSize: Int) -> AsyncStream<CGImage> {
        // `bufferingNewest(1)`: if the consumer is busy, the newest frame is the only one worth having — an animation catches up, it does not replay what was
        // missed.
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await play(fileURL: fileURL, uti: uti, maxPixelSize: maxPixelSize, into: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }


    private static func play(fileURL: URL, uti: String, maxPixelSize: Int, into continuation: AsyncStream<CGImage>.Continuation) async {

        defer { continuation.finish() }

        let sourceOptions = [kCGImageSourceTypeIdentifierHint: uti] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions) else {
            logger.error("Could not read an animated image from its file")
            return
        }

        let numberOfFrames = CGImageSourceGetCount(source)
        guard numberOfFrames > 0 else { return }

        // Read at the size it will be drawn at, with the orientation baked in. `FromImageIfAbsent` because a frame of an
        // animation has no embedded thumbnail to find.
        let thumbnailOptions = [kCGImageSourceThumbnailMaxPixelSize: maxPixelSize as NSNumber,
                                kCGImageSourceCreateThumbnailFromImageIfAbsent: kCFBooleanTrue as Any,
                                kCGImageSourceCreateThumbnailWithTransform: kCFBooleanTrue as Any] as CFDictionary

        // A single picture in an animated container — a one-frame GIF is a real thing, and often a sticker. Yielded, and then nothing more happens for the life
        // of this attachment.
        guard numberOfFrames > 1 else {
            if let onlyFrame = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) {
                continuation.yield(onlyFrame)
            }
            return
        }

        let delays = (0..<numberOfFrames).map { delay(of: source, at: $0) }

        var cachedFrames = [Int: CGImage]()
        var cachedBytes = 0
        var indexOfTheFrame = 0

        // **The schedule is absolute, not a sleep after each frame.** Sleeping for the delay would add the decode to it, and an animation would run slower than
        // it says by however long its frames take to read — visibly so for the fast ones.
        var deadline = ContinuousClock.now

        while !Task.isCancelled {

            let frame: CGImage?
            if let alreadyDecoded = cachedFrames[indexOfTheFrame] {
                frame = alreadyDecoded
            } else if let decoded = CGImageSourceCreateThumbnailAtIndex(source, indexOfTheFrame, thumbnailOptions) {
                frame = decoded
                let bytes = decoded.bytesPerRow * decoded.height
                if cachedBytes + bytes <= cacheBudget {
                    cachedFrames[indexOfTheFrame] = decoded
                    cachedBytes += bytes
                }
            } else {
                // A frame that will not decode is skipped rather than fatal: the rest of the animation is still worth showing.
                frame = nil
            }

            if let frame {
                continuation.yield(frame)
            }

            deadline = deadline.advanced(by: .seconds(delays[indexOfTheFrame]))
            // A deadline already past means time went missing — the app was away, or the decoding fell behind. Racing through frames to catch up would look like
            // a stutter, so the schedule restarts from now instead.
            if deadline < .now {
                deadline = .now.advanced(by: .seconds(delays[indexOfTheFrame]))
            }

            do {
                try await Task.sleep(until: deadline, clock: .continuous)
            } catch {
                return // Cancelled while waiting for the next frame, which is the ordinary way this ends.
            }

            indexOfTheFrame = (indexOfTheFrame + 1) % numberOfFrames

        }

    }


    /// How long one frame asks to be shown.
    ///
    /// The **unclamped** delay first, which is what the file actually says, and the clamped one as the fallback. Measured, ImageIO's clamped value is the stated
    /// delay for anything from about a fiftieth of a second upwards, and a tenth of a second below that — so the two answers differ only for the frames that
    /// claim to be nearly instantaneous, which is precisely where a decision has to be made rather than inherited. Both are read for animated WebP as well as
    /// for GIF: the keys are different, the shape of the answer is not.
    ///
    /// This is not what makes an animation play at the right speed, though — the *schedule* is. A file whose frames are read one at a time and shown for what
    /// each one asks plays as it was written; the legacy screen sums the delays into a total and lets `UIImage.animatedImage(with:duration:)` divide it evenly,
    /// so a GIF holding one frame for half a second and flicking through the rest at a fortieth becomes a uniform slideshow.
    private static func delay(of source: CGImageSource, at index: Int) -> TimeInterval {

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return defaultDelay }
        let dictionaryOfTheKind = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? properties[kCGImagePropertyWebPDictionary] as? [CFString: Any]
        guard let dictionaryOfTheKind else { return defaultDelay }

        let unclamped = dictionaryOfTheKind[kCGImagePropertyGIFUnclampedDelayTime] as? Double
            ?? dictionaryOfTheKind[kCGImagePropertyWebPUnclampedDelayTime] as? Double
        if let unclamped, unclamped >= shortestHonouredDelay { return unclamped }

        let clamped = dictionaryOfTheKind[kCGImagePropertyGIFDelayTime] as? Double
            ?? dictionaryOfTheKind[kCGImagePropertyWebPDelayTime] as? Double
        if let clamped, clamped >= shortestHonouredDelay { return clamped }

        return defaultDelay

    }

}
