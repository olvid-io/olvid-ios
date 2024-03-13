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
import CoreData
import os.log
import ObvMetaManager
import ObvTypes
import OlvidUtils
import ObvCrypto


// MARK: - Tracker

protocol AttachmentChunkDownloadProgressTracker: AnyObject {
    func downloadAttachmentChunksSessionDidBecomeInvalid(downloadAttachmentChunksSessionDelegate: DownloadAttachmentChunksSessionDelegate, error: DownloadAttachmentChunksSessionDelegate.ErrorForTracker?) async // called
    func urlSessionDidFinishEventsForSessionWithIdentifier(downloadAttachmentChunksSessionDelegate: DownloadAttachmentChunksSessionDelegate, urlSessionIdentifier: String) async // called
    func attachmentChunkDidProgress(downloadAttachmentChunksSessionDelegate: DownloadAttachmentChunksSessionDelegate, chunkProgress: (chunkNumber: Int, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)) async // called
    func attachmentChunkWasDecryptedAndWrittenToAttachmentFile(downloadAttachmentChunksSessionDelegate: DownloadAttachmentChunksSessionDelegate, chunkNumber: Int) async // called
    func attachmentDownloadIsComplete(downloadAttachmentChunksSessionDelegate: DownloadAttachmentChunksSessionDelegate) async //called
}


/// An instance of this class servers as a delegate for an URLSession allowing to download an attachment chunk. As a consequence, this class cannot have any strong reference to other classes, like the delegate manager for example.
/// This is also the reason why we receive a context in the initializer.
final class DownloadAttachmentChunksSessionDelegate: NSObject {

    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "DownloadAttachmentChunksSessionDelegate"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)

    let uuid = UUID()
    let attachmentId: ObvAttachmentIdentifier
    let flowId: FlowIdentifier
    private let decryptedAttachmentURL: URL
    private let cleartextChunkLengths: [Int]
    private let decryptionKey: AuthenticatedEncryptionKey
    private let queueForDecryptingChunks: OperationQueue
    private let queueForComposedOperations: OperationQueue
    private let queueSharedAmongCoordinators: OperationQueue
    private let contextProvider: ContextProviderForDownloadAttachmentChunksSessionDelegate
    weak var tracker: AttachmentChunkDownloadProgressTracker?

    enum ErrorForTracker: Error {
        case couldNotRecoverAttachmentIdFromTask
        case unsupportedHTTPErrorStatusCode
        case atLeastOneChunkDownloadPrivateURLHasExpired
        case couldNotRetrieveAnHTTPResponse
        case sessionInvalidationError(error: Error)
        case cannotFindAttachmentInDatabase
        case couldNotSaveContext
        case atLeastOneChunkIsNotYetAvailableOnServer
        case couldNotOpenEncryptedChunkFile
        case failedToDecryptChunkOrWriteToFile
        case markChunkAsWrittenToAttachmentFileOperationFailed
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

    init(attachmentId: ObvAttachmentIdentifier, logSubsystem: String, decryptedAttachmentURL: URL, tracker: AttachmentChunkDownloadProgressTracker, flowId: FlowIdentifier, cleartextChunkLengths: [Int], decryptionKey: AuthenticatedEncryptionKey, queueForDecryptingChunks: OperationQueue, queueForComposedOperations: OperationQueue, queueSharedAmongCoordinators: OperationQueue, obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        self.attachmentId = attachmentId
        self.tracker = tracker
        self.flowId = flowId
        self.decryptedAttachmentURL = decryptedAttachmentURL
        self.cleartextChunkLengths = cleartextChunkLengths
        self.decryptionKey = decryptionKey
        self.queueForDecryptingChunks = queueForDecryptingChunks
        self.queueForComposedOperations = queueForComposedOperations
        self.queueSharedAmongCoordinators = queueSharedAmongCoordinators
        self.contextProvider = .init(obvContext: obvContext, viewContext: viewContext)
        super.init()
        Self.log = OSLog(subsystem: logSubsystem, category: Self.logCategory)
    }
    
}


// MARK: - URLSessionDelegate

