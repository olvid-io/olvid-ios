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
import Intents
import UniformTypeIdentifiers
import Foundation
import OSLog
import ObvAppCoreConstants


extension INFile {

    enum TranscodeError: Error {
        case couldNotCreateExportSession
        case exportFailed(status: AVAssetExportSession.Status)
        case inputTooLarge(byteCount: Int)
    }

    /// Maximum accepted input size for ``transcodeToM4A()``. Keeps the peak of CAF (in `self.data`)
    /// plus M4A (read back into memory after export) well under the Intents Extension's ~32 MB budget.
    /// Siri's audio messages are capped at ~1 min and are typically a few MB of CAF, so this cap is
    /// far above any real-world input — it exists to fail loudly if Apple ever lifts the dictation cap.
    private static let maxTranscodeInputByteCount: Int = 10 * 1024 * 1024

    private static let transcodeLogger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "INFile+Transcode")

    /// Transcodes the audio data of this file to an `INFile` containing M4A encoded with AAC-LC.
    ///
    /// Siri delivers audio messages as CAF files (typically containing Linear PCM). CAF is an
    /// Apple-only container and will not play on Android. This method converts the audio to M4A
    /// (AAC-LC at 128 kbps), which plays natively on both iOS and Android.
    ///
    /// `INFile.fileURL` points to a location outside the Intents Extension sandbox and cannot be
    /// read directly. The audio is therefore always materialised from the in-memory `data` property
    /// into a temporary CAF file before transcoding.
    ///
    /// The asset's tracks are loaded asynchronously before the export session is created; this is
    /// required because `AVAssetExportSession` returns `nil` when the asset has not yet been
    /// inspected.
    ///
    /// All temporary files are deleted before this method returns. The caller receives a plain
    /// `INFile` whose `data` contains the M4A bytes and requires no further cleanup.
    ///
    /// **Memory note.** Intent extensions run inside a ~32 MB process budget on older devices.
    /// Around the export call this method holds two audio blobs in memory simultaneously: the
    /// input CAF (`self.data`) and the resulting M4A (`m4aData`). For Siri-sized voice clips
    /// (typically < 1 min, so a few MB of CAF and < 1 MB of M4A) this is comfortably within budget.
    /// If Siri ever lifts its dictation cap, switch to a `fileURL`-based pipeline so the M4A
    /// payload doesn't have to round-trip through process memory.
    ///
    /// - Returns: An `INFile` whose `data` contains the transcoded M4A audio.
    /// - Throws: `TranscodeError` if the export session could not be created or the export failed.
    func transcodeToM4A() async throws -> INFile {

        // Reject oversized inputs before materialising them. The peak of self.data + the M4A data
        // read back after export must stay under the ~32 MB extension budget; the cap here gives
        // generous headroom over Siri's typical sub-1-minute clips. Logged as .fault so we see it
        // if Apple ever lifts the dictation cap.
        guard data.count <= Self.maxTranscodeInputByteCount else {
            let dataCount = data.count
            Self.transcodeLogger.fault("🎙️ Refusing to transcode \(dataCount, privacy: .public) bytes (cap \(Self.maxTranscodeInputByteCount, privacy: .public))")
            throw TranscodeError.inputTooLarge(byteCount: data.count)
        }

        // INFile.fileURL points to a location outside the Intents Extension sandbox and cannot
        // be read directly. Always materialise from the in-memory data property instead.
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")
        try data.write(to: inputURL)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let asset = AVURLAsset(url: inputURL)

        // Load tracks asynchronously before creating the export session.
        // AVAssetExportSession returns nil when the asset has not yet been inspected.
        _ = try await asset.loadTracks(withMediaType: .audio)

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscodeError.couldNotCreateExportSession
        }

        if #available(iOS 18.0, *) {
            // iOS 18 throwing API replaces the property-based setup + status-polling pattern below.
            try await session.export(to: outputURL, as: .m4a)
        } else {
            session.outputURL = outputURL
            session.outputFileType = .m4a
            await session.export()
            if let error = session.error {
                throw error
            }
            guard session.status == .completed else {
                throw TranscodeError.exportFailed(status: session.status)
            }
        }

        let m4aData = try Data(contentsOf: outputURL)

        let baseName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        // When Siri gives us no usable base name, prefix the fallback with a Unix timestamp so multiple
        // voice messages saved by the recipient don't all share the same `olvidaudio.m4a` filename.
        let m4aFilename = (baseName.isEmpty ? "\(Int(Date.now.timeIntervalSince1970))-olvidaudio" : baseName) + ".m4a"

        return INFile(data: m4aData, filename: m4aFilename, typeIdentifier: UTType.mpeg4Audio.identifier)
    }

}
