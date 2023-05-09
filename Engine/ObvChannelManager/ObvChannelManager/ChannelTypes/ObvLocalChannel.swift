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
import os.log
import CoreData
import ObvCrypto
import ObvMetaManager
import ObvTypes
import OlvidUtils

final class ObvLocalChannel: ObvChannel {
    
    private static let logCategory = "ObvLocalChannel"
    
    private static let errorDomain = "ObvLocalChannel"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    let cryptoSuiteVersion: SuiteVersion = 0
    let ownedIdentity: ObvCryptoIdentity
    
    init(ownedIdentity: ObvCryptoIdentity) {
        self.ownedIdentity = ownedIdentity
    }
    
    private func post(_ message: ObvChannelMessageToSend, randomizedWith prng: PRNGService, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> MessageIdentifier {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObvLocalChannel.logCategory)
        
        guard let protocolDelegate = delegateManager.protocolDelegate else {
            os_log("The protocol delegate is not set", log: log, type: .fault)
            throw Self.makeError(message: "The protocol delegate is not set")
        }

        switch message.messageType {
            
        case .ProtocolMessage:
            os_log("Posting a protocol message on a local channel", log: log, type: .debug)
            
            guard let message = message as? ObvChannelProtocolMessageToSend else {
                os_log("Could not cast to protocol message", log: log, type: .fault)
                throw Self.makeError(message: "Could not cast to protocol message")
            }
                        
            guard let toIdentity = message.channelType.toIdentity else {
                assertionFailure()
                throw ObvLocalChannel.makeError(message: "The channel type has no toIdentity, which is unexpected")
            }
            
            let ownedIdentity = message.channelType.fromOwnedIdentity
            
            guard toIdentity == ownedIdentity else {
                assertionFailure()
                throw ObvLocalChannel.makeError(message: "We expect the toIdentity to identical to the ownedIdentity on a local channel")
            }
            
            let randomUid = UID.gen(with: prng)
            let messageId = MessageIdentifier(ownedCryptoIdentity: ownedIdentity, uid: randomUid) // For a local message, to toIdentity is also the from (owned) identity

            let receivedMessage = ObvProtocolReceivedMessage(messageId: messageId,
                                                             timestamp: message.timestamp,
                                                             receptionChannelInfo: .Local,
                                                             encodedElements: message.encodedElements)
                        
            os_log("Processing a posted protocol message with a (just created) messageId %{public}@", log: log, type: .info, messageId.debugDescription)
            try protocolDelegate.processProtocolReceivedMessage(receivedMessage, within: obvContext)
            
            return messageId
            
        case .ApplicationMessage:
            os_log("Trying to post an application message on a local channel (not implemented)", log: log, type: .fault)
            throw ObvLocalChannel.makeError(message: "Trying to post an application message on a local channel (not implemented)")
            
        case .DialogMessage:
            os_log("Trying to post a dialog message on a local channel (not implemented)", log: log, type: .fault)
            throw ObvLocalChannel.makeError(message: "Trying to post a dialog message on a local channel (not implemented)")

        case .ServerQuery:
            os_log("Trying to post a server query on a local channel (not implemented)", log: log, type: .fault)
            throw ObvLocalChannel.makeError(message: "Trying to post a server query on a local channel (not implemented)")

        case .DialogResponseMessage:
            os_log("Posting a dialog response message on a local channel", log: log, type: .debug)
            
            guard let message = message as? ObvChannelDialogResponseMessageToSend else {
                os_log("Could not cast to dialog response message to send", log: log, type: .fault)
                throw ObvLocalChannel.makeError(message: "Could not cast to dialog response message to send")
            }

            let receivedMessage = ObvProtocolReceivedDialogResponse(toOwnedIdentity: ownedIdentity,
                                                                    timestamp: message.timestamp,
                                                                    receptionChannelInfo: .Local,
                                                                    encodedElements: message.encodedElements,
                                                                    encodedUserDialogResponse: message.encodedUserDialogResponse,
                                                                    dialogUuid: message.uuid)
            
            try protocolDelegate.process(receivedMessage, within: obvContext)

            let randomUid = UID.gen(with: prng)
            let messageId = MessageIdentifier(ownedCryptoIdentity: ownedIdentity, uid: randomUid) // For a local message, to toIdentity is also the from (owned) identity

            return messageId
            
        case .ServerResponse:
            os_log("Posting a server response message on a local channel", log: log, type: .debug)

            guard let message = message as? ObvChannelServerResponseMessageToSend else {
                os_log("Could not cast to server response message to send", log: log, type: .fault)
                throw ObvLocalChannel.makeError(message: "Could not cast to server response message to send")
            }
            
            let receivedMessage = ObvProtocolReceivedServerResponse(toOwnedIdentity: ownedIdentity,
                                                                    serverTimestamp: message.serverTimestamp,
                                                                    receptionChannelInfo: .Local,
                                                                    encodedElements: message.encodedElements,
                                                                    serverResponseType: message.responseType)

            try protocolDelegate.process(receivedMessage, within: obvContext)
            
            let randomUid = UID.gen(with: prng)
            let messageId = MessageIdentifier(ownedCryptoIdentity: ownedIdentity, uid: randomUid) // For a local message, to toIdentity is also the from (owned) identity

            return messageId

        }
    }
    
}

// MARK: Implementing ObvChannel
extension ObvLocalChannel {
    
    static func acceptableChannelsForPosting(_ message: ObvChannelMessageToSend, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> [ObvChannel] {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObvLocalChannel.logCategory)

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw ObvLocalChannel.makeError(message: "The identity delegate is not set")
        }

        let acceptableChannels: [ObvChannel]
        
        switch message.channelType {
        case .Local(ownedIdentity: let ownedIdentity):
            
            guard message.messageType == .ProtocolMessage || message.messageType == .DialogResponseMessage || message.messageType == .ServerResponse else {
                throw ObvLocalChannel.makeError(message: "Wrong message type")
            }

            guard try identityDelegate.isOwned(ownedIdentity, within: obvContext) else {
                os_log("Cannot send local message to an identity that is not owned", log: log, type: .error)
                throw ObvLocalChannel.makeError(message: "Cannot send local message to an identity that is not owned")
            }
            
            acceptableChannels = [ObvLocalChannel(ownedIdentity: ownedIdentity)]
            
        default:
            os_log("Wrong message channel type", log: log, type: .fault)
            throw ObvLocalChannel.makeError(message: "Wrong message channel type")
        }

        return acceptableChannels
    }
    
    static func post(_ message: ObvChannelMessageToSend, randomizedWith prng: PRNGService, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> [MessageIdentifier: Set<ObvCryptoIdentity>] {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObvLocalChannel.logCategory)

        guard let acceptableChannels = try acceptableChannelsForPosting(message, delegateManager: delegateManager, within: obvContext) as? [ObvLocalChannel] else {
            os_log("No acceptable local channel found", log: log, type: .error)
            throw ObvLocalChannel.makeError(message: "No acceptable local channel found")
        }
        
        guard acceptableChannels.count == 1, let acceptableLocalChannel = acceptableChannels.first else {
            os_log("Unexpected number of local channels found. Expecting 1, go %d", log: log, type: .error, acceptableChannels.count)
            throw ObvLocalChannel.makeError(message: "Unexpected number of local channels found")
        }
        
        let messageId = try acceptableLocalChannel.post(message, randomizedWith: prng, delegateManager: delegateManager, within: obvContext)
        let ownedIdentity = acceptableLocalChannel.ownedIdentity
        
        return [messageId: Set([ownedIdentity])]
        
    }

}
