/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import CoreData
import os.log
import OlvidUtils
import ObvUICoreData
import ObvAppCoreConstants

final class DeleteDraftFyleJoinOfDraftOperation: ContextualOperationWithSpecificReasonForCancel<DeleteDraftFyleJoinOfDraftOperationReasonForCancel>, @unchecked Sendable {
    
    private let draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>
    
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: DeleteDraftFyleJoinOfDraftOperation.self))
    
    init(draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) {
        self.draftFyleJoinObjectID = draftFyleJoinObjectID
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            // An attachment that is already gone is what this operation was asked for, not a failure: a second tap on the same ✕ finds nothing to delete.
            guard let persistedDraftFyleJoin = try PersistedDraftFyleJoin.get(withObjectID: draftFyleJoinObjectID, within: obvContext.context) else {
                return
            }
            
            let draft = persistedDraftFyleJoin.draft
            draft?.removeDraftFyleJoin(persistedDraftFyleJoin)
            
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

}


enum DeleteDraftFyleJoinOfDraftOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case contextIsNil
    case coreDataError(error: Error)

    var logType: OSLogType {
        switch self {
        case .contextIsNil,
             .coreDataError:
            return .fault
        }
    }

    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "The context is not set"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }

}
