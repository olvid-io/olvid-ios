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
import ObvCrypto
import ObvEncoder
import ObvTypes
import ObvOperation
import ObvMetaManager
import OlvidUtils


public struct DeviceDiscoveryForRemoteIdentityProtocol: ConcreteCryptoProtocol {
    
    static let logCategory = "DeviceDiscoveryForRemoteIdentityProtocol"
    
    static let id = CryptoProtocolId.DeviceDiscoveryForRemoteIdentity
    
    static let finalStateIds: [ConcreteProtocolStateId] = [StateId.DeviceUidsReceived, StateId.DeviceUidsSent]
    
    let ownedIdentity: ObvCryptoIdentity
    let currentState: ConcreteProtocolState
    
    let delegateManager: ObvProtocolDelegateManager
    let obvContext: ObvContext
    let prng: PRNGService
    let instanceUid: UID
    
    init(instanceUid: UID, currentState: ConcreteProtocolState, ownedCryptoIdentity: ObvCryptoIdentity, delegateManager: ObvProtocolDelegateManager, prng: PRNGService, within obvContext: ObvContext) {
        self.currentState = currentState
        self.ownedIdentity = ownedCryptoIdentity
        self.delegateManager = delegateManager
        self.obvContext = obvContext
        self.prng = prng
        self.instanceUid = instanceUid
    }
    
    static func stateId(fromRawValue rawValue: Int) -> ConcreteProtocolStateId? {
        return StateId(rawValue: rawValue)
    }
    
    static func messageId(fromRawValue rawValue: Int) -> ConcreteProtocolMessageId? {
        return MessageId(rawValue: rawValue)
    }
    
    static let allStepIds: [ConcreteProtocolStepId] = [StepId.SendServerRequest,
                                                       StepId.ProcessDeviceUidsFromServerOrSendrequest,
                                                       StepId.RespondToRequest,
                                                       StepId.ProcessDeviceUids]
}

// MARK: - Protocol Steps

extension DeviceDiscoveryForRemoteIdentityProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId {
        
