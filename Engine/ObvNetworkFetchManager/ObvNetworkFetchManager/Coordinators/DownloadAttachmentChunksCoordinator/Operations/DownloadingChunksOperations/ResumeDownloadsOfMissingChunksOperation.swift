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
import ObvTypes
import ObvMetaManager
import ObvServerInterface
import OlvidUtils

final class ResumeDownloadsOfMissingChunksOperation: Operation {
    
    enum ReasonForCancel: Hashable {
        case contextCreatorIsNotSet
        case identityDelegateIsNotSet
        case cannotFindAttachmentInDatabase
        case missingRequiredDependency
        case cancelledDependency
        case dependencyDoesNotProvideExpectedInformations
        case failedToCreateTask
        case coreDataFailure
        case allChunksAreAlreadyDownloaded
        case atLeastOneChunkHasNoSignedURL
    }
    
    private let uuid = UUID()
    private let logSubsystem: String
    private let log: OSLog
    private let flowId: FlowIdentifier
    private let logCategory = String(describing: ResumeDownloadsOfMissingChunksOperation.self)
    private let attachmentId: ObvAttachmentIdentifier
    private(set) var urlSession: URLSession?
    
    private weak var contextCreator: ObvCreateContextDelegate?
    private weak var identityDelegate: ObvIdentityDelegate?
    private weak var delegate: FinalizeDownloadChunksOperationsDelegate?

    private(set) var reasonForCancel: ReasonForCancel?
    
    init(attachmentId: ObvAttachmentIdentifier, logSubsystem: String, flowId: FlowIdentifier, contextCreator: ObvCreateContextDelegate, identityDelegate: ObvIdentityDelegate, delegate: FinalizeDownloadChunksOperationsDelegate) {
        self.flowId = flowId
        self.logSubsystem = logSubsystem
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.attachmentId = attachmentId
        self.contextCreator = contextCreator
        self.identityDelegate = identityDelegate
        self.delegate = delegate
        super.init()
        os_log("ResumeDownloadsOfMissingChunksOperation %{public}@ was initialized", log: log, type: .info, uuid.description)
    }
    
    deinit {
        os_log("ResumeDownloadsOfMissingChunksOperation %{public}@ is deinitialized", log: log, type: .info, uuid.description)
    }
    
    private func cancel(withReason reason: ReasonForCancel) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
    }
    
    override func main() {
        defer {
            let delegate = self.delegate
            let attachmentId = self.attachmentId
            let flowId = self.flowId
            let reasonForCancel = self.reasonForCancel
            let urlSession = self.urlSession
            DispatchQueue(label: "Queue for calling signedURLsOperationsAreFinished").async {
                assert(delegate != nil)
                delegate?.downloadChunksOperationsAreFinished(attachmentId: attachmentId, urlSession: urlSession, flowId: flowId, error: reasonForCancel)
            }
        }
        
        guard let contextCreator = self.contextCreator else {
            assertionFailure()
            cancel(withReason: .contextCreatorIsNotSet)
            return
        }
        
        guard let identityDelegate = self.identityDelegate else {
            assertionFailure()
            cancel(withReason: .identityDelegateIsNotSet)
            return
        }
        
        guard let reCreateURLSessionWithNewDelegateForAttachmentDownloadOperation = filterDependencies() else {
            return cancel(withReason: .missingRequiredDependency)
        }
        
        guard !reCreateURLSessionWithNewDelegateForAttachmentDownloadOperation.isCancelled else {
            return cancel(withReason: .cancelledDependency)
        }
        
        guard let urlSession = reCreateURLSessionWithNewDelegateForAttachmentDownloadOperation.urlSession, self.attachmentId == reCreateURLSessionWithNewDelegateForAttachmentDownloadOperation.attachmentId else {
            return cancel(withReason: .dependencyDoesNotProvideExpectedInformations)
        }
        self.urlSession = urlSession
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            let chunks: [InboxAttachmentChunk]
            do {
                chunks = try InboxAttachmentChunk.getAllMissingAttachmentChunks(ofAttachmentId: attachmentId, within: obvContext)
            } catch {
                os_log("Failed to get inbox attachment chunks: %{public}@", log: log, type: .fault, error.localizedDescription)
                return cancel(withReason: .coreDataFailure)
            }

            guard !chunks.isEmpty else {
                // All chunks are acknowledged. Mark the attachment as downloaded and cancel.
                do {
                    let attachment = try InboxAttachment.get(attachmentId: attachmentId, within: obvContext)
                    try attachment?.tryChangeStatusToDownloaded()
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not change status of attachment to downloaded: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                }
                return cancel(withReason: .allChunksAreAlreadyDownloaded)
            }
            
            let chunkNumbersAndSignedURLs: [(chunkNumber: Int, signedURL: URL)] = chunks.compactMap({
                guard let signedURL = $0.signedURL else { return nil }
                return ($0.chunkNumber, signedURL)
            })
            
            guard chunkNumbersAndSignedURLs.count == chunks.count else {
                return cancel(withReason: .atLeastOneChunkHasNoSignedURL)
            }
            
            let tasks: [URLSessionDownloadTask] = chunkNumbersAndSignedURLs.compactMap({
                let method = ObvS3DownloadAttachmentChunkMethod(attachmentId: attachmentId,
                                                                chunkNumber: $0.chunkNumber,
                                                                signedURL: $0.signedURL,
                                                                flowId: flowId)
                method.identityDelegate = identityDelegate
                guard let task = try? method.downloadTask(within: urlSession) else { return nil }
                task.setAssociatedChunkNumber($0.chunkNumber)
                return task
            })

            guard tasks.count == chunks.count else {
                return cancel(withReason: .failedToCreateTask)
            }
            
            for task in tasks {
                task.resume()
            }

            urlSession.finishTasksAndInvalidate()
            
            os_log("⛑ %{public}d download tasks were resumed for downloading chunks of attachment %{public}@", log: log, type: .info, tasks.count, attachmentId.debugDescription)
            
        }
        
    }
    
}

// MARK: - Helper

extension ResumeDownloadsOfMissingChunksOperation {
    
    private func filterDependencies() -> ReCreateURLSessionWithNewDelegateForAttachmentDownloadOperation? {
        guard dependencies.count == 1 else { return nil }
        guard let op = dependencies.first(where: { $0 is ReCreateURLSessionWithNewDelegateForAttachmentDownloadOperation }) as? ReCreateURLSessionWithNewDelegateForAttachmentDownloadOperation else { return nil }
        return op
    }
    
}

protocol FinalizeDownloadChunksOperationsDelegate: AnyObject {
    
    func downloadChunksOperationsAreFinished(attachmentId: ObvAttachmentIdentifier, urlSession: URLSession?, flowId: FlowIdentifier, error: ResumeDownloadsOfMissingChunksOperation.ReasonForCancel?)
    
}
