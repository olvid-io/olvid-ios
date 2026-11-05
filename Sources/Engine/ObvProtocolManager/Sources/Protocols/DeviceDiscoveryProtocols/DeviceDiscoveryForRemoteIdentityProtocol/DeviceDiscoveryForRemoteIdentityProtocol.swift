/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import OSLog
import ObvCrypto
import ObvEncoder
import ObvTypes
import ObvOperation
import ObvMetaManager
import OlvidUtils


public struct DeviceDiscoveryForRemoteIdentityProtocol: ConcreteCryptoProtocol {
    
    static let logCategory = "DeviceDiscoveryForRemoteIdentityProtocol"
    
    static let id = CryptoProtocolId.deviceDiscoveryForRemoteIdentity
    
    static let finalStateIds: [ConcreteProtocolStateId] = [
        StateId.deviceUidsReceived,
        StateId.cancelled,
        StateId.serverQueryFailed,
    ]
    
    enum FinalState {
        case deviceUidsReceived(DeviceUidsReceivedState)
        case serverQueryFailed(ServerQueryFailedState)
        case cancelled

        init(_ inputs: ChildToParentProtocolMessageInputs) throws {
            guard let stateId = StateId(rawValue: inputs.childProtocolInstanceReachedStateRawId) else {
                assertionFailure()
                throw ObvError.unknownStateId
            }
            let encoded = inputs.childProtocolInstanceEncodedReachedState
            switch stateId {
            case .deviceUidsReceived: self = .deviceUidsReceived(try DeviceUidsReceivedState(encoded))
            case .cancelled:          self = .cancelled
            case .serverQueryFailed:  self = .serverQueryFailed(ServerQueryFailedState(encoded))
            case .waitingForDeviceUids,
                    .initialState:
                assertionFailure()
                throw ObvError.stateIsNotFinalStateOfThisProtocol
            }
        }
        
        enum ObvError: Error {
            case stateIsNotFinalStateOfThisProtocol
            case unknownStateId
        }
        
    }
    
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
    
    static var allStepIds: [ConcreteProtocolStepId] {
        return StepId.allCases
    }

}

