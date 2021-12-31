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
import ObvServerInterface
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils


final class UploadAttachmentChunksCoordinator: NSObject {
    
    // MARK: - Instance variables
    
    fileprivate let defaultLogSubsystem = ObvNetworkSendDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "UploadAttachmentChunksCoordinator"
    private let currentAppType: AppType
    private let sharedContainerIdentifier: String
    private let outbox: URL
    private let internalQueueForHandlers = DispatchQueue(label: "Internal queue for handlers")
    private var _handlerForSessionIdentifier = [String: (() -> Void)]()
    
    var delegateManager: ObvNetworkSendDelegateManager?
    
    private let localQueue = DispatchQueue(label: "UploadAttachmentChunksCoordinatorQueue")
    
    /* We do not limit the number of concurrent operations in the queue.
     * If we did, we would have to wait for one upload to be over before starting sending the next one.
     * This would be acceptable within the app, but not within the share extensions that waits until
     * all attachments have been taken care of before dismissing.
     * Well, we limit the maxConcurrentOperationCount to 4. In practice, this seems
     * acceptable in terms of memory footprint wrt the share extension. Not limiting leads
     * to crashes of the share extension due to the memory footprint.
     */
    private var internalOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Queue for UploadAttachmentChunksCoordinator operations"
        queue.maxConcurrentOperationCount = 4
        return queue
    }()
    
    init(appType: AppType, sharedContainerIdentifier: String, outbox: URL) {
        self.currentAppType = appType
        self.sharedContainerIdentifier = sharedContainerIdentifier
        self.outbox = outbox
        super.init()
    }
    
    
    private func removeHandlerForIdentifier(_ identifier: String) -> (() -> Void)? {
        var handler: (() -> Void)?
        internalQueueForHandlers.sync {
            handler = _handlerForSessionIdentifier.removeValue(forKey: identifier)
        }
        return handler
    }
    
    private func setHandlerForIdentifier(_ identifier: String, handler: @escaping () -> Void) {
        internalQueueForHandlers.sync {
            _handlerForSessionIdentifier[identifier] = handler
        }
    }
    
    
    // Dealing with attachment upload progress
    
    private var _attachmentsProgresses = [AttachmentIdentifier: AttachmentProgress]()
    private let queueForAttachmentsProgresses = DispatchQueue(label: "Internal queue for attachments progresses", qos: .utility)

    
    private let queueForCurrentURLSessions = DispatchQueue(label: "Internal queue for _currentURLSessions", qos: .utility)
    private var _currentURLSessions = [WeakRef<URLSession>]()
    private func cleanCurrentURLSessions() {
        _currentURLSessions = _currentURLSessions.filter({ $0.value != nil })
    }
    private func addCurrentURLSession(_ urlSession: URLSession) {
        queueForCurrentURLSessions.sync {
            cleanCurrentURLSessions()
            _currentURLSessions.append(WeakRef(to: urlSession))
        }
    }
    private func currentURLSessionExists(withIdentifier identifier: String) -> Bool {
        var res = false
        queueForCurrentURLSessions.sync {
            cleanCurrentURLSessions()
            res = _currentURLSessions.compactMap({ $0.value }).filter({ $0.configuration.identifier == identifier }).first != nil
        }
        return res
    }
    private func findURLSession(withIdentifier sessionIdentifier: String) -> URLSession? {
        var res: URLSession? = nil
        queueForCurrentURLSessions.sync {
            res = _currentURLSessions.compactMap({ $0.value }).filter({ $0.configuration.identifier == sessionIdentifier }).first
        }
        return res
    }
    private func removeURLSession(withIdentifier sessionIdentifier: String) {
        queueForCurrentURLSessions.sync {
            cleanCurrentURLSessions()
            _currentURLSessions.removeAll(where: { $0.value?.configuration.identifier == sessionIdentifier })
        }
    }

    // Calls must be in sync with localQueue
    private var _stillUploadingCancelledAttachments = [MessageIdentifier: [AttachmentIdentifier]]()
    private func addStillUploadingCancelledAttachmentsOfMessage(_ message: OutboxMessage) {
        _stillUploadingCancelledAttachments[message.messageId] = message.attachments.filter({ !$0.acknowledged }).map({ $0.attachmentId })
    }
    /// This method removes the attachmentIds from the list of still uploading attachments of the message.
    private func removeStillUploadingCancelledAttachments(attachmentId: AttachmentIdentifier) {
        guard var remaining = _stillUploadingCancelledAttachments[attachmentId.messageId] else { return }
        remaining.removeAll(where: { $0 == attachmentId })
        if remaining.isEmpty {
            _stillUploadingCancelledAttachments.removeValue(forKey: attachmentId.messageId)
        } else {
            _stillUploadingCancelledAttachments[attachmentId.messageId] = remaining
        }
    }
    private func noMoreStillUploadingAttachments(messageId: MessageIdentifier) -> Bool {
        !_stillUploadingCancelledAttachments.keys.contains(messageId)
    }
    
    // This array tracks the attachment identifiers that are currently refreshing their signed URLs, so as to prevent an infinite loop of refresh
    private var _attachmentIdsRefreshingSignedURLs = Set<AttachmentIdentifier>()
    private let queueForAttachmentIdsRefreshingSignedURLs = DispatchQueue(label: "Queue for sync access to _attachmentIdsRefreshingSignedURLs")
    private func attachmentStartsToRefreshSignedURLs(attachmentId: AttachmentIdentifier) {
        queueForAttachmentIdsRefreshingSignedURLs.sync {
            _ = _attachmentIdsRefreshingSignedURLs.insert(attachmentId)
        }
    }
    private func attachmentStoppedToRefreshSignedURLs(attachmentId: AttachmentIdentifier) {
        queueForAttachmentIdsRefreshingSignedURLs.sync {
            _ = _attachmentIdsRefreshingSignedURLs.remove(attachmentId)
        }
    }
    private func attachmentIsAlreadyRefreshingSignedURLs(attachmentId: AttachmentIdentifier) -> Bool {
        var val = false
        queueForAttachmentIdsRefreshingSignedURLs.sync {
            val = _attachmentIdsRefreshingSignedURLs.contains(attachmentId)
        }
        return val
    }

}


