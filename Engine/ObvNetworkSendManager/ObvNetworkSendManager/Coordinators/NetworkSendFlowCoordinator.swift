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
import ObvTypes
import ObvOperation
import ObvMetaManager
import ObvCrypto
import Network
import OlvidUtils

final class NetworkSendFlowCoordinator: ObvErrorMaker {
    
    // MARK: - Instance variables
    
    fileprivate let defaultLogSubsystem = ObvNetworkSendDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "NetworkSendFlowCoordinator"

    static let errorDomain = "NetworkSendFlowCoordinator"

    private var failedFetchAttemptsCounterManager = FailedFetchAttemptsCounterManager()
    private var retryManager = SendRetryManager()
    private let outbox: URL
    private let nwPathMonitor = NWPathMonitor()
    
    private let queueForPostingNotifications = DispatchQueue(label: "Queue for posting certain notifications from the NetworkSendFlowCoordinator")
    
    weak var delegateManager: ObvNetworkSendDelegateManager?

    init(outbox: URL) {
        self.outbox = outbox
        monitorNetworkChanges()
    }

}


// MARK: - NetworkSendFlowDelegate

extension NetworkSendFlowCoordinator: NetworkSendFlowDelegate {
    

    func post(_ message: ObvNetworkMessageToSend, within obvContext: ObvContext) throws {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            throw Self.makeError(message: "The Delegate Manager is not set")
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
            throw Self.makeError(message: "Could not create outboxMessage in database")
        }
        
        for header in message.headers {
            _ = MessageHeader(message: outboxMessage,
                              toCryptoIdentity: header.toIdentity,
                              deviceUid: header.deviceUid,
                              wrappedKey: header.wrappedMessageKey)
        }
        
        var attachmentIds = [ObvAttachmentIdentifier]()
        if let attachments = message.attachments {
            var attachmentNumber = 0
            for attachment in attachments {
                _ = try OutboxAttachment(message: outboxMessage,
                                         attachmentNumber: attachmentNumber,
                                         fileURL: attachment.fileURL,
                                         deleteAfterSend: attachment.deleteAfterSend,
                                         byteSize: attachment.byteSize,
                                         key: attachment.key)
                let attachmentId = ObvAttachmentIdentifier(messageId: message.messageId, attachmentNumber: attachmentNumber)
                attachmentIds.append(attachmentId)
                
                attachmentNumber += 1
            }
        }
        
