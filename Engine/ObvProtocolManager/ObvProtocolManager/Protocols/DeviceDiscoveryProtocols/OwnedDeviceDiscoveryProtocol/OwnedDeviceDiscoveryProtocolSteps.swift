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

extension OwnedDeviceDiscoveryProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        case sendServerQuery = 0
        case processServerQuery = 1
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
                
            case .sendServerQuery:
                if let step = SendServerQueryFromInitiateOwnedDeviceDiscoveryMessageStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = SendServerQueryStepFromInitiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDeviceMessageStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else {
                    return nil
                }
                
            case .processServerQuery:
                let step = ProcessServerQueryStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            }
        }
    }
    
    // MARK: - SendServerQueryStep
    
    class SendServerQueryStep: ProtocolStep {
        
        private let startState: ConcreteProtocolInitialState
        private let receivedMessage: ReceivedMessageType
        
        enum ReceivedMessageType {
            case initiateOwnedDeviceDiscoveryMessage(receivedMessage: InitiateOwnedDeviceDiscoveryMessage)
            case initiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDeviceMessage(receivedMessage: InitiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDeviceMessage)
        }

        init?(startState: ConcreteProtocolInitialState, receivedMessage: ReceivedMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            switch receivedMessage {
            case .initiateOwnedDeviceDiscoveryMessage(receivedMessage: let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .Local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case .initiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDeviceMessage(receivedMessage: let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            }
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            // Send the server query
            
            let coreMessage = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
            let concreteMessage = ServerQueryMessage(coreProtocolMessage: coreMessage)
            let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.ownedDeviceDiscovery
            guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
            _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: concreteCryptoProtocol.prng, within: obvContext)

            // Return the new state

            return WaitingForServerQueryResultState()
            
        }
        
    }
    
    
    // MARK: SendServerQueryFromInitiateOwnedDeviceDiscoveryMessageStep
    
    final class SendServerQueryFromInitiateOwnedDeviceDiscoveryMessageStep: SendServerQueryStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateOwnedDeviceDiscoveryMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: InitiateOwnedDeviceDiscoveryMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: startState,
                       receivedMessage: .initiateOwnedDeviceDiscoveryMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }
    
    // MARK: SendServerQueryStepFromInitiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDeviceMessageStep
    
    final class SendServerQueryStepFromInitiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDeviceMessageStep: SendServerQueryStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDeviceMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: InitiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDeviceMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: startState,
                       receivedMessage: .initiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDeviceMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }

    
    
    
    
    
    
    
    // MARK: - ProcessServerQueryStep
    
    final class ProcessServerQueryStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForServerQueryResultState
        let receivedMessage: ServerQueryMessage
        
        init?(startState: WaitingForServerQueryResultState, receivedMessage: ServerQueryMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: OwnedDeviceDiscoveryProtocol.logCategory)
            
            guard let ownedDeviceDiscoveryResult = receivedMessage.ownedDeviceDiscoveryResult else {
                assertionFailure()
                os_log("The ServerQueryMessage has no ownedDeviceDiscoveryResult. This is a bug.", log: log, type: .fault)
                return CancelledState()
            }
            
            switch ownedDeviceDiscoveryResult {
                
            case .failure:
                return CancelledState()
                
            case .success(encryptedOwnedDeviceDiscoveryResult: let encryptedOwnedDeviceDiscoveryResult):
                
                let currentDeviceIsPartOfOwnedDeviceDiscoveryResult = try identityDelegate.processEncryptedOwnedDeviceDiscoveryResult(encryptedOwnedDeviceDiscoveryResult, forOwnedCryptoId: ownedIdentity, within: obvContext)
                
                if !currentDeviceIsPartOfOwnedDeviceDiscoveryResult {
                    ObvProtocolNotification.theCurrentDeviceWasNotPartOfTheLastOwnedDeviceDiscoveryResults(ownedIdentity: ownedIdentity)
                        .postOnBackgroundQueue(within: notificationDelegate)
                }
                
                // Return the new state
                
                return ServerQueryProcessedState()

            }
                        
        }
        
    }

}
