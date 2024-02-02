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
import ObvTypes
import ObvEngine
import os.log
import ObvUICoreData
import CoreData
import ObvSettings


/// Operation executed when the local user updates a group v2 (as an administrator)
final class UpdateGroupV2Operation: ContextualOperationWithSpecificReasonForCancel<UpdateGroupV2OperationReasonForCancel> {
    
    private let groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>
    private let changeset: ObvGroupV2.Changeset
    private let obvEngine: ObvEngine

    init(groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>, changeset: ObvGroupV2.Changeset, obvEngine: ObvEngine) {
        self.groupObjectID = groupObjectID
        self.changeset = changeset
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let group = try PersistedGroupV2.get(objectID: groupObjectID, within: obvContext.context) else { assertionFailure(); return }
            guard group.ownedIdentityIsAdmin else { assertionFailure(); return }
            
            // If the changeset contains no specific information about the owned identity, we add the default admin permissions for her
            let updatedChangeSet: ObvGroupV2.Changeset
            if !changeset.concernedMembers.contains(try group.ownCryptoId) && !changeset.isEmpty {
                updatedChangeSet = try changeset.adding(newChanges: Set([.ownPermissionsChanged(permissions: ObvUICoreDataConstants.defaultObvGroupV2PermissionsForAdmin)]))
            } else {
                updatedChangeSet = changeset
            }
            
            guard !updatedChangeSet.isEmpty else {
                return
            }
            
            do {
                try obvEngine.updateGroupV2(ownedCryptoId: group.ownCryptoId, groupIdentifier: group.groupIdentifier, changeset: updatedChangeSet)
            } catch {
                return cancel(withReason: .theEngineRequestFailed(error: error))
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}


enum UpdateGroupV2OperationReasonForCancel: LocalizedErrorWithLogType {
    
    case contextIsNil
    case coreDataError(error: Error)
    case theEngineRequestFailed(error: Error)
    
    var logType: OSLogType {
        switch self {
        case .coreDataError, .contextIsNil, .theEngineRequestFailed:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil: return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .theEngineRequestFailed(error: let error):
            return "The group v2 modification engine request did fail: \(error.localizedDescription)"
        }
    }

}
