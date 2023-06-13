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
import OlvidUtils


@objc(PendingMessageReaction)
public final class PendingMessageReaction: NSManagedObject, ObvErrorMaker {

    private static let entityName = "PendingMessageReaction"
    public static let errorDomain = "PendingMessageReaction"
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PendingMessageReaction")

    // MARK: - Attributes

    @NSManaged public private(set) var emoji: String?
    @NSManaged private var senderIdentifier: Data
    @NSManaged private var senderSequenceNumber: Int
    @NSManaged private var senderThreadIdentifier: UUID
    @NSManaged public private(set) var serverTimestamp: Date

    // MARK: - Relationships

    @NSManaged private var discussion: PersistedDiscussion? // Expected to be non-nil

    // MARK: - Other variables

    public var messageReferenceJSON: MessageReferenceJSON {
        MessageReferenceJSON(senderSequenceNumber: senderSequenceNumber, senderThreadIdentifier: senderThreadIdentifier, senderIdentifier: senderIdentifier)
    }

    // MARK: - Init

    private convenience init(emoji: String?, senderIdentifier: Data, senderSequenceNumber: Int, senderThreadIdentifier: UUID, serverTimestamp: Date, discussion: PersistedDiscussion) throws {

        guard let context = discussion.managedObjectContext else { throw Self.makeError(message: "Could not find context") }

        let entityDescription = NSEntityDescription.entity(forEntityName: PendingMessageReaction.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.emoji = emoji
        self.senderIdentifier = senderIdentifier
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.serverTimestamp = serverTimestamp
        self.discussion = discussion
    }

    public static func createPendingMessageReactionIfAppropriate(emoji: String?, messageReference: MessageReferenceJSON, serverTimestamp: Date, discussion: PersistedDiscussion) throws {

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

    public func delete() throws {
        guard let context = self.managedObjectContext else { throw Self.makeError(message: "Cannot find context") }
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
                NSPredicate(Key.discussion, equalTo: discussion),
                NSPredicate(Key.senderIdentifier, EqualToData: senderIdentifier),
                NSPredicate(Key.senderThreadIdentifier, EqualToUuid: senderThreadIdentifier),
                NSPredicate(Key.senderSequenceNumber, EqualToInt: senderSequenceNumber),
            ])
        }
        static func olderThanServerTimestamp(_ serverTimestamp: Date) -> NSPredicate {
            NSPredicate(Key.serverTimestamp, earlierThan: serverTimestamp)
        }
        static func moreRecentThanServerTimestamp(_ serverTimestamp: Date) -> NSPredicate {
            NSPredicate(Key.serverTimestamp, laterThan: serverTimestamp)
        }
        static var withoutAssociatedDiscussion: NSPredicate {
            NSPredicate(withNilValueForKey: Key.discussion)
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

    public static func deleteRequestsOlderThanDate(_ date: Date, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = PendingMessageReaction.fetchRequest()
        request.predicate = Predicate.olderThanServerTimestamp(date)
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(batchDeleteRequest)
    }

    public static func deleteOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = PendingMessageReaction.fetchRequest()
        request.predicate = Predicate.withoutAssociatedDiscussion
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(batchDeleteRequest)
    }

    public static func getPendingMessageReaction(discussion: PersistedDiscussion, senderIdentifier: Data, senderThreadIdentifier: UUID, senderSequenceNumber: Int) throws -> PendingMessageReaction? {
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
