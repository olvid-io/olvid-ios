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

final class ResumeEncryptedChunkUploadTaskIfRequiredOperation: Operation {
    
    enum ReasonForCancel: Hashable {
        case contextCreatorIsNotSet
        case identityDelegateIsNotSet
        case cannotFindAttachmentInDatabase
        case missingRequiredDependency
        case cancelledDependency
        case dependencyDoesNotProvideExpectedInformations
        case failedToCreateTask
        case cannotFindEncryptedChunkURL
        case cannotFindEncryptedChunkAtURL
        case noSignedURLAvailable
    }

    private let uuid = UUID()
    private let logSubsystem: String
    private let log: OSLog
    private let flowId: FlowIdentifier
    private let logCategory = String(describing: ResumeEncryptedChunkUploadTaskIfRequiredOperation.self)

    weak var contextCreator: ObvCreateContextDelegate?
    weak var identityDelegate: ObvIdentityDelegate?
    
    private(set) var reasonForCancel: ReasonForCancel?

    init(logSubsystem: String, flowId: FlowIdentifier, contextCreator: ObvCreateContextDelegate, identityDelegate: ObvIdentityDelegate) {
        self.flowId = flowId
        self.logSubsystem = logSubsystem
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.contextCreator = contextCreator
        self.identityDelegate = identityDelegate
        super.init()
        os_log("ResumeChunkUploadTaskOperation %{public}@ was initialized", log: log, type: .info, uuid.description)
    }
    
    deinit {
        os_log("ResumeChunkUploadTaskOperation %{public}@ is deinitialized", log: log, type: .info, uuid.description)
    }

    private func cancel(withReason reason: ReasonForCancel) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
    }

    
    override func main() {

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

        guard let (createSessionForAttachmentUploadOp, encryptAttachmentChunkOperation) = filterDependencies() else {
            return cancel(withReason: .missingRequiredDependency)
        }
        
        guard !createSessionForAttachmentUploadOp.isCancelled && !encryptAttachmentChunkOperation.isCancelled else {
            return cancel(withReason: .cancelledDependency)
        }
        
        guard let urlSession = createSessionForAttachmentUploadOp.urlSession else {
            return cancel(withReason: .dependencyDoesNotProvideExpectedInformations)
        }
        
        let attachmentId = encryptAttachmentChunkOperation.attachmentId
        let chunkNumber = encryptAttachmentChunkOperation.chunkNumber

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            guard let attachment = try? OutboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                return cancel(withReason: .cannotFindAttachmentInDatabase)
            }

            let chunk = attachment.chunks[chunkNumber]
            
            guard !chunk.isAcknowledged else {
                os_log("⛑ Chunk %{public}d of attachment %{public}@ was already acknowledged. We do not need to resume a task for it", log: log, type: .info, chunk.chunkNumber, attachmentId.debugDescription)
                return
            }
            
            guard let url = chunk.encryptedChunkURL else {
                return cancel(withReason: .cannotFindEncryptedChunkURL)
            }
            
            guard url.isFileURL && FileManager.default.isReadableFile(atPath: url.path) && url.getFileSize() == chunk.ciphertextChunkLength else {
                return cancel(withReason: .cannotFindEncryptedChunkAtURL)
            }
            
            guard let signedURL = attachment.chunks[chunkNumber].signedURL else {
                return cancel(withReason: .noSignedURLAvailable)
            }

            let method = ObvS3UploadAttachmentChunkMethod(attachmentId: attachmentId,
                                                          fileURL: url,
                                                          fileSize: chunk.ciphertextChunkLength,
                                                          chunkNumber: chunkNumber,
                                                          signedURL: signedURL,
                                                          flowId: flowId)
            method.identityDelegate = identityDelegate
            
            let task: URLSessionUploadTask
            do {
                task = try method.uploadTask(within: urlSession)
            } catch {
                return cancel(withReason: .failedToCreateTask)
            }
            task.setAssociatedChunkNumber(chunkNumber)
            task.resume()

            os_log("⛑ Upload task for Chunk %{public}d of attachment %{public}@ was resumed", log: log, type: .info, chunk.chunkNumber, attachmentId.debugDescription)

        }
    }
    
}


// MARK: - Helper

extension ResumeEncryptedChunkUploadTaskIfRequiredOperation {
    
    private func filterDependencies() -> (createSessionForAttachmentUploadOp: ReCreateURLSessionWithNewDelegateForAttachmentUploadOperation, encryptAttachmentChunkOperation: EncryptAttachmentChunkOperation)? {
        
        guard dependencies.count == 2 else { return nil }
        
        guard let op1 = dependencies.first(where: { $0 is ReCreateURLSessionWithNewDelegateForAttachmentUploadOperation }) as? ReCreateURLSessionWithNewDelegateForAttachmentUploadOperation else { return nil }
        guard let op2 = dependencies.first(where: { $0 is EncryptAttachmentChunkOperation }) as? EncryptAttachmentChunkOperation else { return nil }
        
        return (op1, op2)

    }
    
    

}


private extension URL {
    
    func getFileSize() -> Int? {
        guard FileManager.default.fileExists(atPath: self.path) else { return nil }
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: self.path) else { return nil }
        return fileAttributes[FileAttributeKey.size] as? Int
    }

    
}
