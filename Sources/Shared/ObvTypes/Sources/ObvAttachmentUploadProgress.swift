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


/// How far the upload of one attachment has got, as the send manager reports it.
///
/// The counterpart of ``ObvAttachmentDownloadProgress``, and deliberately a type of its own rather than that one reused: the two are the
/// same shape today and are not the same fact, and a value called a *download* progress arriving from the send manager is the kind of
/// thing that reads as a mistake for years.
public struct ObvAttachmentUploadProgress: Sendable, Equatable, Hashable {

    public let totalBytesSent: Int64
    public let totalBytesExpectedToSend: Int64

    public init(totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        self.totalBytesSent = totalBytesSent
        self.totalBytesExpectedToSend = totalBytesExpectedToSend
    }

    /// Between 0 and 1, and zero for an attachment whose size is not known yet rather than a division by zero.
    public var fractionCompleted: Double {
        guard totalBytesExpectedToSend > 0 else { return 0 }
        return min(1, max(0, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }

}
