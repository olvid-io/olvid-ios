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
import CoreData
import ObvTypes
import ObvServerInterface
import OlvidUtils


final class ResumeTaskForGettingAttachmentSignedURLsOperation: Operation {
    
    enum ReasonForCancel {
        case unexpectedDependencies
        case cannotFindAttachmentInDatabase
        case aDependencyCancelled
        case nonNilSignedURLWasFound
        case cannotFindMessageInDatabase
        case messageUidFromServerIsNotSet
        case identityDelegateNotSet
        case attachmentChunksSignedURLsTrackerNotSet
        case failedToCreateTask(error: Error)
    }

    private let uuid = UUID()
    private let attachmentId: AttachmentIdentifier
    private let logSubsystem: String
    private let log: OSLog
    private let obvContext: ObvContext
    private let appType: AppType
    private let logCategory = String(describing: ResumeTaskForGettingAttachmentSignedURLsOperation.self)
    private weak var identityDelegate: ObvIdentityDelegate?
    private weak var attachmentChunksSignedURLsTracker: AttachmentChunksSignedURLsTracker?
    private weak var delegate: FinalizeSignedURLsOperationsDelegate?
    
    private var flowId: FlowIdentifier { obvContext.flowId }
    
    private(set) var reasonForCancel: ReasonForCancel?

    init(attachmentId: AttachmentIdentifier, logSubsystem: String, obvContext: ObvContext, identityDelegate: ObvIdentityDelegate, attachmentChunksSignedURLsTracker: AttachmentChunksSignedURLsTracker, appType: AppType, delegate: FinalizeSignedURLsOperationsDelegate) {
        self.attachmentId = attachmentId
        self.logSubsystem = logSubsystem
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.obvContext = obvContext
        self.identityDelegate = identityDelegate
        self.attachmentChunksSignedURLsTracker = attachmentChunksSignedURLsTracker
        self.appType = appType
        self.delegate = delegate
        super.init()
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
            DispatchQueue(label: "Queue for calling signedURLsOperationsAreFinished").async {
                delegate?.signedURLsOperationsAreFinished(attachmentId: attachmentId, flowId: flowId, error: reasonForCancel)
            }
        }
        
        guard let identityDelegate = self.identityDelegate else {
            return cancel(withReason: .identityDelegateNotSet)
        }
        
        guard let attachmentChunksSignedURLsTracker = self.attachmentChunksSignedURLsTracker else {
            return cancel(withReason: .attachmentChunksSignedURLsTrackerNotSet)
        }
        
        // Check that no dependency cancelled
        guard let deleteURLsOp = self.filterDependencies() else {
            return cancel(withReason: .unexpectedDependencies)
        }
        guard !deleteURLsOp.isCancelled else {
            return cancel(withReason: .aDependencyCancelled)
        }
        
        obvContext.performAndWait {
            
            guard let attachment = try? OutboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                return cancel(withReason: .cannotFindAttachmentInDatabase)
            }

            let allSignedURLsAreNil = attachment.chunks.allSatisfy({ $0.signedURL == nil })
            guard allSignedURLsAreNil else {
                return cancel(withReason: .nonNilSignedURLWasFound)
            }
            
            guard let message = attachment.message else {
                os_log("Could not find message associated to attachment, unexpected", log: log, type: .fault)
                assertionFailure()
                return cancel(withReason: .cannotFindMessageInDatabase)
            }

            guard let messageUidFromServer = message.messageUidFromServer, let nonceFromServer = message.nonceFromServer else {
                return cancel(withReason: .messageUidFromServerIsNotSet)
            }
            
            guard let messageId = message.messageId else {
                // This happens if the message has just been deleted
                return cancel(withReason: .cannotFindMessageInDatabase)
            }

            let serverURL = message.serverURL
            
            // Create a new session
            let sessionDelegate = GetSignedURLsSessionDelegate(attachmentId: attachmentId,
                                                               obvContext: obvContext,
                                                               appType: appType,
                                                               logSubsystem: logSubsystem,
                                                               attachmentChunksSignedURLsTracker: attachmentChunksSignedURLsTracker)
            let sessionConfiguration = URLSessionConfiguration.ephemeral
            sessionConfiguration.useOlvidSettings(sharedContainerIdentifier: nil)
            let session = URLSession(configuration: sessionConfiguration, delegate: sessionDelegate, delegateQueue: nil)
            defer {
                session.finishTasksAndInvalidate()
            }

            // Create a method
            let method = ObvServerUploadPrivateURLsForAttachmentChunksMethod(ownedIdentity: messageId.ownedCryptoIdentity,
                                                                             serverURL: serverURL,
                                                                             messageUidFromServer: messageUidFromServer,
                                                                             attachmentNumber: attachmentId.attachmentNumber,
                                                                             nonceFromServer: nonceFromServer,
                                                                             expectedChunkCount: attachment.chunks.count,
                                                                             flowId: flowId)
            method.identityDelegate = identityDelegate
            
            let task: URLSessionDataTask
            do {
                task = try method.dataTask(within: session)
            } catch let error {
                return cancel(withReason: .failedToCreateTask(error: error))
            }
            task.resume()

        }
        
    }
    
}


// MARK: - Helpers

extension ResumeTaskForGettingAttachmentSignedURLsOperation {
    
    private func filterDependencies() -> DeletePreviousAttachmentSignedURLsOperation? {
        guard dependencies.count == 1 else { return nil }
        return dependencies.first as? DeletePreviousAttachmentSignedURLsOperation
    }
    
}

protocol FinalizeSignedURLsOperationsDelegate: AnyObject {
    
    func signedURLsOperationsAreFinished(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier, error: ResumeTaskForGettingAttachmentSignedURLsOperation.ReasonForCancel?)
    
}
