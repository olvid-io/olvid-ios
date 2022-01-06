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
import ObvTypes
import ObvOperation
import ObvMetaManager
import ObvCrypto
import Network
import OlvidUtils

final class NetworkSendFlowCoordinator {
    
    // MARK: - Instance variables
    
    fileprivate let defaultLogSubsystem = ObvNetworkSendDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "NetworkSendFlowCoordinator"

    private var failedFetchAttemptsCounterManager = FailedFetchAttemptsCounterManager()
    private var retryManager = SendRetryManager()
    private var notificationTokens = [NSObjectProtocol]()
    private let outbox: URL
    
    private let queueForPostingNotifications: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 5
        queue.name = "Operation Queue for posting certain notifications from the NetworkSendFlowCoordinator"
        return queue
    }()
    
    weak var delegateManager: ObvNetworkSendDelegateManager?

    init(outbox: URL) {
        self.outbox = outbox
        if #available(iOS 12, *) {
            monitorNetworkChanges()
        }
    }

}


// MARK: - NetworkSendFlowDelegate

extension NetworkSendFlowCoordinator: NetworkSendFlowDelegate {
    

    func post(_ message: ObvNetworkMessageToSend, within obvContext: ObvContext) throws {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            throw NSError()
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set (1)", log: log, type: .fault)
            return
        }
        
        os_log("Posting a message with %{public}d headers and %{public}d attachments within flow %{public}@", log: log, type: .info, message.headers.count, message.attachments?.count ?? 0, obvContext.flowId.debugDescription)

        guard let outboxMessage = OutboxMessage(messageId: message.messageId,
                                                serverURL: message.serverURL,
                                                encryptedContent: message.encryptedContent,
                                                encryptedExtendedMessagePayload: message.encryptedExtendedMessagePayload,
                                                isAppMessageWithUserContent: message.isAppMessageWithUserContent,
                                                isVoipMessage: message.isVoipMessageForStartingCall,
                                                delegateManager: delegateManager,
                                                within: obvContext)
            else {
                os_log("Could not create outboxMessage in database", log: log, type: .error)
                throw NSError()
        }
        
        for header in message.headers {
            _ = MessageHeader(message: outboxMessage,
                              toCryptoIdentity: header.toIdentity,
                              deviceUid: header.deviceUid,
                              wrappedKey: header.wrappedMessageKey)
        }
        
        var attachmentIds = [AttachmentIdentifier]()
        if let attachments = message.attachments {
            var attachmentNumber = 0
            for attachment in attachments {
                guard OutboxAttachment(message: outboxMessage,
                                       attachmentNumber: attachmentNumber,
                                       fileURL: attachment.fileURL,
                                       deleteAfterSend: attachment.deleteAfterSend,
                                       byteSize: attachment.byteSize,
                                       key: attachment.key) != nil
                    else {
                        os_log("Could not create outboxAttachment in database", log: log, type: .error)
                        throw NSError()
                }

                let attachmentId = AttachmentIdentifier(messageId: message.messageId, attachmentNumber: attachmentNumber)
                attachmentIds.append(attachmentId)

                attachmentNumber += 1
            }
        }
        
