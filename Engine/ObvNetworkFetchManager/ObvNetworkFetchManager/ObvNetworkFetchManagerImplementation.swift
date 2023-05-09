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
import OlvidUtils
import ObvMetaManager
import ObvCrypto
import ObvTypes
import ObvEncoder

public final class ObvNetworkFetchManagerImplementation: ObvNetworkFetchDelegate {

    public var logSubsystem: String { return delegateManager.logSubsystem }
    
    private static func makeError(message: String) -> Error { NSError(domain: "ObvNetworkFetchManagerImplementation", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { ObvNetworkFetchManagerImplementation.makeError(message: message) }

    public func prependLogSubsystem(with prefix: String) {
        delegateManager.prependLogSubsystem(with: prefix)
    }

    // MARK: Instance variables
    
    private var log: OSLog
        
    /// Strong reference to the delegate manager, which keeps strong references to all external and internal delegate requirements.
    let delegateManager: ObvNetworkFetchDelegateManager
    
    let bootstrapWorker: BootstrapWorker

    // MARK: Initialiser
    
    public init(inbox: URL, downloadedUserData: URL, prng: PRNGService, sharedContainerIdentifier: String, supportBackgroundDownloadTasks: Bool, remoteNotificationByteIdentifierForServer: Data) {
                
        self.bootstrapWorker = BootstrapWorker(inbox: inbox)
        
        let networkFetchFlowCoordinator = NetworkFetchFlowCoordinator(prng: prng)
        let getAndSolveChallengeCoordinator = GetAndSolveChallengeCoordinator()
        let getTokenCoordinator = GetTokenCoordinator()
        let downloadMessagesAndListAttachmentsCoordinator = MessagesCoordinator()
        let downloadAttachmentChunksCoordinator = DownloadAttachmentChunksCoordinator()
        let deleteMessageAndAttachmentsFromServerCoordinator = DeleteMessageAndAttachmentsFromServerCoordinator()
        let processRegisteredPushNotificationsCoordinator = ProcessRegisteredPushNotificationsCoordinator(remoteNotificationByteIdentifierForServer: remoteNotificationByteIdentifierForServer)
        let getTurnCredentialsCoordinator = GetTurnCredentialsCoordinator()
        let queryApiKeyStatusCoordinator = QueryApiKeyStatusCoordinator()
        let freeTrialQueryCoordinator = FreeTrialQueryCoordinator()
        let verifyReceiptCoordinator = VerifyReceiptCoordinator()
        let serverQueryCoordinator = ServerQueryCoordinator(prng: prng, downloadedUserData: downloadedUserData)
        let serverUserDataCoordinator = ServerUserDataCoordinator(prng: prng, downloadedUserData: downloadedUserData)
        let wellKnownCoordinator = WellKnownCoordinator()
        let webSocketCoordinator = WebSocketCoordinator()
        
        delegateManager = ObvNetworkFetchDelegateManager(inbox: inbox,
                                                         sharedContainerIdentifier: sharedContainerIdentifier,
                                                         supportBackgroundFetch: supportBackgroundDownloadTasks,
                                                         networkFetchFlowDelegate: networkFetchFlowCoordinator,
                                                         getAndSolveChallengeDelegate: getAndSolveChallengeCoordinator,
                                                         getTokenDelegate: getTokenCoordinator,
                                                         downloadMessagesAndListAttachmentsDelegate: downloadMessagesAndListAttachmentsCoordinator,
                                                         downloadAttachmentChunksDelegate: downloadAttachmentChunksCoordinator,
                                                         deleteMessageAndAttachmentsFromServerDelegate: deleteMessageAndAttachmentsFromServerCoordinator,
                                                         processRegisteredPushNotificationsDelegate: processRegisteredPushNotificationsCoordinator,
                                                         webSocketDelegate: webSocketCoordinator,
                                                         getTurnCredentialsDelegate: getTurnCredentialsCoordinator,
                                                         queryApiKeyStatusDelegate: queryApiKeyStatusCoordinator,
                                                         freeTrialQueryDelegate: freeTrialQueryCoordinator,
                                                         verifyReceiptDelegate: verifyReceiptCoordinator,
                                                         serverQueryDelegate: serverQueryCoordinator,
                                                         serverUserDataDelegate: serverUserDataCoordinator,
                                                         wellKnownCacheDelegate: wellKnownCoordinator)
        
        self.log = OSLog(subsystem: delegateManager.logSubsystem, category: "ObvNetworkFetchManagerImplementation")
        
        networkFetchFlowCoordinator.delegateManager = delegateManager // Weak reference
        getAndSolveChallengeCoordinator.delegateManager = delegateManager  // Weak reference
        getTokenCoordinator.delegateManager = delegateManager
        downloadMessagesAndListAttachmentsCoordinator.delegateManager = delegateManager
        downloadAttachmentChunksCoordinator.delegateManager = delegateManager
        deleteMessageAndAttachmentsFromServerCoordinator.delegateManager = delegateManager
        processRegisteredPushNotificationsCoordinator.delegateManager = delegateManager
        getTurnCredentialsCoordinator.delegateManager = delegateManager
        queryApiKeyStatusCoordinator.delegateManager = delegateManager
        freeTrialQueryCoordinator.delegateManager = delegateManager
        verifyReceiptCoordinator.delegateManager = delegateManager
        serverQueryCoordinator.delegateManager = delegateManager
        serverUserDataCoordinator.delegateManager = delegateManager
        wellKnownCoordinator.delegateManager = delegateManager
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
        self.log = OSLog(subsystem: delegateManager.logSubsystem, category: "ObvNetworkFetchManagerImplementation")
        bootstrapWorker.finalizeInitialization(flowId: flowId)
        if let serverQueryCoordinator = delegateManager.serverQueryDelegate as? ServerQueryCoordinator {
            serverQueryCoordinator.finalizeInitialization()
        } else {
            assertionFailure()
        }
        if let serverUserDataCoordinator = delegateManager.serverUserDataDelegate as? ServerUserDataCoordinator {
            serverUserDataCoordinator.finalizeInitialization()
        } else {
            assertionFailure()
        }
    }
    
    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {
        if forTheFirstTime {
            delegateManager.networkFetchFlowDelegate.resetAllFailedFetchAttempsCountersAndRetryFetching()
        }
        await bootstrapWorker.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime, flowId: flowId)
    }

}


// MARK: - Implementing ObvNetworkFetchDelegate
extension ObvNetworkFetchManagerImplementation {

