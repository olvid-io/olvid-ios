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
    private let appType: AppType
    private let logSubsystem: String
    private let urlSessionIdentifier: String
    private let log: OSLog
    private let flowId: FlowIdentifier
    private let sharedContainerIdentifier: String
    private let logCategory = String(describing: RecreatingURLSessionForCallingUIKitCompletionHandlerOperation.self)

    private weak var contextCreator: ObvCreateContextDelegate?
    private weak var attachmentChunkUploadProgressTracker: AttachmentChunkUploadProgressTracker?
    
    private(set) var reasonForCancel: ReasonForCancel?

    init(urlSessionIdentifier: String, appType: AppType, sharedContainerIdentifier: String, logSubsystem: String, flowId: FlowIdentifier, contextCreator: ObvCreateContextDelegate, attachmentChunkUploadProgressTracker: AttachmentChunkUploadProgressTracker) {
        self.appType = appType
        self.urlSessionIdentifier = urlSessionIdentifier
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.logSubsystem = logSubsystem
        self.flowId = flowId
        self.sharedContainerIdentifier = sharedContainerIdentifier
        self.contextCreator = contextCreator
        self.attachmentChunkUploadProgressTracker = attachmentChunkUploadProgressTracker
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
            os_log("👑 Ending RecreatingURLSessionForCallingUIKitCompletionHandlerOperation %{public}@ isCancelled: %{public}@", log: log, type: .info, uuid.description, isCancelled.description)
        }

        guard let contextCreator = self.contextCreator else {
            assertionFailure()
            cancel(withReason: .contextCreatorIsNotSet)
            return
        }

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in

            let attachmentSession: OutboxAttachmentSession
            do {
                let _attachmentSession = try OutboxAttachmentSession.getWithSessionIdentifier(urlSessionIdentifier, within: obvContext)
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
            
            let sendSessionDelegate = UploadAttachmentChunksSessionDelegate(attachmentId: attachmentId,
                                                                            obvContext: obvContext,
                                                                            appType: appType,
                                                                            logSubsystem: logSubsystem)
            sendSessionDelegate.tracker = attachmentChunkUploadProgressTracker
            os_log("👑 The delegate created for calling the UIKit handler has the following UID: %{public}@", log: log, type: .info, sendSessionDelegate.uuid.uuidString)
            
            let sessionConfiguration = URLSessionConfiguration.background(withIdentifier: urlSessionIdentifier)
            sessionConfiguration.useOlvidSettings(sharedContainerIdentifier: sharedContainerIdentifier)
            
            _ = URLSession(configuration: sessionConfiguration,
                           delegate: sendSessionDelegate,
                           delegateQueue: nil)
            
        }
        
    }
}
