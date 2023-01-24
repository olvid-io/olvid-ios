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
import CoreData
import ObvOperation
import ObvServerInterface
import ObvTypes
import ObvMetaManager
import OlvidUtils


final class TryToDeleteMessageAndAttachmentsCoordinator: NSObject {
    
    // MARK: - Instance variables
    
    fileprivate let defaultLogSubsystem = ObvNetworkSendDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "TryToDeleteMessageAndAttachmentsCoordinator"
    
    weak var delegateManager: ObvNetworkSendDelegateManager?
    
    private let localQueue = DispatchQueue(label: "TryToDeleteMessageAndAttachmentsCoordinatorQueue")
    
    private lazy var session: URLSession! = {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.useOlvidSettings(sharedContainerIdentifier: delegateManager?.sharedContainerIdentifier)
        return URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }()

    private var _currentTasks = [UIBackgroundTaskIdentifier: (attachmentId: AttachmentIdentifier, flowId: FlowIdentifier, dataReceived: Data)]()
    private let currentTasksQueue = DispatchQueue(label: "TryToDeleteMessageAndAttachmentsCoordinatorQueueForCurrentTasks")

}


// MARK: - Synchronized access to the current download tasks

extension TryToDeleteMessageAndAttachmentsCoordinator {
    
    private func currentTaskExistsForAttachment(withId attachmentId: AttachmentIdentifier) -> Bool {
        var exist = true
        currentTasksQueue.sync {
            exist = _currentTasks.values.contains(where: { $0.attachmentId == attachmentId })
        }
        return exist
    }
    
    private func taskExistsForAtLeastOneAttachmentAssociatedToMessage(withId messageId: MessageIdentifier) -> Bool {
        var exist = true
        currentTasksQueue.sync {
            exist = _currentTasks.values.contains(where: { $0.attachmentId.messageId == messageId })
        }
        return exist
    }

    private func removeInfoFor(_ task: URLSessionTask) -> (attachmentId: AttachmentIdentifier, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (AttachmentIdentifier, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentTasks.removeValue(forKey: UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier))
        }
        return info
    }
    
    private func getInfoFor(_ task: URLSessionTask) -> (mesattachmentIdsageId: AttachmentIdentifier, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (AttachmentIdentifier, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)]
        }
        return info
    }
    
    private func insert(_ task: URLSessionTask, forAttachmentId attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {
        currentTasksQueue.sync {
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (attachmentId, flowId, Data())
        }
    }
    
    private func accumulate(_ data: Data, forTask task: URLSessionTask) {
        currentTasksQueue.sync {
            guard let (attachmentId, flowId, currentData) = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] else { return }
            var newData = currentData
            newData.append(data)
            _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)] = (attachmentId, flowId, newData)
        }
    }

}


// MARK: - TryToDeleteMessageAndAttachmentsDelegate

extension TryToDeleteMessageAndAttachmentsCoordinator: TryToDeleteMessageAndAttachmentsDelegate {

    func tryToDeleteMessageAndAttachments(messageId: MessageIdentifier, flowId: FlowIdentifier) {

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

        localQueue.sync {

            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                obvContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump // In case cancelExternallyRequested is set to true

                guard let message = try? OutboxMessage.get(messageId: messageId, delegateManager: delegateManager, within: obvContext) else { return }
                
                guard message.uploaded || message.cancelExternallyRequested else {
                    os_log("Aborting the deletion of a message that is neither uploaded nor cancelled", log: log, type: .debug)
                    return
                }
                
                for attachment in message.attachments {
                    guard attachment.acknowledged || attachment.cancelExternallyRequested else {
                        os_log("Aborting the deletion of a message that has an attachment that is neither uploaded nor cancelled", log: log, type: .debug)
                        return
                    }
                }
                
                let externallyCancelledAttachments = message.attachments.filter { $0.cancelExternallyRequested && !$0.acknowledged }
                
                if externallyCancelledAttachments.isEmpty {
                    
                    // We delete the message and attachments right now
                    
                    // We remove the attachment *content*, if required
                    removeTheAttachmentFilesThatAreMarkedAsDeleteAfterSend(attachments: message.attachments)
                    
                    // We remove the database entries (deleting the message cascade deletes the headers and attachments)
                    do {
                        try message.deleteThisOutboxMessage()
                        try obvContext.save(logOnFailure: log)
                    } catch {
                        os_log("We could not delete the message %{public}@ nor its attachments", log: log, type: .error, messageId.debugDescription)
                        return
                    }
                    
                    os_log("The outbox message %{public}@ and its attachments were deleted", log: log, type: .debug, messageId.debugDescription)
                    
                    delegateManager.networkSendFlowDelegate.messageAndAttachmentsWereDeletedFromTheirOutboxes(messageId: messageId, flowId: flowId)
                    
                } else {
                    
                    // Before deleting the message and attachments, we notify the server about the fact that attachments were cancelled. We will delete the message and attachments within the completion handler of the session.
                    
                    for attachment in externallyCancelledAttachments {
                        guard !currentTaskExistsForAttachment(withId: attachment.attachmentId) else {
                            continue
                        }
                        guard let message = attachment.message else {
                            os_log("Could not find message associated to attachment, unexpected", log: log, type: .fault)
                            assertionFailure()
                            continue
                        }
                        guard let messageUidFromServer = message.messageUidFromServer, let nonceFromServer = message.nonceFromServer else {
                            os_log("The attachment we are trying to cancel has no messageUid from server. This can happen if the message never managed to obtain this UID from server due, e.g., to bad network conditions", log: log, type: .error)
                            continue
                        }
                        let method = ObvServerCancelAttachmentUpload(ownedIdentity: messageId.ownedCryptoIdentity,
                                                                     serverURL: message.serverURL,
                                                                     messageUidFromServer: messageUidFromServer,
                                                                     attachmentNumber: attachment.attachmentNumber,
                                                                     nonceFromServer: nonceFromServer, flowId: flowId)
                        method.identityDelegate = delegateManager.identityDelegate
                        let task: URLSessionDataTask
                        do {
                            task = try method.dataTask(within: self.session)
                        } catch let error {
                            os_log("Could not create task for ObvServerCancelAttachmentUpload: %{public}@", log: log, type: .error, error.localizedDescription)
                            assertionFailure()
                            return
                        }
                        insert(task, forAttachmentId: attachment.attachmentId, flowId: flowId)
                        task.resume()
                    }
                    
                }
                
            }

        }
    }
    
    private func removeTheAttachmentFilesThatAreMarkedAsDeleteAfterSend(attachments: [OutboxAttachment]) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        let attachmentsToDelete = attachments.filter() { $0.deleteAfterSend }
        attachmentsToDelete.forEach { (attachment) in
            if FileManager.default.fileExists(atPath: attachment.fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: attachment.fileURL)
                } catch {
                    os_log("Could not delete attachment at path: %@ (error: %@)", log: log, type: .fault, attachment.fileURL.path)
                }
            }
        }
    }

}


