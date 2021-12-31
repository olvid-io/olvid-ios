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
import os.log
import ObvCrypto
import ObvEncoder
import ObvTypes
import OlvidUtils

public struct FullRatchetProtocol: ConcreteCryptoProtocol {
    
    static let logCategory = "FullRatchetProtocol"
    
    static let id = CryptoProtocolId.FullRatchet
    
    private static let errorDomain = "FullRatchetProtocol"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    var finalStateIds: [ConcreteProtocolStateId] = [StateId.FullRatchetDone,
                                                    StateId.Cancelled]
    
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
    
    static let allStepIds: [ConcreteProtocolStepId] = [
        StepId.AliceSendEphemeralKey,
        StepId.AliceResendEphemeralKeyFromAliceWaitingForK1State,
        StepId.AliceResendEphemeralKeyFromAliceWaitingForAckState,
        StepId.BobSendEphemeralKeyAndK1FromInitialState,
        StepId.BobSendEphemeralKeyAndK1BobWaitingForK2State,
        StepId.AliceRecoverK1AndSendK2,
        StepId.BobRecoverK2ToUpdateReceiveSeedAndSendAck,
        StepId.AliceUpdateSendSeed,
    ]
    
    static func computeProtocolUid(aliceIdentity: ObvCryptoIdentity, bobIdentity: ObvCryptoIdentity, aliceDeviceUid: UID, bobDeviceUid: UID) throws -> UID {
        guard let seed1 = Seed(with: aliceIdentity.getIdentity()) else { throw makeError(message: "Could not compute protocol uid (seed1 error)") }
        guard let seed2 = Seed(with: bobIdentity.getIdentity()) else { throw makeError(message: "Could not compute protocol uid (seed2 error)") }
        guard let seed3 = Seed(with: aliceDeviceUid.raw) else { throw makeError(message: "Could not compute protocol uid (seed3 error)") }
        guard let seed4 = Seed(with: bobDeviceUid.raw) else { throw makeError(message: "Could not compute protocol uid (seed4 error)") }
        let seed = Seed(seeds: [seed1, seed2, seed3, seed4])
        let prng = ObvCryptoSuite.sharedInstance.concretePRNG().init(with: seed)
        return UID.gen(with: prng)
    }

}
