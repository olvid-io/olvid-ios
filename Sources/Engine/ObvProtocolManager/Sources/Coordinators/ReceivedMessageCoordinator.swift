/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvMetaManager
import ObvTypes
import ObvOperation
import ObvCrypto
import OlvidUtils

final class ReceivedMessageCoordinator: ReceivedMessageDelegate {
    
    // MARK: Instance variables
    
    fileprivate static let logCategory = "ReceivedMessageCoordinator"
    
    // Thanks to the initializer of the manager, we can safely force unwrap
    weak var delegateManager: ObvProtocolDelegateManager!
    
    private let prng: PRNGService
    
    private let queueForProtocolOperations: ObvOperationNoDuplicateQueue = {
        let q = ObvOperationNoDuplicateQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()
    
    // MARK: Initializer
    
    init(prng: PRNGService) {
        self.prng = prng
    }

    // MARK: Queuing ProtocolInstanceInputsConsumerOperations
    
    private func queueNewProtocolOperationIfThereIsNotAlreadyOne(receivedMessageId messageId: ObvMessageIdentifier, flowId: FlowIdentifier) {
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ReceivedMessageCoordinator.logCategory)
        os_log("Queuing a ProtocolOperation", log: log, type: .debug)
        let op = ProtocolOperation(receivedMessageId: messageId,
                                   flowId: flowId,
                                   delegateManager: delegateManager,
                                   prng: prng)
        let opWrapper = ProtocolStepAndActionsOperationWrapper(wrappedOperation: op) // The wrapper op has the same uid as the wrapped op
        queueForProtocolOperations.addOperation(opWrapper)
    }

}

// MARK: Implementing ProtocolInstanceInputsConsumerDelegate

extension ReceivedMessageCoordinator {
    
