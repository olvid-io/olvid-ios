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
import os.log
import CoreData
import ObvOperation
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils

class ProtocolStep {
    
    let concreteCryptoProtocol: ConcreteCryptoProtocol
    var endState: ConcreteProtocolState? // Non nil if, and only if `executeStep()` returns a proper state, i.e., if the protocol step execution was correct
    var isCancelled = false
    var eraseReceivedMessagesAfterReachingAFinalState = true
    
    var obvContext: ObvContext {
        return concreteCryptoProtocol.obvContext
    }
    
    init?(expectedToIdentity: ObvCryptoIdentity, expectedReceptionChannelInfo: ObvProtocolReceptionChannelInfo, receivedMessage: ConcreteProtocolMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
        
        let log = OSLog(subsystem: concreteCryptoProtocol.delegateManager.logSubsystem, category: "ProtocolStepOperation")
        
        guard expectedToIdentity == receivedMessage.toOwnedIdentity else {
            os_log("Unexpected toIdentity", log: log, type: .error)
            return nil
        }
        guard let receivedMessageReceptionChannelInfo = receivedMessage.receptionChannelInfo else {
            os_log("The message's receptionChannelInfo is nil", log: log, type: .error)
            return nil
        }
        guard let identityDelegate = concreteCryptoProtocol.delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return nil
        }
        do {
            guard try expectedReceptionChannelInfo.accepts(receivedMessageReceptionChannelInfo, identityDelegate: identityDelegate, within: concreteCryptoProtocol.obvContext) else {
                os_log("Unexpected receptionChannelInfo (%{public}@ does not accept %{public}@)", log: log, type: .error, expectedReceptionChannelInfo.debugDescription, receivedMessageReceptionChannelInfo.debugDescription)
                assertionFailure()
                return nil
            }
        } catch {
            os_log("We could not check whether the expectedReceptionChannelInfo accepts the receivedMessageReceptionChannelInfo", log: log, type: .fault)
            return nil
        }
        
        self.concreteCryptoProtocol = concreteCryptoProtocol
    }
    
    
    final func execute() {
        var newState: ConcreteProtocolState?
        do {
            newState = try executeStep(within: obvContext)
        } catch {
            isCancelled = true
            return
        }
        if newState == nil {
            isCancelled = true
            endState = nil
        } else {
            endState = newState
        }
    }
    
    func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
        return nil // Must be overriden by subclass
    }
    
    func getCoreMessage(for channelType: ObvChannelSendChannelType, partOfFullRatchetProtocolOfTheSendSeed: Bool = false) -> CoreProtocolMessage {
        return CoreProtocolMessage(channelType: channelType,
                                   cryptoProtocolId: type(of: concreteCryptoProtocol).id,
                                   protocolInstanceUid: concreteCryptoProtocol.instanceUid,
                                   partOfFullRatchetProtocolOfTheSendSeed: partOfFullRatchetProtocolOfTheSendSeed)
    }
    
    func getCoreMessageForOtherLocalProtocol(otherCryptoProtocolId: CryptoProtocolId, otherProtocolInstanceUid: UID) -> CoreProtocolMessage {
        return CoreProtocolMessage(channelType: .Local(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                                   cryptoProtocolId: otherCryptoProtocolId,
                                   protocolInstanceUid: otherProtocolInstanceUid)
    }
}
