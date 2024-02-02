/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import OlvidUtils


/// An attachment sent by one of the other owned devices of an owned identity.
public struct ObvOwnedAttachment: Hashable {
    
    public let metadata: Data
    public let totalUnitCount: Int64
    public let url: URL
    public let status: ObvAttachment.Status
    public let attachmentId: ObvAttachmentIdentifier
    public let messageUploadTimestampFromServer: Date

    public var messageIdentifier: Data {
        return attachmentId.messageId.uid.raw
    }
    public var number: Int {
        return attachmentId.attachmentNumber
    }
    
    public var ownedCryptoId: ObvCryptoId {
        ObvCryptoId(cryptoIdentity: attachmentId.messageId.ownedCryptoIdentity)
    }

    public var downloadPaused: Bool {
        return self.status == .paused
    }

    
    public init(metadata: Data, totalUnitCount: Int64, url: URL, status: ObvAttachment.Status, attachmentId: ObvAttachmentIdentifier, messageUploadTimestampFromServer: Date) {
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

        var localizedDescription: String {
            switch self {
            case .couldNotGetAttachment:
                return "Could not get attachment"
            }
        }
    }

}