    func processReceivedMessage(withId messageId: ObvMessageIdentifier, flowId: FlowIdentifier) {
        queueNewProtocolOperationIfThereIsNotAlreadyOne(receivedMessageId: messageId, flowId: flowId)
    }
    
    
    func abortProtocol(withProtocolInstanceUid uid: UID, forOwnedIdentity identity: ObvCryptoIdentity) {
        
        let abortProtocolBlock = createBlockForAbortingProtocol(withProtocolInstanceUid: uid, forOwnedIdentity: identity)
        let abortProtocolBlockOperation = BlockOperation(block: abortProtocolBlock)
        queueForProtocolOperations.addOperation(abortProtocolBlockOperation)
        
    }
    
    
    /// This method is called during boostrap. It deletes old protocol instances that are in a final state. Normaly, no such instance should exist. It is only used in case a step was not declared as final by mistake, and later considered as final.
    /// We declare this method in this coordinator to make sure it does not interfere with the processing of protocol messages.
    func deleteProtocolInstancesInAFinalState(flowId: FlowIdentifier) {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ReceivedMessageCoordinator.logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        let op1 = DeleteProtocolInstancesInAFinalStateOperation()
        let queueForComposedOperations = OperationQueue.createSerialQueue()
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: contextCreator, queueForComposedOperations: queueForComposedOperations, log: log, flowId: flowId)
        queueForProtocolOperations.addOperation(composedOp)
        
    }
    
    
    /// This method is called during boostrap. It deletes all `CryptoProtocolId.ownedIdentityTransfer` protocol instances.
    /// We declare this method in this coordinator to make sure it does not interfere with the processing of protocol messages.
    func deleteOwnedIdentityTransferProtocolInstances(flowId: FlowIdentifier) {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ReceivedMessageCoordinator.logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        let op1 = DeleteOwnedIdentityTransferProtocolInstancesOperation()
        let queueForComposedOperations = OperationQueue.createSerialQueue()
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: contextCreator, queueForComposedOperations: queueForComposedOperations, log: log, flowId: flowId)
        queueForProtocolOperations.addOperation(composedOp)
        
    }
    
    
    /// This method is called during boostrap. It deletes all `ReceivedMessage` concerning a identity transfer protocol instance.
    /// We declare this method in this coordinator to make sure it does not interfere with the processing of protocol messages.
    func deleteReceivedMessagesConcerningAnOwnedIdentityTransferProtocol(flowId: FlowIdentifier) {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ReceivedMessageCoordinator.logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        let op1 = DeleteReceivedMessagesConcerningAnOwnedIdentityTransferProtocolOperation()
        let queueForComposedOperations = OperationQueue.createSerialQueue()
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: contextCreator, queueForComposedOperations: queueForComposedOperations, log: log, flowId: flowId)
        queueForProtocolOperations.addOperation(composedOp)

    }
    
    /// This method is called during boostrap. It deletes all received messages that are older than 15 days and that have no associated protocol instance.
    func deleteObsoleteReceivedMessages(flowId: FlowIdentifier) {

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ReceivedMessageCoordinator.logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        let op1 = DeleteObsoleteReceivedMessagesOperation(delegateManager: delegateManager)
        let queueForComposedOperations = OperationQueue.createSerialQueue()
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: contextCreator, queueForComposedOperations: queueForComposedOperations, log: log, flowId: flowId)
        queueForProtocolOperations.addOperation(composedOp)

    }
    
    
    /// This method is called during boostrap. It re-processes all `ReceivedMessages`.
    func processAllReceivedMessages(flowId: FlowIdentifier) {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ReceivedMessageCoordinator.logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        queueForProtocolOperations.addOperation { [weak self] in
            var messageIds = [ObvMessageIdentifier]()
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { obvContext in
                do {
                    messageIds = try ReceivedMessage.getAllMessageIds(within: obvContext)
                } catch {
                    assertionFailure()
                    os_log("Could not fetch all ReceivedMessage Ids", log: log, type: .fault)
                }
            }
            
            for messageId in messageIds {
                self?.processReceivedMessage(withId: messageId, flowId: flowId)
            }
        }
        
    }


    func createBlockForAbortingProtocol(withProtocolInstanceUid uid: UID, forOwnedIdentity identity: ObvCryptoIdentity) -> (() -> Void) {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ReceivedMessageCoordinator.logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            return {}
        }

        var blockEndingWithContextSave: (() -> Void)?
        let randomFlowId = FlowIdentifier()
        contextCreator.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            let block = createBlockForAbortingProtocol(withProtocolInstanceUid: uid, forOwnedIdentity: identity, within: obvContext)
            blockEndingWithContextSave = {
                obvContext.perform {
                    block()
                    try? obvContext.save(logOnFailure: log)
                }
            }
        }
        return blockEndingWithContextSave!
    }
    
    func createBlockForAbortingProtocol(withProtocolInstanceUid uid: UID, forOwnedIdentity identity: ObvCryptoIdentity, within obvContext: ObvContext) -> (() -> Void) {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ReceivedMessageCoordinator.logCategory)
        
        os_log("Returning a block allowing to abort protocol with uid %{public}@", log: log, type: .debug, uid.debugDescription)
        
        return { [weak self] in
            
            obvContext.performAndWait {
                
                os_log("Starting a block for aborting the protocol with instance uid %{public}@", log: log, type: .debug, uid.debugDescription)
                
                guard let delegateManager = self?.delegateManager else { return }
                
                debugPrint("Call to ProtocolInstance.delete...")
                
                // Delete the protocol instance
                do {
                    try ProtocolInstance.delete(uid: uid, ownedCryptoIdentity: identity, within: obvContext)
                } catch {
                    os_log("Could not delete protocol instance", log: log, type: .error)
                    return
                }
                
                // Delete the received messages of this protocol instance
                do {
                    try ReceivedMessage.deleteAllAssociatedWithProtocolInstance(withUid: uid, ownedIdentity: identity, within: obvContext)
                } catch {
                    os_log("Could not delete all the received messages associated to the protocol instance to abort", log: log, type: .error)
                    return
                }
                
                // Abort the childs of this protocol instance
                do {
                    let links: [LinkBetweenProtocolInstances]
                    do {
                        links = try LinkBetweenProtocolInstances.getAllLinksForWhichTheParentProtocolHasUid(uid, andOwnedIdentity: identity, delegateManager: delegateManager, within: obvContext)
                    } catch {
                        os_log("Could not get LinkBetweenProtocolInstances", log: log, type: .error)
                        return
                    }
                    let childProtocolInstanceUids = links.map { $0.childProtocolInstanceUid }
                    childProtocolInstanceUids.forEach {
                        let subBlock = self?.createBlockForAbortingProtocol(withProtocolInstanceUid: $0, forOwnedIdentity: identity, within: obvContext)
                        subBlock?() // We execute the sub block operation right away
                    }
                }
                
                // Abort the parent(s) of this protocol instance
                do {
                    let links: [LinkBetweenProtocolInstances]
                    do {
                        links = try LinkBetweenProtocolInstances.getAllLinksForWhichTheChildProtocolHasUid(uid, andOwnedIdentity: identity, delegateManager: delegateManager, within: obvContext)
                    } catch {
                        os_log("Could not get LinkBetweenProtocolInstances", log: log, type: .error)
                        return
                    }
                    let parentProtocolInstanceUids = links.map { $0.parentProtocolInstance.uid }
                    parentProtocolInstanceUids.forEach {
                        let subBlock = self?.createBlockForAbortingProtocol(withProtocolInstanceUid: $0, forOwnedIdentity: identity, within: obvContext)
                        subBlock?() // We execute the sub block operation right away
                    }
                }
            }
                        
        }
    }

}