// MARK: - UploadAttachmentChunksDelegate

extension UploadAttachmentChunksCoordinator: UploadAttachmentChunksDelegate {

    
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool {
        return backgroundURLSessionIdentifier.isBackgroundURLSessionIdentifierForUploadingAttachment()
    }
    
    
    func processAllAttachmentsOfMessage(messageId: MessageIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        var attachmentsRequiringSignedURLs = [AttachmentIdentifier]()
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in

            guard let message = try? OutboxMessage.get(messageId: messageId, delegateManager: delegateManager, within: obvContext) else {
                os_log("Could not find message in DB", log: log, type: .fault)
                return
            }
            
            attachmentsRequiringSignedURLs = message.attachments.filter({ !$0.allChunksHaveSignedUrls && !$0.cancelExternallyRequested }).map({ $0.attachmentId })
            
        }
        
        // The attachments requiring signed URLs are dealt with now.
        downloadSignedURLsForAttachments(attachmentIds: attachmentsRequiringSignedURLs, flowId: flowId)
        // There might be attachments with signed URLs already. We upload them now.
        resumeMissingAttachmentUploads(flowId: flowId)

    }
       
    /// This is method is called prior `resumeMissingAttachmentUploads` and allows to download signed URLs for
    /// all the attachment's chunks. It is also called when something goes wrong with previously downloaded URLs (like
    /// when they expire).
    ///
    /// We queue an operation that will delete all the signed URLs
    /// of the attachment, then an operation that resume a download task that gets signed URLs from the server.
    /// We do so after adding a barrier to the queue, so as to make sure not to interfere with other tasks.
    func downloadSignedURLsForAttachments(attachmentIds: [AttachmentIdentifier], flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        localQueue.sync {
            
            var operationsToQueue = [Operation]()

            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
                for attachmentId in attachmentIds {
                    guard !attachmentIsAlreadyRefreshingSignedURLs(attachmentId: attachmentId) else { continue }
                    attachmentStartsToRefreshSignedURLs(attachmentId: attachmentId)
                    let ops = getOperationsForDownloadingSignedURLsForAttachment(attachmentId: attachmentId,
                                                                                 logSubsystem: delegateManager.logSubsystem,
                                                                                 obvContext: obvContext,
                                                                                 identityDelegate: identityDelegate,
                                                                                 appType: currentAppType)
                    
                    operationsToQueue.append(contentsOf: ops)
                }
                
            }
            
            // We prevent any interference with previous operations
            if #available(iOS 13, *) {
                internalOperationQueue.addBarrierBlock({})
            } else {
                internalOperationQueue.waitUntilAllOperationsAreFinished()
            }
            internalOperationQueue.addOperations(operationsToQueue, waitUntilFinished: false)

        }
        
    }
    

    /// This method is called whenever there might be one (or more) attachment ready to be uploaded.
    func resumeMissingAttachmentUploads(flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        localQueue.sync {
                        
            var operationsToQueue = [Operation]()
            
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                
                let attachmentsToResume: [OutboxAttachment]
                do {
                    attachmentsToResume = try OutboxAttachment.getAllUploadableWithoutSession(within: obvContext)
                } catch {
                    os_log("Could not get attachments to upload", log: log, type: .fault)
                    return
                }

                guard !attachmentsToResume.isEmpty else {
                    os_log("There is no resumable attachment left", log: log, type: .info)
                    return
                }
                
                os_log("👑 We found %{public}d attachment(s) to resume.", log: log, type: .info, attachmentsToResume.count)

                attachmentsToResume.forEach {
                    os_log("👑 Attachment %{public}@ has a total of %{public}d chunk(s), and %{public}d still need to be uploaded", log: log, type: .info, $0.attachmentId.debugDescription, $0.chunks.count, $0.chunks.filter({ !$0.isAcknowledged }).count)
                    let ops = getOperationsForResumingAttachment($0, flowId: flowId, logSubsystem: delegateManager.logSubsystem, notificationDelegate: notificationDelegate, contextCreator: contextCreator, identityDelegate: identityDelegate)
                    os_log("👑 We created %{public}d operations in order to upload Attachment %{public}@", log: log, type: .info, ops.count, $0.attachmentId.debugDescription)
                    operationsToQueue.append(contentsOf: ops)
                }
                                
            }
            
            // We prevent any interference with previous operations
            if #available(iOS 13, *) {
                internalOperationQueue.addBarrierBlock({})
            } else {
                internalOperationQueue.waitUntilAllOperationsAreFinished()
            }
            /* Waiting for the operation to be finished is important:
             * - Waiting for ReCreateURLSessionWithNewDelegateForAttachmentUploadOperation to be finished is important since it is the existence
             *   of the session for a given attachment that allows to decide whether it shall be resumed or not
             * - Waiting for the tasks to be passed to the system is important especially in the background. Failing to do so would lead to
             *   an "early" call of the completion handler that would prevent the resume of missing tasks for an upload
             */
            internalOperationQueue.addOperations(operationsToQueue, waitUntilFinished: true)
            
        } /* end of localQueue.sync */
                
    }

    
    func processCompletionHandler(_ handler: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier identifier: String, withinFlowId flowId: FlowIdentifier) {
        assert(currentAppType == .mainApp)
        guard currentAppType == .mainApp else { assertionFailure(); return }
                
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            DispatchQueue.main.async { handler() }
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            DispatchQueue.main.async { handler() }
            assertionFailure()
            return
        }

        // Store the completion handler
        setHandlerForIdentifier(identifier, handler: handler)

        localQueue.sync {

            /* Look for an existing URLSession for the given identifier. If one exists, there is noting left to do:
             * We simply wait until all the events have been delivered to the delegate. When this is done,
             * the urlSessionDidFinishEvents(forBackgroundURLSession:) method of the delegate will be called, calling the
             * urlSessionDidFinishEventsForSessionWithIdentifier(_: String) of this coordinator, which will call the stored completion handler.
             */
            guard !currentURLSessionExists(withIdentifier: identifier) else {
                return
            }

            
            let operation = RecreatingURLSessionForCallingUIKitCompletionHandlerOperation(urlSessionIdentifier: identifier,
                                                                                          appType: currentAppType,
                                                                                          sharedContainerIdentifier: sharedContainerIdentifier,
                                                                                          logSubsystem: delegateManager.logSubsystem,
                                                                                          flowId: flowId,
                                                                                          contextCreator: contextCreator,
                                                                                          attachmentChunkUploadProgressTracker: self)
            if #available(iOS 13, *) {
                internalOperationQueue.addBarrierBlock({})
            } else {
                internalOperationQueue.waitUntilAllOperationsAreFinished()
            }
            internalOperationQueue.addOperation(operation)

        } /* end of localQueue.sync */

    }
    
    /// This method looks for `OutboxAttachmentSession` objects created by the specified `creatorAppType`. The objective is to "takover" these sessions.
    /// More precisely: this method creates one operation per object. This operation does the following *before* finishing :
    /// - It recreates the `URLSession`
    /// - It lists all the tasks, looks for the finished ones, and acknoledges the corresponding chunks
    /// - It invalidates the `URLSession` and cancels all the tasks
    /// - It deletes the `OutboxAttachmentSession` object.
    func cleanExistingOutboxAttachmentSessionsCreatedBy(_ creatorAppType: AppType, flowId: FlowIdentifier) {
        assert(currentAppType == .mainApp)
        guard currentAppType == .mainApp else { return }

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        let internalOperationQueue = self.internalOperationQueue
        let sharedContainerIdentifier = self.sharedContainerIdentifier
        
        localQueue.async {
            
            var attachmentIds = [AttachmentIdentifier]()
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                let outboxAttachmentSessions: [OutboxAttachmentSession]
                do {
                    outboxAttachmentSessions = try OutboxAttachmentSession.getAllCreatedByAppType(creatorAppType, within: obvContext)
                } catch {
                    os_log("Could not get attachments", log: log, type: .fault)
                    return
                }
                attachmentIds = outboxAttachmentSessions.compactMap({ $0.attachment?.attachmentId })
            }
            guard !attachmentIds.isEmpty else { return }
            
            let operationsToQueue: [Operation] = attachmentIds.map { (attachmentId) in
                ManuallyAcknowledgeChunksThenInvalidateAndCancelAndDeleteOutboxAttachmentSessionOperation(attachmentId: attachmentId,
                                                                                                          logSubsystem: delegateManager.logSubsystem,
                                                                                                          contextCreator: contextCreator,
                                                                                                          flowId: flowId,
                                                                                                          sharedContainerIdentifier: sharedContainerIdentifier)
            }

            if #available(iOS 13, *) {
                internalOperationQueue.addBarrierBlock({})
            } else {
                internalOperationQueue.waitUntilAllOperationsAreFinished()
            }
            internalOperationQueue.addOperations(operationsToQueue, waitUntilFinished: true)
            
        }
        
    }
    
    
    func requestProgressOfAttachment(withIdentifier attachmentId: AttachmentIdentifier) -> Progress? {
        var attachmentProgress: Progress?
        queueForAttachmentsProgresses.sync {
            attachmentProgress = _attachmentsProgresses[attachmentId]
        }
        return attachmentProgress
    }
    
    
    func queryServerOnSessionsTasksCreatedByShareExtension(flowId: FlowIdentifier) {

        guard currentAppType == .mainApp else { return }
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let opToQueue = QueryServerForAttachmentsProgressesSentByShareExtensionOperation(flowId: flowId, tracker: self, delegateManager: delegateManager)
        
        let internalOperationQueue = self.internalOperationQueue

        localQueue.async {

            if #available(iOS 13, *) {
                internalOperationQueue.addBarrierBlock({})
            } else {
                internalOperationQueue.waitUntilAllOperationsAreFinished()
            }
            
            opToQueue.completionBlock = {
                guard opToQueue.reasonForCancel == nil else {
                    return
                }
                DispatchQueue(label: "Queue for ").asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
                    self?.queryServerOnSessionsTasksCreatedByShareExtension(flowId: flowId)
                }
            }
            
            internalOperationQueue.addOperations([opToQueue], waitUntilFinished: false)

        }
        
    }
    
    
    func cancelAllAttachmentsUploadOfMessage(messageId: MessageIdentifier, flowId: FlowIdentifier) throws {
        
        assert(currentAppType == .mainApp)
        guard currentAppType == .mainApp else { return }

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        try localQueue.sync {
            
            try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
                
                guard let message = try OutboxMessage.get(messageId: messageId, delegateManager: delegateManager, within: obvContext) else {
                    // No attachment upload to cancel
                    return
                }
                
                guard !message.attachments.isEmpty else {
                    // No attachment upload to cancel
                    return
                }
                
                // We add an item to the dictionary keeping track of the attachmnent ids that are cancelled.
                // Later, we remove these attachment ids one by one, each time the URLSession uploading the attachment becomes invalid.
                // Once all the attachments will be gone, we will try to delete that message and its attachments.
                addStillUploadingCancelledAttachmentsOfMessage(message)
                
                // We prevent any interference with previous operations
                if #available(iOS 13, *) {
                    internalOperationQueue.addBarrierBlock({})
                } else {
                    internalOperationQueue.waitUntilAllOperationsAreFinished()
                }

                for attachment in message.attachments {
                    let op1 = MarkAttachmentAsCancelledOperation(attachmentId: attachment.attachmentId, logSubsystem: delegateManager.logSubsystem, contextCreator: contextCreator, flowId: flowId)
                    internalOperationQueue.addOperation(op1)
                    if let session = attachment.session, let urlSession = findURLSession(withIdentifier: session.sessionIdentifier) {
                        let op2 = CancelAllTasksAndInvalidateURLSessionOperation(urlSession: urlSession)
                        op2.addDependency(op1)
                        internalOperationQueue.addOperation(op2)
                        op2.waitUntilFinished()
                        let op3 = DeleteOutboxAttachmentSessionOperation(attachmentId: attachment.attachmentId, logSubsystem: delegateManager.logSubsystem, contextCreator: contextCreator, flowId: flowId)
                        op3.addDependency(op2)
                        internalOperationQueue.addOperation(op3)
                    }
                }

                internalOperationQueue.waitUntilAllOperationsAreFinished()
                                
            }
            
        } /* end localQueue.sync */

    }
}


