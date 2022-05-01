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
import os.log
import ObvEngine
import OlvidUtils


final class UpdateContactsSortOrderOperation: OperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    let ownedCryptoId: ObvCryptoId
    let newSortOrder: ContactsSortOrder
    let log: OSLog
    
    init(ownedCryptoId: ObvCryptoId, newSortOrder: ContactsSortOrder, log: OSLog) {
        self.ownedCryptoId = ownedCryptoId
        self.newSortOrder = newSortOrder
        self.log = log
        super.init()
    }
    
    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { context in

            let persistedObvContactIdentites: [PersistedObvContactIdentity]
            do {
                persistedObvContactIdentites = try PersistedObvContactIdentity.getAllContactOfOwnedIdentity(with: ownedCryptoId, whereOneToOneStatusIs: .any, within: context)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

            for persistedObvContactIdentity in persistedObvContactIdentites {
                persistedObvContactIdentity.updateSortOrder(with: newSortOrder)
            }

            do {
                try context.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

            ObvMessengerSettings.Interface.contactsSortOrder = newSortOrder
        }

    }
    
}
