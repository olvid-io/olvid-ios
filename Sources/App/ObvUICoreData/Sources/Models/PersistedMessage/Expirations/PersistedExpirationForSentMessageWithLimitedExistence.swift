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

@objc(PersistedExpirationForSentMessageWithLimitedExistence)
public final class PersistedExpirationForSentMessageWithLimitedExistence: PersistedMessageExpiration {
    
    private static let entityName = "PersistedExpirationForSentMessageWithLimitedExistence"

    // MARK: Relationships

    @NSManaged private(set) var messageSentWithLimitedExistence: PersistedMessageSent?

    // MARK: - Initializer

    convenience init?(messageSentWithLimitedExistence: PersistedMessageSent, existenceDuration: TimeInterval) {
        guard let context = messageSentWithLimitedExistence.managedObjectContext else { return nil }
        self.init(duration: existenceDuration,
                  relativeTo: Date(),
                  entityName: PersistedExpirationForSentMessageWithLimitedExistence.entityName,
                  within: context)
        self.messageSentWithLimitedExistence = messageSentWithLimitedExistence
    }

}


extension PersistedExpirationForSentMessageWithLimitedExistence {
    
    private struct Predicate {
        enum Key: String {
            case messageSentWithLimitedExistence = "messageSentWithLimitedExistence"
        }
        static let withNoMessage = NSPredicate(withNilValueForKey: Key.messageSentWithLimitedExistence)
    }
    
    @nonobjc private static func fetchRequest() -> NSFetchRequest<PersistedExpirationForSentMessageWithLimitedExistence> {
        return NSFetchRequest<PersistedExpirationForSentMessageWithLimitedExistence>(entityName: PersistedExpirationForSentMessageWithLimitedExistence.entityName)
    }

    static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = PersistedExpirationForSentMessageWithLimitedExistence.fetchRequest()
        request.predicate = Predicate.withNoMessage
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs
        let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }
    
}
