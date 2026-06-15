/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils
import ObvServerInterface


final class GetTurnCredentialsCoordinator {
    
    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "ServerPushNotificationsCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
    private static var logger = Logger(subsystem: defaultLogSubsystem, category: logCategory)

    var delegateManager: ObvNetworkFetchDelegateManager?
    
}


protocol GetTurnCredentialsDelegate: AnyObject {
    func getTurnCredentials(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> ObvWellKnownTurnCredentials
}


extension GetTurnCredentialsCoordinator: GetTurnCredentialsDelegate {
    
    func getTurnCredentials(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> ObvWellKnownTurnCredentials {
        
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

        let sessionToken = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: ownedCryptoId, currentInvalidToken: nil, flowId: flowId).serverSessionToken

        let task = Task {
            
            let method = GetTurnCredentialsServerMethod(
                ownedIdentity: ownedCryptoId,
                token: sessionToken,
                username1: "alice",
                username2: "bob",
                flowId: flowId,
                identityDelegate: identityDelegate)
            
            let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ObvError.invalidServerResponse
            }
            
            guard let (status, turnCredentials) = GetTurnCredentialsServerMethod.parseObvServerResponse(responseData: data, using: Self.log) else {
                assertionFailure()
                throw ObvError.couldNotParseReturnStatusFromServer
            }
            
            return (status, turnCredentials)
            
        }

        do {
            
            let (status, turnCredentials) = try await task.value
            
            switch status {
                
            case .ok:
                guard let turnCredentials else {
                    throw ObvError.okFromServerButNoCredentialsReturned
                }
                switch try await delegateManager.wellKnownCacheDelegate.getTurnURLs(for: ownedCryptoId.serverURL, flowId: flowId) {
                case .success(let (turnServerURLs, turnServerAlternativeURLs)):
                    let obvTurnCredentials = ObvWellKnownTurnCredentials(turnCredentials: turnCredentials, turnServerURLs: turnServerURLs, turnServerAlternativeURLs: turnServerAlternativeURLs)
                    Self.logger.info("☎️ Returning Turn Credentials received from server")
                    return obvTurnCredentials
                case .failure(let error):
                    Self.logger.error("Could not retrive turn server URLs \(error.localizedDescription, privacy: .public)")
                    throw ObvError.couldNotRetrieveTurnServers
                }
                
            case .invalidSession:
                _ = try await delegateManager.networkFetchFlowDelegate.getValidServerSessionToken(for: ownedCryptoId, currentInvalidToken: sessionToken, flowId: flowId)
                return try await getTurnCredentials(ownedCryptoId: ownedCryptoId, flowId: flowId)

            case .permissionDenied:
                os_log("Server reported permission denied", log: Self.log, type: .error)
                throw ObvError.permissionDenied
                
            case .generalError:
                os_log("Server reported general error", log: Self.log, type: .fault)
                throw ObvError.generalError

            }

        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
}


extension GetTurnCredentialsCoordinator {
    
    enum ObvError: Error {
        case theDelegateManagerIsNotSet
        case theIdentityDelegateIsNotSet
        case invalidServerResponse
        case couldNotParseReturnStatusFromServer
        case okFromServerButNoCredentialsReturned
        case permissionDenied
        case generalError
        case couldNotRetrieveTurnServers
    }
        
}


// MARK: - Helpers

fileprivate extension ObvWellKnownTurnCredentials {
    
    init(turnCredentials: TurnCredentials, turnServerURLs: [String], turnServerAlternativeURLs: [String]) {
        self.init(callerUsername: turnCredentials.expiringUsername1,
                  callerPassword: turnCredentials.password1,
                  recipientUsername: turnCredentials.expiringUsername2,
                  recipientPassword: turnCredentials.password2,
                  turnServerURLs: turnServerURLs,
                  turnServerAlternativeURLs: turnServerAlternativeURLs)
    }
    
}
