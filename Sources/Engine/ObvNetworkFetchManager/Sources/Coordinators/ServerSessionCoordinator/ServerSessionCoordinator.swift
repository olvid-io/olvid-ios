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
import ObvServerInterface
import ObvCrypto
import ObvTypes
import OlvidUtils
import ObvMetaManager


actor ServerSessionCoordinator: ServerSessionDelegate {
    
    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "ServerSessionCreator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)

    private let prng: PRNGService

    weak var delegateManager: ObvNetworkFetchDelegateManager?

    /// Keys are owned crypto identites, values are server session tokens
    private var cache = [ObvCryptoIdentity: ServerSessionCreationTask]()
    private enum ServerSessionCreationTask {
        case inProgress(Task<(serverSessionToken: Data, apiKeyElements: APIKeyElements), Error>)
        case ready((serverSessionToken: Data, apiKeyElements: APIKeyElements))
    }
    
    init(prng: PRNGService, logPrefix: String) {
        self.prng = prng
        let logSubsystem = "\(logPrefix).\(Self.defaultLogSubsystem)"
        Self.log = OSLog(subsystem: logSubsystem, category: Self.logCategory)
    }
    
    
    func setDelegateManager(_ delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }

    
    func deleteServerSession(of ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws {
        
        let requestUUID = UUID()
        
        os_log("䷍[%{public}@] Deleting server session", log: Self.log, type: .info, requestUUID.debugDescription)

        if let cached = cache[ownedCryptoIdentity] {
            switch cached {
            case .inProgress:
                break
            case .ready:
                cache.removeValue(forKey: ownedCryptoIdentity)
            }
        }
        
        try await executeDeleteServerSessionOperation(of: ownedCryptoIdentity, flowId: flowId)
        
        os_log("䷍[%{public}@] Server session deleted", log: Self.log, type: .info, requestUUID.debugDescription)
        
    }
    
    
    /// Returns a valid server session token: either the one that is cached (if still valid), or a new one, provided by the server after performing a valid challenge/response.
    func getValidServerSessionToken(for ownedCryptoIdentity: ObvCryptoIdentity, currentInvalidToken: Data?, flowId: FlowIdentifier) async throws -> (serverSessionToken: Data, apiKeyElements: APIKeyElements) {
        
        let requestUUID = UUID()

        os_log("䷍[%{public}@] getValidServerSessionToken called (currentInvalidToken: %{public}@)", log: Self.log, type: .info, requestUUID.debugDescription, currentInvalidToken?.hexString() ?? "nil")

        let result = try await getValidServerSessionToken(for: ownedCryptoIdentity, currentInvalidToken: currentInvalidToken, flowId: flowId, requestUUID: requestUUID)
        
        os_log("䷍[%{public}@] getValidServerSessionToken returns (token: %{public}@)", log: Self.log, type: .info, requestUUID.debugDescription, result.serverSessionToken.hexString())
        
        return result
        
    }
    

    
    
    // MARK: - Helper methods

    private func getValidServerSessionToken(for ownedCryptoIdentity: ObvCryptoIdentity, currentInvalidToken: Data?, flowId: FlowIdentifier, requestUUID: UUID) async throws -> (serverSessionToken: Data, apiKeyElements: APIKeyElements) {
        
        if let currentInvalidToken {
            
            // Clean the cache in case a .ready value contains the invalid token
            if let cached = cache[ownedCryptoIdentity] {
                switch cached {
                case .inProgress:
                    break
                case .ready(let (cachedToken, _)):
                    if cachedToken == currentInvalidToken {
                        os_log("䷍[%{public}@] Cached (ready) value found but the token is invalid. Removing the value from cache", log: Self.log, type: .info, requestUUID.debugDescription, cachedToken.hexString())
                        cache.removeValue(forKey: ownedCryptoIdentity)
                    }
                }
            }
            // Reset the ServerSession stode in Core Data in case is stores the invalid token
            os_log("䷍[%{public}@] Calling resetServerSessionCorrespondingToInvalidToken", log: Self.log, type: .info, requestUUID.debugDescription)
            try await resetServerSessionCorrespondingToInvalidToken(
                for: ownedCryptoIdentity,
                currentInvalidToken: currentInvalidToken,
                flowId: flowId)
            
        }

        if let cached = cache[ownedCryptoIdentity] {
            switch cached {
            case .ready(let (cachedToken, cachedAPIKeyElements)):
                if cachedToken != currentInvalidToken {
                    os_log("䷍[%{public}@] Cached (ready) value found (token: %{public}@)", log: Self.log, type: .info, requestUUID.debugDescription, cachedToken.hexString())
                    return (cachedToken, cachedAPIKeyElements)
                } else {
                    os_log("䷍[%{public}@] Cached (ready) value found but the token is invalid", log: Self.log, type: .info, requestUUID.debugDescription, cachedToken.hexString())
                    cache.removeValue(forKey: ownedCryptoIdentity)
                }
            case .inProgress(let task):
                os_log("䷍[%{public}@] Cached (inProgress) value found. Waiting for value...", log: Self.log, type: .info, requestUUID.debugDescription)
                return try await task.value
            }
        }
        
        os_log("䷍[%{public}@] No cached value found", log: Self.log, type: .info, requestUUID.debugDescription)
        
        // If we reach this point, no valid token was found in cache.
        
        let task: Task<(serverSessionToken: Data, apiKeyElements: APIKeyElements), Error> = createTaskForGettingServerSession(for: ownedCryptoIdentity, requestUUID: requestUUID, flowId: flowId)
                                
        cache[ownedCryptoIdentity] = .inProgress(task)
        
        os_log("䷍[%{public}@] Added an inProgress task in cache", log: Self.log, type: .info, requestUUID.debugDescription)

        do {
            os_log("䷍[%{public}@] Waiting for value...", log: Self.log, type: .info, requestUUID.debugDescription)
            let (serverSessionToken, apiKeyElements) = try await task.value
            cache[ownedCryptoIdentity] = .ready((serverSessionToken, apiKeyElements))
            os_log("䷍[%{public}@] Returning value", log: Self.log, type: .info, requestUUID.debugDescription)
            return (serverSessionToken, apiKeyElements)
        } catch {
            cache.removeValue(forKey: ownedCryptoIdentity)
            throw error
        }

    }
    
    
    private func createTaskForGettingServerSession(for ownedCryptoIdentity: ObvCryptoIdentity, requestUUID: UUID, flowId: FlowIdentifier) -> Task<(serverSessionToken: Data, apiKeyElements: APIKeyElements), Error> {
        
        return Task {
            
            let localServerSessionTokenAndAPIKeyElements = try await getLocalServerSessionTokenAndAPIKeyElements(for: ownedCryptoIdentity, flowId: flowId)
            
            if let localServerSessionTokenAndAPIKeyElements {
                // A cached session token exist, we return it
                os_log("䷍[%{public}@] Found local value in database. Returning it now", log: Self.log, type: .info, requestUUID.debugDescription)
                return localServerSessionTokenAndAPIKeyElements
            }
            
            os_log("䷍[%{public}@] No local value found. Requesting a challenge to the server...", log: Self.log, type: .info, requestUUID.debugDescription)

            let nonce = prng.genBytes(count: ObvConstants.serverSessionNonceLength)
            
            let challenge = try await requestChallengeFromServer(for: ownedCryptoIdentity, nonce: nonce, flowId: flowId)
            
            os_log("䷍[%{public}@] Challenge received. Computing response", log: Self.log, type: .info, requestUUID.debugDescription)

            let response = try await solveChallenge(challenge: challenge, for: ownedCryptoIdentity, flowId: flowId)

            os_log("䷍[%{public}@] Using response to get server session token", log: Self.log, type: .info, requestUUID.debugDescription)

            let serverSessionTokenAndAPIKeyElements = try await requestSessionFromServer(for: ownedCryptoIdentity, response: response, nonce: nonce, flowId: flowId)

            os_log("䷍[%{public}@] Saving received server session token for next time", log: Self.log, type: .info, requestUUID.debugDescription)

            try await saveServerSessionTokenAndAPIKeyElements(for: ownedCryptoIdentity, serverSessionTokenAndAPIKeyElements: serverSessionTokenAndAPIKeyElements, flowId: flowId)
            
            os_log("䷍[%{public}@] Returning server session token and api key elements", log: Self.log, type: .info, requestUUID.debugDescription)

            return serverSessionTokenAndAPIKeyElements
            
        }
    }
    
    
    private func executeDeleteServerSessionOperation(of ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws {

        guard let delegateManager else {
            assertionFailure("The Delegate Manager is not set")
            throw ObvError.theDelegateManagerIsNotSet
        }

        let coordinatorsQueue = delegateManager.queueSharedAmongCoordinators
        
        let op1 = DeleteServerSessionOperation(ownedCryptoIdentity: ownedCryptoIdentity)
        let composedOp = try createCompositionOfOneContextualOperation(op1: op1, flowId: flowId)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            defer { coordinatorsQueue.addOperation(composedOp) }
            let previousCompletion = composedOp.completionBlock
            composedOp.completionBlock = {
                
                previousCompletion?()
                
                guard composedOp.isCancelled else {
                    continuation.resume()
                    return
                }
                
                guard let reasonForCancel = composedOp.reasonForCancel else {
                    assertionFailure()
                    continuation.resume(throwing: ObvError.operationFailedWithoutSpecifyingReason)
                    return
                }
                
                switch reasonForCancel {
                case .unknownReason, .op1HasUnfinishedDependency:
                    assertionFailure()
                    continuation.resume(throwing: ObvError.operationFailedWithoutSpecifyingReason)
                    return
                case .coreDataError(error: let error):
                    assertionFailure()
                    continuation.resume(throwing: ObvError.coreDataError(error: error))
                    return
                case .op1Cancelled(reason: let op1ReasonForCancel):
                    switch op1ReasonForCancel {
                    case .coreDataError(error: let error):
                        assertionFailure()
                        continuation.resume(throwing: ObvError.coreDataError(error: error))
                        return
                    }
                }

            }

        }

    }

    
    private func saveServerSessionTokenAndAPIKeyElements(for ownedCryptoIdentity: ObvCryptoIdentity, serverSessionTokenAndAPIKeyElements: (serverSessionToken: Data, apiKeyElements: APIKeyElements), flowId: FlowIdentifier) async throws {
        
        guard let delegateManager else {
            assertionFailure("The Delegate Manager is not set")
            throw ObvError.theDelegateManagerIsNotSet
        }

        let coordinatorsQueue = delegateManager.queueSharedAmongCoordinators
        
        let op1 = SaveServerSessionTokenAndAPIKeyElementsOperation(
            ownedCryptoIdentity: ownedCryptoIdentity,
            serverSessionTokenAndAPIKeyElements: serverSessionTokenAndAPIKeyElements)
        let composedOp = try createCompositionOfOneContextualOperation(op1: op1, flowId: flowId)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            defer { coordinatorsQueue.addOperation(composedOp) }
            let previousCompletion = composedOp.completionBlock
            composedOp.completionBlock = {
                
                previousCompletion?()
                
                guard composedOp.isCancelled else {
                    continuation.resume()
                    return
                }
                
                guard let reasonForCancel = composedOp.reasonForCancel else {
                    assertionFailure()
                    continuation.resume(throwing: ObvError.operationFailedWithoutSpecifyingReason)
                    return
                }
                
                switch reasonForCancel {
                case .unknownReason, .op1HasUnfinishedDependency:
                    assertionFailure()
                    continuation.resume(throwing: ObvError.operationFailedWithoutSpecifyingReason)
                    return
                case .coreDataError(error: let error):
                    assertionFailure()
                    continuation.resume(throwing: ObvError.coreDataError(error: error))
                    return
                case .op1Cancelled(reason: let op1ReasonForCancel):
                    switch op1ReasonForCancel {
                    case .coreDataError(error: let error):
                        assertionFailure()
                        continuation.resume(throwing: ObvError.coreDataError(error: error))
                        return
                    }
                }

            }

        }

    }
    
    
    private func requestSessionFromServer(for ownedCryptoIdentity: ObvCryptoIdentity, response: Data, nonce: Data, flowId: FlowIdentifier) async throws -> (serverSessionToken: Data, apiKeyElements: APIKeyElements) {
        
        let method = ObvServerGetTokenMethod(
            ownedIdentity: ownedCryptoIdentity,
            response: response,
            nonce: nonce,
            toIdentity: ownedCryptoIdentity,
            flowId: flowId)
        
        let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ObvError.invalidServerResponse
        }
        
        let result = ObvServerGetTokenMethod.parseObvServerResponse(responseData: data, using: Self.log)

        switch result {
        case .failure(let error):
            throw ObvError.serverError(error: error)
        case .success(let returnStatus):
            switch returnStatus {
            case .serverDidNotFindChallengeCorrespondingToResponse:
                assertionFailure()
                throw ObvError.serverReportedThatItDidNotFindChallengeCorrespondingToResponse
            case .generalError:
                assertionFailure()
                throw ObvError.serverReportedGeneralError
            case .ok(token: let token, serverNonce: let serverNonce, apiKeyStatus: let apiKeyStatus, apiPermissions: let apiPermissions, apiKeyExpirationDate: let apiKeyExpirationDate):
                if nonce != serverNonce {
                    assertionFailure("Unexpected server nonce")
                }
                return (token, .init(status: apiKeyStatus, permissions: apiPermissions, expirationDate: apiKeyExpirationDate))
            }
        }
        
    }
    
    
    private func solveChallenge(challenge: Data, for ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> Data {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure("The Delegate Manager is not set")
            throw ObvError.theDelegateManagerIsNotSet
        }

        guard let solveChallengeDelegate = delegateManager.solveChallengeDelegate else {
            os_log("The solve challenge delegate is not set", log: Self.log, type: .fault)
            assertionFailure("The solve challenge delegate is not set")
            throw ObvError.theSolveChallengeDelegateIsNotSet
        }

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: Self.log, type: .fault)
            assertionFailure("The context creator manager is not set")
            throw ObvError.theContextCreatorIsNotSet
        }

        let prng = ObvCryptoSuite.sharedInstance.prngService()
        let challengeType = ChallengeType.authentChallenge(challengeFromServer: challenge)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let response = try solveChallengeDelegate.solveChallenge(challengeType, for: ownedCryptoIdentity, using: prng, within: obvContext)
                    continuation.resume(returning: response)
                } catch {
                    continuation.resume(throwing: ObvError.coreDataError(error: error))
                }
            }
        }

    }
    
    
    private func requestChallengeFromServer(for ownedCryptoIdentity: ObvCryptoIdentity, nonce: Data, flowId: FlowIdentifier) async throws -> Data {
        
        // No cached server session token exists. To get a new one, we first request a challenge to the server
        
        let method = ObvServerRequestChallengeMethod(
            ownedIdentity: ownedCryptoIdentity,
            nonce: nonce,
            toIdentity: ownedCryptoIdentity,
            flowId: flowId)
        
        let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ObvError.invalidServerResponse
        }
        
        let result = ObvServerRequestChallengeMethod.parseObvServerResponse(responseData: data, using: Self.log)

        switch result {
        case .failure(let error):
            throw ObvError.serverError(error: error)
        case .success(let returnStatus):
            switch returnStatus {
            case .generalError:
                assertionFailure()
                throw ObvError.serverReportedGeneralError
            case .ok(challenge: let challenge, serverNonce: let serverNonce):
                guard serverNonce == nonce else {
                    assertionFailure()
                    throw ObvError.serverNonceDiffersFromLocalNonce
                }
                return challenge
            }
        }

    }
    
    
    private func resetServerSessionCorrespondingToInvalidToken(for ownedCryptoIdentity: ObvCryptoIdentity, currentInvalidToken: Data, flowId: FlowIdentifier) async throws {
        
        guard let delegateManager else {
            assertionFailure("The Delegate Manager is not set")
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        let coordinatorsQueue = delegateManager.queueSharedAmongCoordinators

        let op1 = ResetServerSessionCorrespondingToInvalidTokenOperation(
            ownedCryptoIdentity: ownedCryptoIdentity,
            invalidToken: currentInvalidToken)
        let composedOp = try createCompositionOfOneContextualOperation(op1: op1, flowId: flowId)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            defer { coordinatorsQueue.addOperation(composedOp) }
            let previousCompletion = composedOp.completionBlock
            composedOp.completionBlock = {
                
                previousCompletion?()
                
                guard composedOp.isCancelled else {
                    continuation.resume()
                    return
                }
                
                guard let reasonForCancel = composedOp.reasonForCancel else {
                    assertionFailure()
                    continuation.resume(throwing: ObvError.operationFailedWithoutSpecifyingReason)
                    return
                }
                
                switch reasonForCancel {
                case .unknownReason, .op1HasUnfinishedDependency:
                    assertionFailure()
                    continuation.resume(throwing: ObvError.operationFailedWithoutSpecifyingReason)
                    return
                case .coreDataError(error: let error):
                    assertionFailure()
                    continuation.resume(throwing: ObvError.coreDataError(error: error))
                    return
                case .op1Cancelled(reason: let op1ReasonForCancel):
                    switch op1ReasonForCancel {
                    case .coreDataError(error: let error):
                        assertionFailure()
                        continuation.resume(throwing: ObvError.coreDataError(error: error))
                        return
                    }
                }

            }

        }
        
    }
    
    
    private func getLocalServerSessionTokenAndAPIKeyElements(for ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> (serverSessionToken: Data, apiKeyElements: APIKeyElements)? {
        
        guard let delegateManager else {
            assertionFailure("The Delegate Manager is not set")
            throw ObvError.theDelegateManagerIsNotSet
        }

        let coordinatorsQueue = delegateManager.queueSharedAmongCoordinators

        let op1 = GetLocalServerSessionTokenAndAPIKeyElementsOperation(ownedCryptoIdentity: ownedCryptoIdentity)
        let composedOp = try createCompositionOfOneContextualOperation(op1: op1, flowId: flowId)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(serverSessionToken: Data, apiKeyElements: APIKeyElements)?, Error>) in
            defer { coordinatorsQueue.addOperation(composedOp) }
            let previousCompletion = composedOp.completionBlock
            composedOp.completionBlock = {
                
                previousCompletion?()
                
                guard composedOp.isCancelled else {
                    continuation.resume(returning: op1.serverSessionTokenAndAPIKeyElements)
                    return
                }
                
                guard let reasonForCancel = composedOp.reasonForCancel else {
                    assertionFailure()
                    continuation.resume(throwing: ObvError.operationFailedWithoutSpecifyingReason)
                    return
                }
                
                switch reasonForCancel {
                case .unknownReason, .op1HasUnfinishedDependency:
                    assertionFailure()
                    continuation.resume(throwing: ObvError.operationFailedWithoutSpecifyingReason)
                    return
                case .coreDataError(error: let error):
                    assertionFailure()
                    continuation.resume(throwing: ObvError.coreDataError(error: error))
                    return
                case .op1Cancelled(reason: let op1ReasonForCancel):
                    switch op1ReasonForCancel {
                    case .coreDataError(error: let error):
                        assertionFailure()
                        continuation.resume(throwing: ObvError.coreDataError(error: error))
                        return
                    }
                }

            }

        }

        
    }
    
    
    // MARK: - Errors
    
    enum ObvError: LocalizedError {
        
        case theDelegateManagerIsNotSet
        case theContextCreatorIsNotSet
        case theSolveChallengeDelegateIsNotSet
        case operationFailedWithoutSpecifyingReason
        case coreDataError(error: Error)
        case noAPIKey
        case invalidServerResponse
        case couldNotParseReturnStatusFromServer
        case serverError(error: Error)
        case serverReportedGeneralError
        case serverNonceDiffersFromLocalNonce
        case serverReportedThatItDidNotFindChallengeCorrespondingToResponse
        
        var errorDescription: String? {
            switch self {
            case .theDelegateManagerIsNotSet:
                return "The delegate manager is not set"
            case .theContextCreatorIsNotSet:
                return "The context creator is not set"
            case .operationFailedWithoutSpecifyingReason:
                return "Operation failed without specifying reason"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .theSolveChallengeDelegateIsNotSet:
                return "The solve challenge delegate is not set"
            case .noAPIKey:
                return "No API key could be found"
            case .invalidServerResponse:
                return "Invalid server response"
            case .couldNotParseReturnStatusFromServer:
                return "Could not parse return status from server"
            case .serverError(error: let error):
                return "Server error: \(error.localizedDescription)"
            case .serverReportedGeneralError:
                return "Server reported a general error"
            case .serverNonceDiffersFromLocalNonce:
                return "Server nonce differs from local nonce"
            case .serverReportedThatItDidNotFindChallengeCorrespondingToResponse:
                return "Server reported that no challenge corresponding to response could be found"
            }
        }
    }
    
}



// MARK: - Helpers

extension ServerSessionCoordinator {
    
    private func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>, flowId: FlowIdentifier) throws -> CompositionOfOneContextualOperation<T> {

        guard let delegateManager else {
            assertionFailure("The Delegate Manager is not set")
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        guard let contextCreator = delegateManager.contextCreator else {
            assertionFailure("The context creator manager is not set")
            throw ObvError.theContextCreatorIsNotSet
        }
        
        let queueForComposedOperations = delegateManager.queueForComposedOperations

        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: contextCreator, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: flowId)

        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp

    }
    
}
