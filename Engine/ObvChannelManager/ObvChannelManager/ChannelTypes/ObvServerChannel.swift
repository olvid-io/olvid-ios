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
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils

final class ObvServerChannel: ObvChannel {
    
    private static let logCategory = "ObvServerChannel"
    
    private static let errorDomain = "ObvServerChannel"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    private let ownedIdentity: ObvCryptoIdentity
    let cryptoSuiteVersion: SuiteVersion = 0

    private init(ownedIdentity: ObvCryptoIdentity) {
        self.ownedIdentity = ownedIdentity
    }
}

// MARK: - Implementing ObvChannel
extension ObvServerChannel {
    
    private func post(_ message: ObvChannelMessageToSend, randomizedWith prng: PRNGService, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> MessageIdentifier {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObvServerChannel.logCategory)
        
        guard let networkFetchDelegate = delegateManager.networkFetchDelegate else {
            os_log("The network fetch delegate is not set", log: log, type: .fault)
            throw Self.makeError(message: "The network fetch delegate is not set")
        }

        switch message.messageType {
        case .ServerQuery:
            
            os_log("Posting a server query on a server channel", log: log, type: .debug)

            guard let message = message as? ObvChannelServerQueryMessageToSend else {
                os_log("Could not cast to dialog message", log: log, type: .fault)
                throw Self.makeError(message: "Could not cast to dialog message")
            }
            
            // Transform an ObvChannelServerQueryMessageToSend.QueryType (type within the Channel Manager) into a ServerQuery.QueryType (Network Fetch Manager type)
            let serverQueryType: ServerQuery.QueryType
            switch message.queryType {
            case .deviceDiscovery(of: let identity):
                serverQueryType = .deviceDiscovery(of: identity)
            case .putUserData(label: let label, dataURL: let dataURL, dataKey: let dataKey):
                serverQueryType = .putUserData(label: label, dataURL: dataURL, dataKey: dataKey)
            case .getUserData(of: let identity, label: let label):
                serverQueryType = .getUserData(of: identity, label: label)
            case .checkKeycloakRevocation(keycloakServerUrl: let keycloakServerUrl, signedContactDetails: let signedContactDetails):
                serverQueryType = .checkKeycloakRevocation(keycloakServerUrl: keycloakServerUrl, signedContactDetails: signedContactDetails)
            }
            
            let serverQuery = ServerQuery(ownedIdentity: ownedIdentity, queryType: serverQueryType, encodedElements: message.encodedElements)
            
            networkFetchDelegate.postServerQuery(serverQuery, within: obvContext)
            
            let randomUid = UID.gen(with: prng)
            let messageId = MessageIdentifier(ownedCryptoIdentity: ownedIdentity, uid: randomUid)

            return messageId

        default:
            os_log("Inappropriate message type posted on a server channel", log: log, type: .fault)
            throw Self.makeError(message: "Inappropriate message type posted on a server channel")

        }
    }

    static func acceptableChannelsForPosting(_ message: ObvChannelMessageToSend, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> [ObvChannel] {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw ObvServerChannel.makeError(message: "The identity delegate is not set")
        }
        
        let acceptableChannels: [ObvChannel]
        
        switch message.channelType {
            
        case .ServerQuery(ownedIdentity: let ownedIdentity):
            // Only server query messages may be sent through the server channel
            guard message.messageType == .ServerQuery else {
                throw ObvServerChannel.makeError(message: "Wrong message type")
            }
            
            if try identityDelegate.isOwned(ownedIdentity, within: obvContext) {
                acceptableChannels = [ObvServerChannel(ownedIdentity: ownedIdentity)]
            } else {
                assertionFailure()
                throw ObvServerChannel.makeError(message: "Identity is not owned")
            }
            
            
        default:
            os_log("Wrong message channel type", log: log, type: .fault)
            throw ObvServerChannel.makeError(message: "Wrong message channel type")
        }

        return acceptableChannels
        
    }

    static func post(_ message: ObvChannelMessageToSend, randomizedWith prng: PRNGService, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> [MessageIdentifier: Set<ObvCryptoIdentity>] {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObvServerChannel.logCategory)

        guard let acceptableChannels = try acceptableChannelsForPosting(message, delegateManager: delegateManager, within: obvContext) as? [ObvServerChannel] else {
            os_log("No acceptable server channel found", log: log, type: .error)
            throw ObvServerChannel.makeError(message: "No acceptable server channel found")
        }
        
        guard acceptableChannels.count == 1, let acceptableServerChannel = acceptableChannels.first else {
            os_log("Unexpected number of server channels found. Expecting 1, go %d", log: log, type: .error, acceptableChannels.count)
            throw Self.makeError(message: "Unexpected number of server channels found")
        }

        let messageId = try acceptableServerChannel.post(message, randomizedWith: prng, delegateManager: delegateManager, within: obvContext)
        
        return [messageId: Set([acceptableServerChannel.ownedIdentity])]
        
    }

}
