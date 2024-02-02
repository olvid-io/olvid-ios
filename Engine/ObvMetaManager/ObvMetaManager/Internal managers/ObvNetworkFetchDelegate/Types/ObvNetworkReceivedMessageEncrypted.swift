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

/// This struct represents an encrypted message received through the network, either via a push notification (in which case the number of attachments is not known, and the encryptedExtendedContent may be available) or via the normal connection we have with the server (in which case the number of attachments is known, while the encrypted content is not available as it is downloaded asynchronously).
public struct ObvNetworkReceivedMessageEncrypted: Hashable {

    public let messageId: ObvMessageIdentifier
    public let encryptedContent: EncryptedData
    public let knownAttachmentCount: Int?
    public let messageUploadTimestampFromServer: Date
    public let downloadTimestampFromServer: Date
    public let localDownloadTimestamp: Date
    public let wrappedKey: EncryptedData
    public let availableEncryptedExtendedContent: EncryptedData?

    public init(messageId: ObvMessageIdentifier, messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, localDownloadTimestamp: Date, encryptedContent: EncryptedData, wrappedKey: EncryptedData, knownAttachmentCount: Int?, availableEncryptedExtendedContent: EncryptedData?) {
        self.messageId = messageId
        self.encryptedContent = encryptedContent
        self.knownAttachmentCount = knownAttachmentCount
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.wrappedKey = wrappedKey
        self.downloadTimestampFromServer = downloadTimestampFromServer
        self.localDownloadTimestamp = localDownloadTimestamp
        self.availableEncryptedExtendedContent = availableEncryptedExtendedContent
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(messageId)
    }

}
