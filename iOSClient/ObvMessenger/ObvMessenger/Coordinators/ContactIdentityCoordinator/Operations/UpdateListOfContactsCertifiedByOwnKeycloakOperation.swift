/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import ObvTypes
import os.log
import ObvUICoreData


/// This operation is typically called when binding an owned identity to a keycloak server. In that case, the engine will return a list of all the contacts that are bound to the same keycloak server.
/// This is the list that is passed to this operation, where we synchronize this list with the corresponding `PersistedObvContactIdentity` instances.
final class UpdateListOfContactsCertifiedByOwnKeycloakOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    let ownedIdentity: ObvCryptoId
    let contactsCertifiedByOwnKeycloak: Set<ObvCryptoId>
    
    init(ownedIdentity: ObvCryptoId, contactsCertifiedByOwnKeycloak: Set<ObvCryptoId>) {
        self.ownedIdentity = ownedIdentity
        self.contactsCertifiedByOwnKeycloak = contactsCertifiedByOwnKeycloak
        super.init()
    }
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: UpdateListOfContactsCertifiedByOwnKeycloakOperation.self))

    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            
            // We first mark *all* the contacts of the owned identity as *not* keycloak managed
            
            do {
                try PersistedObvContactIdentity.markAllContactOfOwnedIdentityAsNotCertifiedBySameKeycloak(ownedCryptoId: ownedIdentity, within: obvContext.context)
                
                // We then fetch all the contacts corresponding to the contact Id's received in the new list and mark the corresponding
                // `PersistedObvContactIdentity` instances as certified by the same keycloak
                
                for contactCryptoId in contactsCertifiedByOwnKeycloak {
                    let contact = try PersistedObvContactIdentity.get(contactCryptoId: contactCryptoId, ownedIdentityCryptoId: ownedIdentity, whereOneToOneStatusIs: .any, within: obvContext.context)
                    contact?.markAsCertifiedByOwnKeycloak()
                }
                                
            } catch {
                assertionFailure()
                return cancel(withReason: .coreDataError(error: error))
            }

            
        }
        
    }
    
}
