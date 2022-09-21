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
import ObvMetaManager
import ObvTypes
import OlvidUtils


final class DownloadAttachmentChunksCoordinator {
    
    // MARK: - Instance variables

    fileprivate let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "DownloadAttachmentChunksCoordinator"
    private let internalQueueForHandlers = DispatchQueue(label: "Internal queue for handlers")
    private var _handlerForSessionIdentifier = [String: (() -> Void)]()
    private let localQueue = DispatchQueue(label: "DownloadAttachmentChunksCoordinatorQueue")
    private let queueForNotifications = DispatchQueue(label: "DownloadAttachmentChunksCoordinator queue for notifications")

    // We only use the `downloadAttachment` counter
    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()

    var delegateManager: ObvNetworkFetchDelegateManager?

    private var internalOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Queue for DownloadAttachmentChunksCoordinator operations"
        queue.maxConcurrentOperationCount = 4
        return queue
    }()
    
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
    
    // Maps an attachment identifier to its (exact) completed unit count
    typealias ChunkProgress = (totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)
    private var _chunksProgressesForAttachment = [AttachmentIdentifier: (chunkProgresses: [ChunkProgress], dateOfLastUpdate: Date)]()
    private let queueForAttachmentsProgresses = DispatchQueue(label: "Internal queue for attachments progresses", attributes: .concurrent)
    
    private var _currentURLSessions = [WeakRef<URLSession>]()
    private func cleanCurrentURLSessions() {
        _currentURLSessions = _currentURLSessions.filter({ $0.value != nil })
    }
    private func addCurrentURLSession(_ urlSession: URLSession) {
        cleanCurrentURLSessions()
        _currentURLSessions.append(WeakRef(to: urlSession))
    }
    private func currentURLSessionExists(withIdentifier identifier: String) -> Bool {
        cleanCurrentURLSessions()
        return _currentURLSessions.compactMap({ $0.value }).filter({ $0.configuration.identifier == identifier }).first != nil
    }
    private func getCurrentURLSession(withIdentifier identifier: String) -> URLSession? {
        cleanCurrentURLSessions()
        return _currentURLSessions.compactMap({ $0.value }).filter({ $0.configuration.identifier == identifier }).first
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


// MARK: - Implementing DownloadAttachmentChunksDelegate

extension DownloadAttachmentChunksCoordinator: DownloadAttachmentChunksDelegate {
    
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool {
        return backgroundURLSessionIdentifier.isBackgroundURLSessionIdentifierForDownloadingAttachment()
    }
    
    
    func processAllAttachmentsOfMessage(messageId: MessageIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        os_log("🌊 Call to processAllAttachmentsOfMessage within flow %{public}@", log: log, type: .debug, flowId.debugDescription)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        var attachmentsRequiringSignedURLs = [AttachmentIdentifier]()

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            let message: InboxMessage
            do {
                guard let _message = try InboxMessage.get(messageId: messageId, within: obvContext) else {
                    os_log("Could not find message in DB", log: log, type: .fault)
                    return
                }
                message = _message
            } catch {
                os_log("Failed to get inbox message: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
                        
            attachmentsRequiringSignedURLs = message.attachments.filter({ !$0.allChunksHaveSignedURLs }).map({ $0.attachmentId })

        }
        
        // The attachments requiring signed URLs are dealt with now.
        downloadSignedURLsForAttachments(attachmentIds: attachmentsRequiringSignedURLs, flowId: flowId)
        // There might be attachments with signed URLs already. We download them now.
        resumeMissingAttachmentDownloads(flowId: flowId)

    }
    
    
    /// This is method is called prior `resumeMissingAttachmentDownloads` and allows to download signed URLs for
    /// all the attachment's chunks. It is also called when something goes wrong with previously downloaded URLs (like
    /// when they expire).
    ///
    /// We queue an operation that will delete all the signed URLs
    /// of the attachment, then an operation that resume a download task that gets signed URLs from the server.
    /// We do so after adding a barrier to the queue, so as to make sure not to interfere with other tasks.
    private func downloadSignedURLsForAttachments(attachmentIds: [AttachmentIdentifier], flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
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
        
        localQueue.async { [weak self] in
            
            guard let _self = self else { return }
            
            var operationsToQueue = [Operation]()

            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
                for attachmentId in attachmentIds {
                    guard !_self.attachmentIsAlreadyRefreshingSignedURLs(attachmentId: attachmentId) else { continue }
                    _self.attachmentStartsToRefreshSignedURLs(attachmentId: attachmentId)
                    let ops = _self.getOperationsForDownloadingSignedURLsForAttachment(attachmentId: attachmentId,
                                                                                 logSubsystem: delegateManager.logSubsystem,
                                                                                 obvContext: obvContext,
                                                                                 identityDelegate: identityDelegate)
                    
                    operationsToQueue.append(contentsOf: ops)
                }
                
            }
            
            guard !operationsToQueue.isEmpty else { return }
            
            // We prevent any interference with previous operations
            self?.internalOperationQueue.addBarrierBlock({})
            self?.internalOperationQueue.addOperations(operationsToQueue, waitUntilFinished: false)

        }
        
    }


    func processCompletionHandler(_ handler: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier identifier: String, withinFlowId flowId: FlowIdentifier) {
                
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            DispatchQueue.main.async { handler() }
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        // Store the completion handler
        setHandlerForIdentifier(identifier, handler: handler)

        localQueue.async { [weak self] in

            guard let _self = self else { return }
            
            // Look for an existing URLSession for the given identifier. If one exists, there is noting left to do:
            // We simply wait until all the events have been delivered to the delegate. When this is done, the urlSessionDidFinishEvents(forBackgroundURLSession:) method of the delegate will be called, calling the urlSessionDidFinishEventsForSessionWithIdentifier(_: String) of this coordinator, which will call the stored completion handler.
            guard !_self.currentURLSessionExists(withIdentifier: identifier) else {
                return
            }
            
            // If we reach this point, there is no more URLSession with the given identifier so we recreate one
            
            let operation = RecreatingURLSessionForCallingUIKitCompletionHandlerOperation(urlSessionIdentifier: identifier,
                                                                                          logSubsystem: delegateManager.logSubsystem,
                                                                                          flowId: flowId,
                                                                                          inbox: delegateManager.inbox,
                                                                                          contextCreator: contextCreator,
                                                                                          attachmentChunkDownloadProgressTracker: _self)
            
            self?.internalOperationQueue.addBarrierBlock({})
            self?.internalOperationQueue.addOperation(operation)
            
        } // End of localQueue.async

    }


    /// This method looks for `InboxAttachmentSession` objects . The objective is to "takover" these sessions.
    /// More precisely: this method creates one operation per object. This operation does the following *before* finishing :
    /// - It recreates the `URLSession`
    /// - It invalidates the `URLSession` and cancels all the tasks
    /// - It deletes the `InboxAttachmentSession` object.
    func cleanExistingOutboxAttachmentSessions(flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
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
        
        localQueue.async { [weak self] in

            guard let _self = self else { return }
            
            var attachmentIds = [AttachmentIdentifier]()
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                let attachmentSessions: [InboxAttachmentSession]
                do {
                    attachmentSessions = try InboxAttachmentSession.getAll(within: obvContext)
                } catch {
                    os_log("Could not get attachments sessions", log: log, type: .fault)
                    return
                }
                attachmentIds = attachmentSessions.compactMap({ $0.attachment?.attachmentId })
            }
            guard !attachmentIds.isEmpty else { return }
            
            let operationsToQueue: [Operation] = attachmentIds.map { (attachmentId) in
                CleanExistingInboxAttachmentSessions(attachmentId: attachmentId,
                                                     logSubsystem: delegateManager.logSubsystem,
                                                     contextCreator: contextCreator,
                                                     delegate: _self,
                                                     flowId: flowId)
            }

            self?.internalOperationQueue.addBarrierBlock({})
            self?.internalOperationQueue.addOperations(operationsToQueue, waitUntilFinished: true)
            
        }

        
    }
    
    
    func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async -> [AttachmentIdentifier: Float] {
        
        return await withCheckedContinuation { (continuation: CheckedContinuation<[AttachmentIdentifier: Float], Never>) in
            queueForAttachmentsProgresses.async { [weak self] in
                guard let _self = self else { continuation.resume(returning: [:]); return }
                var progressesToReturn = [AttachmentIdentifier: Float]()
                let appropriateChunksProgressesForAttachment = _self._chunksProgressesForAttachment.filter({ $0.value.dateOfLastUpdate > date })
                for (attachmentId, value) in appropriateChunksProgressesForAttachment {
                    let totalBytesWritten = value.chunkProgresses.map({ $0.totalBytesWritten }).reduce(0, +)
                    let totalBytesExpectedToWrite = value.chunkProgresses.map({ $0.totalBytesExpectedToWrite }).reduce(0, +)
                    let progress = Float(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
                    progressesToReturn[attachmentId] = progress
                }
                continuation.resume(returning: progressesToReturn)
            }
        }
                
    }
    
    
    func resumeMissingAttachmentDownloads(flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
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
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        var resumedAttachmentIds = [AttachmentIdentifier]()

        localQueue.async { [weak self] in

            guard let _self = self else { return }
            
            var operationsToQueue = [Operation]()

            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                
                let attachmentsToResume: [InboxAttachment]
                do {
                    attachmentsToResume = (try InboxAttachment.getAllDownloadableWithoutSession(within: obvContext))
                } catch {
                    os_log("Could not get attachments to upload", log: log, type: .fault)
                    return
                }

                guard !attachmentsToResume.isEmpty else {
                    os_log("There is no downloadable attachment left", log: log, type: .info)
                    return
                }

                os_log("👑 We found %{public}d attachment(s) to resume.", log: log, type: .info, attachmentsToResume.count)

                attachmentsToResume.forEach {
                    os_log("👑 Attachment %{public}@ has a total of %{public}d chunk(s), and %{public}d still need to be downloaded", log: log, type: .info, $0.attachmentId.debugDescription, $0.chunks.count, $0.chunks.filter({ !$0.cleartextChunkWasWrittenToAttachmentFile }).count)
                    let ops = _self.getOperationsForResumingAttachment($0, flowId: flowId, logSubsystem: delegateManager.logSubsystem, inbox: delegateManager.inbox, contextCreator: contextCreator, identityDelegate: identityDelegate)
                    os_log("👑 We created %{public}d operations in order to download Attachment %{public}@", log: log, type: .info, ops.count, $0.attachmentId.debugDescription)
                    operationsToQueue.append(contentsOf: ops)
                }

                resumedAttachmentIds = attachmentsToResume.map({ $0.attachmentId })

            }
                        
            // We prevent any interference with previous operations
            _self.internalOperationQueue.addBarrierBlock({})
            _self.internalOperationQueue.addOperations(operationsToQueue, waitUntilFinished: true)
            
            // We notify that the attachment has been taken care of. This will be catched by the flow manager.
            for attachmentId in resumedAttachmentIds {
                ObvNetworkFetchNotificationNew.inboxAttachmentWasTakenCareOf(attachmentId: attachmentId, flowId: flowId)
                    .postOnBackgroundQueue(_self.queueForNotifications, within: notificationDelegate)
            }

        } // End of localQueue.async
     
    }

    
    func resumeAttachmentDownloadIfResumeIsRequested(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
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

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        localQueue.async { [weak self] in
            
            guard let _self = self else { return }
            
            var operationsToQueue = [Operation]()

            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                
                let attachmentToResume: InboxAttachment
                do {
                    guard let _attachmentToResume = try InboxAttachment.get(attachmentId: attachmentId, within: obvContext) else { return }
                    guard !_attachmentToResume.isDownloaded else { return }
                    guard _attachmentToResume.session == nil else { return }
                    guard _attachmentToResume.status == .resumeRequested else { return }
                    attachmentToResume = _attachmentToResume
                } catch {
                    os_log("Could not get attachments to upload", log: log, type: .fault)
                    return
                }
                
                os_log("👑 Attachment %{public}@ has a total of %{public}d chunk(s) and its download is about to be resumed", log: log, type: .info, attachmentId.debugDescription, attachmentToResume.chunks.count)
                operationsToQueue = _self.getOperationsForResumingAttachment(attachmentToResume, flowId: flowId, logSubsystem: delegateManager.logSubsystem, inbox: delegateManager.inbox, contextCreator: contextCreator, identityDelegate: identityDelegate)
                os_log("👑 We created %{public}d operations in order to download Attachment %{public}@", log: log, type: .info, operationsToQueue.count, attachmentId.debugDescription)
                
            }
            
            guard !operationsToQueue.isEmpty else { return }
                        
            // We prevent any interference with previous operations
            _self.internalOperationQueue.addBarrierBlock({})
            _self.internalOperationQueue.addOperations(operationsToQueue, waitUntilFinished: true)
        
            ObvNetworkFetchNotificationNew.inboxAttachmentWasTakenCareOf(attachmentId: attachmentId, flowId: flowId)
                .postOnBackgroundQueue(_self.queueForNotifications, within: notificationDelegate)

        } // End of localQueue.async
                
    }
}


