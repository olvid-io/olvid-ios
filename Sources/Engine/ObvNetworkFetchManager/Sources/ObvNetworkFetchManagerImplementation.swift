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
import CoreData
import OlvidUtils
import ObvMetaManager
import ObvCrypto
import ObvTypes
import ObvEncoder
import ObvServerInterface

public final class ObvNetworkFetchManagerImplementation: ObvNetworkFetchDelegate {

    public var logSubsystem: String { return delegateManager.logSubsystem }
    
    private static func makeError(message: String) -> Error { NSError(domain: "ObvNetworkFetchManagerImplementation", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { ObvNetworkFetchManagerImplementation.makeError(message: message) }

    public func prependLogSubsystem(with prefix: String) {
        // 2023-06-30 The log prefix was set in the init of this class, which is much more convenient than setting it afterwards
    }

    // MARK: Instance variables
    
    private static var logCategory = "ObvNetworkFetchManagerImplementation"
    private static var log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
        
    /// Strong reference to the delegate manager, which keeps strong references to all external and internal delegate requirements.
    let delegateManager: ObvNetworkFetchDelegateManager
    
    let bootstrapWorker: BootstrapWorker

    // MARK: Initialiser
    
    public init(inbox: URL, downloadedUserData: URL, prng: PRNGService, sharedContainerIdentifier: String, supportBackgroundDownloadTasks: Bool, remoteNotificationByteIdentifierForServer: Data, logPrefix: String) {
                
        let logSubsystem = "\(logPrefix).\(ObvNetworkFetchDelegateManager.defaultLogSubsystem)"
        Self.log = OSLog(subsystem: logSubsystem, category: Self.logCategory)

        self.bootstrapWorker = BootstrapWorker(inbox: inbox, logPrefix: logPrefix)
                
        let networkFetchFlowCoordinator = NetworkFetchFlowCoordinator(prng: prng, logPrefix: logPrefix)
        let serverSessionCoordinator = ServerSessionCoordinator(prng: prng, logPrefix: logPrefix)
        let downloadMessagesAndListAttachmentsCoordinator = MessagesCoordinator(logPrefix: logPrefix)
        let downloadAttachmentChunksCoordinator = DownloadAttachmentChunksCoordinator(logPrefix: logPrefix)
        let batchDeleteAndMarkAsListedCoordinator = BatchDeleteAndMarkAsListedCoordinator()
        let serverPushNotificationsCoordinator = ServerPushNotificationsCoordinator(
            remoteNotificationByteIdentifierForServer: remoteNotificationByteIdentifierForServer, prng: prng, logPrefix: logPrefix)
        let getTurnCredentialsCoordinator = GetTurnCredentialsCoordinator()
        let freeTrialQueryCoordinator = FreeTrialQueryCoordinator()
        let verifyReceiptCoordinator = VerifyReceiptCoordinator(logPrefix: logPrefix)
        let serverQueryCoordinator = ServerQueryCoordinator(prng: prng, downloadedUserData: downloadedUserData, logPrefix: logPrefix)
        let serverQueryWebSocketCoordinator = ServerQueryWebSocketCoordinator(logPrefix: logPrefix, prng: prng)
        let serverUserDataCoordinator = ServerUserDataCoordinator(downloadedUserData: downloadedUserData, logPrefix: logPrefix)
        let wellKnownCoordinator = WellKnownCoordinator(logPrefix: logPrefix)
        let webSocketCoordinator = WebSocketCoordinator()
        
        delegateManager = ObvNetworkFetchDelegateManager(
            inbox: inbox,
            sharedContainerIdentifier: sharedContainerIdentifier,
            supportBackgroundFetch: supportBackgroundDownloadTasks,
            logPrefix: logPrefix,
            networkFetchFlowDelegate: networkFetchFlowCoordinator,
            serverSessionDelegate: serverSessionCoordinator,
            downloadMessagesAndListAttachmentsDelegate: downloadMessagesAndListAttachmentsCoordinator,
            downloadAttachmentChunksDelegate: downloadAttachmentChunksCoordinator,
            batchDeleteAndMarkAsListedDelegate: batchDeleteAndMarkAsListedCoordinator,
            serverPushNotificationsDelegate: serverPushNotificationsCoordinator,
            webSocketDelegate: webSocketCoordinator,
            getTurnCredentialsDelegate: getTurnCredentialsCoordinator,
            freeTrialQueryDelegate: freeTrialQueryCoordinator,
            verifyReceiptDelegate: verifyReceiptCoordinator,
            serverQueryDelegate: serverQueryCoordinator,
            serverQueryWebSocketDelegate: serverQueryWebSocketCoordinator,
            serverUserDataDelegate: serverUserDataCoordinator,
            wellKnownCacheDelegate: wellKnownCoordinator)
                
        networkFetchFlowCoordinator.delegateManager = delegateManager // Weak reference
        Task { await serverSessionCoordinator.setDelegateManager(delegateManager) }
        Task { await serverQueryCoordinator.setDelegateManager(delegateManager) }
        Task { await downloadMessagesAndListAttachmentsCoordinator.setDelegateManager(delegateManager) }
        Task { await downloadAttachmentChunksCoordinator.setDelegateManager(delegateManager) }
        Task { await batchDeleteAndMarkAsListedCoordinator.setDelegateManager(delegateManager) }
        Task { await serverPushNotificationsCoordinator.setDelegateManager(delegateManager) }
        getTurnCredentialsCoordinator.delegateManager = delegateManager
        Task { await freeTrialQueryCoordinator.setDelegateManager(delegateManager) }
        Task { await verifyReceiptCoordinator.setDelegateManager(delegateManager) }
        Task { await serverQueryWebSocketCoordinator.setDelegateManager(delegateManager) }
        Task { await serverUserDataCoordinator.setDelegateManager(delegateManager) }
        Task { await wellKnownCoordinator.setDelegateManager(delegateManager) }
        bootstrapWorker.delegateManager = delegateManager
        Task {
            await webSocketCoordinator.setDelegateManager(to: delegateManager)
        }

    }
}


// MARK: - Implementing ObvManager
extension ObvNetworkFetchManagerImplementation {
    
    public var requiredDelegates: [ObvEngineDelegateType] {
        return [ObvEngineDelegateType.ObvCreateContextDelegate,
                ObvEngineDelegateType.ObvSolveChallengeDelegate,
                ObvEngineDelegateType.ObvIdentityDelegate,
                ObvEngineDelegateType.ObvProcessDownloadedMessageDelegate,
                ObvEngineDelegateType.ObvNotificationDelegate,
                ObvEngineDelegateType.ObvSimpleFlowDelegate,
                ObvEngineDelegateType.ObvChannelDelegate]
    }
    
    public func fulfill(requiredDelegate delegate: AnyObject, forDelegateType delegateType: ObvEngineDelegateType) throws {
        switch delegateType {
        case .ObvCreateContextDelegate:
            guard let delegate = delegate as? ObvCreateContextDelegate else { throw makeError(message: "Cannot fulfill all delegate requirements") }
            delegateManager.contextCreator = delegate
        case .ObvProcessDownloadedMessageDelegate:
            guard let delegate = delegate as? ObvProcessDownloadedMessageDelegate else { throw makeError(message: "Cannot fulfill all delegate requirements") }
            delegateManager.processDownloadedMessageDelegate = delegate
        case .ObvSolveChallengeDelegate:
            guard let delegate = delegate as? ObvSolveChallengeDelegate else { throw makeError(message: "Cannot fulfill all delegate requirements") }
            delegateManager.solveChallengeDelegate = delegate
        case .ObvNotificationDelegate:
            guard let delegate = delegate as? ObvNotificationDelegate else { throw makeError(message: "Cannot fulfill all delegate requirements") }
            delegateManager.notificationDelegate = delegate
        case .ObvIdentityDelegate:
            guard let delegate = delegate as? ObvIdentityDelegate else { throw makeError(message: "Cannot fulfill all delegate requirements") }
            delegateManager.identityDelegate = delegate
        case .ObvSimpleFlowDelegate:
            guard let delegate = delegate as? ObvSimpleFlowDelegate else { throw makeError(message: "Cannot fulfill all delegate requirements") }
            delegateManager.simpleFlowDelegate = delegate
        case .ObvChannelDelegate:
            guard let delegate = delegate as? ObvChannelDelegate else { throw makeError(message: "Cannot fulfill all delegate requirements") }
            delegateManager.channelDelegate = delegate
        default:
            throw makeError(message: "Unexpected delegate type")
        }
    }
    
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {
        bootstrapWorker.finalizeInitialization(flowId: flowId)
        Task { [weak self] in
            if let serverQueryCoordinator = self?.delegateManager.serverQueryDelegate as? ServerQueryCoordinator {
                await serverQueryCoordinator.finalizeInitialization(flowId: flowId)
            } else {
                assertionFailure()
            }
            if let serverUserDataCoordinator = self?.delegateManager.serverUserDataDelegate as? ServerUserDataCoordinator {
                try await serverUserDataCoordinator.finalizeInitialization(flowId: flowId)
            } else {
                assertionFailure()
            }
        }
    }
    
    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {
        await bootstrapWorker.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime, flowId: flowId)
    }

}


// MARK: - Implementing ObvNetworkFetchDelegate

extension ObvNetworkFetchManagerImplementation {

