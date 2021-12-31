/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import ObvEngine
import os.log

/// This operation is typically called when binding an owned identity to a keycloak server. In that case, the engine will return a list of all the contacts that are bound to the same keycloak server.
/// This is the list that is passed to this operation, where we synchronize this list with the corresponding `PersistedObvContactIdentity` instances.
final class UpdateListOfContactsCertifiedByOwnKeycloakOperation: OperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    let ownedIdentity: ObvCryptoId
    let contactsCertifiedByOwnKeycloak: Set<ObvCryptoId>
    
    init(ownedIdentity: ObvCryptoId, contactsCertifiedByOwnKeycloak: Set<ObvCryptoId>) {
        self.ownedIdentity = ownedIdentity
        self.contactsCertifiedByOwnKeycloak = contactsCertifiedByOwnKeycloak
        super.init()
    }
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { context in
            
            // We first mark *all* the contacts of the owned identity as *not* keycloak managed
            
            do {
                try PersistedObvContactIdentity.markAllContactOfOwnedIdentityAsNotCertifiedBySameKeycloak(ownedCryptoId: ownedIdentity, within: context)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            // We then fetch all the contacts corresponding to the contact Id's received in the new list and mark the corresponding
            // `PersistedObvContactIdentity` instances as certified by the same keycloak
            
            var oneOfTheContactsCouldNotBeUpdated = false
            for contactCryptoId in contactsCertifiedByOwnKeycloak {
                do {
                    let contact = try PersistedObvContactIdentity.get(contactCryptoId: contactCryptoId, ownedIdentityCryptoId: ownedIdentity, within: context)
                    contact?.markAsCertifiedByOwnKeycloak()
                } catch {
                    oneOfTheContactsCouldNotBeUpdated = true
                }
            }
            
            // Once we reached this point, we can save the context
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            if oneOfTheContactsCouldNotBeUpdated {
                os_log("One of the contacts could not be marked as certified by own keycloak", log: log, type: .fault)
                assertionFailure()
            }
            
        }
        
    }
    
}
