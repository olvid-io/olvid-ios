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

import AVFoundation
import ObvCrypto
import UIKit
import ImageIO
@preconcurrency import ObvUICoreData
import CoreData
import os.log
import UniformTypeIdentifiers
import ObvAppCoreConstants
import ObvAppTypes
import ObvMediaTranscoding
import OlvidUtils

/// Reads an in-flight export's completed fraction from a thread other than the one that started it.
///
/// `AVAssetExportSession` is not `Sendable`, but polling its `progress` while `export()` runs is the
/// supported way to observe an export, so the unchecked conformance is deliberate and confined to this
/// single read-only access.
private final class ExportProgressReader: @unchecked Sendable {

    private let exportSession: AVAssetExportSession

    init(_ exportSession: AVAssetExportSession) {
        self.exportSession = exportSession
    }

    var fractionCompleted: Double {
        Double(exportSession.progress)
    }
}


class TranscodeUtils {

    /// Logger for this type's own messages.
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "TranscodeUtils")

    /// `Fyle.moveFileToPermanentURL(from:logTo:)` (in ObvUICoreData) still takes an `OSLog`, so we keep
    /// a single instance solely to bridge into that shared API. All of this type's own logging goes
    /// through `logger` above.
    private static let osLog = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "TranscodeUtils")

    /// Transcodes an image to standard quality: downscaled and re-encoded as JPEG.
    ///
    /// The pixel work is done by `ObvPhotoTranscoder`, in `ObvMediaTranscoding`, shared with the composition bar. This
    /// keeps only what is the extension's own: turning the result into a `Fyle` and a `FyleJoin`.
    ///
    /// The extension's "standard" quality is `ObvMediaFormat.med`, so that the app and the extension share one
    /// definition of each size.
    ///
    /// - Parameters:
    ///   - fyleJoin: The fyle join containing the image to be transcoded
    ///   - hardlinkURL: The URL to the actual file (hardlink) to read from
    ///   - context: The managed object context for creating the new fyle
    /// - Returns: A new fyle join with the transcoded image, or nil if transcoding fails
    public static func transcodeImage(_ fyleJoin: FyleJoin,
                                      hardlinkURL: URL,
                                      within context: NSManagedObjectContext) async throws -> FyleJoin? {

        guard fyleJoin.fyle != nil else { return nil }

        let format = ObvMediaFormat.med

        // Several frames or an alpha channel would be lost in a JPEG, so such a photo is sent as it is.
        guard ObvPhotoTranscoder.isOneOpaqueImage(photoAt: hardlinkURL) else {
            logger.info("The photo has several frames or an alpha channel, sending it as it is")
            return fyleJoin
        }

        // A photo already within the cap is left exactly as it is. Re-encoding it would produce a *larger* file
        // than the one the user attached, which is the opposite of what asking for standard quality means.
        guard ObvPhotoTranscoder.transcodingWouldReduce(photoAt: hardlinkURL, to: format) else {
            logger.info("The photo is already within the \(format.rawValue, privacy: .public) cap, sending it as it is")
            return fyleJoin
        }

        let transcoded: ObvPhotoTranscoder.TranscodedPhoto
        do {
            transcoded = try ObvPhotoTranscoder.transcode(photoAt: hardlinkURL,
                                                          named: fyleJoin.fileName,
                                                          to: format,
                                                          inDirectory: FileManager.default.temporaryDirectory)
        } catch {
            logger.error("Failed to transcode the photo: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        // Create the Fyle, move the file into permanent storage, and build the resulting
        // FyleJoin. All Core Data access must happen on the context's queue, so it is wrapped
        // in `performAndWait`. The heavy work above (compression, hashing) deliberately stays
        // outside the queue so it does not block it.
        let result: Result<FyleJoin, Error> = context.performAndWait {
            do {
                // Create a new Fyle for the compressed image, reusing existing if same hash exists
                let compressedFyle = try Fyle.getOrCreate(sha256: transcoded.sha256, within: context)
                // Move the compressed file from temporary location to its permanent storage location
                try compressedFyle.moveFileToPermanentURL(from: transcoded.temporaryURL, logTo: osLog)
                // Create a new FyleJoin with the compressed image as a JPEG
                let fyleJoin = FyleJoinImpl(fyle: compressedFyle,
                                            fileName: transcoded.fileName,
                                            contentType: transcoded.contentType,
                                            index: fyleJoin.index)
                return .success(fyleJoin)
            } catch {
                return .failure(error)
            }
        }

        // **Removed whichever way this went, and the success path is the one that is easy to miss.**
        // `Fyle.moveFileToPermanentURL` deliberately *leaves the source where it is* when the destination already holds that content —
        // `Fyle` being content-addressed, two files that transcode to the same bytes share one row and one file — so a success does not
        // imply the temporary file has gone. Removing it on failure alone leaves a copy of every duplicate behind.
        // The system temp directory of the extension, not the shared container, so removing it is right here.
        try? FileManager.default.removeItem(at: transcoded.temporaryURL)

        switch result {
        case .success(let fyleJoin):
            return fyleJoin
        case .failure(let error):
            logger.error("Failed to create Fyle or move transcoded image to permanent url: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Transcodes a video to standard quality (MP4 with medium/low quality preset).
    /// - Parameters:
    ///   - fyleJoin: The fyle join containing the video to be transcoded
    ///   - hardlinkURL: The URL to the actual file (hardlink) to read from
    ///   - context: The managed object context for creating the new fyle
    ///   - onProgress: Called repeatedly while the export runs, with the export's completed fraction
    ///     (0...1). Called from an arbitrary context, so callers that touch UI state must hop themselves.
    /// - Returns: A new fyle join with the transcoded video, or nil if transcoding fails
    public static func transcodeVideo(_ fyleJoin: FyleJoin,
                                      hardlinkURL: URL,
                                      within context: NSManagedObjectContext,
                                      onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> FyleJoin? {
        guard fyleJoin.fyle != nil else { return nil }
        let url = hardlinkURL

        // Verify the original file exists and is accessible
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.error("Source video file does not exist at: \(url.path, privacy: .public)")
            return nil
        }

        // Start accessing security-scoped resource if needed (for files from external sources)
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Copy the video to a temporary location before exporting. We copy on disk via
        // FileManager rather than reading the whole file into memory with Data(contentsOf:):
        // the share extension runs under a tight memory limit and a large (e.g. 4K) clip would
        // get the extension jetsam-killed. The security-scoped access started above lets the
        // streamed copy succeed for files coming from external sources.
        let tempInputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("input_\(UUID().uuidString)")
            .appendingPathExtension(url.pathExtension)

        do {
            try FileManager.default.copyItem(at: url, to: tempInputURL)
            logger.info("Successfully copied video to temp location")
        } catch {
            logger.error("Failed to copy video to temp location: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        // Ensure temp file is cleaned up
        defer {
            try? FileManager.default.removeItem(at: tempInputURL)
        }

        // Create an AVAsset from the temporary copy
        let asset = AVAsset(url: tempInputURL)

        // Verify the asset is valid and readable
        let isReadable = try await asset.load(.isReadable)
        let isExportable = try await asset.load(.isExportable)

        guard isReadable, isExportable else {
            logger.error("Video asset is not readable or exportable at temp location")
            return nil
        }

        // Choose the best available preset for standard quality transcoding
        // Prioritizes medium quality, then 640x480, then low quality
        let presetName: String
        if await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPreset960x540, with: asset, outputFileType: .mp4) {
            presetName = AVAssetExportPreset960x540
        } else if await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetMediumQuality, with: asset, outputFileType: .mp4) {
            presetName = AVAssetExportPresetMediumQuality
        } else if await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPreset640x480, with: asset, outputFileType: .mp4) {
            presetName = AVAssetExportPreset640x480
        } else if await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetLowQuality, with: asset, outputFileType: .mp4) {
            presetName = AVAssetExportPresetLowQuality
        } else {
            logger.error("No compatible export preset found for video")
            return nil
        }

        logger.info("Using export preset: \(presetName, privacy: .public)")

        // Create export session with the selected compatible preset
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: presetName) else {
            logger.error("Failed to create AVAssetExportSession with preset: \(presetName, privacy: .public)")
            return nil
        }

        // Set up output path in the temporary directory with MP4 extension
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("output_\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        // Remove output file if it already exists to avoid export errors
        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        // Configure additional settings to optimize for network use and improve compatibility
        exportSession.shouldOptimizeForNetworkUse = true

        // Export the video asynchronously, polling `progress` alongside so the caller can drive a
        // determinate bar. This is the longest step of the whole send for a large clip, and it is the one
        // the user is most likely to think has hung.
        //
        // We poll `AVAssetExportSession.progress` rather than use the iOS 18 `states(updateInterval:)`
        // sequence: the deployment target here is iOS 16, and `states(_:)` also *performs* the export, which
        // would mean two code paths for the export itself rather than just for the progress reporting.
        let progressPoller: Task<Void, Never>?
        if let onProgress {
            let progressReader = ExportProgressReader(exportSession)
            progressPoller = Task.detached(priority: .utility) {
                while !Task.isCancelled {
                    // `export()` sets `progress` to 1 only once it has finished, so the caller gets the
                    // final value from the explicit report below rather than from this loop.
                    onProgress(progressReader.fractionCompleted)
                    try? await Task.sleep(seconds: 0.2)
                }
            }
        } else {
            progressPoller = nil
        }

        await exportSession.export()

        progressPoller?.cancel()
        onProgress?(1.0)

        // Verify export completed successfully
        guard exportSession.status == .completed else {
            logger.error("Video export failed with status: \(exportSession.status.rawValue, privacy: .public)")
            if let error = exportSession.error {
                logger.error("Video export error: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }

        // Verify output file exists on disk after export
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            logger.error("Video export completed but output file does not exist")
            return nil
        }

        // Get file size to ensure the export produced valid content
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attributes[.size] as? Int ?? 0

        // Ensure the file is not empty
        guard fileSize > 0 else {
            logger.error("Video export produced empty file")
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }

        logger.info("Video transcoded successfully, output size: \(fileSize, privacy: .public) bytes")

        // Compute the SHA-256 hash of the transcoded video file
        let sha256: Data
        do {
            let Sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()
            sha256 = try Sha256.hash(fileAtUrl: outputURL)
        } catch {
            logger.error("Failed to compute SHA256 for transcoded video: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }

        // Create the Fyle, move the file into permanent storage, and build the resulting
        // FyleJoin. All Core Data access must happen on the context's queue, so it is wrapped
        // in `performAndWait`. The heavy work above (export, hashing) deliberately stays
        // outside the queue so it does not block it.

        let fileName = fyleJoin.fileName
        let fileIndex = fyleJoin.index

        let result: Result<FyleJoin, Error> = context.performAndWait {
            do {
                // Create a new Fyle for the transcoded video, reusing existing if same hash exists
                let compressedFyle = try Fyle.getOrCreate(sha256: sha256, within: context)
                // Move the transcoded file from temporary location to its permanent storage location
                try compressedFyle.moveFileToPermanentURL(from: outputURL, logTo: osLog)
                // Create a new FyleJoin with the transcoded video as an MP4
                let fyleJoin = FyleJoinImpl(fyle: compressedFyle,
                                            fileName: fileName,
                                            contentType: UTType.mpeg4Movie,
                                            index: fileIndex)
                return .success(fyleJoin)
            } catch {
                return .failure(error)
            }
        }

        switch result {
        case .success(let fyleJoin):
            return fyleJoin
        case .failure(let error):
            logger.error("Failed to create Fyle or move transcoded video to permanent url: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
    }
}
