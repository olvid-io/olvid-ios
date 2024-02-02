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
import ObvTypes
import OlvidUtils


public extension ObvOwnedAttachment {
    
    init(attachmentId: ObvAttachmentIdentifier, networkFetchDelegate: ObvNetworkFetchDelegate, within obvContext: ObvContext) throws {
        guard let networkReceivedAttachment = networkFetchDelegate.getAttachment(withId: attachmentId, within: obvContext) else {
            throw ObvError.couldNotGetAttachment
        }
        let attachmentId = networkReceivedAttachment.attachmentId
        let metadata = networkReceivedAttachment.metadata
        let url = networkReceivedAttachment.url
        let status = networkReceivedAttachment.status.toObvAttachmentStatus
        let messageUploadTimestampFromServer = networkReceivedAttachment.messageUploadTimestampFromServer
        let totalUnitCount = networkReceivedAttachment.totalUnitCount
        self.init(metadata: metadata,
                  totalUnitCount: totalUnitCount,
                  url: url,
                  status: status,
                  attachmentId: attachmentId,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer)
    }
    
}
