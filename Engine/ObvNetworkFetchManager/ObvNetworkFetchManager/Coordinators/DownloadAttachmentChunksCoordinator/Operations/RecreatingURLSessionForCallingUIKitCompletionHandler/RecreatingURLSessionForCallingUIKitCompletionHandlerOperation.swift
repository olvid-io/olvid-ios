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


final class RecreatingURLSessionForCallingUIKitCompletionHandlerOperation: Operation {
    
    enum ReasonForCancel: Hashable {
        case contextCreatorIsNotSet
        case couldNotFindOutboxAttachmentSessionInDatabase
        case cannotFindAttachmentInDatabase
    }
    
    private let uuid = UUID()
    private let urlSessionIdentifier: String
    private let flowId: FlowIdentifier
    private let log: OSLog
    private let logSubsystem: String
    private let logCategory = String(describing: RecreatingURLSessionForCallingUIKitCompletionHandlerOperation.self)
    private let inbox: URL

    private weak var contextCreator: ObvCreateContextDelegate?
    private weak var attachmentChunkDownloadProgressTracker: AttachmentChunkDownloadProgressTracker?

    private(set) var reasonForCancel: ReasonForCancel?

    init(urlSessionIdentifier: String, logSubsystem: String, flowId: FlowIdentifier, inbox: URL, contextCreator: ObvCreateContextDelegate, attachmentChunkDownloadProgressTracker: AttachmentChunkDownloadProgressTracker) {
        self.urlSessionIdentifier = urlSessionIdentifier
        self.flowId = flowId
        self.logSubsystem = logSubsystem
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.inbox = inbox
        self.contextCreator = contextCreator
        self.attachmentChunkDownloadProgressTracker = attachmentChunkDownloadProgressTracker
        super.init()
    }

    deinit {
        os_log("RecreatingURLSessionForCallingUIKitCompletionHandlerOperation %{public}@ is deinitialized", log: log, type: .info, uuid.description)
    }

    private func cancel(withReason reason: ReasonForCancel) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
    }

    
    override func main() {
        
        os_log("👑 Starting RecreatingURLSessionForCallingUIKitCompletionHandlerOperation %{public}@", log: log, type: .info, uuid.description)
        defer {
            os_log("👑 Ending RecreatingURLSessionForCallingUIKitCompletionHandlerOperation %{public}@ isCancelled: %{public}d", log: log, type: .info, uuid.description, isCancelled)
        }

        guard let contextCreator = self.contextCreator else {
            assertionFailure()
            cancel(withReason: .contextCreatorIsNotSet)
            return
        }
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            let attachmentSession: InboxAttachmentSession
            do {
                let _attachmentSession = try InboxAttachmentSession.getWithSessionIdentifier(urlSessionIdentifier, within: obvContext)
                guard _attachmentSession != nil else { throw NSError() }
                attachmentSession = _attachmentSession!
            } catch {
                os_log("Could not find any OutboxAttachmentSession for the given session identifier. Callin the completion handler now.", log: log, type: .error)
                return cancel(withReason: .couldNotFindOutboxAttachmentSessionInDatabase)
            }

            guard let attachment = attachmentSession.attachment else {
                return cancel(withReason: .cannotFindAttachmentInDatabase)
            }

            let attachmentId = attachment.attachmentId

            let sessionDelegate = DownloadAttachmentChunksSessionDelegate(attachmentId: attachmentId,
                                                                          obvContext: obvContext,
                                                                          logSubsystem: logSubsystem,
                                                                          inbox: inbox)
            sessionDelegate.tracker = attachmentChunkDownloadProgressTracker
            os_log("👑 The delegate created for calling the UIKit handler has the following UID: %{public}@", log: log, type: .info, sessionDelegate.uuid.uuidString)

            let sessionConfiguration = URLSessionConfiguration.background(withIdentifier: urlSessionIdentifier)
            sessionConfiguration.waitsForConnectivity = true
            sessionConfiguration.isDiscretionary = false
            sessionConfiguration.allowsCellularAccess = true
            sessionConfiguration.sessionSendsLaunchEvents = true
            sessionConfiguration.shouldUseExtendedBackgroundIdleMode = true
            sessionConfiguration.allowsConstrainedNetworkAccess = true
            sessionConfiguration.allowsExpensiveNetworkAccess = true

            _ = URLSession(configuration: sessionConfiguration,
                           delegate: sessionDelegate,
                           delegateQueue: nil)
            
        }
        
    }
}
