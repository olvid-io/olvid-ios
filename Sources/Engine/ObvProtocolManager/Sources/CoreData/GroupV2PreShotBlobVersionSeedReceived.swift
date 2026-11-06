/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvMetaManager
import ObvCrypto
import OlvidUtils
import ObvTypes


@objc(GroupV2PreShotBlobVersionSeedReceived)
final class GroupV2PreShotBlobVersionSeedReceived: NSManagedObject {
    
    private static let entityName = "GroupV2PreShotBlobVersionSeedReceived"
    
    // Attributes
    
    @NSManaged private var insertionDate: Date? // Non-nil in the model
    @NSManaged private var rawBlobVersionSeed: Data? // Non-nil in the model
    @NSManaged private var rawGroupIdentifierCategory: Int
    @NSManaged private var rawGroupIdentifierServerURL: URL? // Non-nil in the model
    @NSManaged private var rawGroupIdentifierUID: Data? // Non-nil in the model
    @NSManaged private var rawOwnedCryptoId: Data? // Non-nil in the model

    // Init
    
    private convenience init(
        ownedCryptoId: ObvCryptoId,
        groupIdentifier: GroupV2.Identifier,
        blobVersionSeed: Seed,
        within context: NSManagedObjectContext
    ) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.insertionDate = .now
        self.rawBlobVersionSeed = blobVersionSeed.raw
        self.rawGroupIdentifierCategory = groupIdentifier.category.rawValue
        self.rawGroupIdentifierServerURL = groupIdentifier.serverURL
        self.rawGroupIdentifierUID = groupIdentifier.groupUID.raw
        self.rawOwnedCryptoId = ownedCryptoId.getIdentity()

    }
    
    /// Inserts a new row, or returns the existing one if `(ownedCryptoId, groupIdentifier, blobVersionSeed)`
    /// is already present. The entity has a uniqueness constraint on that tuple; deduping here keeps the
    /// constraint as a model-level invariant without relying on a save-time merge policy.
    static func insertGroupV2PreShotBlobVersionSeedReceived(
        ownedCryptoId: ObvCryptoId,
        groupIdentifier: GroupV2.Identifier,
        blobVersionSeed: Seed,
        within context: NSManagedObjectContext
    ) throws -> GroupV2PreShotBlobVersionSeedReceived {
        let request: NSFetchRequest<GroupV2PreShotBlobVersionSeedReceived> = fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoId(ownedCryptoId),
            Predicate.withGroupIdentifier(groupIdentifier),
            Predicate.withBlobVersionSeed(blobVersionSeed),
        ])
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            return existing
        }
        return GroupV2PreShotBlobVersionSeedReceived(
            ownedCryptoId: ownedCryptoId,
            groupIdentifier: groupIdentifier,
            blobVersionSeed: blobVersionSeed,
            within: context)
    }
    
}


// MARK: - Computed variables

extension GroupV2PreShotBlobVersionSeedReceived {
    
    var blobVersionSeed: Seed {
        get throws {
            guard let rawBlobVersionSeed else {
                assertionFailure()
                throw ObvError.unexpectedNilValue
            }
            guard let seed = Seed(with: rawBlobVersionSeed) else {
                assertionFailure()
                throw ObvError.couldNotParseSeed
            }
            return seed
        }
    }
    
}


// MARK: - Queries

extension GroupV2PreShotBlobVersionSeedReceived {
    
