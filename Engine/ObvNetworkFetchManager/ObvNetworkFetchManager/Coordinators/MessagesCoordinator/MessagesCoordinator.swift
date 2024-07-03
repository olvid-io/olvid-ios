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

    weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    private enum ExtendedPayloadDownloadTask {
        case inProgress(task: Task<Void, Error>)
    }
    
    private var extendedPayloadDownloadTasks = [ObvMessageIdentifier: ExtendedPayloadDownloadTask]()
    
    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()

    init(logPrefix: String) {
        let logSubsystem = "\(logPrefix).\(Self.defaultLogSubsystem)"
        Self.log = OSLog(subsystem: logSubsystem, category: Self.logCategory)
    }

    func setDelegateManager(_ delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }

    private var cacheOfCurrentDeviceUIDForOwnedIdentity = [ObvCryptoIdentity: UID]()
    
    private typealias DownloadMessagesTask = Task<Void,Error>
    private typealias PairOfDownloadMessagesTasks = (inProgress: DownloadMessagesTask, next: DownloadMessagesTask?)
    private var cacheOfPairOfServerDownloadMessagesTasks = [ObvCryptoIdentity: PairOfDownloadMessagesTasks]()

}


// MARK: - MessagesDelegate

extension MessagesCoordinator: MessagesDelegate {
    