// MARK: - Implementing AttachmentChunkDownloadProgressTracker

extension DownloadAttachmentChunksCoordinator: AttachmentChunkDownloadProgressTracker {
    
    func downloadAttachmentChunksSessionDidBecomeInvalid(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier, error: DownloadAttachmentChunksSessionDelegate.ErrorForTracker?) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
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

        // Check whether the attachment is downloaded and delete the session
        
        var attachmentIsDownloaded = false
        var allChunksHaveSignedURLs = false
        localQueue.sync {
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                guard let attachment = try? InboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                    os_log("Could not find attachment in database", log: log, type: .info)
                    attachmentIsDownloaded = false
                    return
                }
                attachmentIsDownloaded = attachment.isDownloaded
                allChunksHaveSignedURLs = attachment.allChunksHaveSignedURLs
                if let attachmentSession = attachment.session {
                    obvContext.delete(attachmentSession)
                    do {
                        try obvContext.save(logOnFailure: log)
                    } catch {
                        os_log("Could not delete InboxAttachmentSession although is was invalidated", log: log, type: .fault)
                        assertionFailure()
                        return
                    }
                }
            }
        }
        
        // If the attachment is downloaded, there is nothing left to do.
        // Note that, if the attachment is downloaded, the network fetch flow delegate was already notified about it.
        guard !attachmentIsDownloaded else {
            return
        }

        // If we reach this point, the attachment is not downloaded.
        // If there is no error, we simply resume missing chunks
        
        guard let error = error else {
            failedAttemptsCounterManager.reset(counter: .downloadAttachment(attachmentId: attachmentId))
            if allChunksHaveSignedURLs {
                resumeAttachmentDownloadIfResumeIsRequested(attachmentId: attachmentId, flowId: flowId)
            } else {
                downloadSignedURLsForAttachments(attachmentIds: [attachmentId], flowId: flowId)
            }
            return
        }
        
        // If we reach this point, some error occured while downloading the attachment's chunks.
        
        switch error {
        case .couldNotRecoverAttachmentIdFromTask,
             .couldNotRetrieveAnHTTPResponse,
             .sessionInvalidationError(error: _),
             .couldNotSaveContext,
             .atLeastOneChunkIsNotYetAvailableOnServer,
             .couldNotOpenEncryptedChunkFile,
             .unsupportedHTTPErrorStatusCode:
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.downloadAttachment(attachmentId: attachmentId))
            retryManager.executeWithDelay(delay) { [weak self] in
                self?.resumeAttachmentDownloadIfResumeIsRequested(attachmentId: attachmentId, flowId: flowId)
            }
        case .atLeastOneChunkDownloadPrivateURLHasExpired:
            downloadSignedURLsForAttachments(attachmentIds: [attachmentId], flowId: flowId)
        case .cannotFindAttachmentInDatabase:
            // We do nothing
            break
        }
    }
    
    func urlSessionDidFinishEventsForSessionWithIdentifier(_ identifier: String) {
        guard let handler = removeHandlerForIdentifier(identifier) else { return }
        internalOperationQueue.addBarrierBlock({})
        internalOperationQueue.addOperation {
            DispatchQueue.main.async {
                handler()
            }
        }
    }
    
    
    func attachmentChunkDidProgress(attachmentId: AttachmentIdentifier, chunkProgress: (chunkNumber: Int, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64), flowId: FlowIdentifier) {
        
        queueForAttachmentsProgresses.async(flags: .barrier) { [weak self] in
            guard let _self = self else { return }
            
            if var (chunksProgresses, _) = _self._chunksProgressesForAttachment[attachmentId] {
                
                guard chunkProgress.chunkNumber < chunksProgresses.count else { assertionFailure(); return }
                chunksProgresses[chunkProgress.chunkNumber] = (chunkProgress.totalBytesWritten, chunkProgress.totalBytesExpectedToWrite)
                _self._chunksProgressesForAttachment[attachmentId] = (chunksProgresses, Date())
                
            } else {
                
                guard let delegateManager = _self.delegateManager else {
                    let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: _self.logCategory)
                    os_log("The Delegate Manager is not set", log: log, type: .fault)
                    assertionFailure()
                    return
                }

                let log = OSLog(subsystem: delegateManager.logSubsystem, category: _self.logCategory)

                guard let contextCreator = delegateManager.contextCreator else {
                    os_log("The context creator manager is not set", log: log, type: .fault)
                    assertionFailure()
                    return
                }

                guard let chunksProgresses = _self.createChunksProgressesForAttachment(attachmentId: attachmentId,
                                                                                       contextCreator: contextCreator,
                                                                                       flowId: flowId)
                else {
                    return
                }
                _self._chunksProgressesForAttachment[attachmentId] = chunksProgresses

            }

        }
                
    }
    
    
    /// This method is called by the delegate of the session managing a chunk download task. It is called as soon as an encrypted chunk was downloaded, decrypted then written to the appropriate location in the attachment file.
    func attachmentChunkWasDecryptedAndWrittenToAttachmentFile(attachmentId: AttachmentIdentifier, chunkNumber: Int, flowId: FlowIdentifier) {
        failedAttemptsCounterManager.reset(counter: .downloadAttachment(attachmentId: attachmentId))

        queueForAttachmentsProgresses.async(flags: .barrier) { [weak self] in
            
            guard var (chunksProgresses, _) = self?._chunksProgressesForAttachment[attachmentId] else { return }
            guard chunkNumber < chunksProgresses.count else { assertionFailure(); return }
            let totalBytesExpectedToWrite = chunksProgresses[chunkNumber].totalBytesExpectedToWrite
            chunksProgresses[chunkNumber] = (totalBytesExpectedToWrite, totalBytesExpectedToWrite)
            self?._chunksProgressesForAttachment[attachmentId] = (chunksProgresses, Date())

        }

    }
    
    
    func attachmentDownloadIsComplete(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {

        // When an attachment is downloaded, we remove the progresses we stored in memory for its chunks

        queueForAttachmentsProgresses.async(flags: .barrier) { [weak self] in
            self?._chunksProgressesForAttachment.removeValue(forKey: attachmentId)
        }

        // We also immediately notify the network fetch flow delegate (so as to notify the app)
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        delegateManager.networkFetchFlowDelegate.attachmentWasDownloaded(attachmentId: attachmentId, flowId: flowId)
        
    }


    private func createChunksProgressesForAttachment(attachmentId: AttachmentIdentifier, contextCreator: ObvCreateContextDelegate, flowId: FlowIdentifier) -> ([ChunkProgress], Date)? {
        /// Must be executed on queueForAttachmentsProgresses
        var chunksProgressess: ([ChunkProgress], Date)?
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            guard let attachment = try? InboxAttachment.get(attachmentId: attachmentId, within: obvContext) else { return }
            chunksProgressess = (attachment.currentChunkProgresses, Date())
        }
        return chunksProgressess
    }

    
    func resumeDownloadOfAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
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

        // Since the that attachment download was resumed by the user, we reset the failed attempt counter
        
        failedAttemptsCounterManager.reset(counter: .downloadAttachment(attachmentId: attachmentId))
        
        localQueue.async { [weak self] in
            
            // We prevent any interference with previous operations
            self?.internalOperationQueue.addBarrierBlock({})

            let op = MarkInboxAttachmentAsPausedOrResumedOperation(attachmentId: attachmentId, targetStatus: .resumed, logSubsystem: delegateManager.logSubsystem, flowId: flowId, contextCreator: contextCreator, delegate: self)
            self?.internalOperationQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
            if op.isCancelled {
                guard let reasonForCancel = op.reasonForCancel else {
                    assertionFailure()
                    return
                }
                switch reasonForCancel {
                case .contextCreatorIsNotSet, .couldNotResumeOrPauseDownload, .coreDataError:
                    assertionFailure()
                    return
                case .cannotFindInboxAttachmentInDatabase, .attachmentIsMarkedForDeletion:
                    return
                }
            }
            
        }
        
    }

    
    func pauseDownloadOfAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
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

        localQueue.async { [weak self] in
            
            // We prevent any interference with previous operations
            self?.internalOperationQueue.addBarrierBlock({})

            let op = MarkInboxAttachmentAsPausedOrResumedOperation(attachmentId: attachmentId, targetStatus: .paused, logSubsystem: delegateManager.logSubsystem, flowId: flowId, contextCreator: contextCreator, delegate: self)
            self?.internalOperationQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
            if op.isCancelled {
                guard let reasonForCancel = op.reasonForCancel else {
                    assertionFailure()
                    return
                }
                switch reasonForCancel {
                case .contextCreatorIsNotSet, .couldNotResumeOrPauseDownload, .coreDataError:
                    assertionFailure()
                    return
                case .cannotFindInboxAttachmentInDatabase, .attachmentIsMarkedForDeletion:
                    assertionFailure()
                    return
                }
            }
            
        }
        
    }

}

