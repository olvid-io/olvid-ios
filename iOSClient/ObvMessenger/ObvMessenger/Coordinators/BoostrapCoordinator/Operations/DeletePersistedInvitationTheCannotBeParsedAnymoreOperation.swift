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
import ObvUICoreData
import CoreData


/// This operation is used during bootstrap to delete any `PersistedInvitation` that cannot be properly parsed, i.e., that returns a `nil` ObvDialog.
/// Usually, all instances can be parsed. But after an app upgrade, we might delete a particular ObvDialog type. In that case, we want to properly delete
/// the corresponding obsolete `PersistedInvitation` instances.
final class DeletePersistedInvitationTheCannotBeParsedAnymoreOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            let allInvitations = try PersistedInvitation.getAllForAllOwnedIdentities(within: obvContext.context)
            let invitationsToDelete = allInvitations.filter { $0.obvDialog == nil }
            guard !invitationsToDelete.isEmpty else { return }
            try invitationsToDelete.forEach {
                try $0.delete()
            }
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
