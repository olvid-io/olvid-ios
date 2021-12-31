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

@objc(PersistedExpirationForReceivedMessageWithLimitedVisibility)
final class PersistedExpirationForReceivedMessageWithLimitedVisibility: PersistedMessageExpiration {
    
    // MARK: Internal constants

    private static let entityName = "PersistedExpirationForReceivedMessageWithLimitedVisibility"
    private static let messageReceivedWithLimitedVisibilityKey = "messageReceivedWithLimitedVisibility"

    // MARK: - Attributes

    // MARK: - Relationships

    @NSManaged private(set) var messageReceivedWithLimitedVisibility: PersistedMessageReceived

    // MARK: - Initializer

    convenience init?(messageReceivedWithLimitedVisibility: PersistedMessageReceived, visibilityDuration: TimeInterval) {
        guard let context = messageReceivedWithLimitedVisibility.managedObjectContext else { return nil }
        self.init(duration: visibilityDuration,
                  relativeTo: Date(),
                  entityName: PersistedExpirationForReceivedMessageWithLimitedVisibility.entityName,
                  within: context)
        self.messageReceivedWithLimitedVisibility = messageReceivedWithLimitedVisibility
    }
}


extension PersistedExpirationForReceivedMessageWithLimitedVisibility {
    
    private struct Predicate {
        static let withNoMessage = NSPredicate(format: "%K == NULL", messageReceivedWithLimitedVisibilityKey)
    }
    
    @nonobjc private static func fetchRequest() -> NSFetchRequest<PersistedExpirationForReceivedMessageWithLimitedVisibility> {
        return NSFetchRequest<PersistedExpirationForReceivedMessageWithLimitedVisibility>(entityName: PersistedExpirationForReceivedMessageWithLimitedVisibility.entityName)
    }

    static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = PersistedExpirationForReceivedMessageWithLimitedVisibility.fetchRequest()
        request.predicate = Predicate.withNoMessage
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(deleteRequest)
    }
    
}
