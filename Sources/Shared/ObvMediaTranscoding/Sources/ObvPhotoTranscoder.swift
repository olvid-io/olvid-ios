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
import ImageIO
import OSLog
import ObvAppCoreConstants
import ObvAppTypes
import ObvCrypto
import UniformTypeIdentifiers


/// Makes one photo smaller, and nothing else.
///
/// No Core Data and no knowledge of drafts: given a file and a size, it writes another file, so that callers encode away from any
/// context's queue. Shared by the app and the share extension.
///
/// ImageIO rather than a platform image: `CGImageSourceCreateThumbnailAtIndex` decodes at the requested size, where `UIImage` decodes a
/// 48-megapixel photo in full first, a couple of hundred megabytes, beyond the share extension's memory limit.
public enum ObvPhotoTranscoder {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ObvPhotoTranscoder")

    /// One photo written at one size. See ``ObvTranscodedFile``, which is the same thing a video's export hands back — one type, so that
    /// what records either of them into the database has one path rather than two that could drift.
    public typealias TranscodedPhoto = ObvTranscodedFile


    public enum ObvError: Error {
        case couldNotReadPhoto(url: URL)
        case couldNotDownsizePhoto
        case couldNotCreateDestination
        case couldNotWriteTranscodedPhoto
        case couldNotComputeSha256
        case couldNotReadTheSizeOfTheTranscodedPhoto
        case thisFormatDoesNotTranscode(format: ObvMediaFormat)
    }


    /// The photo's size in pixels, with the orientation already applied.
    ///
    /// Reads the metadata only, no pixel, so it is cheap to ask of every photo. An iPhone portrait is stored landscape with an EXIF
    /// rotation, so the orientation is applied to report what a viewer sees.
    public static func pixelSize(ofPhotoAt url: URL) -> (width: Int, height: Int)? {

        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        guard let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }

        // Orientations 5...8 are the ones that exchange the two axes (the four that include a 90° turn).
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let axesAreExchanged = (5...8).contains(orientation)