// MARK: Wrapper for ProtocolStepAndActionsOperations

final class ProtocolStepAndActionsOperationWrapper: ObvOperationWrapper<ProtocolOperation>, @unchecked Sendable {
    
    override func wrapperOperationWillFinishAndWrappedOperationDidFinishWithoutCancelling(operation: ProtocolOperation) {
        
        guard let delegateManager = operation.delegateManager else {
            let log = OSLog(subsystem: ObvProtocolDelegateManager.defaultLogSubsystem, category: ReceivedMessageCoordinator.logCategory)
            os_log("The delegate manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ReceivedMessageCoordinator.logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let protocolInstanceUid = operation.protocolInstanceUid else {
            os_log("The Protocol Operation did not cancel but has no protocol instance uid", log: log, type: .fault)
            return
        }
        
        guard let protocolInstanceOwnedIdentity = operation.protocolInstanceOwnedIdentity else {
            os_log("The Protocol Operation did not cancel but has no protocol instance owned identity", log: log, type: .fault)
            return
        }
        
        
        let randomFlowId = FlowIdentifier()
        contextCreator.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in

            let idsOfOtherReceivedMessages: [ObvMessageIdentifier]

            guard let receivedMessages = ReceivedMessage.getAll(protocolInstanceUid: protocolInstanceUid,
                                                                ownedCryptoIdentity: protocolInstanceOwnedIdentity,
                                                                delegateManager: delegateManager,
                                                                within: obvContext)
                else {
                    os_log("Could not retrieve remaining protocol messages", log: log, type: .error)
                    return
            }
                        
            idsOfOtherReceivedMessages = receivedMessages.map { $0.messageId }
            
            
            // For each of these messages, we notify that we have a received message to process.
            
            receivedMessages.forEach { (receivedMessage) in
                
                os_log("We found an old received message with uid %{public}@ that we will re-process within flow %{public}@", log: log, type: .info, receivedMessage.messageId.debugDescription, operation.flowId.debugDescription)
                
                ObvProtocolNotification.protocolMessageToProcess(protocolMessageId: receivedMessage.messageId, flowId: operation.flowId)
                    .postOnBackgroundQueue(within: notificationDelegate)
                
            }
            
            
            try? obvContext.save(logOnFailure: log)

            // There may be other protocol messages waiting within the ReceivedMessage database that could not be processed at the time they were received. Now that the protocol instance is in a new state, we may be able to process them. We queue a new ProtocolOperation for each of these messages. We do this after saving the context, to ensure that the store protocol instance is indeed in a new state before queuing new Protocol Operations.
            
            
            // If there were other received messages to process, we already send the appropriate notifications. We can now notify that we processed the (now deleted) original received message
            
            ObvProtocolNotification.protocolMessageProcessed(protocolMessageId: operation.receivedMessageId, flowId: operation.flowId)
                .postOnBackgroundQueue(within: notificationDelegate)
            
            // Now we can try to process the other received messages
            
            idsOfOtherReceivedMessages.forEach { (receivedMessageId) in
                delegateManager.receivedMessageDelegate.processReceivedMessage(withId: receivedMessageId, flowId: operation.flowId)
            }

        }
        
    }
    
