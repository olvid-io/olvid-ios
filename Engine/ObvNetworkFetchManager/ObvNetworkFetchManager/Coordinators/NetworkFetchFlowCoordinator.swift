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
import ObvCrypto
import ObvTypes
import ObvMetaManager
import ObvEncoder
import Network
import OlvidUtils


final class NetworkFetchFlowCoordinator: NetworkFetchFlowDelegate, ObvErrorMaker {

    fileprivate let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "NetworkFetchFlowCoordinator"
    
    private let queueForPostingNotifications = DispatchQueue(label: "NetworkFetchFlowCoordinator queue for notifications")
    private let internalQueue = OperationQueue.createSerialQueue(name: "NetworkFetchFlowCoordinator internal operation queue")

    weak var delegateManager: ObvNetworkFetchDelegateManager? {
        didSet {
            pollingWorker.delegateManager = delegateManager
        }
    }
    
    static let errorDomain = "NetworkFetchFlowCoordinator"

    let pollingWorker = PollingWorker()
    
    // The `downloadAttachment` counter is used in `DownloadAttachmentChunksCoordinator`
    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()
    private let prng: PRNGService

    init(prng: PRNGService) {
        self.prng = prng
        monitorNetworkChanges()
    }
    
    private var nwPathMonitor: AnyObject? // Actually an NWPathMonitor, but this is only available since iOS 12 and since we support iOS 11, we cannot specify the type
}


// MARK: - NetworkFetchFlowDelegate

extension NetworkFetchFlowCoordinator {
    
    func updatedListOfOwnedIdentites(ownedIdentities: Set<ObvCryptoIdentity>, flowId: FlowIdentifier) {
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        delegateManager.wellKnownCacheDelegate.updatedListOfOwnedIdentites(ownedIdentities: ownedIdentities, flowId: flowId)
        delegateManager.webSocketDelegate.updatedListOfOwnedIdentites(ownedIdentities: ownedIdentities, flowId: flowId)
    }
    
    // MARK: - Session's Challenge/Response/Token related methods
    
    func resetServerSession(for identity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        try ServerSession.deleteAllSessionsOfIdentity(identity, within: obvContext)
        try obvContext.addContextDidSaveCompletionHandler { [weak self] (error) in
            guard error == nil else { return }
            try? self?.serverSessionRequired(for: identity, flowId: obvContext.flowId)
        }
    }
    
    func serverSessionRequired(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) throws {
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        failedAttemptsCounterManager.reset(counter: .sessionCreation(ownedIdentity: identity))
        
        try delegateManager.getAndSolveChallengeDelegate.getAndSolveChallenge(forIdentity: identity,
                                                                              currentInvalidToken: nil,
                                                                              discardExistingToken: false,
                                                                              flowId: flowId)
    }
    
    
    func serverSession(of identity: ObvCryptoIdentity, hasInvalidToken invalidToken: Data, flowId: FlowIdentifier) throws {
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        failedAttemptsCounterManager.reset(counter: .sessionCreation(ownedIdentity: identity))
        try delegateManager.getAndSolveChallengeDelegate.getAndSolveChallenge(forIdentity: identity,
                                                                              currentInvalidToken: invalidToken,
                                                                              discardExistingToken: false,
                                                                              flowId: flowId)
    }
    

    func getAndSolveChallengeWasNotNeeded(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        // We do nothing
    }
    
    
    func failedToGetOrSolveChallenge(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        let delay = failedAttemptsCounterManager.incrementAndGetDelay(.sessionCreation(ownedIdentity: identity))
        retryManager.executeWithDelay(delay) { [weak self] in
            try? self?.delegateManager?.getAndSolveChallengeDelegate.getAndSolveChallenge(forIdentity: identity,
                                                                                          currentInvalidToken: nil,
                                                                                          discardExistingToken: false,
                                                                                          flowId: flowId)
        }
    }
    
    
    func newChallengeResponse(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) throws {
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        failedAttemptsCounterManager.reset(counter: .sessionCreation(ownedIdentity: identity))
        try delegateManager.getTokenDelegate.getToken(for: identity, flowId: flowId)
    }

    
    func getTokenWasNotNeeded(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        // We do nothing
    }

    
    func failedToGetToken(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        let delay = failedAttemptsCounterManager.incrementAndGetDelay(.sessionCreation(ownedIdentity: identity))
        retryManager.executeWithDelay(delay) { [weak self] in
            try? self?.delegateManager?.getTokenDelegate.getToken(for: identity, flowId: flowId)
        }
    }
    
    
    func newToken(_ token: Data, for identity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            return
        }

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        failedAttemptsCounterManager.reset(counter: .sessionCreation(ownedIdentity: identity))
        
