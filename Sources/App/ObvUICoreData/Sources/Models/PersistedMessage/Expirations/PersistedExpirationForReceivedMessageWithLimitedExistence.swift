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

@objc(PersistedExpirationForReceivedMessageWithLimitedExistence)
public final class PersistedExpirationForReceivedMessageWithLimitedExistence: PersistedMessageExpiration {
    
    private static let entityName = "PersistedExpirationForReceivedMessageWithLimitedExistence"

    // MARK: Relationships

    @NSManaged private(set) var messageReceivedWithLimitedExistence: PersistedMessageReceived?

    // MARK: - Initializer

    convenience init?(messageReceivedWithLimitedExistence: PersistedMessageReceived, existenceDuration: TimeInterval, messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, localDownloadTimestamp: Date) {
        guard let context = messageReceivedWithLimitedExistence.managedObjectContext else { return nil }
        let elapsedTimeBeforeDownload = max(0, downloadTimestampFromServer.timeIntervalSince(messageUploadTimestampFromServer))
        let relativeTo = localDownloadTimestamp.addingTimeInterval(-elapsedTimeBeforeDownload)
        self.init(duration: existenceDuration,
                  relativeTo: relativeTo,
                  entityName: PersistedExpirationForReceivedMessageWithLimitedExistence.entityName,
                  within: context)
        self.messageReceivedWithLimitedExistence = messageReceivedWithLimitedExistence
    }

}


extension PersistedExpirationForReceivedMessageWithLimitedExistence {
    
    private struct Predicate {
        enum Key: String {
            case messageReceivedWithLimitedExistence = "messageReceivedWithLimitedExistence"
        }
        static let withNoMessage = NSPredicate(withNilValueForKey: Key.messageReceivedWithLimitedExistence)
    }
    
    @nonobjc private static func fetchRequest() -> NSFetchRequest<PersistedExpirationForReceivedMessageWithLimitedExistence> {
        return NSFetchRequest<PersistedExpirationForReceivedMessageWithLimitedExistence>(entityName: PersistedExpirationForReceivedMessageWithLimitedExistence.entityName)
    }

    static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = PersistedExpirationForReceivedMessageWithLimitedExistence.fetchRequest()
        request.predicate = Predicate.withNoMessage
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(deleteRequest)
    }
    
}
