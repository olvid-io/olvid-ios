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
            
            guard let persistedDraftFyleJoin = try PersistedDraftFyleJoin.get(withObjectID: draftFyleJoinObjectID, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindDraftFyleJoin)
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
    case couldNotFindDraftFyleJoin
    
    var logType: OSLogType {
        switch self {
        case .contextIsNil,
             .coreDataError:
            return .fault
        case .couldNotFindDraftFyleJoin:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "The context is not set"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindDraftFyleJoin:
            return "Could not find draft fyle join in database"
        }
    }

}
