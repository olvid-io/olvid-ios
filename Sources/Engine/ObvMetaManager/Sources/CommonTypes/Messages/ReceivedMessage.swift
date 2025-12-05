/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OSLog
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
    
    private static let logger = Logger(subsystem: "io.olvid.channel", category: "ReceivedMessage")
    
    public init(with message: ObvNetworkReceivedMessageEncrypted, decryptedWith messageKey: AuthenticatedEncryptionKey, obtainedUsing channelType: ObvProtocolReceptionChannelInfo) throws {
        
        let (encodedContent, rawDecryptedContentForMessageKey) = try ReceivedMessage.decryptToObvEncoded(message.encryptedContent, with: messageKey)
        self.contentForMessageKey = rawDecryptedContentForMessageKey
        let (type, encodedElements) = try ReceivedMessage.parse(encodedContent)
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
            self.extendedMessagePayload = try Self.decryptToData(encryptedExtendedContent, with: extendedMessagePayloadKey)
        } else {
            self.extendedMessagePayload = nil
        }
        
        // Now that both the message key and the message content are available, we ensure GKMv2 support
        try Self.checkGKMV2Support(messageKey: messageKey, messageContent: self.contentForMessageKey)

    }

    private static func decryptToData(_ encryptedContent: EncryptedData, with messageKey: AuthenticatedEncryptionKey) throws -> Data {
        let authEnc = messageKey.algorithmImplementationByteId.algorithmImplementation
        let rawEncodedElements = try authEnc.decrypt(encryptedContent, with: messageKey)
        return rawEncodedElements
    }

    private static func decryptToObvEncoded(_ encryptedContent: EncryptedData, with messageKey: AuthenticatedEncryptionKey) throws -> (obvEncoded: ObvEncoded, rawDecryptedContentForMessageKey: Data) {
        let rawEncodedElements = try decryptToData(encryptedContent, with: messageKey)
        guard let content = ObvEncoded(withPaddedRawData: rawEncodedElements) else { throw ObvError.parsingFailed }
        return (content, rawEncodedElements)
    }
    
    private static func parse(_ content: ObvEncoded) throws -> (messageType: ObvChannelMessageType, encodedElements: ObvEncoded) {
        guard let listOfEncoded = [ObvEncoded](content) else { throw ObvError.parsingFailed }
        guard listOfEncoded.count == 2 else { throw ObvError.parsingFailed }
        guard let messageType = ObvChannelMessageType(listOfEncoded[0]) else { throw ObvError.parsingFailed }
        let encodedElements = listOfEncoded[1]
        return (messageType, encodedElements)
    }
    
    
    /// Each time a message is decrypted, this method is called to evaluate the channel support for GKMV2.
    /// Since 2025-09-09, this support is mandatory, for all channel types (oblivious, pre-key, and asymmetric).
    private static func checkGKMV2Support(messageKey: AuthenticatedEncryptionKey, messageContent: Data) throws {

        let authEnc = messageKey.algorithmImplementationByteId.algorithmImplementation

        assert((messageContent.count & 0x1FF) == 0) // We expect the content to be a multiple of 512
        if !authEnc.verifyMessageKey(messageKey: messageKey, message: messageContent) {
            assertionFailure()
            Self.logger.fault("The message key does not support GKMV2 although it should at this point. Rejecting the message.")
            throw ObvError.messageKeyDoesNotSupportGKMV2AlthoughItShould
        }

    }

    enum ObvError: Error {
        case messageKeyDoesNotSupportGKMV2AlthoughItShould
        case parsingFailed
    }

}

