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
import Foundation
import OSLog
import ObvAppCoreConstants
import ObvAppTypes
import ObvCrypto
import OlvidUtils
import UniformTypeIdentifiers


/// Makes one video smaller, and nothing else.
///
/// The same contract as `ObvPhotoTranscoder`: no Core Data and no knowledge of drafts. An export takes tens of seconds, so it reports its
/// progress and can be cancelled.
///
/// An `AVAssetWriter` rather than the export presets, which pick their own bitrate (heavier than an iPhone's own 1080p at 720p) and keep
/// the frame rate. Each size gets ``ObvMediaFormat/videoBitRate`` and at most 30 fps; an `AVVideoComposition` in BT.709 rotates, scales
/// and converts HDR to SDR. The output is H.264 in MP4, which every platform reads.
///
/// The sound is every *enabled* sound track mixed into one AAC track, which is what a player does with such a clip and what the export
/// presets do. Keeping one track instead muted a clip whose first track was silent and whose voice was on a second one.
///
/// Whether an export would reduce a clip is a question of weight, not of frame: a 1080p clip at 90 Mb/s is within the 1080p cap and would
/// still shrink tenfold. ``estimatedByteCount(of:to:)`` estimates it from the bitrates and the duration, and
/// ``estimateOfAnExportWorthMaking(of:to:belowACeilingOf:)`` decides from that estimate whether to export.
///
/// **The URL must carry a file extension.** AVFoundation refuses a file without one, without an error, and a `Fyle` is named by its
/// sha256 with none. Callers go through a hardlink; see
/// `ObvVideoTranscoderTests.testAClipIsUnreadableWithoutAnExtensionWhichIsWhyTheMakerUsesAHardlink`.
public enum ObvVideoTranscoder {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ObvVideoTranscoder")

    /// The container everything written here is wrapped in, and the type recorded for it.
    ///
    /// MP4/H.264 rather than HEVC, which would roughly halve the weight: Olvid is sent to Android, to desktop and to whatever the
    /// recipient opens it with, and a clip that will not play is worse at every size than one that is twice as large.
    private static let outputFileType: AVFileType = .mp4
    private static let outputContentType: UTType = .mpeg4Movie


    /// One video written at one size. The very same type a photo's downscale hands back — see ``ObvTranscodedFile``.
    public typealias TranscodedVideo = ObvTranscodedFile


    public enum ObvError: Error {
        case thisFormatDoesNotTranscode(format: ObvMediaFormat)
        case couldNotReadVideo(url: URL)
        case exportDidNotComplete(status: Int, error: Error?)
        case exportWasCancelled
        case theExportProducedNothing
        case couldNotComputeSha256
        case couldNotReadTheSizeOfTheTranscodedVideo
    }


    // MARK: - Reading the source

