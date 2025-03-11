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


final class RemoveReplyToOnDraftOperation: ContextualOperationWithSpecificReasonForCancel<RemoveReplyToOnDraftOperationReasonForCancel>, @unchecked Sendable {

    let draftObjectID: TypeSafeManagedObjectID<PersistedDraft>

    init(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        self.draftObjectID = draftObjectID
        super.init()
    }

    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            guard let draft = try PersistedDraft.get(objectID: draftObjectID, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindDraftInDatabase)
            }
            draft.removeReplyTo()
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

}



enum RemoveReplyToOnDraftOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case contextIsNil
    case coreDataError(error: Error)
    case couldNotFindDraftInDatabase

    var logType: OSLogType {
        switch self {
        case .contextIsNil,
             .coreDataError:
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
        }
    }

    
}
