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
import ObvEncoder
import ObvTypes
import ObvMetaManager


protocol ObvChannelMessageToSendWrapper {
    init?(message: ObvChannelMessageToSend, messageKey: AuthenticatedEncryptionKey, headers: [ObvNetworkMessageToSend.Header], randomizedWith prng: PRNGService)
    func generateObvNetworkMessageToSend() throws -> ObvNetworkMessageToSend
}


fileprivate extension ObvChannelMessageToSendWrapper {
    
    static func generateContent(type: ObvChannelMessageType, encodedElements: ObvEncoded) -> ObvEncoded {
        return [type.encode(), encodedElements].encode()
    }
    
    static func encryptContent(messageKey: AuthenticatedEncryptionKey, type: ObvChannelMessageType, encodedElements: ObvEncoded, extendedMessagePayload: Data?, randomizedWith prng: PRNGService) -> (encryptedMessagePayload: EncryptedData, encryptedExtendedMessagePayload: EncryptedData?) {
        let authEnc = messageKey.algorithmImplementationByteId.algorithmImplementation
        let content = generateContent(type: type, encodedElements: encodedElements)
        let encryptedMessagePayload = try! authEnc.encrypt(content.rawData, with: messageKey, and: prng)
        if let extendedMessagePayload = extendedMessagePayload {
            guard let seed = Seed(withKeys: [messageKey]) else { assertionFailure(); return (encryptedMessagePayload, nil)}
            let prng = ObvCryptoSuite.sharedInstance.concretePRNG().init(with: seed)
            let authEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption()
            let encryptionKey = authEnc.generateKey(with: prng)
            guard let encryptedExtendedMessagePayload = try?authEnc.encrypt(extendedMessagePayload, with: encryptionKey, and: prng) else { assertionFailure(); return (encryptedMessagePayload, nil)}
            return (encryptedMessagePayload, encryptedExtendedMessagePayload)
        } else {
            return (encryptedMessagePayload, nil)
        }
    }
}


struct ObvChannelProtocolMessageToSendWrapper: ObvChannelMessageToSendWrapper {
    
    private let protocolMessage: ObvChannelProtocolMessageToSend
    private let messageKey: AuthenticatedEncryptionKey
    private let headers: [ObvNetworkMessageToSend.Header]
    private let prng: PRNGService
    
    // MARK: Computed properties
    
    private var messageType: ObvChannelMessageType { return protocolMessage.messageType }
    private var toIdentity: ObvCryptoIdentity? { return protocolMessage.channelType.toIdentity }
    private var toIdentities: Set<ObvCryptoIdentity>? { return protocolMessage.channelType.toIdentities }
    private var encodedElements: ObvEncoded { return protocolMessage.encodedElements }
    private var messageId: MessageIdentifier { return protocolMessage.messageId }
    
    // MARK: Initializer
    
    init?(message: ObvChannelMessageToSend, messageKey: AuthenticatedEncryptionKey, headers: [ObvNetworkMessageToSend.Header], randomizedWith prng: PRNGService) {
        guard let protocolMessage = message as? ObvChannelProtocolMessageToSend else { return nil }
        self.protocolMessage = protocolMessage
        self.messageKey = messageKey
        self.headers = headers
        self.prng = prng
    }
    
    // MARK: Generating the `ObvNetworkMessageToSend` structure that can be passed to the `ObvNetworkSendManager`
    
    func generateObvNetworkMessageToSend() throws -> ObvNetworkMessageToSend {
        let encryptedContent = ObvChannelProtocolMessageToSendWrapper.encryptContent(messageKey: messageKey,
                                                                                     type: messageType,
                                                                                     encodedElements: encodedElements,
                                                                                     extendedMessagePayload: nil,
                                                                                     randomizedWith: prng)
        let serverURL: URL
        if let toIdentity = self.toIdentity {
            serverURL = toIdentity.serverURL
        } else if let toIdentities = self.toIdentities {
            let serverURLs = Set(toIdentities.map { $0.serverURL })
            guard serverURLs.count == 1 else { throw NSError() } // All identities mut belong to the same server
            serverURL = serverURLs.first!
        } else {
            throw NSError()
        }
        
        let messageToSend = ObvNetworkMessageToSend(messageId: messageId,
                                                    encryptedContent: encryptedContent.encryptedMessagePayload,
                                                    encryptedExtendedMessagePayload: encryptedContent.encryptedExtendedMessagePayload,
                                                    isAppMessageWithUserContent: false,
                                                    isVoipMessageForStartingCall: false,
                                                    serverURL: serverURL,
                                                    headers: headers)
        return messageToSend
    }
}


struct ObvChannelApplicationMessageToSendWrapper: ObvChannelMessageToSendWrapper {
    
    private let applicationMessage: ObvChannelApplicationMessageToSend
    private let messageKey: AuthenticatedEncryptionKey
    private let headers: [ObvNetworkMessageToSend.Header]
    private let prng: PRNGService
    private let encodedElements: ObvEncoded
    private let attachments: [ObvNetworkMessageToSend.Attachment]
    
