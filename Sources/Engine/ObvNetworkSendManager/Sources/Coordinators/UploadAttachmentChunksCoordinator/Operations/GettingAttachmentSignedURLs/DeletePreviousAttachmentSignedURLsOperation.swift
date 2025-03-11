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


final class DeletePreviousAttachmentSignedURLsOperation: Operation, @unchecked Sendable {
    
    enum ReasonForCancel: Hashable {
        case cannotFindAttachmentInDatabase
        case couldNotSaveContext
    }

    private let uuid = UUID()
    private let attachmentId: ObvAttachmentIdentifier
    private let logSubsystem: String
    private let log: OSLog
    private let obvContext: ObvContext
    private let logCategory = String(describing: DeletePreviousAttachmentSignedURLsOperation.self)

    private(set) var reasonForCancel: ReasonForCancel?

    init(attachmentId: ObvAttachmentIdentifier, logSubsystem: String, obvContext: ObvContext) {
        self.attachmentId = attachmentId
        self.logSubsystem = logSubsystem
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.obvContext = obvContext
        super.init()
    }
    
    private func cancel(withReason reason: ReasonForCancel) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
    }

    override func main() {
        
        obvContext.performAndWait {
            
            guard let attachment = try? OutboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                return cancel(withReason: .cannotFindAttachmentInDatabase)
            }
            
            attachment.chunks.forEach { (chunk) in
                chunk.signedURL = nil
            }
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .couldNotSaveContext)
            }
            
        }
        
    }
    
}