    public func updatedListOfOwnedIdentites(ownedIdentities: Set<ObvCryptoIdentity>, flowId: FlowIdentifier) {
        delegateManager.networkFetchFlowDelegate.updatedListOfOwnedIdentites(ownedIdentities: ownedIdentities, flowId: flowId)
    }

    public func postServerQuery(_ serverQuery: ServerQuery, within context: ObvContext) {
        delegateManager.networkFetchFlowDelegate.post(serverQuery, within: context)
    }

    public func getTurnCredentials(ownedIdenty: ObvCryptoIdentity, callUuid: UUID, username1: String, username2: String, flowId: FlowIdentifier) {
        delegateManager.getTurnCredentialsDelegate?.getTurnCredentials(ownedIdenty: ownedIdenty, callUuid: callUuid, username1: username1, username2: username2, flowId: flowId)
    }
    
    public func getWebSocketState(ownedIdentity: ObvCryptoIdentity) async throws -> (URLSessionTask.State,TimeInterval?) {
        return try await delegateManager.webSocketDelegate.getWebSocketState(ownedIdentity: ownedIdentity)
    }
    
    public func connectWebsockets(flowId: FlowIdentifier) async {
        await delegateManager.webSocketDelegate.connectAll(flowId: flowId)
    }
    
    public func disconnectWebsockets(flowId: FlowIdentifier) async {
        await delegateManager.webSocketDelegate.disconnectAll(flowId: flowId)
    }
    
    public func sendDeleteReturnReceipt(ownedIdentity: ObvCryptoIdentity, serverUid: UID) async throws {
        try await delegateManager.webSocketDelegate.sendDeleteReturnReceipt(ownedIdentity: ownedIdentity, serverUid: serverUid)
    }
    
    
    /// This methods allows to download messages currently on the server. Under the hood, it starts by creating a list operation.
    ///
    /// - Parameters:
    ///   - ownedIdentity: The identity for which we want to download messages. Although this identity is a `ObvCryptoIdentity` (and not a `ObvOwnedCryptoIdentity`), the challenge solver delegate should be able to solve any challenge sent by the server. This means that this identity must exists in the OwnedIdentity database of the channel manager.
    ///   - deviceUid: The current device of the owned identity.
    public func downloadMessages(for ownedIdentity: ObvCryptoIdentity, andDeviceUid deviceUid: UID, flowId: FlowIdentifier) {
        
        assert(!Thread.isMainThread)
        
        os_log("Call to downloadMessages for owned identity %@ with identifier for notifications %{public}@", log: log, type: .debug, ownedIdentity.debugDescription, flowId.debugDescription)
        
        delegateManager.messagesDelegate.downloadMessagesAndListAttachments(for: ownedIdentity, andDeviceUid: deviceUid, flowId: flowId)
    }
    

