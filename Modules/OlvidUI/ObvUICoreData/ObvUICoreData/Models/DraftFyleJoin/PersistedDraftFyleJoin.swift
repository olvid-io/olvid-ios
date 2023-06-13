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
import OlvidUtils

@objc(PersistedDraftFyleJoin)
public final class PersistedDraftFyleJoin: NSManagedObject, FyleJoin, ObvIdentifiableManagedObject, ObvErrorMaker {
    
    public static let entityName = "PersistedDraftFyleJoin"
    public static let errorDomain = "PersistedDraftFyleJoin"
    
    // MARK: Attributes
    
    @NSManaged private(set) public var fileName: String
    @NSManaged private(set) public var index: Int
    @NSManaged private var permanentUUID: UUID
    @NSManaged private(set) public var uti: String
    
    // MARK: Relationships
    
    @NSManaged public private(set) var draft: PersistedDraft? // If nil, this entity is eventually cascade-deleted
    @NSManaged private(set) public var fyle: Fyle? // If nil, this entity is eventually cascade-deleted

    // MARK: Computed properties

    public var objectPermanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin> {
        ObvManagedObjectPermanentID<PersistedDraftFyleJoin>(uuid: self.permanentUUID)
    }

}


// MARK: - Initializer

extension PersistedDraftFyleJoin {
    
    public convenience init?(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, fyleObjectID: NSManagedObjectID, fileName: String, uti: String, within context: NSManagedObjectContext) {

        let draft: PersistedDraft
        let fyle: Fyle
        do {
            guard let fetchedDraft = try PersistedDraft.getManagedObject(withPermanentID: draftPermanentID, within: context) else { return nil }
            guard let fetchedFyle = try Fyle.get(objectID: fyleObjectID, within: context) else { return nil }
            draft = fetchedDraft
            fyle = fetchedFyle
        } catch {
            return nil
        }

        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedDraftFyleJoin.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.fileName = fileName
        self.uti = uti
        let currentIndexes = draft.unsortedDraftFyleJoins.map { return $0.index }
        self.index = 1 + (currentIndexes.max() ?? -1)
        self.permanentUUID = UUID()
        
        self.draft = draft
        self.fyle = fyle
        
    }
}


// MARK: - Convenience DB getters

extension PersistedDraftFyleJoin {
    
    public struct Predicate {
        public enum Key: String {
            // Attributes
            case fileName = "fileName"
            case index = "index"
            case permanentUUID = "permanentUUID"
            case uti = "uti"
            // Relationships
            case draft = "draft"
            case fyle = "fyle"
            // Others
            static let draftPermanentUUID = [draft.rawValue, PersistedDraft.Predicate.Key.permanentUUID.rawValue].joined(separator: ".")
        }
        static func persistedDraftFyleJoin(withObjectID objectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) -> NSPredicate {
            NSPredicate(withObjectID: objectID.objectID)
        }
        public static func withPersistedDraft(_ persistedDraft: PersistedDraft) -> NSPredicate {
            NSPredicate(Key.draft, equalTo: persistedDraft)
        }
        static func withPersistedDraft(withObjectID objectID: TypeSafeManagedObjectID<PersistedDraft>) -> NSPredicate {
            NSPredicate(Key.draft, equalToObjectWithObjectID: objectID.objectID)
        }
        static func withFyle(_ fyle: Fyle) -> NSPredicate {
            NSPredicate(Key.fyle, equalTo: fyle)
        }
        static func withFyleWithObjectID(_ fyleObjectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(Key.fyle, equalToObjectWithObjectID: fyleObjectID)
        }
        static var withoutDraft: NSPredicate {
            NSPredicate(withNilValueForKey: Key.draft)
        }
        static func withDraft(withPermanentID draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>) -> NSPredicate {
            NSPredicate(Key.draftPermanentUUID, EqualToUuid: draftPermanentID.uuid)
        }
        static func withPermanentID(_ permanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>) -> NSPredicate {
            NSPredicate(Key.permanentUUID, EqualToUuid: permanentID.uuid)
        }
    }
    
    
    @nonobjc public static func fetchRequest() -> NSFetchRequest<PersistedDraftFyleJoin> {
        return NSFetchRequest<PersistedDraftFyleJoin>(entityName: PersistedDraftFyleJoin.entityName)
    }
    

    static func getManagedObject(withPermanentID permanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>, within context: NSManagedObjectContext) throws -> PersistedDraftFyleJoin? {
        let request: NSFetchRequest<PersistedDraftFyleJoin> = PersistedDraftFyleJoin.fetchRequest()
        request.predicate = Predicate.withPermanentID(permanentID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func get(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, fyleObjectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedDraftFyleJoin? {
        let request: NSFetchRequest<PersistedDraftFyleJoin> = PersistedDraftFyleJoin.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withDraft(withPermanentID: draftPermanentID),
            Predicate.withFyleWithObjectID(fyleObjectID),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func get(objectID typeSafeObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>, within context: NSManagedObjectContext) -> PersistedDraftFyleJoin? {
        let join: PersistedDraftFyleJoin
        do {
            guard let res = try context.existingObject(with: typeSafeObjectID.objectID) as? PersistedDraftFyleJoin else { throw Self.makeError(message: "Could not find PersistedDraftFyleJoin") }
            join = res
        } catch {
            return nil
        }
        return join
    }
    
    
    public static func get(withObjectID objectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>, within context: NSManagedObjectContext) throws -> PersistedDraftFyleJoin? {
        let request: NSFetchRequest<PersistedDraftFyleJoin> = PersistedDraftFyleJoin.fetchRequest()
        request.predicate = Predicate.persistedDraftFyleJoin(withObjectID: objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }


    public static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = PersistedDraftFyleJoin.fetchRequest()
        request.predicate = Predicate.withoutDraft
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(deleteRequest)
    }
    
    
    public static func getFetchedResultsControllerForAllDraftFyleJoinsOfDraft(withObjectID draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedDraftFyleJoin> {
        let fetchRequest: NSFetchRequest<PersistedDraftFyleJoin> = PersistedDraftFyleJoin.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.index.rawValue, ascending: false)]
        fetchRequest.fetchBatchSize = 50
        fetchRequest.predicate = Predicate.withPersistedDraft(withObjectID: draftObjectID)
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        return fetchedResultsController
    }
}
