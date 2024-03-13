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


actor DeleteMessageAndAttachmentsFromServerCoordinator: DeleteMessageAndAttachmentsFromServerDelegate {
    
    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "NewDeleteMessageAndAttachmentsFromServerCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)

    weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()

    private var requestDeletionTaskCache = [ObvMessageIdentifier: RequestDeletionTask]()
    private enum RequestDeletionTask {
        case inProgress(Task<ObvServerDeleteMessageAndAttachmentsMethod.PossibleReturnStatus, Error>)
    }
    
    private var markAsListedTaskCache = [ObvMessageIdentifier: MarkAsListedTask]()
    private enum MarkAsListedTask {
        case inProgress(Task<ObvServerDeleteMessageAndAttachmentsMethod.PossibleReturnStatus, Error>)
    }
    
    func setDelegateManager(_ delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }

    private var cacheOfCurrentDeviceUIDForOwnedIdentity = [ObvCryptoIdentity: UID]()
    
}


// MARK: - Implementing DeleteMessageAndAttachmentsFromServerDelegate

extension DeleteMessageAndAttachmentsFromServerCoordinator {
    
    /// If there is no `PendingDeleteFromServer` for the message in DB, this method does nothing.
    /// Otherwise, it contacts the server to request the message deletion. If the server call is successful, the `PendingDeleteFromServer`
    /// entry is deleted from DB.
    func deleteMessage(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) async throws {
        
        guard let delegateManager else {
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        guard try await pendingDeleteFromServerExists(for: messageId, flowId: flowId) else {
            // Nothing to do
            return
        }
        
        let returnStatus = try await deleteOrMarkMessageAsListed(messageId: messageId, category: .requestDeletion, flowId: flowId)
        
        switch returnStatus {

        case .invalidSession, .generalError:

            // No need to inform the delegate that our session is invalid, this has been done already in deleteOrMarkMessageAsListed(messageId:category:flowId:)
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.processPendingDeleteFromServer(messageId: messageId))
            os_log("Will retry the call to deleteMessage in %f seconds", log: Self.log, type: .error, Double(delay) / 1000.0)
            await retryManager.waitForDelay(milliseconds: delay)
            try await deleteMessage(messageId: messageId, flowId: flowId)

        case .ok:

            failedAttemptsCounterManager.reset(counter: .processPendingDeleteFromServer(messageId: messageId))
            let op1 = DeletePendingDeleteFromServerAndInboxMessageAndAttachmentsOperation(messageId: messageId, inbox: delegateManager.inbox)
            do {
                try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
            } catch {
                throw ObvError.failedToDeletePendingDeleteFromServer
            }
            
        }
        
    }
    
    
    /// If the `InboxMessage` in database indicates that this message was already marked as listed on the server, this method does nothing.
    /// Otherwise, it contacts the server so that the message is marked as listed. If the server call is successful, the `InboxMessage` is modified in DB
    /// so as to indicate that this message was marked as listed on server.
    func markMessageAsListedOnServer(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) async throws {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        guard try await inboxMessageExistsAndIsNotMarkedAsListedOnServer(messageId: messageId, flowId: flowId) else {
            // Nothing to do
            return
        }
        
        let returnStatus = try await deleteOrMarkMessageAsListed(messageId: messageId, category: .markAsListed, flowId: flowId)
        
        switch returnStatus {
            
        case .invalidSession, .generalError:
            
            // No need to inform the delegate that our session is invalid, this has been done already in deleteOrMarkMessageAsListed(messageId:category:flowId:)
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.processPendingDeleteFromServer(messageId: messageId))
            os_log("Will retry the call to markMessageAsListedOnServer in %f seconds", log: Self.log, type: .error, Double(delay) / 1000.0)
            await retryManager.waitForDelay(milliseconds: delay)
            try await markMessageAsListedOnServer(messageId: messageId, flowId: flowId)
            
        case .ok:
            
            failedAttemptsCounterManager.reset(counter: .processPendingDeleteFromServer(messageId: messageId))
            let op1 = MarkInboxMessageAsListedOnServerOperation(messageId: messageId)
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
            
        }
        
    }
    
}


// MARK: - Main private method

extension DeleteMessageAndAttachmentsFromServerCoordinator {
    
    private func deleteOrMarkMessageAsListed(messageId: ObvMessageIdentifier, category: ObvServerDeleteMessageAndAttachmentsMethod.Category, flowId: FlowIdentifier) async throws -> ObvServerDeleteMessageAndAttachmentsMethod.PossibleReturnStatus {
        
        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        let sessionToken = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: messageId.ownedCryptoIdentity, currentInvalidToken: nil, flowId: flowId).serverSessionToken
        let currentDeviceUid = try await getCurrentDeviceUidOfOwnedIdentity(ownedCryptoIdentity: messageId.ownedCryptoIdentity, flowId: flowId)

        // Check if a previous task exists for the given category. If there is one, return its result when available.
        