    public func getDecryptedMessage(messageId: MessageIdentifier, flowId: FlowIdentifier) -> ObvNetworkReceivedMessageDecrypted? {
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The Context Creator is not set", log: log, type: .fault)
            return nil
        }
        
        var message: ObvNetworkReceivedMessageDecrypted?
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            guard let inboxMessage = try? InboxMessage.get(messageId: messageId, within: obvContext) else {
                os_log("Message does not exist in InboxMessage", log: log, type: .error)
                return
            }

            guard let fromIdentity = inboxMessage.fromCryptoIdentity else { return }
            guard let messagePayload = inboxMessage.messagePayload else { return }
            
            message = ObvNetworkReceivedMessageDecrypted(messageId: messageId,
                                                         attachmentIds: inboxMessage.attachmentIds,
                                                         fromIdentity: fromIdentity,
                                                         messagePayload: messagePayload,
                                                         messageUploadTimestampFromServer: inboxMessage.messageUploadTimestampFromServer,
                                                         downloadTimestampFromServer: inboxMessage.downloadTimestampFromServer,
                                                         localDownloadTimestamp: inboxMessage.localDownloadTimestamp,
                                                         extendedMessagePayload: inboxMessage.extendedMessagePayload)
        }
        return message
    }

    
    public func allAttachmentsCanBeDownloadedForMessage(withId messageId: MessageIdentifier, within obvContext: ObvContext) throws -> Bool {
        
        guard let inboxMessage = try InboxMessage.get(messageId: messageId, within: obvContext) else {
            os_log("Message does not exist in InboxMessage", log: log, type: .error)
            throw makeError(message: "Message does not exist in InboxMessage")
        }

        let allAttachmentsCanBeDownloaded = inboxMessage.attachments.allSatisfy({ $0.canBeDownloaded })
        
        return allAttachmentsCanBeDownloaded
    }
    
    
    public func attachment(withId attachmentId: AttachmentIdentifier, canBeDownloadedwithin obvContext: ObvContext) throws -> Bool {
        
        guard let inboxAttachment = try InboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
            os_log("Attachment does not exist in InboxAttachment (1)", log: log, type: .error)
            throw makeError(message: "Attachment does not exist in InboxAttachment (1)")
        }
        
        return inboxAttachment.canBeDownloaded
        
    }
    
    public func allAttachmentsHaveBeenDownloadedForMessage(withId messageId: MessageIdentifier, within obvContext: ObvContext) throws -> Bool {
        
        guard let inboxMessage = try InboxMessage.get(messageId: messageId, within: obvContext) else {
            os_log("Message does not exist in InboxMessage", log: log, type: .error)
            throw makeError(message: "Message does not exist in InboxMessage")
        }

        let allAttachmentsHaveBeenDownloaded = inboxMessage.attachments.allSatisfy({ $0.isDownloaded })

        return allAttachmentsHaveBeenDownloaded
    }


    // MARK: Other methods for attachments
    
    public func set(remoteCryptoIdentity: ObvCryptoIdentity, messagePayload: Data, extendedMessagePayloadKey: AuthenticatedEncryptionKey?, andAttachmentsInfos attachmentsInfos: [ObvNetworkFetchAttachmentInfos], forApplicationMessageWithmessageId messageId: MessageIdentifier, within obvContext: ObvContext) throws {
        guard let inboxMessage = try InboxMessage.get(messageId: messageId, within: obvContext) else {
            os_log("Message does not exist in InboxMessage", log: log, type: .error)
            assertionFailure()
            throw makeError(message: "Message does not exist in InboxMessage")
        }
        try inboxMessage.set(fromCryptoIdentity: remoteCryptoIdentity, andMessagePayload: messagePayload, extendedMessagePayloadKey: extendedMessagePayloadKey, flowId: obvContext.flowId, delegateManager: delegateManager)
        guard inboxMessage.attachments.count == attachmentsInfos.count else {
            os_log("Message does not have an appropriate number of attachments", log: log, type: .error)
            assertionFailure()
            throw makeError(message: "Message does not have an appropriate number of attachments")
        }
        guard inboxMessage.attachments.count == attachmentsInfos.count else {
            os_log("Invalid attachment count", log: log, type: .error)
            assertionFailure()
            throw makeError(message: "Invalid attachment count")
        }
        for inboxMessageAttachment in inboxMessage.attachments {
            let attachmentInfos = attachmentsInfos[inboxMessageAttachment.attachmentNumber]
            try inboxMessageAttachment.set(decryptionKey: attachmentInfos.key,
                                           metadata: attachmentInfos.metadata,
                                           inbox: delegateManager.inbox)
        }
        
        // We have set all the elements allowing the attachments to be downloaded.
        // So we process all the attachment in case the context saves successfully
        try obvContext.addContextDidSaveCompletionHandler { [weak self] (error) in
            guard error == nil else { return }
            self?.delegateManager.downloadAttachmentChunksDelegate.processAllAttachmentsOfMessage(messageId: messageId, flowId: obvContext.flowId)
        }
        
        // If the message has an encrypted payload to download, we ask for the download
        if inboxMessage.hasEncryptedExtendedMessagePayload && extendedMessagePayloadKey != nil {
            try obvContext.addContextDidSaveCompletionHandler { [weak self] (error) in
                guard error == nil else { return }
                self?.delegateManager.messagesDelegate.downloadExtendedMessagePayload(messageId: messageId, flowId: obvContext.flowId)
            }
        }

    }
    
    
    public func getAttachment(withId attachmentId: AttachmentIdentifier, within obvContext: ObvContext) -> ObvNetworkFetchReceivedAttachment? {
        var receivedAttachment: ObvNetworkFetchReceivedAttachment? = nil
        obvContext.performAndWait {
            guard let inboxAttachment = try? InboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                os_log("Attachment does not exist in InboxAttachment (3)", log: log, type: .error)
                return
            }
            guard let metadata = inboxAttachment.metadata,
                let fromCryptoIdentity = inboxAttachment.fromCryptoIdentity
                else {
                    os_log("Attachment is not ready yet", log: log, type: .error)
                    return
            }
            guard let inboxAttachmentUrl = inboxAttachment.getURL(withinInbox: delegateManager.inbox) else {
                os_log("Cannot determine the inbox attachment URL", log: log, type: .fault)
                return
            }
            guard let message = inboxAttachment.message else {
                os_log("Could not find message associated to attachment, which is unexpected at this point", log: log, type: .fault)
                assertionFailure()
                return
            }
            let totalUnitCount: Int64
            if inboxAttachment.status == .cancelledByServer {
                totalUnitCount = 0
            } else {
                guard let _totalUnitCount = inboxAttachment.plaintextLength else {
                    os_log("Could not find cleartext attachment size. The file might not exist yet (which is the case if the decryption key has not been set).", log: log, type: .fault)
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
    
    
    
    public func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool {
        return delegateManager.downloadAttachmentChunksDelegate.backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: backgroundURLSessionIdentifier)
    }
    
    
    public func processCompletionHandler(_ handler: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier sessionIdentifier: String, withinFlowId flowId: FlowIdentifier) {
        delegateManager.downloadAttachmentChunksDelegate.processCompletionHandler(handler, forHandlingEventsForBackgroundURLSessionWithIdentifier: sessionIdentifier, withinFlowId: flowId)
    }
        
    
    /// Called when an owned identity is about to be deleted.
    public func prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        // Delete all inbox messages relating to the owned identity
        
        let inboxMessages = try InboxMessage.getAll(forIdentity: ownedCryptoIdentity, within: obvContext)
        for inboxMessage in inboxMessages {
            deleteMessageAndAttachments(messageId: inboxMessage.messageId, within: obvContext)
        }
        
        // Delete all pending deletes from server relating to the owned identity
        
        try PendingDeleteFromServer.deleteAllPendingDeleteFromServerForOwnedCryptoIdentity(ownedCryptoIdentity, within: obvContext)
        
        // Delete all pending server queries relating to the owned identity
        
        try PendingServerQuery.deleteAllServerQuery(for: ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext)
        
        // Delete all registered push notifications relating to the owned identity
        
        try RegisteredPushNotification.deleteAllRegisteredPushNotificationForOwnedCryptoIdentity(ownedCryptoIdentity, within: obvContext)
        
        // Delete all server sessions of owned identity
        
        try ServerSession.deleteAllSessionsOfIdentity(ownedCryptoIdentity, within: obvContext)

    }
    
}


