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

final class GetAndSolveChallengeCoordinator: NSObject {
    
    // MARK: - Instance variables
    
    fileprivate let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "GetAndSolveChallengeCoordinator"
    
    weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    private let localQueue = DispatchQueue(label: "GetAndSolveChallengeCoordinatorQueue")
    
    private lazy var session: URLSession! = {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        return URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }()
    
    private var _currentTasks = [UIBackgroundTaskIdentifier: (ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier, dataReceived: Data)]()
    private var currentTasksQueue = DispatchQueue(label: "GetAndSolveChallengeCoordinatorQueueForCurrentTasks")
    
    private let challengePrefix = "authentChallenge".data(using: .utf8)!
}


// MARK: - Synchronized access to the current download tasks

extension GetAndSolveChallengeCoordinator {
    
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


// MARK: - GetAndSolveChallengeDelegate

extension GetAndSolveChallengeCoordinator: GetAndSolveChallengeDelegate {
    
    private enum SyncQueueOutput {
        case noApiKey
        case previousTaskExists
        case existingTokenWasFound
        case existingResponseWasFoundButNoTokenExists
        case newTaskToRun(task: URLSessionTask)
        case failedToCreateTask(error: Error)
    }
    
    
    func getAndSolveChallenge(forIdentity identity: ObvCryptoIdentity, currentInvalidToken: Data?, discardExistingToken: Bool, flowId: FlowIdentifier) throws {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let solveChallengeDelegate = delegateManager.solveChallengeDelegate else {
            os_log("The solve challenge delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            return
        }
        
        var syncQueueOutput: SyncQueueOutput? // The state after the localQueue.sync is executed
        
        try localQueue.sync {
            
            try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
                
                guard !currentTaskExistsFor(identity) else {
                    syncQueueOutput = .previousTaskExists
                    return
                }
                
                let serverSession = try ServerSession.getOrCreate(within: obvContext, withIdentity: identity)
                
                if let currentInvalidToken = currentInvalidToken {
                    // This operation was launched because of an invalid token. This operation is only useful if this token is still the one in DB. Otherwise, some other GetAndSolveChallengeOperation was executed in the meantime.
                    guard currentInvalidToken == serverSession.token else { return }
                    // If we reach this point, we are in charge of refreshing the token.
                    serverSession.resetSession()
                }
                
                if discardExistingToken {
                    serverSession.resetSession()
                }
                
                if serverSession.token != nil {
                    syncQueueOutput = .existingTokenWasFound
                    return
                }
                
                if serverSession.response != nil {
                    syncQueueOutput = .existingResponseWasFoundButNoTokenExists
                    return
                }
                
                // If we reach this point, we do need to ask a challenge to the server
                
                let prng = ObvCryptoSuite.sharedInstance.prngService()
                serverSession.nonce = prng.genBytes(count: ObvConstants.nonceLength)
                
                do {
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not save the generated nonce", log: log, type: .fault)
                    return
                }
                
                let apiKey: UUID
                do {
                    apiKey = try solveChallengeDelegate.getApiKeyForOwnedIdentity(identity)
                } catch {
                    syncQueueOutput = .noApiKey
                    return
                }
                
                let method = ObvServerRequestChallengeMethod(ownedIdentity: identity, apiKey: apiKey, nonce: serverSession.nonce!, toIdentity: identity, flowId: flowId)
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
            
        } // End localQueue.sync
        
        guard syncQueueOutput != nil else {
            os_log("syncQueueOutput is nil", log: log, type: .fault)
            return
        }
        
        switch syncQueueOutput! {
            
        case .previousTaskExists:
            os_log("A running task already exists for identity %@", log: log, type: .debug, identity.debugDescription)
            delegateManager.networkFetchFlowDelegate.getAndSolveChallengeWasNotNeeded(for: identity, flowId: flowId)
            
        case .newTaskToRun(task: let task):
            os_log("New task to run for identity %@", log: log, type: .debug, identity.debugDescription)
            task.resume()
            
        case .existingTokenWasFound:
            os_log("Aborting getAndSolveChallenge since a previous token was found for identity %@", log: log, type: .info, identity.debugDescription)
            
        case .existingResponseWasFoundButNoTokenExists:
            os_log("We already have a response to some challenge but no token", log: log, type: .debug)
            try delegateManager.networkFetchFlowDelegate.newChallengeResponse(for: identity, flowId: flowId)
            
        case .failedToCreateTask(error: let error):
            os_log("Could not create task for ObvServerRequestChallengeMethod: %{public}@", log: log, type: .error, error.localizedDescription)
            return
            
        case .noApiKey:
            os_log("Could not get API Key for owned identity %@", log: log, type: .fault, identity.debugDescription)
        }
    }
}


// MARK: - URLSessionDataDelegate

extension GetAndSolveChallengeCoordinator: URLSessionDataDelegate {
    
    
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
        
