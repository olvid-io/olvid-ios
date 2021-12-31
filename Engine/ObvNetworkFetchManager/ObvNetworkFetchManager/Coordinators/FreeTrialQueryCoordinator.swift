/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import ObvServerInterface
import ObvMetaManager
import OlvidUtils


final class FreeTrialQueryCoordinator: NSObject {
    
    fileprivate let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "FreeTrialQueryCoordinator"

    weak var delegateManager: ObvNetworkFetchDelegateManager?

    private let localQueue = DispatchQueue(label: "FreeTrialQueryCoordinatorQueue")
    private let queueForNotifications = DispatchQueue(label: "FreeTrialQueryCoordinator queue for notifications")
    
    private lazy var session: URLSession! = {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        return URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }()

    private var _currentTasks = [UIBackgroundTaskIdentifier: (ownedIdentity: ObvCryptoIdentity, retrieveAPIKey: Bool, flowId: FlowIdentifier, dataReceived: Data)]()
    private var currentTasksQueue = DispatchQueue(label: "FreeTrialQueryCoordinatorQueueForCurrentTasks")
    
    private var queriesWaitingForNewServerSession = [(ownedIdentity: ObvCryptoIdentity, retrieveAPIKey: Bool, flowId: FlowIdentifier)]()
}

// MARK: - Synchronized access to the current download tasks

extension FreeTrialQueryCoordinator {
    
    private func currentTaskExistsFor(_ identity: ObvCryptoIdentity, retrieveAPIKey: Bool) -> Bool {
        var exist = true
        currentTasksQueue.sync {
            exist = _currentTasks.values.contains(where: { $0.ownedIdentity == identity && $0.retrieveAPIKey == retrieveAPIKey })
        }
        return exist
    }
    
    private func removeInfoFor(_ task: URLSessionTask) -> (ownedIdentity: ObvCryptoIdentity, retrieveAPIKey: Bool, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (ObvCryptoIdentity, Bool, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentTasks.removeValue(forKey: UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier))
        }
        return info
    }
    
    private func getInfoFor(_ task: URLSessionTask) -> (ownedIdentity: ObvCryptoIdentity, retrieveAPIKey: Bool, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (ObvCryptoIdentity, Bool, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)]
        }
        return info
    }
    
    private func insert(_ task: URLSessionTask, for identity: ObvCryptoIdentity, retrieveAPIKey: Bool, flowId: FlowIdentifier) {
        currentTasksQueue.sync {
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (identity, retrieveAPIKey, flowId, Data())
        }
    }
    
    private func accumulate(_ data: Data, forTask task: URLSessionTask) {
        currentTasksQueue.sync {
            guard let (ownedIdentity, retrieveAPIKey, identifierForNotifications, currentData) = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] else { return }
            var newData = currentData
            newData.append(data)
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (ownedIdentity, retrieveAPIKey, identifierForNotifications, newData)
        }
    }
    
}
 

// MARK: - FreeTrialQueryDelegate

extension FreeTrialQueryCoordinator: FreeTrialQueryDelegate {
    
    private enum SyncQueueOutput {
        case previousTaskExists
        case serverSessionRequired
        case newTaskToRun(task: URLSessionTask)
        case failedToCreateTask(error: Error)
    }

    
    func queryFreeTrial(for identity: ObvCryptoIdentity, retrieveAPIKey: Bool, flowId: FlowIdentifier) {
        
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
        
        localQueue.sync {
            
            guard !currentTaskExistsFor(identity, retrieveAPIKey: retrieveAPIKey) else {
                syncQueueOutput = .previousTaskExists
                return
            }
            
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: identity) else {
                    syncQueueOutput = .serverSessionRequired
                    return
                }
                
                guard let token = serverSession.token else {
                    syncQueueOutput = .serverSessionRequired
                    return
                }
                
                let method = FreeTrialServerMethod(ownedIdentity: identity, token: token, retrieveAPIKey: retrieveAPIKey, flowId: flowId)
                method.identityDelegate = delegateManager.identityDelegate
                let task: URLSessionDataTask
                do {
                    task = try method.dataTask(within: self.session)
                } catch let error {
                    syncQueueOutput = .failedToCreateTask(error: error)
                    return
                }
                
                insert(task, for: identity, retrieveAPIKey: retrieveAPIKey, flowId: flowId)
                
                syncQueueOutput = .newTaskToRun(task: task)
                
            }
        }
        
        guard syncQueueOutput != nil else {
            assertionFailure()
            os_log("syncQueueOutput is nil", log: log, type: .fault)
            return
        }

        let queueForCallingDelegate = DispatchQueue(label: "FreeTrialQueryCoordinator queue for calling delegate in queryFreeTrial")

        switch syncQueueOutput! {
        
        case .previousTaskExists:
            os_log("A running task already exists for identity %{public}@", log: log, type: .debug, identity.debugDescription)
            assertionFailure()

        case .serverSessionRequired:
            os_log("Server session required for identity %@ with flow identifier %{public}@", log: log, type: .debug, identity.debugDescription, flowId.debugDescription)
            queueForCallingDelegate.async {
                do {
                    try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: identity, flowId: flowId)
                } catch {
                    os_log("Call serverSessionRequired did fail", log: log, type: .fault)
                    assertionFailure()
                }
            }

        case .newTaskToRun(task: let task):
            os_log("New task to run for identity %{public}@", log: log, type: .debug, identity.debugDescription)
            task.resume()

        case .failedToCreateTask(error: let error):
            os_log("Could not create task for FreeTrialServerMethod: %{public}@", log: log, type: .error, error.localizedDescription)
            assertionFailure()
            return

        }
    }

    
    func processFreeTrialQueriesExpectingNewSession() {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        var queries = [(ownedIdentity: ObvCryptoIdentity, retrieveAPIKey: Bool, flowId: FlowIdentifier)]()
        localQueue.sync {
            queries = queriesWaitingForNewServerSession
            queriesWaitingForNewServerSession.removeAll()
        }

        os_log("Processing %d queries that were waiting for a new server session", log: log, type: .info, queries.count)

        for query in queries {
            queryFreeTrial(for: query.ownedIdentity, retrieveAPIKey: query.retrieveAPIKey, flowId: query.flowId)
        }
    }
    
}