    public func updatedListOfOwnedIdentites(activeOwnedCryptoIdsAndCurrentDeviceUIDs: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, flowId: FlowIdentifier) async throws {
        try await delegateManager.networkFetchFlowDelegate.updatedListOfOwnedIdentites(activeOwnedCryptoIdsAndCurrentDeviceUIDs: activeOwnedCryptoIdsAndCurrentDeviceUIDs, flowId: flowId)
    }

    public func postServerQuery(_ serverQuery: ServerQuery, within context: ObvContext) {
        delegateManager.networkFetchFlowDelegate.post(serverQuery, within: context)
    }

    public func getTurnCredentials(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> ObvTurnCredentials {
        guard let getTurnCredentialsDelegate = delegateManager.getTurnCredentialsDelegate else {
            assertionFailure()
            throw Self.makeError(message: "The turn credentials delegate is not set")
        }
        return try await getTurnCredentialsDelegate.getTurnCredentials(ownedCryptoId: ownedCryptoId, flowId: flowId)
    }

    public func getWebSocketState(ownedIdentity: ObvCryptoIdentity) async throws -> (state: URLSessionTask.State, pingInterval: TimeInterval?) {
        return try await delegateManager.webSocketDelegate.getWebSocketState(ownedIdentity: ownedIdentity)
    }
    
    public func connectWebsockets(activeOwnedCryptoIdsAndCurrentDeviceUIDs: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, flowId: FlowIdentifier) async throws {
        try await delegateManager.webSocketDelegate.connectUpdatedListOfOwnedIdentites(activeOwnedCryptoIdsAndCurrentDeviceUIDs: activeOwnedCryptoIdsAndCurrentDeviceUIDs, flowId: flowId)
    }
    
    public func disconnectWebsockets(flowId: FlowIdentifier) async {
        await delegateManager.webSocketDelegate.disconnectAll(flowId: flowId)
    }
    
    public func sendDeleteReturnReceipt(ownedIdentity: ObvCryptoIdentity, serverUid: UID) async throws {
        try await delegateManager.webSocketDelegate.sendDeleteReturnReceipt(ownedIdentity: ownedIdentity, serverUid: serverUid)
    }
    
    
    /// This methods allows to download messages currently on the server.
    ///
    /// - Parameters:
    ///   - ownedIdentity: The identity for which we want to download messages. Although this identity is a `ObvCryptoIdentity` (and not a `ObvOwnedCryptoIdentity`), the challenge solver delegate should be able to solve any challenge sent by the server. This means that this identity must exists in the OwnedIdentity database of the channel manager.
    ///   - deviceUid: The current device of the owned identity.
    public func downloadMessages(for ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async {
        os_log("Call to downloadMessages for owned identity %@ with identifier for notifications %{public}@", log: Self.log, type: .debug, ownedIdentity.debugDescription, flowId.debugDescription)
        ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] ObvNetworkFetchManagerImplementation.downloadMessages(for:flowId:)")
        await delegateManager.messagesDelegate.downloadAllMessagesAndListAttachments(ownedCryptoId: ownedIdentity, flowId: flowId)
    }
    

    public func allAttachmentsCanBeDownloadedForMessage(withId messageId: ObvMessageIdentifier, within obvContext: ObvContext) throws -> Bool {
        
        guard let inboxMessage = try InboxMessage.get(messageId: messageId, within: obvContext) else {
            os_log("Message does not exist in InboxMessage", log: Self.log, type: .error)
            throw makeError(message: "Message does not exist in InboxMessage")
        }

        let allAttachmentsCanBeDownloaded = inboxMessage.attachments.allSatisfy({ $0.canBeDownloaded })
        
        return allAttachmentsCanBeDownloaded
    }
    
    
    public func attachment(withId attachmentId: ObvAttachmentIdentifier, canBeDownloadedwithin obvContext: ObvContext) throws -> Bool {
        
        guard let inboxAttachment = try InboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
            os_log("Attachment does not exist in InboxAttachment (1)", log: Self.log, type: .error)
            throw makeError(message: "Attachment does not exist in InboxAttachment (1)")
        }
        
        return inboxAttachment.canBeDownloaded
        
    }
    
