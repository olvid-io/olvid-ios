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
import ObvTypes
import ObvEngine
import ObvUICoreData
import CoreData


final class processUserDidSeeNewDetailsOfContactOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {

    let ownedCryptoId: ObvCryptoId
    let contactCryptoId: ObvCryptoId

    init(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) {
        self.ownedCryptoId = ownedCryptoId
        self.contactCryptoId = contactCryptoId
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let persistedContactIdentity = try PersistedObvContactIdentity.get(contactCryptoId: contactCryptoId,
                                                                                     ownedIdentityCryptoId: ownedCryptoId,
                                                                                     whereOneToOneStatusIs: .any,
                                                                                     within: obvContext.context)
            else {
                return
            }
            guard persistedContactIdentity.status == .unseenPublishedDetails else { return }
            persistedContactIdentity.setContactStatus(to: .seenPublishedDetails)
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
}
