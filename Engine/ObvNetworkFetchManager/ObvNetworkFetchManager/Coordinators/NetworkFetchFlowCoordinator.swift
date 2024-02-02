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
import ObvCrypto
import ObvTypes
import ObvMetaManager
import ObvEncoder
import Network
import OlvidUtils
import ObvServerInterface


final class NetworkFetchFlowCoordinator: NetworkFetchFlowDelegate, ObvErrorMaker {

    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "NetworkFetchFlowCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)

    private let queueForPostingNotifications = DispatchQueue(label: "NetworkFetchFlowCoordinator queue for notifications")
    private let internalQueue = OperationQueue.createSerialQueue(name: "NetworkFetchFlowCoordinator internal operation queue")
    private let syncQueue = DispatchQueue(label: "NetworkFetchFlowCoordinator internal queue")
    private let nwPathMonitor = NWPathMonitor()

    weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    static let errorDomain = "NetworkFetchFlowCoordinator"

    // let pollingWorker = PollingWorker()
    
    // The `downloadAttachment` counter is used in `DownloadAttachmentChunksCoordinator`
    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()
    private let prng: PRNGService

    init(prng: PRNGService, logPrefix: String) {
        self.prng = prng
        let logSubsystem = "\(logPrefix).\(Self.defaultLogSubsystem)"
        Self.log = OSLog(subsystem: logSubsystem, category: Self.logCategory)
        monitorNetworkChanges()
    }
    
}


// MARK: - NetworkFetchFlowDelegate

extension NetworkFetchFlowCoordinator {
    
    func updatedListOfOwnedIdentites(ownedIdentities: Set<ObvCryptoIdentity>, flowId: FlowIdentifier) {
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        delegateManager.wellKnownCacheDelegate.updatedListOfOwnedIdentites(ownedIdentities: ownedIdentities, flowId: flowId)
        Task {
            await delegateManager.webSocketDelegate.updateListOfOwnedIdentites(ownedIdentities: ownedIdentities, flowId: flowId)
        }
    }
    
    // MARK: - Session's Challenge/Response/Token related methods
    
    func refreshAPIPermissions(of ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> APIKeyElements {

        guard let delegateManager else {
            assertionFailure()
            throw Self.makeError(message: "The delegate manager is not set")
        }

        try await delegateManager.serverSessionDelegate.deleteServerSession(of: ownedCryptoIdentity, flowId: flowId)

        let (_, apiKeyElements) = try await getValidServerSessionToken(for: ownedCryptoIdentity, currentInvalidToken: nil, flowId: flowId)
        
        return apiKeyElements
        
    }
    
    
    func getValidServerSessionToken(for ownedCryptoIdentity: ObvCryptoIdentity, currentInvalidToken: Data?, flowId: FlowIdentifier) async throws -> (serverSessionToken: Data, apiKeyElements: APIKeyElements) {
        guard let delegateManager else {
            assertionFailure()
            throw Self.makeError(message: "The delegate manager is not set")
        }
        let (serverSessionToken, apiKeyElements) = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: ownedCryptoIdentity, currentInvalidToken: currentInvalidToken, flowId: flowId)
        
        newToken(serverSessionToken, for: ownedCryptoIdentity, flowId: flowId)
        newAPIKeyElementsForCurrentAPIKeyOf(ownedCryptoIdentity, apiKeyStatus: apiKeyElements.status, apiPermissions: apiKeyElements.permissions, apiKeyExpirationDate: apiKeyElements.expirationDate, flowId: flowId)
        
        return (serverSessionToken, apiKeyElements)
    }
    

    private func newToken(_ token: Data, for identity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }

        failedAttemptsCounterManager.reset(counter: .sessionCreation(ownedIdentity: identity))
        
        contextCreator.performBackgroundTask(flowId: flowId) { (obvContext) in
            
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
                os_log("Could not call downloadMessagesAndListAttachments", log: Self.log, type: .fault)
            }
            
