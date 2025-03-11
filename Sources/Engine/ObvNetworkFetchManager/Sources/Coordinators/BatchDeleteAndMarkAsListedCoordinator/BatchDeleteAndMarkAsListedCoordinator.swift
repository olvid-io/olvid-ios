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
import CoreData
import OlvidUtils


actor BatchDeleteAndMarkAsListedCoordinator: BatchDeleteAndMarkAsListedDelegate {
    
    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "BatchDeleteAndMarkAsListedCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
    private static var logger = Logger(subsystem: defaultLogSubsystem, category: logCategory)

    weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()

    private var currentTaskForOwnedCryptoIdentity = [ObvCryptoIdentity: Task<Void, Error>]()

    func setDelegateManager(_ delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }

    private var cacheOfCurrentDeviceUIDForOwnedIdentity = [ObvCryptoIdentity: UID]()
    
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


// MARK: - Implementing BatchDeleteAndMarkAsListedDelegate

extension BatchDeleteAndMarkAsListedCoordinator {
    
    /// This is called by the `MessagesCoordinator` just after saving to DB a slice of downloaded messages.
    func markSpecificMessagesAsListed(ownedCryptoId: ObvCryptoIdentity, messageUIDs: [UID], flowId: FlowIdentifier) async throws {
        
        guard !messageUIDs.isEmpty else { return }
        
        guard let delegateManager else {
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        do {
            let messageUIDsAndCategories: [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory] = messageUIDs.map({ .init(messageUID: $0, category: .markAsListed) })
            let taskId = String(UUID().description.prefix(5))
            try await requestDeleteMessageAndAttachments(ownedCryptoIdentity: ownedCryptoId,
                                                         messageUIDsAndCategories: messageUIDsAndCategories,
                                                         currentInvalidToken: nil,
                                                         delegateManager: delegateManager,
                                                         flowId: flowId,
                                                         taskId: taskId)
        } catch {
            Self.logger.fault("Could not mark specific messages as listed: \(error.localizedDescription)")
            assertionFailure()
            return
        }
        
    }
    
    
    func batchDeleteAndMarkAsListed(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws {
        try await batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: Self.defaultFetchLimit, flowId: flowId)
    }
    
    
    private func batchDeleteAndMarkAsListed(ownedCryptoIdentity: ObvCryptoIdentity, fetchLimit: Int, flowId: FlowIdentifier) async throws {
        
        os_log("Call to batchDeleteAndMarkAsListed", log: Self.log, type: .debug)
        
        guard let delegateManager else {
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        do {
            try await internalBatchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity, isFirstRequest: true, fetchLimit: fetchLimit, delegateManager: delegateManager, flowId: flowId)
            failedAttemptsCounterManager.reset(counter: .batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity))
        } catch {
            if let obvError = error as? ObvError {
                // Certain errors do not require us to wait before trying again
                switch obvError {
                case .serverQueryPayloadIsTooLargeForServer(let currentFetchLimit):
                    if currentFetchLimit > 1 {
                        try? await batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: currentFetchLimit / 2, flowId: flowId)
                        return
                    }
                case .tryAgainNowThatTheServerSessionIsValid:
                    try? await batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: fetchLimit, flowId: flowId)
                    return
                default:
                    break
                }
            }
            // If we reach this point, the error requires to wait for a certain delay.
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity))
            await retryManager.waitForDelay(milliseconds: delay)
            try await batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: fetchLimit, flowId: flowId)
        }

    }
    
    
    private func internalBatchDeleteAndMarkAsListed(ownedCryptoIdentity: ObvCryptoIdentity, isFirstRequest: Bool, fetchLimit: Int, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) async throws {
        
        if let currentTask = currentTaskForOwnedCryptoIdentity[ownedCryptoIdentity] {
            
            // An batch task already exists. If this is our first request, we await the end of this batch task and perform a recursive call. During the second call:
            // - If there is no batch task, we will create one and await for it
            // - If there is one, it's a new one, created after our first call => awaiting for it is sufficient
            
            if isFirstRequest {
                
                defer { if self.currentTaskForOwnedCryptoIdentity[ownedCryptoIdentity] == currentTask { self.currentTaskForOwnedCryptoIdentity.removeValue(forKey: ownedCryptoIdentity) } }
                try await currentTask.value
                try await internalBatchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity, isFirstRequest: false, fetchLimit: fetchLimit, delegateManager: delegateManager, flowId: flowId)
                
            } else {
                
                defer { if self.currentTaskForOwnedCryptoIdentity[ownedCryptoIdentity] == currentTask { self.currentTaskForOwnedCryptoIdentity.removeValue(forKey: ownedCryptoIdentity) } }
                
                try await currentTask.value

            }

        } else {
            
            // There is no current batch task. We create one and execute it now.
            
            let localTask = createBatchTask(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: fetchLimit, delegateManager: delegateManager, flowId: flowId)
            
            self.currentTaskForOwnedCryptoIdentity[ownedCryptoIdentity] = localTask
            defer { if self.currentTaskForOwnedCryptoIdentity[ownedCryptoIdentity] == localTask { self.currentTaskForOwnedCryptoIdentity.removeValue(forKey: ownedCryptoIdentity) } }
            
            try await localTask.value

        }

    }

    
    private func createBatchTask(ownedCryptoIdentity: ObvCryptoIdentity, fetchLimit: Int, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) -> Task<Void, Error> {
        return Task { [weak self] in
                                    
            guard let self else { return }
            
            let taskId = String(UUID().description.prefix(5))

            let messageUIDsAndCategories = try await fetchMessagesThatCanBeDeletedFromServerOrMarkedAsListed(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: fetchLimit, delegateManager: delegateManager)
            
            os_log("🎉 [%@] Starting the task for deleting from server, or marking as listed, %d received messages", log: Self.log, type: .debug, taskId, messageUIDsAndCategories.count)

            guard !messageUIDsAndCategories.isEmpty else {
                // Nothing to upload
                return
            }
            
            try await requestDeleteMessageAndAttachments(ownedCryptoIdentity: ownedCryptoIdentity,
                                                         messageUIDsAndCategories: messageUIDsAndCategories,
                                                         currentInvalidToken: nil,
                                                         delegateManager: delegateManager,
                                                         flowId: flowId,
                                                         taskId: taskId)
            
            Task { [weak self] in
                // Call this coordinator again, in case the batch was not large enough to delete/mark as listed all messages
                // Note that it is important that this is done outside of the upload task
                try? await self?.batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId)
            }
            
        }
    }
    
    
    private func requestDeleteMessageAndAttachments(ownedCryptoIdentity: ObvCryptoIdentity, messageUIDsAndCategories: [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory], currentInvalidToken: Data?, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier, taskId: String) async throws {
        
        let token = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: ownedCryptoIdentity, currentInvalidToken: currentInvalidToken, flowId: flowId).serverSessionToken
        let deviceUid = try await getCurrentDeviceUidOfOwnedIdentity(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId)
        
        let method = ObvServerDeleteMessageAndAttachmentsMethod(ownedCryptoId: ownedCryptoIdentity,
                                                                token: token,
                                                                deviceUid: deviceUid,
                                                                messageUIDsAndCategories: messageUIDsAndCategories,
                                                                flowId: flowId)
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.urlSession.data(for: method.getURLRequest())
        } catch {
            assertionFailure()
            throw error
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ObvError.invalidServerResponse
        }

        os_log("🎉 [%@] HTTP response status code is %d", log: Self.log, type: .debug, taskId, httpResponse.statusCode)

        guard httpResponse.statusCode == 200 else {
            switch httpResponse.statusCode {
            case 413:
                os_log("🎉 [%@] Payload is too large", log: Self.log, type: .debug, taskId)
                throw ObvError.serverQueryPayloadIsTooLargeForServer(currentFetchLimit: messageUIDsAndCategories.count)
            default:
                throw ObvError.serverReturnedBadStatusCode
            }
        }

        guard let returnStatus = ObvServerDeleteMessageAndAttachmentsMethod.parseObvServerResponse(responseData: data, using: Self.log) else {
            assertionFailure()
            throw ObvError.couldNotParseReturnStatusFromServer
        }
        
        switch returnStatus {
            
        case .generalError:
            
            assertionFailure()
            throw ObvError.serverReturnedGeneralError
            
        case .invalidSession:
            
            try await requestDeleteMessageAndAttachments(ownedCryptoIdentity: ownedCryptoIdentity,
                                                         messageUIDsAndCategories: messageUIDsAndCategories,
                                                         currentInvalidToken: token,
                                                         delegateManager: delegateManager,
                                                         flowId: flowId,
                                                         taskId: taskId)
            return
                        
        case .ok:
            os_log("🎉 [%@] Will process the ok from server", log: Self.log, type: .debug, taskId)
            let op1 = ProcessMessagesThatWereDeletedFromServerOrMarkedAsListedOnServerOperation(ownedCryptoIdentity: ownedCryptoIdentity, messageUIDsAndCategories: messageUIDsAndCategories, inbox: delegateManager.inbox)
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)

        }

    }
    
    
    private func fetchMessagesThatCanBeDeletedFromServerOrMarkedAsListed(ownedCryptoIdentity: ObvCryptoIdentity, fetchLimit: Int, delegateManager: ObvNetworkFetchDelegateManager) async throws -> [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory] {
        
        guard let contextCreator = delegateManager.contextCreator else {
            assertionFailure()
            throw ObvError.theContextCreatorIsNotSet
        }
                
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory], any Error>) in
            contextCreator.performBackgroundTask() { context in
                do {
                    let messages = try InboxMessage.fetchMessagesThatCanBeDeletedFromServerOrMarkedAsListed(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: fetchLimit, within: context)
                    return continuation.resume(returning: messages)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
}


// MARK: - Helpers

extension BatchDeleteAndMarkAsListedCoordinator {
    
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

        let currentDeviceUID = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UID, Error>) in
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

}


