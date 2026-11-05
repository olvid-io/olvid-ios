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
import UniformTypeIdentifiers


/// One of the four sizes the photos and videos of a draft can be sent at, chosen once for the whole draft in the composition bar.
///
/// The names say a rank and not a number of pixels, because the two media do not share one: ``hi`` caps a photo at 3840px and a clip at
/// 1080p.
///
/// **The raw values are persisted**, in `PersistedDraftFyleJoinVariant.rawFormat` and in the user defaults, so they must never change.
/// They are written out rather than derived from the case names, so that renaming a case cannot change what is stored.
///
/// ``max`` is the file exactly as it was attached, never re-encoded. Its caps are therefore nil, and optional so that every caller must
/// say what it does in that case.
public enum ObvMediaFormat: String, CaseIterable, Sendable, Hashable, Identifiable {

    /// Small enough to be cheap on a poor connection, large enough to fill a phone screen.
    case low = "low"

    /// The default, and what the share extension's "standard" quality also produces.
    case med = "med"

    /// As large as this offers before ``max``, which is the file itself.
    case hi = "hi"

    /// The original file, untouched.
    case max = "max"

    public var id: String { rawValue }

    /// The cap applied to a **photo's** longest edge, or nil for ``max``, which caps nothing.
    ///
    /// A cap, not a target: a photo already shorter than this on both edges is never enlarged to meet it — see
    /// `ObvPhotoTranscoder`, which answers nil in that case so that the format reuses the original file rather than producing a
    /// second, larger copy of it.
    public var longestPhotoEdgeInPixels: Int? {
        switch self {
        case .low: return 1_280
        case .med: return 2_048
        case .hi: return 3_840
        case .max: return nil
        }
    }

    /// The JPEG quality the downscaled formats are encoded at, or nil for ``max``, which is not encoded at all.
    public var jpegCompressionQuality: Double? {
        switch self {
        case .low: return 0.50
        case .med: return 0.70
        case .hi: return 0.80
        case .max: return nil
        }
    }

    /// The average bitrate, in bits per second, a **video's** picture is encoded at, or nil for ``max``, which is not encoded at all.
    ///
    /// Chosen by watching the results on iPhone clips: the frame sizes' own presets encoded at 2.8, 10.6 and 15.4 Mb/s whatever the
    /// source, heavier at 720p than an iPhone's 1080p HEVC.
    public var videoBitRate: Int? {
        switch self {
        case .low: return 1_000_000
        case .med: return 2_500_000
        case .hi: return 5_000_000
        case .max: return nil
        }
    }

    /// The bitrate, in bits per second, a **video's** sound is encoded at, or nil for ``max``.
    public var audioBitRate: Int? {
        switch self {
        case .low: return 96_000
        case .med, .hi: return 128_000
        case .max: return nil
        }
    }

    /// What a **video** at this format is scaled to fit within, or nil for ``max``, which is the clip exactly as it was attached.
    ///
    /// A standard frame size (480p, 720p, 1080p), not the photo caps. A pair rather than a longest edge, a portrait clip fitting the same
    /// pair turned round; ``longestVideoEdgeInPixels`` gives the one number.
    public var videoDimensions: VideoDimensions? {
        switch self {
        case .low: return .init(width: 640, height: 480)
        case .med: return .init(width: 1_280, height: 720)
        case .hi: return .init(width: 1_920, height: 1_080)
        case .max: return nil
        }
    }

    /// The frame a video at this format is scaled to fit within. See ``ObvMediaFormat/videoDimensions``.
    public struct VideoDimensions: Sendable, Hashable {

        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }

        public var longestEdge: Int {
            Swift.max(width, height)
        }

    }

    /// The cap applied to a **video's** longest edge, or nil for ``max``.
    public var longestVideoEdgeInPixels: Int? {
        videoDimensions?.longestEdge
    }

    /// Whether this format re-encodes what it is given, which is every format but ``max``.
    ///
    /// Asked of the case itself rather than derived from one of the caps above, so that it goes on meaning the same thing for a photo
    /// and for a video rather than answering whichever medium's table happens to be consulted.
    public var isATranscode: Bool {
        self != .max
    }

    /// The order the menu draws them in: largest first, so the list reads as a scale rather than as an arbitrary set.
    ///
    /// `allCases` follows the order the cases are *declared* in, which is the order they are worth reading as a progression of
    /// size when reasoning about the enum, and the reverse of what the menu wants. Stating the menu's order separately means
    /// neither has to be bent to suit the other.
    public static var orderShownInMenu: [ObvMediaFormat] {
        [.max, .hi, .med, .low]
    }

    /// Of the sizes larger than `format` that have a weight in `byteCountForFormat`, the lightest one and its weight, or nil if none has.
    ///
    /// At equal weight, the largest of them: when a size points at the original, it weighs the same as ``max``, and ``max`` is then the
    /// one returned.
    public static func lightestSize(largerThan format: ObvMediaFormat, among byteCountForFormat: [ObvMediaFormat: Int64]) -> (format: ObvMediaFormat, byteCount: Int64)? {
        var lightest: (format: ObvMediaFormat, byteCount: Int64)?
        for larger in orderShownInMenu.prefix(while: { $0 != format }) {
            guard let byteCount = byteCountForFormat[larger] else { continue }
            if byteCount < (lightest?.byteCount ?? .max) {
                lightest = (larger, byteCount)
            }
        }
        return lightest
    }

}


// MARK: - What the sizes apply to

extension ObvMediaFormat {

    /// The photo types a size may be chosen for. Anything else is sent as attached.
    ///
    /// An allowlist, because every size below ``max`` is a JPEG: a type that can carry transparency or animation (PNG, GIF, WebP, AVIF)
    /// would lose it. PNG is left off although screenshots are PNG, because an iPhone screenshot has transparent corners. A HEIC can
    /// also carry either, which the type does not say; `ObvPhotoTranscoder.isOneOpaqueImage(photoAt:)` checks the file.
    ///
    /// `public.heic` does not conform to `public.heif`, so both are listed. DNG and the camera makers' RAW formats conform to
    /// `public.camera-raw-image`.
    public static let photoTypesASizeMayBeChosenFor: [UTType] = [.jpeg, .heic, .heif, .rawImage]

    /// The video types a size may be chosen for. Anything else is sent as attached.
    ///
    /// An allowlist rather than `public.movie`, which MKV, WebM, AVI and others conform to although AVFoundation cannot read them.
    /// `com.apple.m4v-video` conforms to `public.mpeg-4`. No audio type conforms to any of these, so a voice message is never exported.
    public static let videoTypesASizeMayBeChosenFor: [UTType] = [.mpeg4Movie, .quickTimeMovie] + [UTType("public.3gpp")].compactMap { $0 }

    public static func mayBeChosen(forPhotoOfType contentType: UTType) -> Bool {
        photoTypesASizeMayBeChosenFor.contains(where: { contentType.conforms(to: $0) })
    }

    public static func mayBeChosen(forVideoOfType contentType: UTType) -> Bool {
        videoTypesASizeMayBeChosenFor.contains(where: { contentType.conforms(to: $0) })
    }

}
