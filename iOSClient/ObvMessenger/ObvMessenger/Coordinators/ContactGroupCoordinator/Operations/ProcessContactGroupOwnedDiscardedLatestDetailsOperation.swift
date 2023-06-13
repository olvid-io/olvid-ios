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


final class ProcessContactGroupOwnedDiscardedLatestDetailsOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {

    let obvContactGroup: ObvContactGroup
    
    init(obvContactGroup: ObvContactGroup) {
        self.obvContactGroup = obvContactGroup
        super.init()
    }
    
    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            
            do {

                guard let persistedObvOwnedIdentity = try PersistedObvOwnedIdentity.get(persisted: obvContactGroup.ownedIdentity, within: obvContext.context) else {
                    assertionFailure()
                    return
                }
                
                let groupId = (obvContactGroup.groupUid, obvContactGroup.groupOwner.cryptoId)
                
                guard let groupOwned = try PersistedContactGroupOwned.getContactGroup(groupId: groupId, ownedIdentity: persistedObvOwnedIdentity) as? PersistedContactGroupOwned else {
                    assertionFailure()
                    return
                }
                
                groupOwned.setStatus(to: .noLatestDetails)

            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

        }

    }
}