        case SendServerRequest = 3
        case ProcessDeviceUidsFromServerOrSendrequest = 0
        case RespondToRequest = 1
        case ProcessDeviceUids = 2
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            var concreteProtocolStep: ConcreteProtocolStep?
            switch self {
            case .SendServerRequest:
                concreteProtocolStep = SendServerRequestStep(from: concreteProtocol, and: receivedMessage)
            case .ProcessDeviceUidsFromServerOrSendrequest:
                concreteProtocolStep = ProcessDeviceUidsFromServerOrSendRequestStep(from: concreteProtocol, and: receivedMessage)
            case .RespondToRequest:
                concreteProtocolStep = RespondToRequestStep(from: concreteProtocol, and: receivedMessage)
            case .ProcessDeviceUids:
                concreteProtocolStep = ProcessDeviceUidsStep(from: concreteProtocol, and: receivedMessage)
            }
            return concreteProtocolStep
        }
    }
    
    final class SendServerRequestStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialMessage
        
        init?(startState: StartConcreteProtocolStateType, receivedMessage: ConcreteProtocolMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
            
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let remoteIdentity = receivedMessage.remoteIdentity
            
            // Send the server query
            
            let coreMessage = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
            let concreteMessage = ServerQueryMessage(coreProtocolMessage: coreMessage)
            let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.deviceDiscovery(of: remoteIdentity)
            guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
            _ = try channelDelegate.post(messageToSend, randomizedWith: concreteCryptoProtocol.prng, within: obvContext)
            
            // Return the new state
            
            return WaitingForDeviceUidsState.init(remoteIdentity: remoteIdentity)
        }
    }

    
    final class ProcessDeviceUidsFromServerOrSendRequestStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForDeviceUidsState
        let receivedMessage: ServerQueryMessage
        
        init?(startState: StartConcreteProtocolStateType, receivedMessage: ConcreteProtocolMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
            
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: DeviceDiscoveryForRemoteIdentityProtocol.logCategory)
            
            let remoteIdentity = startState.remoteIdentity
            guard let deviceUids = receivedMessage.deviceUids else {
                os_log("The received server response does not contain device uids", log: log, type: .error)
                return nil
            }
            
            let nextState: ConcreteProtocolState
            
            // If we received no device uids, we send a new request directly to the remote identity.
            // If we receive at least one device uid, we assume the server knows about all the device uids and go the final state right now
            
            if deviceUids.isEmpty {

                os_log("The server knows no device uid for the remote identity. We query the remote identity directly.", log: log, type: .debug)
                
                // Get current device uid
                
                let currentDeviceUid: UID
                do {
                    currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
                } catch {
                    os_log("Could not get current device uid", log: log, type: .fault)
                    return nil
                }

                // Send the message
                
                let coreMessage = getCoreMessage(for: .AsymmetricChannelBroadcast(to: remoteIdentity, fromOwnedIdentity: ownedIdentity))
                let concreteMessage = FromAliceMessage(coreProtocolMessage: coreMessage, remoteIdentity: ownedIdentity, remoteDeviceUid: currentDeviceUid)
                guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: concreteCryptoProtocol.prng, within: obvContext)

                nextState = WaitingForDeviceUidsState.init(remoteIdentity: remoteIdentity)
                
            } else {
                
                os_log("The server knows %d device uids for the remote identity.", log: log, type: .debug, deviceUids.count)
                
                nextState = DeviceUidsReceivedState(remoteIdentity: remoteIdentity, deviceUids: deviceUids)
                
            }

            return nextState
        }
    }
    
    final class RespondToRequestStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: FromAliceMessage
        
        init?(startState: StartConcreteProtocolStateType, receivedMessage: ConcreteProtocolMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AsymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
            
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let remoteIdentity = receivedMessage.remoteIdentity
            let remoteDeviceUid = receivedMessage.remoteDeviceUid
            
            // Get a set of all device uids of the owned identity
            
            let allDeviceUids = try identityDelegate.getDeviceUidsOfOwnedIdentity(concreteCryptoProtocol.ownedIdentity, within: obvContext)
            
            // Broadcast the longterm identity's device uids using an asymmetric channel with the fresh ephemeral identity
            
            do {
                let coreMessage = getCoreMessage(for: .AsymmetricChannel(to: remoteIdentity, remoteDeviceUids: [remoteDeviceUid], fromOwnedIdentity: ownedIdentity))
                let concreteMessage = FromBobMessage(coreProtocolMessage: coreMessage, deviceUids: Array(allDeviceUids))
                guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Return the new state
            return DeviceUidsSentState()
        }
    }

    
    final class ProcessDeviceUidsStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForDeviceUidsState
        let receivedMessage: FromBobMessage
        
        init?(startState: StartConcreteProtocolStateType, receivedMessage: ConcreteProtocolMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AsymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
            
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let remoteIdentity = startState.remoteIdentity
            let deviceUids = receivedMessage.deviceUids
            
            // Return the new state
            return DeviceUidsReceivedState(remoteIdentity: remoteIdentity, deviceUids: deviceUids)
            
        }
    }

}


// MARK: - Protocol Messages

extension DeviceDiscoveryForRemoteIdentityProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        case Initial = 0
        case ServerQuery = 3
        case FromAlice = 1
        case FromBob = 2
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .Initial     : return InitialMessage.self
            case .ServerQuery : return ServerQueryMessage.self
            case .FromAlice   : return FromAliceMessage.self
            case .FromBob     : return FromBobMessage.self
            }
        }
    }
    
    
    struct InitialMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.Initial
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let remoteIdentity: ObvCryptoIdentity
        
        var encodedInputs: [ObvEncoded] {
            return [remoteIdentity.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            remoteIdentity = try message.encodedInputs.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, remoteIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.remoteIdentity = remoteIdentity
        }
    }
    
    
    struct ServerQueryMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.ServerQuery
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message

        let deviceUids: [UID]? // Only set when the message is sent to this protocol, not when sending this message to the server
        
        var encodedInputs: [ObvEncoded] { return [] }
        
        // Initializers

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            guard let listOfEncodedUids = [ObvEncoded](encodedElements[0]) else { assertionFailure(); throw Self.makeError(message: "Failed to get list of encoded inputs") }
            var uids = [UID]()
            for encodedUid in listOfEncodedUids {
                guard let uid = UID(encodedUid) else { assertionFailure(); throw Self.makeError(message: "Failed to decode UID") }
                uids.append(uid)
            }
            self.deviceUids = uids
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.deviceUids = nil
        }
    }
    
    
    struct FromAliceMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.FromAlice
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let remoteIdentity: ObvCryptoIdentity
        let remoteDeviceUid: UID
        
        var encodedInputs: [ObvEncoded] {
            return [remoteIdentity.obvEncode(), remoteDeviceUid.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            (remoteIdentity, remoteDeviceUid) = try message.encodedInputs.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, remoteIdentity: ObvCryptoIdentity, remoteDeviceUid: UID) {
            self.coreProtocolMessage = coreProtocolMessage
            self.remoteIdentity = remoteIdentity
            self.remoteDeviceUid = remoteDeviceUid
        }
    }


    struct FromBobMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.FromBob
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let deviceUids: [UID]
        
        var encodedInputs: [ObvEncoded] {
            return [(deviceUids as [ObvEncodable]).obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            let deviceUidsAsEncodedList = message.encodedInputs[0]
            guard let listOfEncodedUids = [ObvEncoded](deviceUidsAsEncodedList) else { assertionFailure(); throw Self.makeError(message: "Failed to obtain encoded device uids") }
            deviceUids = try listOfEncodedUids.map { try $0.obvDecode() }
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, deviceUids: [UID]) {
            self.coreProtocolMessage = coreProtocolMessage
            self.deviceUids = deviceUids
        }
        
    }
}

// MARK: - Protocol States

extension DeviceDiscoveryForRemoteIdentityProtocol {
    
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case InitialState = 0
        // Alice's side
        case WaitingForDeviceUids = 1
        case DeviceUidsReceived = 2 // Final
        // Bob's side
        case DeviceUidsSent = 3 // Final
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .InitialState         : return ConcreteProtocolInitialState.self
            case .WaitingForDeviceUids : return WaitingForDeviceUidsState.self
            case .DeviceUidsReceived   : return DeviceUidsReceivedState.self
            case .DeviceUidsSent       : return DeviceUidsSentState.self
            }
        }
    }
    
    
    struct WaitingForDeviceUidsState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.WaitingForDeviceUids
        
        let remoteIdentity: ObvCryptoIdentity
        
        init(_ encoded: ObvEncoded) throws {
            (remoteIdentity) = try encoded.obvDecode()
        }
        
        init(remoteIdentity: ObvCryptoIdentity) {
            self.remoteIdentity = remoteIdentity
        }
        
        func obvEncode() -> ObvEncoded {
            return remoteIdentity.obvEncode()
        }
        
    }
    
    
    struct DeviceUidsReceivedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.DeviceUidsReceived
        
        let remoteIdentity: ObvCryptoIdentity
        let deviceUids: [UID]
        
        init(_ obvEncoded: ObvEncoded) throws {
            guard let listOfEncoded = [ObvEncoded](obvEncoded, expectedCount: 2) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded elements") }
            remoteIdentity = try listOfEncoded[0].obvDecode()
            guard let listOfEncodedDeviceUids = [ObvEncoded](listOfEncoded[1]) else { assertionFailure(); throw Self.makeError(message: "Failed to obtain encoded device uids") }
            deviceUids = try listOfEncodedDeviceUids.map { return try $0.obvDecode() }
        }
        
        init(remoteIdentity: ObvCryptoIdentity, deviceUids: [UID]) {
            self.remoteIdentity = remoteIdentity
            self.deviceUids = deviceUids
        }
        
        func obvEncode() -> ObvEncoded {
            let listOfEncodedDeviceUids = deviceUids.map { $0.obvEncode() }
            let encodedDeviceUids = listOfEncodedDeviceUids.obvEncode()
            let encodedRemoteIdentity = remoteIdentity.obvEncode()
            return [encodedRemoteIdentity, encodedDeviceUids].obvEncode()
        }
    }

    struct DeviceUidsSentState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.DeviceUidsSent
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
    }

}
