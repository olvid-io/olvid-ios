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
import os.log
import ObvTypes
import OlvidUtils
import ObvUICoreData
import CoreData
import ObvSettings


final class UpdateContactsSortOrderOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    let ownedCryptoId: ObvCryptoId
    let newSortOrder: ContactsSortOrder
    
    init(ownedCryptoId: ObvCryptoId, newSortOrder: ContactsSortOrder) {
        self.ownedCryptoId = ownedCryptoId
        self.newSortOrder = newSortOrder
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            // Update the sort order of PersistedObvContactIdentity instances
            
            let persistedObvContactIdentites = try PersistedObvContactIdentity.getAllContactOfOwnedIdentity(with: ownedCryptoId, whereOneToOneStatusIs: .any, within: obvContext.context)
            
            for persistedObvContactIdentity in persistedObvContactIdentites {
                persistedObvContactIdentity.updateSortOrder(with: newSortOrder)
            }
            
            // Update the sort order of PersistedGroupV2Member instances (some where already updated thanks to the update made to the PersistedObvContactIdentity instances, but not all)
            
            let persistedGroupV2Members = try PersistedGroupV2Member.getAllPersistedGroupV2MemberOfOwnedIdentity(with: ownedCryptoId, within: obvContext.context)
            
            for persistedGroupV2Member in persistedGroupV2Members {
                persistedGroupV2Member.updateNormalizedSortAndSearchKeys(with: newSortOrder)
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
        ObvMessengerSettings.Interface.contactsSortOrder = newSortOrder
        
    }
    
}
