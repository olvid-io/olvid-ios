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


/// How much of an attachment has been downloaded.
///
/// Bytes rather than a fraction, deliberately: the engine states what it knows and leaves the presentation to the app. A throughput and an estimated time
/// remaining are computed from these two numbers and the moment they arrived, which is what `ObvProgress` does on the app side, so reporting a fraction would
/// mean a second mechanism the day those are wanted.
public struct ObvAttachmentDownloadProgress: Sendable, Equatable, Hashable {

    public let totalBytesWritten: Int64
    public let totalBytesExpectedToWrite: Int64

    public init(totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        self.totalBytesWritten = totalBytesWritten
        self.totalBytesExpectedToWrite = totalBytesExpectedToWrite
    }

    /// Between 0 and 1, and zero for an attachment whose size is not known yet rather than a division by zero.
    public var fractionCompleted: Double {
        guard totalBytesExpectedToWrite > 0 else { return 0 }
        return min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

}
