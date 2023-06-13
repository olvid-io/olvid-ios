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

@objc(PersistedExpirationForReceivedMessageWithLimitedVisibility)
public final class PersistedExpirationForReceivedMessageWithLimitedVisibility: PersistedMessageExpiration {
    
    private static let entityName = "PersistedExpirationForReceivedMessageWithLimitedVisibility"

    // MARK: Relationships

    @NSManaged private(set) var messageReceivedWithLimitedVisibility: PersistedMessageReceived?

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
        enum Key: String {
            case messageReceivedWithLimitedVisibility = "messageReceivedWithLimitedVisibility"
        }
        static let withNoMessage = NSPredicate(withNilValueForKey: Key.messageReceivedWithLimitedVisibility)
    }
    
    @nonobjc private static func fetchRequest() -> NSFetchRequest<PersistedExpirationForReceivedMessageWithLimitedVisibility> {
        return NSFetchRequest<PersistedExpirationForReceivedMessageWithLimitedVisibility>(entityName: PersistedExpirationForReceivedMessageWithLimitedVisibility.entityName)
    }

    public static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = PersistedExpirationForReceivedMessageWithLimitedVisibility.fetchRequest()
        request.predicate = Predicate.withNoMessage
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(deleteRequest)
    }
    
}