// MARK: - Helpers

extension UploadAttachmentChunksCoordinator {
    
    private func getOperationsForResumingAttachment(_ attachment: OutboxAttachment, flowId: FlowIdentifier, logSubsystem: String, notificationDelegate: ObvNotificationDelegate, contextCreator: ObvCreateContextDelegate, identityDelegate: ObvIdentityDelegate) -> [Operation] {
        
        var operations = [Operation]()
        
        // Create the operations and set the dependencies
        
        let firstOp = ReCreateURLSessionWithNewDelegateForAttachmentUploadOperation(attachmentId: attachment.attachmentId,
                                                                                    appType: currentAppType,
                                                                                    sharedContainerIdentifier: sharedContainerIdentifier,
                                                                                    logSubsystem: logSubsystem,
                                                                                    flowId: flowId,
                                                                                    contextCreator: contextCreator,
                                                                                    attachmentChunkUploadProgressTracker: self)
        operations.append(firstOp)
                
        let otherOps: [(EncryptAttachmentChunkOperation, ResumeEncryptedChunkUploadTaskIfRequiredOperation)] = attachment.chunks.filter({ !$0.isAcknowledged }).map {
            let op1 = EncryptAttachmentChunkOperation(attachmentId: attachment.attachmentId, chunkNumber: $0.chunkNumber, outbox: outbox, logSubsystem: logSubsystem, flowId: flowId, contextCreator: contextCreator)
            let op2 = ResumeEncryptedChunkUploadTaskIfRequiredOperation(logSubsystem: logSubsystem, flowId: flowId, contextCreator: contextCreator, identityDelegate: identityDelegate)
            op2.addDependency(op1)
            op2.addDependency(firstOp)
            return (op1, op2)
        }
        let operationsToAppend: [(EncryptAttachmentChunkOperation, ResumeEncryptedChunkUploadTaskIfRequiredOperation)]
        if !otherOps.isEmpty {
            // In case the current app is, e.g., the share extension, we only keep one upload task.
            // This gives a chance to the main app to get called when the upload task is done.
            operationsToAppend = currentAppType == .mainApp ? otherOps : [(EncryptAttachmentChunkOperation, ResumeEncryptedChunkUploadTaskIfRequiredOperation)](otherOps[0..<min(10, otherOps.count)])
            operations.append(contentsOf: operationsToAppend.map({ $0.0 }))
            operations.append(contentsOf: operationsToAppend.map({ $0.1 }))
        } else {
            operationsToAppend = []
        }

        let finalOp = FinalizePostAttachmentUploadRequestOperation(attachmentId: attachment.attachmentId, flowId: flowId, logSubsystem: logSubsystem, notificationDelegate: notificationDelegate, delegate: self)
        finalOp.addDependency(firstOp)
        for other in operationsToAppend {
            finalOp.addDependency(other.0)
            finalOp.addDependency(other.1)
        }
        operations.append(finalOp)
        
        // Set the priorities
        
        let queuePriority = attachment.getAppropriateOperationQueuePriority()
        operations.forEach({ $0.queuePriority = queuePriority })
        
        return operations
        
    }

    
    private func getOperationsForDownloadingSignedURLsForAttachment(attachmentId: AttachmentIdentifier, logSubsystem: String, obvContext: ObvContext, identityDelegate: ObvIdentityDelegate, appType: AppType) -> [Operation] {
        
        var operations = [Operation]()

        let firstOp = DeletePreviousAttachmentSignedURLsOperation(attachmentId: attachmentId, logSubsystem: logSubsystem, obvContext: obvContext)
        let secondOp = ResumeTaskForGettingAttachmentSignedURLsOperation(attachmentId: attachmentId, logSubsystem: logSubsystem, obvContext: obvContext, identityDelegate: identityDelegate, attachmentChunksSignedURLsTracker: self, appType: appType, delegate: self)
        
        secondOp.addDependency(firstOp)
        
        operations.append(firstOp)
        operations.append(secondOp)

        return operations
    }
    
}


