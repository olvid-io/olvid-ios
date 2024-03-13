/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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


final class RefreshNumberOfNewMessagesForAllDiscussionsOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            let ownedIdentities = try PersistedObvOwnedIdentity.getAll(within: obvContext.context)
            for ownedIdentity in ownedIdentities {
                do {
                    try PersistedDiscussion.refreshNumberOfNewMessagesOfAllDiscussions(ownedIdentity: ownedIdentity)
                } catch {
                    assertionFailure() // In production, continue anyway
                }
            }
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

}