// MARK: - Implementing MarkInboxAttachmentAsPausedOrResumedOperationDelegate

extension DownloadAttachmentChunksCoordinator: MarkInboxAttachmentAsPausedOrResumedOperationDelegate {
    
    func inboxAttachmentWasJustMarkedAsPausedOrResumed(attachmentId: AttachmentIdentifier, pausedOrResumed: MarkInboxAttachmentAsPausedOrResumedOperation.PausedOrResumed, flowId: FlowIdentifier) {
        
        // If we reach this point, the attachment was just marked as "resumed" or as "paused".
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
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

        // We first notify
        
        switch pausedOrResumed {
        case .paused:
            ObvNetworkFetchNotificationNew.inboxAttachmentDownloadWasPaused(attachmentId: attachmentId, flowId: flowId)
                .postOnBackgroundQueue(queueForNotifications, within: notificationDelegate)
        case .resumed:
            ObvNetworkFetchNotificationNew.inboxAttachmentDownloadWasResumed(attachmentId: attachmentId, flowId: flowId)
                .postOnBackgroundQueue(queueForNotifications, within: notificationDelegate)
        }

        // We can now try to resume or pause the tasks of an existing session, or creation a new session.

        localQueue.async { [weak self] in

            guard let _self = self else { return }
            
            var previousURLSession: URLSession?
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                let attachment = try? InboxAttachment.get(attachmentId: attachmentId, within: obvContext)
                guard let sessionIdentifier = attachment?.session?.sessionIdentifier else { return }
                previousURLSession = _self.getCurrentURLSession(withIdentifier: sessionIdentifier)
            }

            if let prevSess = previousURLSession {
                let resumeOrSuspend: ResumeOrSuspendAllTasksOfURLSessionOperation.ResumeOrSuspend = pausedOrResumed == .paused ? .suspend : .resume
                let op = ResumeOrSuspendAllTasksOfURLSessionOperation(urlSession: prevSess, resumeOrSuspend: resumeOrSuspend, logSubsystem: delegateManager.logSubsystem)
                self?.internalOperationQueue.addOperations([op], waitUntilFinished: true) // Cannot fail
            } else {
                DispatchQueue(label: "Queue for calling resumeAttachmentDownloadIfResumeIsRequested").async { [weak self] in
                    switch pausedOrResumed {
                    case .paused:
                        // There is no session to suspend, so we have nothing to do in this case
                        break
                    case .resumed:
                        self?.resumeAttachmentDownloadIfResumeIsRequested(attachmentId: attachmentId, flowId: flowId)
                    }
                }
            }

        }
    }
    
    
}

