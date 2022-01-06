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


final class QueryApiKeyStatusCoordinator: NSObject {
    
    fileprivate let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "QueryApiKeyStatusCoordinator"

    weak var delegateManager: ObvNetworkFetchDelegateManager?

    private let localQueue = DispatchQueue(label: "QueryApiKeyStatusCoordinatorQueue")
    
    private lazy var session: URLSession! = {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        return URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }()

    private var _currentTasks = [UIBackgroundTaskIdentifier: (ownedIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier, dataReceived: Data)]()
    private var currentTasksQueue = DispatchQueue(label: "QueryApiKeyStatusCoordinatorQueueForCurrentTasks")

}


// MARK: - Synchronized access to the current download tasks

extension QueryApiKeyStatusCoordinator {
    
    private func currentTaskExistsFor(_ identity: ObvCryptoIdentity, apiKey: UUID) -> Bool {
        var exist = true
        currentTasksQueue.sync {
            exist = _currentTasks.values.contains(where: { $0.ownedIdentity == identity && $0.apiKey == apiKey })
        }
        return exist
    }
    
    private func removeInfoFor(_ task: URLSessionTask) -> (ownedIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (ObvCryptoIdentity, UUID, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentTasks.removeValue(forKey: UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier))
        }
        return info
    }
    
    private func getInfoFor(_ task: URLSessionTask) -> (ownedIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (ObvCryptoIdentity, UUID, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)]
        }
        return info
    }
    
    private func insert(_ task: URLSessionTask, for identity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) {
        currentTasksQueue.sync {
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (identity, apiKey, flowId, Data())
        }
    }
    
    private func accumulate(_ data: Data, forTask task: URLSessionTask) {
        currentTasksQueue.sync {
            guard let (ownedIdentity, apiKey, identifierForNotifications, currentData) = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] else { return }
            var newData = currentData
            newData.append(data)
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (ownedIdentity, apiKey, identifierForNotifications, newData)
        }
    }

}


// MARK: - QueryApiKeyStatusDelegate

extension QueryApiKeyStatusCoordinator: QueryApiKeyStatusDelegate {
    
    private enum SyncQueueOutput {
        case previousTaskExists
        case newTaskToRun(task: URLSessionTask)
        case failedToCreateTask(error: Error)
    }

    func queryAPIKeyStatus(for identity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        var syncQueueOutput: SyncQueueOutput? // The state after the localQueue.sync is executed
        
        localQueue.sync {
            
            guard !currentTaskExistsFor(identity, apiKey: apiKey) else {
                syncQueueOutput = .previousTaskExists
                return
            }
            
            let method = QueryApiKeyStatusServerMethod(ownedIdentity: identity, apiKey: apiKey, flowId: flowId)
            method.identityDelegate = delegateManager.identityDelegate
            let task: URLSessionDataTask
            do {
                task = try method.dataTask(within: self.session)
            } catch let error {
                syncQueueOutput = .failedToCreateTask(error: error)
                return
            }

            insert(task, for: identity, apiKey: apiKey, flowId: flowId)
            
            syncQueueOutput = .newTaskToRun(task: task)

        }
        
        guard syncQueueOutput != nil else {
            assertionFailure()
            os_log("syncQueueOutput is nil", log: log, type: .fault)
            return
        }

        switch syncQueueOutput! {
        
        case .previousTaskExists:
            os_log("A running task already exists for identity %{public}@ and keyId %{public}@", log: log, type: .debug, identity.debugDescription, apiKey.debugDescription)
            assertionFailure()

        case .newTaskToRun(task: let task):
            os_log("New task to run for identity %{public}@ and keyId %{public}@", log: log, type: .debug, identity.debugDescription, apiKey.debugDescription)
            task.resume()

        case .failedToCreateTask(error: let error):
            os_log("Could not create task for QueryApiKeyStatusServerMethod: %{public}@", log: log, type: .error, error.localizedDescription)
            assertionFailure()
            return

        }
    }
    
}


// MARK: - URLSessionDataDelegate

extension QueryApiKeyStatusCoordinator: URLSessionDataDelegate {
    
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

        guard let (ownedIdentity, apiKey, flowId, dataReceived) = getInfoFor(task) else { return }
        
        guard error == nil else {
            os_log("💰 The QueryApiKeyStatusServerMethod task failed for identity %{public}@: %@", log: log, type: .error, ownedIdentity.debugDescription, error!.localizedDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.apiKeyStatusQueryFailed(ownedIdentity: ownedIdentity, apiKey: apiKey)
            return
        }

        // If we reach this point, the data task did complete without error

        guard let (status, returnedValues) = QueryApiKeyStatusServerMethod.parseObvServerResponse(responseData: dataReceived, using: log) else {
            os_log("💰 Could not parse the server response for the QueryApiKeyStatusServerMethod task for identity %{public}@ and apiKey", log: log, type: .fault, ownedIdentity.debugDescription, apiKey.debugDescription)
            _ = removeInfoFor(task)
            assertionFailure()
            delegateManager.networkFetchFlowDelegate.apiKeyStatusQueryFailed(ownedIdentity: ownedIdentity, apiKey: apiKey)
            return
        }

        switch status {
        case .ok:
            let (apiKeyStatus, apiPermissions, apiKeyExpirationDate) = returnedValues!
            os_log("💰 Server returned an API Key Status [%{public}@] with the following expiration date: %{public}@", log: log, type: .fault, apiKeyStatus.description, apiKeyExpirationDate?.debugDescription ?? "NONE")
            delegateManager.networkFetchFlowDelegate.newAPIKeyElementsForAPIKey(serverURL: ownedIdentity.serverURL, apiKey: apiKey, apiKeyStatus: apiKeyStatus, apiPermissions: apiPermissions, apiKeyExpirationDate: apiKeyExpirationDate, flowId: flowId)
            _ = removeInfoFor(task)

        case .generalError:
            os_log("💰 Server reported general error during the QueryApiKeyStatusServerMethod task for identity %{public}@ for keyId %{public}@", log: log, type: .fault, ownedIdentity.debugDescription, apiKey.debugDescription)
            _ = removeInfoFor(task)
            assertionFailure()
            delegateManager.networkFetchFlowDelegate.apiKeyStatusQueryFailed(ownedIdentity: ownedIdentity, apiKey: apiKey)
            return

        }
    }
    
}