        contextCreator.performBackgroundTask(flowId: flowId) { (obvContext) in
            
            // We process any pending receipt validation and any pending Free trial query
            delegateManager.verifyReceiptDelegate?.verifyReceiptsExpectingNewSesssion()
            delegateManager.freeTrialQueryDelegate?.processFreeTrialQueriesExpectingNewSession()
            
            // We relaunch incomplete attachments
            delegateManager.downloadAttachmentChunksDelegate.resumeMissingAttachmentDownloads(flowId: flowId)

            // We relaunch pending server queries
            delegateManager.serverQueryDelegate.postAllPendingServerQuery(for: identity, flowId: flowId)
            // We relaunch user data cleaning
            delegateManager.serverUserDataDelegate.cleanUserData(flowId: flowId)

            // We download new messages and list their attachments
            do {
                let deviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(identity, within: obvContext)
                delegateManager.messagesDelegate.downloadMessagesAndListAttachments(for: identity, andDeviceUid: deviceUid, flowId: flowId)
            } catch {
                os_log("Could not call downloadMessagesAndListAttachments", log: log, type: .fault)
            }
            
            // We re-subscribe to push notifications
            do {
                let pushNotifications = RegisteredPushNotification.getAllSortedByCreationDate(for: identity, delegateManager: delegateManager, within: obvContext)
                pushNotifications?.forEach { (pushNotification) in
                    do {
                        try delegateManager.processRegisteredPushNotificationsDelegate.process(forIdentity: pushNotification.cryptoIdentity, withDeviceUid: pushNotification.deviceUid, flowId: flowId)
                    } catch {
                        os_log("Call to processRegisteredPushNotificationsDelegate.process did fail", log: log, type: .fault)
                        assertionFailure()
                    }
                }
            }
            
            // We pass the token to the WebSocket coordinator
            do {
                delegateManager.webSocketDelegate.setServerSessionToken(to: token, for: identity)
            }
        }
        
    }
        
    func newAPIKeyElementsForAPIKey(serverURL: URL, apiKey: UUID, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        ObvNetworkFetchNotificationNew.newAPIKeyElementsForAPIKey(serverURL: serverURL,
                                                                  apiKey: apiKey,
                                                                  apiKeyStatus: apiKeyStatus,
                                                                  apiPermissions: apiPermissions,
                                                                  apiKeyExpirationDate: apiKeyExpirationDate)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }
    
    
    func apiKeyStatusQueryFailed(ownedIdentity: ObvCryptoIdentity, apiKey: UUID) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        ObvNetworkFetchNotificationNew.apiKeyStatusQueryFailed(ownedIdentity: ownedIdentity, apiKey: apiKey)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }
    
    
    func verifyReceipt(ownedIdentity: ObvCryptoIdentity, receiptData: String, transactionIdentifier: String, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let verifyReceiptDelegate = delegateManager.verifyReceiptDelegate else {
            os_log("The verifyReceiptDelegate delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        verifyReceiptDelegate.verifyReceipt(ownedIdentity: ownedIdentity, receiptData: receiptData, transactionIdentifier: transactionIdentifier, flowId: flowId)
        
    }

    func newAPIKeyElementsForCurrentAPIKeyOf(_ ownedIdentity: ObvCryptoIdentity, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        ObvNetworkFetchNotificationNew.newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(ownedIdentity: ownedIdentity,
                                                                                        apiKeyStatus: apiKeyStatus,
                                                                                        apiPermissions: apiPermissions,
                                                                                        apiKeyExpirationDate: apiKeyExpirationDate)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }
    
    
    func newFreeTrialAPIKeyForOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        ObvNetworkFetchNotificationNew.newFreeTrialAPIKeyForOwnedIdentity(ownedIdentity: ownedIdentity, apiKey: apiKey, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)
    }
    
    
    func noMoreFreeTrialAPIKeyAvailableForOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        ObvNetworkFetchNotificationNew.noMoreFreeTrialAPIKeyAvailableForOwnedIdentity(ownedIdentity: ownedIdentity, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)
    }
    
    
    func freeTrialIsStillAvailableForOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        ObvNetworkFetchNotificationNew.freeTrialIsStillAvailableForOwnedIdentity(ownedIdentity: ownedIdentity, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)
    }

    
    // MARK: - Downloading message and listing attachments

    func downloadingMessagesAndListingAttachmentFailed(for identity: ObvCryptoIdentity, andDeviceUid deviceUid: UID, flowId: FlowIdentifier) {
        let delay = failedAttemptsCounterManager.incrementAndGetDelay(.downloadMessagesAndListAttachments(ownedIdentity: identity))
        retryManager.executeWithDelay(delay) { [weak self] in
            self?.delegateManager?.messagesDelegate.downloadMessagesAndListAttachments(for: identity, andDeviceUid: deviceUid, flowId: flowId)
        }
    }
    
    
    func downloadingMessagesAndListingAttachmentWasNotNeeded(for identity: ObvCryptoIdentity, andDeviceUid deviceUid: UID, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        // Although we did not find any new message on the server, we might still have unprocessed messages to process.

        os_log("Downloading messages was not needed. We still try to process (old) unprocessed messages", log: log, type: .info)
        processUnprocessedMessages(flowId: flowId)

    }
    
    
    func downloadingMessagesAndListingAttachmentWasPerformed(for identity: ObvCryptoIdentity, andDeviceUid uid: UID, flowId: FlowIdentifier) {
        failedAttemptsCounterManager.reset(counter: .downloadMessagesAndListAttachments(ownedIdentity: identity))
        processUnprocessedMessages(flowId: flowId)
        pollingWorker.pollingIfRequired(for: identity, withDeviceUid: uid, flowId: flowId)
    }
    
    
    func aMessageReceivedThroughTheWebsocketWasSavedByTheMessageDelegate(flowId: FlowIdentifier) {
        processUnprocessedMessages(flowId: flowId)
    }
    
    
    func processUnprocessedMessages(flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        os_log("Processing unprocessed messages within flow %{public}@", log: log, type: .debug, flowId.debugDescription)

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            return
        }
        
        guard let processDownloadedMessageDelegate = delegateManager.processDownloadedMessageDelegate else {
            os_log("The processDownloadedMessageDelegate is not set", log: log, type: .fault)
            return
        }
        
        var moreUnprocessedMessagesRemain = true
        var maxNumberOfOperations = 1_000
        
        while moreUnprocessedMessagesRemain && maxNumberOfOperations > 0 {
            
            maxNumberOfOperations -= 1
            assert(maxNumberOfOperations > 0, "May happen if there were many unprocessed messages. But this is unlikely and should be investigated.")
            
            let op1 = ProcessBatchOfUnprocessedMessagesOperation(queueForPostingNotifications: queueForPostingNotifications,
                                                                 notificationDelegate: notificationDelegate,
                                                                 processDownloadedMessageDelegate: processDownloadedMessageDelegate,
                                                                 log: log)
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: contextCreator, log: log, flowId: flowId)
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
            if composedOp.isCancelled {
                assertionFailure(composedOp.reasonForCancel.debugDescription)
                moreUnprocessedMessagesRemain = false
            } else {
                moreUnprocessedMessagesRemain = op1.moreUnprocessedMessagesRemain ?? false
            }
            
        }
        
    }
    

    func messagePayloadAndFromIdentityWereSet(messageId: MessageIdentifier, attachmentIds: [AttachmentIdentifier], hasEncryptedExtendedMessagePayload: Bool, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }
        
        ObvNetworkFetchNotificationNew.applicationMessageDecrypted(messageId: messageId,
                                                                   attachmentIds: attachmentIds,
                                                                   hasEncryptedExtendedMessagePayload: hasEncryptedExtendedMessagePayload,
                                                                   flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)
    }
    
    
    // MARK: - Message's extended content related methods
    
    func downloadingMessageExtendedPayloadFailed(messageId: MessageIdentifier, flowId: FlowIdentifier) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        ObvNetworkFetchNotificationNew.downloadingMessageExtendedPayloadFailed(messageId: messageId, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }
    
    
    func downloadingMessageExtendedPayloadWasPerformed(messageId: MessageIdentifier, extendedMessagePayload: Data, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        ObvNetworkFetchNotificationNew.downloadingMessageExtendedPayloadWasPerformed(messageId: messageId, extendedMessagePayload: extendedMessagePayload, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }

    
    // MARK: - Attachment's related methods
    
    func resumeDownloadOfAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        delegateManager.downloadAttachmentChunksDelegate.resumeDownloadOfAttachment(attachmentId: attachmentId, flowId: flowId)
        
    }

    
    func pauseDownloadOfAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        delegateManager.downloadAttachmentChunksDelegate.pauseDownloadOfAttachment(attachmentId: attachmentId, flowId: flowId)
        
    }
    
    func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async throws -> [AttachmentIdentifier: Float] {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            throw Self.makeError(message: "The Delegate Manager is not set")
        }
        
        return await delegateManager.downloadAttachmentChunksDelegate.requestDownloadAttachmentProgressesUpdatedSince(date: date)
        
    }

    func attachmentWasCancelledByServer(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }
        
        ObvNetworkFetchNotificationNew.inboxAttachmentDownloadCancelledByServer(attachmentId: attachmentId, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }

    func downloadedAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }
        ObvNetworkFetchNotificationNew.inboxAttachmentWasDownloaded(attachmentId: attachmentId, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }
        

    // MARK: - Deletion related methods

    /// Called when a `PendingDeleteFromServer` was just created in DB. This also means that the message and its attachments have been deleted
    /// from the local inbox.
    func newPendingDeleteToProcessForMessage(messageId: MessageIdentifier, flowId: FlowIdentifier) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        do {
            try delegateManager.deleteMessageAndAttachmentsFromServerDelegate.processPendingDeleteFromServer(messageId: messageId, flowId: flowId)
        } catch {
            os_log("Could not process pending delete from server", log: log, type: .fault)
            assertionFailure()
            return
        }
        
    }

    
    func failedToProcessPendingDeleteFromServer(messageId: MessageIdentifier, flowId: FlowIdentifier) {
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        os_log("We could not delete message %{public}@ within flow %{public}@", log: log, type: .fault, messageId.debugDescription, flowId.debugDescription)
        let delay = failedAttemptsCounterManager.incrementAndGetDelay(.processPendingDeleteFromServer(messageId: messageId))
        retryManager.executeWithDelay(delay) {
            try? delegateManager.deleteMessageAndAttachmentsFromServerDelegate.processPendingDeleteFromServer(messageId: messageId, flowId: flowId)
        }
    }


    func messageAndAttachmentsWereDeletedFromServerAndInboxes(messageId: MessageIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }
        
        let NotificationType = ObvNetworkFetchNotification.InboxMessageDeletedFromServerAndInboxes.self
        let userInfo = [NotificationType.Key.messageId: messageId,
                        NotificationType.Key.flowId: flowId] as [String: Any]
        notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
    }

    
    // MARK: - Push notification's related methods

    func newRegisteredPushNotificationToProcess(for identity: ObvCryptoIdentity, withDeviceUid uid: UID, flowId: FlowIdentifier) throws {
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        failedAttemptsCounterManager.reset(counter: .registerPushNotification(ownedIdentity: identity))
        try delegateManager.processRegisteredPushNotificationsDelegate.process(forIdentity: identity, withDeviceUid: uid, flowId: flowId)
                
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            assert(false)
            return
        }
        
        contextCreator.performBackgroundTask(flowId: flowId) { (obvContext) in

            guard let serverSession = try? ServerSession.getToken(within: obvContext, forIdentity: identity) else {
                os_log("Could not set the WebSocket server session since none can be found in DB for the given identity.", log: log, type: .error)
                return
            }
            
            delegateManager.webSocketDelegate.setServerSessionToken(to: serverSession, for: identity)
            
        }
    }


    func failedToProcessRegisteredPushNotification(for identity: ObvCryptoIdentity, withDeviceUid deviceUid: UID, flowId: FlowIdentifier) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        let delay = failedAttemptsCounterManager.incrementAndGetDelay(.registerPushNotification(ownedIdentity: identity))
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        retryManager.executeWithDelay(delay) { [weak self] in
            do {
                try self?.delegateManager?.processRegisteredPushNotificationsDelegate.process(forIdentity: identity, withDeviceUid: deviceUid, flowId: flowId)
            } catch {
                os_log("Failed to process registered push notification", log: log, type: .fault)
                assertionFailure()
            }
        }
    }

    
    func pollingRequested(for identity: ObvCryptoIdentity, withDeviceUid deviceUid: UID, andPollingIdentifier pollingIdentifier: UUID, flowId: FlowIdentifier) {
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        os_log("Polling requested for identity %{public}@", log: log, type: .debug, identity.debugDescription)
        pollingWorker.pollingRequested(for: identity, withPollingIdentifier: pollingIdentifier)
        pollingWorker.pollingIfRequired(for: identity, withDeviceUid: deviceUid, flowId: flowId)
        // When polling is requested, we immediately download messages and list attachments. We do this once.
        os_log("Since polling was requested, we perform an initial downloadMessagesAndListAttachmentsDelegate for identity %{public}@", log: log, type: .debug, identity.debugDescription)
        delegateManager.messagesDelegate.downloadMessagesAndListAttachments(for: identity, andDeviceUid: deviceUid, flowId: flowId)
    }


    func serverReportedThatAnotherDeviceIsAlreadyRegistered(forOwnedIdentity ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)

        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        // Post a serverReportedThatAnotherDeviceIsAlreadyRegistered notification (this will allow the identity manager to deactiviate the owned identity)
        ObvNetworkFetchNotificationNew.serverReportedThatAnotherDeviceIsAlreadyRegistered(ownedIdentity: ownedIdentity, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }
    
    func serverReportedThatThisDeviceWasSuccessfullyRegistered(forOwnedIdentity ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {

        let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)

        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }
        
        ObvNetworkFetchNotificationNew.serverReportedThatThisDeviceWasSuccessfullyRegistered(ownedIdentity: ownedIdentity, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)
        
        // We might have missed push notifications during the registration process, so we list and download messages now
                
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            return
        }

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        contextCreator.performBackgroundTask(flowId: flowId) { (obvContext) in
            
            // We relaunch incomplete attachments
            delegateManager.downloadAttachmentChunksDelegate.resumeMissingAttachmentDownloads(flowId: flowId)
            
            guard let identities = try? identityDelegate.getOwnedIdentities(within: obvContext) else {
                os_log("Could not get owned identities", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            // We download new messages and list their attachments
            for identity in identities {
                do {
                    let deviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(identity, within: obvContext)
                    delegateManager.messagesDelegate.downloadMessagesAndListAttachments(for: identity, andDeviceUid: deviceUid, flowId: flowId)
                } catch {
                    os_log("Could not call downloadMessagesAndListAttachments", log: log, type: .fault)
                }
            }

        }
    }

    
    func serverReportedThatThisDeviceIsNotRegistered(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
     
        let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)

        os_log("We need to re-register to push notifications since the server reported that this device is not registered", log: log, type: .info)

        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        ObvNetworkFetchNotificationNew.serverRequiresThisDeviceToRegisterToPushNotifications(ownedIdentity: ownedIdentity, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }
    
    
    func fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
        
        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }
        
        ObvNetworkFetchNotificationNew.fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ownedIdentity, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }

    // MARK: - Handling Server Queries

    func post(_ serverQuery: ServerQuery, within context: ObvContext) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The delegate manager is not set", log: log, type: .fault)
            return
        }

        _ = PendingServerQuery(serverQuery: serverQuery, delegateManager: delegateManager, within: context)

    }


    func newPendingServerQueryToProcessWithObjectId(_ pendingServerQueryObjectId: NSManagedObjectID, flowId: FlowIdentifier) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        delegateManager.serverQueryDelegate.postServerQuery(withObjectId: pendingServerQueryObjectId, flowId: flowId)

    }


    func failedToProcessServerQuery(withObjectId objectId: NSManagedObjectID, flowId: FlowIdentifier) {
        let delay = failedAttemptsCounterManager.incrementAndGetDelay(.serverQuery(objectID: objectId))
        retryManager.executeWithDelay(delay) { [weak self] in
            self?.delegateManager?.serverQueryDelegate.postServerQuery(withObjectId: objectId, flowId: flowId)
        }
    }


    func successfullProcessOfServerQuery(withObjectId objectId: NSManagedObjectID, flowId: FlowIdentifier) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The Context Creator is not set", log: log, type: .fault)
            return
        }

        guard let channelDelegate = delegateManager.channelDelegate else {
            os_log("The channel delegate is not set", log: log, type: .fault)
            return
        }

        failedAttemptsCounterManager.reset(counter: .serverQuery(objectID: objectId))

        let prng = self.prng
        contextCreator.performBackgroundTask(flowId: flowId) { (obvContext) in

            let serverQuery: PendingServerQuery
            do {
                serverQuery = try PendingServerQuery.get(objectId: objectId, delegateManager: delegateManager, within: obvContext)
            } catch {
                os_log("Could not find pending server query in database", log: log, type: .fault)
                return
            }

            guard let serverResponseType = serverQuery.responseType else {
                os_log("The server response type is not set", log: log, type: .fault)
                return
            }

            let channelServerResponseType: ObvChannelServerResponseMessageToSend.ResponseType
            switch serverResponseType {
            case .deviceDiscovery(of: let contactIdentity, deviceUids: let deviceUids):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.deviceDiscovery(of: contactIdentity, deviceUids: deviceUids)
            case .putUserData:
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.putUserData
            case .getUserData(of: let contactIdentity, userDataPath: let userDataPath):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.getUserData(of: contactIdentity, userDataPath: userDataPath)
            case .checkKeycloakRevocation(verificationSuccessful: let verificationSuccessful):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.checkKeycloakRevocation(verificationSuccessful: verificationSuccessful)
            }

            let aResponseMessageShouldBePosted: Bool
            if let listOfEncoded = [ObvEncoded](serverQuery.encodedElements), listOfEncoded.count == 0 {
                // This server query was built in ServerUserDataCoordinator#urlSession(session, task, ...) and not from a protocol, a response is not expected.
                // This happens, e.g., when refreshing an owned profile picture that expired on the server. In that case, we know there is no ongoing protocol to notify.
                aResponseMessageShouldBePosted = false
            } else {
                // This happens when the server query was created by a protocol. We need notify this protocol that it can now proceed.
                aResponseMessageShouldBePosted = true
            }

            if aResponseMessageShouldBePosted {
                let serverTimestamp = Date()
                let responseMessage = ObvChannelServerResponseMessageToSend(toOwnedIdentity: serverQuery.ownedIdentity,
                                                                            serverTimestamp: serverTimestamp,
                                                                            responseType: channelServerResponseType,
                                                                            encodedElements: serverQuery.encodedElements,
                                                                            flowId: flowId)

                do {
                    _ = try channelDelegate.post(responseMessage, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not process response to server query", log: log, type: .fault)
                    return
                }
            }

            serverQuery.delete(flowId: flowId)

            try? obvContext.save(logOnFailure: log)

        }

    }


    func pendingServerQueryWasDeletedFromDatabase(objectId: NSManagedObjectID, flowId: FlowIdentifier) {

    }

    // MARK: Handling with user data

    func failedToProcessServerUserData(input: ServerUserDataInput, flowId: FlowIdentifier) {
        let delay = failedAttemptsCounterManager.incrementAndGetDelay(.serverUserData(input: input))
        retryManager.executeWithDelay(delay) { [weak self] in
            self?.delegateManager?.serverUserDataDelegate.postUserData(input: input, flowId: flowId)
        }
    }

    // MARK: - Forwarding urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) and notifying successfull/failed listing (for performing fetchCompletionHandlers within the engine)

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    }

    // MARK: - Monitor Network Path Status
    
    private func monitorNetworkChanges() {
        nwPathMonitor = NWPathMonitor()
        (nwPathMonitor as? NWPathMonitor)?.start(queue: DispatchQueue(label: "NetworkFetchMonitor"))
        (nwPathMonitor as? NWPathMonitor)?.pathUpdateHandler = self.networkPathDidChange
    }

    
    private func networkPathDidChange(nwPath: NWPath) {
        // The nwPath status changes very early during the network status change. This is the reason why we wait before trying to reconnect. This is not bullet proof though, as the `networkPathDidChange` method does not seem to be called at every network change... This is unfortunate. Last but not least, it is very hard to work with nwPath.status so we don't even look at it.
        DispatchQueue(label: "Queue dispatching work on network change").async { [weak self] in
            self?.delegateManager?.webSocketDelegate.reconnectAll()
            self?.resetAllFailedFetchAttempsCountersAndRetryFetching()
        }
    }

    
    func resetAllFailedFetchAttempsCountersAndRetryFetching() {
        failedAttemptsCounterManager.resetAll()
        retryManager.executeAllWithNoDelay()
    }

    
    // MARK: - Reacting to changes within the WellKnownCoordinator
    
    func newWellKnownWasCached(server: URL, newWellKnownJSON: WellKnownJSON, flowId: FlowIdentifier) {
        
        failedAttemptsCounterManager.reset(counter: .queryServerWellKnown(serverURL: server))

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        os_log("New well known was cached", log: log, type: .info)

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            return
        }

        
        var ownedIdentitiesOnServer = Set<ObvCryptoIdentity>()
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { obvContext in
            if let allOwnedIdentities = try? identityDelegate.getOwnedIdentities(within: obvContext) {
                ownedIdentitiesOnServer = allOwnedIdentities.filter({ $0.serverURL == server })
            } else {
                assertionFailure()
            }
        }

        for ownedIdentity in ownedIdentitiesOnServer {
            delegateManager.webSocketDelegate.setWebSocketServerURL(to: newWellKnownJSON.serverConfig.webSocketURL, for: ownedIdentity)
        }

        // On Android, this notification is not sent when `wellKnownHasBeenUpdated` is sent. But we agreed with Matthieu that this is better ;-)
        ObvNetworkFetchNotificationNew.wellKnownHasBeenDownloaded(serverURL: server, appInfo: newWellKnownJSON.appInfo, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }
    
    
    func cachedWellKnownWasUpdated(server: URL, newWellKnownJSON: WellKnownJSON, flowId: FlowIdentifier) {

        failedAttemptsCounterManager.reset(counter: .queryServerWellKnown(serverURL: server))
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        delegateManager.webSocketDelegate.updateWebSocketServerURL(for: server, to: newWellKnownJSON.serverConfig.webSocketURL)

        ObvNetworkFetchNotificationNew.wellKnownHasBeenUpdated(serverURL: server, appInfo: newWellKnownJSON.appInfo, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

        
    }
    
    
    func currentCachedWellKnownCorrespondToThatOnServer(server: URL, wellKnownJSON: WellKnownJSON, flowId: FlowIdentifier) {
        
        failedAttemptsCounterManager.reset(counter: .queryServerWellKnown(serverURL: server))

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        ObvNetworkFetchNotificationNew.wellKnownHasBeenDownloaded(serverURL: server, appInfo: wellKnownJSON.appInfo, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }
    
    
    func failedToQueryServerWellKnown(serverURL: URL, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        let delay = failedAttemptsCounterManager.incrementAndGetDelay(.queryServerWellKnown(serverURL: serverURL))
        retryManager.executeWithDelay(delay) {
            delegateManager.wellKnownCacheDelegate.queryServerWellKnown(serverURL: serverURL, flowId: flowId)
        }
                
    }
    
    
    // MARK: - Reacting to web socket changes
    
    func successfulWebSocketRegistration(identity: ObvCryptoIdentity, deviceUid: UID) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        let flowId = FlowIdentifier()
        
        delegateManager.messagesDelegate.downloadMessagesAndListAttachments(for: identity, andDeviceUid: deviceUid, flowId: flowId)
    }

}