// MARK: - Implementing AttachmentChunksSignedURLsTracker

extension UploadAttachmentChunksCoordinator: AttachmentChunksSignedURLsTracker {
    
    
    func getSignedURLsSessionDidBecomeInvalid(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier, error: GetSignedURLsSessionDelegate.ErrorForTracker?) {
        
        defer {
            attachmentStoppedToRefreshSignedURLs(attachmentId: attachmentId)
        }

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let error = error else {
            self.resumeMissingAttachmentUploads(flowId: flowId)
            return
        }
    
        // If we reach this point, something went wrong while downloading the signed URLs
        
        switch error {
        case .aTaskDidBecomeInvalidWithError(error: _),
             .couldNotSaveContext,
             .couldNotParseServerResponse,
             .generalErrorFromServer,
             .sessionInvalidationError(error: _):
            delegateManager.networkSendFlowDelegate.signedURLsDownloadFailedForAttachment(attachmentId: attachmentId, flowId: flowId)
        case .cannotFindAttachmentInDatabase:
            // We do nothing
            break
        case .attachmentWasDeletedFromServerSoWeDidSetItAsAcknowledged:
            delegateManager.networkSendFlowDelegate.acknowledgedAttachment(attachmentId: attachmentId, flowId: flowId)
        }
        
    }
            
}


