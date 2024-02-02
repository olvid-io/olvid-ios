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
import CoreData
import OlvidUtils


final class ReCreateURLSessionWithNewDelegateForAttachmentDownloadOperation: Operation {
    
    enum ReasonForCancel {
        case contextCreatorIsNotSet
        case cannotFindAttachmentInDatabase
        case coreDataFailure
        case attachmentCannotBeDownloadedYet
        case attachmentIsAlreadyDownloaded
        case resumeNotRequested
        case failedToCreateInboxAttachmentSession
        case couldNotSaveContext
    }
    
    private let uuid = UUID()
    let attachmentId: ObvAttachmentIdentifier
    private let logSubsystem: String
    private let log: OSLog
    private let flowId: FlowIdentifier
    private let logCategory = String(describing: ReCreateURLSessionWithNewDelegateForAttachmentDownloadOperation.self)
    private let inbox: URL

    private weak var contextCreator: ObvCreateContextDelegate?
    private weak var attachmentChunkDownloadProgressTracker: AttachmentChunkDownloadProgressTracker?
    
    private(set) var reasonForCancel: ReasonForCancel?
    private(set) var urlSession: URLSession?

    init(attachmentId: ObvAttachmentIdentifier, logSubsystem: String, flowId: FlowIdentifier, inbox: URL, contextCreator: ObvCreateContextDelegate, attachmentChunkDownloadProgressTracker: AttachmentChunkDownloadProgressTracker) {
        self.attachmentId = attachmentId
        self.logSubsystem = logSubsystem
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.flowId = flowId
        self.inbox = inbox
        self.contextCreator = contextCreator
        self.attachmentChunkDownloadProgressTracker = attachmentChunkDownloadProgressTracker
        super.init()
        os_log("ReCreateURLSessionWithNewDelegateForAttachmentDownloadOperation %{public}@ was initialized", log: log, type: .info, uuid.description)
    }

    deinit {
        os_log("ReCreateURLSessionWithNewDelegateForAttachmentDownloadOperation %{public}@ is deinitialized", log: log, type: .info, uuid.description)
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
            
            // 2020-01-06 This was added to prevent a merge conflict
            // In case of conflict on a property, the in-memory version is kept, the store version is lost.
            obvContext.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
                        
            let attachment: InboxAttachment
            do {
                guard let _attachment = try InboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                    return cancel(withReason: .cannotFindAttachmentInDatabase)
                }
                attachment = _attachment
            } catch {
                os_log("Failed to get inbox attachment: %{public}@", log: log, type: .fault, error.localizedDescription)
                return cancel(withReason: .coreDataFailure)
            }
            
            guard !attachment.isDownloaded else {
                os_log("Attachment is already downloaded", log: log, type: .info)
                assertionFailure()
                return cancel(withReason: .attachmentIsAlreadyDownloaded)
            }
            
            guard attachment.status == .resumeRequested else {
                os_log("Attachment resume is not requested", log: log, type: .error)
                return cancel(withReason: .resumeNotRequested)
            }
            
            guard attachment.canBeDownloaded else {
                os_log("Attachment cannot be downloaded yet", log: log, type: .error)
                assertionFailure()
                return cancel(withReason: .attachmentCannotBeDownloadedYet)
            }
            
            let inboxAttachmentSession: InboxAttachmentSession
            if let existingSession = attachment.session {
                inboxAttachmentSession = existingSession
            } else {
                os_log("No OutboxAttachmentSession exists for attachment %{public}@. We create one with a new session identifier.", log: log, type: .info, attachment.attachmentId.debugDescription)
                guard let newOutboxAttachmentSession = attachment.createSession() else {
                    return cancel(withReason: .failedToCreateInboxAttachmentSession)
                }
                inboxAttachmentSession = newOutboxAttachmentSession
            }

            let sessionDelegate = DownloadAttachmentChunksSessionDelegate(attachmentId: attachmentId,
                                                                          obvContext: obvContext,
                                                                          logSubsystem: logSubsystem,
                                                                          inbox: inbox)
            sessionDelegate.tracker = attachmentChunkDownloadProgressTracker
            
            let sessionConfiguration = URLSessionConfiguration.background(withIdentifier: inboxAttachmentSession.sessionIdentifier)
            sessionConfiguration.waitsForConnectivity = true
            sessionConfiguration.isDiscretionary = false
            sessionConfiguration.allowsCellularAccess = true
            sessionConfiguration.sessionSendsLaunchEvents = true
            sessionConfiguration.shouldUseExtendedBackgroundIdleMode = true
            sessionConfiguration.allowsConstrainedNetworkAccess = true
            sessionConfiguration.allowsExpensiveNetworkAccess = true

            self.urlSession = URLSession(configuration: sessionConfiguration,
                                         delegate: sessionDelegate,
                                         delegateQueue: nil)

            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not write new InboxAttachmentSession to DB", log: log, type: .fault)
                self.urlSession?.invalidateAndCancel()
                self.urlSession = nil
                return cancel(withReason: .couldNotSaveContext)
            }

        }
        
    }
    
}
