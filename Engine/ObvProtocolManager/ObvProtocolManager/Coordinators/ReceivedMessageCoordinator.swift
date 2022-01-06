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
    
    private func queueNewProtocolOperationIfThereIsNotAlreadyOne(receivedMessageId messageId: MessageIdentifier, flowId: FlowIdentifier) {
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
    
    func processReceivedMessage(withId messageId: MessageIdentifier, flowId: FlowIdentifier) {
        queueNewProtocolOperationIfThereIsNotAlreadyOne(receivedMessageId: messageId, flowId: flowId)
    }
    
    
    func abortProtocol(withProtocolInstanceUid uid: UID, forOwnedIdentity identity: ObvCryptoIdentity) {
        
        let abortProtocolBlock = createBlockForAbortingProtocol(withProtocolInstanceUid: uid, forOwnedIdentity: identity)
        let abortProtocolBlockOperation = BlockOperation(block: abortProtocolBlock)
        queueForProtocolOperations.addOperation(abortProtocolBlockOperation)
        
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
                    try ReceivedMessage.deleteAllAssociatedWithProtocolInstance(withUid: uid, within: obvContext)
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

final class ProtocolStepAndActionsOperationWrapper: ObvOperationWrapper<ProtocolOperation> {
    
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

            let idsOfOtherReceivedMessages: [MessageIdentifier]

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
                
                let NotificationType = ObvProtocolNotification.ProtocolMessageToProcess.self
                let userInfo = [NotificationType.Key.protocolMessageId: receivedMessage.messageId,
                                NotificationType.Key.flowId: operation.flowId] as [String: Any]
                notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                
            }
            
            
            try? obvContext.save(logOnFailure: log)

            // There may be other protocol messages waiting within the ReceivedMessage database that could not be processed at the time they were received. Now that the protocol instance is in a new state, we may be able to process them. We queue a new ProtocolOperation for each of these messages. We do this after saving the context, to ensure that the store protocol instance is indeed in a new state before queuing new Protocol Operations.
            
            
            // If there were other received messages to process, we already send the appropriate notifications. We can now notify that we processed the (now deleted) original received message
            
            let NotificationType = ObvProtocolNotification.ProtocolMessageProcessed.self
            let userInfo = [NotificationType.Key.protocolMessageId: operation.receivedMessageId,
                            NotificationType.Key.flowId: operation.flowId] as [String: Any]
            notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
            
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
        
        // Whatever the reason for cancel, we notify that the received message has been processed
        
        let NotificationType = ObvProtocolNotification.ProtocolMessageProcessed.self
        let userInfo = [NotificationType.Key.protocolMessageId: operation.receivedMessageId,
                        NotificationType.Key.flowId: operation.flowId] as [String: Any]
        notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)

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
                                                                         encodedElements: 0.encode())
                        _ = try? channelDelegate.post(deleteDialog, randomizedWith: operation.prng, within: obvContext)
                        obvContext.delete(message)
                    }
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not delete the received protocol message from database", log: log, type: .error)
                    return
                }
            }
            return
            
        case .couldNotConstructConcreteProtocolMessageForTheGivenCryptoProtocol,
             .theProtocolStepCancelled,
             .couldNotDetermineNewProtocolState,
             .couldNotUpdateProtocolState,
             .couldNotSaveContext,
             .couldNotDetermineTheAssociatedOwnedIdentity,
             .couldNotReconstructConcreteCryptoProtocol:
            // Delete the received protocol message
            let randomFlowId = FlowIdentifier()
            contextCreator.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
                do {
                    try ReceivedMessage.delete(messageId: operation.receivedMessageId, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not delete the received protocol message from database", log: log, type: .error)
                    return
                }
            }
        }
    }
}
