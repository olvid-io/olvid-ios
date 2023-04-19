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
    static var inboundMessageThatIsNotNewAnymore: NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            isInboundMessage,
            PersistedMessageReceived.Predicate.isNotNewAnymore,
        ])
    }
    static func withSectionIdentifier(_ sectionIdentifier: String) -> NSPredicate {
        NSPredicate(Key.sectionIdentifier, EqualToString: sectionIdentifier)
    }
    static var outboundMessageThatWasSent: NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            isOutboundMessage,
            PersistedMessageSent.Predicate.wasSent,
        ])
    }
}


extension PersistedMessage {

    static func getMessage(beforeSortIndex sortIndex: Double, inDiscussionWithObjectID objectID: TypeSafeManagedObjectID<PersistedDiscussion>, within context: NSManagedObjectContext) throws -> PersistedMessage? {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(objectID),
            Predicate.withSortIndexSmallerThan(sortIndex),
        ])
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: false)]
        return try context.fetch(request).first
    }

    
    static func getAll(with objectIDs: [NSManagedObjectID], within context: NSManagedObjectContext) throws -> [PersistedMessage] {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = Predicate.objectsWithObjectId(in: objectIDs)
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }


    static func getNumberOfMessagesWithinDiscussion(discussionObjectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> Int {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = Predicate.withinDiscussionWithObjectID(discussionObjectID)
        return try context.count(for: request)
    }

    
    static func getLastMessage(in discussion: PersistedDiscussion) throws -> PersistedMessage? {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: false)]
        request.fetchLimit = 1
        request.predicate = Predicate.withinDiscussion(discussion)
        return try context.fetch(request).first
    }
    
}

// MARK: - Convenience NSFetchedResultsController creators

extension PersistedMessage {

    static func getFetchedResultsControllerForAllMessagesWithinDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedMessage> {
        let fetchRequest: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        fetchRequest.predicate = Predicate.withinDiscussion(discussionObjectID)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: true)]
        fetchRequest.fetchBatchSize = 500
        fetchRequest.propertiesToFetch = [
            Predicate.Key.body.rawValue,
            Predicate.Key.rawStatus.rawValue,
            Predicate.Key.rawVisibilityDuration.rawValue,
            Predicate.Key.readOnce.rawValue,
            Predicate.Key.sectionIdentifier.rawValue,
            Predicate.Key.senderSequenceNumber.rawValue,
            Predicate.Key.sortIndex.rawValue,
            Predicate.Key.timestamp.rawValue,
        ]
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.shouldRefreshRefetchedObjects = true
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: Predicate.Key.sectionIdentifier.rawValue,
                                                                  cacheName: nil)

        return fetchedResultsController
    }


    /// This method deletes the first outbound/inbound messages of the discussion, up to the `count` parameter.
    /// Outbound messages only concerns sent messages. Inbound messages only concerns non-new messages.
    static func deleteFirstMessages(discussion: PersistedDiscussion, count: Int) throws {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        guard count > 0 else { return }
        let fetchRequest: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: true)]
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


// MARK: - Determining actions availability

extension PersistedMessage {
    
    var copyActionCanBeMadeAvailable: Bool {
        if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.copyActionCanBeMadeAvailableForReceivedMessage
        } else if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.copyActionCanBeMadeAvailableForSentMessage
        } else {
            return false
        }
    }

    var shareActionCanBeMadeAvailable: Bool {
        if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.shareActionCanBeMadeAvailableForReceivedMessage
        } else if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.shareActionCanBeMadeAvailableForSentMessage
        } else {
            return false
        }
    }
    
    var forwardActionCanBeMadeAvailable: Bool {
        if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.forwardActionCanBeMadeAvailableForReceivedMessage
        } else if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.forwardActionCanBeMadeAvailableForSentMessage
        } else {
            return false
        }
    }
    
    var infoActionCanBeMadeAvailable: Bool {
        if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.infoActionCanBeMadeAvailableForReceivedMessage
        } else if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.infoActionCanBeMadeAvailableForSentMessage
        } else if let systemMessage = self as? PersistedMessageSystem {
            return systemMessage.infoActionCanBeMadeAvailableForSystemMessage
        } else {
            return false
        }
    }
    
    var replyToActionCanBeMadeAvailable: Bool {
        if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.replyToActionCanBeMadeAvailableForReceivedMessage
        } else if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.replyToActionCanBeMadeAvailableForSentMessage
        } else {
            return false
        }
    }

    var editBodyActionCanBeMadeAvailable: Bool {
        if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.editBodyActionCanBeMadeAvailableForSentMessage
        } else {
            return false
        }
    }
    
    var callActionCanBeMadeAvailable: Bool {
        if let systemMessage = self as? PersistedMessageSystem {
            return systemMessage.callActionCanBeMadeAvailableForSystemMessage
        } else {
            return false
        }
    }
    
    var deleteOwnReactionActionCanBeMadeAvailable: Bool {
        if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.deleteOwnReactionActionCanBeMadeAvailableForReceivedMessage
        } else if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.deleteOwnReactionActionCanBeMadeAvailableForSentMessage
        } else {
            return false
        }
    }
    

    /// Returns `true` iff the owned identity is allowed to locally delete this message.
    var deleteMessageActionCanBeMadeAvailable: Bool {
        guard let ownedCryptoId = self.discussion.ownedIdentity?.cryptoId else { assertionFailure(); return false }
        return requesterIsAllowedToDeleteMessage(requester: .ownedIdentity(ownedCryptoId: ownedCryptoId, deletionType: .local))
    }

    
    /// Returns `true` iff the owned identity is allowed to perform a remote (global) delete of this message.
    var globalDeleteMessageActionCanBeMadeAvailable: Bool {
        guard let ownedCryptoId = self.discussion.ownedIdentity?.cryptoId else { assertionFailure(); return false }
        return requesterIsAllowedToDeleteMessage(requester: .ownedIdentity(ownedCryptoId: ownedCryptoId, deletionType: .global))
    }
    
    
    func requesterIsAllowedToDeleteMessage(requester: RequesterOfMessageDeletion) -> Bool {
        do {
            try throwIfRequesterIsNotAllowedToDeleteMessage(requester: requester)
        } catch {
            return false
        }
        return true
    }

}
