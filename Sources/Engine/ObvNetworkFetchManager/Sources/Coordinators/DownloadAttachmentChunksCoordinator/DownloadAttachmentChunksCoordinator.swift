/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OSLog
import ObvMetaManager
import ObvTypes
import OlvidUtils
import ObvServerInterface


actor DownloadAttachmentChunksCoordinator {
    
    // MARK: - Instance variables

    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "DownloadAttachmentChunksCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
    private static var logger = Logger(subsystem: defaultLogSubsystem, category: logCategory)

    // We only use the `downloadAttachment` counter
    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()

    var delegateManager: ObvNetworkFetchDelegateManager?

    // Dealing with attachment upload progress
    
    // Maps an attachment identifier to its (exact) completed unit count
    typealias ChunkProgress = (totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)
    
    private var missingSignedURLsDownloadTasks = [ObvAttachmentIdentifier: MissingSignedURLsDownloadTask]()
    private enum MissingSignedURLsDownloadTask {
        case inProgress(task: Task<TaskForDownloadingAndSavingSignedURLsResult, Error>)
    }
    
    private var downloadAttachmentTask = [ObvAttachmentIdentifier: DownloadAttachmentTask]()
    private enum DownloadAttachmentTask {
        case resumingBackgroundDownload(task: Task<Void, Error>)
        case backgroundDownloadInProgress(urlSession: URLSession)
        case pausingBackgroundDownload(task: Task<Void, Error>, urlSession: URLSession)
        case backgroundDownloadPaused(urlSession: URLSession)
    }
        
    private var handlerForHandlingEventsForBackgroundURLSessionWithIdentifier = [String: (() -> Void)]()
    
    private var chunksProgressesForAttachment = [ObvAttachmentIdentifier: (chunkProgresses: [ChunkProgress], dateOfLastUpdate: Date)]()

    init(logPrefix: String) {
        let logSubsystem = "\(logPrefix).\(Self.defaultLogSubsystem)"
        Self.logger = Logger(subsystem: logSubsystem, category: Self.logCategory)
    }

    
    func setDelegateManager(_ delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }

}


// MARK: - Implementing DownloadAttachmentChunksDelegate

