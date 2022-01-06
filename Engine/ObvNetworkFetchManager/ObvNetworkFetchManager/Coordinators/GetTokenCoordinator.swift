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
import ObvServerInterface
import ObvTypes
import ObvOperation
import ObvCrypto
import ObvMetaManager
import OlvidUtils

final class GetTokenCoordinator: NSObject {
    
    // MARK: - Instance variables
    
    fileprivate let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "GetTokenCoordinator"
    
    weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    private let localQueue = DispatchQueue(label: "GetTokenCoordinatorQueue")
    
    private lazy var session: URLSession! = {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        return URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }()

    private var _currentTasks = [UIBackgroundTaskIdentifier: (ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier, dataReceived: Data)]()
    private var currentTasksQueue = DispatchQueue(label: "GetTokenCoordinatorQueueForCurrentTasks")

}


// MARK: - Synchronized access to the current download tasks

extension GetTokenCoordinator {
    
    private func currentTaskExistsFor(_ identity: ObvCryptoIdentity) -> Bool {
        var exist = true
        currentTasksQueue.sync {
            exist = _currentTasks.values.contains(where: { $0.ownedIdentity == identity })
        }
        return exist
    }
    
    private func removeInfoFor(_ task: URLSessionTask) -> (ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (ObvCryptoIdentity, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentTasks.removeValue(forKey: UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier))
        }
        return info
    }
    
    private func getInfoFor(_ task: URLSessionTask) -> (ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (ObvCryptoIdentity, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)]
        }
        return info
    }
    
    private func insert(_ task: URLSessionTask, for identity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        currentTasksQueue.sync {
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (identity, flowId, Data())
        }
    }
    
    private func accumulate(_ data: Data, forTask task: URLSessionTask) {
        currentTasksQueue.sync {
            guard let (ownedIdentity, identifierForNotifications, currentData) = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] else { return }
            var newData = currentData
            newData.append(data)
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (ownedIdentity, identifierForNotifications, newData)
        }
    }

}


// MARK: - GetTokenDelegate

extension GetTokenCoordinator: GetTokenDelegate {
    
    private enum SyncQueueOutput {
        case previousTaskExists
        case serverSessionRequired
        case existingTokenWasFound
        case newTaskToRun(task: URLSessionTask)
        case failedToCreateTask(error: Error)
    }
    
    func getToken(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) throws {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            return
        }
        
        var syncQueueOutput: SyncQueueOutput? // The state after the localQueue.sync is executed

        try localQueue.sync {
            
            guard !currentTaskExistsFor(identity) else {
                syncQueueOutput = .previousTaskExists
                return
            }
            
            try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
                
                guard let serverSession = try ServerSession.get(within: obvContext, withIdentity: identity) else {
                    syncQueueOutput = .serverSessionRequired
                    return
                }
                
                guard serverSession.token == nil else {
                    syncQueueOutput = .existingTokenWasFound
                    return
                }
                
                guard let nonce = serverSession.nonce else {
                    syncQueueOutput = .serverSessionRequired
                    return
                }
                
                guard let response = serverSession.response else {
                    syncQueueOutput = .serverSessionRequired
                    return
                }
                
                // If we reach this point, we must get a token from the server
                
                let method = ObvServerGetTokenMethod(ownedIdentity: identity, response: response, nonce: nonce, toIdentity: identity, flowId: flowId)
                method.identityDelegate = delegateManager.identityDelegate
                let task: URLSessionDataTask
                do {
                    task = try method.dataTask(within: self.session)
                } catch let error {
                    syncQueueOutput = .failedToCreateTask(error: error)
                    return
                }

                insert(task, for: identity, flowId: flowId)
                
                syncQueueOutput = .newTaskToRun(task: task)
            }
            
        } // End of localQueue.sync
        
        guard syncQueueOutput != nil else {
            os_log("syncQueueOutput is nil", log: log, type: .fault)
            return
        }
        
        switch syncQueueOutput! {
            
        case .previousTaskExists:
            os_log("A running task already exists for identity %{public}@", log: log, type: .debug, identity.debugDescription)
            delegateManager.networkFetchFlowDelegate.getTokenWasNotNeeded(for: identity, flowId: flowId)

        case .serverSessionRequired:
            os_log("Server session required for identity %{public}@", log: log, type: .debug, identity.debugDescription)
            try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: identity, flowId: flowId)
            
        case .newTaskToRun(task: let task):
            os_log("New task to run for identity %{public}@", log: log, type: .debug, identity.debugDescription)
            task.resume()
            
        case .failedToCreateTask(error: let error):
            os_log("Could not create task for ObvServerGetTokenMethod: %{public}@", log: log, type: .error, error.localizedDescription)
            return
            
        case .existingTokenWasFound:
            os_log("Aborting getToken because an existing token was found for identity %@", log: log, type: .info, identity.debugDescription)
        }
        
    }
}


