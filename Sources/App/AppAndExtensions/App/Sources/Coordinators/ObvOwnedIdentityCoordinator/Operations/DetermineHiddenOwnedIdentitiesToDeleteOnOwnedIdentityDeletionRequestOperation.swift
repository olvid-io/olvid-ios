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
import OlvidUtils
import os.log
import ObvTypes
import ObvEngine
import ObvUICoreData
import CoreData


/// This operation is executed when the user requests the deletion of one of her profile. If the profile to be deleted is that last non-hidden profile, we want to delete all the remaining hidden profiles as well. This operation allows to return a list of these profiles.
final class DetermineHiddenOwnedIdentitiesToDeleteOnOwnedIdentityDeletionRequestOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {

    private let ownedCryptoId: ObvCryptoId
    
    init(ownedCryptoId: ObvCryptoId) {
        self.ownedCryptoId = ownedCryptoId
        super.init()
    }
    
    private(set) var hiddenCryptoIdsToDelete: [ObvCryptoId]?
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            guard let ownedIdentityToDelete = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else { assertionFailure(); return }
            
            // If the owned identity to delete is the last unhidden owned identity, we also delete all hidden identities
            
            if try ownedIdentityToDelete.isLastUnhiddenOwnedIdentity {
                self.hiddenCryptoIdsToDelete = try PersistedObvOwnedIdentity.getAllHiddenOwnedIdentities(within: obvContext.context).map({ $0.cryptoId })
            } else {
                self.hiddenCryptoIdsToDelete = []
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
}
