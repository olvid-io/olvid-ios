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
import ObvEngine
import ObvTypes
import OlvidUtils

@objc(PersistedPendingGroupMember)
public final class PersistedPendingGroupMember: NSManagedObject {
    
    private static let entityName = "PersistedPendingGroupMember"
    
    // MARK: Attributes
    
    @NSManaged private(set) public var declined: Bool
    @NSManaged private(set) var fullDisplayName: String
    @NSManaged private var identity: Data
    @NSManaged private var rawGroupOwnerIdentity: Data // Required for core data constraints
    @NSManaged private var rawGroupUidRaw: Data // Required for core data constraints
    @NSManaged private var rawOwnedIdentityIdentity: Data // Required for core data constraints
    @NSManaged private var serializedIdentityCoreDetails: Data

    // MARK: Relationships
    
    // If nil, the following entity is eventually cascade-deleted
    @NSManaged private var rawContactGroup: PersistedContactGroup? // *Never* accessed directly

    // MARK: Variables
    
    private(set) var contactGroup: PersistedContactGroup? {
        get {
            return self.rawContactGroup
        }
        set {
            assert(newValue != nil)
            if let value = newValue {
                self.rawGroupOwnerIdentity = value.ownerIdentity
                self.rawGroupUidRaw = value.groupUid.raw
                self.rawOwnedIdentityIdentity = value.rawOwnedIdentityIdentity
            }
            self.rawContactGroup = newValue
        }
    }
    
    public var identityCoreDetails: ObvIdentityCoreDetails {
        return try! ObvIdentityCoreDetails(serializedIdentityCoreDetails)
    }

    public var cryptoId: ObvCryptoId {
        return try! ObvCryptoId(identity: identity)
    }
    
    func setDeclined(to newDeclined: Bool) {
        guard self.declined != newDeclined else { return }
        self.declined = newDeclined
    }
    
}


// MARK: - Initializer

extension PersistedPendingGroupMember {
    
    convenience init(genericIdentity: ObvGenericIdentity, contactGroup: PersistedContactGroup) throws {
        
        guard let context = contactGroup.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedPendingGroupMember.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.declined = false
        self.serializedIdentityCoreDetails = try genericIdentity.currentIdentityDetails.coreDetails.jsonEncode()
        self.fullDisplayName = genericIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
        self.identity = genericIdentity.cryptoId.getIdentity()
        self.rawGroupOwnerIdentity = contactGroup.ownerIdentity
        self.rawGroupUidRaw = contactGroup.groupUid.raw
        self.rawOwnedIdentityIdentity = contactGroup.rawOwnedIdentityIdentity

        self.contactGroup = contactGroup
    }
    
}


// MARK: - Convenience NSFetchedResultsController creators

extension PersistedPendingGroupMember {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case declined = "declined"
            case fullDisplayName = "fullDisplayName"
            case identity = "identity"
            case rawGroupOwnerIdentity = "rawGroupOwnerIdentity"
            case rawGroupUidRaw = "rawGroupUidRaw"
            case rawOwnedIdentityIdentity = "rawOwnedIdentityIdentity"
            case serializedIdentityCoreDetails = "serializedIdentityCoreDetails"
            // Relationships
            case rawContactGroup = "rawContactGroup"
        }
        static func withPersistedContactGroup(_ persistedContactGroup: PersistedContactGroup) -> NSPredicate {
            NSPredicate(Key.rawContactGroup, equalTo: persistedContactGroup)
        }
    }
    
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedPendingGroupMember> {
        return NSFetchRequest<PersistedPendingGroupMember>(entityName: self.entityName)
    }
    

    public static func getFetchedResultsControllerForContactGroup(_ persistedContactGroup: PersistedContactGroup) throws -> NSFetchedResultsController<PersistedPendingGroupMember> {
        guard let context = persistedContactGroup.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let fetchRequest: NSFetchRequest<PersistedPendingGroupMember> = PersistedPendingGroupMember.fetchRequest()
        fetchRequest.predicate = Predicate.withPersistedContactGroup(persistedContactGroup)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.fullDisplayName.rawValue, ascending: true)]
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        return fetchedResultsController
        
    }

}


// MARK: - NSFetchedResultsController safeObject

public extension NSFetchedResultsController<PersistedPendingGroupMember> {
    
    /// Provides a safe way to access a `PersistedMessage` at an `indexPath`.
    func safeObject(at indexPath: IndexPath) -> PersistedPendingGroupMember? {
        guard let selfSections = self.sections, indexPath.section < selfSections.count else { return nil }
        let sectionInfos = selfSections[indexPath.section]
        guard indexPath.item < sectionInfos.numberOfObjects else { return nil }
        return self.object(at: indexPath)
    }
    
}