// MARK: - Implementing AttachmentChunksSignedURLsTracker

extension DownloadAttachmentChunksCoordinator: AttachmentChunksSignedURLsTracker {
    
    func getSignedURLsSessionDidBecomeInvalid(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier, error: GetSignedURLsSessionDelegate.ErrorForTracker?) {
        
        defer {
            attachmentStoppedToRefreshSignedURLs(attachmentId: attachmentId)
        }
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let error = error else {
            self.resumeMissingAttachmentDownloads(flowId: flowId)
            return
        }
    
        // If we reach this point, something went wrong while downloading the signed URLs
        
        switch error {
        case .aTaskDidBecomeInvalidWithError(error: _),
             .couldNotParseServerResponse,
             .coreDataFailure,
             .couldNotSaveContext,
             .generalErrorFromServer,
             .sessionInvalidationError(error: _):
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.downloadAttachment(attachmentId: attachmentId))
            retryManager.executeWithDelay(delay) { [weak self] in
                self?.downloadSignedURLsForAttachments(attachmentIds: [attachmentId], flowId: flowId)
            }
        case .cannotFindAttachmentInDatabase:
            // We do nothing
            break
        case .attachmentWasCancelledByTheServer:
            delegateManager.networkFetchFlowDelegate.attachmentWasCancelledByServer(attachmentId: attachmentId, flowId: flowId)
        }
        
    }
}


