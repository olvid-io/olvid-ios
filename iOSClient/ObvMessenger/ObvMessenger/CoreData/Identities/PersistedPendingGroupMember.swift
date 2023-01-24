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
import ObvEngine
import ObvTypes

@objc(PersistedPendingGroupMember)
final class PersistedPendingGroupMember: NSManagedObject {
    
    private static let entityName = "PersistedPendingGroupMember"
    private static let fullDisplayNameKey = "fullDisplayName"
    private static let rawContactGroupKey = "rawContactGroup"
    private static let errorDomain = "PersistedPendingGroupMember"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: - Attributes
    
    @NSManaged var declined: Bool
    @NSManaged var fullDisplayName: String
    @NSManaged private var identity: Data
    @NSManaged private var rawGroupOwnerIdentity: Data // Required for core data constraints
    @NSManaged private var rawGroupUidRaw: Data // Required for core data constraints
    @NSManaged private var rawOwnedIdentityIdentity: Data // Required for core data constraints
    @NSManaged private var serializedIdentityCoreDetails: Data

    // MARK: - Relationships
    
    // If nil, the following entity is eventually cascade-deleted
    @NSManaged private var rawContactGroup: PersistedContactGroup? // *Never* accessed directly

    // MARK: - Variables
    
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
    
    var identityCoreDetails: ObvIdentityCoreDetails {
        return try! ObvIdentityCoreDetails(serializedIdentityCoreDetails)
    }

    var cryptoId: ObvCryptoId {
        return try! ObvCryptoId(identity: identity)
    }
}


// MARK: Initializer

extension PersistedPendingGroupMember {
    
    convenience init(genericIdentity: ObvGenericIdentity, contactGroup: PersistedContactGroup) throws {
        
        guard let context = contactGroup.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        
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
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedPendingGroupMember> {
        return NSFetchRequest<PersistedPendingGroupMember>(entityName: self.entityName)
    }

    static func getFetchedResultsControllerForContactGroup(_ persistedContactGroup: PersistedContactGroup) throws -> NSFetchedResultsController<PersistedPendingGroupMember> {
        
        guard let context = persistedContactGroup.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        
        let fetchRequest: NSFetchRequest<PersistedPendingGroupMember> = PersistedPendingGroupMember.fetchRequest()
        
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: PersistedPendingGroupMember.fullDisplayNameKey, ascending: true)]
        
        fetchRequest.predicate = NSPredicate(format: "%K == %@", rawContactGroupKey, persistedContactGroup)
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        
        return fetchedResultsController
        
    }

    
}