        do {
            try obvContext.addContextDidSaveCompletionHandler { [weak self] (error) in
                guard let self else { return }
                guard error == nil else { return }
                ObvNetworkPostNotification.newOutboxMessageAndAttachmentsToUpload(messageId: message.messageId, attachmentIds: attachmentIds, flowId: obvContext.flowId)
                    .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)
            }
        } catch {
            assertionFailure()
            os_log("Failed to notify that there is a new message and attachments to upload", log: log, type: .fault)
        }

    }
    
    
    func newOutboxMessage(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        os_log("Call to newOutboxMessage for message %{public}@ within flow %{public}@", log: log, type: .info, messageId.debugDescription, flowId.debugDescription)

        delegateManager.uploadMessageAndGetUidsDelegate.getIdFromServerUploadMessage(messageId: messageId, flowId: flowId)

    }
    
    
    func failedUploadAndGetUidOfMessage(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        os_log("We failed to upload and get uid for message %{public}@ within flow %{public}@", log: log, type: .error, messageId.debugDescription, flowId.debugDescription)
        
        let delay = failedFetchAttemptsCounterManager.incrementAndGetDelay(.uploadMessage(messageId: messageId))
        retryManager.executeWithDelay(delay) { [weak self] in
            self?.delegateManager?.uploadMessageAndGetUidsDelegate.getIdFromServerUploadMessage(messageId: messageId, flowId: flowId)
        }
    }

    
    func successfulUploadOfMessage(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) {
        
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
            
            guard let self else { return }
            
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
                failedUploadAndGetUidOfMessage(messageId: messageId, flowId: flowId)
                return
            }
            
            guard let notificationDelegate = delegateManager.notificationDelegate else {
                os_log("The notification delegate is not set (2)", log: log, type: .fault)
                return
            }
            
            ObvNetworkPostNotification.outboxMessageWasUploaded(messageId: messageId,
                                                                timestampFromServer: timestampFromServer,
                                                                isAppMessageWithUserContent: message.isAppMessageWithUserContent,
                                                                isVoipMessage: message.isVoipMessage,
                                                                flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)
            
        }
        
    }
    
    
    
    func messageAndAttachmentsWereExternallyCancelledAndCanSafelyBeDeletedNow(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        delegateManager.tryToDeleteMessageAndAttachmentsDelegate.tryToDeleteMessageAndAttachments(messageId: messageId, flowId: flowId)

    }
    
    
    
    func newProgressForAttachment(attachmentId: ObvAttachmentIdentifier) {
        failedFetchAttemptsCounterManager.reset(counter: .uploadAttachment(attachmentId: attachmentId))
    }

    
    func requestUploadAttachmentProgressesUpdatedSince(date: Date) async throws -> [ObvAttachmentIdentifier: Float] {
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            throw Self.makeError(message: "The Delegate Manager is not set")
        }
        return await delegateManager.uploadAttachmentChunksDelegate.requestUploadAttachmentProgressesUpdatedSince(date: date)
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
            os_log("🌊 Unexpected background session identifier: %{public}@", log: log, type: .fault, identifer)
            assertionFailure()
        }
    }
    
    
    
    func acknowledgedAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) {
        
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
        
        ObvNetworkPostNotification.outboxAttachmentWasAcknowledged(attachmentId: attachmentId, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

        delegateManager.tryToDeleteMessageAndAttachmentsDelegate.tryToDeleteMessageAndAttachments(messageId: attachmentId.messageId, flowId: flowId)
                
    }

    
    func attachmentFailedToUpload(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) {
        let delay = failedFetchAttemptsCounterManager.incrementAndGetDelay(.uploadAttachment(attachmentId: attachmentId))
        retryManager.executeWithDelay(delay) { [weak self] in
            self?.delegateManager?.uploadAttachmentChunksDelegate.resumeMissingAttachmentUploads(flowId: flowId)
        }
    }
    
    func signedURLsDownloadFailedForAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) {
        let delay = failedFetchAttemptsCounterManager.incrementAndGetDelay(.uploadAttachment(attachmentId: attachmentId))
        retryManager.executeWithDelay(delay) { [weak self] in
            self?.delegateManager?.uploadAttachmentChunksDelegate.downloadSignedURLsForAttachments(attachmentIds: [attachmentId], flowId: flowId)
        }
    }


    func messageAndAttachmentsWereDeletedFromTheirOutboxes(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) {

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

        ObvNetworkPostNotification.outboxMessageAndAttachmentsDeleted(messageId: messageId, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)

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

        ObvNetworkPostNotification.postNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ownedIdentity, flowId: flowId)
            .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)
        
    }
        
    // MARK: - Monitor Network Path Status
    
    private func monitorNetworkChanges() {
        nwPathMonitor.start(queue: DispatchQueue(label: "NetworkSendMonitor"))
        nwPathMonitor.pathUpdateHandler = self.networkPathDidChange
    }

    
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
    
    func cleanOutboxForMessage(_ messageId: ObvMessageIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        // Legacy cleaning
        for legacyDirectoryNameForMessageAttachments in messageId.legacyDirectoryNamesForMessageAttachments {
            let messageURL = outbox.appendingPathComponent(legacyDirectoryNameForMessageAttachments, isDirectory: true)
            if FileManager.default.fileExists(atPath: messageURL.path) {
                do {
                    try FileManager.default.removeItem(at: messageURL)
                } catch {
                    os_log("Could not clean outbox for message %{public}@: %{public}@", log: log, type: .fault, messageId.debugDescription, error.localizedDescription)
                }
            }
        }
        
        // Non-legacy cleaning
        do {
            let messageURL = outbox.appendingPathComponent(messageId.directoryNameForMessageAttachments, isDirectory: true)
            if FileManager.default.fileExists(atPath: messageURL.path) {
                do {
                    try FileManager.default.removeItem(at: messageURL)
                } catch {
                    os_log("Could not clean outbox for message %{public}@: %{public}@", log: log, type: .fault, messageId.debugDescription, error.localizedDescription)
                }
            }
        }

    }
    
}
