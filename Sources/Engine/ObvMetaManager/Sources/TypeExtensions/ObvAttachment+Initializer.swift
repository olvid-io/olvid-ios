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
import ObvTypes
import OlvidUtils


public extension ObvAttachment {
    
    init(attachmentId: ObvAttachmentIdentifier,
         fromContactIdentity: ObvContactIdentifier,
         networkFetchDelegate: ObvNetworkFetchDelegate,
         within context: NSManagedObjectContext) throws {
        guard let networkReceivedAttachment = networkFetchDelegate.getAttachment(withId: attachmentId, within: context) else {
            throw ObvError.couldNotGetAttachment
        }
        let fromContactIdentity = fromContactIdentity
        let attachmentId = networkReceivedAttachment.attachmentId
        let metadata = networkReceivedAttachment.metadata
        let status = networkReceivedAttachment.status.toObvAttachmentStatus
        let messageUploadTimestampFromServer = networkReceivedAttachment.messageUploadTimestampFromServer
        self.init(fromContactIdentity: fromContactIdentity,
                  metadata: metadata,
                  status: status,
                  attachmentId: attachmentId,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer)
    }
    
    
    private init(networkReceivedAttachment: ObvNetworkFetchReceivedAttachment, within obvContext: ObvContext) throws {
        let fromContactIdentity = ObvContactIdentifier(contactCryptoIdentity: networkReceivedAttachment.fromCryptoIdentity, ownedCryptoIdentity: networkReceivedAttachment.attachmentId.messageId.ownedCryptoIdentity)
        let attachmentId = networkReceivedAttachment.attachmentId
        let metadata = networkReceivedAttachment.metadata
        let status = networkReceivedAttachment.status.toObvAttachmentStatus
        let messageUploadTimestampFromServer = networkReceivedAttachment.messageUploadTimestampFromServer
        self.init(fromContactIdentity: fromContactIdentity,
                  metadata: metadata,
                  status: status,
                  attachmentId: attachmentId,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer)
    }
    
}


extension ObvNetworkFetchReceivedAttachment.Status {
    
    var toObvAttachmentStatus: ObvAttachment.Status {
        switch self {
        case .paused(expectedTotalUnitCount: let expectedTotalUnitCount):
            return .paused(expectedTotalUnitCount: expectedTotalUnitCount)
        case .resumed(expectedTotalUnitCount: let expectedTotalUnitCount):
            return .resumed(expectedTotalUnitCount: expectedTotalUnitCount)
        case .downloaded(url: let url, totalUnitCount: _):
            return .downloaded(url: url)
        case .cancelledByServer:
            return .cancelledByServer
        case .markedForDeletion:
            return .markedForDeletion
        }
    }
    
}