// MARK: - Deletion methods

extension ObvNetworkFetchManagerImplementation {

    /// This method is typically called by the channel manager when it cannot decrypt the message. It marks the message and its
    /// attachments for deletion. This does not actually delete the message/attachments. Instead, this will triger a notification
    /// that will be catched internally by the appropriate coordinator that will atomically delete the message/attachments and
    /// create a PendingDeleteFromServer
    public func deleteMessageAndAttachments(messageId: MessageIdentifier, within obvContext: ObvContext) {
        let flowId = obvContext.flowId
        let delegateManager = self.delegateManager
        guard let message = try? InboxMessage.get(messageId: messageId, within: obvContext) else {
            os_log("Could not find message, no need to delete it", log: log, type: .info)
            return
        }
        message.markForDeletion()
        for attachment in message.attachments {
            attachment.markForDeletion()
        }
        if !message.canBeDeleted { assertionFailure() }
        try? obvContext.addContextDidSaveCompletionHandler({ (error) in
            guard error == nil else { return }
            try? delegateManager.messagesDelegate.processMarkForDeletionForMessageAndAttachmentsAndCreatePendingDeleteFromServer(messageId: messageId, flowId: flowId)
        })
    }
    
    
    /// This method should be called by the channel manager as soon as it decrypts a message.
    ///
    /// In case the message is a protocol message (typically, new inputs for a protocol instance), then the channel manager has stored the result in one of its own databases, and calling this method ends up deleting the message from the inbox.
    ///
    /// In case the message is an application message, then it certainly has associated attachments. In that case, the message in the inbox will only be marked for deletion but not deleted yet. The application is expected to do something with the attachments (such as storing them in its own inboxes) before marking each of the them for deletion (using the `deleteAttachment` below). We this is done, the message and its attachments will indeed be deleted from their inboxes.
    public func markMessageForDeletion(messageId: MessageIdentifier, within obvContext: ObvContext) {
        let flowId = obvContext.flowId
        let delegateManager = self.delegateManager
        guard let message = try? InboxMessage.get(messageId: messageId, within: obvContext) else { return }
        message.markForDeletion()
        if message.canBeDeleted {
            try? obvContext.addContextDidSaveCompletionHandler({ (error) in
                guard error == nil else { return }
                try? delegateManager.messagesDelegate.processMarkForDeletionForMessageAndAttachmentsAndCreatePendingDeleteFromServer(messageId: messageId, flowId: flowId)
            })
        }
    }

    
    /// This marks the attachment for deletion.
    ///
    /// If the message and the other attachments are already marked for deletion, this will internally trigger
    /// the required steps to actually delete the message and the attachments from the inboxes (and from the inbox folder).
    public func markAttachmentForDeletion(attachmentId: AttachmentIdentifier, within obvContext: ObvContext) {
        let flowId = obvContext.flowId
        let delegateManager = self.delegateManager
        guard let attachment = try? InboxAttachment.get(attachmentId: attachmentId, within: obvContext) else { return }
        attachment.markForDeletion()
        guard let message = attachment.message else { return }
        let messageId = message.messageId
        if message.canBeDeleted {
            try? obvContext.addContextDidSaveCompletionHandler({ (error) in
                guard error == nil else { return }
                try? delegateManager.messagesDelegate.processMarkForDeletionForMessageAndAttachmentsAndCreatePendingDeleteFromServer(messageId: messageId, flowId: flowId)
            })
        }
    }
    
    
    public func resumeDownloadOfAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {
        self.delegateManager.networkFetchFlowDelegate.resumeDownloadOfAttachment(attachmentId: attachmentId, flowId: flowId)
    }


