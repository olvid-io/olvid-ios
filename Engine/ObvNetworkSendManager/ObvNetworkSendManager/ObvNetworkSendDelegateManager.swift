/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvMetaManager
import OlvidUtils

/// As all managers, we expect this one to be uniquely instantiated (i.e., a singleton). The ObvNetworkSendManagerImplementation holds a strong reference to this manager. This manager holds a strong reference to:
/// - All coordinators (which are singleton)
/// - All delegate requirements of this framework (at this time, only one, conforming to `ObvCreateNSManagedObjectContextDelegate`).
/// This architecture ensures that all managers and coordinator do not leave the heap. All other references to these managers and coordinators (including this one) should be weak to avoid memory cycles.
final class ObvNetworkSendDelegateManager {

    let sharedContainerIdentifier: String
    let supportBackgroundFetch: Bool
    
    static let defaultLogSubsystem = "io.olvid.network.send"
    private(set) var logSubsystem = ObvNetworkSendDelegateManager.defaultLogSubsystem
    
    func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
    }
    
    let queueSharedAmongCoordinators = OperationQueue.createSerialQueue(name: "Queue shared among coordinators of ObvNetworkSendManagerImplementation", qualityOfService: .default)
    private let queueForComposedOperations = {
        let queue = OperationQueue()
        queue.name = "Queue for composed operations"
        queue.qualityOfService = .default
        return queue
    }()

    // MARK: Instance variables (internal delegates)
    
    let uploadMessageAndGetUidsDelegate: UploadMessageAndGetUidDelegate
    let networkSendFlowDelegate: NetworkSendFlowDelegate
    let uploadAttachmentChunksDelegate: UploadAttachmentChunksDelegate
    let tryToDeleteMessageAndAttachmentsDelegate: TryToDeleteMessageAndAttachmentsDelegate
    let batchUploadMessagesWithoutAttachmentDelegate: BatchUploadMessagesWithoutAttachmentDelegate

    // MARK: Instance variables (external delegates)

    var contextCreator: ObvCreateContextDelegate?
    var notificationDelegate: ObvNotificationDelegate?
    weak var channelDelegate: ObvChannelDelegate?
    var identityDelegate: ObvIdentityDelegate? // DEBUG 2022-03-15 Allows to keep a strong reference to the identity delegate, required when uploading large attachment within the share extension
    var simpleFlowDelegate: ObvSimpleFlowDelegate? // DEBUG 2019-10-17 Allows to keep a strong reference to the simpleFlowDelegate, required when uploading large attachment within the share extension

    // MARK: Initialiazer
    
    init(sharedContainerIdentifier: String, supportBackgroundFetch: Bool, networkSendFlowDelegate: NetworkSendFlowDelegate, uploadMessageAndGetUidsDelegate: UploadMessageAndGetUidDelegate, uploadAttachmentChunksDelegate: UploadAttachmentChunksDelegate, tryToDeleteMessageAndAttachmentsDelegate: TryToDeleteMessageAndAttachmentsDelegate, batchUploadMessagesWithoutAttachmentDelegate: BatchUploadMessagesWithoutAttachmentDelegate) {
        self.sharedContainerIdentifier = sharedContainerIdentifier
        self.supportBackgroundFetch = supportBackgroundFetch
        self.networkSendFlowDelegate = networkSendFlowDelegate
        self.uploadMessageAndGetUidsDelegate = uploadMessageAndGetUidsDelegate
        self.uploadAttachmentChunksDelegate = uploadAttachmentChunksDelegate
        self.tryToDeleteMessageAndAttachmentsDelegate = tryToDeleteMessageAndAttachmentsDelegate
        self.batchUploadMessagesWithoutAttachmentDelegate = batchUploadMessagesWithoutAttachmentDelegate
    }
    
}


// MARK: - Errors

extension ObvNetworkSendDelegateManager {
    
    enum ObvError: Error {
        case contextCreatorIsNil
        case composedOperationCancelled
    }
    
}


// MARK: - Helpers

extension ObvNetworkSendDelegateManager {
    
    func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>, log: OSLog, flowId: FlowIdentifier) throws -> CompositionOfOneContextualOperation<T> {
        
        guard let contextCreator else {
            assertionFailure("The context creator manager is not set")
            throw ObvError.contextCreatorIsNil
        }
        
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: contextCreator, queueForComposedOperations: queueForComposedOperations, log: log, flowId: flowId)
        
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: log)
        }
        return composedOp
        
    }
    
    func createCompositionOfTwoContextualOperation<T1: LocalizedErrorWithLogType, T2: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T1>, op2: ContextualOperationWithSpecificReasonForCancel<T2>, log: OSLog, flowId: FlowIdentifier) throws -> CompositionOfTwoContextualOperations<T1, T2> {
        
        guard let contextCreator else {
            assertionFailure("The context creator manager is not set")
            throw ObvError.contextCreatorIsNil
        }

        let composedOp = CompositionOfTwoContextualOperations(op1: op1, op2: op2, contextCreator: contextCreator, queueForComposedOperations: queueForComposedOperations, log: log, flowId: flowId)
        
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: log)
        }
        return composedOp
    }
    
    func queueAndAwaitCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>, log: OSLog, flowId: FlowIdentifier) async throws {
        
        let composedOp = try createCompositionOfOneContextualOperation(op1: op1, log: log, flowId: flowId)
        await queueSharedAmongCoordinators.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw ObvError.composedOperationCancelled
        }

    }
    
    func queueAndAwaitCompositionOfTwoContextualOperation<T1: LocalizedErrorWithLogType, T2: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T1>, op2: ContextualOperationWithSpecificReasonForCancel<T2>, log: OSLog, flowId: FlowIdentifier) async throws {
     
        let composedOp = try createCompositionOfTwoContextualOperation(op1: op1, op2: op2, log: log, flowId: flowId)
        await queueSharedAmongCoordinators.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw ObvError.composedOperationCancelled
        }

    }
    
}
