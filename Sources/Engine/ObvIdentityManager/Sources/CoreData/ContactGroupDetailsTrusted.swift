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
import OSLog
import ObvTypes
import ObvCrypto
import ObvEncoder
import ObvMetaManager
import OlvidUtils


@objc(ContactGroupDetailsTrusted)
final class ContactGroupDetailsTrusted: ContactGroupDetails {
    
    // MARK: Internal constants
    
    private static let entityName = "ContactGroupDetailsTrusted"
    private static let errorDomain = String(describing: ContactGroupDetailsTrusted.self)

    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: ContactGroupDetailsTrusted.logSubsystem, category: "ContactGroupDetailsTrusted") }()

    // MARK: Relationships
    
    @NSManaged private(set) var contactGroupJoined: ContactGroupJoined

    // MARK: - Initializer
    
    convenience init(contactGroupJoined: ContactGroupJoined, groupDetailsElementsWithPhoto: GroupDetailsElementsWithPhoto) throws {
        
        guard let context = contactGroupJoined.managedObjectContext else {
            throw ObvIdentityManagerError.contextIsNil
        }
        
        try self.init(groupDetailsElementsWithPhoto: groupDetailsElementsWithPhoto,
                      forEntityName: ContactGroupDetailsTrusted.entityName,
                      within: context)
                
        self.contactGroupJoined = contactGroupJoined

    }

    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    convenience init(backupItem: ContactGroupDetailsBackupItem, within context: NSManagedObjectContext) {
        self.init(backupItem: backupItem, forEntityName: ContactGroupDetailsTrusted.entityName, within: context)
    }

    /// Used *exclusively* during a snapshot restore for creating an instance, relatioships are recreater in a second step
    convenience init(snapshotNode: ContactGroupDetailsSyncSnapshotNode, within context: NSManagedObjectContext) {
        self.init(snapshotNode: snapshotNode, forEntityName: ContactGroupDetailsTrusted.entityName, within: context)
    }

    
    struct Predicate {
        enum Key: String {
            case contactGroupJoined = "contactGroupJoined"
        }
    }

}