// MARK: - Implementing AttachmentChunkUploadProgressTracker

extension UploadAttachmentChunksCoordinator: AttachmentChunkUploadProgressTracker {

    func attachmentChunkDidProgress(attachmentId: AttachmentIdentifier, chunksProgresses: [(chunkNumber: Int, totalBytesSent: Int64, totalBytesExpectedToSend: Int64)], flowId: FlowIdentifier) {
        
        guard currentAppType == .mainApp else { return }
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        queueForAttachmentsProgresses.async { [weak self] in
            
            guard let _self = self else { return }
            
            let attachmentProgress: AttachmentProgress
            let newAttachmentProgress: Bool
            if let _progress = _self._attachmentsProgresses[attachmentId] {
                attachmentProgress = _progress
                newAttachmentProgress = false
            } else {
                guard let _progress = _self.createAttachmentProgress(attachmentId: attachmentId, contextCreator: contextCreator, flowId: flowId) else { return }
                _self._attachmentsProgresses[attachmentId] = _progress
                attachmentProgress = _progress
                newAttachmentProgress = true
            }

            for chunkProgress in chunksProgresses {
                attachmentProgress.set(totalBytesSent: chunkProgress.totalBytesSent, forChunkNumber: chunkProgress.chunkNumber)
            }
            
            
            if newAttachmentProgress {
                delegateManager.networkSendFlowDelegate.newProgressForAttachment(attachmentId: attachmentId, newProgress: attachmentProgress, flowId: flowId)
            }
            
        }
        
        
    }
    
    
    func attachmentChunksAreAcknowledged(attachmentId: AttachmentIdentifier, chunkNumbers: [Int], flowId: FlowIdentifier) {
        
        guard currentAppType == .mainApp else { return }

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        queueForAttachmentsProgresses.async { [weak self] in
            
            guard let _self = self else { return }
            
            let attachmentProgress: AttachmentProgress
            let newAttachmentProgress: Bool
            if let _progress = _self._attachmentsProgresses[attachmentId] {
                attachmentProgress = _progress
                newAttachmentProgress = false
            } else {
                guard let _progress = _self.createAttachmentProgress(attachmentId: attachmentId, contextCreator: contextCreator, flowId: flowId) else { return }
                _self._attachmentsProgresses[attachmentId] = _progress
                attachmentProgress = _progress
                newAttachmentProgress = true
            }

            for chunkNumber in chunkNumbers {
                attachmentProgress.acknowledgeChunk(number: chunkNumber)
            }
            
            if newAttachmentProgress {
                delegateManager.networkSendFlowDelegate.newProgressForAttachment(attachmentId: attachmentId, newProgress: attachmentProgress, flowId: flowId)
            }
            
        }

    }
    
    
    