extension DownloadAttachmentChunksSessionDelegate: URLSessionDelegate {
    
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {

        // This delegate method is typically called when all tasks have been completed while the App stayed in the foreground.
        // It does not seem to be called when the tasks were completed while the app was in the background. In that case,
        // `func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession)` is called.

        guard let tracker = self.tracker else { return }

        if let error = error {
            os_log("📄 The session with identifier %{public}@ did Become Invalid with error: %{debug}@", log: Self.log, type: .error, session.configuration.identifier ?? "NO IDENTIFIER", error.localizedDescription)
            errorForTracker = .sessionInvalidationError(error: error)
        } else {
            os_log("📄 The session with identifier %{public}@ did Become Invalid without error", log: Self.log, type: .info, session.configuration.identifier ?? "NO IDENTIFIER")
        }
        
        let errorForTracker = self.errorForTracker
        Task {
            await tracker.downloadAttachmentChunksSessionDidBecomeInvalid(downloadAttachmentChunksSessionDelegate: self, error: errorForTracker)
        }
        
    }

    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        
        // This delegate method is typically called when all tasks have been completed while the App was in the background.
        // It does not seem to be called when the tasks were completed while the app was in the foreground. In that case,
        // `func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?)` is called.

        guard let tracker = self.tracker else { return }
        let attachmentId = self.attachmentId

        os_log("📄 urlSession Did Finish Events for attachment %{public}@ within the delegate with UID %{public}@", log: Self.log, type: .info, attachmentId.debugDescription, self.uuid.uuidString)
                
        Task {
            await tracker.downloadAttachmentChunksSessionDidBecomeInvalid(downloadAttachmentChunksSessionDelegate: self, error: errorForTracker)
            if let sessionIdentifier = session.configuration.identifier {
                await tracker.urlSessionDidFinishEventsForSessionWithIdentifier(downloadAttachmentChunksSessionDelegate: self, urlSessionIdentifier: sessionIdentifier)
            } else {
                assertionFailure()
                os_log("No session identifier could be found for attachment %{public}@", log: Self.log, type: .error, attachmentId.debugDescription)
            }
        }

    }

}


// MARK: - URLSessionTaskDelegate

extension DownloadAttachmentChunksSessionDelegate: URLSessionDownloadDelegate {
    
