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
import OlvidUtils


public struct DeviceDiscoveryForContactIdentityProtocol: ConcreteCryptoProtocol {
    
    static let logCategory = "DeviceDiscoveryForContactIdentityProtocol"
    
    static let id = CryptoProtocolId.DeviceDiscoveryForContactIdentity
    
    let finalStateIds: [ConcreteProtocolStateId] = [StateId.ChildProtocolStateProcessed, StateId.Cancelled]

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
    
    static let allStepIds: [ConcreteProtocolStepId] = [StepId.StartChildProtocol, StepId.ProcessChildProtocolState]
}

// MARK: - Protocol Steps

extension DeviceDiscoveryForContactIdentityProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId {

        case StartChildProtocol = 0
        case ProcessChildProtocolState = 1

        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
            case .StartChildProtocol        : return StartChildProtocolStep(from: concreteProtocol, and: receivedMessage)
            case .ProcessChildProtocolState : return ProcessChildProtocolStateStep(from: concreteProtocol, and: receivedMessage)
            }
        }
    }

    final class StartChildProtocolStep: ProtocolStep, TypedConcreteProtocolStep {

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

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: DeviceDiscoveryForContactIdentityProtocol.logCategory)

            let contactIdentity = receivedMessage.contactIdentity
            
            // We check that the identity is indeed a contact identity
            
            guard (try? identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true else {
                os_log("The identity %@ is not a contact identity of the owned identity %@", log: log, type: .fault, contactIdentity.debugDescription, ownedIdentity.debugDescription)
                return CancelledState()
            }
            
            guard try identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext) else {
                os_log("The identity %@ is not an active contact identity of the owned identity %@", log: log, type: .fault, contactIdentity.debugDescription, ownedIdentity.debugDescription)
                return CancelledState()
            }
            
            // We execute a child protocol : a DeviceDiscoveryForRemoteIdentityProtocol. So we create a link between this protocol instance and the future child protocol instance
            
            let childProtocolInstanceUid = UID.gen(with: prng)
            os_log("Creating a link between the parent with uid %@ and the child protocol with uid %@, with owned identity %@", log: log, type: .debug, protocolInstanceUid.debugDescription, childProtocolInstanceUid.debugDescription, ownedIdentity.debugDescription)
            
            guard let thisProtocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId, uid: protocolInstanceUid, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
                os_log("Could not retrive this protocol instance", log: log, type: .fault)
                return CancelledState()
            }
            guard let _ = LinkBetweenProtocolInstances(parentProtocolInstance: thisProtocolInstance,
                                                       childProtocolInstanceUid: childProtocolInstanceUid,
                                                       expectedChildStateRawId: DeviceDiscoveryForRemoteIdentityProtocol.StateId.DeviceUidsReceived.rawValue,
                                                       messageToSendRawId: MessageId.ChildProtocolReachedExpectedState.rawValue)
                else {
                    os_log("Could not create a link between protocol instances", log: log, type: .fault)
                    return CancelledState()
            }

            // To actually create the child protocol instance, we post an appropriate message on the loopback channel
            
            let coreMessage = getCoreMessageForOtherLocalProtocol(otherCryptoProtocolId: .DeviceDiscoveryForRemoteIdentity,
                                                                  otherProtocolInstanceUid: childProtocolInstanceUid)
            let childProtocolInitialMessage = DeviceDiscoveryForRemoteIdentityProtocol.InitialMessage(coreProtocolMessage: coreMessage,
                                                                                                      remoteIdentity: contactIdentity)
            guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw NSError() }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

            // Return the new state

            return WaitingForChildProtocolState(contactIdentity: contactIdentity)
        }
    }


    final class ProcessChildProtocolStateStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: WaitingForChildProtocolState
        let receivedMessage: ChildProtocolReachedExpectedStateMessage

        init?(startState: WaitingForChildProtocolState, receivedMessage: ChildProtocolReachedExpectedStateMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: DeviceDiscoveryForContactIdentityProtocol.logCategory)

            let contactIdentity: ObvCryptoIdentity
            do {
                let expectedContactIdentity = startState.contactIdentity
                let receivedContactIdentity = receivedMessage.deviceUidsSentState.remoteIdentity
                
                guard expectedContactIdentity == receivedContactIdentity else {
                    os_log("We received the device uids of an unexpected identity", log: log, type: .fault)
                    return CancelledState()
                }
                contactIdentity = expectedContactIdentity
            }

            let latestSetOfDeviceUids = Set(receivedMessage.deviceUidsSentState.deviceUids)

            // Get the list of previously known device uids
            
            let previousSetOfDeviceUids: Set<UID>
            do {
                previousSetOfDeviceUids = try identityDelegate.getDeviceUidsOfContactIdentity(contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
            } catch {
                os_log("Could not delete obsolete devices for a contact", log: log, type: .fault)
                assertionFailure()
                previousSetOfDeviceUids = Set<UID>()
                // We continue anyway
            }

            // Remove any obsolete device uid
            
            do {
                let obsoleteDeviceUids = previousSetOfDeviceUids.subtracting(latestSetOfDeviceUids)
                for deviceUid in obsoleteDeviceUids {
                    do {
                        try identityDelegate.removeDeviceForContactIdentity(contactIdentity, withUid: deviceUid, ofOwnedIdentity: ownedIdentity, within: obvContext)
                    } catch {
                        os_log("Could not remove one of the obsolete devices of a contact identity", log: log, type: .fault)
                        assertionFailure()
                        // We continue anyway
                    }
                }
            }
            
            // We can safely store the device uids as contact device uids of the contact identity
            
            for deviceUid in latestSetOfDeviceUids {
                do {
                    try identityDelegate.addDeviceForContactIdentity(contactIdentity, withUid: deviceUid, ofOwnedIdentity: ownedIdentity, within: obvContext)
                } catch {
                    os_log("Could not add a device to a contact identity", log: log, type: .fault)
                    assertionFailure()
                    // We continue anyway
                }
            }
            
            // Return the new state
            
            return ChildProtocolStateProcessedState()
            
        }
    }
}


