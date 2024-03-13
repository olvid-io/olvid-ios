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
import CoreData
import OlvidUtils
import ObvTypes
import ObvCrypto
import ObvMetaManager

final class NetworkReceivedMessageDecryptor: NetworkReceivedMessageDecryptorDelegate {
    
    // MARK: Instance variables
    
    weak var delegateManager: ObvChannelDelegateManager?
    private static let logCategory = "NetworkReceivedMessageDecryptor"
 
    private static let errorDomain = "NetworkReceivedMessageDecryptor"
    
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

}


// MARK: Implementing ObvNetworkReceivedMessageDecryptorDelegate

extension NetworkReceivedMessageDecryptor {
    
    // This method only succeeds if the ObvNetworkReceivedMessageEncrypted actually is an Application message. It is typically used when decrypting Application's User Notifications sent through APNS.
    func decrypt(_ receivedMessage: ObvNetworkReceivedMessageEncrypted, within obvContext: ObvContext) throws -> ReceivedApplicationMessage {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvChannelDelegateManager.defaultLogSubsystem, category: NetworkReceivedMessageDecryptor.logCategory)
            os_log("The Channel Delegate Manager is not set", log: log, type: .error)
            throw Self.makeError(message: "The Channel Delegate Manager is not set")
        }
        
        // We try to decrypt the received message with an Oblivious channel. If it does not work, then we are not dealing with an application message so we throw an error.
        guard let (messageKey, channelInfo) = try ObvObliviousChannel.unwrapMessageKey(wrappedKey: receivedMessage.wrappedKey, toOwnedIdentity: receivedMessage.messageId.ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw NetworkReceivedMessageDecryptor.makeError(message: "Could not unwrap the received message wrapped key")
        }
        guard let obvChannelReceivedMessage = ReceivedMessage(with: receivedMessage, decryptedWith: messageKey, obtainedUsing: channelInfo) else {
            throw NetworkReceivedMessageDecryptor.makeError(message: "Could not decrypt the message")
        }
        guard let applicationMessage = ReceivedApplicationMessage(with: obvChannelReceivedMessage) else {
            throw NetworkReceivedMessageDecryptor.makeError(message: "Could not turn received message into a ReceivedApplicationMessage")
        }
        
        return applicationMessage
        
    }
    
    
    /// This method is called on each new received message.
    func decryptAndProcessNetworkReceivedMessageEncrypted(_ receivedMessage: ObvNetworkReceivedMessageEncrypted, within obvContext: ObvContext) throws -> ReceivedEncryptedMessageProcessingResult {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvChannelDelegateManager.defaultLogSubsystem, category: NetworkReceivedMessageDecryptor.logCategory)
            os_log("The Channel Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            throw ReceivedEncryptedMessageProcessingError.delegateManagerIsNil
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: NetworkReceivedMessageDecryptor.logCategory)
        
        // We try to decrypt the received message with an Oblivious channel. If it does not work, we try again with an asymmetric channel.
        
        if let (messageKey, channelInfo) = try ObvObliviousChannel.unwrapMessageKey(wrappedKey: receivedMessage.wrappedKey,
                                                                                    toOwnedIdentity: receivedMessage.messageId.ownedCryptoIdentity,
                                                                                    delegateManager: delegateManager,
                                                                                    within: obvContext) {
            os_log("🔑 A received wrapped key was decrypted using an Oblivious channel", log: log, type: .debug)
            return try decryptAndProcess(receivedMessage, with: messageKey, channelType: channelInfo, within: obvContext)
        } else if let (messageKey, channelInfo) = ObvAsymmetricChannel.unwrapMessageKey(wrappedKey: receivedMessage.wrappedKey,
                                                                                        toOwnedIdentity: receivedMessage.messageId.ownedCryptoIdentity,
                                                                                        delegateManager: delegateManager,
                                                                                        within: obvContext) {
            os_log("🔑 A received wrapped key was decrypted using an Asymmetric Channel", log: log, type: .debug)
            return try decryptAndProcess(receivedMessage, with: messageKey, channelType: channelInfo, within: obvContext)
        } else {
            os_log("🔑 The received message %@ could not be decrypted", log: log, type: .fault, receivedMessage.messageId.debugDescription)
            return .noKeyAllowedToDecrypt(messageId: receivedMessage.messageId)
        }
        
    }
    
    
    private func decryptAndProcess(_ receivedMessage: ObvNetworkReceivedMessageEncrypted, with messageKey: AuthenticatedEncryptionKey, channelType: ObvProtocolReceptionChannelInfo, within obvContext: ObvContext) throws -> ReceivedEncryptedMessageProcessingResult {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvChannelDelegateManager.defaultLogSubsystem, category: NetworkReceivedMessageDecryptor.logCategory)
            os_log("The Channel Delegate Manager is not set", log: log, type: .error)
            assertionFailure()
            throw ReceivedEncryptedMessageProcessingError.delegateManagerIsNil
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: NetworkReceivedMessageDecryptor.logCategory)
        
        guard let protocolDelegate = delegateManager.protocolDelegate else {
            assertionFailure()
            os_log("The protocol delegate is not set", log: log, type: .fault)
            assertionFailure()
            throw ReceivedEncryptedMessageProcessingError.protocolDelegateIsNil
        }

        guard let obvChannelReceivedMessage = ReceivedMessage(with: receivedMessage, decryptedWith: messageKey, obtainedUsing: channelType) else {
            os_log("A received message could not be decrypted or parsed", log: log, type: .error)
            assertionFailure()
            return .couldNotDecryptOrParse(messageId: receivedMessage.messageId)
        }
        
        switch obvChannelReceivedMessage.type {
            
        case .ProtocolMessage:
            os_log("🔑 New protocol message with id %{public}@", log: log, type: .info, receivedMessage.messageId.debugDescription)
            if let receivedProtocolMessage = ReceivedProtocolMessage(with: obvChannelReceivedMessage) {
                let protocolReceivedMessage = receivedProtocolMessage.protocolReceivedMessage
                do {
                    os_log("Processing a decrypted received protocol message with messageId %{public}@", log: log, type: .info, protocolReceivedMessage.messageId.debugDescription)
                    try protocolDelegate.processProtocolReceivedMessage(protocolReceivedMessage, within: obvContext)
                    return .protocolMessageWasProcessed(messageId: receivedMessage.messageId)
                } catch {
                    os_log("A received protocol message could not be processed", log: log, type: .error)
                    assertionFailure()
                    return .protocolManagerFailedToProcessMessage(messageId: receivedMessage.messageId)
                }
            } else {
                os_log("A received protocol message could not be parsed", log: log, type: .error)
                return .protocolMessageCouldNotBeParsed(messageId: receivedMessage.messageId)
            }
            
        case .ApplicationMessage:
            os_log("🔑🌊 New application message within flow %{public}@ with id %{public}@", log: log, type: .info, obvContext.flowId.debugDescription, receivedMessage.messageId.debugDescription)
            // We do not post an applicationMessageDecrypted notification, this is done by the Network Fetch Manager.
            if let receivedApplicationMessage = ReceivedApplicationMessage(with: obvChannelReceivedMessage) {
                //do {
                    // At this point, we expect the `knownAttachmentCount` of the `obvChannelReceivedMessage` to be set and equal to `receivedApplicationMessage.attachmentsInfos`
                    guard receivedApplicationMessage.attachmentsInfos.count == obvChannelReceivedMessage.knownAttachmentCount else {
                        os_log("Invalid count of attachment infos", log: log, type: .fault)
                        assertionFailure()
                        return .invalidAttachmentCountOfApplicationMessage(messageId: receivedMessage.messageId)
                    }
                    os_log("New application message", log: log, type: .debug)
                    return .remoteIdentityToSetOnReceivedMessage(
                        messageId: receivedApplicationMessage.messageId,
                        remoteCryptoIdentity: receivedApplicationMessage.remoteCryptoIdentity,
                        messagePayload: receivedApplicationMessage.messagePayload,
                        extendedMessagePayloadKey: receivedApplicationMessage.extendedMessagePayloadKey,
                        attachmentsInfos: receivedApplicationMessage.attachmentsInfos)
            } else {
                os_log("A received application message could not be parsed", log: log, type: .error)
                return .applicationMessageCouldNotBeParsed(messageId: receivedMessage.messageId)
            }
            
        case .DialogMessage,
             .DialogResponseMessage,
             .ServerQuery,
             .ServerResponse:
            os_log("Dialog/Response/ServerQuery messages are not intended to be decrypted", log: log, type: .fault)
            assertionFailure()
            return .unexpectedMessageType(messageId: receivedMessage.messageId)
        }

    }
}