// MARK: - Implementing FinalizeCleanExistingInboxAttachmentSessionsDelegate

extension DownloadAttachmentChunksCoordinator: FinalizeCleanExistingInboxAttachmentSessionsDelegate {
    
    func cleanExistingInboxAttachmentSessionsIsFinished(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier, error: CleanExistingInboxAttachmentSessions.ReasonForCancel?) {
        
        failedAttemptsCounterManager.reset(counter: .downloadAttachment(attachmentId: attachmentId))

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let error = error else {
            // This is the best case, when no error occured
            os_log("We successfully cleaned InboxAttachmentSession for attachment %{public}@", log: log, type: .info, attachmentId.debugDescription)
            return
        }

        switch error {
        case .contextCreatorIsNotSet,
             .couldNotSaveContext,
             .coreDataFailure:
            assertionFailure()
        case .cannotFindAttachmentInDatabase,
             .noOutboxAttachmentSessionSet:
            break
        }
        
    }
    
}


// MARK: - Implementing FinalizeSignedURLsOperationsDelegate

extension DownloadAttachmentChunksCoordinator: FinalizeSignedURLsOperationsDelegate {
    
    func signedURLsOperationsAreFinished(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier, error: ResumeTaskForGettingAttachmentSignedURLsOperation.ReasonForCancel?) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let error = error else {
            // This is the best case, when no error occured
            os_log("Signed URLs operations are finished for attachment %{public}@", log: log, type: .info, attachmentId.debugDescription)
            return
        }

