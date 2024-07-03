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
import ObvCrypto
import ObvTypes
import ObvEncoder
import ObvMetaManager

struct ReceivedMessage {
    
    let type: ObvChannelMessageType
    let encodedElements: ObvEncoded
    let extendedMessagePayloadKey: AuthenticatedEncryptionKey?
    let channelType: ObvProtocolReceptionChannelInfo
    let extendedMessagePayload: Data? // Available only when the message was received in a notification. Not available during a "normal" reception as the extended payload is downloaded asynchronously
    private let message: ObvNetworkReceivedMessageEncrypted
    let contentForMessageKey: Data

    var messageId: ObvMessageIdentifier { return message.messageId }
    var knownAttachmentCount: Int? { return message.knownAttachmentCount }
    var messageUploadTimestampFromServer: Date { return message.messageUploadTimestampFromServer }
    
    init?(with message: ObvNetworkReceivedMessageEncrypted, decryptedWith messageKey: AuthenticatedEncryptionKey, obtainedUsing channelType: ObvProtocolReceptionChannelInfo) {
        
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

struct ReceivedApplicationMessage {
    
    let message: ReceivedMessage
    let remoteCryptoIdentity: ObvCryptoIdentity
    let remoteDeviceUid: UID
    let messagePayload: Data
    let attachmentsInfos: [ObvNetworkFetchAttachmentInfos]

    var messageId: ObvMessageIdentifier { return message.messageId }
    var extendedMessagePayloadKey: AuthenticatedEncryptionKey? { message.extendedMessagePayloadKey }
    var extendedMessagePayload: Data? { message.extendedMessagePayload }

    init?(with message: ReceivedMessage) {
        guard message.type == .ApplicationMessage else { return nil }
        switch message.channelType {
        case .asymmetricChannel,
             .local,
             .anyObliviousChannelOrPreKeyWithOwnedDevice,
             .anyObliviousChannelOrPreKeyChannel,
             .anyObliviousChannel:
            return nil
        case .obliviousChannel(remoteCryptoIdentity: let remoteCryptoIdentity, remoteDeviceUid: let remoteDeviceUid):
            // We do not check whether the channel is confirmed or not. This does not matter when receiving a message.
            self.remoteCryptoIdentity = remoteCryptoIdentity
            self.remoteDeviceUid = remoteDeviceUid
        case .preKeyChannel(remoteCryptoIdentity: let remoteCryptoIdentity, remoteDeviceUid: let remoteDeviceUid):
            self.remoteCryptoIdentity = remoteCryptoIdentity
            self.remoteDeviceUid = remoteDeviceUid
        }
        
        guard let (messagePayload, attachmentsInfos) = ReceivedApplicationMessage.generateMessagePayloadAndAttachmentsInfos(from: message.encodedElements) else { return nil }
        self.attachmentsInfos = attachmentsInfos
        self.messagePayload = messagePayload
        self.message = message
    }
    
    private static func generateMessagePayloadAndAttachmentsInfos(from encodedElements: ObvEncoded) -> (messagePayload: Data, attachmentsInfos: [ObvNetworkFetchAttachmentInfos])? {
        guard var encodedElements = [ObvEncoded](encodedElements) else { return nil }
        guard let encodedMessagePayload = encodedElements.popLast() else { return nil }
        guard let messagePayload = Data(encodedMessagePayload) else { return nil }
        var attachmentsInfos = [ObvNetworkFetchAttachmentInfos]()
        for encodedElement in encodedElements {
            guard let attachmentInfos = generateAttachmentInfos(from: encodedElement) else { return nil }
            attachmentsInfos.append(attachmentInfos)
        }
        return (messagePayload, attachmentsInfos)
    }
    
    private static func generateAttachmentInfos(from encodedElement: ObvEncoded) -> ObvNetworkFetchAttachmentInfos? {
        guard let listOfEncodedInfos = [ObvEncoded](encodedElement) else { return nil }
        guard listOfEncodedInfos.count == 2 else { return nil }
        guard let key = try? AuthenticatedEncryptionKeyDecoder.decode(listOfEncodedInfos[0]) else { return nil }
        guard let metadata = Data(listOfEncodedInfos[1]) else { return nil }
        return ObvNetworkFetchAttachmentInfos(metadata: metadata, key: key)
    }
}

struct ReceivedProtocolMessage {
    
    let protocolReceivedMessage: ObvProtocolReceivedMessage

    init?(with message: ReceivedMessage) {
        guard message.type == .ProtocolMessage else { return nil }
        self.protocolReceivedMessage = ObvProtocolReceivedMessage(messageId: message.messageId,
                                                                  timestamp: message.messageUploadTimestampFromServer,
                                                                  receptionChannelInfo: message.channelType,
                                                                  encodedElements: message.encodedElements)
    }
    
}
