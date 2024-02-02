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
import ObvTypes
import ObvMetaManager


extension ObvNetworkReceivedMessageDecrypted {
    
    init(with message: ReceivedApplicationMessage, messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, localDownloadTimestamp: Date) {

        let attachmentIds = message.attachmentsInfos.enumerated().map {
            ObvAttachmentIdentifier(messageId: message.messageId, attachmentNumber: $0.offset)
        }
        self = ObvNetworkReceivedMessageDecrypted(messageId: message.messageId,
                                                  attachmentIds: attachmentIds,
                                                  fromIdentity: message.remoteCryptoIdentity,
                                                  messagePayload: message.messagePayload,
                                                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                                                  downloadTimestampFromServer: downloadTimestampFromServer,
                                                  localDownloadTimestamp: localDownloadTimestamp,
                                                  extendedMessagePayload: message.extendedMessagePayload)
    }
    
}
