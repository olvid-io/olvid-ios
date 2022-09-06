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
import CoreData
import ObvMetaManager
import ObvTypes
import OlvidUtils

public struct ObvMessage {
    
    public let fromContactIdentity: ObvContactIdentity
    internal let messageId: MessageIdentifier
    public let attachments: [ObvAttachment]
    public let messageUploadTimestampFromServer: Date
    public let downloadTimestampFromServer: Date
    public let localDownloadTimestamp: Date
    public let messagePayload: Data

    public var messageIdentifierFromEngine: Data {
        return messageId.uid.raw
    }

    var toIdentity: ObvOwnedIdentity {
        return fromContactIdentity.ownedIdentity
    }
    
    var ownedCryptoId: ObvCryptoId {
        return fromContactIdentity.ownedIdentity.cryptoId
    }
    
    
    private static func makeError(message: String, code: Int = 0) -> Error {
        NSError(domain: "ObvMessage", code: code, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

    
    init(messageId: MessageIdentifier, networkFetchDelegate: ObvNetworkFetchDelegate, identityDelegate: ObvIdentityDelegate, within obvContext: ObvContext) throws {

        guard let networkReceivedMessage = networkFetchDelegate.getDecryptedMessage(messageId: messageId, flowId: obvContext.flowId) else {
            throw Self.makeError(message: "The call to getDecryptedMessage did fail")
        }
        
        try self.init(networkReceivedMessage: networkReceivedMessage, networkFetchDelegate: networkFetchDelegate, identityDelegate: identityDelegate, within: obvContext)
        
    }
    
    
    init(networkReceivedMessage: ObvNetworkReceivedMessageDecrypted, networkFetchDelegate: ObvNetworkFetchDelegate, identityDelegate: ObvIdentityDelegate, within obvContext: ObvContext) throws {
        guard let obvContact = ObvContactIdentity(contactCryptoIdentity: networkReceivedMessage.fromIdentity,
                                                  ownedCryptoIdentity: networkReceivedMessage.messageId.ownedCryptoIdentity,
                                                  identityDelegate: identityDelegate,
                                                  within: obvContext) else {
            throw Self.makeError(message: "Could not get ObvContactIdentity")
        }
        
        self.fromContactIdentity = obvContact
        self.messageId = networkReceivedMessage.messageId
        self.messagePayload = networkReceivedMessage.messagePayload
        self.messageUploadTimestampFromServer = networkReceivedMessage.messageUploadTimestampFromServer
        self.downloadTimestampFromServer = networkReceivedMessage.downloadTimestampFromServer
        self.localDownloadTimestamp = networkReceivedMessage.localDownloadTimestamp
        
        self.attachments = try networkReceivedMessage.attachmentIds.map {
            return try ObvAttachment(attachmentId: $0, fromContactIdentity: obvContact, networkFetchDelegate: networkFetchDelegate, within: obvContext)
        }
    }
}


// MARK: - Codable

extension ObvMessage: Codable {
    
    /// ObvMessage is codable so as to be able to transfer a message from the notification service to the main app.
    /// This serialization should **not** be used within long term storage since we may change it regularly.
    /// Si also `ObvContactIdentity` and  `ObvAttachment`.

    enum CodingKeys: String, CodingKey {
        case fromContactIdentity = "from_contact_identity"
        case messageId = "message_id"
        case attachments = "attachments"
        case messageUploadTimestampFromServer = "messageUploadTimestampFromServer"
        case downloadTimestampFromServer = "downloadTimestampFromServer"
        case messagePayload = "message_payload"
        case localDownloadTimestamp = "localDownloadTimestamp"
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
