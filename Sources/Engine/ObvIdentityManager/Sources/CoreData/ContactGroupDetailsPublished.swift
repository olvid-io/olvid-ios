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
import CoreData
import os.log
import ObvTypes
import ObvCrypto
import ObvEncoder
import ObvMetaManager
import OlvidUtils


@objc(ContactGroupDetailsPublished)
final class ContactGroupDetailsPublished: ContactGroupDetails {
    
    // MARK: Internal constants
    
    private static let entityName = "ContactGroupDetailsPublished"
    private static let errorDomain = String(describing: ContactGroupDetailsPublished.self)
    private static let contactGroupKey = "contactGroup"
    
    // MARK: Relationships
    
    private(set) var contactGroup: ContactGroup {
        get {
            let item = kvoSafePrimitiveValue(forKey: ContactGroupDetailsPublished.contactGroupKey) as! ContactGroup
            item.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ContactGroupDetailsPublished.contactGroupKey)
        }
    }
    
    // MARK: - Initializer
    
    convenience init(contactGroup: ContactGroup, groupDetailsElementsWithPhoto: GroupDetailsElementsWithPhoto, delegateManager: ObvIdentityDelegateManager) throws {
        
        guard let obvContext = contactGroup.obvContext else {
            throw ObvIdentityManagerError.contextIsNil
        }
        
        try self.init(groupDetailsElementsWithPhoto: groupDetailsElementsWithPhoto,
                      delegateManager: delegateManager,
                      forEntityName: ContactGroupDetailsPublished.entityName,
                      within: obvContext)
        
        self.contactGroup = contactGroup

    }

    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    convenience init(backupItem: ContactGroupDetailsBackupItem, with obvContext: ObvContext) {
        self.init(backupItem: backupItem, forEntityName: ContactGroupDetailsPublished.entityName, within: obvContext)
    }

    
    /// Used *exclusively* during a snapshot restore for creating an instance, relatioships are recreater in a second step
    convenience init(snapshotNode: ContactGroupDetailsSyncSnapshotNode, with obvContext: ObvContext) {
        self.init(snapshotNode: snapshotNode, forEntityName: ContactGroupDetailsPublished.entityName, within: obvContext)
    }

}