    public func allAttachmentsHaveBeenDownloadedForMessage(withId messageId: ObvMessageIdentifier, within obvContext: ObvContext) throws -> Bool {
        
        guard let inboxMessage = try InboxMessage.get(messageId: messageId, within: obvContext) else {
            os_log("Message does not exist in InboxMessage", log: Self.log, type: .error)
            throw makeError(message: "Message does not exist in InboxMessage")
        }

        let allAttachmentsHaveBeenDownloaded = inboxMessage.attachments.allSatisfy({ $0.isDownloaded })

        return allAttachmentsHaveBeenDownloaded
    }


    // MARK: Other methods for attachments
    
    public func getAttachment(withId attachmentId: ObvAttachmentIdentifier, within obvContext: ObvContext) -> ObvNetworkFetchReceivedAttachment? {
        var receivedAttachment: ObvNetworkFetchReceivedAttachment? = nil
        obvContext.performAndWait {
            guard let inboxAttachment = try? InboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                os_log("Attachment does not exist in InboxAttachment (3)", log: Self.log, type: .error)
                return
            }
            guard let metadata = inboxAttachment.metadata,
                let fromCryptoIdentity = inboxAttachment.fromCryptoIdentity
                else {
                    os_log("Attachment is not ready yet", log: Self.log, type: .error)
                    return
            }
            guard let inboxAttachmentUrl = inboxAttachment.getURL(withinInbox: delegateManager.inbox) else {
                os_log("Cannot determine the inbox attachment URL", log: Self.log, type: .fault)
                return
            }
            guard let message = inboxAttachment.message else {
                os_log("Could not find message associated to attachment, which is unexpected at this point", log: Self.log, type: .fault)
                assertionFailure()
                return
            }
            let totalUnitCount: Int64
            if inboxAttachment.status == .cancelledByServer {
                totalUnitCount = 0
            } else {
                guard let _totalUnitCount = inboxAttachment.plaintextLength else {
                    os_log("Could not find cleartext attachment size. The file might not exist yet (which is the case if the decryption key has not been set).", log: Self.log, type: .fault)
                    assertionFailure()
                    return
                }
                totalUnitCount = _totalUnitCount
            }
            receivedAttachment = ObvNetworkFetchReceivedAttachment(fromCryptoIdentity: fromCryptoIdentity,
                                                                   attachmentId: attachmentId,
                                                                   messageUploadTimestampFromServer: message.messageUploadTimestampFromServer,
                                                                   downloadTimestampFromServer: message.downloadTimestampFromServer,
                                                                   metadata: metadata,
                                                                   totalUnitCount: totalUnitCount,
                                                                   url: inboxAttachmentUrl,
                                                                   status: inboxAttachment.status.toObvNetworkFetchReceivedAttachmentStatus)
        }
        return receivedAttachment
    }
    
    
    
