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
import ObvTypes
import ObvCrypto
import OlvidUtils


public struct ContactMutualIntroductionProtocol: ConcreteCryptoProtocol, ObvErrorMaker {
    
    static let logCategory = "ContactMutualIntroductionProtocol"
    public static let errorDomain = "ContactMutualIntroductionProtocol"

    static let id = CryptoProtocolId.ContactMutualIntroduction
    
    static let finalStateIds: [ConcreteProtocolStateId] = [StateId.Cancelled,
                                                           StateId.ContactsIntroduced,
                                                           StateId.InvitationRejected,
                                                           StateId.MutualTrustEstablished]
    
    let ownedIdentity: ObvCryptoIdentity
    let currentState: ConcreteProtocolState
    
    let delegateManager: ObvProtocolDelegateManager
    let obvContext: ObvContext
    let prng: PRNGService
    let instanceUid: UID
    
    static func makeError(message: String) -> Error { NSError(domain: "ContactMutualIntroductionProtocol", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    
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
    
    static let allStepIds: [ConcreteProtocolStepId] = [StepId.IntroduceContacts,
                                                       StepId.CheckTrustLevelsAndShowDialog,
                                                       StepId.PropagateInviteResponse,
                                                       StepId.ProcessPropagatedInviteResponse,
                                                       StepId.PropagateNotificationAddTrustAndSendAck,
                                                       StepId.ProcessPropagatedNotificationAndAddTrust,
                                                       StepId.NotifyMutualTrustEstablished,
                                                       StepId.RecheckTrustLevelsAfterTrustLevelIncrease]

    
}

extension ContactMutualIntroductionProtocol {
    
    // A introduced identity is either "accepted" because it already is part of our contacts (case 0), because the trust we have in the mediator is high enough (case 1), or requires an intervention of the user (case 2). This value is essentially used to determine which dialogs to send to the user during the protocol.
    struct AcceptType {
        static let alreadyTrusted = 0
        static let automatic = 1
        static let manual = 2
    }
    
}