    private func createAttachmentProgress(attachmentId: AttachmentIdentifier, contextCreator: ObvCreateContextDelegate, flowId: FlowIdentifier) -> AttachmentProgress? {
        /// Must be executed on queueForAttachmentsProgresses
        assert(currentAppType == .mainApp)
        var attachmentProgress: AttachmentProgress?
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            guard let attachment = OutboxAttachment.get(attachmentId: attachmentId, within: obvContext) else { return }
            let currentChunkProgresses = attachment.currentChunkProgresses
            attachmentProgress = AttachmentProgress(currentChunkProgresses: currentChunkProgresses)
        }
        return attachmentProgress
    }
    
    
    func uploadAttachmentChunksSessionDidBecomeInvalid(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier, error: UploadAttachmentChunksSessionDelegate.ErrorForTracker?) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        // Check whether the attachment is acknowledged and delete the session
        
        var attachmentIsAcknowledged = false
        var attachmentCancelExternallyRequested = false
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            guard let attachment = OutboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                os_log("Could not find attachment in database. We assume it was acknowledged (this sometimes happens when calling the completion handler received from UIKit)", log: log, type: .info)
                attachmentIsAcknowledged = true
                return
            }
            attachmentIsAcknowledged = attachment.acknowledged
            attachmentCancelExternallyRequested = attachment.cancelExternallyRequested
            if let attachmentSession = attachment.session {
                removeURLSession(withIdentifier: attachmentSession.sessionIdentifier)
                let op = DeleteOutboxAttachmentSessionOperation(attachmentId: attachmentId, logSubsystem: delegateManager.logSubsystem, contextCreator: contextCreator, flowId: flowId)
                internalOperationQueue.addOperations([op], waitUntilFinished: true)
                op.logReasonIfCancelled(log: log)
            }
        }
        
        // If the attachment is acknowledged, there is nothing left to do
        
        guard !attachmentIsAcknowledged else {
            delegateManager.networkSendFlowDelegate.acknowledgedAttachment(attachmentId: attachmentId, flowId: flowId)
            return
        }
        
        /* If the attachment is cancelled was externally requested, it is certainly within the list of the attachments that are cancelled
         * but still uploading. If this list is empty at that point, it means there is no more attachment to wait for and we can safely
         * call the flow delegate so as to delete the cancelled message and its attachments
         */
        guard !attachmentCancelExternallyRequested else {
            var shouldTryToDeleteMessageAndAttachments = false
            localQueue.sync {
                removeStillUploadingCancelledAttachments(attachmentId: attachmentId)
                shouldTryToDeleteMessageAndAttachments = noMoreStillUploadingAttachments(messageId: attachmentId.messageId)
            }
            guard shouldTryToDeleteMessageAndAttachments else { return }
            delegateManager.networkSendFlowDelegate.messageAndAttachmentsWereExternallyCancelledAndCanSafelyBeDeletedNow(messageId: attachmentId.messageId, flowId: flowId)
            return
        }

        // If we reach this point, the attachment is not ackowledged.
        // If there is no error, we simply resume missing chunks
        
        guard let error = error else {
            resumeMissingAttachmentUploads(flowId: flowId)
            return
        }
        
        // If we reach this point, some error occured while uploading the attachment's chunks.
        
        switch error {
        case .aTaskWasCancelled:
            // This happens when we cancel an upload: in that case, we cancel all upload tasks
            break
        case .couldNotRecoverAttachmentIdFromTask,
             .couldNotRetrieveAnHTTPResponse,
             .aTaskDidBecomeInvalidWithError(error: _),
             .sessionInvalidationError(error: _),
             .couldNotSaveContext,
             .unsupportedHTTPErrorStatusCode:
            resumeMissingAttachmentUploads(flowId: flowId)
        case .atLeastOneChunkDownloadPrivateURLHasExpired:
            downloadSignedURLsForAttachments(attachmentIds: [attachmentId], flowId: flowId)
        case .cannotFindAttachmentInDatabase:
            // We do nothing
            break
        }
    }
    
    
    func urlSessionDidFinishEventsForSessionWithIdentifier(_ identifier: String) {
        guard let handler = removeHandlerForIdentifier(identifier) else { return }
        if #available(iOS 13, *) {
            internalOperationQueue.addBarrierBlock({})
        } else {
            internalOperationQueue.waitUntilAllOperationsAreFinished()
        }
        internalOperationQueue.addOperation {
            DispatchQueue.main.async {
                handler()
            }
        }
    }

}