// MARK: - Protocol Messages

extension DeviceDiscoveryForContactIdentityProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        case Initial = 0
        case ChildProtocolReachedExpectedState = 1
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .Initial                           : return InitialMessage.self
            case .ChildProtocolReachedExpectedState : return ChildProtocolReachedExpectedStateMessage.self
            }
        }
    }
    
    
    struct InitialMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.Initial
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactIdentity: ObvCryptoIdentity

        var encodedInputs: [ObvEncoded] {
            return [contactIdentity.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            contactIdentity = try message.encodedInputs.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
        }
    }
    
    
    struct ChildProtocolReachedExpectedStateMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.ChildProtocolReachedExpectedState
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let childToParentProtocolMessageInputs: ChildToParentProtocolMessageInputs
        let deviceUidsSentState: DeviceDiscoveryForRemoteIdentityProtocol.DeviceUidsReceivedState
        
        var encodedInputs: [ObvEncoded] {
            return childToParentProtocolMessageInputs.toListOfEncoded()
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard let inputs = ChildToParentProtocolMessageInputs(message.encodedInputs) else { throw NSError() }
            childToParentProtocolMessageInputs = inputs
            deviceUidsSentState = try DeviceDiscoveryForRemoteIdentityProtocol.DeviceUidsReceivedState(childToParentProtocolMessageInputs.childProtocolInstanceEncodedReachedState)
        }
    }
}

// MARK: - Protocol States

extension DeviceDiscoveryForContactIdentityProtocol {
    
    
    enum StateId: Int, ConcreteProtocolStateId {

        case InitialState = 0
        case WaitingForChildProtocol = 1
        case ChildProtocolStateProcessed = 2
        case Cancelled = 3

        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .InitialState                 : return ConcreteProtocolInitialState.self
            case .WaitingForChildProtocol      : return WaitingForChildProtocolState.self
            case .ChildProtocolStateProcessed  : return ChildProtocolStateProcessedState.self
            case .Cancelled                    : return CancelledState.self
            }
        }
    }
    
    struct WaitingForChildProtocolState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.WaitingForChildProtocol
        
        let contactIdentity: ObvCryptoIdentity
        
        init(_ obvEncoded: ObvEncoded) throws {
            do {
                contactIdentity = try obvEncoded.obvDecode()
            } catch let error {
                throw error
            }
        }
        
        init(contactIdentity: ObvCryptoIdentity) {
            self.contactIdentity = contactIdentity
        }
        
        func obvEncode() -> ObvEncoded {
            return contactIdentity.obvEncode()
        }
    }

    struct ChildProtocolStateProcessedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.ChildProtocolStateProcessed
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
    }
    
    struct CancelledState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.Cancelled
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
    }

}
