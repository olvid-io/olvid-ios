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

// MARK: - Convenience DB getters

extension PersistedMessage.Predicate {
    static var isInboundMessage: NSPredicate {
        NSPredicate(format: "entity == %@", PersistedMessageReceived.entity())
    }
    static var isNotInboundMessage: NSPredicate {
        NSPredicate(format: "entity != %@", PersistedMessageReceived.entity())
    }
    static var isSystemMessage: NSPredicate {
        NSPredicate(format: "entity == %@", PersistedMessageSystem.entity())
    }
    static var inboundMessageThatIsNotNewAnymore: NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            isInboundMessage,
            PersistedMessageReceived.Predicate.isNotNewAnymore,
        ])
    }
    static func withSortIndexSmallerThan(_ sortIndex: Double) -> NSPredicate {
        NSPredicate(format: "%K < %lf", PersistedMessage.sortIndexKey, sortIndex)
    }
    static func withSectionIdentifier(_ sectionIdentifier: String) -> NSPredicate {
        NSPredicate(format: "%K == %@", PersistedMessage.sectionIdentifierKey, sectionIdentifier)
    }
    static var isOutboundMessage: NSPredicate {
        NSPredicate(format: "entity == %@", PersistedMessageSent.entity())
    }
    static var outboundMessageThatWasSent: NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            isOutboundMessage,
            PersistedMessageSent.Predicate.wasSent,
        ])
    }
}


extension PersistedMessage {

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: Self.self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessage> {
        return NSFetchRequest<PersistedMessage>(entityName: PersistedMessage.PersistedMessageEntityName)
    }
    static func getMessageRightBeforeReceivedMessageInSameSection(_ message: PersistedMessageReceived) throws -> PersistedMessage? {
        guard let context = message.managedObjectContext else { throw NSError() }
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withSortIndexSmallerThan(message.sortIndex),
            Predicate.withSectionIdentifier(message.sectionIdentifier),
        ])
        request.sortDescriptors = [
            NSSortDescriptor(key: PersistedMessage.sectionIdentifierKey, ascending: true),
            NSSortDescriptor(key: sortIndexKey, ascending: false),
        ]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func getMessage(afterSortIndex sortIndex: Double, in discussion: PersistedDiscussion) throws -> PersistedMessage? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K > %lf",
                                        discussionKey, discussion,
                                        sortIndexKey, sortIndex)
        request.sortDescriptors = [NSSortDescriptor(key: sortIndexKey, ascending: true)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func getMessage(beforeSortIndex sortIndex: Double, in discussion: PersistedDiscussion) throws -> PersistedMessage? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K < %lf",
                                        discussionKey, discussion,
                                        sortIndexKey, sortIndex)
        request.sortDescriptors = [NSSortDescriptor(key: sortIndexKey, ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func getMessage(beforeSortIndex sortIndex: Double, inDiscussionWithObjectID objectID: TypeSafeManagedObjectID<PersistedDiscussion>, within context: NSManagedObjectContext) throws -> PersistedMessage? {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K < %lf",
                                        discussionKey, objectID.objectID,
                                        sortIndexKey, sortIndex)
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: sortIndexKey, ascending: false)]
        return try context.fetch(request).first
    }

    static func get(with objectID: TypeSafeManagedObjectID<PersistedMessage>, within context: NSManagedObjectContext) throws -> PersistedMessage? {
        return try get(with: objectID.objectID, within: context)
    }

    static func get(with objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedMessage? {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }


    static func getAll(with objectIDs: [NSManagedObjectID], within context: NSManagedObjectContext) throws -> [PersistedMessage] {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = Predicate.objectsWithObjectId(in: objectIDs)
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }

    static func deleteAllWithinDiscussion(persistedDiscussionObjectID: NSManagedObjectID, within context: NSManagedObjectContext) throws {
        // For now, the structure of the database prevents batch deletion
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", discussionKey, persistedDiscussionObjectID)
        request.fetchBatchSize = 1_000
        request.includesPropertyValues = false
        let messages = try context.fetch(request)
        _ = messages.map { context.delete($0) }
    }

    static func getNumberOfMessagesWithinDiscussion(discussionObjectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> Int {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", discussionKey, discussionObjectID)
        return try context.count(for: request)
    }

    static func getAppropriateIllustrativeMessage(in discussion: PersistedDiscussion) throws -> PersistedMessage? {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: PersistedMessage.sortIndexKey, ascending: false)]
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withinDiscussion(discussion),
                Predicate.isInboundMessage,
            ]),
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withinDiscussion(discussion),
                Predicate.isOutboundMessage,
            ]),
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withinDiscussion(discussion),
                Predicate.isSystemMessage,
                PersistedMessageSystem.Predicate.isRelevantForIllustrativeMessage,
            ]),
        ])
        return try context.fetch(request).first
    }

    static func findMessageFrom(reference referenceJSON: MessageReferenceJSON, within discussion: PersistedDiscussion) throws -> PersistedMessage? {
        if let message = try PersistedMessageReceived.get(senderSequenceNumber: referenceJSON.senderSequenceNumber,
                                                          senderThreadIdentifier: referenceJSON.senderThreadIdentifier,
                                                          contactIdentity: referenceJSON.senderIdentifier,
                                                          discussion: discussion) {
            return message
        } else if let message = try PersistedMessageSent.get(senderSequenceNumber: referenceJSON.senderSequenceNumber,
                                                             senderThreadIdentifier: referenceJSON.senderThreadIdentifier,
                                                             ownedIdentity: referenceJSON.senderIdentifier,
                                                             discussion: discussion) {
            assert(referenceJSON.senderIdentifier == discussion.ownedIdentity!.cryptoId.getIdentity())
            return message
        } else {
            return nil
        }
    }
    
}