extension DownloadAttachmentChunksCoordinator: DownloadAttachmentChunksDelegate {
    
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) async -> Bool {
        return backgroundURLSessionIdentifier.isBackgroundURLSessionIdentifierForDownloadingAttachment()
    }
    
    
    func resumeDownloadOfAttachmentsNotAlreadyDownloading(downloadKind: InboxAttachmentDownloadKind, flowId: FlowIdentifier) async throws {
        
        Self.logger.debug("📄 Call to resumeDownloadOfAttachmentsNotAlreadyDownloading with downloadKind: \(downloadKind.debugDescription, privacy: .public)")
        
        // If the download is requested by the user (i.e., by the app), reset the failed attempts counter
        
        switch downloadKind {
        case .allDownloadableAttachmentsWithoutSession:
            break
        case .allDownloadableAttachmentsWithoutSessionForMessage(messageId: _):
            break
        case .specificDownloadableAttachmentsWithoutSession(attachmentId: let attachmentId, resumeRequestedByApp: let resumeRequestedByApp):
            if resumeRequestedByApp {
                failedAttemptsCounterManager.reset(counter: .downloadAttachment(attachmentId: attachmentId))
            }
        }
        
        // Make sure the attachment have signed URLs
        
        try await downloadAndSaveAllMissingSignedURLs(flowId: flowId)
        
        // Resume the download of missing chunks
        
        try await resumeDownloadOfAttachmentsHavingSignedURLs(kind: downloadKind, flowId: flowId)
        
    }
    
    
    /// Called, e.g., when the user deletes a message. Since she might do so while an attachment is downloading, this is called to make sure the download is properly cancelled.
    func cancelDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws {
        
        Self.logger.debug("📄[\(attachmentId.debugDescription, privacy: .public)] Call to cancelDownloadOfAttachment")

        // If there is no download task in progress, there is nothing to do
        
        guard downloadAttachmentTask[attachmentId] != nil else {
            return
        }
        
        // There is a download task, we pause it

        try await pauseDownloadOfAttachment(attachmentId: attachmentId, flowId: flowId)
        
        // We expect the download task to be paused. We cancel its associated URLSession
        
        guard let currentDownloadTask = downloadAttachmentTask[attachmentId] else {
            return
        }
        
        switch currentDownloadTask {
        case .resumingBackgroundDownload:
            assertionFailure()
            try await cancelDownloadOfAttachment(attachmentId: attachmentId, flowId: flowId)
            return
        case .pausingBackgroundDownload:
            assertionFailure()
            try await cancelDownloadOfAttachment(attachmentId: attachmentId, flowId: flowId)
            return
        case .backgroundDownloadInProgress:
            assertionFailure()
            try await cancelDownloadOfAttachment(attachmentId: attachmentId, flowId: flowId)
            return
        case .backgroundDownloadPaused(urlSession: let urlSession):
            Self.logger.debug("📄[\(attachmentId.debugDescription, privacy: .public)] Cancelling the url session associated to the attachment")
            urlSession.invalidateAndCancel()
            downloadAttachmentTask.removeValue(forKey: attachmentId)
            return
        }

    }
    
    
    func pauseDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws {
        
        Self.logger.debug("📄[\(attachmentId.debugDescription, privacy: .public)] Call to pauseDownloadOfAttachment")
        
        guard let delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            Self.logger.fault("The notification delegate is not set")
            assertionFailure()
            throw ObvError.theNotificationDelegateIsNotSet
        }

        // Make sure there is a download task to pause.
        
        guard let currentDownloadTask = downloadAttachmentTask[attachmentId] else {
            let op1 = ChangeAttachmentStatusToPausedOperation(attachmentId: attachmentId)
            do {
                try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
            } catch {
                assertionFailure()
            }
            ObvNetworkFetchNotificationNew.inboxAttachmentDownloadWasPaused(attachmentId: attachmentId, flowId: flowId)
                .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
            return
        }
        
        let urlSessionToPause: URLSession
        
        switch currentDownloadTask {
        case .resumingBackgroundDownload(let task):
            // We wait until the background download is resumed before we pause it
            try await task.value
            try await Task.sleep(milliseconds: 300) // Give some time to switch to backgroundDownloadInProgress
            try await pauseDownloadOfAttachment(attachmentId: attachmentId, flowId: flowId)
            return
        case .pausingBackgroundDownload(task: let task, urlSession: _):
            Self.logger.debug("📄[\(attachmentId.debugDescription, privacy: .public)] Awaiting an existing pause task")
            try await task.value
            try await pauseDownloadOfAttachment(attachmentId: attachmentId, flowId: flowId)
            return
        case .backgroundDownloadPaused(urlSession: _):
            Self.logger.debug("📄[\(attachmentId.debugDescription, privacy: .public)] The attachment download is already paused")
            return
        case .backgroundDownloadInProgress(urlSession: let urlSession):
            // The background download is ongoing, we can pause it
            urlSessionToPause = urlSession
        }
        
        // If we reach this point, we are in charge of pausing the attachment download
        
        let task = createTaskForPausingAttachmentDownload(attachmentId: attachmentId, urlSession: urlSessionToPause, flowId: flowId, delegateManager: delegateManager)
        
        do {
            downloadAttachmentTask[attachmentId] = .pausingBackgroundDownload(task: task, urlSession: urlSessionToPause)
            try await task.value
            downloadAttachmentTask[attachmentId] = .backgroundDownloadPaused(urlSession: urlSessionToPause)
        } catch {
            downloadAttachmentTask.removeValue(forKey: attachmentId)
            throw error
        }
        
        ObvNetworkFetchNotificationNew.inboxAttachmentDownloadWasPaused(attachmentId: attachmentId, flowId: flowId)
            .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
        
    }
    
    
    private func createTaskForPausingAttachmentDownload(attachmentId: ObvAttachmentIdentifier, urlSession: URLSession, flowId: FlowIdentifier, delegateManager: ObvNetworkFetchDelegateManager) -> Task<Void, Error> {
        Task {
            
            let allTasks = await urlSession.allTasks
            for task in allTasks {
                task.suspend()
            }
            
            let op1 = ChangeAttachmentStatusToPausedOperation(attachmentId: attachmentId)
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)

        }
    }


    func processCompletionHandler(_ handler: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier sessionIdentifier: String, withinFlowId flowId: FlowIdentifier) async {
        
        guard let delegateManager = delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            DispatchQueue.main.async { handler() }
            assertionFailure()
            return
        }
        
        if let previousHandler = handlerForHandlingEventsForBackgroundURLSessionWithIdentifier.removeValue(forKey: sessionIdentifier) {
            assertionFailure()
            DispatchQueue.main.async { previousHandler() }
        }
        
        handlerForHandlingEventsForBackgroundURLSessionWithIdentifier[sessionIdentifier] = handler
        
        // Look for an existing URLSession for the given identifier. If one exists, there is noting left to do:
        // We simply wait until all the events have been delivered to the delegate. When this is done, the urlSessionDidFinishEvents(forBackgroundURLSession:) method of the delegate will be called, calling the urlSessionDidFinishEventsForSessionWithIdentifier(_: String) of this coordinator, which will call the stored completion handler.
        
        for task in downloadAttachmentTask.values {
            switch task {
            case .backgroundDownloadInProgress(urlSession: let urlSession):
                assert(urlSession.configuration.identifier != nil)
                if urlSession.configuration.identifier == sessionIdentifier {
                    return
                }
            default:
                continue
            }
        }
        
        // If we reach this point, there is no more URLSession with the given identifier so we recreate one
        
        do {
            let op1 = RecreateURLSessionForCallingUIKitCompletionHandlerOperation(urlSessionIdentifier: sessionIdentifier, tracker: self, delegateManager: delegateManager)
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            assertionFailure()
        }
        
    }
    
    
    /// Called during bootstrap so as to invalidate and cancel any URLSession and to delete their associated ``InboxAttachmentSession``.
    /// This ensures a "fresh start" after a cold boot of the app.
    /// 2023-12: ok
    func cleanExistingOutboxAttachmentSessions(flowId: FlowIdentifier) async throws {
        
        guard let delegateManager = delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        let op1 = CleanExistingInboxAttachmentSessionsOperation(logSubsystem: delegateManager.logSubsystem)
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            assertionFailure()
            throw ObvError.failedToCleanExistingOutboxAttachmentSessions
        }
        
        failedAttemptsCounterManager.resetAll()
        
    }
    
    
    /// 2023-12: ok
    func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async -> [ObvAttachmentIdentifier: Float] {
        
        let latestChunksProgressesForAttachment = chunksProgressesForAttachment
            .filter { $0.value.dateOfLastUpdate > date }

        var progressesToReturn = [ObvAttachmentIdentifier: Float]()
        
        for (attachmentId, value) in latestChunksProgressesForAttachment {
            let totalBytesWritten = value.chunkProgresses.map({ $0.totalBytesWritten }).reduce(0, +)
            let totalBytesExpectedToWrite = value.chunkProgresses.map({ $0.totalBytesExpectedToWrite }).reduce(0, +)
            let progress = Float(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            progressesToReturn[attachmentId] = progress
        }
        
        return progressesToReturn
                        
    }

    
    /// Called by the app when it cannot find the file associated to an attachment, although it was notified that the attachment is fully downloaded. This is very rare.
    func appCouldNotFindFileOfDownloadedAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws {
        
        guard let delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        let op1 = ResetAttachmentStatusIfCurrentStatusIsDownloadedAndFileIsNotAvailableOperation(attachmentId: attachmentId, inbox: delegateManager.inbox)
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            assertionFailure()
            throw ObvError.anOperationCancelled(localizedDescription: "ResetAttachmentStatusIfCurrentStatusIsDownloadedAndFileIsNotAvailableOperation")
        }

    }

}


