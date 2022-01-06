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
import ObvTypes
import ObvMetaManager
import os.log
import OlvidUtils

final class FinalizePostAttachmentUploadRequestOperation: Operation {
    
    enum ReasonForCancel: Int {
        case attachmentWasAlreadyAcknowledged = 0
        case messageNotUploadedYet
        case cancelExternallyRequested
        case noSignedURLAvailable
        case failedToCreateOutboxAttachmentSession
        case failedToCreateAnUploadTask
        case couldNotWriteEncryptedChunkToFile
        case cannotFindEncryptedChunkURL
        case cannotFindEncryptedChunkAtURL
        case couldNotSaveContext
        case contextCreatorIsNotSet
        case identityDelegateIsNotSet
        case cannotFindMessageOrAttachmentInDatabase
        case invalidChunkNumberWasRequested
        case couldNotReadCleartextChunk
        case attachmentFileCannotBeRead
        case cannotDetermineReasonForCancel
        case fileDoesNotExistAnymore
        
        fileprivate var index: Int { return self.rawValue }
        
    }

    private let uuid = UUID()
    private let attachmentId: AttachmentIdentifier
    private let flowId: FlowIdentifier
    private let log: OSLog
    private let logCategory = String(describing: FinalizePostAttachmentUploadRequestOperation.self)
    private weak var notificationDelegate: ObvNotificationDelegate?
    
    private weak var delegate: FinalizePostAttachmentUploadRequestOperationDelegate?
        
    init(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier, logSubsystem: String, notificationDelegate: ObvNotificationDelegate, delegate: FinalizePostAttachmentUploadRequestOperationDelegate) {
        self.attachmentId = attachmentId
        self.flowId = flowId
        self.notificationDelegate = notificationDelegate
        self.delegate = delegate
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        super.init()
    }
    
    override func main() {        
        // Find the session and invalidate it
        guard let sessionOp = dependencies.filter({ $0 is ReCreateURLSessionWithNewDelegateForAttachmentUploadOperation }).first as? ReCreateURLSessionWithNewDelegateForAttachmentUploadOperation else {
            assertionFailure()
            os_log("Could not find ReCreateURLSessionWithNewDelegateForAttachmentUploadOperation so we cannot invalidate the session", log: log, type: .fault)
            return
        }
        
        let urlSession: URLSession?
        if let _urlSession = sessionOp.urlSession {
            os_log("Calling finishTasksAndInvalidate on the session for uploading %{public}@", log: log, type: .info, attachmentId.debugDescription)
            _urlSession.finishTasksAndInvalidate()
            urlSession = _urlSession
        } else {
            urlSession = nil
        }

        let delegate = self.delegate
        let flowId = self.flowId
        let attachmentId = self.attachmentId

        let cancelledOperations = dependencies.filter { $0.isCancelled }
        guard cancelledOperations.isEmpty else {
            let reason = processReasonsForCancel(in: cancelledOperations) ?? ReasonForCancel.cannotDetermineReasonForCancel
            DispatchQueue(label: "Queue for calling postAttachmentUploadRequestOperationsAreFinished").async {
                delegate?.postAttachmentUploadRequestOperationsAreFinished(attachmentId: attachmentId, urlSession: urlSession, flowId: flowId, error: reason)
            }
            return
        }
        
        DispatchQueue(label: "Queue for calling postAttachmentUploadRequestOperationsAreFinished").async {
            delegate?.postAttachmentUploadRequestOperationsAreFinished(attachmentId: attachmentId, urlSession: urlSession, flowId: flowId, error: nil)
        }
        
    }
    
    
    private func processReasonsForCancel(in cancelledOperations: [Operation]) -> ReasonForCancel? {
        
        var reasonsForCancel = Set<ReasonForCancel>()
        
        for op in cancelledOperations {
            if let op = op as? ReCreateURLSessionWithNewDelegateForAttachmentUploadOperation {
                guard let reasonForCancel = op.reasonForCancel else {
                    os_log("Operation %{public}@ is cancelled but has no reason for cancel", log: log, type: .fault, op.debugDescription)
                    assertionFailure()
                    continue
                }
                reasonsForCancel.insert(map(reasonForCancel: reasonForCancel))
            } else if let op = op as? EncryptAttachmentChunkOperation {
                guard let reasonForCancel = op.reasonForCancel else {
                    os_log("Operation %{public}@ is cancelled but has no reason for cancel", log: log, type: .fault, op.debugDescription)
                    assertionFailure()
                    continue
                }
                reasonsForCancel.insert(map(reasonForCancel: reasonForCancel))
            } else if let op = op as? ResumeEncryptedChunkUploadTaskIfRequiredOperation {
                guard let reasonForCancel = op.reasonForCancel else {
                    os_log("Operation %{public}@ is cancelled but has no reason for cancel", log: log, type: .fault, op.debugDescription)
                    assertionFailure()
                    continue
                }
                if let reason = map(reasonForCancel: reasonForCancel) {
                    reasonsForCancel.insert(reason)
                }
            } else {
                os_log("Unknown operation type: %{public}@", log: log, type: .fault, op.debugDescription)
                assertionFailure()
            }
            
        }
        
        return reasonsForCancel.sorted { $0.index < $1.index }.first
    }
    
