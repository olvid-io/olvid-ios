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

public struct ObvNetworkReceivedMessageDecrypted {
    public let messageId: ObvMessageIdentifier
    public let attachmentIds: [ObvAttachmentIdentifier]
    public let fromIdentity: ObvCryptoIdentity
    public let messagePayload: Data
    public let messageUploadTimestampFromServer: Date
    public let downloadTimestampFromServer: Date
    public let localDownloadTimestamp: Date
    public let extendedMessagePayload: Data?
    
    public init(messageId: ObvMessageIdentifier, attachmentIds: [ObvAttachmentIdentifier], fromIdentity: ObvCryptoIdentity, messagePayload: Data, messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, localDownloadTimestamp: Date, extendedMessagePayload: Data?) {
        self.messageId = messageId
        self.attachmentIds = attachmentIds
        self.fromIdentity = fromIdentity
        self.messagePayload = messagePayload
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.downloadTimestampFromServer = downloadTimestampFromServer
        self.localDownloadTimestamp = localDownloadTimestamp
        self.extendedMessagePayload = extendedMessagePayload
    }

}
