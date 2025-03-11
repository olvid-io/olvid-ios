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
import os.log
import ObvCrypto
import ObvEncoder
import ObvTypes
import ObvMetaManager




protocol ObvChannelMessageToSendWrapper {
    init?(message: ObvChannelMessageToSend, acceptableChannels: [ObvNetworkChannel], randomizedWith prng: PRNGService, log: OSLog)
    func generateObvNetworkMessagesToSend() throws -> [ObvNetworkMessageToSend]
}




// MARK: - Extending the ObvChannelMessageToSendWrapper to bring functionnalities for both ObvChannelProtocolMessageToSendWrapper and ObvChannelApplicationMessageToSendWrapper

fileprivate extension ObvChannelMessageToSendWrapper {
    
    /// Add a padding to message to obfuscate content length. The final length will be a multiple of 512 bytes.
    static func generatePaddedMessageContent(type: ObvChannelMessageType, encodedElements: ObvEncoded) -> Data {
        let unpaddedContent = [type.obvEncode(), encodedElements].obvEncode().rawData
        let unpaddedLength = unpaddedContent.count
        let paddedLength: Int = unpaddedLength > 0 ? (1 + ((unpaddedLength-1)>>9)) << 9 : 0 // We pad to the smallest multiple of 512 larger than the actual length
        let paddedContent = unpaddedContent + Data(count: paddedLength-unpaddedLength)
        return paddedContent
    }
    
    
    /// The `messageContent` is used to inject a context in the message key. This key will be later used to encrypt this `messageContent`
    static func generateMessageKeyAndHeaders(contentForMessageKey: Data, using acceptableChannels: [ObvNetworkChannel], randomizedWith prng: PRNGService, log: OSLog) -> (AuthenticatedEncryptionKey, [ObvNetworkMessageToSend.Header])? {
        assert((contentForMessageKey.count & 0x1FF) == 0) // We expect the content to be a multiple of 512
        let cryptoSuiteVersion = acceptableChannels.reduce(ObvCryptoSuite.sharedInstance.latestVersion) { min($0, $1.cryptoSuiteVersion) }
        guard let authEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption(forSuiteVersion: cryptoSuiteVersion) else {
            return nil
        }
        let messageKey = authEnc.generateMessageKey(with: prng, message: contentForMessageKey)
        let headers = acceptableChannels.compactMap { $0.wrapMessageKey(messageKey, randomizedWith: prng) }
        if headers.count != acceptableChannels.count {
            assertionFailure()
            os_log("Failed to produce a header for at least one of the acceptable channels", log: log, type: .fault)
        }
        return (messageKey, headers)
    }

    
    static func encryptContent(messageKey: AuthenticatedEncryptionKey, messageContent: Data, extendedMessagePayload: Data?, randomizedWith prng: PRNGService) -> (encryptedMessagePayload: EncryptedData, encryptedExtendedMessagePayload: EncryptedData?) {
        assert((messageContent.count & 0x1FF) == 0) // We expect the message to be padded so that its byte-length is a multiple of 512
        let authEnc = messageKey.algorithmImplementationByteId.algorithmImplementation
        let encryptedMessagePayload = try! authEnc.encrypt(messageContent, with: messageKey, and: prng)
        if let extendedMessagePayload {
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




// MARK: - ObvChannelProtocolMessageToSendWrapper

struct ObvChannelProtocolMessageToSendWrapper: ObvChannelMessageToSendWrapper {
    
    private static func makeError(message: String) -> Error {
        NSError(domain: "ObvChannelProtocolMessageToSendWrapper", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

    private let protocolMessage: ObvChannelProtocolMessageToSend
    private let acceptableChannels: [ObvNetworkChannel]
    private let prng: PRNGService
    private let log: OSLog
    
    // MARK: Computed properties
    
    private var messageType: ObvChannelMessageType { return protocolMessage.messageType }
    private var toIdentity: ObvCryptoIdentity? { return protocolMessage.channelType.toIdentity }
    private var toIdentities: Set<ObvCryptoIdentity>? { return protocolMessage.channelType.toIdentities }
    private var isProtocolMessageWithUserContent: Bool { return protocolMessage.withUserContent }
    private var encodedElements: ObvEncoded { return protocolMessage.encodedElements }
    
    // MARK: Initializer
    
    init?(message: ObvChannelMessageToSend, acceptableChannels: [ObvNetworkChannel], randomizedWith prng: PRNGService, log: OSLog) {
        guard let protocolMessage = message as? ObvChannelProtocolMessageToSend else { return nil }
        self.protocolMessage = protocolMessage
        self.acceptableChannels = acceptableChannels
        self.prng = prng
        self.log = log
    }
    
    
    // MARK: Generating the `ObvNetworkMessageToSend` structure that can be passed to the `ObvNetworkSendManager`
    
    func generateObvNetworkMessagesToSend() throws -> [ObvNetworkMessageToSend] {
        
        let messageContent = Self.generatePaddedMessageContent(type: messageType, encodedElements: encodedElements)
        
        guard let (messageKey, headers) = Self.generateMessageKeyAndHeaders(contentForMessageKey: messageContent, using: acceptableChannels, randomizedWith: prng, log: log) else {
            assertionFailure()
            throw Self.makeError(message: "Could not generate message key and headers")
        }
        
        let encryptedContent = Self.encryptContent(messageKey: messageKey, messageContent: messageContent, extendedMessagePayload: nil, randomizedWith: prng)
        
        // We need to create one ObvNetworkMessageToSend per server on which the ObvChannelProtocolMessageToSendWrapper needs to be sent.
        // To do so, we first group together the headers pertaining to the same serverURL
        
        let headersForServer: [URL: [ObvNetworkMessageToSend.Header]] = Dictionary(grouping: headers, by: { $0.toIdentity.serverURL })
        guard !headersForServer.keys.isEmpty else {
            throw Self.makeError(message: "Cannot generate ObvNetworkMessageToSend because we cannot determine the destination identity/identities")
        }
        
        // Now that we have grouped the "to" identities, we generate one ObvNetworkMessageToSend per group
        
        let messagesToSend: [ObvNetworkMessageToSend] = headersForServer.map { (serverURL, headersForThisServer) in
            let uid = UID.gen(with: prng)
            let ownedCryptoIdentity = self.protocolMessage.channelType.fromOwnedIdentity
            let messageId = ObvMessageIdentifier(ownedCryptoIdentity: ownedCryptoIdentity, uid: uid)
            return ObvNetworkMessageToSend(messageId: messageId,
                                           encryptedContent: encryptedContent.encryptedMessagePayload,
                                           encryptedExtendedMessagePayload: encryptedContent.encryptedExtendedMessagePayload,
                                           isAppMessageWithUserContent: isProtocolMessageWithUserContent,
                                           isVoipMessageForStartingCall: false,
                                           serverURL: serverURL,
                                           headers: headersForThisServer)
        }
        
        return messagesToSend
        
    }
    
}




// MARK: - ObvChannelApplicationMessageToSendWrapper

struct ObvChannelApplicationMessageToSendWrapper: ObvChannelMessageToSendWrapper {
    
    private static func makeError(message: String) -> Error {
        NSError(domain: "ObvChannelApplicationMessageToSendWrapper", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

    private let applicationMessage: ObvChannelApplicationMessageToSend
    private let acceptableChannels: [ObvNetworkChannel]
    private let prng: PRNGService
    private let log: OSLog

    // MARK: Computed properties

    private var messageType: ObvChannelMessageType { return applicationMessage.messageType }
    private var toIdentity: ObvCryptoIdentity? { return applicationMessage.channelType.toIdentity }
    private var toIdentities: Set<ObvCryptoIdentity>? { return applicationMessage.channelType.toIdentities }
    private var isAppMessageWithUserContent: Bool { return applicationMessage.withUserContent }
    private var isVoipMessageForStartingCall: Bool { return applicationMessage.isVoipMessageForStartingCall }

    // MARK: Initializer
    
    init?(message: ObvChannelMessageToSend, acceptableChannels: [ObvNetworkChannel], randomizedWith prng: PRNGService, log: OSLog) {
        guard let applicationMessage = message as? ObvChannelApplicationMessageToSend else { return nil }
        self.applicationMessage = applicationMessage
        self.acceptableChannels = acceptableChannels
        self.prng = prng
        self.log = log
    }
    
    
    private static func generateEncodedElements(fromMessagePayload payload: Data, and attachmentsAndKeys: [(attachment: ObvChannelApplicationMessageToSend.Attachment, key: AuthenticatedEncryptionKey)]) -> ObvEncoded {
        let listOfEncodedElementsFromAttachments = attachmentsAndKeys.map { $0.attachment.generateEncodedElement(including: $0.key) }
        let encodedMessagePayload = [payload.obvEncode()]
        let encodedElements = (listOfEncodedElementsFromAttachments + encodedMessagePayload).obvEncode()
        return encodedElements
    }
    
    
    private static func generateObvNetworkMessageToSendAttachments(from attachmentsAndKeys: [(attachment: ObvChannelApplicationMessageToSend.Attachment, key: AuthenticatedEncryptionKey)]) -> [ObvNetworkMessageToSend.Attachment] {
        return attachmentsAndKeys.map { $0.attachment.generateObvNetworkMessageToSendAttachment(including: $0.key) }
    }
    
    
    private func computeEncodedElementsAndAttachments() throws -> (encodedElements: ObvEncoded, attachments: [ObvNetworkMessageToSend.Attachment]) {
        let cryptoSuiteVersion = acceptableChannels.reduce(ObvCryptoSuite.sharedInstance.latestVersion) { min($0, $1.cryptoSuiteVersion) }
        guard let authEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption(forSuiteVersion: cryptoSuiteVersion) else {
            assertionFailure()
            throw Self.makeError(message: "Failed to obtain authenticatedEncryption")
        }
        let attachmentsAndKeys = applicationMessage.attachments.map { ($0, authEnc.generateKey(with: prng)) }
        let encodedElements = Self.generateEncodedElements(fromMessagePayload: self.applicationMessage.messagePayload, and: attachmentsAndKeys)
        let attachments = ObvChannelApplicationMessageToSendWrapper.generateObvNetworkMessageToSendAttachments(from: attachmentsAndKeys)
        return (encodedElements, attachments)
    }
    
    
    // MARK: Generating the `MessageToSend` structure that can be passed to the `ObvNetworkSendManager`
    
    func generateObvNetworkMessagesToSend() throws -> [ObvNetworkMessageToSend] {
        
        let (encodedElements, attachments) = try computeEncodedElementsAndAttachments()
        
        let messageContent = Self.generatePaddedMessageContent(type: messageType, encodedElements: encodedElements)

        guard let (messageKey, headers) = Self.generateMessageKeyAndHeaders(contentForMessageKey: messageContent, using: acceptableChannels, randomizedWith: prng, log: log) else {
            assertionFailure()
            throw Self.makeError(message: "Could not generate message key and headers")
        }

        let encryptedContent = Self.encryptContent(messageKey: messageKey, messageContent: messageContent, extendedMessagePayload: self.applicationMessage.extendedMessagePayload, randomizedWith: prng)

        // We need to create one ObvNetworkMessageToSend per server on which the ObvChannelProtocolMessageToSendWrapper needs to be sent.
        // To do so, we first group together the headers pertaining to the same serverURL
        
        let headersForServer: [URL: [ObvNetworkMessageToSend.Header]] = Dictionary(grouping: headers, by: { $0.toIdentity.serverURL })
        guard !headersForServer.keys.isEmpty else {
            throw Self.makeError(message: "Cannot generate ObvNetworkMessageToSend because we cannot determine the destination identity/identities")
        }
        
        // Now that we have grouped the "to" identities, we generate one ObvNetworkMessageToSend per group
        
        let messagesToSend: [ObvNetworkMessageToSend] = headersForServer.map { (serverURL, headersForThisServer) in
            let uid = UID.gen(with: prng)
            let ownedCryptoIdentity = self.applicationMessage.channelType.fromOwnedIdentity
            let messageId = ObvMessageIdentifier(ownedCryptoIdentity: ownedCryptoIdentity, uid: uid)
            return ObvNetworkMessageToSend(messageId: messageId,
                                           encryptedContent: encryptedContent.encryptedMessagePayload,
                                           encryptedExtendedMessagePayload: encryptedContent.encryptedExtendedMessagePayload,
                                           isAppMessageWithUserContent: isAppMessageWithUserContent,
                                           isVoipMessageForStartingCall: isVoipMessageForStartingCall,
                                           serverURL: serverURL,
                                           headers: headersForThisServer,
                                           attachments: attachments)
        }
        
        return messagesToSend
        
    }

}

// MARK: Extensing the standard ObvChannelApplicationMessageToSend's Attachment struct
fileprivate extension ObvChannelApplicationMessageToSend.Attachment {
    func generateEncodedElement(including key: AuthenticatedEncryptionKey) -> ObvEncoded {
        return [key, metadata].obvEncode()
    }
    
    func generateObvNetworkMessageToSendAttachment(including key: AuthenticatedEncryptionKey) -> ObvNetworkMessageToSend.Attachment {
        return ObvNetworkMessageToSend.Attachment(fileURL: fileURL,
                                                  deleteAfterSend: deleteAfterSend,
                                                  byteSize: byteSize,
                                                  key: key)
    }
}