    public func pauseDownloadOfAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {
        self.delegateManager.networkFetchFlowDelegate.pauseDownloadOfAttachment(attachmentId: attachmentId, flowId: flowId)
    }

    public func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async throws -> [AttachmentIdentifier: Float] {
        return try await self.delegateManager.networkFetchFlowDelegate.requestDownloadAttachmentProgressesUpdatedSince(date: date)
    }
}


// MARK: - Push notification methods

extension ObvNetworkFetchManagerImplementation {
        
    public func register(pushNotificationType: ObvPushNotificationType, for identity: ObvCryptoIdentity, withDeviceUid deviceUid: UID, within obvContext: ObvContext) {
        
        _ = RegisteredPushNotification(identity: identity,
                                       deviceUid: deviceUid,
                                       pushNotificationType: pushNotificationType,
                                       delegateManager: delegateManager,
                                       within: obvContext)
        
    }
    
    /// This method registes the identity to the push notification, but only if not previous registration can be found for this identity. This is typically used by the identity manager at launch time.
    public func registerIfRequired(pushNotificationType: ObvPushNotificationType, for identity: ObvCryptoIdentity, withDeviceUid deviceUid: UID, within obvContext: ObvContext) {
        
        if let previouslyRegisteredPushNotifications = RegisteredPushNotification.getAllSortedByCreationDate(for: identity, delegateManager: delegateManager, within: obvContext) {
            if previouslyRegisteredPushNotifications.count == 0 {
                register(pushNotificationType: pushNotificationType, for: identity, withDeviceUid: deviceUid, within: obvContext)
            } else if previouslyRegisteredPushNotifications.count == 1 {
                // If the new and previous push notifications are "polling", we compare the time intervals
                let previouslyRegisteredPushNotification = previouslyRegisteredPushNotifications.first!
                switch previouslyRegisteredPushNotification.pushNotificationType {
                case .polling(pollingInterval: let previousTimeInterval):
                    switch pushNotificationType {
                    case .polling(pollingInterval: let newTimeInterval):
                        if previousTimeInterval == newTimeInterval {
                            break
                        } else {
                            // We update the time interval of the registered polling push notification
                            os_log("Changing polling time from %f to %f", log: log, type: .info, previousTimeInterval, newTimeInterval)
                            obvContext.delete(previouslyRegisteredPushNotification)
                            register(pushNotificationType: pushNotificationType, for: identity, withDeviceUid: deviceUid, within: obvContext)
                        }
                    default:
                        break
                    }
                default:
                    break
                }
            }
        } else {
            register(pushNotificationType: pushNotificationType, for: identity, withDeviceUid: deviceUid, within: obvContext)
        }
        
    }
    