// MARK: - Helper methods allowing to implement the DownloadAttachmentChunksDelegate protocol

extension DownloadAttachmentChunksCoordinator {
    
    enum TaskForDownloadingAndSavingSignedURLsResult {
        case signedURLsWereSaved
        case attachmentWasMarkedACancelledFromServer
    }
    
    /// Returns a task allowing to download and save signed URLs for the chunks of the attachment.
    private func createTaskForDownloadingAndSavingSignedURLs(attachmentId: ObvAttachmentIdentifier, expectedChunkCount: Int, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) -> Task<TaskForDownloadingAndSavingSignedURLsResult, Error> {
        
        return Task {
            
            let method = RefreshInboxAttachmentSignedUrlServerMethod(
                identity: attachmentId.messageId.ownedCryptoIdentity,
                attachmentId: attachmentId,
                expectedChunkCount: expectedChunkCount,
                flowId: flowId)
            
            method.identityDelegate = delegateManager.identityDelegate

            let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ObvError.invalidServerResponse
            }

            guard let (status, chunkDownloadPrivateUrls) = RefreshInboxAttachmentSignedUrlServerMethod.parseObvServerResponse(responseData: data, using: Self.log) else {
                assertionFailure()
                throw ObvError.couldNotParseReturnStatusFromServer
            }

            switch status {

            case .ok:
                
                guard let chunkDownloadPrivateUrls else { assertionFailure(); throw ObvError.serverReturnedGeneralError }
                let op1 = SaveSignedURLsOperation(attachmentId: attachmentId, chunkDownloadPrivateUrls: chunkDownloadPrivateUrls)
                do {
                    try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
                } catch {
                    assertionFailure()
                    throw ObvError.anOperationCancelled(localizedDescription: "SaveSignedURLsOperation")
                }
                
                return .signedURLsWereSaved
                
            case .deletedFromServer:
                
                let op1 = MarkAttachmentAsDeletedFromServerOperation(attachmentId: attachmentId)
                do {
                    try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
                } catch {
                    assertionFailure()
                    throw ObvError.anOperationCancelled(localizedDescription: "MarKAttachmentAsDeletedFromServerOperation")
                }
                
                return .attachmentWasMarkedACancelledFromServer

            case .generalError:
                
                assertionFailure()
                throw ObvError.serverReturnedGeneralError

            }
            
        }
        
    }

    
    /// Before trying to download all attachments that can be downloaded, we make sure they all have valid signed URLs and download those that are missing.
    /// 2023-12 ok
    private func downloadAndSaveAllMissingSignedURLs(flowId: FlowIdentifier) async throws {
        
        Self.logger.debug("📄 Call to downloadAndSaveAllMissingSignedURLs")

        guard let delegateManager = delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        let op1 = DetermineAttachmentsWithMissingSignedURLsOperation()
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            assertionFailure()
            throw ObvError.anOperationCancelled(localizedDescription: "DetermineAttachmentsWithMissingSignedURLs")
        }

        let attachmentsWithMissingSignedURL = op1.attachmentsWithMissingSignedURL
        Self.logger.debug("📄 \(attachmentsWithMissingSignedURL.count) attachments with missing signed URL")
        guard !attachmentsWithMissingSignedURL.isEmpty else { return }
        
        // If we reach this point, we have signed URLs to download

        for (attachmentId, expectedChunkCount) in attachmentsWithMissingSignedURL {
            
            do {
                
                if let cached = missingSignedURLsDownloadTasks[attachmentId] {
                    switch cached {
                    case .inProgress(task: let task):
                        Self.logger.debug("📄[\(attachmentId.debugDescription, privacy: .public)] Awaiting existing task for downloading missing signed URLs for attachment")
                        _ = try await task.value
                        continue
                    }
                }
                
                let task: Task<TaskForDownloadingAndSavingSignedURLsResult, Error> = createTaskForDownloadingAndSavingSignedURLs(attachmentId: attachmentId, expectedChunkCount: expectedChunkCount, delegateManager: delegateManager, flowId: flowId)
                
                Self.logger.debug("📄[\(attachmentId.debugDescription, privacy: .public)] Awaiting just created task for downloading missing signed URLs for attachment")

                let result: DownloadAttachmentChunksCoordinator.TaskForDownloadingAndSavingSignedURLsResult
                
                do {
                    missingSignedURLsDownloadTasks[attachmentId] = .inProgress(task: task)
                    result = try await task.value
                    missingSignedURLsDownloadTasks.removeValue(forKey: attachmentId)
                } catch {
                    missingSignedURLsDownloadTasks.removeValue(forKey: attachmentId)
                    assertionFailure()
                    continue
                }
                
                switch result {
                case .signedURLsWereSaved:
                    // Signed URLs were returned and saved from database. The attachment can be downloaded at this point.
                    // Nothing left to do here, we continue with the next attachment
                    break
                case .attachmentWasMarkedACancelledFromServer:
                    // The attachment was deleted from server, and we marked it as cancelledFromServer in database.
                    // The networkFetchFlowDelegate that we notify will notify the app. Then, the app will request the deletion of this attachment.
                    delegateManager.networkFetchFlowDelegate.attachmentWasCancelledByServer(attachmentId: attachmentId, flowId: flowId)
                }
                
            } catch {
                
                assertionFailure()
                // In production, continue with the next attachment
                
            }
            
        }
        
    }

    
    /// 2023-12 ok
    private func resumeDownloadOfAttachmentsHavingSignedURLs(kind: InboxAttachmentDownloadKind, flowId: FlowIdentifier) async throws {
        
        Self.logger.debug("📄 Call to resumeDownloadOfAttachmentsHavingSignedURLs")

        guard let delegateManager = delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            Self.logger.fault("The identity delegate is not set")
            assertionFailure()
            throw ObvError.theIdentityDelegateIsNotSet
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            Self.logger.fault("The notification delegate is not set")
            assertionFailure()
            throw ObvError.theNotificationDelegateIsNotSet
        }

        let op1 = DetermineAttachmentsToDownloadAndCreateURLSessionsOperation(
            kind: kind,
            tracker: self,
            delegateManager: delegateManager)
        
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            assertionFailure()
            throw ObvError.anOperationCancelled(localizedDescription: "DetermineAttachmentsToDownloadOperation")
        }

        let chunksToDownloadForAttachment = op1.chunksToDownloadForAttachment
        guard !chunksToDownloadForAttachment.isEmpty else {
            Self.logger.debug("📄 No chunk to download")
            return
        }
        
        // If we reach this point, we have attachment chunks to download

        for (attachmentId, values) in chunksToDownloadForAttachment {
            
            Self.logger.debug("📄[\(attachmentId.debugDescription, privacy: .public)] There are \(values.chunkNumbersAndSignedURLs.count) chunks to download for attachment")

            do {
                
                let kindOfResumeToPerform: ResumeTaskKind
                
                if let cached = downloadAttachmentTask[attachmentId] {
                    switch cached {
                    case .pausingBackgroundDownload(task: let task, urlSession: _):
                        // Wait until the download is paused before resuming it
                        try await task.value
                        try await resumeDownloadOfAttachmentsHavingSignedURLs(kind: kind, flowId: flowId)
                        continue
                    case .resumingBackgroundDownload(task: let task):
                        Self.logger.debug("📄[\(attachmentId.debugDescription, privacy: .public)] Awaiting an existing resumingBackgroundDownload task for attachment")
                        try await task.value
                        continue
                    case .backgroundDownloadInProgress:
                        // Nothing to do, process the next attachment
                        continue
                    case .backgroundDownloadPaused(urlSession: let urlSession):
                        // We only need to resume the download tasks
                        kindOfResumeToPerform = .resumingPausedDownload(urlSession: urlSession)
                    }
                } else {
                    // There is no existing paused download to resume, we create a fresh download
                    kindOfResumeToPerform = .noPausedDownloadToResume(
                        attachmentId: attachmentId,
                        chunksToDownload: values.chunkNumbersAndSignedURLs,
                        urlSession: values.urlSession,
                        identityDelegate: identityDelegate,
                        flowId: flowId)
                }
                
                // If we reach this point, we must resume the download of the attachment
                
                let task: Task<Void, Error> = createTaskForResumingDownloadOfAttachmentWithSignedURLs(kind: kindOfResumeToPerform)

                Self.logger.debug("📄[\(attachmentId.debugDescription, privacy: .public)] Awaiting just created resumingBackgroundDownload task for attachment")

                do {
                    downloadAttachmentTask[attachmentId] = .resumingBackgroundDownload(task: task)
                    try await task.value
                    downloadAttachmentTask[attachmentId] = .backgroundDownloadInProgress(urlSession: values.urlSession)
                } catch {
                    downloadAttachmentTask.removeValue(forKey: attachmentId)
                    throw error
                }
                
                Self.logger.debug("📄[\(attachmentId.debugDescription, privacy: .public)] Download of attachment is in progress")

                ObvNetworkFetchNotificationNew.inboxAttachmentDownloadWasResumed(attachmentId: attachmentId, flowId: flowId)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
                
            } catch {
                
                Self.logger.debug("📄[\(attachmentId.debugDescription, privacy: .public)] Removing the downloadAttachmentTask for attachment as an error occured: \(error.localizedDescription, privacy: .public)")

                assertionFailure()
                // In production, continue with the next attachment
                
            }
            
        }
        
    }

    
    private enum ResumeTaskKind {
        case resumingPausedDownload(urlSession: URLSession)
        case noPausedDownloadToResume(attachmentId: ObvAttachmentIdentifier, chunksToDownload: [(chunkNumber: Int, signedURL: URL)], urlSession: URLSession, identityDelegate: ObvIdentityDelegate, flowId: FlowIdentifier)
    }
    
    
    private func createTaskForResumingDownloadOfAttachmentWithSignedURLs(kind: ResumeTaskKind) -> Task<Void, Error> {
        return Task {
            
            switch kind {
            case .resumingPausedDownload(let urlSession):
                
                let allTasks = await urlSession.allTasks
                for task in allTasks {
                    task.resume()
                }

            case .noPausedDownloadToResume(let attachmentId, let chunksToDownload, let urlSession, let identityDelegate, let flowId):
                
                for (chunkNumber, signedURL) in chunksToDownload {
                    let method = ObvS3DownloadAttachmentChunkMethod(attachmentId: attachmentId,
                                                                    chunkNumber: chunkNumber,
                                                                    signedURL: signedURL,
                                                                    flowId: flowId)
                    method.identityDelegate = identityDelegate
                    let downloadTask = try method.downloadTask(within: urlSession)
                    downloadTask.setAssociatedChunkNumber(chunkNumber)
                    downloadTask.resume()
                }
                
                urlSession.finishTasksAndInvalidate()

            }
            
        }
    }

}