        guard let solveChallengeDelegate = delegateManager.solveChallengeDelegate else {
            os_log("The solve challenge delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let (identity, flowId, responseData) = getInfoFor(task) else { return }
        
        guard error == nil else {
            os_log("The ObvServerRequestChallengeMethod task failed for identity %{public}@: %@", log: log, type: .error, identity.debugDescription, error!.localizedDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.failedToGetOrSolveChallenge(for: identity, flowId: flowId)
            return
        }
        
        // If we reach this point, the data task did complete without error
        
        guard let (status, returnedValues) = ObvServerRequestChallengeMethod.parseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response for the ObvServerRequestChallengeMethod task for identity %{public}@", log: log, type: .fault, identity.debugDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.failedToGetOrSolveChallenge(for: identity, flowId: flowId)
            return
        }
        
        switch status {
        case .ok:
            let (challenge, serverNonce) = returnedValues!
                        
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: identity) else {
                    os_log("Could not find any appropriate server session", log: log, type: .fault)
                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.failedToGetOrSolveChallenge(for: identity, flowId: flowId)
                    return
                }
                
                if serverSession.response != nil || serverSession.token != nil {
                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.failedToGetOrSolveChallenge(for: identity, flowId: flowId)
                    return
                }
                
                let prng = ObvCryptoSuite.sharedInstance.prngService()
                guard let response = try? solveChallengeDelegate.solveChallenge(challenge, prefixedWith: challengePrefix, for: identity, using: prng, within: obvContext) else {
                    os_log("Could not solve the challenge", log: log, type: .error)
                    serverSession.nonce = nil
                    try? obvContext.save(logOnFailure: log)
                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.failedToGetOrSolveChallenge(for: identity, flowId: flowId)
                    return
                }
                
                do {
                    try serverSession.store(response: response, ifCurrentNonceIs: serverNonce)
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not store the response", log: log, type: .fault)
                    _ = removeInfoFor(task)
                    delegateManager.networkFetchFlowDelegate.failedToGetOrSolveChallenge(for: identity, flowId: flowId)
                    return
                }
                
                os_log("We successfully stored a challenge response for identity %@", log: log, type: .debug, identity.debugDescription)
                _ = removeInfoFor(task)
                do {
                    try delegateManager.networkFetchFlowDelegate.newChallengeResponse(for: identity, flowId: flowId)
                } catch {
                    os_log("Call to newChallengeResponse did fail", log: log, type: .fault)
                    assertionFailure()
                }
            }
            
            return
            
        case .unkownApiKey, .apiKeyLicensesExhausted:
            os_log("Server reported an error during the ObvServerRequestChallengeMethod download task for identity %@", log: log, type: .fault, identity.debugDescription)
            _ = removeInfoFor(task)
            
        case .generalError:
            os_log("Server reported general error during the ObvServerRequestChallengeMethod download task for identity %@", log: log, type: .fault, identity.debugDescription)
            _ = removeInfoFor(task)
            delegateManager.networkFetchFlowDelegate.failedToGetOrSolveChallenge(for: identity, flowId: flowId)
            return
        }        
    }
}
