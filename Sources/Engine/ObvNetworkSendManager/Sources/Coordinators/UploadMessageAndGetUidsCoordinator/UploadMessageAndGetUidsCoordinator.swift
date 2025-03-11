/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import CoreData
import ObvOperation
import ObvServerInterface
import ObvTypes
import ObvMetaManager
import OlvidUtils


final class UploadMessageAndGetUidsCoordinator: NSObject {
    
    // MARK: - Instance variables
    
    fileprivate let defaultLogSubsystem = ObvNetworkSendDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "UploadMessageAndGetUidsCoordinator"
    
    weak var delegateManager: ObvNetworkSendDelegateManager?
    
    private let localQueue = DispatchQueue(label: "UploadMessageAndGetUidsCoordinatorQueue")
    
    private lazy var session: URLSession! = {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.useOlvidSettings(sharedContainerIdentifier: delegateManager?.sharedContainerIdentifier)
        return URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }()
    
    private var _currentTasks = [UIBackgroundTaskIdentifier: (messageId: ObvMessageIdentifier, flowId: FlowIdentifier, dataReceived: Data)]()
    private let currentTasksQueue = DispatchQueue(label: "UploadMessageAndGetUidsCoordinatorQueueForCurrentTasks")

}


// MARK: - Synchronized access to the current download tasks

extension UploadMessageAndGetUidsCoordinator {
    
    private func currentTaskExistsForMessage(withId id: ObvMessageIdentifier) -> Bool {
        var exist = true
        currentTasksQueue.sync {
            exist = _currentTasks.values.contains(where: { $0.messageId == id })
        }
        return exist
    }
    
    private func removeInfoFor(_ task: URLSessionTask) -> (messageId: ObvMessageIdentifier, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (ObvMessageIdentifier, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentTasks.removeValue(forKey: UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier))
        }
        return info
    }
    
    private func getInfoFor(_ task: URLSessionTask) -> (messageId: ObvMessageIdentifier, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (ObvMessageIdentifier, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)]
        }
        return info
    }
    
    private func insert(_ task: URLSessionTask, forMessageId messageId: ObvMessageIdentifier, flowId: FlowIdentifier) {
        currentTasksQueue.sync {
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (messageId, flowId, Data())
        }
    }
    
    private func accumulate(_ data: Data, forTask task: URLSessionTask) {
        currentTasksQueue.sync {
            guard let (messageId, flowId, currentData) = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] else { return }
            var newData = currentData
            newData.append(data)
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (messageId, flowId, newData)
        }
    }
    
}


// MARK: - UploadMessageDelegate

extension UploadMessageAndGetUidsCoordinator: UploadMessageAndGetUidDelegate {
    
    private enum SyncQueueOutput {
        case previousTaskExists
        case cannotFindMessageInDatabase
        case messageWasAlreadyUploaded
        case cancelExternallyRequested
        case newRunningTask(task: URLSessionTask)
        case failedToCreateTask(error: Error)
    }
    
    func getIdFromServerUploadMessage(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set (1)", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            return
        }
        
        os_log("Will try to get Id from server for message %{public}@ within flow %{public}@", log: log, type: .info, messageId.debugDescription, flowId.debugDescription)
        
        var syncQueueOutput: SyncQueueOutput? // The state after the localQueue.sync is executed
        
        localQueue.sync {
            
            guard !currentTaskExistsForMessage(withId: messageId) else {
                syncQueueOutput = .previousTaskExists
                return
            }
            
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                
                guard let message = try? OutboxMessage.get(messageId: messageId, delegateManager: delegateManager, within: obvContext) else {
                    syncQueueOutput = .cannotFindMessageInDatabase
                    return
                }
                
                if message.uploaded {
                    syncQueueOutput = .messageWasAlreadyUploaded
                    return
                }
                
                guard !message.cancelExternallyRequested else {
                    syncQueueOutput = .cancelExternallyRequested
                    return
                }
                
                // If we reach this point, we do need to ask the server for and "uid from server"
                
                let headers = message.headers.map() { ($0.deviceUid, $0.wrappedKey, $0.toCryptoIdentity) }
                let encryptedAttachments = message.attachments.map() { (length: $0.ciphertextLength, chunkLength: $0.chunks.first!.ciphertextChunkLength) }
                
                let method = ObvServerUploadMessageAndGetUidsMethod(
                    ownedIdentity: messageId.ownedCryptoIdentity,
                    headers: headers,
                    encryptedContent: message.encryptedContent,
                    encryptedExtendedMessagePayload: message.encryptedExtendedMessagePayload,
                    encryptedAttachments: encryptedAttachments,
                    serverURL: message.serverURL,
                    isAppMessageWithUserContent: message.isAppMessageWithUserContent,
                    isVoipMessageForStartingCall: message.isVoipMessage,
                    flowId: flowId)
                method.identityDelegate = delegateManager.identityDelegate
                let task: URLSessionDataTask
                do {
                    task = try method.dataTask(within: self.session)
                } catch let error {
                    syncQueueOutput = .failedToCreateTask(error: error)
                    return
                }

                insert(task, forMessageId: messageId, flowId: flowId)
                
                syncQueueOutput = .newRunningTask(task: task)
            }
            
        } // End of localQueue.sync

        guard syncQueueOutput != nil else {
            os_log("syncQueueOutput is nil", log: log, type: .fault)
            return
        }
        
        switch syncQueueOutput! {

        case .previousTaskExists:
            os_log("Running task already exists for message %{public}@", log: log, type: .debug, messageId.debugDescription)
            return

        case .cannotFindMessageInDatabase:
            os_log("Message %{public}@ cannot be found in database", log: log, type: .error, messageId.debugDescription)
            return

        case .messageWasAlreadyUploaded:
            os_log("Message %{public}@ was already uploaded", log: log, type: .debug, messageId.debugDescription)
            delegateManager.networkSendFlowDelegate.successfulUploadOfMessage(messageId: messageId, flowId: flowId)
            return

        case .cancelExternallyRequested:
            os_log("Message %{public}@ was externally cancelled", log: log, type: .debug, messageId.debugDescription)
            return
            
        case .failedToCreateTask(error: let error):
            os_log("Could not create task for ObvServerUploadMessageAndGetUidsMethod: %{public}@", log: log, type: .error, error.localizedDescription)
            return
            
        case .newRunningTask(task: let task):
            os_log("New running task to get uid from server for message %{public}@", log: log, type: .debug, messageId.debugDescription)
            task.resume()

        }
    }
    
    
    func cancelMessageUpload(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) throws {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set (1)", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            return
        }

        try localQueue.sync {
            try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
                obvContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
                guard let message = try? OutboxMessage.get(messageId: messageId, delegateManager: delegateManager, within: obvContext) else { return }
                message.cancelUpload()
                try obvContext.save(logOnFailure: log)
            }
        }
        
    }
}


