/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

public struct ObvNetworkFetchReceivedAttachment {
    
    public enum Status: Int, CustomDebugStringConvertible {
        case paused = 0
        case resumed = 1
        case downloaded = 2
        case cancelledByServer = 3
        case markedForDeletion = 4
        
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
    public let attachmentId: AttachmentIdentifier
    public let metadata: Data
    public let totalUnitCount: Int64 // Bytes of the plaintext
    public let url: URL
    public let status: Status
    public let messageUploadTimestampFromServer: Date
    public let downloadTimestampFromServer: Date
    
    public init(fromCryptoIdentity: ObvCryptoIdentity, attachmentId: AttachmentIdentifier, messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, metadata: Data, totalUnitCount: Int64, url: URL, status: Status) {
        self.fromCryptoIdentity = fromCryptoIdentity
        self.attachmentId = attachmentId
        self.metadata = metadata
        self.url = url
        self.status = status
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.totalUnitCount = totalUnitCount
        self.downloadTimestampFromServer = downloadTimestampFromServer
    }
}