    public func unregisterPushNotification(for identity: ObvCryptoIdentity, within obvContext: ObvContext) {
        os_log("unregisterPushNotification is not implemented", log: log, type: .fault)
        if let registeredPushNotifications = RegisteredPushNotification.getAllSortedByCreationDate(for: identity, delegateManager: delegateManager, within: obvContext) {
            registeredPushNotifications.forEach {
                obvContext.delete($0)
            }
        } else {
            os_log("Could not unregister from push notifications", log: log, type: .error)
        }
        
    }
     
    
    // For now, this method is used when new keyckloak push topics are available. This will have the effect to re-register to push notification, adding the push topics found within the identity manager.
    public func forceRegisterToPushNotification(identity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            assertionFailure()
            throw makeError(message: "The identity delegate is not set")
        }
        
        try obvContext.performAndWaitOrThrow {
            let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(identity, within: obvContext)
            try delegateManager.networkFetchFlowDelegate.newRegisteredPushNotificationToProcess(for: identity, withDeviceUid: currentDeviceUid, flowId: obvContext.flowId)
        }
    }

}


// MARK: - Methods related to API keys & Well Known

extension ObvNetworkFetchManagerImplementation {
    
    public func queryAPIKeyStatus(for identity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) {
        delegateManager.queryApiKeyStatusDelegate?.queryAPIKeyStatus(for: identity, apiKey: apiKey, flowId: flowId)
    }

    public func resetServerSession(for identity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        try delegateManager.networkFetchFlowDelegate.resetServerSession(for: identity, within: obvContext)
    }
    
    public func queryFreeTrial(for identity: ObvCryptoIdentity, retrieveAPIKey: Bool, flowId: FlowIdentifier) {
        delegateManager.freeTrialQueryDelegate?.queryFreeTrial(for: identity, retrieveAPIKey: retrieveAPIKey, flowId: flowId)
    }

    public func verifyReceipt(ownedCryptoIdentities: [ObvCryptoIdentity], receiptData: String, transactionIdentifier: String, flowId: FlowIdentifier) {
        delegateManager.networkFetchFlowDelegate.verifyReceipt(ownedCryptoIdentities: ownedCryptoIdentities, receiptData: receiptData, transactionIdentifier: transactionIdentifier, flowId: flowId)
    }
    
    public func queryServerWellKnown(serverURL: URL, flowId: FlowIdentifier) {
        delegateManager.wellKnownCacheDelegate.queryServerWellKnown(serverURL: serverURL, flowId: flowId)
    }
}