    public func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) async -> Bool {
        return await delegateManager.downloadAttachmentChunksDelegate.backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: backgroundURLSessionIdentifier)
    }
    
    
    public func processCompletionHandler(_ handler: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier sessionIdentifier: String, withinFlowId flowId: FlowIdentifier) async {
        await delegateManager.downloadAttachmentChunksDelegate.processCompletionHandler(handler, forHandlingEventsForBackgroundURLSessionWithIdentifier: sessionIdentifier, withinFlowId: flowId)
    }
        
    
    /// Called when an owned identity is about to be deleted.
    public func prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws {
        
        // Delete all inbox messages relating to the owned identity
                
        let messageIds = try await getAllInboxMessageIdsForOwnedIdentity(ownedCryptoId: ownedCryptoIdentity, flowId: flowId)
        for messageId in messageIds {
            do {
                try await deleteApplicationMessageAndAttachments(messageId: messageId, flowId: flowId)
            } catch {
                assertionFailure()
            }
        }
        
        // We do not delete the server sessions now, as the owned identity deletion protocol will need them to propagate information.
        // Those session are deleted in finalizeOwnedIdentityDeletion(ownedCryptoIdentity:within:)
        
        // Likewise, we don't delete PendingServerQueries now, as there might be one user to deactivate the owned identity.
        // The PendingServerQueries are deleted in finalizeOwnedIdentityDeletion(ownedCryptoIdentity:within:)

    }
    
    
    /// Helper method that returns all the ``ObvMessageIdentifier`` of the ``InboxMessages`` for a given owned identity.
    private func getAllInboxMessageIdsForOwnedIdentity(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> [ObvMessageIdentifier] {
        guard let contextCreator = delegateManager.contextCreator else { assertionFailure(); throw ObvError.theContextCreatorIsNotSet }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ObvMessageIdentifier], Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let inboxMessages = try InboxMessage.getAll(forIdentity: ownedCryptoId, within: obvContext)
                    let messageIds = inboxMessages.compactMap({ $0.messageId })
                    return continuation.resume(returning: messageIds)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    public func finalizeOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws {
        
        // Delete all server sessions of owned identity
        
        try await delegateManager.serverSessionDelegate.deleteServerSession(of: ownedCryptoIdentity, flowId: flowId)
        
        // Delete all pending all pending server queries relating to the owned identity

        let op1 = DeleteAllPendingServerQueryOperation(ownedCryptoId: ownedCryptoIdentity, delegateManager: delegateManager)
        try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)

    }
    
    
    public func performOwnedDeviceDiscoveryNow(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> EncryptedData {
        
        let method = ObvServerOwnedDeviceDiscoveryMethod(ownedIdentity: ownedCryptoId, flowId: flowId)
        let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw Self.makeError(message: "Invalid server response")
        }
        
        let result = ObvServerOwnedDeviceDiscoveryMethod.parseObvServerResponse(responseData: data, using: Self.log)
        
        switch result {
        case .success(let status):
            switch status {
            case .ok(encryptedOwnedDeviceDiscoveryResult: let encryptedOwnedDeviceDiscoveryResult):
                return encryptedOwnedDeviceDiscoveryResult
            case .generalError:
                let error = makeError(message: "ObvServerOwnedDeviceDiscoveryMethod returned a general error")
                throw error
            }
        case .failure(let error):
            assertionFailure()
            throw error
        }
        
    }
    
    
    public func remoteIdentityIsNowAContact(contactIdentifier: ObvContactIdentifier, flowId: FlowIdentifier) async throws {
        
        try await delegateManager.messagesDelegate.removeExpectedContactForReProcessingOperationThenProcessUnprocessedMessages(
            expectedContactsThatAreNowContacts: Set([contactIdentifier]),
            flowId: flowId)

    }

}


