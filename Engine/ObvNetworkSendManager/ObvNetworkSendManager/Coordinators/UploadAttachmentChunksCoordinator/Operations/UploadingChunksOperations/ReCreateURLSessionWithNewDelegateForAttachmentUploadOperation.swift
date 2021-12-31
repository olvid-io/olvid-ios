/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


final class ReCreateURLSessionWithNewDelegateForAttachmentUploadOperation: Operation {

    enum ReasonForCancel: Hashable {
        case contextCreatorIsNotSet
        case cannotFindAttachmentInDatabase
        case cannotFindMessageInDatabase
        case messageNotUploadedYet
        case attachmentWasAlreadyAcknowledged
        case cancelExternallyRequested
        case failedToCreateOutboxAttachmentSession
        case couldNotSaveContext
    }

    private let uuid = UUID()
    private let attachmentId: AttachmentIdentifier
    private let appType: AppType
    private let logSubsystem: String
    private let log: OSLog
    private let flowId: FlowIdentifier
    private let sharedContainerIdentifier: String
    private let logCategory = String(describing: ReCreateURLSessionWithNewDelegateForAttachmentUploadOperation.self)

    private weak var contextCreator: ObvCreateContextDelegate?
    private weak var attachmentChunkUploadProgressTracker: AttachmentChunkUploadProgressTracker?

    private(set) var reasonForCancel: ReasonForCancel?
    private(set) var urlSession: URLSession?

    init(attachmentId: AttachmentIdentifier, appType: AppType, sharedContainerIdentifier: String, logSubsystem: String, flowId: FlowIdentifier, contextCreator: ObvCreateContextDelegate, attachmentChunkUploadProgressTracker: AttachmentChunkUploadProgressTracker) {
        self.attachmentId = attachmentId
        self.flowId = flowId
        self.appType = appType
        self.logSubsystem = logSubsystem
        self.sharedContainerIdentifier = sharedContainerIdentifier
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.contextCreator = contextCreator
        self.attachmentChunkUploadProgressTracker = attachmentChunkUploadProgressTracker
        super.init()
        os_log("ReCreateURLSessionWithNewDelegateForAttachmentUploadOperation %{public}@ was initialized", log: log, type: .info, uuid.description)
    }

    deinit {
        os_log("ReCreateURLSessionWithNewDelegateForAttachmentUploadOperation %{public}@ is deinitialized", log: log, type: .info, uuid.description)
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
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            guard let attachment = OutboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                return cancel(withReason: .cannotFindAttachmentInDatabase)
            }

            guard let message = attachment.message else {
                os_log("Message cannot be found", log: log, type: .fault)
                assertionFailure()
                return cancel(withReason: .cannotFindMessageInDatabase)
            }
            
            guard message.uploaded, message.messageUidFromServer != nil else {
                os_log("Message %{public}@ needs to be uploaded", log: log, type: .error, attachmentId.messageId.debugDescription)
                return cancel(withReason: .messageNotUploadedYet)
            }

            guard !attachment.acknowledged else {
                os_log("Attachment %{public}@ was already acknowledged", log: log, type: .debug, attachmentId.debugDescription)
                return cancel(withReason: .attachmentWasAlreadyAcknowledged)
            }
            
            guard !attachment.cancelExternallyRequested else {
                os_log("Attachment %{public}@ was cancelled", log: log, type: .debug, attachmentId.debugDescription)
                return cancel(withReason: .cancelExternallyRequested)
            }
            
            let outboxAttachmentSession: OutboxAttachmentSession
            if let existingSession = attachment.session {
                outboxAttachmentSession = existingSession
            } else {
                os_log("No OutboxAttachmentSession exists for attachment %{public}@. We create one with a new session identifier.", log: log, type: .info, attachment.attachmentId.debugDescription)
                guard let newOutboxAttachmentSession = attachment.createSession(appType: appType) else {
                    return cancel(withReason: .failedToCreateOutboxAttachmentSession)
                }
                outboxAttachmentSession = newOutboxAttachmentSession
            }
            
            let sendSessionDelegate = UploadAttachmentChunksSessionDelegate(attachmentId: attachmentId,
                                                                            obvContext: obvContext,
                                                                            appType: appType,
                                                                            logSubsystem: logSubsystem)
            sendSessionDelegate.tracker = attachmentChunkUploadProgressTracker
            
            let sessionConfiguration = URLSessionConfiguration.background(withIdentifier: outboxAttachmentSession.sessionIdentifier)
            sessionConfiguration.useOlvidSettings(sharedContainerIdentifier: sharedContainerIdentifier)
            
            self.urlSession = URLSession(configuration: sessionConfiguration,
                                         delegate: sendSessionDelegate,
                                         delegateQueue: nil)
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not write new OutboxAttachmentSession to DB", log: log, type: .fault)
                self.urlSession?.invalidateAndCancel()
                self.urlSession = nil
                return cancel(withReason: .couldNotSaveContext)
            }

        }
        
    }
}
