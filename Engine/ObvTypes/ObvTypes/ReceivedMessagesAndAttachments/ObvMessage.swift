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
import OlvidUtils
import ObvCrypto


public struct ObvMessage {
    
    public let fromContactIdentity: ObvContactIdentifier
    public let messageId: ObvMessageIdentifier
    public let attachments: [ObvAttachment]
    public let expectedAttachmentsCount: Int
    public let messageUploadTimestampFromServer: Date
    public let downloadTimestampFromServer: Date
    public let localDownloadTimestamp: Date
    public let messagePayload: Data
    public let extendedMessagePayload: Data?

    /// Legacy variable. Use `messageUID` instead.
    public var messageIdentifierFromEngine: Data {
        return messageId.uid.raw
    }
    
    public var messageUID: UID {
        return messageId.uid
    }

    
    public init(fromContactIdentity: ObvContactIdentifier, messageId: ObvMessageIdentifier, attachments: [ObvAttachment], expectedAttachmentsCount: Int, messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, localDownloadTimestamp: Date, messagePayload: Data, extendedMessagePayload: Data?) {
        self.fromContactIdentity = fromContactIdentity
        self.messageId = messageId
        self.attachments = attachments
        self.expectedAttachmentsCount = expectedAttachmentsCount
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.downloadTimestampFromServer = downloadTimestampFromServer
        self.localDownloadTimestamp = localDownloadTimestamp
        self.messagePayload = messagePayload
        self.extendedMessagePayload = extendedMessagePayload
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


// MARK: - Codable

extension ObvMessage: Codable {
    
    /// ObvMessage is codable so as to be able to transfer a message from the notification service to the main app.
    /// This serialization should **not** be used within long term storage since we may change it regularly.
    /// See also `ObvContactIdentity` and `ObvAttachment`.

    enum CodingKeys: String, CodingKey {
        case fromContactIdentity = "from_contact_identity"
        case messageId = "message_id"
        case attachments = "attachments"
        case messageUploadTimestampFromServer = "messageUploadTimestampFromServer"
        case downloadTimestampFromServer = "downloadTimestampFromServer"
        case messagePayload = "message_payload"
        case localDownloadTimestamp = "localDownloadTimestamp"
        case extendedMessagePayload = "extendedMessagePayload"
        case expectedAttachmentsCount = "expectedAttachmentsCount"
    }

    public func encodeToJson() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    public static func decodeFromJson(data: Data) throws -> ObvMessage {
        let decoder = JSONDecoder()
        return try decoder.decode(ObvMessage.self, from: data)
    }
}