// MARK: - Deletion methods

extension ObvNetworkFetchManagerImplementation {


    /// This method is typically called by the engine when the user requests the deletion of a message. It marks the message and its
    /// attachments for deletion and atomically creates the ``PendingDeleteFromServer``, which will eventually be processed by deleting the message from server.
    /// Once this is done, the inbox message, its attachments (and associated data on disk) and the ``PendingDeleteFromServer`` are atomically deleted.
    public func deleteApplicationMessageAndAttachments(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) async throws {
        try await markApplicationMessageForDeletionAndProcessAttachments(messageId: messageId, attachmentsProcessingRequest: .deleteAll, flowId: flowId)
    }
    
    
    /// This method shall be called as soon as an `InboxMessage` is processed by the app. Note that, since it is an application message and not a protocol message, it might have attachments.
    /// In that case, the message in the inbox will only be marked for deletion but not deleted yet. The application is expected to do something with the attachments (such as storing them in its own inboxes) before marking each of the them for deletion (using the ``markAttachmentForDeletion(attachmentId:within:)`` below). When this is done, the message and its attachments will indeed be deleted from the server, then from their inboxes.
    public func markApplicationMessageForDeletionAndProcessAttachments(messageId: ObvMessageIdentifier, attachmentsProcessingRequest: ObvAttachmentsProcessingRequest, flowId: FlowIdentifier) async throws {

        let attachmentToMarkForDeletion: InboxAttachmentsSet
        let attachmentsToDownload: [ObvAttachmentIdentifier]
        switch attachmentsProcessingRequest {
        case .deleteAll:
            attachmentToMarkForDeletion = .all
            attachmentsToDownload = []
        case .process(processingKindForAttachmentIndex: let processingKindForAttachmentIndex):
            attachmentToMarkForDeletion = .subset(attachmentNumbers: Set(processingKindForAttachmentIndex.filter({ $0.value == .deleteFromServer }).map({ $0.key })))
            attachmentsToDownload = processingKindForAttachmentIndex.filter({ $0.value == .download }).map({ .init(messageId: messageId, attachmentNumber: $0.key) })
        case .doNothing:
            attachmentToMarkForDeletion = .none
            attachmentsToDownload = []
        }

        try await markMessageAndAttachmentsForDeletion(messageId: messageId, attachmentToMarkForDeletion: attachmentToMarkForDeletion, flowId: flowId)

        for attachmentToDownload in attachmentsToDownload {
            try await resumeDownloadOfAttachment(attachmentId: attachmentToDownload, flowId: flowId)
        }
        
    }

    
    /// This marks the attachment for deletion.
    ///
    /// If the message and the other attachments are already marked for deletion, this will internally trigger
    /// the required steps to actually delete the message and the attachments from the inboxes (and from the inbox folder).
    public func markAttachmentForDeletion(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws {
        let messageId = attachmentId.messageId
        let attachmentNumber = attachmentId.attachmentNumber
        try await markMessageAndAttachmentsForDeletion(messageId: messageId, attachmentToMarkForDeletion: .subset(attachmentNumbers: Set([attachmentNumber])), flowId: flowId)
    }
    
    
    /// Private method used by all the methods allowing to mark a message and/or its attachments for deletion. Once marked for deletion, this method tries to process the messages (i.e., actually delete it if appropriate).
    private func markMessageAndAttachmentsForDeletion(messageId: ObvMessageIdentifier, attachmentToMarkForDeletion: InboxAttachmentsSet, flowId: FlowIdentifier) async throws {
        
        let op1 = MarkInboxMessageAndAttachmentsForDeletionOperation(messageId: messageId, attachmentToMarkForDeletion: attachmentToMarkForDeletion)
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            assertionFailure()
            throw ObvError.couldNotMarkMessageAndAttachmentsForDeletion
        }
        
        // Now that the message/attachments are marked for deletion, we cancel any ongoing download of the attachments
        
        let attachmentsMarkedForDeletion = op1.attachmentsMarkedForDeletion
        
        for attachmentMarkedForDeletion in attachmentsMarkedForDeletion {
            do {
                try await delegateManager.downloadAttachmentChunksDelegate.cancelDownloadOfAttachment(attachmentId: attachmentMarkedForDeletion, flowId: flowId)
            } catch {
                assertionFailure()
            }
        }

        Task {
            do {
                try await delegateManager.batchDeleteAndMarkAsListedDelegate.batchDeleteAndMarkAsListed(ownedCryptoIdentity: messageId.ownedCryptoIdentity, flowId: flowId)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }

    }
    

    public func resumeDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws {
        try await delegateManager.networkFetchFlowDelegate.resumeDownloadOfAttachment(attachmentId: attachmentId, flowId: flowId)
    }

    
    public func appCouldNotFindFileOfDownloadedAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws {
        try await delegateManager.downloadAttachmentChunksDelegate.appCouldNotFindFileOfDownloadedAttachment(attachmentId: attachmentId, flowId: flowId)
    }
    

    public func pauseDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws {
        try await delegateManager.networkFetchFlowDelegate.pauseDownloadOfAttachment(attachmentId: attachmentId, flowId: flowId)
    }

    public func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async throws -> [ObvAttachmentIdentifier: Float] {
        return try await self.delegateManager.networkFetchFlowDelegate.requestDownloadAttachmentProgressesUpdatedSince(date: date)
    }
}


// MARK: - Push notification methods

extension ObvNetworkFetchManagerImplementation {
        
