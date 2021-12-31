/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

import ObvOperation
import ObvCrypto
import ObvTypes

protocol TypedConcreteProtocolStep: ConcreteProtocolStep {
    
    associatedtype StartConcreteProtocolStateType
    associatedtype ConcreteProtocolMessageType
    
    var startState: StartConcreteProtocolStateType { get }
    var receivedMessage: ConcreteProtocolMessageType { get }
    
    init?(startState: StartConcreteProtocolStateType, receivedMessage: ConcreteProtocolMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol)
}

extension TypedConcreteProtocolStep {
    
    init?(from concreteCryptoProtocol: ConcreteCryptoProtocol, and receivedMessage: ConcreteProtocolMessage) {
        guard let currentState = concreteCryptoProtocol.currentState as? StartConcreteProtocolStateType else {
            return nil
        }
        guard let receivedMessage = receivedMessage as? ConcreteProtocolMessageType else {
            return nil
        }
        self.init(startState: currentState, receivedMessage: receivedMessage, concreteCryptoProtocol: concreteCryptoProtocol)
    }
    
}

protocol ConcreteProtocolStep {
    
    init?(from: ConcreteCryptoProtocol, and: ConcreteProtocolMessage)
    
    var endState: ConcreteProtocolState? { get }

    var concreteCryptoProtocol: ConcreteCryptoProtocol { get }
    
    // The remaining requirements are implemented within the following extension
    var ownedIdentity: ObvCryptoIdentity { get }
    var delegateManager: ObvProtocolDelegateManager { get }
    var prng: PRNGService { get }
    var protocolInstanceUid: UID { get }
}

extension ConcreteProtocolStep {
    
    var ownedIdentity: ObvCryptoIdentity {
        return concreteCryptoProtocol.ownedIdentity
    }
    
    var delegateManager: ObvProtocolDelegateManager {
        return concreteCryptoProtocol.delegateManager
    }
    
    var prng: PRNGService {
        return concreteCryptoProtocol.prng
    }
        
    var protocolInstanceUid: UID {
        return concreteCryptoProtocol.instanceUid
    }
    
    var cryptoProtocolId: CryptoProtocolId {
        return type(of: concreteCryptoProtocol).id
    }
}

protocol ConcreteProtocolStepId {
    var rawValue: Int { get }
    func getConcreteProtocolStep(_: ConcreteCryptoProtocol, _: ConcreteProtocolMessage) -> ConcreteProtocolStep?
}
