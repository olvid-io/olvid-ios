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
import ObvTypes
import OlvidUtils
import ObvServerInterface


actor BatchUploadMessagesWithoutAttachmentCoordinator {
    
    private static let defaultLogSubsystem = ObvNetworkSendDelegateManager.defaultLogSubsystem
    private static let logCategory = "BatchUploadMessagesWithoutAttachmentCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)

    private weak var delegateManager: ObvNetworkSendDelegateManager?

    init(logPrefix: String) {
        let logSubsystem = "\(logPrefix).\(Self.defaultLogSubsystem)"
        Self.log = OSLog(subsystem: logSubsystem, category: Self.logCategory)
    }

    func setDelegateManager(_ delegateManager: ObvNetworkSendDelegateManager) {
        self.delegateManager = delegateManager
    }

    /// Non-nil if there is an executing task currently uploading a batch of messages on the server with the given URL
    private var currentUploadTaskForServerURL = [URL: Task<Void, Error>]()
    
    private var failedAttemptsCounterManager = FailedFetchAttemptsCounterManager()
    private var retryManager = SendRetryManager()
    
    private static let defaultFetchLimit = 50

    private static let urlSession: URLSession = {
        var configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = true
        configuration.isDiscretionary = false
        configuration.shouldUseExtendedBackgroundIdleMode = true
        configuration.waitsForConnectivity = false
        configuration.allowsConstrainedNetworkAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        let urlSession = URLSession(configuration: configuration)
        return urlSession
    }()

}


extension BatchUploadMessagesWithoutAttachmentCoordinator: BatchUploadMessagesWithoutAttachmentDelegate {
    
    func resetDelaysOnSatisfiedNetworkPath() {
        failedAttemptsCounterManager.resetAll()
    }
    
    
    func batchUploadMessagesWithoutAttachment(serverURL: URL, flowId: FlowIdentifier) async throws {
        try await batchUploadMessagesWithoutAttachment(serverURL: serverURL, fetchLimit: Self.defaultFetchLimit, flowId: flowId)
    }
    
    
    private func batchUploadMessagesWithoutAttachment(serverURL: URL, fetchLimit: Int, flowId: FlowIdentifier) async throws {
        
        os_log("Call to batchUploadMessagesWithoutAttachment with fetchLimit=%d", log: Self.log, type: .debug, fetchLimit)
        
        guard let delegateManager else {
            assertionFailure()
            throw ObvError.theDelegateManagerIsNil
        }
        
        do {
            try await internalBatchUploadMessagesWithoutAttachment(serverURL: serverURL, isFirstRequest: true, fetchLimit: fetchLimit, delegateManager: delegateManager, flowId: flowId)
            os_log("The call to internalBatchUploadMessagesWithoutAttachment did succeed", log: Self.log, type: .debug)
            failedAttemptsCounterManager.reset(counter: .batchUploadMessages(serverURL: serverURL))
        } catch {
            os_log("The call to internalBatchUploadMessagesWithoutAttachment failed: %{public}@", log: Self.log, type: .error, error.localizedDescription)
            if let obvError = error as? ObvError {
                // Certain errors do not require us to wait before trying again
                switch obvError {
                case .serverQueryPayloadIsTooLargeForServer(let currentFetchLimit):
                    if currentFetchLimit > 1 {
                        try? await batchUploadMessagesWithoutAttachment(serverURL: serverURL, fetchLimit: currentFetchLimit / 2, flowId: flowId)
                        return
                    }
                case .messageIsToolLargeForServer(messageToUpload: let messageToUpload):
                    // Delete the message that is too large to be uploaded
                    do {
                        let op1 = DeleteOutboxMessageTooLargeForServerOperation(messageId: messageToUpload.messageId, delegateManager: delegateManager)
                        try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
                    } catch {
                        assertionFailure()
                        // In production, continue anyway
                    }
                    // The message that was too large was deleted, there might be other messages to upload
                    try? await batchUploadMessagesWithoutAttachment(serverURL: serverURL, flowId: flowId)
                    return
                default:
                    break
                }
            }
            // If we reach this point, the error requires to wait for a certain delay.
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.batchUploadMessages(serverURL: serverURL))
            os_log("Will wait for %d milliseconds before calling batchUploadMessagesWithoutAttachment again", log: Self.log, type: .error, delay)
            await retryManager.waitForDelay(milliseconds: delay)
            try await batchUploadMessagesWithoutAttachment(serverURL: serverURL, flowId: flowId)
        }

    }
    
    
    private func internalBatchUploadMessagesWithoutAttachment(serverURL: URL, isFirstRequest: Bool, fetchLimit: Int, delegateManager: ObvNetworkSendDelegateManager, flowId: FlowIdentifier) async throws {
        
        if let currentUploadTask = currentUploadTaskForServerURL[serverURL] {
            
            // An upload task already exists. If this is our first request, we await the end of this upload task and perform a recursive call. During the second call:
            // - If there is no upload task, we will create one and await for it
            // - If there is one, it's a new one, created after our first call => awaiting for it is sufficient
            
            if isFirstRequest {
                
                defer { if self.currentUploadTaskForServerURL[serverURL] == currentUploadTask { self.currentUploadTaskForServerURL.removeValue(forKey: serverURL) } }
                try await currentUploadTask.value
                try await internalBatchUploadMessagesWithoutAttachment(serverURL: serverURL, isFirstRequest: false, fetchLimit: fetchLimit, delegateManager: delegateManager, flowId: flowId)
                
            } else {
                
                defer { if self.currentUploadTaskForServerURL[serverURL] == currentUploadTask { self.currentUploadTaskForServerURL.removeValue(forKey: serverURL) } }
                try await currentUploadTask.value

            }

        } else {
            
            // There is no current upload task. We create one and execute it now.
            
            let localUploadTask = createTaskForUploadingBatchOfMessagesWithoutAttachment(serverURL: serverURL, fetchLimit: fetchLimit, delegateManager: delegateManager, flowId: flowId)
            
            self.currentUploadTaskForServerURL[serverURL] = localUploadTask
            defer { if self.currentUploadTaskForServerURL[serverURL] == localUploadTask { self.currentUploadTaskForServerURL.removeValue(forKey: serverURL) } }
            
            try await localUploadTask.value

        }
        
    }
    
}


