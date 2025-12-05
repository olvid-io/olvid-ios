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
import OSLog
import ObvTypes
import OlvidUtils
import ObvServerInterface


actor BatchUploadMessagesWithoutAttachmentCoordinator {
    
    private static let defaultLogSubsystem = ObvNetworkSendDelegateManager.defaultLogSubsystem
    private static let logCategory = "BatchUploadMessagesWithoutAttachmentCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
    private static var logger = Logger(subsystem: defaultLogSubsystem, category: logCategory)

    private weak var delegateManager: ObvNetworkSendDelegateManager?

    init(logPrefix: String) {
        let logSubsystem = "\(logPrefix).\(Self.defaultLogSubsystem)"
        Self.log = OSLog(subsystem: logSubsystem, category: Self.logCategory)
        Self.logger = Logger(subsystem: logSubsystem, category: Self.logCategory)
    }

    func setDelegateManager(_ delegateManager: ObvNetworkSendDelegateManager) {
        self.delegateManager = delegateManager
    }

    /// Non-nil if there is an executing task currently uploading a batch of messages on the server with the given URL
    private var currentUploadTaskForServerURL = [URL: Task<Void, Error>]()
    
    private var failedAttemptsCounterManager = FailedFetchAttemptsCounterManager()
    private var retryManager = SendRetryManager()
    
    private static let defaultFetchLimit = 50 // hard limit
    private static let defaultMaxNumberOfHeaders = 1_000 // soft limit

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
        try await batchUploadMessagesWithoutAttachment(serverURL: serverURL, fetchLimit: Self.defaultFetchLimit, maxNumberOfHeaders: Self.defaultMaxNumberOfHeaders, flowId: flowId)
    }
    
    
    private func batchUploadMessagesWithoutAttachment(serverURL: URL, fetchLimit: Int, maxNumberOfHeaders: Int, flowId: FlowIdentifier) async throws {
        
        Self.logger.debug("Call to batchUploadMessagesWithoutAttachment with fetchLimit=\(fetchLimit)")
        ObvDisplayableLogs.shared.log("⬆️[BatchUploadMessagesWithoutAttachmentCoordinator] Call to batchUploadMessagesWithoutAttachment with fetchLimit=\(fetchLimit)")
        
        guard let delegateManager else {
            assertionFailure()
            throw ObvError.theDelegateManagerIsNil
        }
        
        do {
            try await internalBatchUploadMessagesWithoutAttachment(serverURL: serverURL, isFirstRequest: true, fetchLimit: fetchLimit, maxNumberOfHeaders: maxNumberOfHeaders, delegateManager: delegateManager, flowId: flowId)
            Self.logger.debug("The call to internalBatchUploadMessagesWithoutAttachment did succeed")
            ObvDisplayableLogs.shared.log("⬆️[BatchUploadMessagesWithoutAttachmentCoordinator] The call to internalBatchUploadMessagesWithoutAttachment did succeed")
            failedAttemptsCounterManager.reset(counter: .batchUploadMessages(serverURL: serverURL))
        } catch {
            Self.logger.error("The call to internalBatchUploadMessagesWithoutAttachment failed: \(error.localizedDescription)")
            ObvDisplayableLogs.shared.log("⬆️[BatchUploadMessagesWithoutAttachmentCoordinator] The call to internalBatchUploadMessagesWithoutAttachment failed: \(error.localizedDescription)")
            if let obvError = error as? ObvError {
                // Certain errors do not require us to wait before trying again
                switch obvError {
                case .serverQueryPayloadIsTooLargeForServer(let currentFetchLimit):
                    try await batchUploadMessagesWithoutAttachment(serverURL: serverURL, fetchLimit: max(1, currentFetchLimit / 2), maxNumberOfHeaders: max(1, maxNumberOfHeaders / 2), flowId: flowId)
                case .messageIsTooLargeForServer(messageToUpload: let messageToUpload):
                    // Delete the message that is too large to be uploaded
                    do {
                        let op1 = DeleteOutboxMessageTooLargeForServerOperation(messageId: messageToUpload.messageId)
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
            Self.logger.error("Will wait for \(delay) milliseconds before calling batchUploadMessagesWithoutAttachment again")
            ObvDisplayableLogs.shared.log("⬆️[BatchUploadMessagesWithoutAttachmentCoordinator] Will wait for \(delay) milliseconds before calling batchUploadMessagesWithoutAttachment again")
            await retryManager.waitForDelay(milliseconds: delay)
            try await batchUploadMessagesWithoutAttachment(serverURL: serverURL, flowId: flowId)
        }

    }
    
    
    private func internalBatchUploadMessagesWithoutAttachment(serverURL: URL, isFirstRequest: Bool, fetchLimit: Int, maxNumberOfHeaders: Int, delegateManager: ObvNetworkSendDelegateManager, flowId: FlowIdentifier) async throws {
        
        if let currentUploadTask = currentUploadTaskForServerURL[serverURL] {
            
            // An upload task already exists. If this is our first request, we await the end of this upload task and perform a recursive call. During the second call:
            // - If there is no upload task, we will create one and await for it
            // - If there is one, it's a new one, created after our first call => awaiting for it is sufficient
            
            if isFirstRequest {
                
                defer { if self.currentUploadTaskForServerURL[serverURL] == currentUploadTask { self.currentUploadTaskForServerURL.removeValue(forKey: serverURL) } }
                try await currentUploadTask.value
                try await internalBatchUploadMessagesWithoutAttachment(serverURL: serverURL, isFirstRequest: false, fetchLimit: fetchLimit, maxNumberOfHeaders: maxNumberOfHeaders, delegateManager: delegateManager, flowId: flowId)
                
            } else {
                
                defer { if self.currentUploadTaskForServerURL[serverURL] == currentUploadTask { self.currentUploadTaskForServerURL.removeValue(forKey: serverURL) } }
                try await currentUploadTask.value

            }

        } else {
            
            // There is no current upload task. We create one and execute it now.
            
            let localUploadTask = createTaskForUploadingBatchOfMessagesWithoutAttachment(serverURL: serverURL, fetchLimit: fetchLimit, maxNumberOfHeaders: maxNumberOfHeaders, delegateManager: delegateManager, flowId: flowId)
            
            self.currentUploadTaskForServerURL[serverURL] = localUploadTask
            defer { if self.currentUploadTaskForServerURL[serverURL] == localUploadTask { self.currentUploadTaskForServerURL.removeValue(forKey: serverURL) } }
            
            try await localUploadTask.value

        }
        
    }
    
}


extension BatchUploadMessagesWithoutAttachmentCoordinator {
    
    private func createTaskForUploadingBatchOfMessagesWithoutAttachment(serverURL: URL, fetchLimit: Int, maxNumberOfHeaders: Int, delegateManager: ObvNetworkSendDelegateManager, flowId: FlowIdentifier) -> Task<Void, Error> {
        
        return Task { [weak self] in
            
            guard let self else { return }
            
            let taskId = String(UUID().description.prefix(5))

            let messagesToUpload = try await getAllMessagesToUploadWithoutAttachments(serverURL: serverURL, fetchLimit: fetchLimit, maxNumberOfHeaders: maxNumberOfHeaders, delegateManager: delegateManager, flowId: flowId)
            
            Self.logger.debug("🎉 [\(taskId)] Starting the task for uploading \(messagesToUpload.count) messages without attachment")
            ObvDisplayableLogs.shared.log("⬆️[BatchUploadMessagesWithoutAttachmentCoordinator]🎉 [\(taskId)] Starting the task for uploading \(messagesToUpload.count) messages without attachment")

            guard !messagesToUpload.isEmpty else {
                // Nothing to upload
                Self.logger.debug("🎉 [\(taskId)] Nothing to upload, we are done with this task")
                ObvDisplayableLogs.shared.log("⬆️[BatchUploadMessagesWithoutAttachmentCoordinator]🎉 [\(taskId)] Nothing to upload, we are done with this task")
                return
            }
            
            let method = ObvServerBatchUploadMessages(serverURL: serverURL, messagesToUpload: messagesToUpload, flowId: flowId)
            
            let (data, response) = try await Self.urlSession.data(for: method.getURLRequest())
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ObvError.invalidServerResponse
            }

            Self.logger.debug("🎉 [\(taskId)] HTTP response status code is \(httpResponse.statusCode)")
            ObvDisplayableLogs.shared.log("⬆️[BatchUploadMessagesWithoutAttachmentCoordinator]🎉 [\(taskId)] HTTP response status code is \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                switch httpResponse.statusCode {
                case 413:
                    Self.logger.error("🎉 [\(taskId)] Payload is too large (fetchLimit is \(fetchLimit)")
                    ObvDisplayableLogs.shared.log("⬆️[BatchUploadMessagesWithoutAttachmentCoordinator]🎉 [\(taskId)] Payload is too large (fetchLimit is \(fetchLimit)")
                    if messagesToUpload.count == 1, let messageToUpload = messagesToUpload.first {
                        throw ObvError.messageIsTooLargeForServer(messageToUpload: messageToUpload)
                    } else {
                        throw ObvError.serverQueryPayloadIsTooLargeForServer(currentFetchLimit: fetchLimit)
                    }
                default:
                    Self.logger.fault("🎉 [\(taskId)] Unexpected status code \(httpResponse.statusCode). We treat it as if the payload is too large")
                    ObvDisplayableLogs.shared.log("⬆️🎉 [\(taskId)] Unexpected status code \(httpResponse.statusCode). Message is \(String(data: data, encoding: .utf8) ?? "-")")
                    throw ObvError.serverReturnedBadStatusCode(statusCode: httpResponse.statusCode)
                }
            }

            guard let returnStatus = ObvServerBatchUploadMessages.parseObvServerResponse(responseData: data) else {
                assertionFailure()
                Self.logger.error("🎉 [\(taskId)] Could not parse the return status from server")
                ObvDisplayableLogs.shared.log("⬆️[BatchUploadMessagesWithoutAttachmentCoordinator]🎉 [\(taskId)] Could not parse the return status from server")
                throw ObvError.couldNotParseReturnStatusFromServer
            }
            
            switch returnStatus {
                
            case .generalError:
                Self.logger.error("🎉 [\(taskId)] Server returned a general error")
                ObvDisplayableLogs.shared.log("⬆️[BatchUploadMessagesWithoutAttachmentCoordinator]🎉 [\(taskId)] Server returned a general error")
                throw ObvError.serverReturnedGeneralError
                
            case .payloadTooLarge:
                Self.logger.error("🎉 [\(taskId)] Server returned an error code indicating that at least one message has a too large payload")
                ObvDisplayableLogs.shared.log("⬆️[BatchUploadMessagesWithoutAttachmentCoordinator]🎉 [\(taskId)] Server returned an error code indicating that at least one message has a too large payload")
                // We adopt the exact same strategy as if the http code was 413
                if messagesToUpload.count == 1, let messageToUpload = messagesToUpload.first {
                    throw ObvError.messageIsTooLargeForServer(messageToUpload: messageToUpload)
                } else {
                    throw ObvError.serverQueryPayloadIsTooLargeForServer(currentFetchLimit: fetchLimit)
                }

            case .ok(let allValuesReturnedByServer):
                
                Self.logger.debug("🎉 [\(taskId)] Will process the ok from server")
                ObvDisplayableLogs.shared.log("⬆️[BatchUploadMessagesWithoutAttachmentCoordinator]🎉 [\(taskId)] Will process the ok from server")

                guard messagesToUpload.count == allValuesReturnedByServer.count else {
                    assertionFailure()
                    Self.logger.error("🎉 [\(taskId)] Unexpected number of values returned by the server. Expecting \(messagesToUpload.count), got \(allValuesReturnedByServer.count)")
                    ObvDisplayableLogs.shared.log("⬆️[BatchUploadMessagesWithoutAttachmentCoordinator]🎉 [\(taskId)] Unexpected number of values returned by the server. Expecting \(messagesToUpload.count), got \(allValuesReturnedByServer.count)")
                    throw ObvError.unexpectedNumberOfValuesReturnedByServer
                }
                
                let op1 = SaveReturnedServerValuesForBatchUploadedMessagesOperation(
                    valuesToSave: Array(zip(messagesToUpload, allValuesReturnedByServer)))
                
                Self.logger.debug("🎉 [\(taskId)] Will save the \(allValuesReturnedByServer.count) returned server values")
                ObvDisplayableLogs.shared.log("⬆️[BatchUploadMessagesWithoutAttachmentCoordinator]🎉 [\(taskId)] Will save the \(allValuesReturnedByServer.count) returned server values")

                try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
                
                Self.logger.debug("🎉 [\(taskId)] Did save the \(allValuesReturnedByServer.count) returned server values")
                ObvDisplayableLogs.shared.log("⬆️[BatchUploadMessagesWithoutAttachmentCoordinator]🎉 [\(taskId)] Did save the \(allValuesReturnedByServer.count) returned server values")

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
    
    
    private func getAllMessagesToUploadWithoutAttachments(serverURL: URL, fetchLimit: Int, maxNumberOfHeaders: Int, delegateManager: ObvNetworkSendDelegateManager, flowId: FlowIdentifier) async throws -> [ObvServerBatchUploadMessages.MessageToUpload] {
        
        guard let contextCreator = delegateManager.contextCreator else {
            assertionFailure()
            throw ObvError.theContextCreatorIsNotSet
        }
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ObvServerBatchUploadMessages.MessageToUpload], any Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let outboxMessages = try OutboxMessage.getAllMessagesToUploadWithoutAttachments(serverURL: serverURL, fetchLimit: fetchLimit, maxNumberOfHeaders: maxNumberOfHeaders, within: obvContext.context)
                    // 2025-05-07: We used to restrict to messages from active owned identities. We don't do that anymore as this prevents the sending of certain messages during a global deletion
                    // of a profile.
                    let messagesToUpload = outboxMessages
                        .compactMap({ try? ObvServerBatchUploadMessages.MessageToUpload(outboxMessage: $0) })
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
        case theContextCreatorIsNotSet // 0
        case theIdentityDelegateIsNotSet // 1
        case invalidServerResponse // 2
        case couldNotParseReturnStatusFromServer // 3
        case serverReturnedGeneralError // 4
        case unexpectedNumberOfValuesReturnedByServer // 5
        case theDelegateManagerIsNil // 6
        case serverQueryPayloadIsTooLargeForServer(currentFetchLimit: Int) // 7
        case messageIsTooLargeForServer(messageToUpload: ObvServerBatchUploadMessages.MessageToUpload) // 8

        case serverReturnedBadStatusCode(statusCode: Int) // 9
    }
    
}


// MARK: - Helpers

fileprivate extension ObvServerBatchUploadMessages.MessageToUpload {
    
    /// Initialises a `MessageToUpload` instance, suitable for the `ObvServerBatchUploadMessages` server method, from a given `OutboxMessage` core data instance.
    init(outboxMessage: OutboxMessage) throws {
        guard let messageId = outboxMessage.messageId else { throw ObvError.noMessageId }
        try self.init(messageId: messageId, headers: outboxMessage.headers.map { try .init(outboxMessageHeader: $0) },
                  encryptedContent: outboxMessage.encryptedContent,
                  isAppMessageWithUserContent: outboxMessage.isAppMessageWithUserContent,
                  isVoipMessageForStartingCall: outboxMessage.isVoipMessage)
    }
    
    enum ObvError: Error {
        case noMessageId
    }
    
}


fileprivate extension ObvServerBatchUploadMessages.MessageToUpload.Header {
    
    init(outboxMessageHeader: MessageHeader) throws {
        self.init(deviceUid: try outboxMessageHeader.deviceUid,
                  wrappedKey: try outboxMessageHeader.wrappedKey,
                  toIdentity: try outboxMessageHeader.toCryptoIdentity)
    }

}