    /// ``URLSessionDownloadDelegate`` method called each time some progress is made for a chunk. This method only calls the tracker so that it can update its in-memory progress.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let tracker = self.tracker else { return }
        guard let chunkNumber = downloadTask.getAssociatedChunkNumber() else { return }
        let chunkProgress = (chunkNumber, totalBytesWritten, totalBytesExpectedToWrite)
        Task {
            await tracker.attachmentChunkDidProgress(downloadAttachmentChunksSessionDelegate: self, chunkProgress: chunkProgress)
        }
    }

    
    /// Called each time an encrypted chunk download task is finished. After a few checks, we decrypt the chunk, write it to the attachment file, and update the associated ``InboxAttachment``.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        
        os_log("📄 Call to urlSession(_:downloadTask:didFinishDownloadingTo:)", log: Self.log, type: .info)

        guard let chunkNumber = downloadTask.getAssociatedChunkNumber() else {
            os_log("Could not recover attachmentId from the task", log: Self.log, type: .fault)
            self.errorForTracker = .couldNotRecoverAttachmentIdFromTask
            return
        }

        os_log("The upload task %d for the chunk %{public}@/%d did complete with no error within flow %{public}@", log: Self.log, type: .info, downloadTask.taskIdentifier, attachmentId.debugDescription, chunkNumber, flowId.debugDescription)

        guard let httpURLResponse = downloadTask.response as? HTTPURLResponse else {
            os_log("Could not retrieve the HTTP response for chunk %{public}@/%d", log: Self.log, type: .fault, attachmentId.debugDescription, chunkNumber)
            self.errorForTracker = .couldNotRetrieveAnHTTPResponse
            return
        }
        
        os_log("The http status code is %{public}d", log: Self.log, type: .info, httpURLResponse.statusCode)

        guard httpURLResponse.statusCode == 200 else {
            // An error occured
            switch httpURLResponse.statusCode {
            case 400:
                os_log("The server reported an error %{public}d for the private URL for a chunk of attachment %{public}@. We ask for new private URLs", log: Self.log, type: .info, httpURLResponse.statusCode, attachmentId.debugDescription)
                self.errorForTracker = .atLeastOneChunkDownloadPrivateURLHasExpired
            case 403:
                os_log("The server reported that the private URL for a chunk of attachment %{public}@ has expired. We should ask for new private URLs", log: Self.log, type: .info, attachmentId.debugDescription)
                self.errorForTracker = .atLeastOneChunkDownloadPrivateURLHasExpired
            case 404:
                os_log("The server reported that the chunk is not yet available on server.", log: Self.log, type: .info)
                self.errorForTracker = .atLeastOneChunkIsNotYetAvailableOnServer
            default:
                os_log("The error status code is not supported. Error code is %{public}d", log: Self.log, type: .fault, httpURLResponse.statusCode)
                logRequestURLInTask(downloadTask, to: Self.log)
                self.errorForTracker = .unsupportedHTTPErrorStatusCode
            }
            return
        }

        // If we reach this point, the download task successsfully downloaded its associated encrypted chunk
        
        let cleartextChunkLengths = self.cleartextChunkLengths
        let cleartextAttachmentURL = self.decryptedAttachmentURL
        let decryptionKey = self.decryptionKey
        
        let decryptAndWriteOp = DecryptChunkAndWriteToFileOperation(
            chunkNumber: chunkNumber,
            encryptedChunkURL: location,
            cleartextChunkLengths: cleartextChunkLengths,
            cleartextAttachmentURL: cleartextAttachmentURL,
            decryptionKey: decryptionKey)
        queueForDecryptingChunks.addOperations([decryptAndWriteOp], waitUntilFinished: true)

        Task {
                        
            guard decryptAndWriteOp.isFinished && !decryptAndWriteOp.isCancelled else {
                assertionFailure()
                self.errorForTracker = .failedToDecryptChunkOrWriteToFile
                return
            }
            
            let op1 = MarkChunkAsWrittenToAttachmentFileOperation(attachmentId: attachmentId, chunkNumber: chunkNumber)
            let composedOp = try createCompositionOfOneContextualOperation(op1: op1, flowId: flowId)
            await queueSharedAmongCoordinators.addAndAwaitOperation(composedOp)
         
            guard composedOp.isFinished && !composedOp.isCancelled else {
                assertionFailure()
                self.errorForTracker = .markChunkAsWrittenToAttachmentFileOperationFailed
                return
            }

            await tracker?.attachmentChunkWasDecryptedAndWrittenToAttachmentFile(downloadAttachmentChunksSessionDelegate: self, chunkNumber: chunkNumber)
            if op1.attachmentIsDownloaded {
                os_log("⛑ Attachment %{public}@ is now fully downoalded within flow %{public}@", log: Self.log, type: .info, attachmentId.debugDescription, flowId.debugDescription)
                await tracker?.attachmentDownloadIsComplete(downloadAttachmentChunksSessionDelegate: self)
            } else {
                os_log("⛑ Attachment %{public}@ is not fully downoalded within flow %{public}@. Still waiting for more chunks.", log: Self.log, type: .info, attachmentId.debugDescription, flowId.debugDescription)
            }

        }
    }

    
    enum ObvError: Error {
        case unexpectedChunkNumber
        case contextCreatorIsNil
    }
    
}


// MARK: - Helpers

extension DownloadAttachmentChunksSessionDelegate {
    
    private func logRequestURLInTask(_ task: URLSessionDownloadTask, to log: OSLog) {
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


// MARK: - Helpers

extension DownloadAttachmentChunksSessionDelegate {
    
    /// This struct simulates an ObvContextCreator, which is usually implemented using a Core Data context creator. In our very particular case, we are implementing an URLSessionDelegate and we cannot have strong pointers to other instances (since the URLSession keeps a strong pointer to this delegate).
    /// The strategy is to create a context in advance and pass it to this class during initialization. We embed this context in this struct, so as to make it possible to call a ``createCompositionOfOneContextualOperation`` method as usual.
    private struct ContextProviderForDownloadAttachmentChunksSessionDelegate: ObvContextCreator {
        
        let obvContext: ObvContext
        let viewContext: NSManagedObjectContext

        func newBackgroundContext(flowId: FlowIdentifier, file: StaticString, line: Int, function: StaticString) -> ObvContext {
            obvContext.performAndWait {
                obvContext.refreshAllObjects()
            }
            return obvContext
        }
        
    }

    private func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>, flowId: FlowIdentifier) throws -> CompositionOfOneContextualOperation<T> {

        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: contextProvider, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: flowId)

        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp

    }
    
}


// MARK: - Extending URLSessionTask for storing chunk numbers within the description

extension URLSessionDownloadTask {
    
    func getAssociatedChunkNumber() -> Int? {
        guard let taskDescription = self.taskDescription else { return nil }
        return Int(taskDescription)
    }
    
    func setAssociatedChunkNumber(_ chunkNumber: Int) {
        self.taskDescription = "\(chunkNumber)"
    }
}
