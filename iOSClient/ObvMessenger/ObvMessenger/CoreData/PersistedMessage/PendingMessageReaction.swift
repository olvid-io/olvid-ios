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
import os.log


@objc(PendingMessageReaction)
final class PendingMessageReaction: NSManagedObject {

    private static let entityName = "PendingMessageReaction"
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PendingMessageReaction")
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: Self.self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { PendingMessageReaction.makeError(message: message) }

    @NSManaged private(set) var emoji: String?
    @NSManaged private var senderIdentifier: Data
    @NSManaged private var senderSequenceNumber: Int
    @NSManaged private var senderThreadIdentifier: UUID
    @NSManaged private(set) var serverTimestamp: Date

    // MARK: - Relationships

    @NSManaged private var discussion: PersistedDiscussion? // Expected to be non-nil

    // MARK: - Other variables

    var messageReferenceJSON: MessageReferenceJSON {
        MessageReferenceJSON(senderSequenceNumber: senderSequenceNumber, senderThreadIdentifier: senderThreadIdentifier, senderIdentifier: senderIdentifier)
    }

    // MARK: - Init

    private convenience init(emoji: String?, senderIdentifier: Data, senderSequenceNumber: Int, senderThreadIdentifier: UUID, serverTimestamp: Date, discussion: PersistedDiscussion) throws {

        guard let context = discussion.managedObjectContext else { throw PendingMessageReaction.makeError(message: "Could not find context") }

        let entityDescription = NSEntityDescription.entity(forEntityName: PendingMessageReaction.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.emoji = emoji
        self.senderIdentifier = senderIdentifier
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.serverTimestamp = serverTimestamp
        self.discussion = discussion
    }

    static func createPendingMessageReactionIfAppropriate(emoji: String?, messageReference: MessageReferenceJSON, serverTimestamp: Date, discussion: PersistedDiscussion) throws {

        // We ignore this reaction if there exists a more recent request
        guard try countPendingReactionsMoreRecentThanServerTimestamp(
            serverTimestamp,
            discussion: discussion,
            senderIdentifier: messageReference.senderIdentifier,
            senderThreadIdentifier: messageReference.senderThreadIdentifier,
            senderSequenceNumber: messageReference.senderSequenceNumber) == 0 else { return }

        // If we reach this point, we will add a new pending reaction. We first delete any previous pending reactions.
        try deleteAllPendingReactions(discussion: discussion, senderIdentifier: messageReference.senderIdentifier, senderThreadIdentifier: messageReference.senderThreadIdentifier, senderSequenceNumber: messageReference.senderSequenceNumber)

        _ = try PendingMessageReaction(emoji: emoji,
                                       senderIdentifier: messageReference.senderIdentifier,
                                       senderSequenceNumber: messageReference.senderSequenceNumber,
                                       senderThreadIdentifier: messageReference.senderThreadIdentifier,
                                       serverTimestamp: serverTimestamp,
                                       discussion: discussion)
    }

    // MARK: - Convenience DB getters

    func delete() throws {
        guard let context = self.managedObjectContext else { throw makeError(message: "Cannot find context") }
        context.delete(self)
    }
    
    @nonobjc private static func fetchRequest() -> NSFetchRequest<PendingMessageReaction> {
        return NSFetchRequest<PendingMessageReaction>(entityName: PendingMessageReaction.entityName)
    }

    private struct Predicate {

        enum Key: String {
            case senderIdentifier = "senderIdentifier"
            case senderThreadIdentifier = "senderThreadIdentifier"
            case senderSequenceNumber = "senderSequenceNumber"
            case serverTimestamp = "serverTimestamp"
            case discussion = "discussion"
        }

        static func withPrimaryKey(discussion: PersistedDiscussion, senderIdentifier: Data, senderThreadIdentifier: UUID, senderSequenceNumber: Int) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "%K == %@", Key.discussion.rawValue, discussion),
                NSPredicate(Key.senderIdentifier, EqualToData: senderIdentifier),
                NSPredicate(Key.senderThreadIdentifier, EqualToUuid: senderThreadIdentifier),
                NSPredicate(Key.senderSequenceNumber, EqualToInt: senderSequenceNumber),
            ])
        }
        static func olderThanServerTimestamp(_ serverTimestamp: Date) -> NSPredicate {
            NSPredicate(format: "%K < %@", Key.serverTimestamp.rawValue, serverTimestamp as NSDate)
        }
        static func moreRecentThanServerTimestamp(_ serverTimestamp: Date) -> NSPredicate {
            NSPredicate(format: "%K > %@", Key.serverTimestamp.rawValue, serverTimestamp as NSDate)
        }
        static var withoutAssociatedDiscussion: NSPredicate {
            NSPredicate(format: "%K == NIL", Key.discussion.rawValue)
        }
    }

    private static func countPendingReactionsMoreRecentThanServerTimestamp(_ serverTimestamp: Date, discussion: PersistedDiscussion, senderIdentifier: Data, senderThreadIdentifier: UUID, senderSequenceNumber: Int) throws -> Int {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context") }
        let request: NSFetchRequest<PendingMessageReaction> = PendingMessageReaction.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withPrimaryKey(discussion: discussion, senderIdentifier: senderIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber),
            Predicate.moreRecentThanServerTimestamp(serverTimestamp),
        ])
        return try context.count(for: request)
    }

    private static func deleteAllPendingReactions(discussion: PersistedDiscussion, senderIdentifier: Data, senderThreadIdentifier: UUID, senderSequenceNumber: Int) throws {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context") }
        let request: NSFetchRequest<PendingMessageReaction> = PendingMessageReaction.fetchRequest()
        request.predicate = Predicate.withPrimaryKey(discussion: discussion, senderIdentifier: senderIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber)
        let results = try context.fetch(request)
        for result in results {
            context.delete(result)
        }
    }

    static func deleteRequestsOlderThanDate(_ date: Date, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = PendingMessageReaction.fetchRequest()
        request.predicate = Predicate.olderThanServerTimestamp(date)
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(batchDeleteRequest)
    }

    static func deleteOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = PendingMessageReaction.fetchRequest()
        request.predicate = Predicate.withoutAssociatedDiscussion
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(batchDeleteRequest)
    }

    static func getPendingMessageReaction(discussion: PersistedDiscussion, senderIdentifier: Data, senderThreadIdentifier: UUID, senderSequenceNumber: Int) throws -> PendingMessageReaction? {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context") }
        let request: NSFetchRequest<PendingMessageReaction> = PendingMessageReaction.fetchRequest()
        request.predicate = Predicate.withPrimaryKey(discussion: discussion, senderIdentifier: senderIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber)
        let results = try context.fetch(request)
        switch results.count {
        case 0, 1:
            return results.first
        default:
            // We expect 0 or 1 request in database
            assertionFailure()
            // In production, we return the most recent reaction
            return results.sorted(by: { $0.serverTimestamp > $1.serverTimestamp }).first
        }
    }


}
