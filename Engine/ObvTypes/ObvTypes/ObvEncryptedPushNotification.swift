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


public struct ObvEncryptedPushNotification {
    
    public let messageIdFromServer: UID
    public let wrappedKey: EncryptedData
    public let encryptedContent: EncryptedData
    public let encryptedExtendedContent: EncryptedData?
    public let maskingUID: UID
    public let messageUploadTimestampFromServer: Date
    // Note that we have no downloadTimestampFromServer since this information is not avaible from APNS
    public let localDownloadTimestamp: Date
    
    public var messageIdFromServerAsString: String {
        return messageIdFromServer.hexString()
    }
    
    public var messageIdentifierFromEngine: Data {
        messageIdFromServer.raw
    }
    
    public init?(messageIdFromServer: String, wrappedKey: Data, encryptedContent: Data, encryptedExtendedContent: Data?, maskingUID: String, messageUploadTimestampFromServer: Date, localDownloadTimestamp: Date) {
        do {
            guard let uid = UID(hexString: messageIdFromServer) else { return nil }
            self.messageIdFromServer = uid
        }
        self.wrappedKey = EncryptedData(data: wrappedKey)
        self.encryptedContent = EncryptedData(data: encryptedContent)
        if let encryptedExtendedContent = encryptedExtendedContent {
            self.encryptedExtendedContent = EncryptedData(data: encryptedExtendedContent)
        } else {
            self.encryptedExtendedContent = nil
        }
        do {
            guard let uid = UID(hexString: maskingUID) else { return nil }
            self.maskingUID = uid
        }
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.localDownloadTimestamp = localDownloadTimestamp
    }
    
}
