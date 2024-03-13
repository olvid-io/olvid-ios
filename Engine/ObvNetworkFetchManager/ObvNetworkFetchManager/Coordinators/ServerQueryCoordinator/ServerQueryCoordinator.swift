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
import CoreData
import os.log
import ObvServerInterface
import ObvMetaManager
import ObvTypes
import ObvEncoder
import ObvCrypto
import OlvidUtils


actor ServerQueryCoordinator {

    // MARK: - Instance variables

    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "ServerQueryCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)

    private weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    private var cacheOfPostingServerQuery = [NSManagedObjectID: PostingServerQuery]()
    typealias TaskForPostingServerQueryAndProcessingServerResult = Task<ProcessServerResponseToPendingServerQueryOperation.PostOperationAction,Error>
    private enum PostingServerQuery {
        case inProgress(task: TaskForPostingServerQueryAndProcessingServerResult)
    }
    
    /// After posting a server query and processing the result, we need to perform post actions. This cache makes sure we perform these actions only once.
    private var cachedForExecutingActionToPerformAfterPostingServerQuery = [ProcessServerResponseToPendingServerQueryOperation.PostOperationAction: ExecutingActionToPerformAfterPostingServerQuery]()
    enum ExecutingActionToPerformAfterPostingServerQuery {
        case inProgress(task: Task<Void,Error>)
        case done
    }
    
    private var cachedForProcessingErrorOfFailedPostedServerQuery = [NSManagedObjectID: ProcessingErrorOfFailedPostedServerQuery]()
    private enum ProcessingErrorOfFailedPostedServerQuery {
        case inProgress(task: Task<Void,Error>)
    }

    private var session: URLSession {
        URLSession.shared
    }

    /// We create a specific session for the case when the query is a Keycloak revocation test. The reason: the keycloak might not be reachable (e.g., the keycloak is on a private network)
    /// and we need the test to fail when it is the case. This is only possible if the `waitsForConnectivity` parameter is false.
    private lazy var sessionForKeycloakRevocation: URLSession! = {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.useOlvidSettings(sharedContainerIdentifier: delegateManager?.sharedContainerIdentifier)
        sessionConfiguration.waitsForConnectivity = false // So as to fail early if the keycloak server is not available
        return URLSession(configuration: sessionConfiguration, delegate: nil, delegateQueue: nil)
    }()

    
    let prng: PRNGService
    let downloadedUserData: URL
    private var notificationCenterTokens = [NSObjectProtocol]()

    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()
    
    init(prng: PRNGService, downloadedUserData: URL, logPrefix: String) {
        self.prng = prng
        self.downloadedUserData = downloadedUserData
        let logSubsystem = "\(logPrefix).\(Self.defaultLogSubsystem)"
        Self.log = OSLog(subsystem: logSubsystem, category: Self.logCategory)
    }

    
    deinit {
        guard let delegateManager else { return }
        notificationCenterTokens.forEach { delegateManager.notificationDelegate?.removeObserver($0) }
    }

    
    func setDelegateManager(_ delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }
    
    
    func finalizeInitialization(flowId: FlowIdentifier) async {
        guard let notificationDelegate = delegateManager?.notificationDelegate else { assertionFailure(); return }
        notificationCenterTokens.append(contentsOf: [
            ObvIdentityNotificationNew.observeOwnedIdentityWasReactivated(within: notificationDelegate) { [weak self] (ownedCryptoId, flowId) in
                Task { [weak self] in
                    do {
                        try await self?.processAllPendingServerQueries(for: ownedCryptoId, flowId: flowId)
                    } catch {
                        assertionFailure()
                    }
                }
            },
        ])
    }

}


// MARK: - ServerQueryDelegate

extension ServerQueryCoordinator: ServerQueryDelegate {

