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
import CoreData
import os.log
import ObvCrypto
import ObvEncoder
import ObvTypes
import ObvMetaManager
import JWS
import OlvidUtils


// MARK: - Protocol Steps

extension KeycloakBindingAndUnbindingProtocol {

    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        case ownedIdentityKeycloakBinding = 0
        case ownedIdentityKeycloakUnbinding = 1

        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
            case .ownedIdentityKeycloakBinding:
                if let step = OwnedIdentityKeycloakBindingFromOwnedIdentityKeycloakBindingMessageStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = OwnedIdentityKeycloakBindingFromPropagateKeycloakBindingMessageStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else {
                    return nil
                }
            case .ownedIdentityKeycloakUnbinding:
                if let step = OwnedIdentityKeycloakUnbindingFromOwnedIdentityKeycloakUnbindingMessageStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = OwnedIdentityKeycloakUnbindingFromPropagateKeycloakUnbindingMessageStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else {
                    return nil
                }
            }
        }

    }


    // MARK: - OwnedIdentityKeycloakBindingStep
    
    class OwnedIdentityKeycloakBindingStep: ProtocolStep {
        
        private let startState: ConcreteProtocolInitialState
        private let receivedMessage: ReceivedMessageType

        enum ReceivedMessageType {
            case ownedIdentityKeycloakBinding(receivedMessage: OwnedIdentityKeycloakBindingMessage)
            case propagateKeycloakBinding(receivedMessage: PropagateKeycloakBindingMessage)
        }

        init?(startState: ConcreteProtocolInitialState, receivedMessage: ReceivedMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            switch receivedMessage {
            case .ownedIdentityKeycloakBinding(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case .propagateKeycloakBinding(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            }
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            eraseReceivedMessagesAfterReachingAFinalState = false
            
            let keycloakState: ObvKeycloakState
            let keycloakUserId: String
            let propagationNeeded: Bool
            
            switch receivedMessage {
            case .ownedIdentityKeycloakBinding(let receivedMessage):
                keycloakState = receivedMessage.keycloakState
                keycloakUserId = receivedMessage.keycloakUserId
                propagationNeeded = true
            case .propagateKeycloakBinding(let receivedMessage):
                keycloakState = receivedMessage.keycloakState
                keycloakUserId = receivedMessage.keycloakUserId
                propagationNeeded = false
            }

            // Bind the owned identity
            
            try identityDelegate.bindOwnedIdentityToKeycloak(
                ownedCryptoIdentity: ownedIdentity,
                keycloakUserId: keycloakUserId,
                keycloakState: keycloakState,
                within: obvContext)
            
            // Propagate the binding to other owned devices
            
            if propagationNeeded {
                
                let otherDeviceUIDs = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
                if !otherDeviceUIDs.isEmpty {
                    let channelType = ObvChannelSendChannelType.obliviousChannel(to: ownedIdentity, 
                                                                                 remoteDeviceUids: Array(otherDeviceUIDs),
                                                                                 fromOwnedIdentity: ownedIdentity,
                                                                                 necessarilyConfirmed: true,
                                                                                 usePreKeyIfRequired: true)
                    let coreMessage = getCoreMessage(for: channelType)
                    let concreteMessage = PropagateKeycloakBindingMessage(
                        coreProtocolMessage: coreMessage,
                        keycloakUserId: keycloakUserId,
                        keycloakState: keycloakState)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
            } else {
                
                do {
                    let notificationDelegate = self.notificationDelegate
                    let ownedIdentity = self.ownedIdentity
                    try obvContext.addContextDidSaveCompletionHandler { error in
                        guard error == nil else { return }
                        ObvProtocolNotification.keycloakSynchronizationRequired(ownedIdentity: ownedIdentity)
                            .postOnBackgroundQueue(within: notificationDelegate)
                    }
                } catch {
                    assertionFailure(error.localizedDescription) // In production, continue anyway
                }
                
            }
            
            // Return the final state

            return FinishedState()
            
        }
        
    }
    
    
    // MARK: OwnedIdentityKeycloakBindingStep from OwnedIdentityKeycloakBindingMessage
    
    final class OwnedIdentityKeycloakBindingFromOwnedIdentityKeycloakBindingMessageStep: OwnedIdentityKeycloakBindingStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: OwnedIdentityKeycloakBindingMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: OwnedIdentityKeycloakBindingMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: startState,
                       receivedMessage: .ownedIdentityKeycloakBinding(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass
        
    }

    
    // MARK: OwnedIdentityKeycloakBindingStep from PropagateKeycloakBindingMessage
    
    final class OwnedIdentityKeycloakBindingFromPropagateKeycloakBindingMessageStep: OwnedIdentityKeycloakBindingStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PropagateKeycloakBindingMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: PropagateKeycloakBindingMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: startState,
                       receivedMessage: .propagateKeycloakBinding(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass
        
    }

    
    // MARK: - OwnedIdentityKeycloakUnbindingStep
    
    class OwnedIdentityKeycloakUnbindingStep: ProtocolStep {
        
        private let startState: ConcreteProtocolInitialState
        private let receivedMessage: ReceivedMessageType

        enum ReceivedMessageType {
            case ownedIdentityKeycloakUnbinding(receivedMessage: OwnedIdentityKeycloakUnbindingMessage)
            case propagateKeycloakUnbinding(receivedMessage: PropagateKeycloakUnbindingMessage)
        }

        init?(startState: ConcreteProtocolInitialState, receivedMessage: ReceivedMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            switch receivedMessage {
            case .ownedIdentityKeycloakUnbinding(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case .propagateKeycloakUnbinding(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            }
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            eraseReceivedMessagesAfterReachingAFinalState = false
            
            let propagationNeeded: Bool
            
            switch receivedMessage {
            case .ownedIdentityKeycloakUnbinding:
                propagationNeeded = true
            case .propagateKeycloakUnbinding:
                propagationNeeded = false
            }

            // Unbind the owned identity
            
            try identityDelegate.unbindOwnedIdentityFromKeycloak(
                ownedCryptoIdentity: ownedIdentity,
                within: obvContext)
            
            // Propagate the binding to other owned devices
            
            if propagationNeeded {
                
                let otherDeviceUIDs = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
                if !otherDeviceUIDs.isEmpty {
                    let channelType = ObvChannelSendChannelType.obliviousChannel(to: ownedIdentity, 
                                                                                 remoteDeviceUids: Array(otherDeviceUIDs),
                                                                                 fromOwnedIdentity: ownedIdentity,
                                                                                 necessarilyConfirmed: true,
                                                                                 usePreKeyIfRequired: true)
                    let coreMessage = getCoreMessage(for: channelType)
                    let concreteMessage = PropagateKeycloakUnbindingMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
            }
            
            // Return the final state

            return FinishedState()
            
        }
        
    }
    
    
    // MARK: OwnedIdentityKeycloakUnbindingStep from OwnedIdentityKeycloakUnbindingMessage
    
    final class OwnedIdentityKeycloakUnbindingFromOwnedIdentityKeycloakUnbindingMessageStep: OwnedIdentityKeycloakUnbindingStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: OwnedIdentityKeycloakUnbindingMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: OwnedIdentityKeycloakUnbindingMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: startState,
                       receivedMessage: .ownedIdentityKeycloakUnbinding(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass
        
    }

    
    // MARK: OwnedIdentityKeycloakUnbindingStep from PropagateKeycloakUnbindingMessage
    
    final class OwnedIdentityKeycloakUnbindingFromPropagateKeycloakUnbindingMessageStep: OwnedIdentityKeycloakUnbindingStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PropagateKeycloakUnbindingMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: PropagateKeycloakUnbindingMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: startState,
                       receivedMessage: .propagateKeycloakUnbinding(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass
        
    }


}