// MARK: - Implementing AttachmentChunkDownloadProgressTrackerNEW

extension DownloadAttachmentChunksCoordinator: AttachmentChunkDownloadProgressTracker {
    
    func downloadAttachmentChunksSessionDidBecomeInvalid(downloadAttachmentChunksSessionDelegate: DownloadAttachmentChunksSessionDelegate, error: DownloadAttachmentChunksSessionDelegate.ErrorForTracker?) async {
                
        let attachmentId = downloadAttachmentChunksSessionDelegate.attachmentId
        let flowId = downloadAttachmentChunksSessionDelegate.flowId
        
        guard let delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            downloadAttachmentTask.removeValue(forKey: attachmentId)
            return
        }
        
        do {
            
            let op1 = DeleteInboxAttachmentSessionOperation(attachmentId: attachmentId)
            do {
                try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
            } catch {
                assertionFailure()
                downloadAttachmentTask.removeValue(forKey: attachmentId)
                return
            }

            // If the attachment is downloaded, there is nothing left to do.
            // Note that, if the attachment is downloaded, the network fetch flow delegate was already notified about it.
            guard !op1.attachmentIsDownloaded else {
                downloadAttachmentTask.removeValue(forKey: attachmentId)
                Self.logger.debug("📄[\(attachmentId.debugDescription, privacy: .public)] Removing the downloadAttachmentTask as the attachment is downloaded")
                return
            }
            
            // If we reach this point, the attachment is not downloaded.
            // If there is no error, we simply resume missing chunks
            
            guard let error else {
                failedAttemptsCounterManager.reset(counter: .downloadAttachment(attachmentId: attachmentId))
                downloadAttachmentTask.removeValue(forKey: attachmentId)
                try await resumeDownloadOfAttachmentsNotAlreadyDownloading(downloadKind: .specificDownloadableAttachmentsWithoutSession(attachmentId: attachmentId, resumeRequestedByApp: false), flowId: flowId)
                return
            }

            // If we reach this point, some error occured while downloading the attachment's chunks.
            
            switch error {
                
            case .failedToDecryptChunkOrWriteToFile:
                
                Self.logger.fault("📄[\(attachmentId.debugDescription, privacy: .public)] A downloaded chunk could not be decrypted or written to a file. We cancel the download.")
                
                do {
                    try await cancelDownloadOfAttachment(attachmentId: attachmentId, flowId: flowId)
                } catch {
                    Self.logger.fault("📄[\(attachmentId.debugDescription, privacy: .public)] Could not cancel the download of the attachment: \(error)")
                    return
                }
                
                Self.logger.info("📄[\(attachmentId.debugDescription, privacy: .public)] Since a chunk could not be decrypted or written to a file, we did cancel the download.")
                
                return
                
            case .couldNotRecoverAttachmentIdFromTask,
                 .couldNotRetrieveAnHTTPResponse,
                 .sessionInvalidationError,
                 .couldNotSaveContext,
                 .atLeastOneChunkIsNotYetAvailableOnServer,
                 .couldNotOpenEncryptedChunkFile,
                 .markChunkAsWrittenToAttachmentFileOperationFailed,
                 .unsupportedHTTPErrorStatusCode:
                
                let delay = failedAttemptsCounterManager.incrementAndGetDelay(.downloadAttachment(attachmentId: attachmentId))
                Self.logger.error("Will retry the call to resumeDownloadOfAttachmentsNotAlreadyDownloading in \(Double(delay) / 1000.0, privacy: .public) seconds")
                await retryManager.waitForDelay(milliseconds: delay)

                downloadAttachmentTask.removeValue(forKey: attachmentId)
                try await resumeDownloadOfAttachmentsNotAlreadyDownloading(downloadKind: .specificDownloadableAttachmentsWithoutSession(attachmentId: attachmentId, resumeRequestedByApp: false), flowId: flowId)
                return
                
            case .atLeastOneChunkDownloadPrivateURLHasExpired:
                
                let op1 = DeleteAllAttachmentSignedURLsOperation(attachmentId: attachmentId)
                try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)

                failedAttemptsCounterManager.reset(counter: .downloadAttachment(attachmentId: attachmentId))
                
                downloadAttachmentTask.removeValue(forKey: attachmentId)
                try await resumeDownloadOfAttachmentsNotAlreadyDownloading(downloadKind: .specificDownloadableAttachmentsWithoutSession(attachmentId: attachmentId, resumeRequestedByApp: false), flowId: flowId)
                return
                
            case .cannotFindAttachmentInDatabase:
                // We do nothing
                downloadAttachmentTask.removeValue(forKey: attachmentId)
                return

            }

        } catch {
            downloadAttachmentTask.removeValue(forKey: attachmentId)
            assertionFailure(error.localizedDescription)
        }
        
    }
    
    
    func urlSessionDidFinishEventsForSessionWithIdentifier(downloadAttachmentChunksSessionDelegate: DownloadAttachmentChunksSessionDelegate, urlSessionIdentifier: String) async {
        guard let handler = handlerForHandlingEventsForBackgroundURLSessionWithIdentifier.removeValue(forKey: urlSessionIdentifier) else { return }
        DispatchQueue.main.async {
            handler()
        }
    }
    

    func attachmentChunkDidProgress(downloadAttachmentChunksSessionDelegate: DownloadAttachmentChunksSessionDelegate, chunkProgress: (chunkNumber: Int, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)) async {
        
        let attachmentId = downloadAttachmentChunksSessionDelegate.attachmentId
        let flowId = downloadAttachmentChunksSessionDelegate.flowId
        
        Self.logger.debug("📄[\(attachmentId.debugDescription, privacy: .public)][\(chunkProgress.chunkNumber)] Attachment chunk did progress \(chunkProgress.totalBytesWritten)/\(chunkProgress.totalBytesExpectedToWrite)")

        guard let delegateManager = delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            return
        }

        if var (chunksProgresses, _) = chunksProgressesForAttachment[attachmentId] {
            
            guard chunkProgress.chunkNumber < chunksProgresses.count else { assertionFailure(); return }
            chunksProgresses[chunkProgress.chunkNumber] = (chunkProgress.totalBytesWritten, chunkProgress.totalBytesExpectedToWrite)
            chunksProgressesForAttachment[attachmentId] = (chunksProgresses, Date())
            
        } else {
            
            do {
                let op1 = CreateChunksProgressesForAttachmentOperation(attachmentId: attachmentId)
                try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)

                chunksProgressesForAttachment[attachmentId] = (op1.currentChunkProgresses, Date())
                
            } catch {
                assertionFailure()
                return
            }
            
        }

    }
    

    /// This method is called by the delegate of the session managing a chunk download task. It is called as soon as an encrypted chunk was downloaded, decrypted then written to the appropriate location in the attachment file.
    func attachmentChunkWasDecryptedAndWrittenToAttachmentFile(downloadAttachmentChunksSessionDelegate: DownloadAttachmentChunksSessionDelegate, chunkNumber: Int) async {
        
        let attachmentId = downloadAttachmentChunksSessionDelegate.attachmentId
        
        failedAttemptsCounterManager.reset(counter: .downloadAttachment(attachmentId: attachmentId))

        guard var (chunksProgresses, _) = chunksProgressesForAttachment[attachmentId] else { return }
        guard chunkNumber < chunksProgresses.count else { assertionFailure(); return }
        let totalBytesExpectedToWrite = chunksProgresses[chunkNumber].totalBytesExpectedToWrite
        chunksProgresses[chunkNumber] = (totalBytesExpectedToWrite, totalBytesExpectedToWrite)
        chunksProgressesForAttachment[attachmentId] = (chunksProgresses, Date())

    }
    

    func attachmentDownloadIsComplete(downloadAttachmentChunksSessionDelegate: DownloadAttachmentChunksSessionDelegate) async {
        
        let attachmentId = downloadAttachmentChunksSessionDelegate.attachmentId
        let flowId = downloadAttachmentChunksSessionDelegate.flowId
        
        // When an attachment is downloaded, we remove the progresses we stored in memory for its chunks

        chunksProgressesForAttachment.removeValue(forKey: attachmentId)
        
        // We also immediately notify the network fetch flow delegate (so as to notify the app)
        
        guard let delegateManager = delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            return
        }

        delegateManager.networkFetchFlowDelegate.attachmentWasDownloaded(attachmentId: attachmentId, flowId: flowId)

    }
    
}


