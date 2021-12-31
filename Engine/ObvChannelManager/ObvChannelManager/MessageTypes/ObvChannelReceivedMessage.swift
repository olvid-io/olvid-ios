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
import ObvEncoder
import ObvMetaManager

struct ReceivedMessage {
    
    let type: ObvChannelMessageType
    let encodedElements: ObvEncoded
    let extendedMessagePayloadKey: AuthenticatedEncryptionKey?
    let channelType: ObvProtocolReceptionChannelInfo
    private let message: ObvNetworkReceivedMessageEncrypted

    var messageId: MessageIdentifier { return message.messageId }
    var attachmentCount: Int { return message.attachmentCount }
    var messageUploadTimestampFromServer: Date { return message.messageUploadTimestampFromServer }
    
    init?(with message: ObvNetworkReceivedMessageEncrypted, decryptedWith messageKey: AuthenticatedEncryptionKey, obtainedUsing channelType: ObvProtocolReceptionChannelInfo) {
        
        guard let content = ReceivedMessage.decrypt(message.encryptedContent, with: messageKey) else { return nil }
        guard let (type, encodedElements) = ReceivedMessage.parse(content) else { return nil }
        self.type = type
        self.encodedElements = encodedElements
        self.message = message
        self.channelType = channelType
        if message.hasEncryptedExtendedMessagePayload {
            if let seed = Seed(withKeys: [messageKey]) {
                let prng = ObvCryptoSuite.sharedInstance.concretePRNG().init(with: seed)
                let authEnc = messageKey.algorithmImplementationByteId.algorithmImplementation
                self.extendedMessagePayloadKey = authEnc.generateKey(with: prng)
            } else {
                assertionFailure()
                self.extendedMessagePayloadKey = nil
            }
        } else {
            self.extendedMessagePayloadKey = nil
        }
    }
    
    private static func decrypt(_ encryptedContent: EncryptedData, with messageKey: AuthenticatedEncryptionKey) -> ObvEncoded? {
        let authEnc = messageKey.algorithmImplementationByteId.algorithmImplementation
        guard let rawEncodedElements = try? authEnc.decrypt(encryptedContent, with: messageKey) else { return nil }
        let content = ObvEncoded(withRawData: rawEncodedElements)
        return content
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

    var messageId: MessageIdentifier { return message.messageId }
    var extendedMessagePayloadKey: AuthenticatedEncryptionKey? { message.extendedMessagePayloadKey }

    init?(with message: ReceivedMessage) {
        guard message.type == .ApplicationMessage else { return nil }
        switch message.channelType {
        case .AsymmetricChannel,
             .Local,
             .AnyObliviousChannelWithOwnedDevice,
             .AnyObliviousChannel:
            return nil
        case .ObliviousChannel(remoteCryptoIdentity: let remoteCryptoIdentity, remoteDeviceUid: let remoteDeviceUid):
            // We do not check whether the channel is confirmed or not. This does not matter when receiving a message.
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