        os_log("Failed to obtain signed URLs for attachment %{public}@", log: log, type: .error, attachmentId.debugDescription)
        
        attachmentStoppedToRefreshSignedURLs(attachmentId: attachmentId)

        // If we reach this point, at least one of the operations queued for getting signed URLs did fail
        
        switch error {
        case .unexpectedDependencies:
            assertionFailure()
        case .cannotFindAttachmentInDatabase:
            return
        case .aDependencyCancelled,
             .nonNilSignedURLWasFound,
             .coreDataFailure,
             .failedToCreateTask(error: _):
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.downloadAttachment(attachmentId: attachmentId))
            retryManager.executeWithDelay(delay) { [weak self] in
                self?.downloadSignedURLsForAttachments(attachmentIds: [attachmentId], flowId: flowId)
            }
        case .attachmentChunksSignedURLsTrackerNotSet:
            assertionFailure()
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.downloadAttachment(attachmentId: attachmentId))
            retryManager.executeWithDelay(delay) { [weak self] in
                self?.downloadSignedURLsForAttachments(attachmentIds: [attachmentId], flowId: flowId)
            }
        }
        
    }
    
}


// MARK: - Implementing FinalizeDownloadChunksOperationsDelegate

extension DownloadAttachmentChunksCoordinator: FinalizeDownloadChunksOperationsDelegate {
    