extension BatchUploadMessagesWithoutAttachmentCoordinator {
    
    private func createTaskForUploadingBatchOfMessagesWithoutAttachment(serverURL: URL, fetchLimit: Int, delegateManager: ObvNetworkSendDelegateManager, flowId: FlowIdentifier) -> Task<Void, Error> {
        
        return Task { [weak self] in
            
            guard let self else { return }
            
            let taskId = String(UUID().description.prefix(5))

            let messagesToUpload = try await getAllMessagesToUploadWithoutAttachmentsForActiveOwnedIdentities(serverURL: serverURL, fetchLimit: fetchLimit, delegateManager: delegateManager, flowId: flowId)
            
            os_log("🎉 [%@] Starting the task for uploading %d messages without attachment", log: Self.log, type: .debug, taskId, messagesToUpload.count)

            guard !messagesToUpload.isEmpty else {
                // Nothing to upload
                os_log("🎉 [%@] Nothing to upload, we are done with this task", log: Self.log, type: .debug, taskId)
                return
            }
            
            let method = ObvServerBatchUploadMessages(serverURL: serverURL, messagesToUpload: messagesToUpload, flowId: flowId)
            
            let (data, response) = try await Self.urlSession.data(for: method.getURLRequest())
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ObvError.invalidServerResponse
            }

            os_log("🎉 [%@] HTTP response status code is %d", log: Self.log, type: .debug, taskId, httpResponse.statusCode)

            guard httpResponse.statusCode == 200 else {
                switch httpResponse.statusCode {
                case 413:
                    os_log("🎉 [%@] Payload is too large (fetchLimit is %d)", log: Self.log, type: .error, taskId, fetchLimit)
                    if messagesToUpload.count == 1, let messageToUpload = messagesToUpload.first {
                        throw ObvError.messageIsToolLargeForServer(messageToUpload: messageToUpload)
                    } else {
                        throw ObvError.serverQueryPayloadIsTooLargeForServer(currentFetchLimit: fetchLimit)
                    }
                default:
                    throw ObvError.serverReturnedBadStatusCode
                }
            }

            guard let returnStatus = ObvServerBatchUploadMessages.parseObvServerResponse(responseData: data, using: Self.log) else {
                assertionFailure()
                os_log("🎉 [%@] Could not parse the return status from server", log: Self.log, type: .error, taskId)
                throw ObvError.couldNotParseReturnStatusFromServer
            }
            
            switch returnStatus {
                
            case .generalError:
                os_log("🎉 [%@] Server returned a general error", log: Self.log, type: .error, taskId)
                throw ObvError.serverReturnedGeneralError
                
            case .payloadTooLarge:
                os_log("🎉 [%@] Server returned an error code indicating that at least one message has a too large payload", log: Self.log, type: .error, taskId)
                // We adopt the exact same strategy as if the http code was 413
                if messagesToUpload.count == 1, let messageToUpload = messagesToUpload.first {
                    throw ObvError.messageIsToolLargeForServer(messageToUpload: messageToUpload)
                } else {
                    throw ObvError.serverQueryPayloadIsTooLargeForServer(currentFetchLimit: fetchLimit)
                }

            case .ok(let allValuesReturnedByServer):
                
                os_log("🎉 [%@] Will process the ok from server", log: Self.log, type: .debug, taskId)

                guard messagesToUpload.count == allValuesReturnedByServer.count else {
                    assertionFailure()
                    os_log("🎉 [%@] Unexpected number of values returned by the server. Expecting %d, got %d", log: Self.log, type: .error, taskId, messagesToUpload.count, allValuesReturnedByServer.count)
                    throw ObvError.unexpectedNumberOfValuesReturnedByServer
                }
                
                let op1 = SaveReturnedServerValuesForBatchUploadedMessagesOperation(
                    valuesToSave: Array(zip(messagesToUpload, allValuesReturnedByServer)),
                    delegateManager: delegateManager,
                    log: Self.log)
                
                os_log("🎉 [%@] Will save the %d returned server values", log: Self.log, type: .debug, taskId, allValuesReturnedByServer.count)

                try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
                
                os_log("🎉 [%@] Did save the %d returned server values", log: Self.log, type: .debug, taskId, allValuesReturnedByServer.count)

                Task.detached { [weak self] in
                    // Notify about the successful upload of each message
                    for messageId in messagesToUpload.map(\.messageId) {
                        delegateManager.networkSendFlowDelegate.successfulUploadOfMessage(messageId: messageId, flowId: flowId)
                    }
                    // Call this coordinator again, in case the batch was not large enough to upload all awaiting messages
                    // Note that it is important that this is done outside of the upload task
                    try? await self?.batchUploadMessagesWithoutAttachment(serverURL: serverURL, flowId: flowId)

                }
                
            }
            
        }
        
    }
    
    
    /// Returns a dictionary, where the keys are server URLs, and the values are all the `MessageToUpload` on the server indicated by the key.
    private func getAllMessagesToUploadWithoutAttachmentsForActiveOwnedIdentities(serverURL: URL, fetchLimit: Int, delegateManager: ObvNetworkSendDelegateManager, flowId: FlowIdentifier) async throws -> [ObvServerBatchUploadMessages.MessageToUpload] {
        
        guard let contextCreator = delegateManager.contextCreator else {
            assertionFailure()
            throw ObvError.theContextCreatorIsNotSet
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            assertionFailure()
            throw ObvError.theIdentityDelegateIsNotSet
        }
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ObvServerBatchUploadMessages.MessageToUpload], any Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let outboxMessages = try OutboxMessage.getAllMessagesToUploadWithoutAttachments(serverURL: serverURL, fetchLimit: fetchLimit, delegateManager: delegateManager, within: obvContext)
                    // Filter out messages corresponding to inactive owned identities and create one MessageToUpload per remaining OutboxMessage
                    let ownedCryptoIds = Set(outboxMessages.compactMap(\.messageId?.ownedCryptoIdentity))
                    let activeOwnedCryptoIds = ownedCryptoIds.filter { ownedCryptoId in
                        do {
                            return try identityDelegate.isOwnedIdentityActive(ownedIdentity: ownedCryptoId, flowId: flowId)
                        } catch {
                            assertionFailure()
                            return false
                        }
                    }
                    let messagesToUpload = outboxMessages
                        .filter {
                            guard let ownedCryptoIdentity = $0.messageId?.ownedCryptoIdentity else { return false }
                            return activeOwnedCryptoIds.contains(ownedCryptoIdentity)
                        }
                        .compactMap({ ObvServerBatchUploadMessages.MessageToUpload(outboxMessage: $0) })
                    // Return the resulting MessageToUpload instances
                    return continuation.resume(returning: messagesToUpload)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
}


