/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

public struct ObvNetworkReceivedMessageEncrypted: Hashable {
    public let messageId: MessageIdentifier
    public let encryptedContent: EncryptedData
    public let attachmentCount: Int
    public let messageUploadTimestampFromServer: Date
    public let downloadTimestampFromServer: Date
    public let localDownloadTimestamp: Date
    public let wrappedKey: EncryptedData
    public let hasEncryptedExtendedMessagePayload: Bool

    public init(messageId: MessageIdentifier, messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, localDownloadTimestamp: Date, encryptedContent: EncryptedData, wrappedKey: EncryptedData, attachmentCount: Int, hasEncryptedExtendedMessagePayload: Bool) {
        self.messageId = messageId
        self.encryptedContent = encryptedContent
        self.attachmentCount = attachmentCount
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.wrappedKey = wrappedKey
        self.downloadTimestampFromServer = downloadTimestampFromServer
        self.localDownloadTimestamp = localDownloadTimestamp
        self.hasEncryptedExtendedMessagePayload = hasEncryptedExtendedMessagePayload
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(messageId)
    }

}