    private func map(reasonForCancel: ReCreateURLSessionWithNewDelegateForAttachmentUploadOperation.ReasonForCancel) -> ReasonForCancel {
        switch reasonForCancel {
        case .contextCreatorIsNotSet:
            return .contextCreatorIsNotSet
        case .cannotFindAttachmentInDatabase,
             .cannotFindMessageInDatabase:
            return .cannotFindMessageOrAttachmentInDatabase
        case .messageNotUploadedYet:
            return .messageNotUploadedYet
        case .attachmentWasAlreadyAcknowledged:
            return .attachmentWasAlreadyAcknowledged
        case .cancelExternallyRequested:
            return .cancelExternallyRequested
        case .failedToCreateOutboxAttachmentSession:
            return .failedToCreateOutboxAttachmentSession
        case .couldNotSaveContext:
            return .couldNotSaveContext
        }
    }
    
    private func map(reasonForCancel: EncryptAttachmentChunkOperation.ReasonForCancel) -> ReasonForCancel {
        switch reasonForCancel {
        case .contextCreatorIsNotSet:
            return .contextCreatorIsNotSet
        case .chunkNumberDoesNotExist:
            return .invalidChunkNumberWasRequested
        case .cannotFindAttachmentInDatabase:
            return .cannotFindMessageOrAttachmentInDatabase
        case .couldNotReadCleartextChunk:
            return .couldNotReadCleartextChunk
        case .couldNotWriteEncryptedChunkToFile:
            return .couldNotWriteEncryptedChunkToFile
        case .attachmentFileCannotBeRead:
            return .attachmentFileCannotBeRead
        case .couldNotSaveContext:
            return .couldNotSaveContext
        case .fileDoesNotExistAnymore:
            return .fileDoesNotExistAnymore
        }
    }
    
    private func map(reasonForCancel: ResumeEncryptedChunkUploadTaskIfRequiredOperation.ReasonForCancel) -> ReasonForCancel? {
        switch reasonForCancel {
        case .contextCreatorIsNotSet:
            return .contextCreatorIsNotSet
        case .identityDelegateIsNotSet:
            return .identityDelegateIsNotSet
        case .cannotFindAttachmentInDatabase:
            return .cannotFindMessageOrAttachmentInDatabase
        case .missingRequiredDependency:
            assertionFailure()
            return nil
        case .cancelledDependency:
            return nil
        case .dependencyDoesNotProvideExpectedInformations:
            return nil
        case .failedToCreateTask:
            return .failedToCreateAnUploadTask
        case .cannotFindEncryptedChunkURL:
            return .cannotFindEncryptedChunkURL
        case .cannotFindEncryptedChunkAtURL:
            return .cannotFindEncryptedChunkAtURL
        case .noSignedURLAvailable:
            return .noSignedURLAvailable
        }
    }
    
}


protocol FinalizePostAttachmentUploadRequestOperationDelegate: AnyObject {
    
    func postAttachmentUploadRequestOperationsAreFinished(attachmentId: AttachmentIdentifier, urlSession: URLSession?, flowId: FlowIdentifier, error: FinalizePostAttachmentUploadRequestOperation.ReasonForCancel?)
    
}
