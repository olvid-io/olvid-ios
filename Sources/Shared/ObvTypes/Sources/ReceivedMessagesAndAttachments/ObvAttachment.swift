/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import CoreData
import ObvCrypto
import OlvidUtils

public struct ObvAttachment: Hashable {
    
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

    public let fromContactIdentity: ObvContactIdentifier
    public let metadata: Data
    public let totalUnitCount: Int64
    public let url: URL
    public let status: Status
    public let attachmentId: ObvAttachmentIdentifier
    public let messageUploadTimestampFromServer: Date

    public var messageIdentifier: Data {
        return attachmentId.messageId.uid.raw
    }
    public var number: Int {
        return attachmentId.attachmentNumber
    }

    public var downloadPaused: Bool {
        return self.status == .paused
    }

    
    public init(fromContactIdentity: ObvContactIdentifier, metadata: Data, totalUnitCount: Int64, url: URL, status: Status, attachmentId: ObvAttachmentIdentifier, messageUploadTimestampFromServer: Date) {
        self.fromContactIdentity = fromContactIdentity
        self.metadata = metadata
        self.totalUnitCount = totalUnitCount
        self.url = url
        self.status = status
        self.attachmentId = attachmentId
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(attachmentId)
    }
    
    
    public enum ObvError: Error {
        case couldNotGetAttachment
        case couldNotDecodeStatus

        var localizedDescription: String {
            switch self {
            case .couldNotGetAttachment:
                return "Could not get attachment"
            case .couldNotDecodeStatus:
                return "Could not decode status"
            }
        }
    }

}