// MARK: - URLSessionDataDelegate

extension FreeTrialQueryCoordinator: URLSessionDataDelegate {
    
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

        guard let (ownedIdentity, retrieveAPIKey, flowId, dataReceived) = getInfoFor(task) else { return }
        
        guard error == nil else {
            os_log("The FreeTrialServerMethod task failed for identity %{public}@: %@", log: log, type: .error, ownedIdentity.debugDescription, error!.localizedDescription)
            _ = removeInfoFor(task)
            assertionFailure()
            return
        }

        // If we reach this point, the data task did complete without error
        
        if retrieveAPIKey {
            
            guard let (status, returnedValues) = FreeTrialServerMethod.parseObvServerResponseWhenRetrievingFreeTrialAPIKey(responseData: dataReceived, using: log) else {
                os_log("Could not parse the server response for the FreeTrialServerMethod while retrieving an API key task for identity %{public}@", log: log, type: .fault, ownedIdentity.debugDescription)
                _ = removeInfoFor(task)
                assertionFailure()
                return
            }
            
            switch status {
            case .ok:
                let apiKey = returnedValues!
                _ = removeInfoFor(task)
                queueForNotifications.async {
                    delegateManager.networkFetchFlowDelegate.newFreeTrialAPIKeyForOwnedIdentity(ownedIdentity, apiKey: apiKey, flowId: flowId)
                }
                return
                
            case .invalidSession:
                os_log("The server session is invalid.", log: log, type: .info)
                _ = removeInfoFor(task)
                localQueue.sync {
                    queriesWaitingForNewServerSession.append((ownedIdentity, retrieveAPIKey, flowId))
                }
                queueForNotifications.async { [weak self] in
                    self?.createNewServerSession(ownedIdentity: ownedIdentity, delegateManager: delegateManager, flowId: flowId, log: log)
                }
                return
                
            case .freeTrialAlreadyUsed:
                os_log("The server reported that no more free trial is available for identity %{public}@", log: log, type: .info, ownedIdentity.debugDescription)
                _ = removeInfoFor(task)
                queueForNotifications.async {
                    delegateManager.networkFetchFlowDelegate.noMoreFreeTrialAPIKeyAvailableForOwnedIdentity(ownedIdentity, flowId: flowId)
                }
                return

            case .generalError:
                os_log("The server reported a general error", log: log, type: .fault, ownedIdentity.debugDescription)
                assertionFailure()
                _ = removeInfoFor(task)
                return
            }
            
        } else {
            
            guard let status = FreeTrialServerMethod.parseObvServerResponseWhenTestingWhetherFreeTrialIsStillAvailable(responseData: dataReceived, using: log) else {
                os_log("Could not parse the server response for the FreeTrialServerMethod for identity %{public}@", log: log, type: .fault, ownedIdentity.debugDescription)
                _ = removeInfoFor(task)
                assertionFailure()
                return
            }

            switch status {
            case .ok:
                _ = removeInfoFor(task)
                queueForNotifications.async {
                    delegateManager.networkFetchFlowDelegate.freeTrialIsStillAvailableForOwnedIdentity(ownedIdentity, flowId: flowId)
                }
                return

            case .invalidSession:
                os_log("The server session is invalid.", log: log, type: .info)
                _ = removeInfoFor(task)
                localQueue.sync {
                    queriesWaitingForNewServerSession.append((ownedIdentity, retrieveAPIKey, flowId))
                }
                queueForNotifications.async { [weak self] in
                    self?.createNewServerSession(ownedIdentity: ownedIdentity, delegateManager: delegateManager, flowId: flowId, log: log)
                }
                return
                
            case .freeTrialAlreadyUsed:
                os_log("The server reported that no more free trial is available for identity %{public}@", log: log, type: .info, ownedIdentity.debugDescription)
                _ = removeInfoFor(task)
                queueForNotifications.async {
                    delegateManager.networkFetchFlowDelegate.noMoreFreeTrialAPIKeyAvailableForOwnedIdentity(ownedIdentity, flowId: flowId)
                }
                return

            case .generalError:
                os_log("The server reported a general error", log: log, type: .fault, ownedIdentity.debugDescription)
                _ = removeInfoFor(task)
                assertionFailure()
                return
            }

        }

    }
    
    
    private func createNewServerSession(ownedIdentity: ObvCryptoIdentity, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier, log: OSLog) {
        guard let contextCreator = delegateManager.contextCreator else { assertionFailure(); return }
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

    }
}
