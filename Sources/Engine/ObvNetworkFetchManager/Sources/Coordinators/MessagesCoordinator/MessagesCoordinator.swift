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
import os.log
import ObvServerInterface
import ObvTypes
import ObvOperation
import ObvCrypto
import ObvMetaManager
import OlvidUtils
import CoreData


actor MessagesCoordinator {
    
    // MARK: - Instance variables
    
    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "MessagesCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
    private static var logger = Logger(subsystem: defaultLogSubsystem, category: logCategory)

    weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    private enum ExtendedPayloadDownloadTask {
        case inProgress(task: Task<Void, Error>)
    }
    
    private var extendedPayloadDownloadTasks = [ObvMessageIdentifier: ExtendedPayloadDownloadTask]()
    
    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()

    init(logPrefix: String) {
        let logSubsystem = "\(logPrefix).\(Self.defaultLogSubsystem)"
        Self.logger = Logger(subsystem: logSubsystem, category: Self.logCategory)
    }

    func setDelegateManager(_ delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }

    private var cacheOfCurrentDeviceUIDForOwnedIdentity = [ObvCryptoIdentity: UID]()
    
    private typealias DownloadMessagesTask = Task<Void,Error>
    private var downloadMessagesTaskInProgressForOwnedCryptoId = [ObvCryptoIdentity: DownloadMessagesTask]()

}


// MARK: - MessagesDelegate

extension MessagesCoordinator: MessagesDelegate {

    
    func downloadAllMessagesAndListAttachments(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async {
                
        Self.logger.debug("[🚩][\(flowId.shortDebugDescription)] Call to downloadAllMessagesAndListAttachments for owned identity \(ownedCryptoId.debugDescription)")
        ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] MessagesCoordinator.downloadAllMessagesAndListAttachments(ownedCryptoId:flowId:)")
        defer {
            Self.logger.debug("[🚩][\(flowId.shortDebugDescription)] End of the call to downloadAllMessagesAndListAttachments for owned identity \(ownedCryptoId.debugDescription)")
        }
        
        var awaitTaskFailed = false
        let awaitedTaskDescription: String

        if let downloadMessagesTaskInProgress = downloadMessagesTaskInProgressForOwnedCryptoId[ownedCryptoId] {
            
            // A download message task is already in progress. Since it was created before our own call to downloadAllMessagesAndListAttachments(ownedCryptoId:flowId:), we wait until it's done before performing our own work.
            
            Self.logger.debug("[🚩][\(flowId.shortDebugDescription)] A task \(downloadMessagesTaskInProgress.shortDebugDescription) is already in progress for downloading messages for owned identity \(ownedCryptoId.debugDescription)")
            ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] A task \(downloadMessagesTaskInProgress.shortDebugDescription) is already in progress for downloading messages for owned identity \(ownedCryptoId.debugDescription)")
            
            try? await downloadMessagesTaskInProgress.value
            
            // Since this task was suspended while we were waiting for the end of the tasks prior our call to downloadAllMessagesAndListAttachments(ownedCryptoId:flowId:), there might be a new task in progress, created *after*
            // our call to downloadAllMessagesAndListAttachments(ownedCryptoId:flowId:).
            
            if let newDownloadMessagesTaskInProgress = downloadMessagesTaskInProgressForOwnedCryptoId[ownedCryptoId], newDownloadMessagesTaskInProgress != downloadMessagesTaskInProgress {

                // A download message task already exists. It was created *after* our call to downloadAllMessagesAndListAttachments(ownedCryptoId:flowId:) so we can simply await until it's done

                Self.logger.debug("[🚩][\(flowId.shortDebugDescription)] The previous download task \(downloadMessagesTaskInProgress.shortDebugDescription) is done. A new one was created in the meantime \(newDownloadMessagesTaskInProgress.shortDebugDescription). We await it.")
                ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] The previous download task \(downloadMessagesTaskInProgress.shortDebugDescription) is done. A new one was created in the meantime \(newDownloadMessagesTaskInProgress.shortDebugDescription). We await it.")

                do {
                    try await newDownloadMessagesTaskInProgress.value
                } catch {
                    awaitTaskFailed = true
                }

                awaitedTaskDescription = newDownloadMessagesTaskInProgress.shortDebugDescription

            } else {
                
                // No download message task was created. So we create one, save it in order to make it accessible to other calls to downloadAllMessagesAndListAttachments(ownedCryptoId:flowId:)
                
                let newDownloadMessagesTaskInProgress = createDownloadMessagesAndListAttachmentsTask(ownedCryptoId: ownedCryptoId, flowId: flowId)

                downloadMessagesTaskInProgressForOwnedCryptoId[ownedCryptoId] = newDownloadMessagesTaskInProgress
                
                Self.logger.debug("[🚩][\(flowId.shortDebugDescription)] The previous download task \(downloadMessagesTaskInProgress.shortDebugDescription) is done. No other download task was created in the meantime. We created and saved a new one \(newDownloadMessagesTaskInProgress.shortDebugDescription). We await it.")
                ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] The previous download task \(downloadMessagesTaskInProgress.shortDebugDescription) is done. No other download task was created in the meantime. We created and saved a new one \(newDownloadMessagesTaskInProgress.shortDebugDescription). We await it.")
                
