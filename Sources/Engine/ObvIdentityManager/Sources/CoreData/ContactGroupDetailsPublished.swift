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


@objc(ContactGroupDetailsPublished)
final class ContactGroupDetailsPublished: ContactGroupDetails {
    
    // MARK: Internal constants
    
    private static let entityName = "ContactGroupDetailsPublished"
    private static let errorDomain = String(describing: ContactGroupDetailsPublished.self)
    
    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: ContactGroupDetailsPublished.logSubsystem, category: "ContactGroupDetailsPublished") }()

    // MARK: Relationships
    
    @NSManaged private(set) var contactGroup: ContactGroup
    
    // MARK: - Initializer
    
    convenience init(contactGroup: ContactGroup, groupDetailsElementsWithPhoto: GroupDetailsElementsWithPhoto) throws {
        
        guard let context = contactGroup.managedObjectContext else {
            throw ObvIdentityManagerError.contextIsNil
        }
        
        try self.init(groupDetailsElementsWithPhoto: groupDetailsElementsWithPhoto,
                      forEntityName: ContactGroupDetailsPublished.entityName,
                      within: context)
        
        self.contactGroup = contactGroup

    }

    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    convenience init(backupItem: ContactGroupDetailsBackupItem, with context: NSManagedObjectContext) {
        self.init(backupItem: backupItem, forEntityName: ContactGroupDetailsPublished.entityName, within: context)
    }

    
    /// Used *exclusively* during a snapshot restore for creating an instance, relatioships are recreater in a second step
    convenience init(snapshotNode: ContactGroupDetailsSyncSnapshotNode, with context: NSManagedObjectContext) {
        self.init(snapshotNode: snapshotNode, forEntityName: ContactGroupDetailsPublished.entityName, within: context)
    }

    
    struct Predicate {
        enum Key: String {
            case contactGroup = "contactGroup"
        }
    }

}


extension ContactGroupDetailsPublished {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ContactGroupDetailsPublished> {
        return NSFetchRequest<ContactGroupDetailsPublished>(entityName: ContactGroupDetailsPublished.entityName)
    }

    struct PredicateForContactGroupDetailsPublished {
        enum Key: String {
            case contactGroup = "contactGroup"
        }
        static func withGroupWithUID(_ groupUid: UID) -> NSPredicate {
            let key = [Self.Key.contactGroup.rawValue, ContactGroup.Predicate.Key.rawGroupUid.rawValue].joined(separator: ".")
            return NSPredicate(key, EqualToData: groupUid.raw)
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            let key = [Self.Key.contactGroup.rawValue, ContactGroup.Predicate.Key.ownedIdentity.rawValue, OwnedIdentity.Predicate.Key.rawCryptoIdentity.rawValue].joined(separator: ".")
            return NSPredicate(key, EqualToData: ownedCryptoId.getIdentity())
        }
    }

    /// For a very technical reason, we cannot create a `NSFetchedResultsController` based on the `ObvGroupV1Identifier` of the associated group.
    /// But we can create one base on the owned identity and the group UID. The requester of this `NSFetchedResultsController` will then have to filter out certain results.
    static func getFetchedResultsController(ownedCryptoId: ObvCryptoId, groupUid: UID, within context: NSManagedObjectContext) -> NSFetchedResultsController<ContactGroupDetailsPublished> {
        let request: NSFetchRequest<ContactGroupDetailsPublished> = ContactGroupDetailsPublished.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            PredicateForContactGroupDetailsPublished.withGroupWithUID(groupUid),
            PredicateForContactGroupDetailsPublished.withOwnedCryptoId(ownedCryptoId),
        ])
        request.sortDescriptors = []
        request.fetchLimit = 1
        let frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil)
        return frc
    }
    
}
