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
import ObvCrypto
import ObvTypes

public struct ObvNetworkFetchReceivedAttachment: Equatable, Hashable {
    
    public enum Status: Hashable, Equatable, CustomDebugStringConvertible {
        case paused(expectedTotalUnitCount: Int64)
        case resumed(expectedTotalUnitCount: Int64) // expectedTotalUnitCount is the number of bytes of the plaintext
        case downloaded(url: URL, totalUnitCount: Int64) // totalUnitCount is the number of bytes of the plaintext
        case cancelledByServer
        case markedForDeletion
        
        public var debugDescription: String {
            switch self {
            case .paused: return "Paused"
            case .resumed: return "Resumed"
            case .downloaded: return "Downloaded"
            case .cancelledByServer: return "Cancelled by server"
            case .markedForDeletion: return "Marked for deletion"
            }
        }
    }

    
    public let fromCryptoIdentity: ObvCryptoIdentity
    public let attachmentId: ObvAttachmentIdentifier
    public let metadata: Data
    public let status: Status
    public let messageUploadTimestampFromServer: Date
    public let downloadTimestampFromServer: Date
    
    public init(fromCryptoIdentity: ObvCryptoIdentity, attachmentId: ObvAttachmentIdentifier, messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, metadata: Data, status: Status) {
        self.fromCryptoIdentity = fromCryptoIdentity
        self.attachmentId = attachmentId
        self.metadata = metadata
        self.status = status
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.downloadTimestampFromServer = downloadTimestampFromServer
    }
}