    public func registerPushNotification(_ pushNotification: ObvPushNotificationType, flowId: FlowIdentifier) async throws {
        
        ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] ObvNetworkFetchManagerImplementation.registerPushNotification(_:flowId:)")

        do {
            try await delegateManager.serverPushNotificationsDelegate.registerPushNotification(pushNotification, flowId: flowId)
        } catch {
            if let error = error as? ServerPushNotificationsCoordinator.ObvError {
                switch error {
                case .anotherDeviceIsAlreadyRegistered:
                    throw ObvNetworkFetchError.RegisterPushNotificationError.anotherDeviceIsAlreadyRegistered
                case .couldNotParseReturnStatusFromServer:
                    throw ObvNetworkFetchError.RegisterPushNotificationError.couldNotParseReturnStatusFromServer
                case .deviceToReplaceIsNotRegistered:
                    throw ObvNetworkFetchError.RegisterPushNotificationError.deviceToReplaceIsNotRegistered
                case .invalidServerResponse:
                    throw ObvNetworkFetchError.RegisterPushNotificationError.invalidServerResponse
                case .theDelegateManagerIsNotSet:
                    throw ObvNetworkFetchError.RegisterPushNotificationError.theDelegateManagerIsNotSet
                case .failedToCreateServerMethod:
                    throw ObvNetworkFetchError.RegisterPushNotificationError.failedToCreateServerMethod
                }
            } else {
                assertionFailure("Unrecognized error that should be casted to an ObvNetworkFetchError or dealt with earlier")
                throw error
            }
        }
        