// MARK: - URLSessionDataDelegate

extension GetTokenCoordinator: URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        accumulate(data, forTask: dataTask)
    }

    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            return
        }
        
        guard let (identity, flowId, responseData) = getInfoFor(task) else { return }
        
        guard error == nil else {
            os_log("The ObvServerGetTokenMethod task failed for identity %{public}@: %@", log: log, type: .error, identity.debugDescription, error!.localizedDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.failedToGetToken(for: identity, flowId: flowId)
            return
        }
        
        // If we reach this point, the data task did complete without error

        guard let (status, returnedValues) = ObvServerGetTokenMethod.parseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response for the ObvServerGetTokenMethod download task for identity %{public}@", log: log, type: .fault, identity.debugDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.failedToGetToken(for: identity, flowId: flowId)
            return
        }
        
        switch status {
        case .ok:
            let (token, serverNonce, apiKeyStatus, apiPermissions, apiKeyExpirationDate) = returnedValues!
            
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: identity) else {
                    os_log("Could not find any appropriate server session", log: log, type: .fault)
                    _ = removeInfoFor(task)
                    do {
                        try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: identity, flowId: flowId)
                    } catch {
                        os_log("Call to serverSessionRequired did fail", log: log, type: .fault)
                        assertionFailure()
                    }
                    return
                }
                
                guard serverSession.token == nil else {
                    _ = removeInfoFor(task)
                    return
                }
                
                do {
                    try serverSession.store(token: token, ifCurrentNonceIs: serverNonce)
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not save token in server session", log: log, type: .fault)
                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.failedToGetToken(for: identity, flowId: flowId)
                    return
                }
                
            }

            os_log("We successfully stored a token for identity %@", log: log, type: .debug, identity.debugDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.newToken(token, for: identity, flowId: flowId)
            delegateManager.networkFetchFlowDelegate.newAPIKeyElementsForCurrentAPIKeyOf(identity, apiKeyStatus: apiKeyStatus, apiPermissions: apiPermissions, apiKeyExpirationDate: apiKeyExpirationDate, flowId: flowId)

            return
            
        case .serverDidNotFindChallengeCorrespondingToResponse:
            os_log("The server could not find the challenge corresponding to the respond we just sent for identity %@", log: log, type: .fault, identity.debugDescription)
            _ = removeInfoFor(task)
            
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: identity) else {
                    os_log("Could not find any appropriate server session", log: log, type: .fault)
                    _ = removeInfoFor(task)
                    do {
                        try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: identity, flowId: flowId)
                    } catch {
                        os_log("Call to serverSessionRequired did fail", log: log, type: .fault)
                        assertionFailure()
                    }
                    return
                }
                
                guard serverSession.token == nil else {
                    _ = removeInfoFor(task)
                    return
                }
                
                serverSession.resetSession()
                
                try? obvContext.save(logOnFailure: log)
                
                _ = removeInfoFor(task)
                delegateManager.networkFetchFlowDelegate.failedToGetOrSolveChallenge(for: identity, flowId: flowId)
            }
            
            return
            
        case .generalError:
            os_log("Server reported general error during the ObvServerGetTokenMethod download task for identity %@", log: log, type: .fault, identity.debugDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.failedToGetToken(for: identity, flowId: flowId)
            return
        }

    }
}
