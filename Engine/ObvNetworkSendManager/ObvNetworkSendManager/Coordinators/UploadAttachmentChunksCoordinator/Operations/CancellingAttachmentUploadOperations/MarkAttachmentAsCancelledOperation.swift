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


final class MarkAttachmentAsCancelledOperation: Operation {
    
    enum ReasonForCancel: Hashable, LocalizedError {
        case contextCreatorIsNotSet
        case couldNotSaveContext
        
        var localizedDescription: String {
            switch self {
            case .contextCreatorIsNotSet:
                return "Context Creator is not set"
            case .couldNotSaveContext:
                return "Could not save context"
            }
        }
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
            
            guard let outboxAttachment = OutboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                // Nothing to cancel
                return
            }

            outboxAttachment.cancelUpload()
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                cancel(withReason: .couldNotSaveContext)
            }

        }
        
    }
}
