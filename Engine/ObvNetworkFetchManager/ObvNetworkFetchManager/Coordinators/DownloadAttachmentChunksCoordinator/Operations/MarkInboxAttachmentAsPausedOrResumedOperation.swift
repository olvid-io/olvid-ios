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
import OlvidUtils


final class MarkInboxAttachmentAsPausedOrResumedOperation: Operation {
    
    enum PausedOrResumed {
        case paused
        case resumed
    }
    
    enum ReasonForCancel: LocalizedError {
        case contextCreatorIsNotSet
        case cannotFindInboxAttachmentInDatabase
        case couldNotResumeOrPauseDownload
        case attachmentIsMarkedForDeletion
        case coreDataError(error: Error)
        
        var logType: OSLogType {
            switch self {
            case .attachmentIsMarkedForDeletion:
                return .info
            case .cannotFindInboxAttachmentInDatabase, .couldNotResumeOrPauseDownload:
                return .error
            case .coreDataError, .contextCreatorIsNotSet:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .attachmentIsMarkedForDeletion: return "Attachment is marked for deletion"
            case .contextCreatorIsNotSet: return "Context creator is not set"
            case .cannotFindInboxAttachmentInDatabase: return "Could not find inbox attachment in database"
            case .couldNotResumeOrPauseDownload: return "Could not resume or pause attachment download"
            case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
            }
        }

    }

    func logReasonIfCancelled(log: OSLog) {
        assert(isFinished)
        guard isCancelled else { return }
        guard let reason = self.reasonForCancel else {
            os_log("%{public}@ cancelled without providing a reason. This is a bug", log: log, type: .fault, String(describing: self))
            assertionFailure()
            return
        }
        os_log("%{public}@ cancelled: %{public}@", log: log, type: reason.logType, String(describing: self), reason.localizedDescription)
        if reason.logType == .fault {
            assertionFailure()
        }
    }

    private let uuid = UUID()
    private let attachmentId: ObvAttachmentIdentifier
    private let logSubsystem: String
    private let log: OSLog
    weak private var contextCreator: ObvCreateContextDelegate?
    private let flowId: FlowIdentifier
    private let logCategory = String(describing: DeletePreviousAttachmentSignedURLsOperation.self)
    private let targetStatus: PausedOrResumed
    weak private var delegate: MarkInboxAttachmentAsPausedOrResumedOperationDelegate?
    private let force: Bool

    private(set) var reasonForCancel: ReasonForCancel?

    init(attachmentId: ObvAttachmentIdentifier, targetStatus: PausedOrResumed, force: Bool, logSubsystem: String, flowId: FlowIdentifier, contextCreator: ObvCreateContextDelegate, delegate: MarkInboxAttachmentAsPausedOrResumedOperationDelegate?) {
        self.attachmentId = attachmentId
        self.logSubsystem = logSubsystem
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.contextCreator = contextCreator
        self.flowId = flowId
        self.targetStatus = targetStatus
        self.delegate = delegate
        self.force = force
        super.init()
    }
    
    private func cancel(withReason reason: ReasonForCancel) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
    }

    override func main() {
        
        let targetStatus = self.targetStatus
        let delegate = self.delegate
        let attachmentId = self.attachmentId
        let flowId = self.flowId

        guard let contextCreator = self.contextCreator else {
            return cancel(withReason: .contextCreatorIsNotSet)
        }
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in

            let attachment: InboxAttachment
            do {
                guard let _attachment = try InboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                    return cancel(withReason: .cannotFindInboxAttachmentInDatabase)
                }
                attachment = _attachment
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

            guard !attachment.markedForDeletion else {
                return cancel(withReason: .attachmentIsMarkedForDeletion)
            }
            
            do {
                switch targetStatus {
                case .paused:
                    try attachment.pauseDownload()
                case .resumed:
                    try attachment.resumeDownload(force: force)
                }
            } catch {
                return cancel(withReason: .couldNotResumeOrPauseDownload)
            }
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
                        
        }
        
        guard !isCancelled else { return }
        
        DispatchQueue(label: "Queue for calling MarkInboxAttachmentAsPausedOrResumedOperation delegate").async {
            delegate?.inboxAttachmentWasJustMarkedAsPausedOrResumed(attachmentId: attachmentId, pausedOrResumed: targetStatus, flowId: flowId)
        }

        
    }
    
}


protocol MarkInboxAttachmentAsPausedOrResumedOperationDelegate: AnyObject {
    func inboxAttachmentWasJustMarkedAsPausedOrResumed(attachmentId: ObvAttachmentIdentifier, pausedOrResumed: MarkInboxAttachmentAsPausedOrResumedOperation.PausedOrResumed, flowId: FlowIdentifier)
}
