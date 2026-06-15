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
import CoreData
import ObvCrypto
import OlvidUtils

public struct ObvAttachment: Hashable {
    
    public enum Status: Equatable, CustomDebugStringConvertible {
        case paused(expectedTotalUnitCount: Int64)
        case resumed(expectedTotalUnitCount: Int64)
        case downloaded(url: URL)
        case cancelledByServer
        case markedForDeletion
        case receivedInUserNotification
        
        public var debugDescription: String {
            switch self {
            case .paused: return "Paused"
            case .resumed: return "Resumed"
            case .downloaded: return "Downloaded"
            case .cancelledByServer: return "Cancelled by server"
            case .markedForDeletion: return "Marked for deletion"
            case .receivedInUserNotification: return "Received in User Notification"
            }
        }
    }

    public let fromContactIdentity: ObvContactIdentifier
    public let metadata: Data
    public let status: Status
    public let attachmentId: ObvAttachmentIdentifier
    public let messageUploadTimestampFromServer: Date

    public var messageIdentifier: Data {
        return attachmentId.messageId.uid.raw
    }
    public var number: Int {
        return attachmentId.attachmentNumber
    }

    public init(fromContactIdentity: ObvContactIdentifier, metadata: Data, status: Status, attachmentId: ObvAttachmentIdentifier, messageUploadTimestampFromServer: Date) {
        self.fromContactIdentity = fromContactIdentity
        self.metadata = metadata
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
