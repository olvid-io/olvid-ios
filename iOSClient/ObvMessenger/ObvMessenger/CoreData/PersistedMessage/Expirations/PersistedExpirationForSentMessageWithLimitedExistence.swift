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

@objc(PersistedExpirationForSentMessageWithLimitedExistence)
final class PersistedExpirationForSentMessageWithLimitedExistence: PersistedMessageExpiration {
    
    // MARK: Internal constants

    private static let entityName = "PersistedExpirationForSentMessageWithLimitedExistence"
    private static let messageSentWithLimitedExistenceKey = "messageSentWithLimitedExistence"

    // MARK: - Attributes

    // None

    // MARK: - Relationships

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
        static let withNoMessage = NSPredicate(format: "%K == NULL", messageSentWithLimitedExistenceKey)
    }
    
    @nonobjc private static func fetchRequest() -> NSFetchRequest<PersistedExpirationForSentMessageWithLimitedExistence> {
        return NSFetchRequest<PersistedExpirationForSentMessageWithLimitedExistence>(entityName: PersistedExpirationForSentMessageWithLimitedExistence.entityName)
    }

    static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = PersistedExpirationForSentMessageWithLimitedExistence.fetchRequest()
        request.predicate = Predicate.withNoMessage
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(deleteRequest)
    }
    
}
