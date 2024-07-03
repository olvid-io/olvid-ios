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
import OlvidUtils
import ObvMetaManager


final class DeletePendingServerQueryOfNonExistingOwnedIdentitiesOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let delegateManager: ObvNetworkFetchDelegateManager
    private let identityDelegate: ObvIdentityDelegate
    
    init(delegateManager: ObvNetworkFetchDelegateManager, identityDelegate: ObvIdentityDelegate) {
        self.delegateManager = delegateManager
        self.identityDelegate = identityDelegate
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            let existingOwnedIdentities = try identityDelegate.getOwnedIdentities(restrictToActive: false, within: obvContext)
            let serverQueries = try PendingServerQuery.getAllServerQuery(
                isWebSocket: .any,
                delegateManager: delegateManager,
                within: obvContext)
            for serverQuery in serverQueries {
                guard !serverQuery.isDeleted else { continue }
                if let ownedCryptoIdentity = try? serverQuery.ownedIdentity {
                    if !existingOwnedIdentities.contains(ownedCryptoIdentity) {
                        serverQuery.deletePendingServerQuery(within: obvContext)
                    }
                } else {
                    assertionFailure()
                    serverQuery.deletePendingServerQuery(within: obvContext)
                }
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
