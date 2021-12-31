/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

@objc(PersistedDraftFyleJoin)
final class PersistedDraftFyleJoin: NSManagedObject, DraftFyleJoin {
    
    private static let entityName = "PersistedDraftFyleJoin"
    static let draftKey = "draft"
    private static let fyleKey = "fyle"
    static let indexKey = "index"

    // MARK: - Attributes
    
    @NSManaged private(set) var fileName: String
    @NSManaged private(set) var index: Int
    @NSManaged private(set) var uti: String
    
    // MARK: - Relationships
    
    @NSManaged private(set) var draft: PersistedDraft
    @NSManaged private(set) var fyle: Fyle? // If nil, this entity is eventually cascade-deleted

    // MARK: - Computed properties
    
    var fyleElement: FyleElement? {
        FyleElementForPersistedDraftFyleJoin(self)
    }

}


// MARK: - Initializer

extension PersistedDraftFyleJoin {
    
    convenience init?(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, fyleObjectID: NSManagedObjectID, fileName: String, uti: String, within context: NSManagedObjectContext) {

        let draft: PersistedDraft
        let fyle: Fyle
        do {
            guard let fetchedDraft = try PersistedDraft.get(objectID: draftObjectID, within: context) else { return nil }
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
        
        self.draft = draft
        self.fyle = fyle
        
    }
}


// MARK: - Convenience DB getters

extension PersistedDraftFyleJoin {
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedDraftFyleJoin> {
        return NSFetchRequest<PersistedDraftFyleJoin>(entityName: PersistedDraftFyleJoin.entityName)
    }
    
    private struct Predicate {
        static func withPersistedDraft(draftObjectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(format: "%K == %@", PersistedDraftFyleJoin.draftKey, draftObjectID)
        }
        static func withObjectID(_ persistedDraftFyleJoinObjectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(format: "SELF == %@", persistedDraftFyleJoinObjectID)
        }
    }

    static func get(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, fyleObjectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedDraftFyleJoin? {
        guard let draft = try PersistedDraft.get(objectID: draftObjectID, within: context) else { throw NSError() }
        guard let fyle = try Fyle.get(objectID: fyleObjectID, within: context) else { throw NSError() }
        let request: NSFetchRequest<PersistedDraftFyleJoin> = PersistedDraftFyleJoin.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        PersistedDraftFyleJoin.draftKey, draft,
                                        PersistedDraftFyleJoin.fyleKey, fyle)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func get(objectID typeSafeObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>, within context: NSManagedObjectContext) -> PersistedDraftFyleJoin? {
        let join: PersistedDraftFyleJoin
        do {
            guard let res = try context.existingObject(with: typeSafeObjectID.objectID) as? PersistedDraftFyleJoin else { throw NSError() }
            join = res
        } catch {
            return nil
        }
        return join
    }
    
    static func get(withObjectID objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedDraftFyleJoin? {
        let request: NSFetchRequest<PersistedDraftFyleJoin> = PersistedDraftFyleJoin.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }


    static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = PersistedDraftFyleJoin.fetchRequest()
        request.predicate = NSPredicate(format: "%K == NIL", draftKey)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(deleteRequest)
    }
    
    
    static func getFetchedResultsControllerForAllDraftFyleJoinsOfDraft(withObjectID draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedDraftFyleJoin> {
        
        let fetchRequest: NSFetchRequest<PersistedDraftFyleJoin> = PersistedDraftFyleJoin.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: PersistedDraftFyleJoin.indexKey, ascending: false)]
        fetchRequest.fetchBatchSize = 50
        fetchRequest.predicate = Predicate.withPersistedDraft(draftObjectID: draftObjectID.objectID)
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        return fetchedResultsController
    }
}
