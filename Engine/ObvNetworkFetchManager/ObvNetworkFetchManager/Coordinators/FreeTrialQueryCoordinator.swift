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
import ObvServerInterface
import OlvidUtils
import ObvCrypto


actor FreeTrialQueryCoordinator: FreeTrialQueryDelegate {
    
    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "ServerPushNotificationsCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)

    weak var delegateManager: ObvNetworkFetchDelegateManager?

    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()

    func setDelegateManager(_ delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }
    
    func queryFreeTrial(for ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> Bool {
        
        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        let sessionToken = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: ownedCryptoId, currentInvalidToken: nil, flowId: flowId).serverSessionToken

        let task = Task {
            
            let method = FreeTrialServerMethod(ownedIdentity: ownedCryptoId, token: sessionToken, retrieveAPIKey: false, flowId: flowId)
            method.identityDelegate = delegateManager.identityDelegate

            let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ObvError.invalidServerResponse
            }
            
            guard let returnStatus = FreeTrialServerMethod.parseObvServerResponseWhenTestingWhetherFreeTrialIsStillAvailable(responseData: data, using: Self.log) else {
                assertionFailure()
                throw ObvError.couldNotParseReturnStatusFromServer
            }
            
            return returnStatus
            
        }

        do {
            let returnStatus = try await task.value
            switch returnStatus {
            case .invalidSession:
                _ = try await delegateManager.networkFetchFlowDelegate.getValidServerSessionToken(for: ownedCryptoId, currentInvalidToken: sessionToken, flowId: flowId)
                return try await queryFreeTrial(for: ownedCryptoId, flowId: flowId)
            case .ok:
                return true
            case .freeTrialAlreadyUsed:
                return false
            case .generalError:
                let delay = failedAttemptsCounterManager.incrementAndGetDelay(.freeTrialQuery(ownedIdentity: ownedCryptoId))
                await retryManager.waitForDelay(milliseconds: delay)
                _ = try await delegateManager.networkFetchFlowDelegate.getValidServerSessionToken(for: ownedCryptoId, currentInvalidToken: sessionToken, flowId: flowId)
                return try await queryFreeTrial(for: ownedCryptoId, flowId: flowId)
            }
        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    
    /// Starts a free trial and returns refresh API permission reflecting the result of starting the free trial.
    func startFreeTrial(for ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> APIKeyElements {
        
        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        let sessionToken = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: ownedCryptoId, currentInvalidToken: nil, flowId: flowId).serverSessionToken

        let task = Task {
            
            let method = FreeTrialServerMethod(ownedIdentity: ownedCryptoId, token: sessionToken, retrieveAPIKey: true, flowId: flowId)
            method.identityDelegate = delegateManager.identityDelegate

            let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ObvError.invalidServerResponse
            }
            
            guard let (returnStatus, values) = FreeTrialServerMethod.parseObvServerResponseWhenRetrievingFreeTrialAPIKey(responseData: data, using: Self.log) else {
                assertionFailure()
                throw ObvError.couldNotParseReturnStatusFromServer
            }
            
            return (returnStatus, values)
            
        }

        do {
            let (returnStatus, _) = try await task.value
            switch returnStatus {
            case .ok:
                let newAPIKeyElements = try await delegateManager.networkFetchFlowDelegate.refreshAPIPermissions(of: ownedCryptoId, flowId: flowId)
                return newAPIKeyElements
            case .invalidSession:
                _ = try await delegateManager.networkFetchFlowDelegate.getValidServerSessionToken(for: ownedCryptoId, currentInvalidToken: sessionToken, flowId: flowId)
                let newAPIKeyElements = try await startFreeTrial(for: ownedCryptoId, flowId: flowId)
                return newAPIKeyElements
            case .freeTrialAlreadyUsed:
                throw ObvError.freeTrialAlreadyUsed
            case .generalError:
                let delay = failedAttemptsCounterManager.incrementAndGetDelay(.freeTrialQuery(ownedIdentity: ownedCryptoId))
                await retryManager.waitForDelay(milliseconds: delay)
                _ = try await delegateManager.networkFetchFlowDelegate.getValidServerSessionToken(for: ownedCryptoId, currentInvalidToken: sessionToken, flowId: flowId)
                let newAPIKeyElements = try await startFreeTrial(for: ownedCryptoId, flowId: flowId)
                return newAPIKeyElements
            }
        } catch {
            assertionFailure()
            throw error
        }
        
    }

    
    enum ObvError: LocalizedError {
        case theDelegateManagerIsNotSet
        case invalidServerResponse
        case couldNotParseReturnStatusFromServer
        case freeTrialAlreadyUsed

        var errorDescription: String? {
            switch self {
            case .invalidServerResponse:
                return "Invalid server response"
            case .theDelegateManagerIsNotSet:
                return "The delegate manager is not set"
            case .couldNotParseReturnStatusFromServer:
                return "Could not parse return status from server"
            case .freeTrialAlreadyUsed:
                return "Free trial already used"
            }
        }
    }

}
