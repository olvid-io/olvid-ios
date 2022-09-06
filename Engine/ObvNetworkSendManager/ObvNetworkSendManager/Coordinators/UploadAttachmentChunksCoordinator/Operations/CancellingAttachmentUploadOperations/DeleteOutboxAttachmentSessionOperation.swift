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


final class DeleteOutboxAttachmentSessionOperation: Operation {
    
    enum ReasonForCancel: LocalizedError {
        case contextCreatorIsNotSet
        case couldNotSaveContext
        case couldNotDeleteOutboxAttachmentSession(error: Error)
        
        var logType: OSLogType {
            switch self {
            case .contextCreatorIsNotSet, .couldNotSaveContext, .couldNotDeleteOutboxAttachmentSession:
                return .fault
            }
        }

        var localizedDescription: String {
            switch self {
            case .contextCreatorIsNotSet:
                return "Context Creator is not set"
            case .couldNotSaveContext:
                return "Could not save context"
            case .couldNotDeleteOutboxAttachmentSession(error: let error):
                return "Could not delete OutboxAttachmentSession: \(error.localizedDescription)"
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
        assertionFailure()
    }


    private let uuid = UUID()
    private let attachmentId: AttachmentIdentifier
    private let logSubsystem: String
    private let log: OSLog
    private let logCategory = String(describing: ManuallyAcknowledgeChunksThenInvalidateAndCancelAndDeleteOutboxAttachmentSessionOperation.self)
    private let flowId: FlowIdentifier
    private weak var contextCreator: ObvCreateContextDelegate?

    private(set) var reasonForCancel: ReasonForCancel?

    init(attachmentId: AttachmentIdentifier, logSubsystem: String, contextCreator: ObvCreateContextDelegate, flowId: FlowIdentifier) {
        self.attachmentId = attachmentId
        self.logSubsystem = logSubsystem
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.contextCreator = contextCreator
        self.flowId = flowId
        super.init()
    }

    private func cancel(withReason reason: ReasonForCancel) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
    }

    override func main() {
        
        guard let contextCreator = self.contextCreator else {
            return cancel(withReason: .contextCreatorIsNotSet)
        }

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            guard let outboxAttachment = try? OutboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                // Nothing to cancel
                return
            }
            
            guard outboxAttachment.session != nil else { return }

            do {
                try outboxAttachment.deleteSession()
            } catch {
                return cancel(withReason: .couldNotDeleteOutboxAttachmentSession(error: error))
            }
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                cancel(withReason: .couldNotSaveContext)
            }

        }
        
    }
}
