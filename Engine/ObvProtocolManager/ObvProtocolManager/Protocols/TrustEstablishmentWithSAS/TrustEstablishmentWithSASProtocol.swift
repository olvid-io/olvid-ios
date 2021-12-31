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
import ObvOperation
import ObvMetaManager
import OlvidUtils

/// This protocol corresponds to the 'Establish mutual trust with an untrusted identity protocol'
public struct TrustEstablishmentWithSASProtocol: ConcreteCryptoProtocol {
    
    static let logCategory = "TrustEstablishmentWithSASProtocol"
    
    static let id = CryptoProtocolId.TrustEstablishmentWithSAS
    
    var finalStateIds: [ConcreteProtocolStateId] = [StateId.Cancelled, StateId.MutualTrustConfirmed]
    
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
    
    static let allStepIds: [ConcreteProtocolStepId] = [StepId.SendCommitment,
                                                       StepId.StoreDecommitment,
                                                       StepId.ShowSasDialogAndSendDecommitment,
                                                       StepId.StoreAndPropagateCommitmentAndAskForConfirmation,
                                                       StepId.StoreCommitmentAndAskForConfirmation,
                                                       StepId.SendSeedAndPropagateConfirmation,
                                                       StepId.ReceiveConfirmationFromOtherDevice,
                                                       StepId.ShowSasDialog,
                                                       StepId.CheckSas,
                                                       StepId.CheckPropagatedSas,
                                                       StepId.NotifiedMutualTrustEstablishedLegacy,
                                                       StepId.AddTrust]
}


// MARK: - Helpers

extension TrustEstablishmentWithSASProtocol {
    
    static func decodeEncodedListOfDeviceUids(_ obvEncoded: ObvEncoded) throws -> [UID] {
        guard let listOfEncodedUids = [ObvEncoded](obvEncoded) else { throw NSError() }
        return try listOfEncodedUids.map { try $0.decode() }
    }
    
}
