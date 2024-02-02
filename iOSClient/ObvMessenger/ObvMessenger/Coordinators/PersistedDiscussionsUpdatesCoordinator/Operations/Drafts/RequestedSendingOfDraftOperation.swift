/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import OlvidUtils
import os.log
import CoreData
import ObvUICoreData


final class RequestedSendingOfDraftOperation: ContextualOperationWithSpecificReasonForCancel<RequestedSendingOfDraftOperationReasonForCancel> {
    
    let draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>

    init(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>) {
        self.draftPermanentID = draftPermanentID
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            guard let draft = try PersistedDraft.getManagedObject(withPermanentID: draftPermanentID, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindDraftInDatabase)
            }
            guard draft.isNotEmpty else {
                return cancel(withReason: .draftIsEmpty)
            }
            draft.send()
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}


enum RequestedSendingOfDraftOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case contextIsNil
    case coreDataError(error: Error)
    case couldNotFindDraftInDatabase
    case draftIsEmpty

    var logType: OSLogType {
        switch self {
        case .contextIsNil,
             .coreDataError,
             .draftIsEmpty:
            return .fault
        case .couldNotFindDraftInDatabase:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "The context is not set"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindDraftInDatabase:
            return "Could not find draft in database"
        case .draftIsEmpty:
            return "Draft is empty"
        }
    }

}
