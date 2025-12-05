/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OlvidUtils
import ObvMetaManager


final class DeletePendingServerQueryOfNonExistingOwnedIdentitiesOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let identityDelegate: ObvIdentityDelegate
    
    init(identityDelegate: ObvIdentityDelegate) {
        self.identityDelegate = identityDelegate
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            let existingOwnedIdentities = try identityDelegate.getOwnedIdentities(restrictToActive: false, within: obvContext)
            let serverQueries = try PendingServerQuery.getAllServerQuery(
                isWebSocket: .any,
                within: obvContext.context)
            for serverQuery in serverQueries {
                guard !serverQuery.isDeleted else { continue }
                if let ownedCryptoIdentity = try? serverQuery.ownedIdentity {
                    if !existingOwnedIdentities.contains(ownedCryptoIdentity) {
                        try serverQuery.deletePendingServerQuery()
                    }
                } else {
                    assertionFailure()
                    try serverQuery.deletePendingServerQuery()
                }
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
