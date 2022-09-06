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
import ObvMetaManager
import ObvTypes
import OlvidUtils


final class UploadAttachmentChunksSessionDelegate: NSObject {
    
    let uuid = UUID()
    private let logCategory = String(describing: UploadAttachmentChunksSessionDelegate.self)
    private let log: OSLog
    private let attachmentId: AttachmentIdentifier
    private let obvContext: ObvContext
    private let appType: AppType
    private let queueSynchronizingCallsToTracker = DispatchQueue(label: "Queue for sync tracker calls within UploadAttachmentChunksSessionDelegate")

    weak var tracker: AttachmentChunkUploadProgressTracker?

    private var flowId: FlowIdentifier {
        return obvContext.flowId
    }

    enum ErrorForTracker: Error {
        case couldNotRecoverAttachmentIdFromTask
        case unsupportedHTTPErrorStatusCode
        case atLeastOneChunkDownloadPrivateURLHasExpired
        case couldNotRetrieveAnHTTPResponse
        case aTaskDidBecomeInvalidWithError(error: Error)
        case aTaskWasCancelled
        case sessionInvalidationError(error: Error)
        case cannotFindAttachmentInDatabase
        case couldNotSaveContext
    }

    // First error "wins"
    private var _error: ErrorForTracker?
    private var errorForTracker: ErrorForTracker? {
        get { _error }
        set {
            guard _error == nil && newValue != nil else { return }
            _error = newValue
        }
    }
    
    init(attachmentId: AttachmentIdentifier, obvContext: ObvContext, appType: AppType, logSubsystem: String) {
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.attachmentId = attachmentId
        self.obvContext = obvContext
        self.appType = appType
        super.init()
        os_log("Initialized UploadAttachmentChunksSessionDelegate %{public}@", log: log, type: .info, self.uuid.description)
    }
    
    deinit {
        os_log("Within the deinit of UploadAttachmentChunksSessionDelegate %{public}@ for attachment %{public}@", log: log, type: .info, self.uuid.description, attachmentId.debugDescription)
    }
    
}


// MARK: - Tracker

protocol AttachmentChunkUploadProgressTracker: AnyObject {
    func uploadAttachmentChunksSessionDidBecomeInvalid(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier, error: UploadAttachmentChunksSessionDelegate.ErrorForTracker?)
    func urlSessionDidFinishEventsForSessionWithIdentifier(_ identifier: String)
    func attachmentChunkDidProgress(attachmentId: AttachmentIdentifier, chunkProgress: (chunkNumber: Int, totalBytesSent: Int64, totalBytesExpectedToSend: Int64), flowId: FlowIdentifier)
    func attachmentChunksAreAcknowledged(attachmentId: AttachmentIdentifier, chunkNumbers: [Int], flowId: FlowIdentifier)
}


// MARK: - URLSessionDelegate

extension UploadAttachmentChunksSessionDelegate: URLSessionDelegate {
    
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {

        // This delegate method is typically called when all tasks have been completed while the App stayed in the foreground.
        // It does not seem to be called when the tasks were completed while the app was in the background. In that case,
        // `func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession)` is called.

        let tracker = self.tracker
        let attachmentId = self.attachmentId
        let flowId = self.flowId

        if let error = error {
            os_log("The session with identifier %{public}@ did Become Invalid with error: %{debug}@", log: log, type: .error, session.configuration.identifier ?? "NO IDENTIFIER", error.localizedDescription)
            errorForTracker = .sessionInvalidationError(error: error)
        } else {
            os_log("The session with identifier %{public}@ did Become Invalid without error", log: log, type: .info, session.configuration.identifier ?? "NO IDENTIFIER")
        }
                
        let errorForTracker = self.errorForTracker
        queueSynchronizingCallsToTracker.async {
            tracker?.uploadAttachmentChunksSessionDidBecomeInvalid(attachmentId: attachmentId, flowId: flowId, error: errorForTracker)
        }

    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        
        // This delegate method is typically called when all tasks have been completed while the App was in the background.
        // It does not seem to be called when the tasks were completed while the app was in the foreground. In that case,
        // `func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?)` is called.

        let tracker = self.tracker
        let attachmentId = self.attachmentId
        let flowId = self.flowId
        let log = self.log

        os_log("urlSession Did Finish Events for attachment %{public}@ within the delegate with UID %{public}@", log: log, type: .info, attachmentId.debugDescription, self.uuid.uuidString)
        
        queueSynchronizingCallsToTracker.async {
            tracker?.uploadAttachmentChunksSessionDidBecomeInvalid(attachmentId: attachmentId, flowId: flowId, error: nil)
            if let sessionIdentifier = session.configuration.identifier {
                tracker?.urlSessionDidFinishEventsForSessionWithIdentifier(sessionIdentifier)
            } else {
                assertionFailure()
                os_log("No session identifier could be found for attachment %{public}@", log: log, type: .error, attachmentId.debugDescription)
            }
        }
        
    }
    
}


// MARK: - URLSessionTaskDelegate