        return axesAreExchanged ? (width: height, height: width) : (width: width, height: height)
    }


    /// Whether the file holds a single image with no alpha channel, which is what a JPEG can hold without loss.
    ///
    /// A HEIC can hold several frames or transparency and its type does not say so. Reads the file's header, not its pixels. Answers false
    /// when the file cannot be read.
    public static func isOneOpaqueImage(photoAt url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return false }
        guard CGImageSourceGetCount(source) == 1 else { return false }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        return (properties[kCGImagePropertyHasAlpha] as? Bool) != true
    }


    /// Whether `format` would actually make this photo smaller.
    ///
    /// False for ``ObvMediaFormat/max``, and for any size whose cap the photo is already within: a cap is never a target, and the caller
    /// then points that size at the original. False too when the size cannot be read, so that an unreadable photo is left alone.
    public static func transcodingWouldReduce(photoAt url: URL, to format: ObvMediaFormat) -> Bool {
        guard let cap = format.longestPhotoEdgeInPixels else { return false }
        guard let size = pixelSize(ofPhotoAt: url) else { return false }
        return Swift.max(size.width, size.height) > cap
    }


    /// Writes `url`'s photo into `directory` at `format`, and describes what it wrote.
    ///
    /// Call ``transcodingWouldReduce(photoAt:to:)`` first: this throws for a format that does not transcode.
    ///
    /// It always writes a JPEG, keeping the original's name: `IMG_4021.HEIC` becomes `IMG_4021.jpeg`.
    public static func transcode(photoAt url: URL, named fileName: String, to format: ObvMediaFormat, inDirectory directory: URL) throws -> TranscodedPhoto {

        // Throws, and deliberately carries no `assertionFailure()` beside it. Refusing a size that does not transcode **is** this
        // method's contract — it is what stops a caller writing a copy of the original and offering it as the smaller option — so it is
        // a handled outcome rather than a programming error to trap on, and a debug build that aborted here could not be tested against
        // the very guard the contract rests on.
        guard let cap = format.longestPhotoEdgeInPixels, let compressionQuality = format.jpegCompressionQuality else {
            throw ObvError.thisFormatDoesNotTranscode(format: format)
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            logger.error("Could not create an image source from \(url.path, privacy: .public)")
            throw ObvError.couldNotReadPhoto(url: url)
        }

        // `kCGImageSourceCreateThumbnailWithTransform` bakes the EXIF orientation into the pixels, which is what makes the file that
        // leaves here upright whatever the camera was doing, a `CGImage` carrying no orientation of its own. Without it a portrait
        // photograph would be sent on its side to anybody whose viewer does not read the tag.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: cap,
        ]

        guard let downsized = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            logger.error("Could not downsize the photo at \(url.path, privacy: .public) to \(cap, privacy: .public)px")
            throw ObvError.couldNotDownsizePhoto
        }

        let destinationURL = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(UTType.jpeg.preferredFilenameExtension ?? "jpeg")

        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ObvError.couldNotCreateDestination
        }
        CGImageDestinationAddImage(destination, downsized, [
            kCGImageDestinationLossyCompressionQuality: compressionQuality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw ObvError.couldNotWriteTranscodedPhoto
        }

        let sha256: Data
        do {
            sha256 = try ObvCryptoSuite.sharedInstance.hashFunctionSha256().hash(fileAtUrl: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw ObvError.couldNotComputeSha256
        }

        guard let byteCount = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? nil else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw ObvError.couldNotReadTheSizeOfTheTranscodedPhoto
        }

        return TranscodedPhoto(temporaryURL: destinationURL,
                               sha256: sha256,
                               byteCount: byteCount,
                               pixelWidth: downsized.width,
                               pixelHeight: downsized.height,
                               contentType: .jpeg,
                               fileName: fileNameForTranscodedPhoto(basedOn: fileName))
    }


    /// What ``transcode(photoAt:named:to:inDirectory:onlyIfLighterThan:)`` did. The same type a video's export hands back.
    public typealias TranscodingUnderACeiling = ObvTranscodingUnderACeiling


    /// Writes `url`'s photo at `format`, and keeps the file only if it weighs strictly less than `ceiling` bytes.
    ///
    /// The ceiling is the weight of the lightest larger size, so that a smaller size never weighs more than a larger one. At equal
    /// weight the larger size is the better file for the same cost, so equality is refused too.
    public static func transcode(photoAt url: URL, named fileName: String, to format: ObvMediaFormat, inDirectory directory: URL, onlyIfLighterThan ceiling: Int64) throws -> TranscodingUnderACeiling {
        let transcoded = try transcode(photoAt: url, named: fileName, to: format, inDirectory: directory)
        guard transcoded.byteCount < ceiling else {
            try? FileManager.default.removeItem(at: transcoded.temporaryURL)
            return .notLighterThanTheCeiling(byteCount: transcoded.byteCount)
        }
        return .written(transcoded)
    }


    /// The quality a RAW is developed at. ImageIO's default for a HEIC is 0.75, measured by writing both. 0.8 is the quality of a Hi
    /// JPEG, and wrote a 48-megapixel ProRAW as 3.8 MB, where 0.9 wrote 8.8 MB.
    private static let heicQualityOfADevelopedRAW = 0.8


    /// Develops a RAW photo into a HEIC at its full size, written in `directory` under the original's stem, and returns its URL.
    ///
    /// The orientation and the metadata are copied, not applied, as in a HEIC from a camera. Measured at 1.8 s on a Mac for a
    /// 48-megapixel ProRAW, the time being the development and not the encoding.
    public static func developRAW(photoAt url: URL, inDirectory directory: URL) throws -> URL {

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            logger.error("Could not create an image source from \(url.path, privacy: .public)")
            throw ObvError.couldNotReadPhoto(url: url)
        }

        let stem = url.deletingPathExtension().lastPathComponent
        let destinationURL = directory
            .appendingPathComponent(stem.isEmpty ? UUID().uuidString : stem)
            .appendingPathExtension(UTType.heic.preferredFilenameExtension ?? "heic")

        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            throw ObvError.couldNotCreateDestination
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, [
            kCGImageDestinationLossyCompressionQuality: heicQualityOfADevelopedRAW,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw ObvError.couldNotWriteTranscodedPhoto
        }

        return destinationURL
    }


    /// `IMG_4021.HEIC` becomes `IMG_4021.jpeg`; a name with no extension simply gains one.
    private static func fileNameForTranscodedPhoto(basedOn fileName: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        let name = stem.isEmpty ? fileName : stem
        return "\(name).\(UTType.jpeg.preferredFilenameExtension ?? "jpeg")"
    }

}
