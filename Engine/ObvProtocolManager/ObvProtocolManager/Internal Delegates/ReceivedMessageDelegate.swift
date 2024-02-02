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
import ObvMetaManager
import OlvidUtils

protocol ReceivedMessageDelegate {
    
    func processReceivedMessage(withId: ObvMessageIdentifier, flowId: FlowIdentifier)
    func deleteObsoleteReceivedMessages(flowId: FlowIdentifier)
    func processAllReceivedMessages(flowId: FlowIdentifier)
    
    // Defining this here allows to perform the steps required to abort a protocol on the same queue than the one used to process a message.
    func abortProtocol(withProtocolInstanceUid: UID, forOwnedIdentity: ObvCryptoIdentity)
    func createBlockForAbortingProtocol(withProtocolInstanceUid uid: UID, forOwnedIdentity identity: ObvCryptoIdentity) -> (() -> Void)
    func createBlockForAbortingProtocol(withProtocolInstanceUid uid: UID, forOwnedIdentity identity: ObvCryptoIdentity, within obvContext: ObvContext) -> (() -> Void)
    func deleteOwnedIdentityTransferProtocolInstances(flowId: FlowIdentifier)
    func deleteReceivedMessagesConcerningAnOwnedIdentityTransferProtocol(flowId: FlowIdentifier)
    func deleteProtocolInstancesInAFinalState(flowId: FlowIdentifier)

    // Allow to execute external operations on the queue executing protocol steps
    func executeOnQueueForProtocolOperations<ReasonForCancelType: LocalizedErrorWithLogType>(operation: OperationWithSpecificReasonForCancel<ReasonForCancelType>) async throws

}
