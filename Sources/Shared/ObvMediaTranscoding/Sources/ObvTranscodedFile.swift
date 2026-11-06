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


/// One attachment written at one size, described well enough that the caller never has to open it again.
///
/// **One type for both media, and that is what keeps the recording of them to one path.** `ObvPhotoTranscoder` and `ObvVideoTranscoder`
/// have nothing in common on the inside — ImageIO against `AVAssetExportSession`, milliseconds against tens of seconds — but what they
/// hand back is the same thing: a file somewhere temporary, its hash, its weight and its pixels. `CreateDraftFyleJoinVariantsOperation`
/// therefore has one case to handle rather than two that would have to be kept in step, and a third medium later adds none.
public struct ObvTranscodedFile: Sendable {

    /// Where the bytes are. **The caller owns this file**: it must move it into the `Fyle` store or trash it. Nothing else knows the
    /// path, so a file left here is a leak in the shared container that no sweep would ever find.
    public let temporaryURL: URL

    public let sha256: Data
    public let byteCount: Int64
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let contentType: UTType
    public let fileName: String

    public init(temporaryURL: URL, sha256: Data, byteCount: Int64, pixelWidth: Int, pixelHeight: Int, contentType: UTType, fileName: String) {
        self.temporaryURL = temporaryURL
        self.sha256 = sha256
        self.byteCount = byteCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.contentType = contentType
        self.fileName = fileName
    }

}


/// What a transcoder did when asked to write a size only if it weighs strictly less than a ceiling.
public enum ObvTranscodingUnderACeiling: Sendable {
    /// The size was written and weighs less than the ceiling. The caller owns the file.
    case written(ObvTranscodedFile)
    /// The size was written and weighed `byteCount`, which is not less than the ceiling. The file has been deleted.
    case notLighterThanTheCeiling(byteCount: Int64)
}
