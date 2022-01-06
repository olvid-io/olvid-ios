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

@objc(PersistedDiscussionGroupLocked)
final class PersistedDiscussionGroupLocked: PersistedDiscussion {
    
    static let entityName = "PersistedDiscussionGroupLocked"
        
}

// MARK: - Initializer

extension PersistedDiscussionGroupLocked {
    
    convenience init?(persistedGroupDiscussionToLock: PersistedGroupDiscussion) {
        try? self.init(persistedGroupDiscussionToLock: persistedGroupDiscussionToLock, forEntityName: PersistedDiscussionGroupLocked.entityName)
    }
    
}


// MARK: - Getting NSFetchRequest

extension PersistedDiscussionGroupLocked {
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedDiscussionGroupLocked> {
        return NSFetchRequest<PersistedDiscussionGroupLocked>(entityName: PersistedDiscussionGroupLocked.entityName)
    }
    
    
    static func getAllWithNoMessage(within context: NSManagedObjectContext) throws -> [PersistedDiscussionGroupLocked] {
        
        let request: NSFetchRequest<PersistedDiscussionGroupLocked> = PersistedDiscussionGroupLocked.fetchRequest()
        request.predicate = NSPredicate(format: "%K.@count == 0", PersistedOneToOneDiscussion.messagesKey)
        return try context.fetch(request)
    }
    
    
    static func deletePersistedDiscussionGroupLocked(withObjectID objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws {

        let object = try context.existingObject(with: objectID)
        context.delete(object)

    }
    
}


extension PersistedDiscussionGroupLocked {
    
    override func didSave() {
        super.didSave()
        
        if isInserted {
            let messagesObjectIDs = self.messages.map { $0.objectID }
            DispatchQueue(label: "Queue for refreshing messages on PersistedDiscussionGroupLocked creation").async {
                ObvStack.shared.viewContext.perform {
                    for objectID in messagesObjectIDs {
                        if let messageToRefreshInViewContext = ObvStack.shared.viewContext.registeredObject(for: objectID) {
                            ObvStack.shared.viewContext.refresh(messageToRefreshInViewContext, mergeChanges: false)
                        }
                    }
                }
            }
        }
    }
    
}


extension TypeSafeManagedObjectID where T == PersistedDiscussionGroupLocked {
    var downcast: TypeSafeManagedObjectID<PersistedDiscussion> {
        TypeSafeManagedObjectID<PersistedDiscussion>(objectID: objectID)
    }
}
