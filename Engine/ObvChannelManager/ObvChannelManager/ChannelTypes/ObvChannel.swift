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
import os.log
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils

protocol ObvChannel {

    var cryptoSuiteVersion: SuiteVersion { get }
    
    /// The returned set contains all the crypto identities to which the `message` was successfully posted.
    static func post(_ message: ObvChannelMessageToSend, randomizedWith prng: PRNGService, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> [ObvMessageIdentifier: Set<ObvCryptoIdentity>]
    
    static func acceptableChannelsForPosting(_ message: ObvChannelMessageToSend, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> [ObvChannel]
    
}

protocol ObvNetworkChannel: ObvChannel {
    
    func wrapMessageKey(_ messageKey: AuthenticatedEncryptionKey, randomizedWith prng: PRNGService) -> ObvNetworkMessageToSend.Header
    
    static func unwrapMessageKey(wrappedKey: EncryptedData, toOwnedIdentity: ObvCryptoIdentity, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> (AuthenticatedEncryptionKey, ObvProtocolReceptionChannelInfo)?

}

extension ObvNetworkChannel {
    
    private static var errorDomain: String { "ObvNetworkChannel" }
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    private static func generateMessageKeyAndHeaders(using acceptableChannels: [ObvNetworkChannel], randomizedWith prng: PRNGService) -> (AuthenticatedEncryptionKey, [ObvNetworkMessageToSend.Header])? {
        let cryptoSuiteVersion = acceptableChannels.reduce(ObvCryptoSuite.sharedInstance.latestVersion) { min($0, $1.cryptoSuiteVersion) }
        guard let authEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption(forSuiteVersion: cryptoSuiteVersion) else {
            return nil
        }
        let messageKey = authEnc.generateKey(with: prng)
        let headers = acceptableChannels.map { $0.wrapMessageKey(messageKey, randomizedWith: prng) }
        return (messageKey, headers)
    }

    /// Generates one or more `ObvNetworkMessageToSend` for the given `ObvChannelMessageToSend`. The reasons why multiple messages can be returned is that we generate one message for server URL found in the destination identities.
    private static func generateObvNetworkMessagesToSend(from message: ObvChannelMessageToSend, messageKey: AuthenticatedEncryptionKey, headers: [ObvNetworkMessageToSend.Header], randomizedWith prng: PRNGService) throws -> [ObvNetworkMessageToSend] {
        
        let wrapperMessage: ObvChannelMessageToSendWrapper?
        switch message.messageType {
        case .ProtocolMessage:
            wrapperMessage = ObvChannelProtocolMessageToSendWrapper(message: message, messageKey: messageKey, headers: headers, randomizedWith: prng)
        case .ApplicationMessage:
            wrapperMessage = ObvChannelApplicationMessageToSendWrapper(message: message, messageKey: messageKey, headers: headers, randomizedWith: prng)
        case .DialogMessage,
             .DialogResponseMessage,
             .ServerQuery,
             .ServerResponse:
            // Dialog/Server Queries messages are not intended to be sent over the network as protocol or application messages
            wrapperMessage = nil
        }
        guard let msg = wrapperMessage else { throw makeError(message: "Could not construct wrapper message") }
        return try msg.generateObvNetworkMessagesToSend()
        
    }
    
    static func post(_ message: ObvChannelMessageToSend, randomizedWith prng: PRNGService, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> [ObvMessageIdentifier: Set<ObvCryptoIdentity>] {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: "ObvNetworkChannel")
                
        guard let networkPostDelegate = delegateManager.networkPostDelegate else {
            os_log("The network post delegate is not set", log: log, type: .fault)
            throw Self.makeError(message: "The network post delegate is not set")
        }

        guard let acceptableChannels = try Self.acceptableChannelsForPosting(message, delegateManager: delegateManager, within: obvContext) as? [ObvNetworkChannel] else {
            throw Self.makeError(message: "Could not cast to [ObvNetworkChannel]")
        }
        
        guard !acceptableChannels.isEmpty else {
            os_log("Could not find any acceptable channel for posting message", log: log, type: .error)
            return [:]
        }
        
        guard let (messageKey, headers) = generateMessageKeyAndHeaders(using: acceptableChannels, randomizedWith: prng) else {
            throw Self.makeError(message: "Could not generate message key and headers")
        }
        
        let networkMessages = try generateObvNetworkMessagesToSend(from: message, messageKey: messageKey, headers: headers, randomizedWith: prng)
        guard !networkMessages.isEmpty else {
            throw Self.makeError(message: "Could not generate obv network message to send")
        }
        
        try networkMessages.forEach { networkMessage in
            try networkPostDelegate.post(networkMessage, within: obvContext)
        }
        
        // If we reach this point, the network post delegate accepted the network messages.
        // We can consider the messages as "posted" for all the identities for which we had a header.
        
        let messageIdsForCryptoIdentities = Dictionary(grouping: networkMessages, by: { $0.messageId })
            .mapValues {
                $0.reduce(Set<ObvCryptoIdentity>()) {
                    $0.union($1.headers.map { $0.toIdentity })
                }
            }
        
        return messageIdsForCryptoIdentities
                
    }
}
