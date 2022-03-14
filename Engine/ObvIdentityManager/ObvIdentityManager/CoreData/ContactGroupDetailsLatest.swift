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
import CoreData
import os.log
import ObvTypes
import ObvCrypto
import ObvEncoder
import ObvMetaManager
import OlvidUtils


@objc(ContactGroupDetailsLatest)
final class ContactGroupDetailsLatest: ContactGroupDetails {
    
    // MARK: Internal constants
    
    private static let entityName = "ContactGroupDetailsLatest"
    private static let errorDomain = String(describing: ContactGroupDetailsLatest.self)
    private static let contactGroupOwnedKey = "contactGroupOwned"
    
    // MARK: Relationships
    
    private(set) var contactGroupOwned: ContactGroupOwned {
        get {
            let item = kvoSafePrimitiveValue(forKey: ContactGroupDetailsLatest.contactGroupOwnedKey) as! ContactGroupOwned
            item.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ContactGroupDetailsLatest.contactGroupOwnedKey)
        }
    }
    
    // MARK: - Initializer
    
    convenience init(contactGroupOwned: ContactGroupOwned, groupDetailsElementsWithPhoto: GroupDetailsElementsWithPhoto, delegateManager: ObvIdentityDelegateManager) throws {
        
        guard let obvContext = contactGroupOwned.obvContext else {
            throw ObvIdentityManagerError.contextIsNil.error(withDomain: ContactGroupDetailsLatest.errorDomain)
        }
        
        try self.init(groupDetailsElementsWithPhoto: groupDetailsElementsWithPhoto,
                      delegateManager: delegateManager,
                      forEntityName: ContactGroupDetailsLatest.entityName,
                      within: obvContext)

        self.contactGroupOwned = contactGroupOwned

    }

    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    convenience init(backupItem: ContactGroupDetailsBackupItem, within obvContext: ObvContext) {
        self.init(backupItem: backupItem, forEntityName: ContactGroupDetailsLatest.entityName, within: obvContext)
    }

}
