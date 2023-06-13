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


final class ServerPushNotificationsCoordinator: NSObject, ObvErrorMaker {
    
    // MARK: - Instance variables
    
    fileprivate let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "ServerPushNotificationsCoordinator"
    static let errorDomain = "ServerPushNotificationsCoordinator"

    weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    private lazy var session: URLSession! = {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        return URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }()

    // Allows to store the data received while resuming the URL task
    private var _currentTasks = [UIBackgroundTaskIdentifier: Data]()
    private var currentTasksQueue = DispatchQueue(label: "GetTokenCoordinatorQueueForCurrentDownloadTasks")
    
    private let remoteNotificationByteIdentifierForServer: Data
    
    private let coordinatorsQueue: OperationQueue
    private let queueForComposedOperations: OperationQueue
    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()

    init(remoteNotificationByteIdentifierForServer: Data, coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue) {
        self.remoteNotificationByteIdentifierForServer = remoteNotificationByteIdentifierForServer
        self.coordinatorsQueue = coordinatorsQueue
        self.queueForComposedOperations = queueForComposedOperations
        super.init()
    }

}

// MARK: - Synchronized access to the current download tasks

extension ServerPushNotificationsCoordinator {
    
    private func removeDataReceivedFor(_ task: URLSessionTask) -> Data? {
        var dataReceived: Data?
        currentTasksQueue.sync {
            dataReceived = _currentTasks.removeValue(forKey: UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier))
        }
        return dataReceived
    }
    
    private func accumulate(_ data: Data, forTask task: URLSessionTask) {
        currentTasksQueue.sync {
            let currentData = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] ?? Data()
            var newData = currentData
            newData.append(data)
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = newData
        }
    }

}

// MARK: - ServerPushNotificationsDelegate

extension ServerPushNotificationsCoordinator: ServerPushNotificationsDelegate {
    