// MARK: - Convenience NSFetchedResultsController creators

extension PersistedMessage {

    static func getFetchedResultsControllerForAllMessagesWithinDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedMessage> {
        let fetchRequest: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "%K == %@", discussionKey, discussionObjectID.objectID)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: PersistedMessage.sortIndexKey, ascending: true)]
        fetchRequest.fetchBatchSize = 500
        fetchRequest.propertiesToFetch = [
            bodyKey,
            rawStatusKey,
            rawVisibilityDurationKey,
            readOnceKey,
            sectionIdentifierKey,
            senderSequenceNumberKey,
            sortIndexKey,
            timestampKey,
        ]
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.shouldRefreshRefetchedObjects = true
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: sectionIdentifierKey,
                                                                  cacheName: nil)

        return fetchedResultsController
    }


    static func getFetchedResultsControllerForLastMessagesWithinDiscussion(discussionObjectID: NSManagedObjectID, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedMessage> {

        let numberOfMessagesToFetch = 20

        let numberOfMessages: Int
        do {
            numberOfMessages = try getNumberOfMessagesWithinDiscussion(discussionObjectID: discussionObjectID, within: context)
        } catch {
            numberOfMessages = 0
        }

        let fetchRequest: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "%K == %@", discussionKey, discussionObjectID)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: PersistedMessage.sortIndexKey, ascending: true)]
        fetchRequest.fetchLimit = min(numberOfMessagesToFetch, numberOfMessages)
        fetchRequest.fetchOffset = max(0, numberOfMessages - numberOfMessagesToFetch)

        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: sectionIdentifierKey,
                                                                  cacheName: nil)

        return fetchedResultsController
    }

    /// This method deletes the first outbound/inbound messages of the discussion, up to the `count` parameter.
    /// Oubound messages only concerns sent messages. Outbound messages only concerns non-new messages.
    static func deleteFirstMessages(discussion: PersistedDiscussion, count: Int) throws {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        guard count > 0 else { return }
        let fetchRequest: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: PersistedMessage.sortIndexKey, ascending: true)]
        fetchRequest.fetchLimit = count
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                Predicate.outboundMessageThatWasSent,
                Predicate.inboundMessageThatIsNotNewAnymore,
            ]),
        ])
        let messages = try context.fetch(fetchRequest)
        messages.forEach { context.delete($0) }
    }

}
