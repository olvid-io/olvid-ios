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
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils
import ObvServerInterface


final class GetTurnCredentialsCoordinator {
    
    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "ServerPushNotificationsCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)

    private let queueForNotifications = DispatchQueue(label: "GetTurnCredentialsCoordinator queue for posting notifications")

    var delegateManager: ObvNetworkFetchDelegateManager?

    
}


protocol GetTurnCredentialsDelegate: AnyObject {
    func getTurnCredentials(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> ObvTurnCredentials
}


extension GetTurnCredentialsCoordinator: GetTurnCredentialsDelegate {
    
    func getTurnCredentials(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> ObvTurnCredentials {
        
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
                switch delegateManager.wellKnownCacheDelegate.getTurnURLs(for: ownedCryptoId.serverURL, flowId: flowId) {
                case .success(let turnServersURL):
                    let obvTurnCredentials = ObvTurnCredentials(turnCredentials: turnCredentials, turnServersURL: turnServersURL)
                    os_log("☎️ Returning Turn Credentials received from server", log: Self.log, type: .info)
                    return obvTurnCredentials
                case .failure(let error):
                    os_log("Cannot retrive turn server URLs %{public}@", log: Self.log, type: .error, error.localizedDescription)
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
    
    
//    func getTurnCredentials(ownedIdenty: ObvCryptoIdentity, callUuid: UUID, username1: String, username2: String, flowId: FlowIdentifier) {
//        
//        guard let delegateManager = delegateManager else {
//            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
//            assertionFailure()
//            return
//        }
//        
//        guard let contextCreator = delegateManager.contextCreator else {
//            os_log("The context creator manager is not set", log: Self.log, type: .fault)
//            assertionFailure()
//            return
//        }
//
//        guard let identityDelegate = delegateManager.identityDelegate else {
//            os_log("The identity deleate is not set", log: Self.log, type: .fault)
//            assertionFailure()
//            return
//        }
//
//        var operationsToQueue = [Operation]()
//
//        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
//            let operation = GetTurnCredentialsOperation(ownedIdentity: ownedIdenty,
//                                                        callUuid: callUuid,
//                                                        username1: username1,
//                                                        username2: username2,
//                                                        obvContext: obvContext,
//                                                        logSubsystem: delegateManager.logSubsystem,
//                                                        identityDelegate: identityDelegate,
//                                                        tracker: self,
//                                                        wellKnownCacheDelegate: delegateManager.wellKnownCacheDelegate)
//            operationsToQueue.append(operation)
//        }
//        
//        guard !operationsToQueue.isEmpty else { assertionFailure(); return }
//        
//        // We prevent any interference with previous operations
//        internalOperationQueue.addBarrierBlock({})
//        internalOperationQueue.addOperations(operationsToQueue, waitUntilFinished: false)
//        
//    }
    
}


// MARK: - Implementing GetTurnCredentialsCoordinator

//extension GetTurnCredentialsCoordinator: GetTurnCredentialsTracker {
//    
//    func getTurnCredentialsSuccess(ownedIdentity: ObvCryptoIdentity, callUuid: UUID, turnCredentials: TurnCredentials, flowId: FlowIdentifier) {
//        
//        guard let delegateManager = delegateManager else {
//            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
//            assertionFailure()
//            return
//        }
//        
//        guard let notificationDelegate = delegateManager.notificationDelegate else {
//            os_log("The notification delegate is not set", log: Self.log, type: .fault)
//            assertionFailure()
//            return
//        }
//
//        switch delegateManager.wellKnownCacheDelegate.getTurnURLs(for: ownedIdentity.serverURL, flowId: flowId) {
//        case .success(let turnServersURL):
//            let turnCredentialsWithTurnServers = TurnCredentialsWithTurnServers(turnCredentials: turnCredentials, turnServersURL: turnServersURL)
//
//            os_log("☎️ Notifying about new Turn Credentials received from server", log: Self.log, type: .info)
//
//            ObvNetworkFetchNotificationNew.turnCredentialsReceived(ownedIdentity: ownedIdentity, callUuid: callUuid, turnCredentialsWithTurnServers: turnCredentialsWithTurnServers, flowId: flowId)
//                .postOnBackgroundQueue(queueForNotifications, within: notificationDelegate)
//        case .failure(let error):
//            os_log("Cannot retrive turn server URLs %{public}@", log: Self.log, type: .info, error.localizedDescription)
//            return
//        }
//        
//    }
//    
//    
//    func getTurnCredentialsFailure(ownedIdentity: ObvCryptoIdentity, callUuid: UUID, withError error: GetTurnCredentialsURLSessionDelegate.ErrorForTracker, flowId: FlowIdentifier) {
//        
//        guard let delegateManager = delegateManager else {
//            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
//            assertionFailure()
//            return
//        }
//        
//        os_log("☎️ Failed to receive new Turn Credentials from server: %{public}@", log: Self.log, type: .error, error.localizedDescription)
//
//        
//        guard let notificationDelegate = delegateManager.notificationDelegate else {
//            os_log("The notification delegate is not set", log: Self.log, type: .fault)
//            assertionFailure()
//            return
//        }
//
//        guard let contextCreator = delegateManager.contextCreator else {
//            os_log("The context creator is not set", log: Self.log, type: .fault)
//            assertionFailure()
//            return
//        }
//        
//        switch error {
//        case .invalidSession:
//            
//            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
//                guard let serverSession = try? ServerSession.get(within: obvContext.context, withIdentity: ownedIdentity), let token = serverSession.token else {
//                    Task.detached {
//                        do {
//                            _ = try await delegateManager.networkFetchFlowDelegate.getValidServerSessionToken(for: ownedIdentity, currentInvalidToken: nil, flowId: flowId)
//                        } catch {
//                            os_log("Call to getValidServerSessionToken did fail", log: Self.log, type: .fault)
//                            assertionFailure()
//                        }
//                    }
//                    return
//                }
//                Task.detached {
//                    do {
//                        _ = try await delegateManager.networkFetchFlowDelegate.getValidServerSessionToken(for: ownedIdentity, currentInvalidToken: token, flowId: flowId)
//                    } catch {
//                        os_log("Call to getValidServerSessionToken did fail", log: Self.log, type: .fault)
//                        assertionFailure()
//                    }
//                }
//            }
//            
//            ObvNetworkFetchNotificationNew.turnCredentialsReceptionFailure(ownedIdentity: ownedIdentity, callUuid: callUuid, flowId: flowId)
//                .postOnBackgroundQueue(queueForNotifications, within: notificationDelegate)
//
//        case .aTaskDidBecomeInvalidWithError,
//             .couldNotParseServerResponse,
//             .generalErrorFromServer,
//             .noOutputAvailable,
//             .wellKnownNotCached:
//            ObvNetworkFetchNotificationNew.turnCredentialsReceptionFailure(ownedIdentity: ownedIdentity, callUuid: callUuid, flowId: flowId)
//                .postOnBackgroundQueue(queueForNotifications, within: notificationDelegate)
//        case .permissionDenied:
//            ObvNetworkFetchNotificationNew.turnCredentialsReceptionPermissionDenied(ownedIdentity: ownedIdentity, callUuid: callUuid, flowId: flowId)
//                .postOnBackgroundQueue(queueForNotifications, within: notificationDelegate)
//        case .serverDoesNotSupportCalls:
//            ObvNetworkFetchNotificationNew.turnCredentialServerDoesNotSupportCalls(ownedIdentity: ownedIdentity, callUuid: callUuid, flowId: flowId)
//                .postOnBackgroundQueue(queueForNotifications, within: notificationDelegate)
//        }
//        
//    }
//
//}


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

fileprivate extension ObvTurnCredentials {
    
    init(turnCredentials: TurnCredentials, turnServersURL: [String]) {
        self.init(callerUsername: turnCredentials.expiringUsername1,
                  callerPassword: turnCredentials.password1,
                  recipientUsername: turnCredentials.expiringUsername2,
                  recipientPassword: turnCredentials.password2,
                  turnServersURL: turnServersURL)
    }
    
}
