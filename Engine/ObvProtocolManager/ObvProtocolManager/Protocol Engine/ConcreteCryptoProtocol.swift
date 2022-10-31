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
import OlvidUtils
import ObvCrypto
import ObvTypes

/// A concrete crypto protocol represents a typed cryptographic protocol in a well defined state.
protocol ConcreteCryptoProtocol: CustomStringConvertible {
    
    static var id: CryptoProtocolId { get }
    
    init(instanceUid: UID, currentState: ConcreteProtocolState, ownedCryptoIdentity: ObvCryptoIdentity, delegateManager: ObvProtocolDelegateManager, prng: PRNGService, within: ObvContext)
    
    static func stateId(fromRawValue rawValue: Int) -> ConcreteProtocolStateId?
    static func messageId(fromRawValue rawValue: Int) -> ConcreteProtocolMessageId?
    
    static var logCategory: String { get }

    var ownedIdentity: ObvCryptoIdentity { get }
    var prng: PRNGService { get }
    var obvContext: ObvContext { get }
    
    var currentState: ConcreteProtocolState { get }
    var finalStateIds: [ConcreteProtocolStateId] { get }
    var finalStateRawIds: [Int] { get }
    static var allStepIds: [ConcreteProtocolStepId] { get }
    
    var delegateManager: ObvProtocolDelegateManager { get }
    
    var instanceUid: UID { get } // The protocol instance uid
    
    // The following protocol requirement are implemented in the following protocol extension
    
    init?(protocolInstance: ProtocolInstance, prng: PRNGService)
    func getConcreteProtocolMessage(from: ReceivedMessage) -> ConcreteProtocolMessage?
    func getConcreteStepToExecute(message: ConcreteProtocolMessage) -> ConcreteProtocolStep?
    
    func reachesFinalState(with state: ConcreteProtocolState) -> Bool
    func reachedFinalState() -> Bool
    
    func transitionedTo(_: ConcreteProtocolState) -> ConcreteCryptoProtocol    
}


extension ConcreteCryptoProtocol {
    
    init?(protocolInstance: ProtocolInstance, prng: PRNGService) {
        guard let currentStateId = Self.stateId(fromRawValue: protocolInstance.currentStateRawId) else {
            return nil
        }
        guard let currentState = currentStateId.getConcreteProtocolState(fromEncodedState: protocolInstance.encodedCurrentState) else {
            return nil
        }
        guard let delegateManager = protocolInstance.delegateManager else {
            return nil
        }
        guard let obvContext = protocolInstance.obvContext else {
            return nil
        }
        self.init(instanceUid: protocolInstance.uid,
                  currentState: currentState,
                  ownedCryptoIdentity: protocolInstance.ownedCryptoIdentity,
                  delegateManager: delegateManager,
                  prng: prng,
                  within: obvContext)
    }
    
    var logCategory: String { Self.logCategory }

    func getConcreteProtocolMessage(from message: ReceivedMessage) -> ConcreteProtocolMessage? {
        guard let messageId = Self.messageId(fromRawValue: message.protocolMessageRawId) else {
            return nil
        }
        let concreteProtocolMessage = messageId.getConcreteProtocolMessage(with: message)
        return concreteProtocolMessage
    }
    
    func getConcreteStepToExecute(message: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
        var candidateSteps = [ConcreteProtocolStep]()
        for stepId in Self.allStepIds {
            if let step = stepId.getConcreteProtocolStep(self, message) {
                candidateSteps.append(step)
            }
        }
        guard candidateSteps.count == 1 else {
            return nil
        }
        return candidateSteps.first
    }
    
    var finalStateRawIds: [Int] {
        return finalStateIds.map { $0.rawValue }
    }
    
    func reachesFinalState(with state: ConcreteProtocolState) -> Bool {
        return finalStateRawIds.contains(state.rawId)
    }

    func reachedFinalState() -> Bool {
        return finalStateRawIds.contains(currentState.rawId)
    }
    
    func transitionedTo(_ newProtocolState: ConcreteProtocolState) -> ConcreteCryptoProtocol {
        return type(of: self).init(instanceUid: self.instanceUid,
                                   currentState: newProtocolState,
                                   ownedCryptoIdentity: self.ownedIdentity,
                                   delegateManager: self.delegateManager,
                                   prng: self.prng,
                                   within: self.obvContext)
    }
}

// MARK: Implementing CustomStringConvertible
extension ConcreteCryptoProtocol {
    public var description: String {
        return "\(Self.id.debugDescription)<instanceUid: \(instanceUid.debugDescription), ownedIdentity: \(ownedIdentity.debugDescription)> in \(currentState)"
    }
}