        // If we reach this point, we succefully registered to push notifications.
        // In that case, we can download messages and list attachments
        
        Task { [weak self] in
            
            guard let self else { return }
            
            let delegateManager = self.delegateManager
            guard let contextCreator = delegateManager.contextCreator else { assertionFailure(); return }
            guard let identityDelegate = delegateManager.identityDelegate else { assertionFailure(); return }

            contextCreator.performBackgroundTask(flowId: flowId) { (obvContext) in
                                
                guard let identities = try? identityDelegate.getOwnedIdentities(restrictToActive: true, within: obvContext) else {
                    os_log("Could not get owned identities", log: Self.log, type: .fault)
                    assertionFailure()
                    return
                }
                
                // We download new messages and list their attachments
                for identity in identities {
                    Task {
                        ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] ObvNetworkFetchManagerImplementation.downloadMessages(for:flowId:)")
                        await delegateManager.messagesDelegate.downloadAllMessagesAndListAttachments(ownedCryptoId: identity, flowId: flowId)
                    }
                }
                
            }
        }

        
    }
    
}


// MARK: - Methods related to API keys & Well Known

extension ObvNetworkFetchManagerImplementation {
    
    public func queryAPIKeyStatus(for ownedCryptoIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws -> APIKeyElements {
        return try await delegateManager.networkFetchFlowDelegate.queryAPIKeyStatus(for: ownedCryptoIdentity, apiKey: apiKey, flowId: flowId)
    }
    
    public func refreshAPIPermissions(of ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> APIKeyElements {
        return try await delegateManager.networkFetchFlowDelegate.refreshAPIPermissions(of: ownedCryptoIdentity, flowId: flowId)
    }
    
    public func queryFreeTrial(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> Bool {
        guard let freeTrialQueryDelegate = delegateManager.freeTrialQueryDelegate else { assertionFailure(); throw Self.makeError(message: "freeTrialQueryDelegate is not set") }
        let freeTrialAvailable = try await freeTrialQueryDelegate.queryFreeTrial(for: identity, flowId: flowId)
        return freeTrialAvailable
    }
    
    public func startFreeTrial(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> APIKeyElements {
        guard let freeTrialQueryDelegate = delegateManager.freeTrialQueryDelegate else { assertionFailure(); throw Self.makeError(message: "freeTrialQueryDelegate is not set") }
        let newAPIKeyElements = try await freeTrialQueryDelegate.startFreeTrial(for: identity, flowId: flowId)
        return newAPIKeyElements
    }

    public func registerOwnedAPIKeyOnServerNow(ownedCryptoIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws -> ObvRegisterApiKeyResult {
        return try await delegateManager.networkFetchFlowDelegate.registerOwnedAPIKeyOnServerNow(ownedCryptoIdentity: ownedCryptoIdentity, apiKey: apiKey, flowId: flowId)
    }

    public func verifyReceiptAndRefreshAPIPermissions(appStoreReceiptElements: ObvAppStoreReceipt, flowId: FlowIdentifier) async throws -> [ObvCryptoIdentity : ObvAppStoreReceipt.VerificationStatus] {
        return try await delegateManager.networkFetchFlowDelegate.verifyReceiptAndRefreshAPIPermissions(appStoreReceiptElements: appStoreReceiptElements, flowId: flowId)
    }
    
    public func queryServerWellKnown(serverURL: URL, flowId: FlowIdentifier) async throws {
        try await delegateManager.wellKnownCacheDelegate.queryServerWellKnown(serverURL: serverURL, flowId: flowId)
    }
}


// MARK: - Errors

extension ObvNetworkFetchManagerImplementation {
    
    enum ObvError: Error {
        case theContextCreatorIsNotSet
        case couldNotMarkMessageAndAttachmentsForDeletion
        case couldNotProcessMessageMarkedForDeletion
    }
    
}