                do {
                    try await newDownloadMessagesTaskInProgress.value
                } catch {
                    awaitTaskFailed = true
                }
                
                if downloadMessagesTaskInProgressForOwnedCryptoId[ownedCryptoId] == newDownloadMessagesTaskInProgress {
                    downloadMessagesTaskInProgressForOwnedCryptoId[ownedCryptoId] = nil
                }

                awaitedTaskDescription = newDownloadMessagesTaskInProgress.shortDebugDescription

            }
            
        } else {
            
            // No download task is in progress. We create one, and save it in order to make it accessible to other calls to downloadAllMessagesAndListAttachments(ownedCryptoId:flowId:)
            
            let awaitedTask = createDownloadMessagesAndListAttachmentsTask(ownedCryptoId: ownedCryptoId, flowId: flowId)
            
            downloadMessagesTaskInProgressForOwnedCryptoId[ownedCryptoId] = awaitedTask

            Self.logger.debug("[🚩][\(flowId.shortDebugDescription)] No existing task found for downloading messages for owned identity \(ownedCryptoId.debugDescription). We created task \(awaitedTask.shortDebugDescription) will now await for it.")
            ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] No existing task found for downloading messages for owned identity \(ownedCryptoId.debugDescription). We created task \(awaitedTask.shortDebugDescription) will now await for it.")

            do {
                try await awaitedTask.value
            } catch {
                awaitTaskFailed = true
            }
            
            if downloadMessagesTaskInProgressForOwnedCryptoId[ownedCryptoId] == awaitedTask {
                downloadMessagesTaskInProgressForOwnedCryptoId[ownedCryptoId] = nil
            }

            awaitedTaskDescription = awaitedTask.shortDebugDescription

        }
        
        Self.logger.debug("[🚩][\(flowId.shortDebugDescription)] The task \(awaitedTaskDescription) for downloading messages for owned identity \(ownedCryptoId.debugDescription) is finished (awaitTaskFailed: \(awaitTaskFailed)).")
        ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] The task \(awaitedTaskDescription) for downloading messages for owned identity \(ownedCryptoId.debugDescription) is finished (awaitTaskFailed: \(awaitTaskFailed))")

        if awaitTaskFailed {
            // The delay increase/reset is managed by the DownloadMessagesTask
            let delay = failedAttemptsCounterManager.getCurrentDelay(.downloadAllMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
            Self.logger.error("[🚩][\(flowId.shortDebugDescription)] 🖲️ Will retry the call to downloadAllMessagesAndListAttachments in \(Double(delay) / 1000.0) seconds")
            ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] Will retry the call to downloadAllMessagesAndListAttachments in \(delay) seconds")
            await retryManager.waitForDelay(milliseconds: delay)
            await downloadAllMessagesAndListAttachments(ownedCryptoId: ownedCryptoId, flowId: flowId)
        }

    }
    
    
    private func createDownloadMessagesAndListAttachmentsTask(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) -> DownloadMessagesTask {
        return Task {
            
            do {
                try await downloadMessagesAndListAttachments(ownedCryptoId: ownedCryptoId, flowId: flowId, serverTimestampOfLastMessageBeforeTruncation: nil, currentInvalidToken: nil)
                failedAttemptsCounterManager.reset(counter: .downloadAllMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
                Self.logger.info("[🚩][\(flowId.shortDebugDescription)] Call to downloadMessagesAndListAttachments for owned identity \(ownedCryptoId.debugDescription) was a success")
            } catch {
                if let error = error as? ObvError {
                    switch error {
                    case .deviceIsNotRegistered:
                        delegateManager?.networkFetchFlowDelegate.serverReportedThatThisDeviceIsNotRegistered(ownedIdentity: ownedCryptoId, flowId: flowId)
                        return
                    default:
                        break
                    }
                } else if let error = error as? ObvServerMethodError {
                    switch error {
                    case .ownedIdentityIsNotActive:
                        delegateManager?.networkFetchFlowDelegate.fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ownedCryptoId, flowId: flowId)
                        return
                    default:
                        break
                    }
                }
                _ = failedAttemptsCounterManager.incrementAndGetDelay(.downloadAllMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
                throw error
            }
            
        }
        
    }
     

    private func downloadMessagesAndListAttachments(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier, serverTimestampOfLastMessageBeforeTruncation: Int?, currentInvalidToken: Data?) async throws {
        
        guard let delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            Self.logger.fault("The identity delegate is not set")
            assertionFailure()
            throw ObvError.theIdentityDelegateIsNotSet
        }

        let sessionToken = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(
            for: ownedCryptoId,
            currentInvalidToken: currentInvalidToken,
            flowId: flowId).serverSessionToken
        
        let currentDeviceUid = try await getCurrentDeviceUidOfOwnedIdentity(ownedCryptoIdentity: ownedCryptoId, flowId: flowId)

        // Perform the server query allowing to download messages and to list their attachments
        
        let serverReturnStatus = try await performServerDownloadMessagesAndListAttachmentsMethod(
            ownedCryptoId: ownedCryptoId,
            sessionToken: sessionToken,
            currentDeviceUid: currentDeviceUid,
            serverTimestampOfLastMessageBeforeTruncation: serverTimestampOfLastMessageBeforeTruncation,
            identityDelegate: identityDelegate,
            flowId: flowId)
        
        // Process the status returned by the server
        
        let downloadTimestampFromServer: Date
        let messagesAndAttachmentsOnServer: [ObvServerDownloadMessagesAndListAttachmentsMethod.MessageAndAttachmentsOnServer]
        let newServerTimestampOfLastMessageBeforeTruncation: Int?
        
        switch serverReturnStatus {
            
        case .deviceIsNotRegistered:
            
            Task { delegateManager.networkFetchFlowDelegate.serverReportedThatThisDeviceIsNotRegistered(ownedIdentity: ownedCryptoId, flowId: flowId) }
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.downloadAllMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
            Self.logger.error("[🚩] 🖲️ Will retry the call to downloadMessagesAndListAttachments in \(Double(delay) / 1000.0) seconds")
            await retryManager.waitForDelay(milliseconds: delay)
            try await downloadMessagesAndListAttachments(
                ownedCryptoId: ownedCryptoId,
                flowId: flowId,
                serverTimestampOfLastMessageBeforeTruncation: serverTimestampOfLastMessageBeforeTruncation,
                currentInvalidToken: nil)
            return

        case .invalidSession:
            
            failedAttemptsCounterManager.reset(counter: .downloadAllMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
            try await downloadMessagesAndListAttachments(
                ownedCryptoId: ownedCryptoId,
                flowId: flowId,
                serverTimestampOfLastMessageBeforeTruncation: serverTimestampOfLastMessageBeforeTruncation,
                currentInvalidToken: sessionToken)
            return

        case .generalError:
            
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.downloadAllMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
            Self.logger.error("🖲️ Will retry the call to downloadMessagesAndListAttachments in \(Double(delay) / 1000.0) seconds")
            await retryManager.waitForDelay(milliseconds: delay)
            try await downloadMessagesAndListAttachments(
                ownedCryptoId: ownedCryptoId,
                flowId: flowId,
                serverTimestampOfLastMessageBeforeTruncation: serverTimestampOfLastMessageBeforeTruncation,
                currentInvalidToken: nil)
            return

        case .listingTruncated(let _downloadTimestampFromServer, let _messagesAndAttachmentsOnServer, let _serverTimestampOfLastMessageBeforeTruncation):
            downloadTimestampFromServer = _downloadTimestampFromServer
            messagesAndAttachmentsOnServer = _messagesAndAttachmentsOnServer
            newServerTimestampOfLastMessageBeforeTruncation = _serverTimestampOfLastMessageBeforeTruncation

        case .ok(let _downloadTimestampFromServer, let _messagesAndAttachmentsOnServer):
            downloadTimestampFromServer = _downloadTimestampFromServer
            messagesAndAttachmentsOnServer = _messagesAndAttachmentsOnServer
            newServerTimestampOfLastMessageBeforeTruncation = nil

        }
        
        // If we reach this point, the server returned a proper list of messages and attachments that we can save.
        // Note that the listing is truncated iff serverTimestampOfLastMessageBeforeTruncation != nil
                
        ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] We successfully downloaded \(messagesAndAttachmentsOnServer.count) messages that we will now save to DB. New serverTimestampOfLastMessageBeforeTruncation: \(String(describing: newServerTimestampOfLastMessageBeforeTruncation))")
        Self.logger.info("[🚩][\(flowId.shortDebugDescription)] We successfully downloaded \(messagesAndAttachmentsOnServer.count) messages that we will now save to DB. New serverTimestampOfLastMessageBeforeTruncation: \(String(describing: newServerTimestampOfLastMessageBeforeTruncation))")

        // We may have downloaded hundreds of messages. We don't want to save them all in one big operation. So we split the
        // messagesAndAttachmentsOnServer array into slices, and save then process each slice idependently.
        
        let messagesAndAttachmentsOnServerSlices = messagesAndAttachmentsOnServer.toSlices(ofMaxSize: ObvNetworkFetchDelegateManager.batchSize)
        
        for (index, messagesAndAttachmentsOnServerSlice) in messagesAndAttachmentsOnServerSlices.enumerated() {
            
            let isLastSlice: Bool = (index == messagesAndAttachmentsOnServerSlices.count - 1)
            
            let idsOfMessagesToProcess: [ObvMessageIdentifier]
            do {
                let op1 = SaveMessagesAndAttachmentsFromServerOperation(
                    ownedIdentity: ownedCryptoId,
                    listOfMessageAndAttachmentsOnServer: messagesAndAttachmentsOnServerSlice,
                    downloadTimestampFromServer: downloadTimestampFromServer,
                    localDownloadTimestamp: Date(),
                    logger: Self.logger,
                    flowId: flowId)
                try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, queuePriority: .high, log: Self.log, flowId: flowId)
                idsOfMessagesToProcess = op1.idsOfMessagesToProcess
            } catch {
                assertionFailure()
                throw ObvError.failedSaveMessagesAndAttachmentsFromServer
            }

            ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] Among the \(messagesAndAttachmentsOnServer.count) downloaded messages, \(idsOfMessagesToProcess.count) should be processed. isLastSlice: \(isLastSlice.description)")
            Self.logger.info("[🚩][\(flowId.shortDebugDescription)] Among the \(messagesAndAttachmentsOnServer.count) downloaded messages, \(idsOfMessagesToProcess.count) should be processed. isLastSlice: \(isLastSlice.description)")
            
            // All the messages of the slice where saved, we can request them to be marked as listed on the server.
            // We do this asynchronously so as not to slow down the saving of other messages.
            
            Task {
                do {
                    let messageUIDs: [UID] = messagesAndAttachmentsOnServerSlice.map(\.messageUidFromServer)
                    try await delegateManager.batchDeleteAndMarkAsListedDelegate.markSpecificMessagesAsListed(ownedCryptoId: ownedCryptoId, messageUIDs: messageUIDs, flowId: flowId)
                } catch {
                    Self.logger.fault("[🚩] The call to markSpecificMessagesAsListed did fail: \(error.localizedDescription)")
                    assertionFailure()
                }
            }
            
            // All the messages of the slice where saved, we can request their processing.
            // We do this asynchronously so as not to slow down the saving of other messages.

            do {
                try launchProcessingOfUnprocessedMessages(ownedCryptoIdentity: ownedCryptoId,
                                                          executionReason: .oneSliceOfListOfDownloadedMessagesWasSaved(idsOfMessagesToProcess: idsOfMessagesToProcess),
                                                          flowId: flowId)
            } catch {
                Self.logger.fault("[🚩] We could not process the saved slice of messages: \(error.localizedDescription)")
                assertionFailure() // In production, save the other slices anyway
            }

            // We requested the "mark as listed" and the processing of the slice, we loop to the next slice
            
        }

        // We saved all the listed messages, request them to be "marked as listed", and requested their processing.
        // If the listing was truncated, try to list again.

        if let newServerTimestampOfLastMessageBeforeTruncation {
            
            Self.logger.info("[🚩][\(flowId.shortDebugDescription)] 🌊 Will call downloadMessagesAndListAttachments as the listing was truncated")
            ObvDisplayableLogs.shared.log("[\(flowId.shortDebugDescription)] Will call downloadMessagesAndListAttachments as the listing was truncated")
            
            do {
                try launchProcessingOfUnprocessedMessages(ownedCryptoIdentity: ownedCryptoId,
                                                          executionReason: .truncatedListPerformed,
                                                          flowId: flowId)
            } catch {
                Self.logger.fault("[🚩] We could not process truncated list of messages: \(error.localizedDescription)")
                assertionFailure() // In production, continue anyway
            }

            try await downloadMessagesAndListAttachments(ownedCryptoId: ownedCryptoId, flowId: flowId, serverTimestampOfLastMessageBeforeTruncation: newServerTimestampOfLastMessageBeforeTruncation, currentInvalidToken: nil)
            
        } else {
            
            do {
                try launchProcessingOfUnprocessedMessages(ownedCryptoIdentity: ownedCryptoId,
                                                          executionReason: .untruncatedListPerformed(downloadTimestampFromServer: downloadTimestampFromServer),
                                                          flowId: flowId)
            } catch {
                Self.logger.fault("[🚩] We could not process untruncated list of messages: \(error.localizedDescription)")
                assertionFailure() // In production, continue anyway
            }

            Self.logger.info("[🚩][\(flowId.shortDebugDescription)] 🌊 Ending the listing as the last one was not truncated")
            ObvDisplayableLogs.shared.log("[\(flowId.shortDebugDescription)] Ending the listing as the last one was not truncated")
            
        }
        
    }
    
    
    private func performServerDownloadMessagesAndListAttachmentsMethod(ownedCryptoId: ObvCryptoIdentity, sessionToken: Data, currentDeviceUid: UID, serverTimestampOfLastMessageBeforeTruncation: Int?, identityDelegate: ObvIdentityDelegate, flowId: FlowIdentifier) async throws -> ObvServerDownloadMessagesAndListAttachmentsMethod.PossibleReturnStatus {
        
        let method = ObvServerDownloadMessagesAndListAttachmentsMethod(
            ownedIdentity: ownedCryptoId,
            currentDeviceUid: currentDeviceUid,
            sessionToken: sessionToken,
            serverTimestampOfLastMessageBeforeTruncation: serverTimestampOfLastMessageBeforeTruncation,
            flowId: flowId)
        
        method.identityDelegate = identityDelegate

        let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ObvError.invalidServerResponse
        }
        
        guard let returnStatus = ObvServerDownloadMessagesAndListAttachmentsMethod.parseObvServerResponse(responseData: data, flowId: flowId) else {
            assertionFailure()
            throw ObvError.couldNotParseReturnStatusFromServer
        }

        return returnStatus
        
    }
    
    
    private func getCurrentDeviceUidOfOwnedIdentity(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> UID {
        
        if let currentDeviceUID = cacheOfCurrentDeviceUIDForOwnedIdentity[ownedCryptoIdentity] {
            return currentDeviceUID
        }

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

        guard let contextCreator = delegateManager.contextCreator else {
            Self.logger.fault("The context creator is not set")
            assertionFailure()
            throw ObvError.theContextCreatorIsNotSet
        }

        let currentDeviceUID =  try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UID, Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedCryptoIdentity, within: obvContext)
                    continuation.resume(returning: currentDeviceUid)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
        cacheOfCurrentDeviceUIDForOwnedIdentity[ownedCryptoIdentity] = currentDeviceUID

        return currentDeviceUID

    }

    
    
    private func launchProcessingOfUnprocessedMessages(ownedCryptoIdentity: ObvCryptoIdentity, executionReason: ProcessBatchOfUnprocessedMessagesOperation.ExecutionReason, flowId: FlowIdentifier) throws {
        
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
        
        guard let processDownloadedMessageDelegate = delegateManager.processDownloadedMessageDelegate else {
            Self.logger.fault("The processDownloadedMessageDelegate is not set")
            assertionFailure()
            throw ObvError.theProcessDownloadedMessageDelegateIsNotSet
        }
                
        Self.logger.info("[\(flowId.shortDebugDescription)] Queuing a ProcessBatchOfUnprocessedMessagesOperation")
        
        let op1 = ProcessBatchOfUnprocessedMessagesOperation(
            ownedCryptoIdentity: ownedCryptoIdentity,
            executionReason: executionReason,
            notificationDelegate: notificationDelegate,
            processDownloadedMessageDelegate: processDownloadedMessageDelegate,
            inbox: delegateManager.inbox,
            logger: Self.logger,
            flowId: flowId)
        let composedOp = try delegateManager.createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        composedOp.queuePriority = .high
        composedOp.completionBlock = { [weak self] in
            Task { [weak self] in
                guard let self else { return }
                await onCompletionOfProcessBatchOfUnprocessedMessagesOperation(op1, flowId: flowId)
            }
        }

        delegateManager.queueSharedAmongCoordinators.addOperation(composedOp)
        
    }
    
    
    private func onCompletionOfProcessBatchOfUnprocessedMessagesOperation(_ op: ProcessBatchOfUnprocessedMessagesOperation, flowId: FlowIdentifier) async {
        
        guard op.isFinished && !op.isCancelled else {
            let reasonForCancel = op.reasonForCancel
            Self.logger.fault("ProcessBatchOfUnprocessedMessagesOperation failed: \(reasonForCancel)")
            assertionFailure()
            return
        }
        
        guard let delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            Self.logger.fault("The notification delegate is not set")
            assertionFailure()
            return
        }

        let postOperationTasksToPerform = op.postOperationTasksToPerform.sorted()
        
        for postOperationTaskToPerform in postOperationTasksToPerform {
            
            switch postOperationTaskToPerform {
                
            case .batchDeleteAndMarkAsListed(ownedCryptoIdentity: let ownedCryptoIdentity):
                
                Self.logger.debug("[\(flowId.shortDebugDescription)] Will batch delete and mark as listed")
                Task {
                    do {
                        try await delegateManager.batchDeleteAndMarkAsListedDelegate.batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId)
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
                
            case .processInboxAttachmentsOfMessage(let messageId):
                
                Task {
                    do {
                        try await delegateManager.downloadAttachmentChunksDelegate.resumeDownloadOfAttachmentsNotAlreadyDownloading(
                            downloadKind: .allDownloadableAttachmentsWithoutSessionForMessage(messageId: messageId),
                            flowId: flowId)
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
                
            case .downloadExtendedPayload(let messageId):
                
                Task {
                    do {
                        try await downloadExtendedMessagePayload(messageId: messageId, flowId: flowId)
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
                
            case .notifyAboutDecryptedApplicationMessage(messages: let messages, flowId: let flowId):
                
                Self.logger.debug("✉️ [\(flowId.shortDebugDescription)] Notifying about \(messages.count) decrypted application messages")
                ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] Notifying the engine about \(messages.count) decrypted application messages")
                
                ObvNetworkFetchNotificationNew.applicationMessagesDecrypted(messages: messages, flowId: flowId)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
                
            }
            
        }
        
        // If more unprocessed messages remain, loop. Otherwise, it might be a good time to delete old current device's pre-keys within the identity manager in case the last listing we untruncated
        
        assert(op.moreUnprocessedMessagesRemain != nil)
        let moreUnprocessedMessagesRemain = op.moreUnprocessedMessagesRemain ?? false

        if moreUnprocessedMessagesRemain {
            
            do {
                try launchProcessingOfUnprocessedMessages(ownedCryptoIdentity: op.ownedCryptoIdentity, executionReason: op.executionReason, flowId: flowId)
            } catch {
                Self.logger.fault("Could not luanch processing of remaining messages to process")
                return
            }
            
        } else {
            
            switch op.executionReason {
            case .untruncatedListPerformed(downloadTimestampFromServer: let downloadTimestampFromServer):
                ObvNetworkFetchNotificationNew.serverAndInboxContainNoMoreUnprocessedMessages(ownedIdentity: op.ownedCryptoIdentity, downloadTimestampFromServer: downloadTimestampFromServer)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
            default:
                break
            }

        }

    }
    
    
    /// When a message has no attachment, it can be received directely on the websocket. In such a case, the websocket manager calls this method.
    func saveMessageReceivedOnWebsocket(message: ObvServerDownloadMessagesAndListAttachmentsMethod.MessageAndAttachmentsOnServer, downloadTimestampFromServer: Date, ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws {
        
        guard let delegateManager else {
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        let op1 = SaveMessagesAndAttachmentsFromServerOperation(
            ownedIdentity: ownedCryptoId,
            listOfMessageAndAttachmentsOnServer: [message],
            downloadTimestampFromServer: downloadTimestampFromServer,
            localDownloadTimestamp: Date(),
            logger: Self.logger,
            flowId: flowId)
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            throw ObvError.failedSaveMessagesAndAttachmentsFromServer
        }

        // The message received on the websocket was saved, we can request it to be marked as listed on the server.
        // We do this asynchronously.
        
        Task {
            do {
                try await delegateManager.batchDeleteAndMarkAsListedDelegate.markSpecificMessagesAsListed(ownedCryptoId: ownedCryptoId, messageUIDs: [message.messageUidFromServer], flowId: flowId)
            } catch {
                Self.logger.fault("The call to markSpecificMessagesAsListed did fail: \(error.localizedDescription)")
                assertionFailure()
            }
        }

        // We can process the saved message
        
        do {
            let idOfMessageToProcess: ObvMessageIdentifier = .init(ownedCryptoId: .init(cryptoIdentity: ownedCryptoId), uid: message.messageUidFromServer)
            try launchProcessingOfUnprocessedMessages(ownedCryptoIdentity: ownedCryptoId, executionReason: .messageReceivedOnWebSocket(idOfMessageToProcess: idOfMessageToProcess), flowId: flowId)
        } catch {
            assertionFailure(error.localizedDescription)
        }
                
    }
    
    
    func removeExpectedContactForReProcessingOperationThenProcessUnprocessedMessages(expectedContactsThatAreNowContacts: Set<ObvContactIdentifier>, flowId: FlowIdentifier) async throws {
        
        guard !expectedContactsThatAreNowContacts.isEmpty else { return }
        
        guard let delegateManager else {
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        let op1 = RemoveExpectedContactForReProcessingOperation(expectedContactsThatAreNowContacts: expectedContactsThatAreNowContacts)
        try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        
        if op1.didRemoveAtLeastOneExpectedContactForReProcessing {
            for ownedCryptoId in Set(expectedContactsThatAreNowContacts.map(\.ownedCryptoId)) {
                try launchProcessingOfUnprocessedMessages(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, executionReason: .removedExpectedContactOfPreKeyMessage, flowId: flowId)
            }
        }

    }
    
}


// MARK: - Downloading extended payload

extension MessagesCoordinator {
    
    private func downloadExtendedMessagePayload(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) async throws {
        
        Self.logger.debug("[\(flowId.shortDebugDescription)] Call to downloadExtendedMessagePayload for message \(messageId.debugDescription)")

        guard let delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        let sessionToken = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: messageId.ownedCryptoIdentity, currentInvalidToken: nil, flowId: flowId).serverSessionToken

        if let cached = extendedPayloadDownloadTasks[messageId] {
            switch cached {
            case .inProgress(task: let task):
                try await task.value
                return
            }
        }
        
        let task = try createTaskToDownloadAndSaveExtendedMessagePayload(messageId: messageId, sessionToken: sessionToken, delegateManager: delegateManager, flowId: flowId)
                
        do {
            extendedPayloadDownloadTasks[messageId] = .inProgress(task: task)
            try await task.value
            extendedPayloadDownloadTasks.removeValue(forKey: messageId)
        } catch {
            extendedPayloadDownloadTasks.removeValue(forKey: messageId)
            throw error
        }
        
    }
    
    
    private func createTaskToDownloadAndSaveExtendedMessagePayload(messageId: ObvMessageIdentifier, sessionToken: Data, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) throws -> Task<Void, Error> {
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            assertionFailure()
            throw ObvError.theNotificationDelegateIsNotSet
        }
        
        return Task {
            
            guard try await shouldDownloadExtendedPayloadOfMessage(messageId: messageId, delegateManager: delegateManager, flowId: flowId) else { return }
            
            let method = ObvServerDownloadMessageExtendedPayloadMethod(messageId: messageId, token: sessionToken, flowId: flowId)
            method.identityDelegate = delegateManager.identityDelegate
            
            let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ObvError.invalidServerResponse
            }
            
            guard let returnStatus = ObvServerDownloadMessageExtendedPayloadMethod.parseObvServerResponse(responseData: data, using: Self.log) else {
                assertionFailure()
                throw ObvError.couldNotParseReturnStatusFromServer
            }

            let encryptedExtendedMessagePayload: EncryptedData
            
            switch returnStatus {
            case .invalidSession:
                failedAttemptsCounterManager.reset(counter: .downloadOfExtendedMessagePayload(messageId: messageId))
                let newSessionToken = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: messageId.ownedCryptoIdentity, currentInvalidToken: sessionToken, flowId: flowId).serverSessionToken
                let newTask = try createTaskToDownloadAndSaveExtendedMessagePayload(messageId: messageId, sessionToken: newSessionToken, delegateManager: delegateManager, flowId: flowId)
                try await newTask.value
                return
            case .extendedContentUnavailable:
                failedAttemptsCounterManager.reset(counter: .downloadOfExtendedMessagePayload(messageId: messageId))
                return
            case .generalError:
                let delay = failedAttemptsCounterManager.incrementAndGetDelay(.downloadOfExtendedMessagePayload(messageId: messageId))
                os_log("Will retry the call to createTaskToDownloadAndSaveExtendedMessagePayload in %f seconds", log: Self.log, type: .error, Double(delay) / 1000.0)
                await retryManager.waitForDelay(milliseconds: delay)
                let newTask = try createTaskToDownloadAndSaveExtendedMessagePayload(messageId: messageId, sessionToken: sessionToken, delegateManager: delegateManager, flowId: flowId)
                try await newTask.value
                return
            case .ok(let _encryptedExtendedMessagePayload):
                encryptedExtendedMessagePayload = _encryptedExtendedMessagePayload
            }
            
            // If we reach this point, the extended message payload of the message was downloaded from the server and we should save it
            
            let obvMessageOrObvOwnedMessage = try await decryptAndSaveExtendedMessagePayload(messageId: messageId, encryptedExtendedMessagePayload: encryptedExtendedMessagePayload, flowId: flowId)
            
            if let obvMessageOrObvOwnedMessage {
                ObvNetworkFetchNotificationNew.downloadingMessageExtendedPayloadWasPerformed(message: obvMessageOrObvOwnedMessage, flowId: flowId)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
            }

        }
        
    }
    
    
    private func shouldDownloadExtendedPayloadOfMessage(messageId: ObvMessageIdentifier, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) async throws -> Bool {
        
        guard let contextCreator = delegateManager.contextCreator else {
            assertionFailure()
            throw ObvError.theContextCreatorIsNotSet
        }
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    guard let message = try InboxMessage.get(messageId: messageId, within: obvContext) else {
                        return continuation.resume(returning: false)
                    }
                    let shouldDownload = message.hasEncryptedExtendedMessagePayload && (message.extendedMessagePayload == nil) && message.extendedMessagePayloadKey != nil
                    return continuation.resume(returning: shouldDownload)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
}


// MARK: - URLSessionDataDelegate

extension MessagesCoordinator { //}: URLSessionDataDelegate {
    
    /// When receiving an encrypted extended message payload from the server, we call this method to fetch the message from database, use the decryption key to decrypt the
    /// extended payload, and store the decrypted payload back to database
    private func decryptAndSaveExtendedMessagePayload(messageId: ObvMessageIdentifier, encryptedExtendedMessagePayload: EncryptedData, flowId: FlowIdentifier) async throws -> ObvMessageOrObvOwnedMessage? {
        
        guard let delegateManager else {
            Self.logger.fault("The Delegate Manager is not set")
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        let op1 = DecryptAndSaveExtendedMessagePayloadOperation(messageId: messageId, encryptedExtendedMessagePayload: encryptedExtendedMessagePayload, inbox: delegateManager.inbox)
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            throw ObvError.failedDecryptAndSaveExtendedMessagePayload
        }
        
        return op1.obvMessageOrObvOwnedMessage
        
    }
    
}


// MARK: - Errors

extension MessagesCoordinator {
    
    enum ObvError: Error {
        case theDelegateManagerIsNotSet
        case theContextCreatorIsNotSet
        case failedDecryptAndSaveExtendedMessagePayload
        case failedToRemoveExtendedMessagePayload
        case failedSaveMessagesAndAttachmentsFromServer
        case theIdentityDelegateIsNotSet
        case invalidServerResponse
        case couldNotParseReturnStatusFromServer
        case deviceIsNotRegistered
        case theNotificationDelegateIsNotSet
        case theProcessDownloadedMessageDelegateIsNotSet
    }
    
}


// MARK: - Private helpers

fileprivate extension Task<Void, Error> {
    
    var shortDebugDescription: String {
        return "<\(self.hashValue & 0xFF)>"
    }
    
}