    func registerToPushNotification(_ pushNotification: ObvPushNotificationType, flowId: FlowIdentifier) {
        
        let op1 = CreateOrUpdateIfRequiredServerPushNotificationOperation(pushNotification: pushNotification)
        
        guard let composedOp = createCompositionOfOneContextualOperation(op1: op1) else { assertionFailure(); return }
        defer { coordinatorsQueue.addOperation(composedOp) }

        let previousCompletion = composedOp.completionBlock
        composedOp.completionBlock = { [weak self] in
            
            previousCompletion?()
            
            guard composedOp.isCancelled else {
                self?.failedAttemptsCounterManager.reset(counter: .registerPushNotification(ownedIdentity: pushNotification.ownedCryptoId))
                if op1.thereIsANewServerPushNotificationToRegister {
                    do {
                        try self?.processServerPushNotificationsToRegister(ownedCryptoId: pushNotification.ownedCryptoId, pushNotificationType: pushNotification.byteId, flowId: flowId)
                    } catch {
                        assertionFailure(error.localizedDescription) // This never happens in practice
                    }
                }
                return
            }
            
            guard let reasonForCancel = composedOp.reasonForCancel else { assertionFailure(); return }
            switch reasonForCancel {
            case .unknownReason:
                assertionFailure("unknownReason")
            case .coreDataError(error: let error):
                assertionFailure(error.localizedDescription)
            case .op1Cancelled(reason: let op1ReasonForCancel):
                switch op1ReasonForCancel {
                case .coreDataError(error: let error):
                    assertionFailure(error.localizedDescription)
                case .contextIsNil:
                    assertionFailure("contextIsNil")
                }
            }
            
            guard let delay = self?.failedAttemptsCounterManager.incrementAndGetDelay(.registerPushNotification(ownedIdentity: pushNotification.ownedCryptoId)) else { return }
            self?.retryManager.executeWithDelay(delay) {
                self?.registerToPushNotification(pushNotification, flowId: flowId)
            }
        }
        
    }
    
    
    func processServerPushNotificationsToRegister(ownedCryptoId: ObvCryptoIdentity, pushNotificationType: ObvPushNotificationType.ByteId, flowId: FlowIdentifier) throws {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        let op1 = RegisterPushNotificationToRegisterOperation(
            ownedCryptoId: ownedCryptoId,
            pushNotificationType: pushNotificationType,
            remoteNotificationByteIdentifierForServer: remoteNotificationByteIdentifierForServer,
            session: session,
            identityDelegate: identityDelegate)
     
        guard let composedOp = createCompositionOfOneContextualOperation(op1: op1) else { assertionFailure(); return }
        defer { coordinatorsQueue.addOperation(composedOp) }

        let previousCompletion = composedOp.completionBlock
        composedOp.completionBlock = { [weak self] in
            
            previousCompletion?()
            
            guard composedOp.isCancelled else {
                self?.failedAttemptsCounterManager.reset(counter: .registerPushNotification(ownedIdentity: ownedCryptoId))
                return
            }
            
            guard let reasonForCancel = composedOp.reasonForCancel else { assertionFailure(); return }
            switch reasonForCancel {
            case .unknownReason:
                assertionFailure("unknownReason")
            case .coreDataError(error: let error):
                assertionFailure(error.localizedDescription)
            case .op1Cancelled(reason: let op1ReasonForCancel):
                switch op1ReasonForCancel {
                case .coreDataError(error: let error):
                    assertionFailure(error.localizedDescription)
                case .contextIsNil:
                    assertionFailure("contextIsNil")
                case .failedToCreateURLSessionDataTask(error: let error):
                    assertionFailure("failedToCreateURLSessionDataTask: \(error.localizedDescription)")
                case .serverSessionRequired:
                    try? delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: ownedCryptoId, flowId: flowId)
                }
            }
            
            self?.retryLaterProcessServerPushNotificationsToRegister(ownedCryptoId: ownedCryptoId, pushNotificationType: pushNotificationType, flowId: flowId)

        }

    }
    
    
    func forceRegisteringOfServerPushNotificationsOnBootstrap(flowId: FlowIdentifier) {
        
        let op1 = MarkAllServerPushNotificationsAsToRegisterOperation()

        guard let composedOp = createCompositionOfOneContextualOperation(op1: op1) else { assertionFailure(); return }
        defer { coordinatorsQueue.addOperation(composedOp) }

        let previousCompletion = composedOp.completionBlock
        composedOp.completionBlock = { [weak self] in
            
            previousCompletion?()
            
            guard composedOp.isCancelled else {
                for serverPushNotificationToRegister in op1.serverPushNotificationsToRegister {
                    do {
                        try self?.processServerPushNotificationsToRegister(
                            ownedCryptoId: serverPushNotificationToRegister.ownedCryptoId,
                            pushNotificationType: serverPushNotificationToRegister.pushNotificationType,
                            flowId: flowId)
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
                return
            }
            
            guard let reasonForCancel = composedOp.reasonForCancel else { assertionFailure(); return }
            switch reasonForCancel {
            case .unknownReason:
                assertionFailure("unknownReason")
            case .coreDataError(error: let error):
                assertionFailure(error.localizedDescription)
            case .op1Cancelled(reason: let op1ReasonForCancel):
                switch op1ReasonForCancel {
                case .coreDataError(error: let error):
                    assertionFailure(error.localizedDescription)
                case .contextIsNil:
                    assertionFailure("contextIsNil")
                }
            }
            
        }

    }
    
    
    private func retryLaterProcessServerPushNotificationsToRegister(ownedCryptoId: ObvCryptoIdentity, pushNotificationType: ObvPushNotificationType.ByteId, flowId: FlowIdentifier) {
        let delay = failedAttemptsCounterManager.incrementAndGetDelay(.registerPushNotification(ownedIdentity: ownedCryptoId))
        retryManager.executeWithDelay(delay) { [weak self] in
            try? self?.processServerPushNotificationsToRegister(ownedCryptoId: ownedCryptoId, pushNotificationType: pushNotificationType, flowId: flowId)
        }
    }
    
    
    func deleteAllServerPushNotificationsOnOwnedIdentityDeletion(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        let op1 = DeleteAllServerPushNotificationsOnOwnedIdentityDeletionOperation(ownedCryptoId: ownedCryptoId)
        guard let composedOp = createCompositionOfOneContextualOperation(op1: op1) else { assertionFailure(); return }
        defer { coordinatorsQueue.addOperation(composedOp) }

        let previousCompletion = composedOp.completionBlock
        composedOp.completionBlock = {
            previousCompletion?()
            guard composedOp.isCancelled else { return }
            guard let reasonForCancel = composedOp.reasonForCancel else { assertionFailure(); return }
            switch reasonForCancel {
            case .unknownReason:
                assertionFailure()
            case .coreDataError(error: let error):
                assertionFailure(error.localizedDescription)
            case .op1Cancelled(reason: let op1ReasonForCancel):
                switch op1ReasonForCancel {
                case .coreDataError(error: let error):
                    assertionFailure(error.localizedDescription)
                case .contextIsNil:
                    assertionFailure()
                }
            }
        }
    }
    
}


// MARK: - URLSessionDataDelegate

extension ServerPushNotificationsCoordinator: URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        accumulate(data, forTask: dataTask)
    }


    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        if let error {
            os_log("The process registered push notification task failed (which also happens if there is no network): %{public}@", log: log, type: .error, error.localizedDescription)
            _ = removeDataReceivedFor(task)
            return
        }

        guard let responseData = removeDataReceivedFor(task) else { assertionFailure(); return }
        
        let op1 = ProcessCompletionOfURLSessionTaskForRegisteringPushNotificationOperation(urlSessionTaskIdentifier: task.taskIdentifier, responseData: responseData, log: log)
        
        guard let composedOp = createCompositionOfOneContextualOperation(op1: op1) else { assertionFailure(); return }
        defer { coordinatorsQueue.addOperation(composedOp) }

        let previousCompletion = composedOp.completionBlock
        composedOp.completionBlock = { [weak self] in
            
            previousCompletion?()

            guard composedOp.isCancelled else {
                
                guard let serverReturnStatus = op1.serverReturnStatus else { assertionFailure(); return }
                
                switch serverReturnStatus {
                    
                case .serverReturnedDataDiscardedAsItWasObsolete:
                    return
                    
                case .ok(ownedCryptoId: let ownedCryptoId, flowId: let flowId):
                    delegateManager.networkFetchFlowDelegate.serverReportedThatThisDeviceWasSuccessfullyRegistered(forOwnedIdentity: ownedCryptoId, flowId: flowId)
                    return
                    
                case .invalidSession(ownedCryptoId: let ownedCryptoId, pushNotificationType: let pushNotificationType, flowId: let flowId):
                    try? delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: ownedCryptoId, flowId: flowId)
                    self?.retryLaterProcessServerPushNotificationsToRegister(ownedCryptoId: ownedCryptoId, pushNotificationType: pushNotificationType, flowId: flowId)
                    return
                    
                case .anotherDeviceIsAlreadyRegistered(ownedCryptoId: let ownedCryptoId, pushNotificationType: let pushNotificationType, flowId: let flowId):
                    delegateManager.networkFetchFlowDelegate.serverReportedThatAnotherDeviceIsAlreadyRegistered(forOwnedIdentity: ownedCryptoId, flowId: flowId)
                    self?.retryLaterProcessServerPushNotificationsToRegister(ownedCryptoId: ownedCryptoId, pushNotificationType: pushNotificationType, flowId: flowId)
                    return

                case .generalError(ownedCryptoId: let ownedCryptoId, pushNotificationType: let pushNotificationType, flowId: let flowId):
                    self?.retryLaterProcessServerPushNotificationsToRegister(ownedCryptoId: ownedCryptoId, pushNotificationType: pushNotificationType, flowId: flowId)
                    return

                case .couldNotParseServerResponse(ownedCryptoId: let ownedCryptoId, pushNotificationType: let pushNotificationType, flowId: let flowId):
                    self?.retryLaterProcessServerPushNotificationsToRegister(ownedCryptoId: ownedCryptoId, pushNotificationType: pushNotificationType, flowId: flowId)
                    return
                    
                }
            }
            
            guard let reasonForCancel = composedOp.reasonForCancel else { assertionFailure(); return }
            
            switch reasonForCancel {
            case .unknownReason:
                assertionFailure()
                return
            case .coreDataError(error: let error):
                assertionFailure(error.localizedDescription)
                return
            case .op1Cancelled(reason: let op1ReasonForCancel):
                switch op1ReasonForCancel {
                case .coreDataError(error: let error):
                    assertionFailure(error.localizedDescription)
                    return
                case .contextIsNil:
                    assertionFailure()
                    return
                }
            }
            
        }

    }

}


// MARK: - Helpers

extension ServerPushNotificationsCoordinator {
    
    private func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>) -> CompositionOfOneContextualOperation<T>? {

        guard let delegateManager else {
            assertionFailure("The Delegate Manager is not set")
            return nil
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            assertionFailure("The context creator manager is not set")
            return nil
        }

        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: contextCreator, queueForComposedOperations: queueForComposedOperations, log: log, flowId: FlowIdentifier())

        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: log)
        }
        return composedOp

    }
    
}
