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

    // Streaming the progress of a download to whoever is showing that attachment

    /// The continuations of the streams being followed, and the attachment each of them follows.
    ///
    /// Two dictionaries rather than one: a chunk arriving must reach the continuations of *its* attachment without a pass over all of them, while a stream is
    /// finished by its UUID alone, as the engine's other streams are.
    private var progressContinuationForStreamUUID = [UUID: AsyncStream<ObvAttachmentDownloadProgress>.Continuation]()
    private var progressStreamUUIDsForAttachment = [ObvAttachmentIdentifier: Set<UUID>]()

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
            // **Not the same as "nothing is downloading".** This map is in memory, so it is empty for a background `URLSession` that outlived the process
            // that started it — and such a session goes on writing chunks into a file whose message may be about to be deleted from the server. Said out
            // loud, because a cancel that cancelled nothing is otherwise indistinguishable from a cancel that had nothing to cancel.
            Self.logger.info("📁 [\(attachmentId.debugDescription, privacy: .public)] Not cancelling anything: this coordinator holds no download task for the attachment. Any background URLSession started by an earlier process is unaffected and keeps writing")
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
            // **The notification is posted only if the status actually changed**, which it was not until 2026-08-31: the failure was swallowed by a bare
            // `assertionFailure()` and the pause was announced regardless. Moving *to* `.paused` is legal only from `.resumeRequested` or from `.paused`
            // itself — `.markedForDeletion` is allowed through silently — so what throws here is `.downloaded` or `.cancelledByServer`, an attachment for
            // which pausing means nothing at all.
            //
            // Announcing it anyway did more than mislead. The app answers `inboxAttachmentDownloadWasPaused` by marking its join `.downloadable`, so the
            // glyph became a download arrow and the tap looked as though it had worked; the join being `.downloadable` then made the app ask to download,
            // `resumeDownload()` was refused on the same grounds, and nothing happened. One lie, and the attachment was further from a working state than
            // before the reader touched it.
            //
            // **A log rather than an assertion**: an attachment stuck at `.downloaded` with the app-side join still believing it is downloading is reachable
            // in ordinary use until that is repaired, and trapping every debug build on a reader's tap is noise. The throw is the signal.
            //
            // Note the sibling path was always right — `createTaskForPausingAttachmentDownload`'s error propagates through `try await task.value`, which
            // returns before the notification below. This branch, the one taken when no download task is held in memory, was the only one that lied.
            let op1 = ChangeAttachmentStatusToPausedOperation(attachmentId: attachmentId)
            do {
                try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
            } catch {
                Self.logger.error("📄[\(attachmentId.debugDescription, privacy: .public)] Could not pause the download: \(error.localizedDescription, privacy: .public). Saying nothing, since saying it paused would be false.")
                throw error
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
    func cleanExistingInboxAttachmentSessions(flowId: FlowIdentifier) async throws {
        
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
            throw ObvError.failedToCleanExistingInboxAttachmentSessions
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

    
    /// Follows the download of one attachment, for as long as the caller keeps the stream.
    ///
    /// The alternative this replaces is `requestDownloadAttachmentProgressesUpdatedSince(date:)`, which the app polls every 0.3s to move a number this
    /// coordinator already has. Here the number is pushed at the moment it changes, to the views showing that one attachment and to nothing else.
    ///
    /// The current progress is yielded at once, and is read from the database when nothing is held in memory. That is not an optimisation: a **paused**
    /// attachment has no in-memory entry, since none is created until a chunk arrives, so a stream that waited for the first chunk would report nothing at all
    /// and a paused download would appear not to have started.
    ///
    /// The buffering policy is what keeps a fast download from flooding its reader: only the latest progress means anything, so a consumer slower than
    /// `URLSession` sees the newest value rather than a queue of stale ones.
    func getAsyncStreamOfDownloadProgress(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async -> (streamUUID: UUID, stream: AsyncStream<ObvAttachmentDownloadProgress>) {

        let progressSoFar = await currentDownloadProgress(attachmentId: attachmentId, flowId: flowId)

        let streamUUID = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: ObvAttachmentDownloadProgress.self, bufferingPolicy: .bufferingNewest(1))

        progressContinuationForStreamUUID[streamUUID] = continuation
        progressStreamUUIDsForAttachment[attachmentId, default: []].insert(streamUUID)

        if let progressSoFar {
            continuation.yield(progressSoFar)
        }

        return (streamUUID, stream)

    }


    /// Ends one stream returned by ``getAsyncStreamOfDownloadProgress(attachmentId:flowId:)``.
    ///
    /// The caller has to do this: a continuation cannot learn on its own that the view following it has gone, `onTermination` running in the app's process and
    /// not here. A caller that forgets leaves this coordinator yielding into a stream nobody reads, for every attachment ever shown.
    func finishAsyncStreamOfDownloadProgress(streamUUID: UUID) {
        guard let continuation = progressContinuationForStreamUUID.removeValue(forKey: streamUUID) else { return }
        continuation.finish()
        for (attachmentId, streamUUIDs) in progressStreamUUIDsForAttachment where streamUUIDs.contains(streamUUID) {
            progressStreamUUIDsForAttachment[attachmentId]?.remove(streamUUID)
            if progressStreamUUIDsForAttachment[attachmentId]?.isEmpty ?? false {
                progressStreamUUIDsForAttachment.removeValue(forKey: attachmentId)
            }
        }
    }


    /// Where an attachment's download stands right now: what is held in memory, or failing that what the chunks on disk say.
    ///
    /// Returns nil when neither can answer, which is an attachment the engine knows nothing about.
    private func currentDownloadProgress(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async -> ObvAttachmentDownloadProgress? {

        if let (chunkProgresses, _) = chunksProgressesForAttachment[attachmentId] {
            return Self.downloadProgress(from: chunkProgresses)
        }

        guard let delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            return nil
        }

        // Nothing in memory, which is what a paused download looks like. The chunks already written are on disk, so the operation that would have created the
        // in-memory entry can answer instead.
        let op1 = CreateChunksProgressesForAttachmentOperation(attachmentId: attachmentId)
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            return nil
        }
        return Self.downloadProgress(from: op1.currentChunkProgresses)

    }


    /// The progress of the whole attachment, which is the sum over its chunks.
    private static func downloadProgress(from chunkProgresses: [ChunkProgress]) -> ObvAttachmentDownloadProgress {
        .init(totalBytesWritten: chunkProgresses.map({ $0.totalBytesWritten }).reduce(0, +),
              totalBytesExpectedToWrite: chunkProgresses.map({ $0.totalBytesExpectedToWrite }).reduce(0, +))
    }


    /// Reports what an attachment's chunks now amount to, to whoever is following it.
    private func yieldDownloadProgress(ofAttachment attachmentId: ObvAttachmentIdentifier) {
        guard let streamUUIDs = progressStreamUUIDsForAttachment[attachmentId], !streamUUIDs.isEmpty else { return }
        guard let (chunkProgresses, _) = chunksProgressesForAttachment[attachmentId] else { return }
        let progress = Self.downloadProgress(from: chunkProgresses)
        for streamUUID in streamUUIDs {
            progressContinuationForStreamUUID[streamUUID]?.yield(progress)
        }
    }


    /// Ends every stream following an attachment, its download being over.
    private func finishStreamsOfDownloadProgress(ofAttachment attachmentId: ObvAttachmentIdentifier) {
        guard let streamUUIDs = progressStreamUUIDsForAttachment.removeValue(forKey: attachmentId) else { return }
        for streamUUID in streamUUIDs {
            progressContinuationForStreamUUID.removeValue(forKey: streamUUID)?.finish()
        }
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


    /// Called by the app when the file of an attachment it was told is fully downloaded does not hash as the sender said it would.
    ///
    /// Deliberately a different entry point from ``appCouldNotFindFileOfDownloadedAttachment(attachmentId:flowId:)`` rather than a reuse of it: that one turns
    /// on the file being absent and returns when it is there, so it cannot serve a file whose bytes are merely wrong. The caller is expected to ask for the
    /// download to be resumed afterwards; this only undoes the belief that the attachment is complete.
    func appFoundACorruptFileForDownloadedAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws {

        guard let delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        let op1 = ResetAttachmentStatusBecauseTheDownloadedFileIsCorruptOperation(attachmentId: attachmentId, inbox: delegateManager.inbox)
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            assertionFailure()
            throw ObvError.anOperationCancelled(localizedDescription: "ResetAttachmentStatusBecauseTheDownloadedFileIsCorruptOperation")
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

        // What this actor is already handling, so that the operation builds no session for those — see there. Read before the `await` below and therefore
        // possibly out of date by the time the loop runs, which the loop allows for: it consults `downloadAttachmentTask` itself, and that reading wins.
        let attachmentsTheCoordinatorIsAlreadyHandling = Set(downloadAttachmentTask.keys)

        let op1 = DetermineAttachmentsToDownloadAndCreateURLSessionsOperation(
            kind: kind,
            tracker: self,
            delegateManager: delegateManager,
            attachmentsTheCoordinatorIsAlreadyHandling: attachmentsTheCoordinatorIsAlreadyHandling)

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
                    // There is no existing paused download to resume, we create a fresh download.
                    //
                    // The session comes from the operation, which built one because this attachment was not among those we said we were handling. It can
                    // be nil all the same: that reading was taken before the operation ran, and whatever we held for this attachment may have been
                    // dropped in between — by a session going invalid, say. Rare, and not worth recovering from here: the attachment stays
                    // `resumeRequested` and the next resume, of which there are several, will build one.
                    guard let urlSession = values.urlSession else {
                        Self.logger.error("📄[\(attachmentId.debugDescription, privacy: .public)] No URLSession for an attachment we no longer hold. Leaving it to the next resume.")
                        continue
                    }
                    kindOfResumeToPerform = .noPausedDownloadToResume(
                        attachmentId: attachmentId,
                        chunksToDownload: values.chunkNumbersAndSignedURLs,
                        urlSession: urlSession,
                        identityDelegate: identityDelegate,
                        flowId: flowId)
                }
                
                // If we reach this point, we must resume the download of the attachment
                
                let task: Task<Void, Error> = createTaskForResumingDownloadOfAttachmentWithSignedURLs(kind: kindOfResumeToPerform)

                Self.logger.debug("📄[\(attachmentId.debugDescription, privacy: .public)] Awaiting just created resumingBackgroundDownload task for attachment")

                do {
                    downloadAttachmentTask[attachmentId] = .resumingBackgroundDownload(task: task)
                    try await task.value
                    // **The session that is downloading, not the one the operation handed us.** Resuming a paused download resumes the tasks of the session
                    // held in memory, and storing the other one here is what left a later pause suspending a session with nothing in it — reporting a stop
                    // to the app while the bytes kept arriving.
                    downloadAttachmentTask[attachmentId] = .backgroundDownloadInProgress(urlSession: kindOfResumeToPerform.urlSession)
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

        /// The session whose tasks this resume actually runs in, which is what must be tracked afterwards.
        var urlSession: URLSession {
            switch self {
            case .resumingPausedDownload(let urlSession):
                urlSession
            case .noPausedDownloadToResume(_, _, let urlSession, _, _):
                urlSession
            }
        }
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
                
            case .attachmentNoLongerAvailable:
                
                let op1 = MarkAttachmentAsDeletedFromServerOperation(attachmentId: attachmentId)
                try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)

                failedAttemptsCounterManager.reset(counter: .downloadAttachment(attachmentId: attachmentId))
                downloadAttachmentTask.removeValue(forKey: attachmentId)

                // The attachment was deleted from server, and we marked it as cancelledFromServer in database.
                // The networkFetchFlowDelegate that we notify will notify the app. Then, the app will request the deletion of this attachment.
                delegateManager.networkFetchFlowDelegate.attachmentWasCancelledByServer(attachmentId: attachmentId, flowId: flowId)

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
            yieldDownloadProgress(ofAttachment: attachmentId)

        } else {
            
            do {
                let op1 = CreateChunksProgressesForAttachmentOperation(attachmentId: attachmentId)
                try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)

                chunksProgressesForAttachment[attachmentId] = (op1.currentChunkProgresses, Date())
                yieldDownloadProgress(ofAttachment: attachmentId)

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
        yieldDownloadProgress(ofAttachment: attachmentId)

    }
    

    func attachmentDownloadIsComplete(downloadAttachmentChunksSessionDelegate: DownloadAttachmentChunksSessionDelegate) async {
        
        let attachmentId = downloadAttachmentChunksSessionDelegate.attachmentId
        let flowId = downloadAttachmentChunksSessionDelegate.flowId
        
        // When an attachment is downloaded, we remove the progresses we stored in memory for its chunks

        chunksProgressesForAttachment.removeValue(forKey: attachmentId)

        // The download being over, there is nothing left to report: whoever was following it is told so by the stream ending. That the file has arrived is said
        // elsewhere, by the notification below and by what the app then reads from its own database.

        finishStreamsOfDownloadProgress(ofAttachment: attachmentId)

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
        case failedToCleanExistingInboxAttachmentSessions
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
            case .failedToCleanExistingInboxAttachmentSessions:
                return "Failed to clean existing inbox attachment sessions"
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
