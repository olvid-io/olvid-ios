/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import OSLog
import CoreData
import OlvidUtils
import ObvUICoreData
import ObvHistoryTransfer
import ObvAppTypes
import ObvAppCoreConstants


final class StoreHistoryTransferredAttachmentOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private static let log = OSLog.init(subsystem: ObvAppCoreConstants.logSubsystem, category: "StoreHistoryTransferredAttachmentOperation")
    
    private let sha256: Data
    private let temporaryURLOfAttachment: URL
    
    init(sha256: Data, temporaryURLOfAttachment: URL) {
        self.sha256 = sha256
        self.temporaryURLOfAttachment = temporaryURLOfAttachment
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        do {
            let fyle = try Fyle.getOrCreate(sha256: sha256, within: obvContext.context)
            try fyle.storeHistoryTransferredAttachment(sha256: sha256, temporaryURLOfAttachment: temporaryURLOfAttachment)
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
    }
 
    enum ObvError: Error {
        case couldNotFindFyle
    }
    
}
