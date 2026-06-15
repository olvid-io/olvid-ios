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
@preconcurrency import ObvEngine
import ObvAppCoreConstants
import OSLog
import ObvAppTypes
import ObvHistoryTransfer


final class HistoryTransferCoordinator: OlvidCoordinator {
    
    static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "HistoryTransferCoordinator")
    static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "HistoryTransferCoordinator")
    
    let obvEngine: ObvEngine
    let queueForComposedOperations: OperationQueue
    let queueForSyncHintsComputationOperation: OperationQueue
    let coordinatorsQueue: OperationQueue
    
    init(obvEngine: ObvEngine,
         coordinatorsQueue: OperationQueue,
         queueForComposedOperations: OperationQueue,
         queueForSyncHintsComputationOperation: OperationQueue) {
        self.obvEngine = obvEngine
        self.coordinatorsQueue = coordinatorsQueue
        self.queueForComposedOperations = queueForComposedOperations
        self.queueForSyncHintsComputationOperation = queueForSyncHintsComputationOperation
    }

}


// MARK: - Implementing ObvHistoryTransfer.DestinationTransferStepsActions

extension HistoryTransferCoordinator: ObvHistoryTransfer.DestinationTransferStepsActions {
    
    func historyTransferRequiresToStoreSourcesMessagesOnThisDestination(
        _ actor: ObvHistoryTransfer.DestinationTransferSteps,
        messagesToStore: [ObvAppTypes.ObvHistoryReceivedMessage]
    ) async throws -> (
        sha256ToRequestToSource: [Data : UInt64],
        sha256NotToBeRequestedToSource: Set<Data>
    ) {
        
        var sha256ToRequestToSource = [Data : UInt64]()
        var sha256NotToBeRequestedToSource = Set<Data>()
        
        for message in messagesToStore {
            let op1 = StoreHistoryTransferredMessageOperation(message: message)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await self.coordinatorsQueue.addAndAwaitOperation(composedOp)
            guard composedOp.isFinished && !composedOp.isCancelled else {
                assertionFailure()
                Self.logger.fault("Could not store transfered message")
                continue // In production, continue with the next message
            }
            sha256ToRequestToSource.merge(op1.sha256ToRequestToSource) { val1, _ in val1 }
            sha256NotToBeRequestedToSource.formUnion(op1.sha256NotToBeRequestedToSource)
        }
        
        return (sha256ToRequestToSource, sha256NotToBeRequestedToSource)
        
    }
    
    func historyTransferRequiresToStoreAttachmentOnThisDestination(_ actor: ObvHistoryTransfer.DestinationTransferSteps, sha256: Data, temporaryURLOfAttachment: URL) async throws {
        
        let op1 = StoreHistoryTransferredAttachmentOperation(sha256: sha256, temporaryURLOfAttachment: temporaryURLOfAttachment)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            Self.logger.fault("Could not store transfered message")
            return
        }

    }
        
}



// MARK: - Private helpers

extension HistoryTransferCoordinator {
        
}
