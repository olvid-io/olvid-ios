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
import ObvEncoder
import ObvCrypto
import ObvTypes


public struct ReceivedMessage {
    
    public let type: ObvChannelMessageType
    let encodedElements: ObvEncoded
    let extendedMessagePayloadKey: AuthenticatedEncryptionKey?
    let channelType: ObvProtocolReceptionChannelInfo
    let extendedMessagePayload: Data? // Available only when the message was received in a notification. Not available during a "normal" reception as the extended payload is downloaded asynchronously
    private let message: ObvNetworkReceivedMessageEncrypted
    public let contentForMessageKey: Data

    var messageId: ObvMessageIdentifier { return message.messageId }
    public var knownAttachmentCount: Int? { return message.knownAttachmentCount }
    var messageUploadTimestampFromServer: Date { return message.messageUploadTimestampFromServer }
    
    public init?(with message: ObvNetworkReceivedMessageEncrypted, decryptedWith messageKey: AuthenticatedEncryptionKey, obtainedUsing channelType: ObvProtocolReceptionChannelInfo) {
        
        guard let (encodedContent, rawDecryptedContentForMessageKey) = ReceivedMessage.decryptToObvEncoded(message.encryptedContent, with: messageKey) else { return nil }
        self.contentForMessageKey = rawDecryptedContentForMessageKey
        guard let (type, encodedElements) = ReceivedMessage.parse(encodedContent) else { return nil }
        self.type = type
        self.encodedElements = encodedElements
        self.message = message
        self.channelType = channelType
        // Set the extendedMessagePayloadKey, in case there is one now (or in the future)
        let extendedMessagePayloadKey: AuthenticatedEncryptionKey?
        if let seed = Seed(withKeys: [messageKey]) {
            let prng = ObvCryptoSuite.sharedInstance.concretePRNG().init(with: seed)
            let authEnc = messageKey.algorithmImplementationByteId.algorithmImplementation
            extendedMessagePayloadKey = authEnc.generateKey(with: prng)
        } else {
            extendedMessagePayloadKey = nil
        }
        self.extendedMessagePayloadKey = extendedMessagePayloadKey
        // If the extended message payload is available (which only happens when the message was received in a notification, otherwise it is downloaded asynchronously), decrypt it now
        if let encryptedExtendedContent = message.availableEncryptedExtendedContent, let extendedMessagePayloadKey {
            self.extendedMessagePayload = Self.decryptToData(encryptedExtendedContent, with: extendedMessagePayloadKey)
        } else {
            self.extendedMessagePayload = nil
        }
    }

    private static func decryptToData(_ encryptedContent: EncryptedData, with messageKey: AuthenticatedEncryptionKey) -> Data? {
        let authEnc = messageKey.algorithmImplementationByteId.algorithmImplementation
        guard let rawEncodedElements = try? authEnc.decrypt(encryptedContent, with: messageKey) else { return nil }
        return rawEncodedElements
    }

    private static func decryptToObvEncoded(_ encryptedContent: EncryptedData, with messageKey: AuthenticatedEncryptionKey) -> (obvEncoded: ObvEncoded, rawDecryptedContentForMessageKey: Data)? {
        guard let rawEncodedElements = decryptToData(encryptedContent, with: messageKey) else { return nil }
        guard let content = ObvEncoded(withPaddedRawData: rawEncodedElements) else { return nil }
        return (content, rawEncodedElements)
    }
    
    private static func parse(_ content: ObvEncoded) -> (messageType: ObvChannelMessageType, encodedElements: ObvEncoded)? {
        guard let listOfEncoded = [ObvEncoded](content) else { return nil }
        guard listOfEncoded.count == 2 else { return nil }
        guard let messageType = ObvChannelMessageType(listOfEncoded[0]) else { return nil }
        let encodedElements = listOfEncoded[1]
        return (messageType, encodedElements)
    }
    
}