    /// The clip's size in pixels, with the track's transform already applied.
    ///
    /// An iPhone portrait clip is stored landscape with a 90° rotation, so the transform is applied to report what a viewer sees. Nil for a
    /// file with no video track.
    public static func pixelSize(ofVideoAt url: URL) async -> (width: Int, height: Int)? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        return await pixelSize(of: track)
    }


    private static func pixelSize(of track: AVAssetTrack) async -> (width: Int, height: Int)? {

        guard let naturalSize = try? await track.load(.naturalSize),
              let preferredTransform = try? await track.load(.preferredTransform) else { return nil }

        let transformed = naturalSize.applying(preferredTransform)

        // `applying` can hand back a negative extent for a transform that flips an axis; the size is its magnitude.
        let width = Int(abs(transformed.width).rounded())
        let height = Int(abs(transformed.height).rounded())

        guard width > 0, height > 0 else { return nil }

        return (width: width, height: height)
    }


    // MARK: - Estimating an export

    /// What an estimate of a clip's export needs to know about the clip. These facts never change for a given file.
    public struct ClipFacts: Sendable, Hashable {

        public let durationInSeconds: Double

        /// The channels of the sound an export would write: 0 for a clip without sound, otherwise 1 or 2.
        public let channelsOfTheSound: Int

        public init(durationInSeconds: Double, channelsOfTheSound: Int) {
            self.durationInSeconds = durationInSeconds
            self.channelsOfTheSound = channelsOfTheSound
        }

    }


    /// Reads the facts an estimate needs. It reads the clip's header only and decodes nothing.
    ///
    /// Nil when the clip cannot be read, which includes a clip whose pixel size cannot be read: such a clip is never exported.
    public static func facts(ofVideoAt url: URL) async -> ClipFacts? {

        let asset = AVURLAsset(url: url)

        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
              await pixelSize(of: videoTrack) != nil,
              let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 else { return nil }

        let channelsOfTheSound = await soundTracksToKeep(of: asset)?.channelsWritten ?? 0

        return ClipFacts(durationInSeconds: duration.seconds, channelsOfTheSound: channelsOfTheSound)

    }


    /// What an export of a clip with these facts would weigh at `format`: the bitrates of the format times the duration. Nil for
    /// ``ObvMediaFormat/max``, which is not an export.
    public static func estimatedByteCount(of facts: ClipFacts, to format: ObvMediaFormat) -> Int64? {

        guard let videoBitRate = format.videoBitRate, let audioBitRate = format.audioBitRate else { return nil }

        let soundBitRate = facts.channelsOfTheSound > 0 ? bitRateOfTheSound(audioBitRate, channels: facts.channelsOfTheSound) : 0
        let bitsPerSecond = Double(videoBitRate + soundBitRate)

        return Int64((facts.durationInSeconds * bitsPerSecond / 8 * encoderOvershoot).rounded())

    }


    /// How much heavier than its bitrates an encoded clip comes out: from 1.0 % to 3.4 % over nine exports of three iPhone clips.
    private static let encoderOvershoot = 1.03


    /// The bitrate the sound is written at: the format's, but at most 64 kb/s per channel. The writer and the estimate both use it.
    static func bitRateOfTheSound(_ audioBitRate: Int, channels: Int) -> Int {
        Swift.min(audioBitRate, 64_000 * channels)
    }


    /// The estimated weight of an export at `format`, when that export is worth making. Nil otherwise: the size then uses the file of
    /// the size that sets `ceiling`.
    ///
    /// The one rule that decides whether to export. ``transcodingWouldReduce(videoAt:to:belowACeilingOf:)`` asks it before an export,
    /// and the size menu asks it to show what a size would weigh, so that both give the same answer.
    ///
    /// - Parameter ceiling: the weight the export must be lighter than, which is the weight of the lightest larger size.
    public static func estimateOfAnExportWorthMaking(of facts: ClipFacts, to format: ObvMediaFormat, belowACeilingOf ceiling: Int64) -> Int64? {

        guard let estimate = estimatedByteCount(of: facts, to: format) else { return nil }

        // A saving so small that it is not worth an export: the reader gets a file that weighs the same, having spent the battery and the
        // heat of a re-encode on it. The threshold is a judgement rather than a measurement, and it is stated here rather than buried at
        // a call site so that there is one number to move when somebody measures what it should be.
        guard Double(estimate) < Double(ceiling) * 0.95 else { return nil }

        return estimate

    }


    /// What choosing `format` would make a clip weigh, without exporting anything: the estimate of its export when one would be made,
    /// and otherwise `ceiling`, the weight of the file the size would use instead.
    ///
    /// Nil facts mean that the clip cannot be read. Such a clip is never exported, so the answer is `ceiling`.
    public static func weightIfChosen(_ format: ObvMediaFormat, ofAClipWith facts: ClipFacts?, belowACeilingOf ceiling: Int64) -> (byteCount: Int64, isAnEstimate: Bool) {
        guard let facts, let estimate = estimateOfAnExportWorthMaking(of: facts, to: format, belowACeilingOf: ceiling) else {
            return (byteCount: ceiling, isAnEstimate: false)
        }
        return (byteCount: estimate, isAnEstimate: true)
    }


    /// Whether exporting at `format` would actually make this clip smaller.
    ///
    /// False for ``ObvMediaFormat/max``, and whenever the estimated export is not lighter than the ceiling: the caller then points the size
    /// at a larger one's file. Compares weights, not resolutions. False too when a weight cannot be read.
    ///
    /// - Parameter ceiling: the weight the export must be lighter than, which is the weight of the lightest larger size. Nil means the
    /// weight of the file at `url`.
    public static func transcodingWouldReduce(videoAt url: URL, to format: ObvMediaFormat, belowACeilingOf ceiling: Int64? = nil) async -> Bool {

        guard format.isATranscode else { return false }

        guard let ceiling = ceiling ?? byteCount(ofFileAt: url) else { return false }
        guard let facts = await facts(ofVideoAt: url), let estimate = estimatedByteCount(of: facts, to: format) else { return false }

        let worthwhile = estimateOfAnExportWorthMaking(of: facts, to: format, belowACeilingOf: ceiling) != nil

        logger.notice("🎬 \(format.rawValue, privacy: .public): the export is estimated at \(estimate, privacy: .public) bytes against a ceiling of \(ceiling, privacy: .public), so it \(worthwhile ? "is worth doing" : "is not worth doing", privacy: .public)")

        return worthwhile

    }


    // MARK: - Doing the work

    /// Exports `url`'s clip at `format`, and keeps the file only if it weighs strictly less than `ceiling` bytes.
    ///
    /// The ceiling is the weight of the lightest larger size, so that a smaller size never weighs more than a larger one. At equal
    /// weight the larger size is the better file for the same cost, so equality is refused too.
    public static func transcode(videoAt url: URL, named fileName: String, to format: ObvMediaFormat, inDirectory directory: URL, onlyIfLighterThan ceiling: Int64, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> ObvTranscodingUnderACeiling {
        let transcoded = try await transcode(videoAt: url, named: fileName, to: format, inDirectory: directory, onProgress: onProgress)
        guard transcoded.byteCount < ceiling else {
            try? FileManager.default.removeItem(at: transcoded.temporaryURL)
            return .notLighterThanTheCeiling(byteCount: transcoded.byteCount)
        }
        return .written(transcoded)
    }


    /// Exports `url`'s clip into `directory` at `format`, and describes what it wrote.
    ///
    /// Call ``transcodingWouldReduce(videoAt:to:belowACeilingOf:)`` first: this throws for a format that does not transcode. An export
    /// heavier than expected is returned as it is, with its weight, for the caller to compare.
    ///
    /// - Parameter onProgress: called repeatedly while the export runs, with the fraction completed. Called from an arbitrary context,
    /// so a caller that touches UI state hops itself.
    public static func transcode(videoAt url: URL, named fileName: String, to format: ObvMediaFormat, inDirectory directory: URL, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> TranscodedVideo {
        try await transcode(videoAt: url, named: fileName, to: format, inDirectory: directory, onProgress: onProgress, appendingAPictureOutOfOrderAfter: nil)
    }


    /// - Parameter picturesBeforeTheFault: for tests only, nil otherwise. After this many pictures, the next one is appended with a
    /// presentation time of zero, earlier than the ones already appended, which makes the writer fail.
    static func transcode(videoAt url: URL, named fileName: String, to format: ObvMediaFormat, inDirectory directory: URL, onProgress: (@Sendable (Double) -> Void)?, appendingAPictureOutOfOrderAfter picturesBeforeTheFault: Int?) async throws -> TranscodedVideo {

        // Throws, and carries no `assertionFailure()` beside it, for the reason written out in `ObvPhotoTranscoder.transcode(...)`:
        // refusing a size that does not transcode *is* this method's contract, so it is a handled outcome rather than a programming
        // error, and a debug build that aborted here could not be tested against the guard the contract rests on.
        guard let frame = format.videoDimensions, let videoBitRate = format.videoBitRate, let audioBitRate = format.audioBitRate else {
            throw ObvError.thisFormatDoesNotTranscode(format: format)
        }

        let asset = AVURLAsset(url: url)

        guard let isReadable = try? await asset.load(.isReadable), isReadable,
              let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await videoTrack.load(.naturalSize),
              let preferredTransform = try? await videoTrack.load(.preferredTransform),
              let nominalFrameRate = try? await videoTrack.load(.nominalFrameRate),
              let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 else {
            logger.error("🎬 The video at \(url.lastPathComponent, privacy: .public) cannot be read")
            throw ObvError.couldNotReadVideo(url: url)
        }

        // **No copy of the source is made**, where the share extension copies before exporting. That copy is not a precaution about
        // exporting, it is about security-scoped URLs handed in from another process; here the file is one of our own `Fyle`s, in our own
        // container, and copying a clip of a gigabyte before touching it would cost the whole of it in time and in space.

        let destinationURL = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(outputContentType.preferredFilenameExtension ?? "mp4")

        let framesPerSecond = nominalFrameRate > 0 ? Swift.min(nominalFrameRate.rounded(), maximumFramesPerSecond) : maximumFramesPerSecond

        let soundTracks = await soundTracksToKeep(of: asset)

        let encoding: VideoReencoding
        do {
            encoding = try VideoReencoding(asset: asset,
                                           videoTrack: videoTrack,
                                           soundTracks: soundTracks,
                                           renderSize: renderSize(of: naturalSize, transformedBy: preferredTransform, within: frame),
                                           transform: preferredTransform,
                                           naturalSize: naturalSize,
                                           framesPerSecond: framesPerSecond,
                                           duration: duration,
                                           videoBitRate: videoBitRate,
                                           audioBitRate: audioBitRate,
                                           outputURL: destinationURL,
                                           outputFileType: outputFileType,
                                           appendingAPictureOutOfOrderAfter: picturesBeforeTheFault)
        } catch {
            removeTheExport(at: destinationURL)
            logger.error("🎬 Could not prepare the export of \(format.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw ObvError.exportDidNotComplete(status: AVAssetWriter.Status.failed.rawValue, error: error)
        }

        let outcome = await withTaskCancellationHandler {
            await encoding.run(onProgress: onProgress)
        } onCancel: {
            encoding.cancel()
        }

        guard case .completed = outcome else {
            removeTheExport(at: destinationURL)
            // The ordinary case of the reader having changed their mind, or removed the clip: cancelling the task that awaits this stops the
            // reading, which lands here as `.cancelled`. Not a failure, so not logged as one.
            if case .cancelled = outcome {
                logger.notice("🎬 The export of \(format.rawValue, privacy: .public) was cancelled")
                throw ObvError.exportWasCancelled
            }
            logger.error("🎬 The export of \(format.rawValue, privacy: .public) did not complete: \(String(describing: outcome), privacy: .public)")
            throw ObvError.exportDidNotComplete(status: outcome.writerStatus.rawValue, error: outcome.error)
        }

        onProgress?(1.0)

        guard let byteCount = byteCount(ofFileAt: destinationURL), byteCount > 0 else {
            removeTheExport(at: destinationURL)
            throw ObvError.theExportProducedNothing
        }

        let sha256: Data
        do {
            sha256 = try ObvCryptoSuite.sharedInstance.hashFunctionSha256().hash(fileAtUrl: destinationURL)
        } catch {
            removeTheExport(at: destinationURL)
            throw ObvError.couldNotComputeSha256
        }

        // Read off the file that was written rather than off the preset that was asked for. A preset names a frame the clip is scaled to
        // *fit within*, so a portrait clip exported at "1920×1080" is 1080×1920, and one whose aspect ratio is neither is neither.
        guard let pixelSize = await pixelSize(ofVideoAt: destinationURL) else {
            removeTheExport(at: destinationURL)
            throw ObvError.couldNotReadTheSizeOfTheTranscodedVideo
        }

        logger.notice("🎬 \(format.rawValue, privacy: .public) written at \(videoBitRate / 1000, privacy: .public) kb/s and \(Int(framesPerSecond), privacy: .public) fps: \(pixelSize.width, privacy: .public)×\(pixelSize.height, privacy: .public), \(byteCount, privacy: .public) bytes")

        return TranscodedVideo(temporaryURL: destinationURL,
                               sha256: sha256,
                               byteCount: byteCount,
                               pixelWidth: pixelSize.width,
                               pixelHeight: pixelSize.height,
                               contentType: outputContentType,
                               fileName: fileNameForTranscodedVideo(basedOn: fileName))

    }


    // MARK: - Helpers

    /// A clip above this is brought down to it, and one at or below it keeps its own. ``ObvMediaFormat/max`` is never re-encoded, and
    /// keeps whatever the clip has.
    private static let maximumFramesPerSecond: Float = 30


    /// The clip's frame once turned upright, scaled to fit within `frame` turned the same way, never enlarged, in even pixels.
    private static func renderSize(of naturalSize: CGSize, transformedBy transform: CGAffineTransform, within frame: ObvMediaFormat.VideoDimensions) -> CGSize {
        let upright = naturalSize.applying(transform)
        let width = abs(upright.width)
        let height = abs(upright.height)
        let box = width >= height
            ? CGSize(width: frame.width, height: frame.height)
            : CGSize(width: frame.height, height: frame.width)
        let scale = Swift.min(box.width / width, box.height / height, 1)
        func even(_ value: CGFloat) -> CGFloat { Swift.max(2, (value / 2).rounded() * 2) }
        return CGSize(width: even(width * scale), height: even(height * scale))
    }


    /// The sound tracks mixed into the one written with the picture, and the widest channel count among them: every enabled track, or
    /// the first when none is enabled. Nil for a clip without sound.
    ///
    /// A disabled track is one a player does not play: an iPhone clip carries its spatial audio that way, in an alternate group with the
    /// stereo AAC it is a variant of, and mixing both would double the sound. An enabled track is one a player plays, whatever its
    /// position, so none may be dropped: a clip whose first track was silent and whose voice was on the second used to come out mute.
    private static func soundTracksToKeep(of asset: AVAsset) async -> VideoReencoding.SoundTracks? {
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        var enabledTracks = [AVAssetTrack]()
        for track in tracks where (try? await track.load(.isEnabled)) == true {
            enabledTracks.append(track)
        }
        let tracksToKeep = enabledTracks.isEmpty ? Array(tracks.prefix(1)) : enabledTracks
        guard !tracksToKeep.isEmpty else { return nil }
        var channelCount = 1
        for track in tracksToKeep {
            guard let description = (try? await track.load(.formatDescriptions))?.first else { continue }
            channelCount = Swift.max(channelCount, Int(CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee.mChannelsPerFrame ?? 2))
        }
        return VideoReencoding.SoundTracks(tracks: tracksToKeep, channelCount: channelCount)
    }


    /// `IMG_4021.MOV` becomes `IMG_4021.mp4`; a name with no extension simply gains one.
    private static func fileNameForTranscodedVideo(basedOn fileName: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        let name = stem.isEmpty ? fileName : stem
        return "\(name).\(outputContentType.preferredFilenameExtension ?? "mp4")"
    }


    /// Deletes an export that is not kept, and the working files `AVAssetWriter` leaves beside it when the writing stops before the end:
    /// `<name>.sb-…`, in the same directory, found beside a failed export.
    private static func removeTheExport(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        let directory = url.deletingLastPathComponent()
        let prefixOfAWorkingFile = url.lastPathComponent + ".sb-"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(prefixOfAWorkingFile) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }


    private static func byteCount(ofFileAt url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.size] as? Int64
    }

}


/// One clip read and written again at one size: an `AVAssetReader` whose picture goes through a video composition, and an
/// `AVAssetWriter`.
///
/// `@unchecked Sendable` because the reader and the writer are not `Sendable`. Each track is pumped on a serial queue of its own, and
/// the only call made from elsewhere is ``cancel()``, which touches neither.
///
/// **Cancelling is cooperative.** `cancelReading()` called while a pump is inside `copyNextSampleBuffer()` crashed the app
/// (`EXC_BAD_ACCESS`), and Apple documents nothing about calling one while the other runs. So ``cancel()`` only raises a flag, each
/// pump stops when it sees it, and the reader is cancelled once both pumps have stopped.
private final class VideoReencoding: @unchecked Sendable {

    struct SoundTracks {
        let tracks: [AVAssetTrack]
        let channelCount: Int
        /// Mono stays mono, anything more becomes stereo.
        var channelsWritten: Int { Swift.min(channelCount, 2) }
    }

    enum Outcome: CustomStringConvertible {
        case completed
        case cancelled
        case failed(Error?)

        var writerStatus: AVAssetWriter.Status {
            switch self {
            case .completed: return .completed
            case .cancelled: return .cancelled
            case .failed: return .failed
            }
        }

        var error: Error? {
            if case .failed(let error) = self { return error }
            return nil
        }

        var description: String {
            switch self {
            case .completed: return "completed"
            case .cancelled: return "cancelled"
            case .failed(let error): return "failed (\(error?.localizedDescription ?? "no error"))"
            }
        }
    }

    enum ObvError: Error {
        case cannotAdd(String)
    }

    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let pictureOutput: AVAssetReaderVideoCompositionOutput
    private let pictureInput: AVAssetWriterInput
    private let sound: (output: AVAssetReaderOutput, input: AVAssetWriterInput)?
    private let durationInSeconds: Double

    /// Touched on the picture's queue only.
    private var lastReportedFraction = 0.0

    /// For tests only. See ``ObvVideoTranscoder/transcode(videoAt:named:to:inDirectory:onProgress:appendingAPictureOutOfOrderAfter:)``.
    private let picturesBeforeTheFault: Int?

    /// Touched on the picture's queue only.
    private var picturesAppended = 0

    /// Raised by ``cancel()``, read by the pumps before each sample and by ``run(onProgress:)``.
    private let cancellationIsRequested = OSAllocatedUnfairLock(initialState: false)

    private var isCancellationRequested: Bool {
        cancellationIsRequested.withLock { $0 }
    }

    init(asset: AVAsset, videoTrack: AVAssetTrack, soundTracks: SoundTracks?, renderSize: CGSize, transform: CGAffineTransform, naturalSize: CGSize,
         framesPerSecond: Float, duration: CMTime, videoBitRate: Int, audioBitRate: Int, outputURL: URL, outputFileType: AVFileType,
         appendingAPictureOutOfOrderAfter picturesBeforeTheFault: Int?) throws {

        self.durationInSeconds = duration.seconds
        self.picturesBeforeTheFault = picturesBeforeTheFault

        // The composition turns the clip upright, scales it, sets its frame rate and converts an HDR clip to SDR.
        let uprightWidth = abs(naturalSize.applying(transform).width)
        let scale = uprightWidth > 0 ? renderSize.width / uprightWidth : 1
        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(transform.concatenating(CGAffineTransform(scaleX: scale, y: scale)), at: .zero)
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]

        self.reader = try AVAssetReader(asset: asset)
        self.writer = try AVAssetWriter(outputURL: outputURL, fileType: outputFileType)
        writer.shouldOptimizeForNetworkUse = true

        pictureOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [videoTrack], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        pictureOutput.videoComposition = composition
        pictureOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(pictureOutput) else { throw ObvError.cannotAdd("the picture's output") }
        reader.add(pictureOutput)

        pictureInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: renderSize.width,
            AVVideoHeightKey: renderSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        pictureInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(pictureInput) else { throw ObvError.cannotAdd("the picture's input") }
        writer.add(pictureInput)

        // The reader mixes the tracks and hands over PCM already at the rate and in the channels the writer encodes, so that nothing has to
        // match by chance.
        if let soundTracks {
            let channelCount = soundTracks.channelsWritten
            let output = AVAssetReaderAudioMixOutput(audioTracks: soundTracks.tracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: channelCount,
            ])
            output.alwaysCopiesSampleData = false
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: channelCount,
                AVEncoderBitRateKey: ObvVideoTranscoder.bitRateOfTheSound(audioBitRate, channels: channelCount),
            ])
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                sound = (output, input)
            } else {
                sound = nil
            }
        } else {
            sound = nil
        }

    }


    func run(onProgress: (@Sendable (Double) -> Void)?) async -> Outcome {

        guard !isCancellationRequested else { return .cancelled }

        guard reader.startReading() else {
            return reader.status == .cancelled ? .cancelled : .failed(reader.error)
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            return .failed(writer.error)
        }
        writer.startSession(atSourceTime: .zero)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.pumpThePicture(onProgress: onProgress) }
            if sound != nil {
                group.addTask { await self.pumpTheSound() }
            }
        }

        // Both pumps have stopped, so nothing is reading and the reader can be cancelled safely.

        // Before the cancellation: a failed append stops the pumps too, and is a failure rather than a cancel.
        if writer.status == .failed {
            reader.cancelReading()
            return .failed(writer.error)
        }

        if isCancellationRequested {
            reader.cancelReading()
            writer.cancelWriting()
            return .cancelled
        }

        switch reader.status {
        case .cancelled:
            writer.cancelWriting()
            return .cancelled
        case .failed:
            writer.cancelWriting()
            return .failed(reader.error)
        default:
            break
        }

        guard writer.status == .writing else {
            writer.cancelWriting()
            return .failed(writer.error)
        }

        await writer.finishWriting()
        return writer.status == .completed ? .completed : .failed(writer.error)

    }


    /// Asks the pumps to stop. Once they have, ``run(onProgress:)`` cancels the reader and discards what was written.
    func cancel() {
        requestThatThePumpsStop()
    }


    private func requestThatThePumpsStop() {
        cancellationIsRequested.withLock { $0 = true }
    }


    private func pumpThePicture(onProgress: (@Sendable (Double) -> Void)?) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pictureInput.requestMediaDataWhenReady(on: DispatchQueue(label: "ObvVideoTranscoder.picture")) {
                while self.pictureInput.isReadyForMoreMediaData {
                    guard !self.isCancellationRequested else {
                        self.pictureInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                    guard let buffer = self.pictureOutput.copyNextSampleBuffer() else {
                        self.pictureInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                    if let onProgress, self.durationInSeconds > 0 {
                        let fraction = Swift.min(Swift.max(CMSampleBufferGetPresentationTimeStamp(buffer).seconds / self.durationInSeconds, 0), 1)
                        // Once per percent, a report being a task of its own on the receiving side.
                        if fraction >= self.lastReportedFraction + 0.01 {
                            self.lastReportedFraction = fraction
                            onProgress(fraction)
                        }
                    }
                    let bufferToAppend = self.pictureOutOfOrderIfTheFaultIsDue(buffer) ?? buffer
                    self.picturesAppended += 1
                    // A failed append stops the other pump too, rather than leaving it waiting.
                    guard self.pictureInput.append(bufferToAppend) else {
                        self.pictureInput.markAsFinished()
                        self.requestThatThePumpsStop()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }


    /// For tests only: a copy of `buffer` presented at zero, once ``picturesBeforeTheFault`` pictures have been appended. Nil otherwise.
    private func pictureOutOfOrderIfTheFaultIsDue(_ buffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let picturesBeforeTheFault, picturesAppended == picturesBeforeTheFault else { return nil }
        var timing = CMSampleTimingInfo(duration: CMSampleBufferGetDuration(buffer), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: buffer, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy)
        return copy
    }


    private func pumpTheSound() async {
        guard let input = sound?.input else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: DispatchQueue(label: "ObvVideoTranscoder.sound")) {
                guard let sound = self.sound else { return }
                while sound.input.isReadyForMoreMediaData {
                    guard !self.isCancellationRequested else {
                        sound.input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    guard let buffer = sound.output.copyNextSampleBuffer() else {
                        sound.input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    guard sound.input.append(buffer) else {
                        sound.input.markAsFinished()
                        self.requestThatThePumpsStop()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }

}
