/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvCrypto


public struct ObvMessage: Equatable, Hashable {
    
    public let fromContactIdentity: ObvContactIdentifier
    public let messageId: ObvMessageIdentifier
    public let attachments: [ObvAttachment]
    public let expectedAttachmentsCount: Int
    public let messageUploadTimestampFromServer: Date
    public let downloadTimestampFromServer: Date
    public let localDownloadTimestamp: Date
    public let messagePayload: Data
    public let extendedMessagePayload: Data?
    public let fromContactDeviceUID: UID? // Non nil when the device is known

    /// Legacy variable. Use `messageUID` instead.
    public var messageIdentifierFromEngine: Data {
        return messageId.uid.raw
    }
    
    public var messageUID: UID {
        return messageId.uid
    }

    /// Non-nil when the contact device is known
    public var contactDeviceIdentifier: ObvContactDeviceIdentifier? {
        guard let fromContactDeviceUID else { return nil }
        return .init(contactIdentifier: fromContactIdentity, deviceUID: fromContactDeviceUID)
    }
    
    
    public init(fromContactIdentity: ObvContactIdentifier, fromContactDeviceUID: UID?, messageId: ObvMessageIdentifier, attachments: [ObvAttachment], expectedAttachmentsCount: Int, messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, localDownloadTimestamp: Date, messagePayload: Data, extendedMessagePayload: Data?) {
        self.fromContactIdentity = fromContactIdentity
        self.messageId = messageId
        self.attachments = attachments
        self.expectedAttachmentsCount = expectedAttachmentsCount
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.downloadTimestampFromServer = downloadTimestampFromServer
        self.localDownloadTimestamp = localDownloadTimestamp
        self.messagePayload = messagePayload
        self.extendedMessagePayload = extendedMessagePayload
        self.fromContactDeviceUID = fromContactDeviceUID
    }
    
    
    public enum ObvError: Error {
        case fromIdentityIsEqualToOwnedIdentity

        var localizedDescription: String {
            switch self {
            case .fromIdentityIsEqualToOwnedIdentity:
                return "From identity is equal to the owned identity"
            }
        }
    }

}
