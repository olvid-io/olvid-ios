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
import os.log
import ObvTypes
import ObvEngine
import ObvUICoreData


protocol DeleteOwnedIdentityOperationDelegate: AnyObject {
    func deleteHiddenOwnedIdentityAsTheLastVisibleOwnedIdentityIsBeingDeleted(hiddenOwnedCryptoId: ObvCryptoId, notifyContacts: Bool)
}


final class DeleteOwnedIdentityOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {

    private let ownedCryptoId: ObvCryptoId
    private let obvEngine: ObvEngine
    private let notifyContacts: Bool
    private weak var delegate: DeleteOwnedIdentityOperationDelegate?
    
    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine, notifyContacts: Bool, delegate: DeleteOwnedIdentityOperationDelegate) {
        self.ownedCryptoId = ownedCryptoId
        self.obvEngine = obvEngine
        self.notifyContacts = notifyContacts
        self.delegate = delegate
        super.init()
    }
    
    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            do {
                guard let ownedIdentityToDelete = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else { assertionFailure(); return }
                
                // If the owned identity to delete is the last unhidden owned identity, we also delete all hidden identities
                
                let hiddenCryptoIdsToDelete: [ObvCryptoId]
                if try ownedIdentityToDelete.isLastUnhiddenOwnedIdentity {
                    hiddenCryptoIdsToDelete = try PersistedObvOwnedIdentity.getAllHiddenOwnedIdentities(within: obvContext.context).map({ $0.cryptoId })
                } else {
                    hiddenCryptoIdsToDelete = []
                }
                
                if !hiddenCryptoIdsToDelete.isEmpty {
                    
                    // If we reach this point, we have hidden profiles to delete. To do so, we request the deletion to our delegate
                    assert(delegate != nil)
                    for hiddenCryptoIdToDelete in hiddenCryptoIdsToDelete {
                        delegate?.deleteHiddenOwnedIdentityAsTheLastVisibleOwnedIdentityIsBeingDeleted(hiddenOwnedCryptoId: hiddenCryptoIdToDelete, notifyContacts: notifyContacts)
                    }
                    
                }
                
                // We can perform the request deletion of the ownedCryptoId

                try obvEngine.deleteOwnedIdentity(with: ownedCryptoId, notifyContacts: notifyContacts)

            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }

    }
}