// MARK: - Errors

extension BatchDeleteAndMarkAsListedCoordinator {
    
    enum ObvError: LocalizedError {
        case theDelegateManagerIsNotSet
        case theIdentityDelegateIsNotSet
        case theContextCreatorIsNotSet
        case invalidServerResponse
        case couldNotParseReturnStatusFromServer
        case tryAgainNowThatTheServerSessionIsValid
        case serverReturnedGeneralError
        case serverQueryPayloadIsTooLargeForServer(currentFetchLimit: Int)
        case serverReturnedBadStatusCode

        
        var errorDescription: String? {
            switch self {
            case .theDelegateManagerIsNotSet:
                return "The delegate manager is not set"
            case .theIdentityDelegateIsNotSet:
                return "The identity delegate is not set"
            case .theContextCreatorIsNotSet:
                return "The context creator is not set"
            case .invalidServerResponse:
                return "Invalid server response"
            case .couldNotParseReturnStatusFromServer:
                return "Could not parse return status from server"
            case .tryAgainNowThatTheServerSessionIsValid:
                return "Try again now that the server session is valid"
            case .serverReturnedGeneralError:
                return "Server returned a general error"
            case .serverQueryPayloadIsTooLargeForServer(currentFetchLimit: let currentFetchLimit):
                return "Server query payload is too large for server (\(currentFetchLimit))"
            case .serverReturnedBadStatusCode:
                return "Server returned a bad status code"
            }
        }
    }

}