// MARK: - Implementing FinalizeSignedURLsOperationsDelegate

extension UploadAttachmentChunksCoordinator: FinalizeSignedURLsOperationsDelegate {
    
    func signedURLsOperationsAreFinished(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier, error: ResumeTaskForGettingAttachmentSignedURLsOperation.ReasonForCancel?) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let error = error else {
            // This is the best case, when no error occured
            os_log("Signed URLs were successfully obtained for attachment %{public}@", log: log, type: .info, attachmentId.debugDescription)
            return
        }
        
        attachmentStoppedToRefreshSignedURLs(attachmentId: attachmentId)

        os_log("Failed to obtain signed URLs for attachment %{public}@", log: log, type: .error, attachmentId.debugDescription)

        // If we reach this point, at least one of the operations queued for getting signed URLs did fail
        
        switch error {
        case .unexpectedDependencies:
            assertionFailure()
        case .cannotFindAttachmentInDatabase,
             .cannotFindMessageInDatabase:
            return
        case .aDependencyCancelled,
             .nonNilSignedURLWasFound,
             .failedToCreateTask(error: _):
            delegateManager.networkSendFlowDelegate.signedURLsDownloadFailedForAttachment(attachmentId: attachmentId, flowId: flowId)
        case .identityDelegateNotSet,
             .attachmentChunksSignedURLsTrackerNotSet:
            assertionFailure()
            delegateManager.networkSendFlowDelegate.signedURLsDownloadFailedForAttachment(attachmentId: attachmentId, flowId: flowId)
        case .messageUidFromServerIsNotSet:
            delegateManager.networkSendFlowDelegate.failedUploadAndGetUidOfMessage(messageId: attachmentId.messageId, flowId: flowId)
        }

        
    }
    
}

// MARK: - Implementing FinalizePostAttachmentUploadRequestOperationDelegate

extension UploadAttachmentChunksCoordinator: FinalizePostAttachmentUploadRequestOperationDelegate {
    
