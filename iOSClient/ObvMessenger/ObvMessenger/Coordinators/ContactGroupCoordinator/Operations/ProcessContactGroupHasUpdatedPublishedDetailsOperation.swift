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
import CoreData
import ObvUICoreData


final class ProcessContactGroupHasUpdatedPublishedDetailsOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {

    let obvContactGroup: ObvContactGroup
    
    init(obvContactGroup: ObvContactGroup) {
        self.obvContactGroup = obvContactGroup
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let persistedObvOwnedIdentity = try PersistedObvOwnedIdentity.get(persisted: obvContactGroup.ownedIdentity, within: obvContext.context) else {
                assertionFailure()
                return
            }
            
            let groupIdentifier = obvContactGroup.groupIdentifier
            
            switch obvContactGroup.groupType {
            case .owned:
                
                guard let groupOwned = try PersistedContactGroupOwned.getContactGroup(groupIdentifier: groupIdentifier, ownedIdentity: persistedObvOwnedIdentity) as? PersistedContactGroupOwned else {
                    assertionFailure()
                    return
                }
                
                try groupOwned.resetGroupName(to: obvContactGroup.publishedCoreDetails.name)
                groupOwned.setStatus(to: .noLatestDetails)
                
            case .joined:
                
                guard let groupJoined = try PersistedContactGroupJoined.getContactGroup(groupIdentifier: groupIdentifier, ownedIdentity: persistedObvOwnedIdentity) as? PersistedContactGroupJoined else {
                    assertionFailure()
                    return
                }
                
                groupJoined.setStatus(to: .unseenPublishedDetails)
                
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
}
