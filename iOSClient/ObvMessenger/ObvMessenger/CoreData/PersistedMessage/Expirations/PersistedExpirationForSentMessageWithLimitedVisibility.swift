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

@objc(PersistedExpirationForSentMessageWithLimitedVisibility)
final class PersistedExpirationForSentMessageWithLimitedVisibility: PersistedMessageExpiration {
        
    // MARK: Internal constants

    private static let entityName = "PersistedExpirationForSentMessageWithLimitedVisibility"
    private static let messageSentWithLimitedVisibilityKey = "messageSentWithLimitedVisibility"

    private static let errorDomain = "PersistedExpirationForSentMessageWithLimitedVisibility"
    private func makeError(message: String) -> Error { NSError(domain: PersistedExpirationForSentMessageWithLimitedVisibility.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: - Attributes
    
    @NSManaged private(set) var retainWipedMessageSent: Bool

    // MARK: - Relationships

    @NSManaged private(set) var messageSentWithLimitedVisibility: PersistedMessageSent

    // MARK: - Initializer

    convenience init?(messageSentWithLimitedVisibility: PersistedMessageSent, visibilityDuration: TimeInterval, retainWipedMessageSent: Bool) {
        guard let context = messageSentWithLimitedVisibility.managedObjectContext else { return nil }
        self.init(duration: visibilityDuration,
                  relativeTo: Date(),
                  entityName: PersistedExpirationForSentMessageWithLimitedVisibility.entityName,
                  within: context)
        self.messageSentWithLimitedVisibility = messageSentWithLimitedVisibility
        self.retainWipedMessageSent = retainWipedMessageSent
    }
    
    func delete() throws {
        guard let context = self.managedObjectContext else { throw makeError(message: "Could not find context") }
        context.delete(self)
    }
}

extension PersistedExpirationForSentMessageWithLimitedVisibility {
    
    private struct Predicate {
        static let withNoMessage = NSPredicate(format: "%K == NULL", messageSentWithLimitedVisibilityKey)
    }
    
    @nonobjc private static func fetchRequest() -> NSFetchRequest<PersistedExpirationForSentMessageWithLimitedVisibility> {
        return NSFetchRequest<PersistedExpirationForSentMessageWithLimitedVisibility>(entityName: PersistedExpirationForSentMessageWithLimitedVisibility.entityName)
    }

    static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = PersistedExpirationForSentMessageWithLimitedVisibility.fetchRequest()
        request.predicate = Predicate.withNoMessage
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(deleteRequest)
    }
    
}