extension UploadAttachmentChunksSessionDelegate: URLSessionTaskDelegate {
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let chunkNumber = task.getAssociatedChunkNumber() else { return }
        let log = self.log
        os_log("🚀 Chunk %d of attachment %{public}@ did progress", log: log, type: .info, chunkNumber, attachmentId.debugDescription)
        let chunkProgress = (chunkNumber, totalBytesSent, totalBytesExpectedToSend)
        let tracker = self.tracker
        let attachmentId = self.attachmentId
        let flowId = self.flowId
        queueSynchronizingCallsToTracker.async {
            tracker?.attachmentChunkDidProgress(attachmentId: attachmentId, chunkProgress: chunkProgress, flowId: flowId)
        }
    }

    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        
        guard let chunkNumber = task.getAssociatedChunkNumber() else {
            os_log("Could not recover attachmentId from the task", log: log, type: .fault)
            self.errorForTracker = .couldNotRecoverAttachmentIdFromTask
            return
        }

        guard error == nil else {
            os_log("The upload task %d for the chunk %{public}@/%d did fail within flow %{public}@: %{public}@", log: log, type: .error, task.taskIdentifier, attachmentId.debugDescription, chunkNumber, flowId.debugDescription, error!.localizedDescription)
            if (error! as NSError).code == NSURLErrorCancelled {
                self.errorForTracker = .aTaskWasCancelled
            } else {
                self.errorForTracker = .aTaskDidBecomeInvalidWithError(error: error!)
            }
            return
        }
        
        os_log("The upload task %d for the chunk %{public}@/%d did complete with no error within flow %{public}@", log: log, type: .info, task.taskIdentifier, attachmentId.debugDescription, chunkNumber, flowId.debugDescription)

        guard let httpURLResponse = task.response as? HTTPURLResponse else {
            os_log("Could not retrieve the HTTP response for chunk %{public}@/%d", log: log, type: .fault, attachmentId.debugDescription, chunkNumber)
            self.errorForTracker = .couldNotRetrieveAnHTTPResponse
            return
        }
        
        os_log("The http status code is %{public}d", log: log, type: .info, httpURLResponse.statusCode)

        guard httpURLResponse.statusCode == 200 else {
            // An error occured
            switch httpURLResponse.statusCode {
            case 400:
                os_log("The server reported an error %{public}d for the private URL for a chunk of attachment %{public}@. We ask for new private URLs", log: log, type: .info, httpURLResponse.statusCode, attachmentId.debugDescription)
                self.errorForTracker = .atLeastOneChunkDownloadPrivateURLHasExpired
            case 403:
                os_log("The server reported that the private URL for a chunk of attachment %{public}@ has expired. We should ask for new private URLs", log: log, type: .info, attachmentId.debugDescription)
                self.errorForTracker = .atLeastOneChunkDownloadPrivateURLHasExpired
            default:
                os_log("The error status code is not supported. Error code is %{public}d", log: log, type: .fault, httpURLResponse.statusCode)
                logRequestURLInTask(task, to: log)
                self.errorForTracker = .unsupportedHTTPErrorStatusCode
            }
            return
        }
        
        // If we reach this point, the task successsfully uploaded its associated chunk
        
        let obvContext = self.obvContext
        let attachmentId = self.attachmentId
        let log = self.log
        let flowId = self.flowId
        let tracker = self.tracker
        let appType = self.appType

        queueSynchronizingCallsToTracker.async {
            obvContext.performAndWait {
                
                guard let attachment = try? OutboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                    os_log("Could not retrieve attachment %{public}@ in DB", log: log, type: .fault, attachmentId.debugDescription)
                    self.errorForTracker = .cannotFindAttachmentInDatabase
                    return
                }
                
                guard !attachment.cancelExternallyRequested else {
                    return
                }
                
                attachment.chunkWasAchknowledged(chunkNumber: chunkNumber, by: appType)
                
                do {
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not save the fact that chunk %d were acknowledged for attachment %{public}@", log: log, type: .error, chunkNumber, attachmentId.debugDescription)
                    self.errorForTracker = .couldNotSaveContext
                    return
                }
                
                os_log("⛑ Saved to DB: Chunk %{public}@/%d was acknowledged within flow %{public}@", log: log, type: .info, attachmentId.debugDescription, chunkNumber, flowId.debugDescription)
                
                // Deal with the progress
                
                tracker?.attachmentChunksAreAcknowledged(attachmentId: attachmentId, chunkNumbers: [chunkNumber], flowId: flowId)
                
            }
        }

    }
    
}


// MARK: - URLSessionDataDelegate

extension UploadAttachmentChunksSessionDelegate: URLSessionDataDelegate {
}


// MARK: - Helpers

extension UploadAttachmentChunksSessionDelegate {
    
    private func logRequestURLInTask(_ task: URLSessionTask, to log: OSLog) {
        if let urlString = task.currentRequest?.url?.absoluteString, !urlString.isEmpty {
            let nsURLString = urlString as NSString
            let numberOfURLParts = 1 + (urlString.count - 1) / 800
            for partIndex in 0..<numberOfURLParts {
                let length = min(nsURLString.length-partIndex*800, 800)
                let urlPart = nsURLString.substring(with: NSRange(location: partIndex*800, length: length))
                os_log("Part %d of %d of Request URL: %{public}@", log: log, type: .fault, partIndex+1, numberOfURLParts, urlPart)
            }
        } else {
            os_log("Could not log request URL", log: log, type: .fault)
        }
    }
    
}


// MARK: - Extending URLSessionTask for storing chunk numbers within the description

extension URLSessionTask {
    
    func getAssociatedChunkNumber() -> Int? {
        guard let taskDescription = self.taskDescription else { return nil }
        return Int(taskDescription)
    }
    
    func setAssociatedChunkNumber(_ chunkNumber: Int) {
        self.taskDescription = "\(chunkNumber)"
    }
}