// MARK: - URLSessionDataDelegate

extension TryToDeleteMessageAndAttachmentsCoordinator: URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        accumulate(data, forTask: dataTask)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {

        defer {
            _ = removeInfoFor(task)
        }
        
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
        
        localQueue.sync {
            
            guard let (attachmentId, flowId, responseData) = getInfoFor(task) else { return }
            
            let messageId = attachmentId.messageId
            
            guard error == nil else {
                os_log("The task failed for attachment %{public}@ within flow %{public}@: %@", log: log, type: .error, attachmentId.debugDescription, flowId.debugDescription, error!.localizedDescription)
                return
            }

            guard let status = ObvServerCancelAttachmentUpload.parseObvServerResponse(responseData: responseData, using: log) else {
                os_log("Could not parse the server response", log: log, type: .fault)
                return
            }

            switch status {
            case .ok:
                
                // We check that this task was the last one concerning the attachments of the message.
                // If this is the case we can delete the message and its attachments from their outbox.
                
                _ = removeInfoFor(task)
                guard !taskExistsForAtLeastOneAttachmentAssociatedToMessage(withId: attachmentId.messageId) else {
                    return
                }
                
                // If we reach this point, we can delete the message and attachments from the outboxes
                
                deleteMessageAndAttachmentsFromTheirOutboxes(messageId: messageId,
                                                             flowId: flowId,
                                                             contextCreator: contextCreator,
                                                             delegateManager: delegateManager,
                                                             log: log)

                return
                
            case .generalError:
                os_log("Server reported general error during the TryToDeleteMessageAndAttachmentsCoordinator download task for message %@. We delete the message (and its attachments) anyway.", log: log, type: .fault, messageId.debugDescription)
                
                deleteMessageAndAttachmentsFromTheirOutboxes(messageId: messageId,
                                                             flowId: flowId,
                                                             contextCreator: contextCreator,
                                                             delegateManager: delegateManager,
                                                             log: log)
                
                return
            }
            
        }
        

        
    }
    
    
    private func deleteMessageAndAttachmentsFromTheirOutboxes(messageId: MessageIdentifier, flowId: FlowIdentifier, contextCreator: ObvCreateContextDelegate, delegateManager: ObvNetworkSendDelegateManager, log: OSLog) {
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            guard let message = try? OutboxMessage.get(messageId: messageId, delegateManager: delegateManager, within: obvContext) else { return }
            
            // We remove the attachment *content*, if required
            removeTheAttachmentFilesThatAreMarkedAsDeleteAfterSend(attachments: message.attachments)
            
            // We remove the database entries (deleting the message cascade deletes the headers and attachments)
            do {
                try message.deleteThisOutboxMessage()
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("We could not delete the message %{public}@ nor its attachments", log: log, type: .error, messageId.debugDescription)
                return
            }
            
            os_log("The outbox message %{public}@ and its attachments were deleted", log: log, type: .debug, messageId.debugDescription)
            
            delegateManager.networkSendFlowDelegate.messageAndAttachmentsWereDeletedFromTheirOutboxes(messageId: messageId, flowId: flowId)
            
        }

    }
    
}