        switch category {
        case .requestDeletion:
            if let cached = requestDeletionTaskCache[messageId] {
                switch cached {
                case .inProgress(let task):
                    return try await task.value
                }
            }
        case .markAsListed:
            if let cached = markAsListedTaskCache[messageId] {
                switch cached {
                case .inProgress(let task):
                    return try await task.value
                }
            }
        }
        
        // If we reach this point, no task exist. We create one and cache it (note that we must not have any call to an async method until that task is cached).

        let task = createTaskForDeletingOrMarkingMessageAsListed(
            messageId: messageId,
            category: category,
            sessionToken: sessionToken,
            currentDeviceUid: currentDeviceUid,
            delegateManager: delegateManager,
            flowId: flowId)
        
        switch category {
        case .requestDeletion:
            requestDeletionTaskCache[messageId] = .inProgress(task)
        case .markAsListed:
            markAsListedTaskCache[messageId] = .inProgress(task)
        }
        
        do {
            
            let returnStatus = try await task.value
            
            switch category {
            case .requestDeletion:
                requestDeletionTaskCache.removeValue(forKey: messageId)
            case .markAsListed:
                markAsListedTaskCache.removeValue(forKey: messageId)
            }
            
            switch returnStatus {
            case .invalidSession:
                _ = try await delegateManager.networkFetchFlowDelegate.getValidServerSessionToken(for: messageId.ownedCryptoIdentity, currentInvalidToken: sessionToken, flowId: flowId)
                return try await deleteOrMarkMessageAsListed(messageId: messageId, category: category, flowId: flowId)
            default:
                return returnStatus
            }
            
        } catch {
            
            switch category {
            case .requestDeletion:
                requestDeletionTaskCache.removeValue(forKey: messageId)
            case .markAsListed:
                markAsListedTaskCache.removeValue(forKey: messageId)
            }
            throw error
            
        }

    }
    
}


// MARK: - Helpers

extension DeleteMessageAndAttachmentsFromServerCoordinator {
    
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
    
    
    private func pendingDeleteFromServerExists(for messageId: ObvMessageIdentifier, flowId: FlowIdentifier) async throws -> Bool {
        
        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theContextCreatorIsNotSet
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let exists = try PendingDeleteFromServer.get(messageId: messageId, within: obvContext) != nil
                    continuation.resume(returning: exists)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
    
    private func inboxMessageExistsAndIsNotMarkedAsListedOnServer(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) async throws -> Bool {
        
        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theContextCreatorIsNotSet
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let returnValue = try InboxMessage.existsAndIsNotMarkedAsListedOnServer(messageId: messageId, within: obvContext)
                    continuation.resume(returning: returnValue)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

    }

 
    
    private func createTaskForDeletingOrMarkingMessageAsListed(messageId: ObvMessageIdentifier, category: ObvServerDeleteMessageAndAttachmentsMethod.Category, sessionToken: Data, currentDeviceUid: UID, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) -> Task<ObvServerDeleteMessageAndAttachmentsMethod.PossibleReturnStatus, Error> {
        
        return Task {
            
            let method = ObvServerDeleteMessageAndAttachmentsMethod(
                token: sessionToken,
                messageId: messageId,
                deviceUid: currentDeviceUid,
                category: category,
                flowId: flowId)
            method.identityDelegate = delegateManager.identityDelegate

            let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ObvError.invalidServerResponse
            }
            
            guard let returnStatus = ObvServerDeleteMessageAndAttachmentsMethod.parseObvServerResponse(responseData: data, using: Self.log) else {
                assertionFailure()
                throw ObvError.couldNotParseReturnStatusFromServer
            }
            
            switch returnStatus {
            case .ok:
                os_log("[🗑️ %{public}@] ObvServerDeleteMessageAndAttachmentsMethod(%{public}@) returned status %{public}@", log: Self.log, type: .debug, messageId.debugDescription, category.debugDescription, returnStatus.debugDescription)
            case .invalidSession:
                os_log("[🗑️ %{public}@] ObvServerDeleteMessageAndAttachmentsMethod(%{public}@) returned status %{public}@", log: Self.log, type: .error, messageId.debugDescription, category.debugDescription, returnStatus.debugDescription)
            case .generalError:
                os_log("[🗑️ %{public}@] ObvServerDeleteMessageAndAttachmentsMethod(%{public}@) returned status %{public}@", log: Self.log, type: .fault, messageId.debugDescription, category.debugDescription, returnStatus.debugDescription)
            }
            return returnStatus
            
        }

    }
    
}


// MARK: - Errors

extension DeleteMessageAndAttachmentsFromServerCoordinator {
    
    enum ObvError: LocalizedError {
        case theDelegateManagerIsNotSet
        case theIdentityDelegateIsNotSet
        case theContextCreatorIsNotSet
        case invalidServerResponse
        case couldNotParseReturnStatusFromServer
        case failedToDeletePendingDeleteFromServer
        
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
            case .failedToDeletePendingDeleteFromServer:
                return "Failed to delete pending delete from server"
            }
        }
    }

}