// MARK: - URLSessionDataDelegate

extension UploadMessageAndGetUidsCoordinator: URLSessionDataDelegate {
    
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        accumulate(data, forTask: dataTask)
    }
    
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set (2)", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            return
        }
        
        guard let (messageId, flowId, responseData) = getInfoFor(task) else { return }
        
        guard error == nil else {
            os_log("The download task failed for message %@ within flow %{public}@: %@", log: log, type: .error, messageId.debugDescription, flowId.debugDescription, error!.localizedDescription)
            _ = removeInfoFor(task)
            delegateManager.networkSendFlowDelegate.failedUploadAndGetUidOfMessage(messageId: messageId, flowId: flowId)
            return
        }
        
        // If we reach this point, the data task did complete without error
        
        guard let (status, infosFromServer) = ObvServerUploadMessageAndGetUidsMethod.parseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .fault)
            _ = removeInfoFor(task)
            delegateManager.networkSendFlowDelegate.failedUploadAndGetUidOfMessage(messageId: messageId, flowId: flowId)
            return
        }
        
        switch status {
            
        case .ok:
            
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                guard let message = try? OutboxMessage.get(messageId: messageId, delegateManager: delegateManager, within: obvContext) else {
                    os_log("Could not retrieve the message", log: log, type: .error)
                    _ = removeInfoFor(task)
                    delegateManager.networkSendFlowDelegate.failedUploadAndGetUidOfMessage(messageId: messageId, flowId: flowId)
                    return
                }
                
                let idFromServer = infosFromServer!.idFromServer
                let nonce = infosFromServer!.nonce
                let timestampFromServer = infosFromServer!.timestampFromServer
                let signedURLs = infosFromServer!.signedURLs
                
                do {
                    try message.setAttachmentUploadPrivateUrls(signedURLs)
                } catch {
                    os_log("The server did not return the appropriate number of signed URLs for the attachment chunks", log: log, type: .error)
                    _ = removeInfoFor(task)
                    delegateManager.networkSendFlowDelegate.failedUploadAndGetUidOfMessage(messageId: messageId, flowId: flowId)
                    return
                }
                                
                message.setAcknowledged(withMessageUidFromServer: idFromServer, nonceFromServer: nonce, andTimeStampFromServer: timestampFromServer, log: log)
                
                do {
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not process the uid from server / upload message", log: log, type: .fault)
                    _ = removeInfoFor(task)
                    delegateManager.networkSendFlowDelegate.failedUploadAndGetUidOfMessage(messageId: messageId, flowId: flowId)
                    return
                }
                
                os_log("Message %{public}@ received an uid from server and was successfully uploaded within flow %{public}@", log: log, type: .debug, messageId.debugDescription, flowId.debugDescription)
                _ = removeInfoFor(task)
                delegateManager.networkSendFlowDelegate.successfulUploadOfMessage(messageId: messageId, flowId: flowId)
                return
            }
            
            
        case .generalError:
            
            os_log("Server reported general error", log: log, type: .fault)
            
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                let message = try? OutboxMessage.get(messageId: messageId, delegateManager: delegateManager, within: obvContext)
                try? message?.resetForResend()
                try? obvContext.save(logOnFailure: log)
            }
            
            _ = removeInfoFor(task)
            delegateManager.networkSendFlowDelegate.newOutboxMessageWithAttachments(messageId: messageId, flowId: flowId)
            return
        }
    }
}
