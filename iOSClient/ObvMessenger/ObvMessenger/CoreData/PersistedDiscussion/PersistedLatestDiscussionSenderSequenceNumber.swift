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

@objc(PersistedLatestDiscussionSenderSequenceNumber)
final class PersistedLatestDiscussionSenderSequenceNumber: NSManagedObject {

    private static let entityName = "PersistedLatestDiscussionSenderSequenceNumber"

    private static let errorDomain = "PersistedLatestDiscussionSenderSequenceNumber"

    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: - Attributes

    @NSManaged private(set) var senderThreadIdentifier: UUID
    @NSManaged private(set) var latestSequenceNumber: Int

    // MARK: - Relationships

    @NSManaged private(set) var contactIdentity: PersistedObvContactIdentity?
    @NSManaged private(set) var discussion: PersistedDiscussion?

    // MARK: - Initializer

    convenience init?(discussion: PersistedDiscussion,
                      contactIdentity: PersistedObvContactIdentity,
                      senderThreadIdentifier: UUID,
                      latestSequenceNumber: Int) {

        guard let context = discussion.managedObjectContext else { assertionFailure(); return nil }
        guard discussion.managedObjectContext == contactIdentity.managedObjectContext else { assertionFailure(); return nil }

        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.senderThreadIdentifier = senderThreadIdentifier
        self.latestSequenceNumber = latestSequenceNumber
        self.discussion = discussion
        self.contactIdentity = contactIdentity
    }

    func updateLatestSequenceNumber(with latestSequenceNumber: Int) {
        self.latestSequenceNumber = latestSequenceNumber
    }

    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedLatestDiscussionSenderSequenceNumber> {
        return NSFetchRequest<PersistedLatestDiscussionSenderSequenceNumber>(entityName: PersistedLatestDiscussionSenderSequenceNumber.entityName)
    }

    private struct Predicate {
        enum Key: String {
            case contactIdentity = "contactIdentity"
            case senderThreadIdentifier = "senderThreadIdentifier"
            case discussion = "discussion"
        }
        static func withPrimaryKey(discussion: PersistedDiscussion, contactIdentity: PersistedObvContactIdentity, senderThreadIdentifier: UUID) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "%K == %@", Key.discussion.rawValue, discussion),
                NSPredicate(format: "%K == %@", Key.contactIdentity.rawValue, contactIdentity),
                NSPredicate(Key.senderThreadIdentifier, EqualToUuid: senderThreadIdentifier),
            ])
        }

    }

    static func get(discussion: PersistedDiscussion, contactIdentity: PersistedObvContactIdentity, senderThreadIdentifier: UUID) throws -> PersistedLatestDiscussionSenderSequenceNumber? {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Context is nil") }
        guard discussion.managedObjectContext == contactIdentity.managedObjectContext else { throw makeError(message: "Discussion context is distinct from contact context") }
        let request: NSFetchRequest<PersistedLatestDiscussionSenderSequenceNumber> = PersistedLatestDiscussionSenderSequenceNumber.fetchRequest()

        request.predicate = Predicate.withPrimaryKey(discussion: discussion, contactIdentity: contactIdentity, senderThreadIdentifier: senderThreadIdentifier)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

}
