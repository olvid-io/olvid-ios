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
    
    private func post(_ message: ObvChannelMessageToSend, randomizedWith prng: PRNGService, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> ObvMessageIdentifier {
        
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
            case .createGroupBlob(groupIdentifier: let groupIdentifier, serverAuthenticationPublicKey: let serverAuthenticationPublicKey, encryptedBlob: let encryptedBlob):
                serverQueryType = .createGroupBlob(groupIdentifier: groupIdentifier, serverAuthenticationPublicKey: serverAuthenticationPublicKey, encryptedBlob: encryptedBlob)
            case .getGroupBlob(groupIdentifier: let groupIdentifier):
                serverQueryType = .getGroupBlob(groupIdentifier: groupIdentifier)
            case .deleteGroupBlob(groupIdentifier: let groupIdentifier, signature: let signature):
                serverQueryType = .deleteGroupBlob(groupIdentifier: groupIdentifier, signature: signature)
            case .putGroupLog(groupIdentifier: let groupIdentifier, querySignature: let querySignature):
                serverQueryType = .putGroupLog(groupIdentifier: groupIdentifier, querySignature: querySignature)
            case .requestGroupBlobLock(groupIdentifier: let groupIdentifier, lockNonce: let lockNonce, signature: let signature):
                serverQueryType = .requestGroupBlobLock(groupIdentifier: groupIdentifier, lockNonce: lockNonce, signature: signature)
            case .updateGroupBlob(groupIdentifier: let groupIdentifier, encodedServerAdminPublicKey: let encodedServerAdminPublicKey, encryptedBlob: let encryptedBlob, lockNonce: let lockNonce, signature: let signature):
                serverQueryType = .updateGroupBlob(groupIdentifier: groupIdentifier, encodedServerAdminPublicKey: encodedServerAdminPublicKey, encryptedBlob: encryptedBlob, lockNonce: lockNonce, signature: signature)
            case .getKeycloakData(serverURL: let serverURL, serverLabel: let serverLabel):
                serverQueryType = .getKeycloakData(serverURL: serverURL, serverLabel: serverLabel)
            case .ownedDeviceDiscovery:
                serverQueryType = .ownedDeviceDiscovery
            case .setOwnedDeviceName(ownedDeviceUID: let ownedDeviceUID, encryptedOwnedDeviceName: let encryptedOwnedDeviceName, isCurrentDevice: let isCurrentDevice):
                serverQueryType = .setOwnedDeviceName(ownedDeviceUID: ownedDeviceUID, encryptedOwnedDeviceName: encryptedOwnedDeviceName, isCurrentDevice: isCurrentDevice)
            case .deactivateOwnedDevice(ownedDeviceUID: let ownedDeviceUID, isCurrentDevice: let isCurrentDevice):
                serverQueryType = .deactivateOwnedDevice(ownedDeviceUID: ownedDeviceUID, isCurrentDevice: isCurrentDevice)
            case .setUnexpiringOwnedDevice(ownedDeviceUID: let ownedDeviceUID):
                serverQueryType = .setUnexpiringOwnedDevice(ownedDeviceUID: ownedDeviceUID)
            case .sourceGetSessionNumber(protocolInstanceUID: let protocolInstanceUID):
                serverQueryType = .sourceGetSessionNumber(protocolInstanceUID: protocolInstanceUID)
            case .sourceWaitForTargetConnection(protocolInstanceUID: let protocolInstanceUID):
                serverQueryType = .sourceWaitForTargetConnection(protocolInstanceUID: protocolInstanceUID)
            case .targetSendEphemeralIdentity(protocolInstanceUID: let protocolInstanceUID, transferSessionNumber: let transferSessionNumber, payload: let payload):
                serverQueryType = .targetSendEphemeralIdentity(protocolInstanceUID: protocolInstanceUID, transferSessionNumber: transferSessionNumber, payload: payload)
            case .transferRelay(protocolInstanceUID: let protocolInstanceUID, connectionIdentifier: let connectionIdentifier, payload: let payload, thenCloseWebSocket: let thenCloseWebSocket):
                serverQueryType = .transferRelay(protocolInstanceUID: protocolInstanceUID, connectionIdentifier: connectionIdentifier, payload: payload, thenCloseWebSocket: thenCloseWebSocket)
            case .transferWait(protocolInstanceUID: let protocolInstanceUID, connectionIdentifier: let connectionIdentifier):
                serverQueryType = .transferWait(protocolInstanceUID: protocolInstanceUID, connectionIdentifier: connectionIdentifier)
            case .closeWebsocketConnection(protocolInstanceUID: let protocolInstanceUID):
                serverQueryType = .closeWebsocketConnection(protocolInstanceUID: protocolInstanceUID)
            case .uploadPreKeyForCurrentDevice(deviceBlobOnServerToUpload: let deviceBlobOnServerToUpload):
                serverQueryType = .uploadPreKeyForCurrentDevice(deviceBlobOnServerToUpload: deviceBlobOnServerToUpload)
            }
            
            let serverQuery = ServerQuery(ownedIdentity: ownedIdentity, queryType: serverQueryType, encodedElements: message.encodedElements)
            
            networkFetchDelegate.postServerQuery(serverQuery, within: obvContext)
            
            let randomUid = UID.gen(with: prng)
            let messageId = ObvMessageIdentifier(ownedCryptoIdentity: ownedIdentity, uid: randomUid)

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
            
        case .serverQuery(ownedIdentity: let ownedIdentity):
            // Only server query messages may be sent through the server channel
            guard message.messageType == .ServerQuery else {
                throw ObvServerChannel.makeError(message: "Wrong message type")
            }

            /// We check that the identity is owned. On some occasions (like in the owned identity transfer protocol), we can use ephemeral owned identities
            if try identityDelegate.isOwned(ownedIdentity, within: obvContext) || message.channelType.fromOwnedIdentity.serverURL == ObvConstants.ephemeralIdentityServerURL {
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

    static func post(_ message: ObvChannelMessageToSend, randomizedWith prng: PRNGService, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> [ObvMessageIdentifier: Set<ObvCryptoIdentity>] {
        
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
