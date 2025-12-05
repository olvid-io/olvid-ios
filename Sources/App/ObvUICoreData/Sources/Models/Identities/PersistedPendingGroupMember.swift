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
import ObvUIObvCircledInitials

@objc(PersistedPendingGroupMember)
public final class PersistedPendingGroupMember: NSManagedObject {
    
    private static let entityName = "PersistedPendingGroupMember"
    
    // MARK: Attributes
    
    @NSManaged private(set) public var declined: Bool
    @NSManaged public private(set) var fullDisplayName: String
    @NSManaged private var identity: Data
    @NSManaged private var rawGroupOwnerIdentity: Data // Required for core data constraints
    @NSManaged private var rawGroupUidRaw: Data // Required for core data constraints
    @NSManaged private var rawOwnedIdentityIdentity: Data // Required for core data constraints
    @NSManaged private var serializedIdentityCoreDetails: Data

    // MARK: Relationships
    
    // If nil, the following entity is eventually cascade-deleted
    @NSManaged private var rawContactGroup: PersistedContactGroup? // *Never* accessed directly

    // MARK: Variables
    
    /// Expected to be non-nil
    public private(set) var contactGroup: PersistedContactGroup? {
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

    public var identityDetails: ObvIdentityDetails {
        return .init(coreDetails: identityCoreDetails, photoURL: nil)
    }

    public var cryptoId: ObvCryptoId {
        return try! ObvCryptoId(identity: identity)
    }
    
    public var ownedCryptoId: ObvCryptoId {
        get throws {
            return try ObvCryptoId(identity: rawOwnedIdentityIdentity)
        }
    }
    
    func setDeclined(to newDeclined: Bool) {
        guard self.declined != newDeclined else { return }
        self.declined = newDeclined
    }
    
    public var circledInitialsConfiguration: CircledInitialsConfiguration {
        .contact(initial: fullDisplayName,
                 photo: .none,
                 showGreenShield: false,
                 showRedShield: false,
                 cryptoId: cryptoId,
                 tintAdjustementMode: .normal)
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
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentityIdentity, EqualToData: ownedCryptoId.getIdentity())
        }
        static func withGroupV1Identifier(_ groupV1Identifier: GroupV1Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.rawGroupUidRaw, EqualToData: groupV1Identifier.groupUid.raw),
                NSPredicate(Key.rawGroupOwnerIdentity, EqualToData: groupV1Identifier.groupOwner.getIdentity()),
            ])
        }
        static func withGroupIdentifier(_ groupIdentifier: ObvGroupV1Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.withOwnedCryptoId(groupIdentifier.ownedCryptoId),
                Self.withGroupV1Identifier(groupIdentifier.groupV1Identifier),
            ])
        }
        static func withObjectID(objectID: TypeSafeManagedObjectID<PersistedPendingGroupMember>) -> NSPredicate {
            NSPredicate(withObjectID: objectID.objectID)
        }
        static func withCryptoIdOfPendingMember(_ cryptoIdOfPendingMember: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.identity, EqualToData: cryptoIdOfPendingMember.getIdentity())
        }
        static func withObjectIDIn(objectIDs: [TypeSafeManagedObjectID<PersistedPendingGroupMember>]) -> NSPredicate {
            NSPredicate(withObjectIDIn: objectIDs.map({ $0.objectID }))
        }
        static func searchPredicate(_ searchedText: String) -> NSPredicate {
            NSPredicate(format: "%K contains[cd] %@", Predicate.Key.fullDisplayName.rawValue, searchedText)
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

    
    public static func getFetchedResultsControllerForContactGroup(groupV1Identifier: ObvGroupV1Identifier, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedPendingGroupMember> {
        let fetchRequest: NSFetchRequest<PersistedPendingGroupMember> = PersistedPendingGroupMember.fetchRequest()
        fetchRequest.predicate = Predicate.withGroupIdentifier(groupV1Identifier)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.fullDisplayName.rawValue, ascending: true)]
        fetchRequest.fetchBatchSize = 300
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        return fetchedResultsController
    }
    
    
    public static func getFetchedResultsController(objectID: TypeSafeManagedObjectID<PersistedPendingGroupMember>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedPendingGroupMember> {
        let request: NSFetchRequest<PersistedPendingGroupMember> = PersistedPendingGroupMember.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID: objectID)
        request.fetchLimit = 1
        request.sortDescriptors = []
        return .init(fetchRequest: request,
                     managedObjectContext: context,
                     sectionNameKeyPath: nil,
                     cacheName: nil)
    }

    public static func get(objectID: TypeSafeManagedObjectID<PersistedPendingGroupMember>, within context: NSManagedObjectContext) throws -> PersistedPendingGroupMember? {
        let request: NSFetchRequest<PersistedPendingGroupMember> = PersistedPendingGroupMember.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID: objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }


    public static func getFetchedResultsController(groupV1Identifier: ObvGroupV1Identifier, cryptoIdOfPendingMember: ObvCryptoId, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedPendingGroupMember> {
        let request: NSFetchRequest<PersistedPendingGroupMember> = PersistedPendingGroupMember.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withGroupIdentifier(groupV1Identifier),
            Predicate.withCryptoIdOfPendingMember(cryptoIdOfPendingMember),
        ])
        request.fetchLimit = 1
        request.sortDescriptors = []
        return .init(fetchRequest: request,
                     managedObjectContext: context,
                     sectionNameKeyPath: nil,
                     cacheName: nil)
    }
 
    
    /// Given a set of persisted pending group members (identified by their objectIDs), this method returns a subset of these pending member, restricting to those matching the search text.
    public static func filterAll(objectIDs: [TypeSafeManagedObjectID<PersistedPendingGroupMember>], searchText: String?, within context: NSManagedObjectContext) throws -> [TypeSafeManagedObjectID<PersistedPendingGroupMember>] {
        
        let sanitizedSearchText = searchText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sanitizedSearchText, !sanitizedSearchText.isEmpty else {
            return objectIDs
        }

        // We will use the input objectIDs in an SQL "IN" statement. Since the maximum size of an "IN" statement is limited,
        // we split the received set of objectIDs in small slices.

        var outputObjectIDs = [TypeSafeManagedObjectID<PersistedPendingGroupMember>]()

        let inputObjectIDsSlices = objectIDs.toSlices(ofMaxSize: 50)
        
        for inputObjectIDsSlice in inputObjectIDsSlices {
            
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: Self.entityName)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.Predicate.withObjectIDIn(objectIDs: inputObjectIDsSlice),
                Self.Predicate.searchPredicate(sanitizedSearchText),
            ])
            request.resultType = .managedObjectIDResultType
            let result = try context.fetch(request) as? [NSManagedObjectID] ?? []
            
            // Keep the input order
            let inputOrder = inputObjectIDsSlice.map(\.objectID)
            let sortedResult = result.sorted { objectID1, objectID2 in
                (inputOrder.firstIndex(of: objectID1) ?? 0) < (inputOrder.firstIndex(of: objectID2) ?? 0)
            }
            
            let outputObjectIDsToAppend: [TypeSafeManagedObjectID<PersistedPendingGroupMember>] = sortedResult.map { TypeSafeManagedObjectID<PersistedPendingGroupMember>(objectID: $0) }
            outputObjectIDs.append(contentsOf: outputObjectIDsToAppend)

        }
        
        return outputObjectIDs

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