    override func wrapperOperationWillFinishAndWrappedOperationDidCancel(operation: ProtocolOperation) {
        
        guard let delegateManager = operation.delegateManager else {
            let log = OSLog(subsystem: ObvProtocolDelegateManager.defaultLogSubsystem, category: ReceivedMessageCoordinator.logCategory)
            os_log("The delegate manager is not set", log: log, type: .fault)
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ReceivedMessageCoordinator.logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        guard let channelDelegate = delegateManager.channelDelegate else {
            os_log("The channel delegate is not set", log: log, type: .fault)
            return

        }
        
        guard let reasonForCancel = operation.reasonForCancel else {
            os_log("A ProtocolOperation cancelled without a proper reason", log: log, type: .fault)
            return
        }
        os_log("ProtocolOperation cancelled for reason %{public}@", log: log, type: .error, reasonForCancel.description)
        
        // Unless the context failed to save, we notify that the received message has been processed
        
        switch reasonForCancel {
        case .couldNotSaveContext:
            break
        default:
            ObvProtocolNotification.protocolMessageProcessed(protocolMessageId: operation.receivedMessageId, flowId: operation.flowId)
                .postOnBackgroundQueue(within: notificationDelegate)
        }

        // Deal with the reason for cancel
        
        switch reasonForCancel {
            
        case .contextCreatorDelegateNotSet,
             .couldNotFindConcreteStepToExecute,
             .messageNotFoundInDatabase:
            break // Do nothing
            
        case .couldNotFindConcreteStepToExecuteForReceivedDialogResponse(uuid: let dialogUuid):
            // When a dialog response fails to execute a new protocol step, we post a "delete" dialog so as to make sure that the engine/app is notified that the dialog should be discarded. We also delete the corresponding received message.
            
            contextCreator.performBackgroundTaskAndWait(flowId: operation.flowId) { (obvContext) in
                do {
                    if let message = ReceivedMessage.get(messageId: operation.receivedMessageId,
                                                         delegateManager: delegateManager,
                                                         within: obvContext) {
                        let deleteDialog = ObvChannelDialogMessageToSend(uuid: dialogUuid,
                                                                         ownedIdentity: message.messageId.ownedCryptoIdentity,
                                                                         dialogType: ObvChannelDialogToSendType.delete,
                                                                         encodedElements: 0.obvEncode())
                        _ = try? channelDelegate.postChannelMessage(deleteDialog, randomizedWith: operation.prng, within: obvContext)
                        obvContext.delete(message)
                    }
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not delete the received protocol message from database", log: log, type: .error)
                    return
                }
            }
            return
            
        case .couldNotSaveContext, .couldNotDeleteReceivedMessage:
            assertionFailure()
            // We reprocess the message in 1 second
            DispatchQueue(label: "Queue for reprocessing a protocol message after a context save failure").asyncAfter(deadline: .now() + .seconds(1)) {
                let receivedMessageId = operation.receivedMessageId
                guard let delegateManager = operation.delegateManager else { assertionFailure(); return }
                delegateManager.receivedMessageDelegate.processReceivedMessage(withId: receivedMessageId, flowId: operation.flowId)
            }
            
        case .couldNotConstructConcreteProtocolMessageForTheGivenCryptoProtocol,
             .theProtocolStepCancelled,
             .couldNotDetermineNewProtocolState,
             .couldNotUpdateProtocolState,
             .couldNotDetermineTheAssociatedOwnedIdentity,
             .couldNotReconstructConcreteCryptoProtocol:
            // Delete the received protocol message
            let randomFlowId = FlowIdentifier()
            contextCreator.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
                do {
                    try ReceivedMessage.delete(messageId: operation.receivedMessageId, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not delete the received protocol message from database", log: log, type: .fault)
                    assertionFailure()
                    return
                }
            }
        }
    }
}


// MARK: - Syncronized execution of external operations

extension ReceivedMessageCoordinator {
    
    /// Allows to queue an operation on the queue on which protocol steps are executed.
    func executeOnQueueForProtocolOperations<ReasonForCancelType: LocalizedErrorWithLogType>(operation: OperationWithSpecificReasonForCancel<ReasonForCancelType>) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let originalCompletionBlock = operation.completionBlock
            operation.completionBlock = {
                originalCompletionBlock?()
                if let reasontForCancel = operation.reasonForCancel {
                    assert(operation.isCancelled)
                    continuation.resume(throwing: reasontForCancel)
                } else {
                    assert(!operation.isCancelled)
                    continuation.resume()
                }
            }
            queueForProtocolOperations.addOperation(operation)
        }
    }
    
}