    func downloadMessagesAndListAttachments(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async {
        
        os_log("[%{public}@] Call to downloadMessagesAndListAttachments for owned identity %{public}@", log: Self.log, type: .debug, flowId.shortDebugDescription, ownedCryptoId.debugDescription)
        defer {
            os_log("[%{public}@] End of the call to downloadMessagesAndListAttachments for owned identity %{public}@", log: Self.log, type: .debug, flowId.shortDebugDescription, ownedCryptoId.debugDescription)
        }
        
        let awaitedTask: DownloadMessagesTask
        
        let pairOfServerDownloadMessagesTasks = cacheOfPairOfServerDownloadMessagesTasks[ownedCryptoId]
        
        var awaitTaskFailed = false
        
        switch pairOfServerDownloadMessagesTasks {
            
        case .none:
            
            awaitedTask = createDownloadMessagesAndListAttachmentsTask(ownedCryptoId: ownedCryptoId, flowId: flowId)
            cacheOfPairOfServerDownloadMessagesTasks[ownedCryptoId] = (awaitedTask, nil)
            os_log("[%{public}@] No existing task found for downloading messages for owned identity %{public}@. We created task %{public}@ will now await for it.", log: Self.log, type: .debug, flowId.shortDebugDescription, ownedCryptoId.debugDescription, awaitedTask.shortDebugDescription)
            do {
                try await awaitedTask.value
            } catch {
                awaitTaskFailed = true
            }
            
        case .some(let pair):
            
            os_log("[%{public}@] A task %{public}@ is already in progress for downloading messages for owned identity %{public}@", log: Self.log, type: .debug, flowId.shortDebugDescription, pair.inProgress.shortDebugDescription, ownedCryptoId.debugDescription)

            if let nextTask = pair.next {
                
                os_log("[%{public}@] No need to create a task for downloading messages for owned identity %{public}@, a next-task %{public}@ already exists", log: Self.log, type: .debug, flowId.shortDebugDescription, ownedCryptoId.debugDescription, nextTask.shortDebugDescription)

                awaitedTask = nextTask

            } else {
                
                awaitedTask = createDownloadMessagesAndListAttachmentsTask(ownedCryptoId: ownedCryptoId, flowId: flowId)
                os_log("[%{public}@] Created the task %{public}@ for downloading messages for owned identity %{public}@", log: Self.log, type: .debug, flowId.shortDebugDescription, awaitedTask.shortDebugDescription, ownedCryptoId.debugDescription)
                cacheOfPairOfServerDownloadMessagesTasks[ownedCryptoId] = (pair.inProgress, awaitedTask)
                
            }
            
            os_log("[%{public}@] Awaiting the end of the previous messages download task %{public}@ for owned identity %{public}@", log: Self.log, type: .debug, flowId.shortDebugDescription, pair.inProgress.shortDebugDescription, ownedCryptoId.debugDescription)

            try? await pair.inProgress.value
            if cacheOfPairOfServerDownloadMessagesTasks[ownedCryptoId]?.next == awaitedTask {
                cacheOfPairOfServerDownloadMessagesTasks[ownedCryptoId] = (awaitedTask, nil)
            }
            
            os_log("[%{public}@] Awaiting the end of messages download task %{public}@ for owned identity %{public}@", log: Self.log, type: .debug, flowId.shortDebugDescription, awaitedTask.shortDebugDescription, ownedCryptoId.debugDescription)

            do {
                try await awaitedTask.value
            } catch {
                awaitTaskFailed = true
            }
            
        }
        
        os_log("[%{public}@] The task %{public}@ for downloading messages for owned identity %{public}@ is finished", log: Self.log, type: .debug, flowId.shortDebugDescription, awaitedTask.shortDebugDescription, ownedCryptoId.debugDescription)

        if let pair = cacheOfPairOfServerDownloadMessagesTasks[ownedCryptoId] {
            if pair.inProgress == awaitedTask {
                if let nextTask = pair.next {
                    cacheOfPairOfServerDownloadMessagesTasks[ownedCryptoId] = (nextTask, nil)
                } else {
                    cacheOfPairOfServerDownloadMessagesTasks.removeValue(forKey: ownedCryptoId)
                }
            } else {
                assert(pair.next != awaitedTask)
            }
        }
        
        if awaitTaskFailed {
            // The delay increase/reset is managed by the DownloadMessagesTask
            let delay = failedAttemptsCounterManager.getCurrentDelay(.downloadMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
            os_log("🖲️ Will retry the call to downloadMessagesAndListAttachments in %f seconds", log: Self.log, type: .error, Double(delay) / 1000.0)
            await retryManager.waitForDelay(milliseconds: delay)
            await downloadMessagesAndListAttachments(ownedCryptoId: ownedCryptoId, flowId: flowId)
        }

    }
    
    
    private func createDownloadMessagesAndListAttachmentsTask(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) -> DownloadMessagesTask {
        return Task {
            
            do {
                try await downloadMessagesAndListAttachments(ownedCryptoId: ownedCryptoId, flowId: flowId, currentInvalidToken: nil)
                failedAttemptsCounterManager.reset(counter: .downloadMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
                os_log("[%{public}@] Call to downloadMessagesAndListAttachments for owned identity %{public}@ was a success", log: Self.log, type: .info, flowId.shortDebugDescription, ownedCryptoId.debugDescription)
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
                _ = failedAttemptsCounterManager.incrementAndGetDelay(.downloadMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
                throw error
            }
            
        }
        
    }
     
    
    private func downloadMessagesAndListAttachments(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier, currentInvalidToken: Data?) async throws {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: Self.log, type: .fault)
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
            identityDelegate: identityDelegate,
            flowId: flowId)

        // The server call has been made, process the returned status
        
        try await processReturnStatusOfObvServerDownloadMessagesAndListAttachmentsMethod(
            serverReturnStatus: serverReturnStatus,
            ownedCryptoId: ownedCryptoId,
            sessionToken: sessionToken,
            flowId: flowId)

    }
    
    
    private func performServerDownloadMessagesAndListAttachmentsMethod(ownedCryptoId: ObvCryptoIdentity, sessionToken: Data, currentDeviceUid: UID, identityDelegate: ObvIdentityDelegate, flowId: FlowIdentifier) async throws -> ObvServerDownloadMessagesAndListAttachmentsMethod.PossibleReturnStatus {
        
        let method = ObvServerDownloadMessagesAndListAttachmentsMethod(
            ownedIdentity: ownedCryptoId,
            token: sessionToken,
            deviceUid: currentDeviceUid,
            toIdentity: ownedCryptoId,
            flowId: flowId)
        method.identityDelegate = identityDelegate

        let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ObvError.invalidServerResponse
        }
        
        guard let returnStatus = ObvServerDownloadMessagesAndListAttachmentsMethod.parseObvServerResponse(responseData: data, using: Self.log, flowId: flowId) else {
            assertionFailure()
            throw ObvError.couldNotParseReturnStatusFromServer
        }

        return returnStatus
        
    }
    
    
    private func processReturnStatusOfObvServerDownloadMessagesAndListAttachmentsMethod(serverReturnStatus: ObvServerDownloadMessagesAndListAttachmentsMethod.PossibleReturnStatus, ownedCryptoId: ObvCryptoIdentity, sessionToken: Data, flowId: FlowIdentifier) async throws {
        
        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        let downloadTimestampFromServer: Date
        let messagesAndAttachmentsOnServer: [ObvServerDownloadMessagesAndListAttachmentsMethod.MessageAndAttachmentsOnServer]
        let isListingTruncated: Bool
        
        switch serverReturnStatus {
            
        case .deviceIsNotRegistered:
            failedAttemptsCounterManager.reset(counter: .downloadMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
            throw ObvError.deviceIsNotRegistered
            
        case .invalidSession:
            failedAttemptsCounterManager.reset(counter: .downloadMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
            try await downloadMessagesAndListAttachments(
                ownedCryptoId: ownedCryptoId,
                flowId: flowId,
                currentInvalidToken: sessionToken)
            return
            
        case .generalError:
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.downloadMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
            os_log("🖲️ Will retry the call to downloadMessagesAndListAttachments in %f seconds", log: Self.log, type: .error, Double(delay) / 1000.0)
            await retryManager.waitForDelay(milliseconds: delay)
            try await downloadMessagesAndListAttachments(
                ownedCryptoId: ownedCryptoId,
                flowId: flowId,
                currentInvalidToken: nil)
            return
            
        case .listingTruncated(let _downloadTimestampFromServer, let _messagesAndAttachmentsOnServer):
            failedAttemptsCounterManager.reset(counter: .downloadMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
            downloadTimestampFromServer = _downloadTimestampFromServer
            messagesAndAttachmentsOnServer = _messagesAndAttachmentsOnServer
            isListingTruncated = true
            
        case .ok(let _downloadTimestampFromServer, let _messagesAndAttachmentsOnServer):
            failedAttemptsCounterManager.reset(counter: .downloadMessagesAndListAttachments(ownedIdentity: ownedCryptoId))
            downloadTimestampFromServer = _downloadTimestampFromServer
            messagesAndAttachmentsOnServer = _messagesAndAttachmentsOnServer
            isListingTruncated = false
            
        }
        
        // If we reach this point, the server returned a proper list of messages and attachments that we can save
                
        let op1 = SaveMessagesAndAttachmentsFromServerOperation(
            ownedIdentity: ownedCryptoId,
            listOfMessageAndAttachmentsOnServer: messagesAndAttachmentsOnServer,
            downloadTimestampFromServer: downloadTimestampFromServer,
            localDownloadTimestamp: Date(),
            log: Self.log)
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            throw ObvError.failedSaveMessagesAndAttachmentsFromServer
        }
        
        let idsOfNewMessages = op1.idsOfNewMessages
        
        os_log("[%{public}@] 🌊 We successfully downloaded %d messages (%d are new) for identity %@. Listing was truncated: %{public}@", log: Self.log, type: .info, flowId.shortDebugDescription, messagesAndAttachmentsOnServer.count, idsOfNewMessages.count, ownedCryptoId.debugDescription, isListingTruncated.description)
        
        // The list of new messages and attachments just received from the server was properly saved, we can new process them.
        // The processing is performed asynchronously, as we want the ``downloadMessagesAndListAttachments(ownedCryptoId:flowId:)`` to return at this point.
        
        Task {
            
            try await processUnprocessedMessages(ownedCryptoIdentity: ownedCryptoId,
                                                 executionReason: isListingTruncated ? .truncatedListPerformed : .untruncatedListPerformed(downloadTimestampFromServer: downloadTimestampFromServer),
                                                 flowId: flowId)
            
            // If the listing was truncated, wait some time (allowing listed messages to be marked as listed) then try to list again.
            
            if isListingTruncated {
                do {
                    try await Task.sleep(for: .init(seconds: Int(ObvConstants.relistDelay)))
                    await downloadMessagesAndListAttachments(ownedCryptoId: ownedCryptoId, flowId: flowId)
                } catch {
                    assertionFailure(error.localizedDescription)
                }
            }
            
        }
        
    }
    
    
    private func getCurrentDeviceUidOfOwnedIdentity(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> UID {
        
        if let currentDeviceUID = cacheOfCurrentDeviceUIDForOwnedIdentity[ownedCryptoIdentity] {
            return currentDeviceUID
        }

        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theIdentityDelegateIsNotSet
        }

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: Self.log, type: .fault)
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

    
    
    private func processUnprocessedMessages(ownedCryptoIdentity: ObvCryptoIdentity, executionReason: ProcessBatchOfUnprocessedMessagesOperation.ExecutionReason, iterationNumber: Int = 0, flowId: FlowIdentifier) async throws {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theNotificationDelegateIsNotSet
        }
        
        guard let processDownloadedMessageDelegate = delegateManager.processDownloadedMessageDelegate else {
            os_log("The processDownloadedMessageDelegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theProcessDownloadedMessageDelegateIsNotSet
        }
        
        let queueForPostingNotifications = delegateManager.queueForPostingNotifications
        
        assert(iterationNumber < 1_000, "May happen if there were many unprocessed messages. But this is unlikely and should be investigated.")
        
        os_log("[%{public}@] Initializing a ProcessBatchOfUnprocessedMessagesOperation (iterationNumber is %d)", log: Self.log, type: .info, flowId.shortDebugDescription, iterationNumber)
        
        let op1 = ProcessBatchOfUnprocessedMessagesOperation(
            ownedCryptoIdentity: ownedCryptoIdentity, 
            executionReason: executionReason,
            queueForPostingNotifications: queueForPostingNotifications,
            notificationDelegate: notificationDelegate,
            processDownloadedMessageDelegate: processDownloadedMessageDelegate,
            inbox: delegateManager.inbox,
            log: Self.log,
            flowId: flowId)
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            os_log("The ProcessBatchOfUnprocessedMessagesOperation cancelled (%{public}@). We could not process unprocessed messages", log: Self.log, type: .fault, op1.reasonForCancel?.localizedDescription ?? "None")
            assertionFailure()
            return
        }

        let postOperationTasksToPerform = op1.postOperationTasksToPerform.sorted()
        Task {
            for postOperationTaskToPerform in postOperationTasksToPerform {
                
                switch postOperationTaskToPerform {
                    
                case .batchDeleteAndMarkAsListed(ownedCryptoIdentity: let ownedCryptoIdentity):
                    
                    os_log("[%{public}@] Will batch delete and mark as listed", log: Self.log, type: .debug, flowId.shortDebugDescription)
                    Task.detached {
                        do {
                            try await delegateManager.batchDeleteAndMarkAsListedDelegate.batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId)
                        } catch {
                            assertionFailure(error.localizedDescription)
                        }
                    }
                    
                case .processInboxAttachmentsOfMessage(let messageId):
                    do {
                        try await delegateManager.downloadAttachmentChunksDelegate.resumeDownloadOfAttachmentsNotAlreadyDownloading(
                            downloadKind: .allDownloadableAttachmentsWithoutSessionForMessage(messageId: messageId),
                            flowId: flowId)
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                    
                case .downloadExtendedPayload(let messageId):
                    do {
                        try await downloadExtendedMessagePayload(messageId: messageId, flowId: flowId)
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                    
                case .notifyAboutDecryptedApplicationMessage(messageId: let messageId, attachmentIds: let attachmentIds, hasEncryptedExtendedMessagePayload: let hasEncryptedExtendedMessagePayload, uploadTimestampFromServer: _, flowId: let flowId):
                    os_log("✉️ [%{public}@] Notifying about a decrypted application message %{public}@", log: Self.log, type: .debug, flowId.shortDebugDescription, messageId.debugDescription)
                    ObvNetworkFetchNotificationNew.applicationMessageDecrypted(messageId: messageId,
                                                                               attachmentIds: attachmentIds,
                                                                               hasEncryptedExtendedMessagePayload: hasEncryptedExtendedMessagePayload,
                                                                               flowId: flowId)
                    .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)
                    
                case .downloadMessagesAndListAttachments(ownedCryptoIdentity: let ownedCryptoIdentity):
                    Task.detached { [weak self] in
                        await self?.downloadMessagesAndListAttachments(ownedCryptoId: ownedCryptoIdentity, flowId: flowId)
                    }
                                        
                }
                
            }
        }
        
        // If more unprocessed messages remain, loop. Otherwise, it might be a good time to delete old current device's pre-keys within the identity manager in case the last listing we untruncated
        
        assert(op1.moreUnprocessedMessagesRemain != nil)
        let moreUnprocessedMessagesRemain = op1.moreUnprocessedMessagesRemain ?? false

        if moreUnprocessedMessagesRemain {
            
            try await processUnprocessedMessages(ownedCryptoIdentity: ownedCryptoIdentity, executionReason: executionReason, iterationNumber: iterationNumber + 1, flowId: flowId)
            
        } else {
            
            switch executionReason {
            case .untruncatedListPerformed(downloadTimestampFromServer: let downloadTimestampFromServer):
                ObvNetworkFetchNotificationNew.serverAndInboxContainNoMoreUnprocessedMessages(ownedIdentity: ownedCryptoIdentity, downloadTimestampFromServer: downloadTimestampFromServer)
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
        
        let messagesAndAttachmentsOnServer = [message]
        
        let op1 = SaveMessagesAndAttachmentsFromServerOperation(
            ownedIdentity: ownedCryptoId,
            listOfMessageAndAttachmentsOnServer: messagesAndAttachmentsOnServer,
            downloadTimestampFromServer: downloadTimestampFromServer,
            localDownloadTimestamp: Date(),
            log: Self.log)
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            throw ObvError.failedSaveMessagesAndAttachmentsFromServer
        }

        Task {
            do {
                try await processUnprocessedMessages(ownedCryptoIdentity: ownedCryptoId, executionReason: .messageReceivedOnWebSocket, flowId: flowId)
            } catch {
                assertionFailure(error.localizedDescription)
            }
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
                try await processUnprocessedMessages(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, executionReason: .removedExpectedContactOfPreKeyMessage, flowId: flowId)
            }
        }

    }
    
}


// MARK: - Downloading extended payload

extension MessagesCoordinator {
    
    private func downloadExtendedMessagePayload(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) async throws {
        
        os_log("Call to downloadExtendedMessagePayload for message %{public}@ with flow id %{public}@", log: Self.log, type: .debug, messageId.debugDescription, flowId.shortDebugDescription)

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
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
            
            try await decryptAndSaveExtendedMessagePayload(messageId: messageId, encryptedExtendedMessagePayload: encryptedExtendedMessagePayload, flowId: flowId)
            
            ObvNetworkFetchNotificationNew.downloadingMessageExtendedPayloadWasPerformed(messageId: messageId, flowId: flowId)
                .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)

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
    private func decryptAndSaveExtendedMessagePayload(messageId: ObvMessageIdentifier, encryptedExtendedMessagePayload: EncryptedData, flowId: FlowIdentifier) async throws {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        let op1 = DecryptAndSaveExtendedMessagePayloadOperation(messageId: messageId, encryptedExtendedMessagePayload: encryptedExtendedMessagePayload)
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            throw ObvError.failedDecryptAndSaveExtendedMessagePayload
        }
        
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