    // MARK: Computed properties

    private var messageType: ObvChannelMessageType { return applicationMessage.messageType }
    private var toIdentity: ObvCryptoIdentity? { return applicationMessage.channelType.toIdentity }
    private var toIdentities: Set<ObvCryptoIdentity>? { return applicationMessage.channelType.toIdentities }
    private var messageId: MessageIdentifier { return applicationMessage.messageId }
    private var isAppMessageWithUserContent: Bool { return applicationMessage.withUserContent }
    private var isVoipMessageForStartingCall: Bool { return applicationMessage.isVoipMessageForStartingCall }

    // MARK: Initializer
    
    init?(message: ObvChannelMessageToSend, messageKey: AuthenticatedEncryptionKey, headers: [ObvNetworkMessageToSend.Header], randomizedWith prng: PRNGService) {
        guard let applicationMessage = message as? ObvChannelApplicationMessageToSend else { return nil }
        self.applicationMessage = applicationMessage
        self.messageKey = messageKey
        self.headers = headers
        self.prng = prng
        let authEnc = messageKey.algorithmImplementationByteId.algorithmImplementation
        let attachmentsAndKeys = applicationMessage.attachments.map { ($0, authEnc.generateKey(with: prng)) }
        self.encodedElements = ObvChannelApplicationMessageToSendWrapper.generateEncodedElements(fromMessagePayload: self.applicationMessage.messagePayload, and: attachmentsAndKeys)
        self.attachments = ObvChannelApplicationMessageToSendWrapper.generateObvNetworkMessageToSendAttachments(from: attachmentsAndKeys)
    }
    
    private static func generateEncodedElements(fromMessagePayload payload: Data, and attachmentsAndKeys: [(attachment: ObvChannelApplicationMessageToSend.Attachment, key: AuthenticatedEncryptionKey)]) -> ObvEncoded {
        let listOfEncodedElementsFromAttachments = attachmentsAndKeys.map { $0.attachment.generateEncodedElement(including: $0.key) }
        let encodedMessagePayload = [payload.encode()]
        let encodedElements = (listOfEncodedElementsFromAttachments + encodedMessagePayload).encode()
        return encodedElements
    }
    
    private static func generateObvNetworkMessageToSendAttachments(from attachmentsAndKeys: [(attachment: ObvChannelApplicationMessageToSend.Attachment, key: AuthenticatedEncryptionKey)]) -> [ObvNetworkMessageToSend.Attachment] {
        return attachmentsAndKeys.map { $0.attachment.generateObvNetworkMessageToSendAttachment(including: $0.key) }
    }
    
    // MARK: Generating the `MessageToSend` structure that can be passed to the `ObvNetworkSendManager`
    
    func generateObvNetworkMessageToSend() throws -> ObvNetworkMessageToSend {
        let encryptedContent = ObvChannelProtocolMessageToSendWrapper.encryptContent(messageKey: messageKey,
                                                                                     type: messageType,
                                                                                     encodedElements: encodedElements,
                                                                                     extendedMessagePayload: applicationMessage.extendedMessagePayload,
                                                                                     randomizedWith: prng)
        
        let serverURL: URL
        if let toIdentity = self.toIdentity {
            serverURL = toIdentity.serverURL
        } else if let toIdentities = self.toIdentities {
            let serverURLs = Set(toIdentities.map { $0.serverURL })
            guard serverURLs.count == 1 else { throw NSError() } // All identities mut belong to the same server
            serverURL = serverURLs.first!
        } else {
            throw NSError()
        }

        let messageToSend = ObvNetworkMessageToSend(messageId: messageId,
                                                    encryptedContent: encryptedContent.encryptedMessagePayload,
                                                    encryptedExtendedMessagePayload: encryptedContent.encryptedExtendedMessagePayload,
                                                    isAppMessageWithUserContent: isAppMessageWithUserContent,
                                                    isVoipMessageForStartingCall: isVoipMessageForStartingCall,
                                                    serverURL: serverURL,
                                                    headers: headers,
                                                    attachments: attachments)
        return messageToSend
    }
}

// MARK: Extensing the standard ObvChannelApplicationMessageToSend's Attachment struct
fileprivate extension ObvChannelApplicationMessageToSend.Attachment {
    func generateEncodedElement(including key: AuthenticatedEncryptionKey) -> ObvEncoded {
        return [key, metadata].encode()
    }
    
    func generateObvNetworkMessageToSendAttachment(including key: AuthenticatedEncryptionKey) -> ObvNetworkMessageToSend.Attachment {
        return ObvNetworkMessageToSend.Attachment(fileURL: fileURL,
                                                  deleteAfterSend: deleteAfterSend,
                                                  byteSize: byteSize,
                                                  key: key)
    }
}
