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


final class GetTurnCredentialsCoordinator {
    
    fileprivate let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "GetTurnCredentialsCoordinator"
    private let localQueue = DispatchQueue(label: "GetTurnCredentialsCoordinatorQueue")
    private let queueForNotifications = OperationQueue()
    private var internalOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Queue for GetTurnCredentialsCoordinator operations"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    var delegateManager: ObvNetworkFetchDelegateManager?

    
}


protocol GetTurnCredentialsDelegate: AnyObject {
    func getTurnCredentials(ownedIdenty: ObvCryptoIdentity, callUuid: UUID, username1: String, username2: String, flowId: FlowIdentifier)
}


extension GetTurnCredentialsCoordinator: GetTurnCredentialsDelegate {
    
    func getTurnCredentials(ownedIdenty: ObvCryptoIdentity, callUuid: UUID, username1: String, username2: String, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
                
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity deleate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        var operationsToQueue = [Operation]()

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            let operation = GetTurnCredentialsOperation(ownedIdentity: ownedIdenty,
                                                        callUuid: callUuid,
                                                        username1: username1,
                                                        username2: username2,
                                                        obvContext: obvContext,
                                                        logSubsystem: delegateManager.logSubsystem,
                                                        identityDelegate: identityDelegate,
                                                        tracker: self,
                                                        wellKnownCacheDelegate: delegateManager.wellKnownCacheDelegate)
            operationsToQueue.append(operation)
        }
        
        guard !operationsToQueue.isEmpty else { assertionFailure(); return }
        
        // We prevent any interference with previous operations
        internalOperationQueue.addBarrierBlock({})
        internalOperationQueue.addOperations(operationsToQueue, waitUntilFinished: false)
        
    }
    
}


// MARK: - Implementing GetTurnCredentialsCoordinator

extension GetTurnCredentialsCoordinator: GetTurnCredentialsTracker {
    
    func getTurnCredentialsSuccess(ownedIdentity: ObvCryptoIdentity, callUuid: UUID, turnCredentials: TurnCredentials, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        switch delegateManager.wellKnownCacheDelegate.getTurnURLs(for: ownedIdentity.serverURL, flowId: flowId) {
        case .success(let turnServersURL):
            let turnCredentialsWithTurnServers = TurnCredentialsWithTurnServers(turnCredentials: turnCredentials, turnServersURL: turnServersURL)

            os_log("☎️ Notifying about new Turn Credentials received from server", log: log, type: .info)

            ObvNetworkFetchNotificationNew.turnCredentialsReceived(ownedIdentity: ownedIdentity, callUuid: callUuid, turnCredentialsWithTurnServers: turnCredentialsWithTurnServers, flowId: flowId)
                .postOnOperationQueue(operationQueue: queueForNotifications, within: notificationDelegate)
        case .failure(let error):
            os_log("Cannot retrive turn server URLs %{public}@", log: log, type: .info, error.localizedDescription)
            return
        }
        
    }
    
    
    func getTurnCredentialsFailure(ownedIdentity: ObvCryptoIdentity, callUuid: UUID, withError error: GetTurnCredentialsURLSessionDelegate.ErrorForTracker, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        os_log("☎️ Failed to receive new Turn Credentials from server: %{public}@", log: log, type: .error, error.localizedDescription)

        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        switch error {
        case .invalidSession:
            
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: ownedIdentity) else {
                    do {
                        try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: ownedIdentity, flowId: flowId)
                    } catch {
                        os_log("Call to serverSessionRequired did fail", log: log, type: .fault)
                        assertionFailure()
                    }
                    return
                }
                
                guard let token = serverSession.token else {
                    do {
                        try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: ownedIdentity, flowId: flowId)
                    } catch {
                        os_log("Call to serverSessionRequired did fail", log: log, type: .fault)
                        assertionFailure()
                    }
                    return
                }
                
                do {
                    try delegateManager.networkFetchFlowDelegate.serverSession(of: ownedIdentity, hasInvalidToken: token, flowId: flowId)
                } catch {
                    os_log("Call to to serverSession(of: ObvCryptoIdentity, hasInvalidToken: Data, flowId: FlowIdentifier) did fail", log: log, type: .fault)
                    assertionFailure()
                }
            }
            
            ObvNetworkFetchNotificationNew.turnCredentialsReceptionFailure(ownedIdentity: ownedIdentity, callUuid: callUuid, flowId: flowId)
                .postOnOperationQueue(operationQueue: queueForNotifications, within: notificationDelegate)

        case .aTaskDidBecomeInvalidWithError,
             .couldNotParseServerResponse,
             .generalErrorFromServer,
             .noOutputAvailable,
             .wellKnownNotCached:
            ObvNetworkFetchNotificationNew.turnCredentialsReceptionFailure(ownedIdentity: ownedIdentity, callUuid: callUuid, flowId: flowId)
                .postOnOperationQueue(operationQueue: queueForNotifications, within: notificationDelegate)
        case .permissionDenied:
            ObvNetworkFetchNotificationNew.turnCredentialsReceptionPermissionDenied(ownedIdentity: ownedIdentity, callUuid: callUuid, flowId: flowId)
                .postOnOperationQueue(operationQueue: queueForNotifications, within: notificationDelegate)
        case .serverDoesNotSupportCalls:
            ObvNetworkFetchNotificationNew.turnCredentialServerDoesNotSupportCalls(ownedIdentity: ownedIdentity, callUuid: callUuid, flowId: flowId)
                .postOnOperationQueue(operationQueue: queueForNotifications, within: notificationDelegate)
        }
        
    }

}