extension BatchUploadMessagesWithoutAttachmentCoordinator {
    
    enum ObvError: Error {
        case theContextCreatorIsNotSet
        case theIdentityDelegateIsNotSet
        case invalidServerResponse
        case couldNotParseReturnStatusFromServer
        case serverReturnedGeneralError
        case unexpectedNumberOfValuesReturnedByServer
        case theDelegateManagerIsNil
        case serverQueryPayloadIsTooLargeForServer(currentFetchLimit: Int)
        case messageIsToolLargeForServer(messageToUpload: ObvServerBatchUploadMessages.MessageToUpload)

        case serverReturnedBadStatusCode
    }
    
}


// MARK: - Helpers

fileprivate extension ObvServerBatchUploadMessages.MessageToUpload {
    
    /// Initialises a `MessageToUpload` instance, suitable for the `ObvServerBatchUploadMessages` server method, from a given `OutboxMessage` core data instance.
    init?(outboxMessage: OutboxMessage) {
        guard let messageId = outboxMessage.messageId else { return nil }
        self.init(messageId: messageId, headers: outboxMessage.headers.map { .init(outboxMessageHeader: $0) },
                  encryptedContent: outboxMessage.encryptedContent,
                  isAppMessageWithUserContent: outboxMessage.isAppMessageWithUserContent,
                  isVoipMessageForStartingCall: outboxMessage.isVoipMessage)
    }
    
}


fileprivate extension ObvServerBatchUploadMessages.MessageToUpload.Header {
    
    init(outboxMessageHeader: MessageHeader) {
        self.init(deviceUid: outboxMessageHeader.deviceUid,
                  wrappedKey: outboxMessageHeader.wrappedKey,
                  toIdentity: outboxMessageHeader.toCryptoIdentity)
    }

}