            // We pass the token to the WebSocket coordinator, this will allow re-scheduled tasks to be executed
            Task {
                await delegateManager.webSocketDelegate.setServerSessionToken(to: token, for: identity)
            }
        }
        
    }

    
    func verifyReceiptAndRefreshAPIPermissions(appStoreReceiptElements: ObvAppStoreReceipt, flowId: FlowIdentifier) async throws -> [ObvCryptoIdentity : ObvAppStoreReceipt.VerificationStatus] {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw Self.makeError(message: "The Delegate Manager is not set")
        }
        
        guard let verifyReceiptDelegate = delegateManager.verifyReceiptDelegate else {
            os_log("The verifyReceiptDelegate delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw Self.makeError(message: "The verifyReceiptDelegate delegate is not set")
        }

        let receiptVerificationResults = try await verifyReceiptDelegate.verifyReceipt(appStoreReceiptElements: appStoreReceiptElements, flowId: flowId)
        
        for result in receiptVerificationResults {
            switch result.value {
            case .failed:
                break
            case .succeededAndSubscriptionIsValid, .succeededButSubscriptionIsExpired:
                _ = try await refreshAPIPermissions(of: result.key, flowId: flowId)
            }
        }
        
        return receiptVerificationResults
        
    }
    
    
    enum ObvError: LocalizedError {
        case theDelegateManagerIsNotSet
        case theIdentityDelegateIsNotSet
        case invalidServerResponse
        case serverReturnedGeneralError
        
        var errorDescription: String? {
            switch self {
            case .theDelegateManagerIsNotSet:
                return "The delegate manager is not set"
            case .theIdentityDelegateIsNotSet:
                return "The identity delegate is not set"
            case .invalidServerResponse:
                return "Invalid server response"
            case .serverReturnedGeneralError:
                return "The server returned a general error"
            }
        }
    }
    
    
    func queryAPIKeyStatus(for ownedCryptoIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws -> APIKeyElements {
        
        let method = QueryApiKeyStatusServerMethod(ownedIdentity: ownedCryptoIdentity, apiKey: apiKey, flowId: flowId)
        let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ObvError.invalidServerResponse
        }
        
        let result = QueryApiKeyStatusServerMethod.parseObvServerResponse(responseData: data, using: Self.log)
        
        switch result {
        case .failure:
            throw ObvError.invalidServerResponse
        case .success(let serverReturnStatus):
            switch serverReturnStatus {
            case .generalError:
                throw ObvError.serverReturnedGeneralError
            case .ok(apiKeyElements: let apiKeyElements):
                return apiKeyElements
            }
        }
        
    }
    
    
    
    func registerOwnedAPIKeyOnServerNow(ownedCryptoIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws -> ObvRegisterApiKeyResult {
        
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

        let serverSessionToken = try await getValidServerSessionToken(for: ownedCryptoIdentity, currentInvalidToken: nil, flowId: flowId).serverSessionToken
        
        let method = ObvRegisterAPIKeyServerMethod(ownedIdentity: ownedCryptoIdentity, serverSessionToken: serverSessionToken, apiKey: apiKey, identityDelegate: identityDelegate, flowId: flowId)
        let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ObvError.invalidServerResponse
        }
        
        let result = ObvRegisterAPIKeyServerMethod.parseObvServerResponse(responseData: data, using: Self.log)
        
        switch result {
        case .failure(let error):
            os_log("The call to ObvRegisterAPIKeyServerMethod did fail: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            return .failed
        case .success(let serverReturnStatus):
            switch serverReturnStatus {
            case .ok:
                // After registering a new API key on the server, we force the refresh of the session to make sure the API keys elements (permissions) are refreshed
                _ = try? await getValidServerSessionToken(for: ownedCryptoIdentity, currentInvalidToken: serverSessionToken, flowId: flowId)
                return .success
            case .invalidSession:
                _ = try await getValidServerSessionToken(for: ownedCryptoIdentity, currentInvalidToken: serverSessionToken, flowId: flowId)
                return try await registerOwnedAPIKeyOnServerNow(ownedCryptoIdentity: ownedCryptoIdentity, apiKey: apiKey, flowId: flowId)
            case .invalidAPIKey:
                return .invalidAPIKey
            case .generalError:
                return .failed
            }
        }
        
    }
    
    
    private func newAPIKeyElementsForCurrentAPIKeyOf(_ ownedIdentity: ObvCryptoIdentity, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?, flowId: FlowIdentifier) {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            return
        }

        ObvNetworkFetchNotificationNew.newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(ownedIdentity: ownedIdentity,
                                                                                        apiKeyStatus: apiKeyStatus,
                                                                                        apiPermissions: apiPermissions,
                                                                                        apiKeyExpirationDate: apiKeyExpirationDate)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }
    
    
    // MARK: - Downloading message and listing attachments

    func downloadingMessagesAndListingAttachmentFailed(for ownedCryptoIdentity: ObvCryptoIdentity, andDeviceUid deviceUid: UID, flowId: FlowIdentifier) async {
        let delay = failedAttemptsCounterManager.incrementAndGetDelay(.downloadMessagesAndListAttachments(ownedIdentity: ownedCryptoIdentity))
        await retryManager.waitForDelay(milliseconds: delay)
        delegateManager?.messagesDelegate.downloadMessagesAndListAttachments(for: ownedCryptoIdentity, andDeviceUid: deviceUid, flowId: flowId)
    }
    
    
    func downloadingMessagesAndListingAttachmentWasNotNeeded(for ownedCryptoIdentity: ObvCryptoIdentity, andDeviceUid deviceUid: UID, flowId: FlowIdentifier) {
        
        // Although we did not find any new message on the server, we might still have unprocessed messages to process.

        os_log("Downloading messages was not needed. We still try to process (old) unprocessed messages", log: Self.log, type: .info)
        processUnprocessedMessages(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId)

    }
    
    
    func downloadingMessagesAndListingAttachmentWasPerformed(for ownedCryptoIdentity: ObvCryptoIdentity, andDeviceUid uid: UID, flowId: FlowIdentifier) {
        failedAttemptsCounterManager.reset(counter: .downloadMessagesAndListAttachments(ownedIdentity: ownedCryptoIdentity))
        processUnprocessedMessages(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId)
    }
    
    
    func aMessageReceivedThroughTheWebsocketWasSavedByTheMessageDelegate(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        processUnprocessedMessages(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId)
    }
    
    
    private func processUnprocessedMessages(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        assert(!Thread.isMainThread)
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            return
        }
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: Self.log, type: .fault)
            return
        }
        
        guard let processDownloadedMessageDelegate = delegateManager.processDownloadedMessageDelegate else {
            os_log("The processDownloadedMessageDelegate is not set", log: Self.log, type: .fault)
            return
        }

        let queueForPostingNotifications = self.queueForPostingNotifications
        let internalQueue = self.internalQueue
        
        syncQueue.async {
                                    
            os_log("Processing unprocessed messages within flow %{public}@", log: Self.log, type: .debug, flowId.debugDescription)
                        
            var moreUnprocessedMessagesRemain = true
            var maxNumberOfOperations = 1_000
            
            while moreUnprocessedMessagesRemain && maxNumberOfOperations > 0 {
                
                maxNumberOfOperations -= 1
                assert(maxNumberOfOperations > 0, "May happen if there were many unprocessed messages. But this is unlikely and should be investigated.")
                
                os_log("Initializing a ProcessBatchOfUnprocessedMessagesOperation (maxNumberOfOperations is %d)", log: Self.log, type: .info, maxNumberOfOperations)
                let op1 = ProcessBatchOfUnprocessedMessagesOperation(ownedCryptoIdentity: ownedCryptoIdentity,
                                                                     queueForPostingNotifications: queueForPostingNotifications,
                                                                     notificationDelegate: notificationDelegate,
                                                                     processDownloadedMessageDelegate: processDownloadedMessageDelegate,
                                                                     log: Self.log)
                let queueForComposedOperations = OperationQueue.createSerialQueue()
                let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: contextCreator, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: flowId)
                internalQueue.addOperations([composedOp], waitUntilFinished: true)
                composedOp.logReasonIfCancelled(log: Self.log)
                if composedOp.isCancelled {
                    os_log("The ProcessBatchOfUnprocessedMessagesOperation cancelled: %{public}@", log: Self.log, type: .fault, composedOp.reasonForCancel?.localizedDescription ?? "No reason given")
                    assertionFailure(composedOp.reasonForCancel.debugDescription)
                    moreUnprocessedMessagesRemain = false
                } else {
                    os_log("The ProcessBatchOfUnprocessedMessagesOperation succeeded", log: Self.log, type: .info)
                    moreUnprocessedMessagesRemain = op1.moreUnprocessedMessagesRemain ?? false
                    if moreUnprocessedMessagesRemain {
                        os_log("More unprocessed messages remain", log: Self.log, type: .info)
                    }
                }
                
            }
            
        }
    }
    

    func messagePayloadAndFromIdentityWereSet(messageId: ObvMessageIdentifier, attachmentIds: [ObvAttachmentIdentifier], hasEncryptedExtendedMessagePayload: Bool, flowId: FlowIdentifier) {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            return
        }
        
        ObvNetworkFetchNotificationNew.applicationMessageDecrypted(messageId: messageId,
                                                                   attachmentIds: attachmentIds,
                                                                   hasEncryptedExtendedMessagePayload: hasEncryptedExtendedMessagePayload,
                                                                   flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)
    }
    
    
    // MARK: - Message's extended content related methods
    
    func downloadingMessageExtendedPayloadFailed(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) {

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            return
        }

        ObvNetworkFetchNotificationNew.downloadingMessageExtendedPayloadFailed(messageId: messageId, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }
    
    
    func downloadingMessageExtendedPayloadWasPerformed(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            return
        }

        ObvNetworkFetchNotificationNew.downloadingMessageExtendedPayloadWasPerformed(messageId: messageId, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }

    
    // MARK: - Attachment's related methods
    
    func resumeDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, forceResume: Bool, flowId: FlowIdentifier) {

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }
        
        delegateManager.downloadAttachmentChunksDelegate.resumeDownloadOfAttachment(attachmentId: attachmentId, forceResume: forceResume, flowId: flowId)
        
    }

    
    func pauseDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) {

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }
        
        delegateManager.downloadAttachmentChunksDelegate.pauseDownloadOfAttachment(attachmentId: attachmentId, flowId: flowId)
        
    }
    
    func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async throws -> [ObvAttachmentIdentifier: Float] {

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            throw Self.makeError(message: "The Delegate Manager is not set")
        }
        
        return await delegateManager.downloadAttachmentChunksDelegate.requestDownloadAttachmentProgressesUpdatedSince(date: date)
        
    }

    func attachmentWasCancelledByServer(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            return
        }
        
        ObvNetworkFetchNotificationNew.inboxAttachmentDownloadCancelledByServer(attachmentId: attachmentId, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }

    func attachmentWasDownloaded(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) {
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            return
        }
        ObvNetworkFetchNotificationNew.inboxAttachmentWasDownloaded(attachmentId: attachmentId, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }
        

    // MARK: - Deletion related methods

    /// Called when a `PendingDeleteFromServer` was just created in DB. This also means that the message and its attachments have been deleted
    /// from the local inbox.
    func newPendingDeleteToProcessForMessage(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) {

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }

        do {
            try delegateManager.deleteMessageAndAttachmentsFromServerDelegate.processPendingDeleteFromServer(messageId: messageId, flowId: flowId)
        } catch {
            os_log("Could not process pending delete from server", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        
    }

    
    func failedToProcessPendingDeleteFromServer(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) async {
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }
        os_log("We could not delete message %{public}@ within flow %{public}@", log: Self.log, type: .fault, messageId.debugDescription, flowId.debugDescription)
        let delay = failedAttemptsCounterManager.incrementAndGetDelay(.processPendingDeleteFromServer(messageId: messageId))
        await retryManager.waitForDelay(milliseconds: delay)
        try? delegateManager.deleteMessageAndAttachmentsFromServerDelegate.processPendingDeleteFromServer(messageId: messageId, flowId: flowId)
    }


    func messageAndAttachmentsWereDeletedFromServerAndInboxes(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            return
        }
        
        let NotificationType = ObvNetworkFetchNotification.InboxMessageDeletedFromServerAndInboxes.self
        let userInfo = [NotificationType.Key.messageId: messageId,
                        NotificationType.Key.flowId: flowId] as [String: Any]
        notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
    }

    
    // MARK: - Push notification's related methods

    func serverReportedThatThisDeviceIsNotRegistered(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
     
        os_log("We need to re-register to push notifications since the server reported that this device is not registered", log: Self.log, type: .info)

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            return
        }

        ObvNetworkFetchNotificationNew.serverRequiresThisDeviceToRegisterToPushNotifications(ownedIdentity: ownedIdentity, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }
    
    
    func fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            return
        }
        
        ObvNetworkFetchNotificationNew.fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ownedIdentity, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }

    // MARK: - Handling Server Queries

    func post(_ serverQuery: ServerQuery, within context: ObvContext) {

        guard let delegateManager else {
            os_log("The delegate manager is not set", log: Self.log, type: .fault)
            return
        }

        _ = PendingServerQuery(serverQuery: serverQuery, delegateManager: delegateManager, within: context)

    }


    /// Called when a `PendingServerQuery` is inserted in database.
    func newPendingServerQueryToProcessWithObjectId(_ pendingServerQueryObjectId: NSManagedObjectID, isWebSocket: Bool, flowId: FlowIdentifier) async {

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }

        if isWebSocket {
            do {
                try await delegateManager.serverQueryWebSocketDelegate.handleServerQuery(pendingServerQueryObjectId: pendingServerQueryObjectId, flowId: flowId)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        } else {
            delegateManager.serverQueryDelegate.postServerQuery(withObjectId: pendingServerQueryObjectId, flowId: flowId)
        }

    }


    func failedToProcessServerQuery(withObjectId objectId: NSManagedObjectID, flowId: FlowIdentifier) async {
        let delay = failedAttemptsCounterManager.incrementAndGetDelay(.serverQuery(objectID: objectId))
        await retryManager.waitForDelay(milliseconds: delay)
        delegateManager?.serverQueryDelegate.postServerQuery(withObjectId: objectId, flowId: flowId)
    }


    func successfullProcessOfServerQuery(withObjectId objectId: NSManagedObjectID, flowId: FlowIdentifier) {

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The Context Creator is not set", log: Self.log, type: .fault)
            return
        }

        guard let channelDelegate = delegateManager.channelDelegate else {
            os_log("The channel delegate is not set", log: Self.log, type: .fault)
            return
        }

        failedAttemptsCounterManager.reset(counter: .serverQuery(objectID: objectId))

        let prng = self.prng
        contextCreator.performBackgroundTask(flowId: flowId) { (obvContext) in
            
            let serverQuery: PendingServerQuery
            do {
                guard let _serverQuery = try PendingServerQuery.get(objectId: objectId, delegateManager: delegateManager, within: obvContext) else {
                    os_log("Could not find pending server query in database", log: Self.log, type: .error)
                    return
                }
                serverQuery = _serverQuery
            } catch {
                os_log("Could not fetch pending server query in database: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }

            guard let serverResponseType = serverQuery.responseType else {
                os_log("The server response type is not set", log: Self.log, type: .fault)
                assertionFailure()
                return
            }

            let channelServerResponseType: ObvChannelServerResponseMessageToSend.ResponseType
            switch serverResponseType {
            case .deviceDiscovery(of: let contactIdentity, deviceUids: let deviceUids):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.deviceDiscovery(of: contactIdentity, deviceUids: deviceUids)
            case .putUserData:
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.putUserData
            case .getUserData(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.getUserData(result: result)
            case .checkKeycloakRevocation(verificationSuccessful: let verificationSuccessful):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.checkKeycloakRevocation(verificationSuccessful: verificationSuccessful)
            case .createGroupBlob(uploadResult: let uploadResult):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.createGroupBlob(uploadResult: uploadResult)
            case .getGroupBlob(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.getGroupBlob(result: result)
            case .deleteGroupBlob(let groupDeletionWasSuccessful):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.deleteGroupBlob(groupDeletionWasSuccessful: groupDeletionWasSuccessful)
            case .putGroupLog:
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.putGroupLog
            case .requestGroupBlobLock(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.requestGroupBlobLock(result: result)
            case .updateGroupBlob(uploadResult: let uploadResult):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.updateGroupBlob(uploadResult: uploadResult)
            case .getKeycloakData(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.getKeycloakData(result: result)
            case .ownedDeviceDiscovery(encryptedOwnedDeviceDiscoveryResult: let encryptedOwnedDeviceDiscoveryResult):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.ownedDeviceDiscovery(encryptedOwnedDeviceDiscoveryResult: encryptedOwnedDeviceDiscoveryResult)
            case .setOwnedDeviceName(success: let success):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.setOwnedDeviceName(success: success)
            case .sourceGetSessionNumberMessage(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.sourceGetSessionNumberMessage(result: result)
            case .targetSendEphemeralIdentity(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.targetSendEphemeralIdentity(result: result)
            case .transferRelay(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.transferRelay(result: result)
            case .transferWait(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.transferWait(result: result)
            case .sourceWaitForTargetConnection(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.sourceWaitForTargetConnection(result: result)
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

            guard let ownedCryptoIdentity = try? serverQuery.ownedIdentity else {
                assertionFailure()
                serverQuery.deletePendingServerQuery(within: obvContext)
                try? obvContext.save(logOnFailure: Self.log)
                return
            }
            
            if aResponseMessageShouldBePosted {
                let serverTimestamp = Date()
                let responseMessage = ObvChannelServerResponseMessageToSend(toOwnedIdentity: ownedCryptoIdentity,
                                                                            serverTimestamp: serverTimestamp,
                                                                            responseType: channelServerResponseType,
                                                                            encodedElements: serverQuery.encodedElements,
                                                                            flowId: flowId)

                do {
                    _ = try channelDelegate.postChannelMessage(responseMessage, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not process response to server query", log: Self.log, type: .fault)
                    return
                }
            }

            serverQuery.deletePendingServerQuery(within: obvContext)

            try? obvContext.save(logOnFailure: Self.log)

        }

    }


    // MARK: Handling with user data

    func failedToProcessServerUserData(input: ServerUserDataInput, flowId: FlowIdentifier) async {
        let delay = failedAttemptsCounterManager.incrementAndGetDelay(.serverUserData(input: input))
        await retryManager.waitForDelay(milliseconds: delay)
        delegateManager?.serverUserDataDelegate.postUserData(input: input, flowId: flowId)
    }

    // MARK: - Forwarding urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) and notifying successfull/failed listing (for performing fetchCompletionHandlers within the engine)

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    }

    // MARK: - Monitor Network Path Status
    
    private func monitorNetworkChanges() {
        nwPathMonitor.start(queue: DispatchQueue(label: "NetworkFetchMonitor"))
        nwPathMonitor.pathUpdateHandler = self.networkPathDidChange
    }

    
    private func networkPathDidChange(nwPath: NWPath) {
        // The nwPath status changes very early during the network status change. This is the reason why we wait before trying to reconnect. This is not bullet proof though, as the `networkPathDidChange` method does not seem to be called at every network change... This is unfortunate. Last but not least, it is very hard to work with nwPath.status so we don't even look at it.
        Task {
            let flowId = FlowIdentifier()
            await delegateManager?.webSocketDelegate.disconnectAll(flowId: flowId)
            await delegateManager?.webSocketDelegate.connectAll(flowId: flowId)
            await resetAllFailedFetchAttempsCountersAndRetryFetching()
        }
    }

    
    func resetAllFailedFetchAttempsCountersAndRetryFetching() async {
        failedAttemptsCounterManager.resetAll()
        await retryManager.executeAllWithNoDelay()
    }

    
    // MARK: - Reacting to changes within the WellKnownCoordinator
    
    func newWellKnownWasCached(server: URL, newWellKnownJSON: WellKnownJSON, flowId: FlowIdentifier) {
        
        failedAttemptsCounterManager.reset(counter: .queryServerWellKnown(serverURL: server))

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }

        os_log("New well known was cached", log: Self.log, type: .info)

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        
        Task {
            await delegateManager.webSocketDelegate.setWebSocketServerURL(for: server, to: newWellKnownJSON.serverConfig.webSocketURL)

            // On Android, this notification is not sent when `wellKnownHasBeenUpdated` is sent. But we agreed with Matthieu that this is better ;-)
            ObvNetworkFetchNotificationNew.wellKnownHasBeenDownloaded(serverURL: server, appInfo: newWellKnownJSON.appInfo, flowId: flowId)
                .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)
        }

    }
    
    
    func cachedWellKnownWasUpdated(server: URL, newWellKnownJSON: WellKnownJSON, flowId: FlowIdentifier) {

        failedAttemptsCounterManager.reset(counter: .queryServerWellKnown(serverURL: server))
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }

        Task {
            await delegateManager.webSocketDelegate.setWebSocketServerURL(for: server, to: newWellKnownJSON.serverConfig.webSocketURL)
            ObvNetworkFetchNotificationNew.wellKnownHasBeenUpdated(serverURL: server, appInfo: newWellKnownJSON.appInfo, flowId: flowId)
                .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)
        }
        
    }
    
    
    func currentCachedWellKnownCorrespondToThatOnServer(server: URL, wellKnownJSON: WellKnownJSON, flowId: FlowIdentifier) {
        
        failedAttemptsCounterManager.reset(counter: .queryServerWellKnown(serverURL: server))

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }

        ObvNetworkFetchNotificationNew.wellKnownHasBeenDownloaded(serverURL: server, appInfo: wellKnownJSON.appInfo, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

    }
    
    
    func failedToQueryServerWellKnown(serverURL: URL, flowId: FlowIdentifier) async {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }

        let delay = failedAttemptsCounterManager.incrementAndGetDelay(.queryServerWellKnown(serverURL: serverURL))
        await retryManager.waitForDelay(milliseconds: delay)
        delegateManager.wellKnownCacheDelegate.queryServerWellKnown(serverURL: serverURL, flowId: flowId)

    }
    
    
    // MARK: - Reacting to web socket changes
    
    func successfulWebSocketRegistration(identity: ObvCryptoIdentity, deviceUid: UID) {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }

        let flowId = FlowIdentifier()
        
        delegateManager.messagesDelegate.downloadMessagesAndListAttachments(for: identity, andDeviceUid: deviceUid, flowId: flowId)
    }

}