    func postAttachmentUploadRequestOperationsAreFinished(attachmentId: AttachmentIdentifier, urlSession: URLSession?, flowId: FlowIdentifier, error: FinalizePostAttachmentUploadRequestOperation.ReasonForCancel?) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        guard let error = error else {
            
            // This is the best case, when no error occured
            
            if let session = urlSession {
                addCurrentURLSession(session)
            }

            let NotificationType = ObvNetworkPostNotification.AttachmentUploadRequestIsTakenCareOf.self
            let userInfo: [String: Any] = [
                NotificationType.Key.flowId: flowId,
                NotificationType.Key.attachmentId: attachmentId
            ]
            notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
            
            return
        }
        
        // If we reach this point, at least one of the operations queued for resuming an attachment upload did fail
        
        switch error {
        case .attachmentWasAlreadyAcknowledged:
            let NotificationType = ObvNetworkPostNotification.AttachmentUploadRequestIsTakenCareOf.self
            let userInfo: [String: Any] = [
                NotificationType.Key.flowId: flowId,
                NotificationType.Key.attachmentId: attachmentId
            ]
            notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
            delegateManager.networkSendFlowDelegate.acknowledgedAttachment(attachmentId: attachmentId, flowId: flowId)
        case .messageNotUploadedYet:
            delegateManager.networkSendFlowDelegate.failedUploadAndGetUidOfMessage(messageId: attachmentId.messageId, flowId: flowId)
        case .noSignedURLAvailable:
            delegateManager.networkSendFlowDelegate.failedUploadAndGetUidOfMessage(messageId: attachmentId.messageId, flowId: flowId)
        case .failedToCreateOutboxAttachmentSession,
             .failedToCreateAnUploadTask,
             .couldNotWriteEncryptedChunkToFile,
             .cannotFindEncryptedChunkURL,
             .cannotFindEncryptedChunkAtURL,
             .couldNotSaveContext:
            delegateManager.networkSendFlowDelegate.attachmentFailedToUpload(attachmentId: attachmentId, flowId: flowId)
        case .contextCreatorIsNotSet,
             .identityDelegateIsNotSet:
            assertionFailure()
            delegateManager.networkSendFlowDelegate.attachmentFailedToUpload(attachmentId: attachmentId, flowId: flowId)
        case .cannotFindMessageOrAttachmentInDatabase:
            return
        case .invalidChunkNumberWasRequested:
            return
        case .attachmentFileCannotBeRead,
             .couldNotReadCleartextChunk,
             .cancelExternallyRequested:
            delegateManager.networkSendFlowDelegate.messageAndAttachmentsWereExternallyCancelledAndCanSafelyBeDeletedNow(messageId: attachmentId.messageId, flowId: flowId)
        case .fileDoesNotExistAnymore:
            // For now, if an attachment is missing, we cancel the whole message
            DispatchQueue(label: "Ephemeral queue created in UploadAttachmentChunksCoordinator for calling cancelAllAttachmentsUploadOfMessage").async {
                try? self.cancelAllAttachmentsUploadOfMessage(messageId: attachmentId.messageId, flowId: flowId)
            }
        case .cannotDetermineReasonForCancel:
            assertionFailure()
            return
        }
        
    }
    
}


// MARK: - Creating a Progress subclass for attachments composed of many chunks

final class AttachmentProgress: Progress {
    
    private let chunkTotalUnitCount: [Int64]
    private var chunkCompletedUnitCount: [Int64]
    
    init(currentChunkProgresses: [(completedUnitCount: Int64, totalUnitCount: Int64)]) {
        self.chunkTotalUnitCount = currentChunkProgresses.map { $0.totalUnitCount }
        self.chunkCompletedUnitCount = currentChunkProgresses.map { $0.completedUnitCount }
        super.init(parent: nil, userInfo: nil)
        self.totalUnitCount = chunkTotalUnitCount.reduce(0, +)
        self.completedUnitCount = chunkCompletedUnitCount.reduce(0, +)
    }

    fileprivate func set(totalBytesSent: Int64, forChunkNumber number: Int) {
        guard chunkIsNotAcknowledged(chunkNumber: number) else { return }
        let difference = totalBytesSent - chunkCompletedUnitCount[number]
        chunkCompletedUnitCount[number] = totalBytesSent
        self.completedUnitCount += difference
    }
    
    fileprivate func acknowledgeChunk(number: Int) {
        guard chunkIsNotAcknowledged(chunkNumber: number) else { return }
        let difference = chunkTotalUnitCount[number] - chunkCompletedUnitCount[number]
        chunkCompletedUnitCount[number] = chunkTotalUnitCount[number]
        assert(difference >= 0)
        self.completedUnitCount += difference
    }
    
    private func chunkIsNotAcknowledged(chunkNumber: Int) -> Bool {
        chunkCompletedUnitCount[chunkNumber] != chunkTotalUnitCount[chunkNumber]
    }
}


fileprivate final class WeakRef<T> where T: AnyObject {
    private(set) weak var value: T?
    init(to object: T) {
        self.value = object
    }
}