        do {
            try obvContext.addContextDidSaveCompletionHandler { (error) in
                guard error == nil else { return }
                let NotificationType = ObvNetworkPostNotification.NewOutboxMessageAndAttachmentsToUpload.self
                let userInfo = [NotificationType.Key.messageId: message.messageId,
                                NotificationType.Key.attachmentIds: attachmentIds,
                                NotificationType.Key.flowId: obvContext.flowId] as [String: Any]
                notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
            }
        } catch {
            os_log("Failed to notify that there is a new message and attachments to upload", log: log, type: .fault)
        }

    }
    
    
    func newOutboxMessage(messageId: MessageIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        os_log("Call to newOutboxMessage for message %{public}@ within flow %{public}@", log: log, type: .info, messageId.debugDescription, flowId.debugDescription)

        delegateManager.uploadMessageAndGetUidsDelegate.getIdFromServerUploadMessage(messageId: messageId, flowId: flowId)

    }
    
    
    func failedUploadAndGetUidOfMessage(messageId: MessageIdentifier, flowId: FlowIdentifier) {
        let delay = failedFetchAttemptsCounterManager.incrementAndGetDelay(.uploadMessage(messageId: messageId))
        retryManager.executeWithDelay(delay) { [weak self] in
            self?.delegateManager?.uploadMessageAndGetUidsDelegate.getIdFromServerUploadMessage(messageId: messageId, flowId: flowId)
        }
    }

    
    func successfulUploadOfMessage(messageId: MessageIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The Context Creator is not set", log: log, type: .fault)
            return
        }
        
        failedFetchAttemptsCounterManager.reset(counter: .uploadMessage(messageId: messageId))
        
        contextCreator.performBackgroundTask(flowId: flowId) { [weak self] (obvContext) in
            
            guard let message = try? OutboxMessage.get(messageId: messageId, delegateManager: delegateManager, within: obvContext) else {
                os_log("Could not find message %{public}@ in database", log: log, type: .fault, messageId.debugDescription)
                return
            }
            
            if message.canBeDeleted {
                delegateManager.tryToDeleteMessageAndAttachmentsDelegate.tryToDeleteMessageAndAttachments(messageId: messageId, flowId: flowId)
            } else {
                assert(!message.attachments.isEmpty)
                os_log("Message %{public}@ has %d attachment(s) to upload", log: log, type: .debug, messageId.debugDescription, message.attachments.count)
                delegateManager.uploadAttachmentChunksDelegate.processAllAttachmentsOfMessage(messageId: messageId, flowId: flowId)
            }
            
            guard let timestampFromServer = message.timestampFromServer else {
                os_log("Although the message is supposed to be uploaded, it has no timestamp from server, which is unexpected", log: log, type: .fault)
                assert(false)
                self?.failedUploadAndGetUidOfMessage(messageId: messageId, flowId: flowId)
                return
            }
            
            guard let notificationDelegate = delegateManager.notificationDelegate else {
                os_log("The notification delegate is not set (2)", log: log, type: .fault)
                return
            }
            
            let notification = ObvNetworkPostNotificationNew.outboxMessageWasUploaded(messageId: messageId,
                                                                                      timestampFromServer: timestampFromServer,
                                                                                      isAppMessageWithUserContent: message.isAppMessageWithUserContent,
                                                                                      isVoipMessage: message.isVoipMessage,
                                                                                      flowId: flowId)
            notification.postOnDispatchQueue(withLabel: "Queue for posting an outboxMessageWasUploaded notification (2)", within: notificationDelegate)
            
        }
        
    }
    
    
    
    func messageAndAttachmentsWereExternallyCancelledAndCanSafelyBeDeletedNow(messageId: MessageIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        delegateManager.tryToDeleteMessageAndAttachmentsDelegate.tryToDeleteMessageAndAttachments(messageId: messageId, flowId: flowId)

    }
    
    
    
    func newProgressForAttachment(attachmentId: AttachmentIdentifier, newProgress: Progress, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set (3)", log: log, type: .fault)
            return
        }
        
        failedFetchAttemptsCounterManager.reset(counter: .uploadAttachment(attachmentId: attachmentId))
        
        ObvNetworkPostNotificationNew.outboxAttachmentHasNewProgress(attachmentId: attachmentId, newProgress: newProgress, flowId: flowId)
            .postOnOperationQueue(operationQueue: queueForPostingNotifications, within: notificationDelegate)

    }

    
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return false
        }
        
        if delegateManager.uploadAttachmentChunksDelegate.backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: backgroundURLSessionIdentifier) {
            return true
        } else {
            return false
        }
        
    }
    
    
    func storeCompletionHandler(_ handler: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier identifer: String, withinFlowId flowId: FlowIdentifier) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        if delegateManager.uploadAttachmentChunksDelegate.backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: identifer) {
            delegateManager.uploadAttachmentChunksDelegate.processCompletionHandler(handler, forHandlingEventsForBackgroundURLSessionWithIdentifier: identifer, withinFlowId: flowId)
        } else {
            os_log("Unexpected background session identifier: %{public}@", log: log, type: .fault, identifer)
            assertionFailure()
        }
    }
    
    
    
    func acknowledgedAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set (4)", log: log, type: .fault)
            return
        }
        
        ObvNetworkPostNotificationNew.outboxAttachmentWasAcknowledged(attachmentId: attachmentId, flowId: flowId)
            .postOnDispatchQueue(withLabel: "Queue for posting an outboxAttachmentWasAcknowledged notification", within: notificationDelegate)
        
        delegateManager.tryToDeleteMessageAndAttachmentsDelegate.tryToDeleteMessageAndAttachments(messageId: attachmentId.messageId, flowId: flowId)
                
    }

    
    func attachmentFailedToUpload(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {
        let delay = failedFetchAttemptsCounterManager.incrementAndGetDelay(.uploadAttachment(attachmentId: attachmentId))
        retryManager.executeWithDelay(delay) { [weak self] in
            self?.delegateManager?.uploadAttachmentChunksDelegate.resumeMissingAttachmentUploads(flowId: flowId)
        }
    }
    
    func signedURLsDownloadFailedForAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {
        let delay = failedFetchAttemptsCounterManager.incrementAndGetDelay(.uploadAttachment(attachmentId: attachmentId))
        retryManager.executeWithDelay(delay) { [weak self] in
            self?.delegateManager?.uploadAttachmentChunksDelegate.downloadSignedURLsForAttachments(attachmentIds: [attachmentId], flowId: flowId)
        }
    }


    func messageAndAttachmentsWereDeletedFromTheirOutboxes(messageId: MessageIdentifier, flowId: FlowIdentifier) {

        cleanOutboxForMessage(messageId)
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set (5)", log: log, type: .fault)
            return
        }

        let NotificationType = ObvNetworkPostNotification.OutboxMessageAndAttachmentsDeleted.self
        let userInfo = [NotificationType.Key.messageId: messageId,
                        NotificationType.Key.flowId: flowId] as [String: Any]
        notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)

    }

    
    func sendNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
        
        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        let notification = ObvNetworkPostNotificationNew.postNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ownedIdentity, flowId: flowId)
        notification.postOnDispatchQueue(withLabel: "Queue for posting postNetworkOperationFailedSinceOwnedIdentityIsNotActive notification", within: notificationDelegate)
        
    }
    
    func requestProgressesOfAllOutboxAttachmentsOfMessage(withIdentifier messageIdentifier: MessageIdentifier, flowId: FlowIdentifier) throws {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The contextCreator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        contextCreator.performBackgroundTask(flowId: flowId) { (obvContext) in

            do {
                if let sentMessage = (try DeletedOutboxMessage.getAll(delegateManager: delegateManager, within: obvContext)).first(where: { $0.messageId == messageIdentifier }) {
                    let messageIdsAndTimestampsFromServer = (sentMessage.messageId, sentMessage.timestampFromServer)
                    ObvNetworkPostNotificationNew.outboxMessagesAndAllTheirAttachmentsWereAcknowledged(messageIdsAndTimestampsFromServer: [messageIdsAndTimestampsFromServer], flowId: flowId)
                        .postOnDispatchQueue(withLabel: "Queue for posting an outboxMessagesAndAllTheirAttachmentsWereAcknowledged notification", within: notificationDelegate)
                    return
                }
            } catch {
                assertionFailure()
                return
            }
            
            // If we reach this point, we could not find the message in the database
            
            do {
                if let message = try OutboxMessage.get(messageId: messageIdentifier, delegateManager: delegateManager, within: obvContext) {
                    let attachmentsIds = message.attachments.map({ $0.attachmentId })
                    for attachmentId in attachmentsIds {
                        guard let progress = delegateManager.uploadAttachmentChunksDelegate.requestProgressOfAttachment(withIdentifier: attachmentId) else { continue }
                        ObvNetworkPostNotificationNew.outboxAttachmentHasNewProgress(attachmentId: attachmentId, newProgress: progress, flowId: flowId)
                            .postOnDispatchQueue(withLabel: "Queue for posting an outboxAttachmentHasNewProgress notification", within: notificationDelegate)
                    }
                    return
                }
            } catch {
                assertionFailure()
                return
            }

            // We should not reach this point. If this happens, we should consider send a notification saying that the message and its attachments were acknowledged.
            // Yet, we do no have access to the timestampFromServer...
            /* assertionFailure() */
        }
        
    }
    
    // MARK: - Monitor Network Path Status
    
    @available(iOS 12.0, *)
    private func monitorNetworkChanges() {
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "NetworkSendMonitor"))
        monitor.pathUpdateHandler = self.networkPathDidChange
    }

    
    @available(iOS 12.0, *)
    private func networkPathDidChange(nwPath: NWPath) {
        guard nwPath.status == .satisfied else { return }
        resetAllFailedSendAttempsCountersAndRetrySending()
    }

    
    func resetAllFailedSendAttempsCountersAndRetrySending() {
        failedFetchAttemptsCounterManager.resetAll()
        retryManager.executeAllWithNoDelay()
    }
    
}


// MARK: - Cleaning message/attachment/chunk files from the outbox

extension NetworkSendFlowCoordinator {
    
    func cleanOutboxForMessage(_ messageId: MessageIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        let messageURL = outbox.appendingPathComponent(messageId.directoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: messageURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: messageURL)
        } catch {
            os_log("Could not clean outbox for message %{public}@: %{public}@", log: log, type: .fault, messageId.debugDescription, error.localizedDescription)
        }
        
    }
    
    
}
