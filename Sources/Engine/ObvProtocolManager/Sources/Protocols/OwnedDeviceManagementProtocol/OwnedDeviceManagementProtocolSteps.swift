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


import Foundation
import os.log
import ObvTypes
import ObvMetaManager
import ObvCrypto
import OlvidUtils
import ObvEncoder

// MARK: - Protocol Steps

extension OwnedDeviceManagementProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        case sendRequest = 0
        case processSetOwnedDeviceNameServerQuery = 1
        case processDeactivateOwnedDeviceServerQuery = 2
        case processSetUnexpiringOwnedDeviceServerQuery = 3
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
                
            case .sendRequest:
                let step = SendRequestStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .processSetOwnedDeviceNameServerQuery:
                let step = ProcessSetOwnedDeviceNameServerQueryStep(from: concreteProtocol, and: receivedMessage)
                return step

            case .processDeactivateOwnedDeviceServerQuery:
                let step = ProcessDeactivateOwnedDeviceServerQueryStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .processSetUnexpiringOwnedDeviceServerQuery:
                let step = ProcessSetUnexpiringOwnedDeviceServerQueryStep(from: concreteProtocol, and: receivedMessage)
                return step

            }
        }
    }
    
    // MARK: - SendRequestStep
    
    final class SendRequestStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateOwnedDeviceManagementMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: InitiateOwnedDeviceManagementMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: OwnedDeviceManagementProtocol.logCategory)

            let request = receivedMessage.request

            switch request {
                
            case .setOwnedDeviceName(let ownedDeviceUID, let ownedDeviceName):
                
                // Check whether the device is the current device or a remote device of the owned identity
                
                let isCurrentDevice: Bool
                if try ownedDeviceUID == identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext) {
                    isCurrentDevice = true
                } else if try identityDelegate.isDevice(withUid: ownedDeviceUID, aRemoteDeviceOfOwnedIdentity: ownedIdentity, within: obvContext) {
                    isCurrentDevice = false
                } else {
                    assertionFailure()
                    return CancelledState()
                }
                
                // Encrypt the device name
                
                guard let encryptedOwnedDeviceName = DeviceNameUtils.encrypt(deviceName: ownedDeviceName, for: ownedIdentity, using: prng) else {
                    assertionFailure()
                    os_log("Failed to encrypt device name", log: log, type: .fault)
                    return CancelledState()
                }
                            
                // Send the server query
                
                let coreMessage = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                let concreteMessage = SetOwnedDeviceNameServerQueryMessage(coreProtocolMessage: coreMessage)
                let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.setOwnedDeviceName(
                    ownedDeviceUID: ownedDeviceUID,
                    encryptedOwnedDeviceName: encryptedOwnedDeviceName,
                    isCurrentDevice: isCurrentDevice)
                guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: concreteCryptoProtocol.prng, within: obvContext)

                // Return the new state

                return WaitingForServerQueryResultState()

            case .deactivateOtherOwnedDevice(let ownedDeviceUID):

                // Make sure we are not deactivating the current device as deactivating the current device shall be done in the OwnedIdentityDeletionProtocol.
                
                guard try ownedDeviceUID != identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext) else {
                    assertionFailure("We are trying to deactivate the current device, which should be done in the OwnedIdentityDeletionProtocol")
                    return CancelledState()
                }

                // Check whether the device is the current device or a remote device of the owned identity
                
                let isCurrentDevice: Bool
                if try ownedDeviceUID == identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext) {
                    isCurrentDevice = true
                } else if try identityDelegate.isDevice(withUid: ownedDeviceUID, aRemoteDeviceOfOwnedIdentity: ownedIdentity, within: obvContext) {
                    isCurrentDevice = false
                } else {
                    return CancelledState()
                }
                
                // Send the server query
                
                let coreMessage = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                let concreteMessage = DeactivateOwnedDeviceServerQueryMessage(coreProtocolMessage: coreMessage)
                let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.deactivateOwnedDevice(
                    ownedDeviceUID: ownedDeviceUID,
                    isCurrentDevice: isCurrentDevice)
                guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: concreteCryptoProtocol.prng, within: obvContext)

                // Return the new state

                return WaitingForServerQueryResultState()

            case .setUnexpiringDevice(let ownedDeviceUID):
                
                // Check whether the device is the current device or a remote device of the owned identity
                
                // Send the server query
                
                let coreMessage = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                let concreteMessage = SetUnexpiringOwnedDeviceServerQueryMessage(coreProtocolMessage: coreMessage)
                let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.setUnexpiringOwnedDevice(ownedDeviceUID: ownedDeviceUID)
                guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: concreteCryptoProtocol.prng, within: obvContext)

                return WaitingForServerQueryResultState()
                
            }
            
            
        }
                
    }
    
    
    // MARK: - ProcessSetOwnedDeviceNameServerQueryStep
    
    final class ProcessSetOwnedDeviceNameServerQueryStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: WaitingForServerQueryResultState
        let receivedMessage: SetOwnedDeviceNameServerQueryMessage

        init?(startState: WaitingForServerQueryResultState, receivedMessage: SetOwnedDeviceNameServerQueryMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            // No need to set the device name locally, it will be updated during the following owned device discovery
            
            let messageToSend = try protocolStarterDelegate.getInitiateOwnedDeviceDiscoveryMessage(ownedCryptoIdentity: ownedIdentity)
            _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: concreteCryptoProtocol.prng, within: obvContext)
            
            // Return the new state

            return ServerQueryProcessedState()

        }

    }

    
    // MARK: - ProcessDeactivateOwnedDeviceServerQueryStep
    
    final class ProcessDeactivateOwnedDeviceServerQueryStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: WaitingForServerQueryResultState
        let receivedMessage: DeactivateOwnedDeviceServerQueryMessage

        init?(startState: WaitingForServerQueryResultState, receivedMessage: DeactivateOwnedDeviceServerQueryMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            // Perform an owned device discovery
            
            do {
                let messageToSend = try protocolStarterDelegate.getInitiateOwnedDeviceDiscoveryMessage(ownedCryptoIdentity: ownedIdentity)
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: concreteCryptoProtocol.prng, within: obvContext)
            }
            
            // Since we deactivated another owned device, we want to notify all our contacts, so that they perform a contact discovery
            
            let contactIdentites = try identityDelegate.getContactsOfOwnedIdentity(ownedIdentity, within: obvContext)
            if !contactIdentites.isEmpty {
                let channel = ObvChannelSendChannelType.allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: contactIdentites, fromOwnedIdentity: ownedIdentity)
                let coreMessage = getCoreMessageForOtherProtocol(for: channel, otherCryptoProtocolId: .contactManagement, otherProtocolInstanceUid: UID.gen(with: prng))
                let concreteMessage = ContactManagementProtocol.PerformContactDeviceDiscoveryMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    assertionFailure()
                    throw Self.makeError(message: "Implementation error")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Return the new state

            return ServerQueryProcessedState()

        }

    }

    
    // MARK: - ProcessSetUnexpiringOwnedDeviceServerQueryStep
    
    final class ProcessSetUnexpiringOwnedDeviceServerQueryStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: WaitingForServerQueryResultState
        let receivedMessage: SetUnexpiringOwnedDeviceServerQueryMessage

        init?(startState: WaitingForServerQueryResultState, receivedMessage: SetUnexpiringOwnedDeviceServerQueryMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            
            
            let messageToSend = try protocolStarterDelegate.getInitiateOwnedDeviceDiscoveryMessage(ownedCryptoIdentity: ownedIdentity)
            _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: concreteCryptoProtocol.prng, within: obvContext)

            // Return the new state

            return ServerQueryProcessedState()

        }

    }

}