    func downloadChunksOperationsAreFinished(attachmentId: AttachmentIdentifier, urlSession: URLSession?, flowId: FlowIdentifier, error: ResumeDownloadsOfMissingChunksOperation.ReasonForCancel?) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let error = error else {
            // This is the best case, when no error occured
            if let session = urlSession {
                addCurrentURLSession(session)
            }
            os_log("All operations for downloading chunks of attachment %{public}@ are finished and did not cancel", log: log, type: .info, attachmentId.debugDescription)
            return
        }

        switch error {
        case .contextCreatorIsNotSet,
             .identityDelegateIsNotSet,
             .missingRequiredDependency,
             .dependencyDoesNotProvideExpectedInformations:
            assertionFailure()
            urlSession?.invalidateAndCancel()
        case .cannotFindAttachmentInDatabase:
            urlSession?.invalidateAndCancel()
        case .cancelledDependency,
             .failedToCreateTask,
             .coreDataFailure:
            urlSession?.invalidateAndCancel()
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.downloadAttachment(attachmentId: attachmentId))
            retryManager.executeWithDelay(delay) { [weak self] in
                self?.resumeAttachmentDownloadIfResumeIsRequested(attachmentId: attachmentId, flowId: flowId)
            }
        case .allChunksAreAlreadyDownloaded:
            assert(urlSession != nil)
            urlSession?.invalidateAndCancel()
        case .atLeastOneChunkHasNoSignedURL:
            urlSession?.invalidateAndCancel()
            downloadSignedURLsForAttachments(attachmentIds: [attachmentId], flowId: flowId)
        }

    }
    
}

