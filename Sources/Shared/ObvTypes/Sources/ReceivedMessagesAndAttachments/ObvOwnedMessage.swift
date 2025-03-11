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


/// An application message sent by one of the other owned devices of an owned identity.
public struct ObvOwnedMessage: Equatable, Hashable {
    
    public let messageId: ObvMessageIdentifier
    public let attachments: [ObvOwnedAttachment]
    public let expectedAttachmentsCount: Int
    public let messageUploadTimestampFromServer: Date
    public let downloadTimestampFromServer: Date
    public let localDownloadTimestamp: Date
    public let messagePayload: Data
    public let extendedMessagePayload: Data?
    public let deviceUID: UID? // Non nil when the other device is known

    /// Legacy variable. Use ``messageUID`` instead.
    public var messageIdentifierFromEngine: Data {
        return messageId.uid.raw
    }
    
    public var messageUID: UID {
        return messageId.uid
    }

    public var ownedCryptoId: ObvCryptoId {
        ObvCryptoId(cryptoIdentity: messageId.ownedCryptoIdentity)
    }
    
    /// Non nil when the other device is known
    public var ownedDeviceIdentifier: ObvOwnedDeviceIdentifier? {
        guard let deviceUID else { return nil }
        return .init(ownedCryptoId: ownedCryptoId, deviceUID: deviceUID)
    }

    public init(messageId: ObvMessageIdentifier, attachments: [ObvOwnedAttachment], expectedAttachmentsCount: Int, messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, localDownloadTimestamp: Date, messagePayload: Data, extendedMessagePayload: Data?, deviceUID: UID?) {
        self.messageId = messageId
        self.attachments = attachments
        self.expectedAttachmentsCount = expectedAttachmentsCount
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.downloadTimestampFromServer = downloadTimestampFromServer
        self.localDownloadTimestamp = localDownloadTimestamp
        self.messagePayload = messagePayload
        self.extendedMessagePayload = extendedMessagePayload
        self.deviceUID = deviceUID
    }
    
    public enum ObvError: Error {
        case fromIdentityIsDifferentFromTheOwnedIdentity

        var localizedDescription: String {
            switch self {
            case .fromIdentityIsDifferentFromTheOwnedIdentity:
                return "From identity is different from the owned identity"
            }
        }
    }

}
