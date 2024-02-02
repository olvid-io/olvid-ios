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
import ObvEngine
import ObvUICoreData
import CoreData


final class UpdatePersistedContactIdentityWithObvContactIdentityOperation: ContextualOperationWithSpecificReasonForCancel<UpdatePersistedContactIdentityWithObvContactIdentityOperationReasonForCancel> {
    
    let obvContactIdentity: ObvContactIdentity
    
    init(obvContactIdentity: ObvContactIdentity) {
        self.obvContactIdentity = obvContactIdentity
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let persistedContactIdentity = try PersistedObvContactIdentity.get(persisted: obvContactIdentity.contactIdentifier, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindContactIdentityInDatabase)
            }
            
            do {
                try persistedContactIdentity.updateContact(with: obvContactIdentity)
            } catch {
                return cancel(withReason: .failedToUpdatePersistedObvContactIdentity(error: error))
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
}


enum UpdatePersistedContactIdentityWithObvContactIdentityOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case contextIsNil
    case couldNotFindContactIdentityInDatabase
    case failedToUpdatePersistedObvContactIdentity(error: Error)

    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .contextIsNil,
             .failedToUpdatePersistedObvContactIdentity:
            return .fault
        case .couldNotFindContactIdentityInDatabase:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindContactIdentityInDatabase:
            return "Could not find contact identity in database"
        case .failedToUpdatePersistedObvContactIdentity(error: let error):
            return "Failed to update PersistedObvContactIdentity with ObvContactIdentity: \(error.localizedDescription)"
        }
    }

}