// MARK: - Helpers

extension DownloadAttachmentChunksCoordinator {
    
    private func getOperationsForResumingAttachment(_ attachment: InboxAttachment, flowId: FlowIdentifier, logSubsystem: String, inbox: URL, contextCreator: ObvCreateContextDelegate, identityDelegate: ObvIdentityDelegate) -> [Operation] {
        
        var operations = [Operation]()

        let firstOp = ReCreateURLSessionWithNewDelegateForAttachmentDownloadOperation(attachmentId: attachment.attachmentId,
                                                                                      logSubsystem: logSubsystem,
                                                                                      flowId: flowId,
                                                                                      inbox: inbox,
                                                                                      contextCreator: contextCreator,
                                                                                      attachmentChunkDownloadProgressTracker: self)
        
        operations.append(firstOp)
        
        let secondOp = ResumeDownloadsOfMissingChunksOperation(attachmentId: attachment.attachmentId,
                                                               logSubsystem: logSubsystem,
                                                               flowId: flowId,
                                                               contextCreator: contextCreator,
                                                               identityDelegate: identityDelegate,
                                                               delegate: self)
        secondOp.addDependency(firstOp)
        operations.append(secondOp)
        
        return operations
    }
 
    
    private func getOperationsForDownloadingSignedURLsForAttachment(attachmentId: AttachmentIdentifier, logSubsystem: String, obvContext: ObvContext, identityDelegate: ObvIdentityDelegate) -> [Operation] {
        
        var operations = [Operation]()

        let firstOp = DeletePreviousAttachmentSignedURLsOperation(attachmentId: attachmentId, logSubsystem: logSubsystem, obvContext: obvContext)
        let secondOp = ResumeTaskForGettingAttachmentSignedURLsOperation(attachmentId: attachmentId, logSubsystem: logSubsystem, obvContext: obvContext, identityDelegate: identityDelegate, attachmentChunksSignedURLsTracker: self, delegate: self)
        
        secondOp.addDependency(firstOp)
        
        operations.append(firstOp)
        operations.append(secondOp)

        return operations
        
    }
    
}


fileprivate final class WeakRef<T> where T: AnyObject {
    private(set) weak var value: T?
    init(to object: T) {
        self.value = object
    }
}
