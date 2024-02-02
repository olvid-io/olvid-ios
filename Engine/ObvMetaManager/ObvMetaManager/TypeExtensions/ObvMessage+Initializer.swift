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


public extension ObvMessage {
    
    init(networkReceivedMessage: ObvNetworkReceivedMessageDecrypted, networkFetchDelegate: ObvNetworkFetchDelegate?, within obvContext: ObvContext) throws {
        guard networkReceivedMessage.fromIdentity != networkReceivedMessage.messageId.ownedCryptoIdentity else {
            assertionFailure()
            throw ObvError.fromIdentityIsEqualToOwnedIdentity
        }
        let fromContactIdentity = ObvContactIdentifier(contactCryptoIdentity: networkReceivedMessage.fromIdentity, ownedCryptoIdentity: networkReceivedMessage.messageId.ownedCryptoIdentity)
        let messageId = networkReceivedMessage.messageId
        let messagePayload = networkReceivedMessage.messagePayload
        let messageUploadTimestampFromServer = networkReceivedMessage.messageUploadTimestampFromServer
        let downloadTimestampFromServer = networkReceivedMessage.downloadTimestampFromServer
        let localDownloadTimestamp = networkReceivedMessage.localDownloadTimestamp
        let extendedMessagePayload = networkReceivedMessage.extendedMessagePayload
        let expectedAttachmentsCount = networkReceivedMessage.attachmentIds.count
        let attachments: [ObvAttachment]
        if let networkFetchDelegate {
            attachments = try networkReceivedMessage.attachmentIds.map {
                try ObvAttachment(attachmentId: $0, fromContactIdentity: fromContactIdentity, networkFetchDelegate: networkFetchDelegate, within: obvContext)
            }
        } else {
            attachments = []
        }
        self.init(fromContactIdentity: fromContactIdentity,
                  messageId: messageId,
                  attachments: attachments,
                  expectedAttachmentsCount: expectedAttachmentsCount,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  downloadTimestampFromServer: downloadTimestampFromServer,
                  localDownloadTimestamp: localDownloadTimestamp,
                  messagePayload: messagePayload,
                  extendedMessagePayload: extendedMessagePayload)
    }
    
}