    enum Predicate {
        enum Key: String {
            case insertionDate = "insertionDate"
            case rawBlobVersionSeed = "rawBlobVersionSeed"
            case rawGroupIdentifierCategory = "rawGroupIdentifierCategory"
            case rawGroupIdentifierServerURL = "rawGroupIdentifierServerURL"
            case rawGroupIdentifierUID = "rawGroupIdentifierUID"
            case rawOwnedCryptoId = "rawOwnedCryptoId"
        }
        static func withGroupIdentifier(_ groupIdentifier: GroupV2.Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.rawGroupIdentifierCategory, EqualToInt: groupIdentifier.category.rawValue),
                NSPredicate(Key.rawGroupIdentifierServerURL, EqualToUrl: groupIdentifier.serverURL),
                NSPredicate(Key.rawGroupIdentifierUID, EqualToData: groupIdentifier.groupUID.raw),
            ])
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawOwnedCryptoId, EqualToData: ownedCryptoId.getIdentity())
        }
        static func withBlobVersionSeed(_ blobVersionSeed: Seed) -> NSPredicate {
            NSPredicate(Key.rawBlobVersionSeed, EqualToData: blobVersionSeed.raw)
        }
        static func insertedBefore(_ date: Date) -> NSPredicate {
            NSPredicate(Key.insertionDate, earlierThan: date)
        }
    }
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<GroupV2PreShotBlobVersionSeedReceived> {
        return NSFetchRequest<GroupV2PreShotBlobVersionSeedReceived>(entityName: Self.entityName)
    }

    static func fetchPreShotBlobVersionSeeds(ownedCryptoId: ObvCryptoId, groupIdentifier: GroupV2.Identifier, within context: NSManagedObjectContext) throws -> [Seed] {
        let request = NSFetchRequest<NSDictionary>(entityName: Self.entityName)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoId(ownedCryptoId),
            Predicate.withGroupIdentifier(groupIdentifier),
        ])
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = [Predicate.Key.rawBlobVersionSeed.rawValue]
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.insertionDate.rawValue, ascending: false)]
        let rows = try context.fetch(request)
        return rows.compactMap { row in
            guard let raw = row[Predicate.Key.rawBlobVersionSeed.rawValue] as? Data else { return nil }
            return Seed(with: raw)
        }
    }

}


// MARK: - Batch deletion

extension GroupV2PreShotBlobVersionSeedReceived {

    static func batchDeletePreShotBlobVersionSeedsReceived(insertedBefore cutoff: Date, within context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: Self.entityName)
        fetchRequest.predicate = Predicate.insertedBefore(cutoff)
        try executeBatchDeleteAndMerge(fetchRequest: fetchRequest, within: context)
    }


    /// Deletes every pre-shot row associated with the given group of the given owned identity. Invoked when
    /// the corresponding `ContactGroupV2` is removed from the identity manager so the protocol-side store
    /// does not keep stranded seeds for a group that no longer exists.
    static func deleteAllPreShotBlobVersionSeedsReceived(ownedCryptoId: ObvCryptoId, groupIdentifier: GroupV2.Identifier, within context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: Self.entityName)
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoId(ownedCryptoId),
            Predicate.withGroupIdentifier(groupIdentifier),
        ])
        try executeBatchDeleteAndMerge(fetchRequest: fetchRequest, within: context)
    }


    /// Deletes every pre-shot row associated with the given owned identity (across all of its groups).
    /// Invoked when the corresponding `OwnedIdentity` is removed from the identity manager so the
    /// protocol-side store does not keep stranded seeds for a profile that no longer exists.
    static func deleteAllPreShotBlobVersionSeedsReceived(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: Self.entityName)
        fetchRequest.predicate = Predicate.withOwnedCryptoId(ownedCryptoId)
        try executeBatchDeleteAndMerge(fetchRequest: fetchRequest, within: context)
    }


    private static func executeBatchDeleteAndMerge(fetchRequest: NSFetchRequest<NSFetchRequestResult>, within context: NSManagedObjectContext) throws {
        let request = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        request.resultType = .resultTypeObjectIDs
        let result = try context.execute(request) as? NSBatchDeleteResult
        // NSBatchDeleteRequest writes directly to the SQLite store, bypassing the context.
        // Merge the deletions back so any in-memory copies in this (or peer) context become consistent.
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSDeletedObjectsKey: objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }

}


// MARK: - Errors

extension GroupV2PreShotBlobVersionSeedReceived {
    
    enum ObvError: Error {
        case unexpectedNilValue
        case couldNotParseSeed
    }
}
