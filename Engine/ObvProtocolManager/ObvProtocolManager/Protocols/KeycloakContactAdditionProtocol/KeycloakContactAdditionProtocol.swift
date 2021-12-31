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

public struct KeycloakContactAdditionProtocol: ConcreteCryptoProtocol {

    static let logCategory = "KeycloakContactAdditionProtocol"

    static let id = CryptoProtocolId.KeycloakContactAddition

    private static let errorDomain = "KeycloakContactAdditionProtocol"

    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    var finalStateIds: [ConcreteProtocolStateId] = [StateId.Finished]

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
        StepId.VerifyContactAndStartDeviceDiscovery,
        StepId.AddContactAndSendRequest,
        StepId.ProcessPropagatedContactAddition,
        StepId.ProcessReceivedKeycloakInvite,
        StepId.AddContactAndSendConfirmation,
        StepId.ProcessConfirmation
    ]

}
