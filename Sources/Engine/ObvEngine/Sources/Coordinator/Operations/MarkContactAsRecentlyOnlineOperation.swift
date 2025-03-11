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
import OlvidUtils
import CoreData
import ObvTypes
import ObvMetaManager



final class MarkContactAsRecentlyOnlineOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    let contactIdentifier: ObvContactIdentifier
    let identityDelegate: ObvIdentityDelegate
    
    init(contactIdentifier: ObvContactIdentifier, identityDelegate: ObvIdentityDelegate) {
        self.contactIdentifier = contactIdentifier
        self.identityDelegate = identityDelegate
        super.init()
    }
    
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {

            try identityDelegate.markContactAsRecentlyOnline(ownedIdentity: contactIdentifier.ownedCryptoId.cryptoIdentity,
                                                         contactIdentity: contactIdentifier.contactCryptoId.cryptoIdentity,
                                                         within: obvContext)
            
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
        
    }
    
    
}
