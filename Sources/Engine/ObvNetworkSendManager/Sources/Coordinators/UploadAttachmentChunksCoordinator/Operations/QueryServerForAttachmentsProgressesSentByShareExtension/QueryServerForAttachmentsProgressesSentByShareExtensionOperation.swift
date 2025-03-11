/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvMetaManager
import CoreData
import ObvTypes
import ObvServerInterface
import OlvidUtils


final class QueryServerForAttachmentsProgressesSentByShareExtensionOperation: Operation, @unchecked Sendable {
    
    enum ReasonForCancel: Hashable {
        case contextCreatorIsNotSet
        case delegateManagerIsNotSet
        case identityDelegateIsNotSet
        case couldNotReadOutboxAttachmentSessionDatabase
        case noMoreAttachmentSentByShareExtension
    }

    private let uuid = UUID()
    private let logSubsystem: String
    private let log: OSLog
    private let flowId: FlowIdentifier
    private weak var tracker: AttachmentChunkUploadProgressTracker?
    private weak var delegateManager: ObvNetworkSendDelegateManager?
    private let logCategory = String(describing: QueryServerForAttachmentsProgressesSentByShareExtensionOperation.self)

    private(set) var reasonForCancel: ReasonForCancel?

    init(flowId: FlowIdentifier, tracker: AttachmentChunkUploadProgressTracker, delegateManager: ObvNetworkSendDelegateManager) {
        self.flowId = flowId
        self.tracker = tracker
        self.logSubsystem = delegateManager.logSubsystem
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.delegateManager = delegateManager
    }
    
    private func cancel(withReason reason: ReasonForCancel) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
    }

    
    
    override func main() {

        guard let delegateManager = self.delegateManager else {
            os_log("The delegate manager is not set", log: log, type: .default)
            assertionFailure()
            cancel(withReason: .delegateManagerIsNotSet)
            return
        }
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The delegate manager is not set", log: log, type: .default)
            assertionFailure()
            cancel(withReason: .contextCreatorIsNotSet)
            return
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .default)
            assertionFailure()
            cancel(withReason: .identityDelegateIsNotSet)
            return
        }
        
        let log = self.log

        var attachmentsSentByShareExtension = Set<AttachmentIdAndServerURL>()

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { [weak self] (obvContext) in
            
            guard let _self = self else { return }
            
            // We look for messages having attachments sent by the share extension
            do {
                let sessions = try OutboxAttachmentSession.getAllCreatedByAppType(.shareExtension, within: obvContext)
                attachmentsSentByShareExtension = Set(sessions.compactMap({
                    guard let attachmentId = $0.attachment?.attachmentId else { return nil }
                    guard let serverURL = $0.attachment?.message?.serverURL else { return nil }
                    return AttachmentIdAndServerURL(attachmentId: attachmentId, serverURL: serverURL)
                }))
            } catch {
                os_log("Failed to read outbox attachment sessions from database: %{public}@", log: log, type: .fault, error.localizedDescription)
                _self.cancel(withReason: .couldNotReadOutboxAttachmentSessionDatabase)
                return
            }
                        
        }
        
        guard !attachmentsSentByShareExtension.isEmpty else {
            cancel(withReason: .noMoreAttachmentSentByShareExtension)
            return
        }
        
        // If we reach this point, we have attachments currently being sent by the share extension

        let sessionDelegate = GetAttachmentUploadProgressMethodSessionDelegate(log: log)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.useOlvidSettings(sharedContainerIdentifier: nil)
        let session = URLSession(configuration: sessionConfiguration, delegate: sessionDelegate, delegateQueue: nil)
 
        let methods: [GetAttachmentUploadProgressMethod] = attachmentsSentByShareExtension.map {
            let method = GetAttachmentUploadProgressMethod(attachmentId: $0.attachmentId, serverURL: $0.serverURL, flowId: flowId)
            method.identityDelegate = identityDelegate
            return method
        }
        for method in methods {
            do {
                let task = try method.dataTask(within: session)
                sessionDelegate.insert(task, forAttachmentId: method.attachmentId, flowId: flowId)
                task.resume()
            } catch let error {
                os_log("Failed to create a data task: %{public}@", log: log, type: .error, error.localizedDescription)
                continue
            }
        }
        
        session.finishTasksAndInvalidate()

    }
    
}


fileprivate struct AttachmentIdAndServerURL: Hashable {
    let attachmentId: ObvAttachmentIdentifier
    let serverURL: URL
}



final class GetAttachmentUploadProgressMethodSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    
    private weak var delegateManager: ObvNetworkSendDelegateManager?
    private weak var tracker: AttachmentChunkUploadProgressTracker?
    private var _currentTasks = [UIBackgroundTaskIdentifier: (attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier, dataReceived: Data)]()
    private let currentTasksQueue = DispatchQueue(label: "GetAttachmentUploadProgressMethodSessionDelegate")
    private let log: OSLog
    
    init(log: OSLog) {
        self.log = log
        super.init()
    }

    private func currentTaskExistsForAttachment(withId id: ObvAttachmentIdentifier) -> Bool {
        var exist = true
        currentTasksQueue.sync {
            exist = _currentTasks.values.contains(where: { $0.attachmentId == id })
        }
        return exist
    }
    
    private func removeInfoFor(_ task: URLSessionTask) -> (attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (ObvAttachmentIdentifier, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentTasks.removeValue(forKey: UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier))
        }
        return info
    }
    
    private func getInfoFor(_ task: URLSessionTask) -> (attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier, dataReceived: Data)? {
        var info: (ObvAttachmentIdentifier, FlowIdentifier, Data)? = nil
        currentTasksQueue.sync {
            info = _currentTasks[UIBackgroundTaskIdentifier(rawValue: task.taskIdentifier)]
        }
        return info
    }
    
    fileprivate func insert(_ task: URLSessionTask, forAttachmentId attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) {
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

    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        accumulate(data, forTask: dataTask)
    }

    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        
        guard let (attachmentId, flowId, responseData) = getInfoFor(task) else { return }
        
        guard error == nil else {
            os_log("The download task failed for attachment %@ within flow %{public}@: %@", log: log, type: .error, attachmentId.debugDescription, flowId.debugDescription, error!.localizedDescription)
            _ = removeInfoFor(task)
            return
        }
        
        // If we reach this point, the data task did complete without error
        
        guard let (status, acknowledgedChunksNumbers) = GetAttachmentUploadProgressMethod.parseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .fault)
            _ = removeInfoFor(task)
            return
        }
        
        switch status {
        case .deletedFromServer:
            assertionFailure()
            return
        case .generalError:
            assertionFailure()
            return
        case .ok:
            guard let acknowledgedChunksNumbers = acknowledgedChunksNumbers else {
                assertionFailure()
                return
            }
            tracker?.attachmentChunksAreAcknowledged(attachmentId: attachmentId, chunkNumbers: acknowledgedChunksNumbers, flowId: flowId)
        }
    }
}