    /// Given a ``PendingServerQuery``, this method post the appropriate server method, save the result, and execute post operations. By the end of this method, the
    /// server ``PendingServerQuery`` is fully processed and deleted from database.
    func processPendingServerQuery(pendingServerQueryObjectID: NSManagedObjectID, flowId: FlowIdentifier) async throws {

        os_log("🖲️ Call to processPendingServerQuery for pending server query %{public}@", log: Self.log, type: .info, pendingServerQueryObjectID.debugDescription)

        guard let delegateManager else {
            os_log("🖲️ The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.delegateManagerIsNil
        }
        
        guard let channelDelegate = delegateManager.channelDelegate else {
            os_log("🖲️ The channel delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.channelDelegateIsNil
        }
                
        // Post and process server result
        
        let actionToPerformAfterPostingServerQuery: ProcessServerResponseToPendingServerQueryOperation.PostOperationAction
        
        do {
            
            if let cached = cacheOfPostingServerQuery[pendingServerQueryObjectID] {
                
                switch cached {
                case .inProgress(task: let task):
                    os_log("🖲️ Found an inProgress task for posting server query and processing result of pending server query %{public}@", log: Self.log, type: .info, pendingServerQueryObjectID.debugDescription)
                    actionToPerformAfterPostingServerQuery = try await task.value
                }
                
            } else {
                
                let task = try createTaskForPostingServerQueryAndProcessingServerResult(
                    pendingServerQueryObjectID: pendingServerQueryObjectID,
                    delegateManager: delegateManager,
                    flowId: flowId)
                do {
                    cacheOfPostingServerQuery[pendingServerQueryObjectID] = .inProgress(task: task)
                    os_log("🖲️ Created and cached a task for posting server query and processing result of pending server query %{public}@", log: Self.log, type: .info, pendingServerQueryObjectID.debugDescription)
                    actionToPerformAfterPostingServerQuery = try await task.value
                    cacheOfPostingServerQuery.removeValue(forKey: pendingServerQueryObjectID)
                } catch {
                    cacheOfPostingServerQuery.removeValue(forKey: pendingServerQueryObjectID)
                    throw error
                }
                
            }
            
        } catch {
            
            try await executeActionToPerformAfterPostingServerQueryThatFailed(
                error: error,
                pendingServerQueryObjectID: pendingServerQueryObjectID,
                delegateManager: delegateManager,
                channelDelegate: channelDelegate,
                flowId: flowId)
            return

        }
        
        // The server method has been posted and the value returned by the server has been save to the PendingServerQuery.
        // There is an action to perform.
        
        try await executeActionToPerformAfterPostingServerQuery(
            actionToPerformAfterPostingServerQuery: actionToPerformAfterPostingServerQuery,
            delegateManager: delegateManager,
            channelDelegate: channelDelegate,
            flowId: flowId)
        
    }
    
    
    func processAllPendingServerQueries(for ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws {
        
        guard let delegateManager else {
            os_log("🖲️ The delegate manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.delegateManagerIsNil
        }
        
        let pendingServerQueryObjectIDs = try await getObjectIDsOfNonWebSocketServerQueries(
            ownedCryptoId: ownedCryptoId,
            delegateManager: delegateManager,
            flowId: flowId)
        
        for pendingServerQueryObjectID in pendingServerQueryObjectIDs {
            do {
                try await processPendingServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID, flowId: flowId)
            } catch {
                os_log("🖲️ Could not post server query: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                continue
            }
        }
        
    }
    
    
    func processAllPendingServerQuery(flowId: FlowIdentifier) async throws {
        
        guard let delegateManager else {
            os_log("🖲️ The delegate manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.delegateManagerIsNil
        }
        
        let pendingServerQueryObjectIDs = try await getObjectIDsOfNonWebSocketServerQueries(
            ownedCryptoId: nil,
            delegateManager: delegateManager,
            flowId: flowId)
        
        for pendingServerQueryObjectID in pendingServerQueryObjectIDs {
            do {
                try await processPendingServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID, flowId: flowId)
            } catch {
                os_log("🖲️ Could not post server query: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                continue
            }
        }

    }


    /// Used during boostrap
    func deletePendingServerQueryOfNonExistingOwnedIdentities(flowId: FlowIdentifier) async throws {
        
        guard let delegateManager else {
            os_log("🖲️ The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.delegateManagerIsNil
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("🖲️ The identity delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.identityDelegateIsNil
        }

        let op1 = DeletePendingServerQueryOfNonExistingOwnedIdentitiesOperation(
            delegateManager: delegateManager,
            identityDelegate: identityDelegate)
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            assertionFailure()
            throw ObvError.failedToDeletePendingServerQueryOfNonExistingOwnedIdentities
        }
        
    }

}


// MARK: - Helpers

extension ServerQueryCoordinator {
    
    
    /// The task allowing to post a server query to the server and to save the returned values always has an action to perform afterwards. This method creates a task
    /// allowing to perform this action.
    private func createTaskForExecutingActionToPerformAfterPostingServerQuery(actionToPerformAfterPostingServerQuery: ProcessServerResponseToPendingServerQueryOperation.PostOperationAction, delegateManager: ObvNetworkFetchDelegateManager, channelDelegate: ObvChannelDelegate, flowId: FlowIdentifier) -> Task<Void,Error> {
        Task {
            
            os_log("🖲️ Executing TaskForExecutingActionToPerformAfterPostingServerQuery for action %{public}@", log: Self.log, type: .info, actionToPerformAfterPostingServerQuery.debugDescription)
            
            switch actionToPerformAfterPostingServerQuery {
                
            case .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: let objectId):
                failedAttemptsCounterManager.reset(counter: .serverQuery(objectID: objectId))
                let op1 = RespondAndDeleteServerQueryOperation(
                    objectIdOfPendingServerQuery: objectId,
                    prng: prng,
                    delegateManager: delegateManager,
                    channelDelegate: channelDelegate)
                do {
                    try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
                } catch {
                    assertionFailure()
                    return
                }
                
            case .shouldBeProcessedByServerQueryWebSocketCoordinator:
                assertionFailure()
                
            case .retryLater(pendingServerQueryObjectID: let objectId):
                let delay = failedAttemptsCounterManager.incrementAndGetDelay(.serverQuery(objectID: objectId))
                os_log("🖲️ Executing TaskForExecutingActionToPerformAfterPostingServerQuery. Will wait for delay: %f seconds", log: Self.log, type: .error, Double(delay) / 1000.0)
                await retryManager.waitForDelay(milliseconds: delay)
                throw ObvError.retryNow(pendingServerQueryObjectID: objectId)
                                
            case .retryAsSessionIsInvalid(pendingServerQueryObjectID: let objectId, ownedCryptoId: let ownedCryptoId, invalidToken: let invalidToken):
                failedAttemptsCounterManager.reset(counter: .serverQuery(objectID: objectId))
                _ = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: ownedCryptoId, currentInvalidToken: invalidToken, flowId: flowId)
                throw ObvError.retryNow(pendingServerQueryObjectID: objectId)

            case .pendingServerQueryNotFound:
                return
                
            case .cancelAsOwnedIdentityIsNotActive:
                return
                
            }
            
        }
    }

    
    /// Creates a task executed in ``processPendingServerQuery(pendingServerQueryObjectID:flowId:)``. This task allows to
    /// - Extract values from the ``PendingServerQuery`` to be posted to the server
    /// - Post the values to the server
    /// - Save the result returned by the server
    /// This task returns an action to be performed (e.g., retrying if something went wrong, or returning the a result to the protocol manager through the channel manager, etc.)
    private func createTaskForPostingServerQueryAndProcessingServerResult(pendingServerQueryObjectID: NSManagedObjectID, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) throws -> TaskForPostingServerQueryAndProcessingServerResult {
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("🖲️ The identity delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.identityDelegateIsNil
        }

        return Task {
            
            let op1 = GetPendingServerQueryTypeOperation(
                pendingServerQueryObjectID: pendingServerQueryObjectID,
                delegateManager: delegateManager,
                identityDelegate: identityDelegate)
            do {
                try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
            } catch {
                if let reasonForCancel = op1.reasonForCancel {
                    switch reasonForCancel {
                    case .pendingServerQueryNotFound:
                        return .pendingServerQueryNotFound
                    case .ownedIdentityIsNotActive:
                        return .cancelAsOwnedIdentityIsNotActive
                    default:
                        break
                    }
                }
                assertionFailure()
                throw ObvError.failedToGetPendingServerQueryType
            }
                        
            guard let (queryType, ownedCryptoId) = op1.queryTypeAndOwnedCryptoId else {
                assertionFailure("Although op1 is finished and did not cancel, it does not specify queryType. This is a bug.")
                throw ObvError.failedToGetPendingServerQueryType
            }
            
            os_log("🖲️ Server query %{public}@ type is %{public}@", log: Self.log, type: .info, pendingServerQueryObjectID.debugDescription, queryType.debugDescription)
            
            // Perform the server query
            
            let (responseData, urlResponse, sessionTokenUsed) = try await performServerMethodForGivenServerQueryType(
                queryType: queryType,
                ownedCryptoId: ownedCryptoId,
                delegateManager: delegateManager,
                flowId: flowId)
            
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                assertionFailure()
                throw ObvError.serverReturnedNonHTTPURLResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                switch httpResponse.statusCode {
                case 413:
                    throw ObvError.serverQueryPayloadIsTooLargeForServer
                default:
                    throw ObvError.serverReturnedBadStatusCode
                }
            }
            
            // Save the result returned by the server
            
            let op2 = ProcessServerResponseToPendingServerQueryOperation(
                pendingServerQueryObjectID: pendingServerQueryObjectID,
                responseData: responseData,
                log: Self.log,
                delegateManager: delegateManager,
                downloadedUserData: downloadedUserData, 
                sessionTokenUsed: sessionTokenUsed)
            do {
                try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op2, log: Self.log, flowId: flowId)
            } catch {
                assertionFailure()
                throw ObvError.failedToGetPendingServerQueryType
            }

            guard let postOperationAction = op2.postOperationAction else {
                assertionFailure("The op did not cancel so the postOperationAction should be set. This is a bug.")
                assertionFailure()
                throw ObvError.failedToGetPendingServerQueryType
            }
            
            return postOperationAction
            
        }
        
    }
    
    

    private func executeActionToPerformAfterPostingServerQuery(actionToPerformAfterPostingServerQuery: ProcessServerResponseToPendingServerQueryOperation.PostOperationAction, delegateManager: ObvNetworkFetchDelegateManager, channelDelegate: ObvChannelDelegate, flowId: FlowIdentifier) async throws {
        
        // Perform post-processing operation action
        
        if let cached = cachedForExecutingActionToPerformAfterPostingServerQuery[actionToPerformAfterPostingServerQuery] {
            
            switch cached {
            case .inProgress(task: let taskForExecutingActionAfterPostingServerQuery):
                os_log("🖲️ Found a cached inProgress task for executing action after posting server query for action %{public}@", log: Self.log, type: .info, actionToPerformAfterPostingServerQuery.debugDescription)
                try await taskForExecutingActionAfterPostingServerQuery.value
            case .done:
                os_log("🖲️ Found a cached done task for executing action after posting server query for action %{public}@", log: Self.log, type: .info, actionToPerformAfterPostingServerQuery.debugDescription)
                return
            }
            
        } else {
            
            os_log("🖲️ Creating and caching a task for executing action after posting server query for action %{public}@", log: Self.log, type: .info, actionToPerformAfterPostingServerQuery.debugDescription)
            
            let taskForExecutingActionAfterPostingServerQuery = createTaskForExecutingActionToPerformAfterPostingServerQuery(
                actionToPerformAfterPostingServerQuery: actionToPerformAfterPostingServerQuery,
                delegateManager: delegateManager,
                channelDelegate: channelDelegate,
                flowId: flowId)
            
            do {
                cachedForExecutingActionToPerformAfterPostingServerQuery[actionToPerformAfterPostingServerQuery] = .inProgress(task: taskForExecutingActionAfterPostingServerQuery)
                try await taskForExecutingActionAfterPostingServerQuery.value
                cachedForExecutingActionToPerformAfterPostingServerQuery[actionToPerformAfterPostingServerQuery] = .done
            } catch {
                cachedForExecutingActionToPerformAfterPostingServerQuery.removeValue(forKey: actionToPerformAfterPostingServerQuery)
                if let error = error as? ObvError {
                    switch error {
                    case .retryNow(pendingServerQueryObjectID: let pendingServerQueryObjectID):
                        os_log("🖲️ Will retry to process pending server query %{public}@", log: Self.log, type: .info, pendingServerQueryObjectID.debugDescription)
                        try await processPendingServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID, flowId: flowId)
                        return
                    default:
                        break
                    }
                }
                throw error
            }
            
        }
        
    }
    
    
    /// Called to process the error thrown when the posting of a server query fails.
    private func executeActionToPerformAfterPostingServerQueryThatFailed(error: Error, pendingServerQueryObjectID: NSManagedObjectID, delegateManager: ObvNetworkFetchDelegateManager, channelDelegate: ObvChannelDelegate, flowId: FlowIdentifier) async throws {
     
        if let cached = cachedForProcessingErrorOfFailedPostedServerQuery[pendingServerQueryObjectID] {
            
            switch cached {
            case .inProgress(task: let taskForProcessingErrorOfFailedPostedServerQuery):
                os_log("🖲️ Found a cached inProgress task for processing error of failed posted server query", log: Self.log, type: .info)
                try await taskForProcessingErrorOfFailedPostedServerQuery.value
            }
            
        } else {
            
            os_log("🖲️ Creating and caching a task for processing error of failed posted server query", log: Self.log, type: .info)
            
            let taskForProcessingErrorOfServerQueryThatFailed = createTaskForProcessingErrorOfServerQueryThatFailed(
                error: error,
                pendingServerQueryObjectID: pendingServerQueryObjectID,
                delegateManager: delegateManager,
                channelDelegate: channelDelegate,
                flowId: flowId)
            
            do {
                cachedForProcessingErrorOfFailedPostedServerQuery[pendingServerQueryObjectID] = .inProgress(task: taskForProcessingErrorOfServerQueryThatFailed)
                try await taskForProcessingErrorOfServerQueryThatFailed.value
                cachedForProcessingErrorOfFailedPostedServerQuery.removeValue(forKey: pendingServerQueryObjectID)
            } catch {
                cachedForProcessingErrorOfFailedPostedServerQuery.removeValue(forKey: pendingServerQueryObjectID)
                if let error = error as? ObvError {
                    switch error {
                    case .retryNow(pendingServerQueryObjectID: let pendingServerQueryObjectID):
                        os_log("🖲️ Will retry to process pending server query %{public}@", log: Self.log, type: .info, pendingServerQueryObjectID.debugDescription)
                        try await processPendingServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID, flowId: flowId)
                        return
                    default:
                        break
                    }
                }
                throw error
            }
            
        }

    }
    
    
    private func createTaskForProcessingErrorOfServerQueryThatFailed(error: Error, pendingServerQueryObjectID: NSManagedObjectID, delegateManager: ObvNetworkFetchDelegateManager, channelDelegate: ObvChannelDelegate, flowId: FlowIdentifier) -> Task<Void, Error> {
        Task {
            
            let op1: SetFailureResponseOnPendingServerQueryIfAppropriate
            
            if let error = error as? ObvError {
                switch error {
                case .serverQueryPayloadIsTooLargeForServer:
                    op1 = SetFailureResponseOnPendingServerQueryIfAppropriate(pendingServerQueryObjectID: pendingServerQueryObjectID, condition: .none, delegateManager: delegateManager)
                default:
                    op1 = SetFailureResponseOnPendingServerQueryIfAppropriate(pendingServerQueryObjectID: pendingServerQueryObjectID, condition: .ifServerQueryIsTooOld, delegateManager: delegateManager)
                }
            } else {
                op1 = SetFailureResponseOnPendingServerQueryIfAppropriate(pendingServerQueryObjectID: pendingServerQueryObjectID, condition: .ifServerQueryIsTooOld, delegateManager: delegateManager)
            }
            
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
            guard let postOperationAction = op1.postOperationAction else { assertionFailure(); return }
            switch postOperationAction {
            case .postResponseAndDeleteServerQuery(let pendingServerQueryObjectID):
                let op1 = RespondAndDeleteServerQueryOperation(
                    objectIdOfPendingServerQuery: pendingServerQueryObjectID,
                    prng: prng,
                    delegateManager: delegateManager,
                    channelDelegate: channelDelegate)
                try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
                return
            case .shouldBeProcessedByServerQueryWebSocketCoordinator:
                assertionFailure()
                return
            case .doNothingAsPendingServerQueryCannotBeFound:
                return
            case .retryLater:
                // The server query that failed is not old enough to be deleted. We throw.
                let delay = failedAttemptsCounterManager.incrementAndGetDelay(.serverQuery(objectID: pendingServerQueryObjectID))
                os_log("🖲️ Executing TaskForProcessingErrorOfServerQueryThatFailed. Will wait for delay: %f seconds", log: Self.log, type: .error, Double(delay) / 1000.0)
                await retryManager.waitForDelay(milliseconds: delay)
                throw ObvError.retryNow(pendingServerQueryObjectID: pendingServerQueryObjectID)
            }

        }
    }

    
    private func getObjectIDsOfNonWebSocketServerQueries(ownedCryptoId: ObvCryptoIdentity?, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) async throws -> Set<NSManagedObjectID> {
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("🖲️ The context creator manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.contextCreatorIsNil
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<NSManagedObjectID>, Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let serverQueries: [PendingServerQuery]
                    if let ownedCryptoId {
                        serverQueries = try PendingServerQuery.getAllServerQuery(for: ownedCryptoId, isWebSocket: .bool(false), delegateManager: delegateManager, within: obvContext)
                    } else {
                        serverQueries = try PendingServerQuery.getAllServerQuery(isWebSocket: .bool(false), delegateManager: delegateManager, within: obvContext)
                    }
                    let objectIDs = serverQueries.map { $0.objectID }
                    return continuation.resume(returning: Set(objectIDs))
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
    
    /// Used to post the appropriate server query for the given server query type.
    /// If a session token was used to perform the query, it is returned (handy if we later need to retry because this token was invalid).
    private func performServerMethodForGivenServerQueryType(queryType: ServerQuery.QueryType, ownedCryptoId: ObvCryptoIdentity, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) async throws -> (returnedData: Data, urlResponse: URLResponse, sessionToken: Data?) {
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            assertionFailure()
            throw ObvError.identityDelegateIsNil
        }
        
        let serverSessionDelegate = delegateManager.serverSessionDelegate

        switch queryType {
            
        case .deviceDiscovery(of: let contactIdentity):
            os_log("🖲️ Creating a ObvServerDeviceDiscoveryMethod of the contact identity %@", log: Self.log, type: .debug, contactIdentity.debugDescription)
            let method = ObvServerDeviceDiscoveryMethod(
                ownedIdentity: ownedCryptoId,
                toIdentity: contactIdentity,
                flowId: flowId)
            method.identityDelegate = identityDelegate
            let (returnedData, urlResponse) = try await self.session.data(for: method.getURLRequest())
            return (returnedData, urlResponse, nil)

        case .ownedDeviceDiscovery:
            os_log("🖲️ Creating an ObvServerOwnedDeviceDiscoveryMethod of the owned identity %@", log: Self.log, type: .debug, ownedCryptoId.debugDescription)
            let method = ObvServerOwnedDeviceDiscoveryMethod(ownedIdentity: ownedCryptoId, flowId: flowId)
            method.identityDelegate = identityDelegate
            let (returnedData, urlResponse) = try await self.session.data(for: method.getURLRequest())
            return (returnedData, urlResponse, nil)

        case .setOwnedDeviceName(ownedDeviceUID: let ownedDeviceUID, encryptedOwnedDeviceName: let encryptedOwnedDeviceName, isCurrentDevice: _):
            os_log("🖲️ Creating an ObvServerOwnedDeviceManagementMethod (setOwnedDeviceName) of the owned identity %@", log: Self.log, type: .debug, ownedCryptoId.debugDescription)
            let token = try await serverSessionDelegate.getValidServerSessionToken(for: ownedCryptoId, currentInvalidToken: nil, flowId: flowId).serverSessionToken
            let method = OwnedDeviceManagementServerMethod(
                ownedIdentity: ownedCryptoId,
                token: token,
                queryType: .setOwnedDeviceName(
                    ownedDeviceUID: ownedDeviceUID,
                    encryptedOwnedDeviceName: encryptedOwnedDeviceName),
                flowId: flowId)
            method.identityDelegate = identityDelegate
            let (returnedData, urlResponse) = try await self.session.data(for: method.getURLRequest())
            return (returnedData, urlResponse, token)

        case .deactivateOwnedDevice(ownedDeviceUID: let ownedDeviceUID, isCurrentDevice: _):
            os_log("🖲️ Creating an ObvServerOwnedDeviceManagementMethod (deactivateOwnedDevice) of the owned identity %@", log: Self.log, type: .debug, ownedCryptoId.debugDescription)
            let token = try await serverSessionDelegate.getValidServerSessionToken(for: ownedCryptoId, currentInvalidToken: nil, flowId: flowId).serverSessionToken
            let method = OwnedDeviceManagementServerMethod(
                ownedIdentity: ownedCryptoId,
                token: token,
                queryType: .deactivateOwnedDevice(ownedDeviceUID: ownedDeviceUID),
                flowId: flowId)
            method.identityDelegate = identityDelegate
            let (returnedData, urlResponse) = try await self.session.data(for: method.getURLRequest())
            return (returnedData, urlResponse, token)

        case .setUnexpiringOwnedDevice(ownedDeviceUID: let ownedDeviceUID):
            os_log("🖲️ Creating an ObvServerOwnedDeviceManagementMethod (setUnexpiringOwnedDevice) of the owned identity %@ for device %{public}@", log: Self.log, type: .debug, ownedCryptoId.debugDescription, ownedDeviceUID.debugDescription)
            let token = try await serverSessionDelegate.getValidServerSessionToken(for: ownedCryptoId, currentInvalidToken: nil, flowId: flowId).serverSessionToken
            let method = OwnedDeviceManagementServerMethod(
                ownedIdentity: ownedCryptoId,
                token: token,
                queryType: .setUnexpiringOwnedDevice(ownedDeviceUID: ownedDeviceUID),
                flowId: flowId)
            method.identityDelegate = identityDelegate
            let (returnedData, urlResponse) = try await self.session.data(for: method.getURLRequest())
            return (returnedData, urlResponse, token)

        case .putUserData(label: let label, dataURL: let dataURL, dataKey: let dataKey):
            os_log("🖲️ Creating a ObvServerPutUserDataMethod", log: Self.log, type: .debug)
            let token = try await serverSessionDelegate.getValidServerSessionToken(for: ownedCryptoId, currentInvalidToken: nil, flowId: flowId).serverSessionToken
            // Encrypt the photo
            let authEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption()
            let data = try Data(contentsOf: dataURL)
            let encryptedData = try authEnc.encrypt(data, with: dataKey, and: prng)
            let method = ObvServerPutUserDataMethod(
                ownedIdentity: ownedCryptoId,
                token: token,
                serverLabel: label,
                data: encryptedData,
                flowId: flowId)
            method.identityDelegate = identityDelegate
            let (returnedData, urlResponse) = try await self.session.data(for: method.getURLRequest())
            return (returnedData, urlResponse, token)

        case .getUserData(of: let contactIdentity, label: let label):
            os_log("🖲️ Creating a ObvServerGetUserDataMethod of the contact identity %@", log: Self.log, type: .debug, contactIdentity.debugDescription)
            let method = ObvServerGetUserDataMethod(ownedIdentity: ownedCryptoId, toIdentity: contactIdentity, serverLabel: label, flowId: flowId)
            method.identityDelegate = identityDelegate
            let (returnedData, urlResponse) = try await self.session.data(for: method.getURLRequest())
            return (returnedData, urlResponse, nil)

        case .checkKeycloakRevocation(keycloakServerUrl: let keycloakServerUrl, signedContactDetails: let signedContactDetails):
            guard let (serverURL, path) = ObvServerCheckKeycloakRevocationMethod.splitServerAndPath(from: keycloakServerUrl) else {
                os_log("🖲️ Could not compute url and path", log: Self.log, type: .error)
                assertionFailure()
                throw ObvError.failedToSplitServerAndPathForObvServerCheckKeycloakRevocationMethod
            }
            os_log("🖲️ Creating a ObvServerCheckKeycloakRevocationMethod for the server %@", log: Self.log, type: .debug, keycloakServerUrl.absoluteString)
            let method = ObvServerCheckKeycloakRevocationMethod(
                ownedIdentity: ownedCryptoId,
                serverURL: serverURL,
                path: path,
                signedContactDetails: signedContactDetails,
                flowId: flowId)
            method.identityDelegate = identityDelegate
            let (returnedData, urlResponse) = try await self.sessionForKeycloakRevocation.data(for: method.getURLRequest())
            return (returnedData, urlResponse, nil)

        case .createGroupBlob(groupIdentifier: let groupIdentifier, serverAuthenticationPublicKey: let serverAuthenticationPublicKey, encryptedBlob: let encryptedBlob):
            let token = try await serverSessionDelegate.getValidServerSessionToken(for: ownedCryptoId, currentInvalidToken: nil, flowId: flowId).serverSessionToken
            let method = ObvServerCreateGroupBlobServerMethod(
                ownedIdentity: ownedCryptoId,
                token: token,
                groupIdentifier: groupIdentifier,
                newGroupAdminServerAuthenticationPublicKey: serverAuthenticationPublicKey,
                encryptedBlob: encryptedBlob,
                flowId: flowId)
            method.identityDelegate = identityDelegate
            let (returnedData, urlResponse) = try await self.session.data(for: method.getURLRequest())
            return (returnedData, urlResponse, token)

        case .getGroupBlob(groupIdentifier: let groupIdentifier):
            let method = ObvServerGetGroupBlobServerMethod(
                ownedIdentity: ownedCryptoId,
                groupIdentifier: groupIdentifier,
                flowId: flowId)
            method.identityDelegate = identityDelegate
            let (returnedData, urlResponse) = try await self.session.data(for: method.getURLRequest())
            return (returnedData, urlResponse, nil)

        case .deleteGroupBlob(groupIdentifier: let groupIdentifier, signature: let signature):
            let method = ObvServerDeleteGroupBlobServerMethod(
                ownedIdentity: ownedCryptoId,
                groupIdentifier: groupIdentifier,
                signature: signature,
                flowId: flowId)
            method.identityDelegate = identityDelegate
            let (returnedData, urlResponse) = try await self.session.data(for: method.getURLRequest())
            return (returnedData, urlResponse, nil)

        case .putGroupLog(groupIdentifier: let groupIdentifier, querySignature: let querySignature):
            let method = ObvServerPutGroupLogServerMethod(
                ownedIdentity: ownedCryptoId,
                groupIdentifier: groupIdentifier,
                signature: querySignature,
                flowId: flowId)
            method.identityDelegate = identityDelegate
            let (returnedData, urlResponse) = try await self.session.data(for: method.getURLRequest())
            return (returnedData, urlResponse, nil)

        case .requestGroupBlobLock(groupIdentifier: let groupIdentifier, lockNonce: let lockNonce, signature: let signature):
            let method = ObvServerGroupBlobLockServerMethod(
                ownedIdentity: ownedCryptoId,
                groupIdentifier: groupIdentifier,
                lockNonce: lockNonce,
                signature: signature,
                flowId: flowId)
            method.identityDelegate = identityDelegate
            let (returnedData, urlResponse) = try await self.session.data(for: method.getURLRequest())
            return (returnedData, urlResponse, nil)

        case .updateGroupBlob(groupIdentifier: let groupIdentifier, encodedServerAdminPublicKey: let encodedServerAdminPublicKey, encryptedBlob: let encryptedBlob, lockNonce: let lockNonce, signature: let signature):
            let method = ObvServerGroupBlobUpdateServerMethod(
                ownedIdentity: ownedCryptoId,
                groupIdentifier: groupIdentifier,
                lockNonce: lockNonce,
                signature: signature,
                encodedServerAdminPublicKey: encodedServerAdminPublicKey,
                encryptedBlob: encryptedBlob,
                flowId: flowId)
            method.identityDelegate = identityDelegate
            let (returnedData, urlResponse) = try await self.session.data(for: method.getURLRequest())
            return (returnedData, urlResponse, nil)

        case .getKeycloakData(serverURL: let serverURL, serverLabel: let serverLabel):
            let method = GetKeycloakDataServerMethod(
                ownedIdentity: ownedCryptoId,
                serverURL: serverURL,
                serverLabel: serverLabel,
                flowId: flowId)
            method.identityDelegate = identityDelegate
            let (returnedData, urlResponse) = try await self.session.data(for: method.getURLRequest())
            return (returnedData, urlResponse, nil)

        case .sourceGetSessionNumber, .sourceWaitForTargetConnection, .targetSendEphemeralIdentity, .transferRelay, .transferWait, .closeWebsocketConnection:
            assertionFailure("This query is be handled by the ServerQueryWebSocketCoordinator, this one should not have been called")
            throw ObvError.webSocketQueryHandledByAnotherCoordinator
            
        }
        
    }

}

// MARK: - Errors

extension ServerQueryCoordinator {
    
    enum ObvError: Error {
        case contextCreatorIsNil
        case delegateManagerIsNil
        case identityDelegateIsNil
        case failedToGetPendingServerQueryType
        case failedToSplitServerAndPathForObvServerCheckKeycloakRevocationMethod
        case webSocketQueryHandledByAnotherCoordinator
        case channelDelegateIsNil
        case failedToDeletePendingServerQueryOfNonExistingOwnedIdentities
        case retryNow(pendingServerQueryObjectID: NSManagedObjectID)
        case serverReturnedNonHTTPURLResponse
        case serverQueryPayloadIsTooLargeForServer
        case serverReturnedBadStatusCode
    }
    
}