// MARK: - Errors

extension DownloadAttachmentChunksCoordinator {
        
    enum ObvError: LocalizedError {
        
        case theDelegateManagerIsNotSet
        case theContextCreatorIsNotSet
        case theIdentityDelegateIsNotSet
        case theNotificationDelegateIsNotSet
        case anOperationCancelled(localizedDescription: String?)
        case failedToCleanExistingOutboxAttachmentSessions
        case invalidServerResponse
        case couldNotParseReturnStatusFromServer
        case serverReturnedGeneralError
        case couldNotPauseAttachmentDownload
        
        var errorDescription: String? {
            switch self {
            case .theDelegateManagerIsNotSet:
                return "The delegate manager is not set"
            case .theContextCreatorIsNotSet:
                return "The context creator is not set"
            case .anOperationCancelled(localizedDescription: let localizedDescription):
                return "An operation cancelled with reason: \(String(describing: localizedDescription))"
            case .failedToCleanExistingOutboxAttachmentSessions:
                return "Failed to clean existing outbox attachments session"
            case .invalidServerResponse:
                return "Invalid server response"
            case .couldNotParseReturnStatusFromServer:
                return "Could not parse return status from server"
            case .serverReturnedGeneralError:
                return "Server returned a general error"
            case .theIdentityDelegateIsNotSet:
                return "The identity delegate is not set"
            case .theNotificationDelegateIsNotSet:
                return "The notification delegate is not set"
            case .couldNotPauseAttachmentDownload:
                return "Could not pause attachment download"
            }
        }
    }

    
}

// MARK: - Other stuff

fileprivate final class WeakRef<T> where T: AnyObject {
    private(set) weak var value: T?
    init(to object: T) {
        self.value = object
    }
}
