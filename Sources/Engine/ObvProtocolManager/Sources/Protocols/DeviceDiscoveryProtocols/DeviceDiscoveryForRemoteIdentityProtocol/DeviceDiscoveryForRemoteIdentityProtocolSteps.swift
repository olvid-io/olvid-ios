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
import ObvOperation
import ObvMetaManager
import OlvidUtils



// MARK: - Protocol Steps

extension DeviceDiscoveryForRemoteIdentityProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {

        case sendServerRequest
        case processDeviceUids
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            var concreteProtocolStep: ConcreteProtocolStep?
            switch self {
            case .sendServerRequest:
                concreteProtocolStep = SendServerRequestStep(from: concreteProtocol, and: receivedMessage)
            case .processDeviceUids:
                concreteProtocolStep = ProcessDeviceUidsFromServerStep(from: concreteProtocol, and: receivedMessage)
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
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
            
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let remoteIdentity = receivedMessage.remoteIdentity
            
            // Send the server query
            
            let coreMessage = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
            let concreteMessage = ServerQueryMessage(coreProtocolMessage: coreMessage)
            let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.deviceDiscovery(of: remoteIdentity)
            guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
            _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: concreteCryptoProtocol.prng, within: obvContext)
            
            // Return the new state
            
            return WaitingForDeviceUidsState(remoteIdentity: remoteIdentity)
        }
    }

    
    final class ProcessDeviceUidsFromServerStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForDeviceUidsState
        let receivedMessage: ServerQueryMessage
        
        init?(startState: StartConcreteProtocolStateType, receivedMessage: ConcreteProtocolMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
            
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: DeviceDiscoveryForRemoteIdentityProtocol.logCategory)
            
            let remoteIdentity = startState.remoteIdentity
            
            guard let contactDeviceDiscoveryResult = receivedMessage.contactDeviceDiscoveryResult else {
                os_log("The received server response does not contain a result. This is a bug", log: log, type: .error)
                assertionFailure()
                return CancelledState()
            }
            
            switch contactDeviceDiscoveryResult {
            case .failure:
                assertionFailure()
                return CancelledState()
            case .success(result: let result):
                return DeviceUidsReceivedState(remoteIdentity: remoteIdentity, result: result)
            }
                        
        }
    }
    
}
