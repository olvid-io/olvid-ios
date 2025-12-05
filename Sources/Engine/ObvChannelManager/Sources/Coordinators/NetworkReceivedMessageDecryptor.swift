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
import CoreData
import OlvidUtils
import ObvTypes
import ObvCrypto
import ObvMetaManager

final class NetworkReceivedMessageDecryptor: NetworkReceivedMessageDecryptorDelegate {
    
    weak var delegateManager: ObvChannelDelegateManager?
 
    static let logger = Logger(subsystem: ObvChannelDelegateManager.defaultLogSubsystem, category: "NetworkReceivedMessageDecryptor")

}


// MARK: Implementing ObvNetworkReceivedMessageDecryptorDelegate

extension NetworkReceivedMessageDecryptor {
    
    // This method only succeeds if the ObvNetworkReceivedMessageEncrypted actually is an Application message. It is typically used when decrypting Application's User Notifications sent through APNS.
    func decryptUserNotification(_ receivedMessage: ObvNetworkReceivedMessageEncrypted, within obvContext: ObvContext) throws -> ReceivedApplicationOrProtocolMessage {
        
        guard let delegateManager = delegateManager else {
            Self.logger.error("The Channel Delegate Manager is not set")
            throw ObvError.obvChannelDelegateManagerIsNil
        }
        
        // We try to decrypt the received message with an Oblivious channel, then with a PreKey. If it does not work, then we are not dealing with an application message so we throw an error.
        
        // Try #1: Unwrap with an Oblivious channel
        
        var unwrappedValues: (messageKey: AuthenticatedEncryptionKey, receptionChannelInfo: ObvProtocolReceptionChannelInfo)?
        
        do {
            let unwrapResult = try ObvObliviousChannel.unwrapMessageKey(wrappedKey: receivedMessage.wrappedKey,
                                                                        toOwnedIdentity: receivedMessage.messageId.ownedCryptoIdentity,
                                                                        delegateManager: delegateManager,
                                                                        within: obvContext)
            switch unwrapResult {
            case .unwrapSucceeded(messageKey: let messageKey, receptionChannelInfo: let receptionChannelInfo):
                unwrappedValues = (messageKey, receptionChannelInfo)
            case .unwrapSucceededButRemoteCryptoIdIsUnknown,
                    .couldNotUnwrap,
                    .contactIsRevokedAsCompromised:
                unwrappedValues = nil
            }
        }
        
        // Try #2: Unwrap with a PreKey channel (if Try #1 failed)

        if unwrappedValues == nil {
            let unwrapResult = try PreKeyChannel.unwrapMessageKey(wrappedKey: receivedMessage.wrappedKey,
                                                                  toOwnedIdentity: receivedMessage.messageId.ownedCryptoIdentity,
                                                                  delegateManager: delegateManager,
                                                                  within: obvContext)
            switch unwrapResult {
            case .unwrapSucceeded(messageKey: let messageKey, receptionChannelInfo: let receptionChannelInfo):
                unwrappedValues = (messageKey, receptionChannelInfo)
            case .unwrapSucceededButRemoteCryptoIdIsUnknown,
                    .couldNotUnwrap,
                    .contactIsRevokedAsCompromised:
                unwrappedValues = nil
            }
        }
        
        // Try to return a ReceivedApplicationMessage
        
        guard let (messageKey, channelInfo) = unwrappedValues else {
            throw ObvError.couldNotUnwrapTheReceivedMessageWrappedKey
        }

        let obvChannelReceivedMessage: ReceivedMessage
        do {
            obvChannelReceivedMessage = try ReceivedMessage(with: receivedMessage, decryptedWith: messageKey, obtainedUsing: channelInfo)
        } catch {
            throw ObvError.couldNotDecryptTheMessage
        }
        
        // If we reach this point, the decryption was successful
        
        if let applicationMessage = ReceivedApplicationMessage(with: obvChannelReceivedMessage) {
            return .applicationMessage(applicationMessage)
        } else if let protocolMessage = ReceivedProtocolMessage(with: obvChannelReceivedMessage) {
            return .protocolMessage(protocolMessage)
        } else {
            throw ObvError.couldNotTurnReceivedMessageIntoAReceivedApplicationMessage
        }
        
    }
    
    
    /// This method is called on each new received message.
    func decryptAndProcessNetworkReceivedMessageEncrypted(_ receivedMessage: ObvNetworkReceivedMessageEncrypted, within obvContext: ObvContext) throws -> ReceivedEncryptedMessageProcessingResult {
        
        guard let delegateManager = delegateManager else {
            Self.logger.fault("The Channel Delegate Manager is not set")
            assertionFailure()
            throw ReceivedEncryptedMessageProcessingError.delegateManagerIsNil
        }
        
        // Try #1: Unwrap with an Oblivious channel
        
        do {
            let unwrapResult = try ObvObliviousChannel.unwrapMessageKey(wrappedKey: receivedMessage.wrappedKey,
                                                                        toOwnedIdentity: receivedMessage.messageId.ownedCryptoIdentity,
                                                                        delegateManager: delegateManager,
                                                                        within: obvContext)
            
            switch unwrapResult {
                
            case .unwrapSucceeded(messageKey: let messageKey, receptionChannelInfo: let receptionChannelInfo):
                Self.logger.debug("🔑 A received wrapped key was decrypted using an Oblivious channel")
                return try decryptAndProcess(receivedMessage, with: messageKey, channelType: receptionChannelInfo, within: obvContext)
                
            case .unwrapSucceededButRemoteCryptoIdIsUnknown(remoteCryptoIdentity: let remoteCryptoIdentity):
                assertionFailure("This is not expected for an Oblivious channel")
                return .unwrapSucceededButRemoteCryptoIdIsUnknown(messageId: receivedMessage.messageId, remoteCryptoIdentity: remoteCryptoIdentity)
                
            case .couldNotUnwrap:
                // We will try with a PreKey channel instead
                break
                
            case .contactIsRevokedAsCompromised:
                return .messageReceivedFromContactThatIsRevokedAsCompromised(messageId: receivedMessage.messageId)
                
            }
        }
        
        // Try #2: Unwrap with a PreKey channel
        
        do {
            let unwrapResult = try PreKeyChannel.unwrapMessageKey(wrappedKey: receivedMessage.wrappedKey,
                                                                  toOwnedIdentity: receivedMessage.messageId.ownedCryptoIdentity,
                                                                  delegateManager: delegateManager,
                                                                  within: obvContext)
            
            switch unwrapResult {
                
            case .unwrapSucceeded(messageKey: let messageKey, receptionChannelInfo: let receptionChannelInfo):
                Self.logger.debug("🔑 A received wrapped key was decrypted using a PreKey channel")
                return try decryptAndProcess(receivedMessage, with: messageKey, channelType: receptionChannelInfo, within: obvContext)
                
            case .unwrapSucceededButRemoteCryptoIdIsUnknown(remoteCryptoIdentity: let remoteCryptoIdentity):
                Self.logger.debug("🔑 A received wrapped key was decrypted using a PreKey channel but the remote crypto id is not known yet")
                return .unwrapSucceededButRemoteCryptoIdIsUnknown(messageId: receivedMessage.messageId, remoteCryptoIdentity: remoteCryptoIdentity)
                
            case .couldNotUnwrap:
                // We will try with an asymmetric channel instead
                break
                
            case .contactIsRevokedAsCompromised:
                return .messageReceivedFromContactThatIsRevokedAsCompromised(messageId: receivedMessage.messageId)

            }
        }
        
        // Try #3: Unwrap with an asymmetric channel

        
        do {
            let unwrapResult = try ObvAsymmetricChannel.unwrapMessageKey(wrappedKey: receivedMessage.wrappedKey,
                                                                         toOwnedIdentity: receivedMessage.messageId.ownedCryptoIdentity,
                                                                         delegateManager: delegateManager,
                                                                         within: obvContext)

            switch unwrapResult {
                
            case .unwrapSucceeded(messageKey: let messageKey, receptionChannelInfo: let receptionChannelInfo):
                Self.logger.debug("🔑 A received wrapped key was decrypted using a symmetric channel")
                return try decryptAndProcess(receivedMessage, with: messageKey, channelType: receptionChannelInfo, within: obvContext)
                
            case .unwrapSucceededButRemoteCryptoIdIsUnknown(remoteCryptoIdentity: let remoteCryptoIdentity):
                assertionFailure("This is not expected for an asymmetric channel")
                return .unwrapSucceededButRemoteCryptoIdIsUnknown(messageId: receivedMessage.messageId, remoteCryptoIdentity: remoteCryptoIdentity)

            case .couldNotUnwrap:
                break
                
            case .contactIsRevokedAsCompromised:
                return .messageReceivedFromContactThatIsRevokedAsCompromised(messageId: receivedMessage.messageId)

            }
        }
        
        // If we reach this point, we could not decrypt
        
        Self.logger.fault("🔑 The received message %@ could not be decrypted")
        return .noKeyAllowedToDecrypt(messageId: receivedMessage.messageId)
        
    }
    
    
    private func decryptAndProcess(_ receivedMessage: ObvNetworkReceivedMessageEncrypted, with messageKey: AuthenticatedEncryptionKey, channelType: ObvProtocolReceptionChannelInfo, within obvContext: ObvContext) throws -> ReceivedEncryptedMessageProcessingResult {
        
        guard let delegateManager = delegateManager else {
            Self.logger.error("The Channel Delegate Manager is not set")
            assertionFailure()
            throw ReceivedEncryptedMessageProcessingError.delegateManagerIsNil
        }
        
        guard let protocolDelegate = delegateManager.protocolDelegate else {
            assertionFailure()
            Self.logger.fault("The protocol delegate is not set")
            assertionFailure()
            throw ReceivedEncryptedMessageProcessingError.protocolDelegateIsNil
        }

        let obvChannelReceivedMessage: ReceivedMessage
        do {
            obvChannelReceivedMessage = try ReceivedMessage(with: receivedMessage, decryptedWith: messageKey, obtainedUsing: channelType)
        } catch {
            Self.logger.error("A received message could not be decrypted or parsed: \(error)")
            assertionFailure()
            return .couldNotDecryptOrParse(messageId: receivedMessage.messageId)
        }
        
        switch obvChannelReceivedMessage.type {
            
        case .ProtocolMessage:
            Self.logger.info("🔑 New protocol message with id \(receivedMessage.messageId.debugDescription, privacy: .public)")
            if let receivedProtocolMessage = ReceivedProtocolMessage(with: obvChannelReceivedMessage) {
                let protocolReceivedMessage = receivedProtocolMessage.protocolReceivedMessage
                do {
                    Self.logger.info("Processing a decrypted received protocol message with messageId \(protocolReceivedMessage.messageId.debugDescription, privacy: .public)")
                    try protocolDelegate.processProtocolReceivedMessage(protocolReceivedMessage, within: obvContext)
                    return .protocolMessageWasProcessed(messageId: receivedMessage.messageId)
                } catch {
                    Self.logger.error("A received protocol message could not be processed")
                    assertionFailure()
                    return .protocolManagerFailedToProcessMessage(messageId: receivedMessage.messageId)
                }
            } else {
                Self.logger.error("A received protocol message could not be parsed")
                return .protocolMessageCouldNotBeParsed(messageId: receivedMessage.messageId)
            }
            
        case .ApplicationMessage:
            Self.logger.info("🔑🌊 New application message within flow \(obvContext.flowId.debugDescription, privacy: .public) with id \(receivedMessage.messageId.debugDescription, privacy: .public)")
            // We do not post an applicationMessageDecrypted notification, this is done by the Network Fetch Manager.
            if let receivedApplicationMessage = ReceivedApplicationMessage(with: obvChannelReceivedMessage) {
                // At this point, we expect the `knownAttachmentCount` of the `obvChannelReceivedMessage` to be set and equal to `receivedApplicationMessage.attachmentsInfos`
                guard receivedApplicationMessage.attachmentsInfos.count == obvChannelReceivedMessage.knownAttachmentCount else {
                    Self.logger.fault("Invalid count of attachment infos")
                    assertionFailure()
                    return .invalidAttachmentCountOfApplicationMessage(messageId: receivedMessage.messageId)
                }
                Self.logger.debug("New application message")
                return .remoteIdentityToSetOnReceivedMessage(
                    messageId: receivedApplicationMessage.messageId,
                    remoteCryptoIdentity: receivedApplicationMessage.remoteCryptoIdentity,
                    remoteDeviceUID: receivedApplicationMessage.remoteDeviceUid,
                    messagePayload: receivedApplicationMessage.messagePayload,
                    extendedMessagePayloadKey: receivedApplicationMessage.extendedMessagePayloadKey,
                    attachmentsInfos: receivedApplicationMessage.attachmentsInfos)
            } else {
                Self.logger.error("A received application message could not be parsed")
                return .applicationMessageCouldNotBeParsed(messageId: receivedMessage.messageId)
            }
            
        case .DialogMessage,
             .DialogResponseMessage,
             .ServerQuery,
             .ServerResponse:
            Self.logger.fault("Dialog/Response/ServerQuery messages are not intended to be decrypted")
            assertionFailure()
            return .unexpectedMessageType(messageId: receivedMessage.messageId)
        }

    }
}


extension NetworkReceivedMessageDecryptor {
    
    enum ObvError: Error {
        case obvChannelDelegateManagerIsNil
        case couldNotUnwrapTheReceivedMessageWrappedKey
        case couldNotDecryptTheMessage
        case couldNotTurnReceivedMessageIntoAReceivedApplicationMessage
    }
    
}
