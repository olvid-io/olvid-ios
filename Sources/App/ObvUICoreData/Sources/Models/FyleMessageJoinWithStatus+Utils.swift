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
import UniformTypeIdentifiers


extension FyleMessageJoinWithStatus.Predicate {
    
    static func isReceivedFyleMessageJoinWithStatusInDiscussion(_ discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) -> NSPredicate {
        let discussionKey = [ReceivedFyleMessageJoinWithStatus.Predicate.Key.receivedMessage.rawValue, PersistedMessage.Predicate.Key.discussion.rawValue].joined(separator: ".")
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(withEntity: ReceivedFyleMessageJoinWithStatus.entity()),
            NSPredicate(format: "%K == %@", discussionKey, discussionObjectID.objectID),
        ])
    }

    static func isFyleMessageJoinWithStatusInDiscussion(_ discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) -> NSPredicate {
        NSCompoundPredicate(orPredicateWithSubpredicates: [
            isSentFyleMessageJoinWithStatusInDiscussion(discussionObjectID),
            isReceivedFyleMessageJoinWithStatusInDiscussion(discussionObjectID),
        ])
    }

    
    static func isReceivedFyleMessageJoinWithStatusOfReceivedMessage(_ receivedMessage: PersistedMessageReceived) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(withEntity: ReceivedFyleMessageJoinWithStatus.entity()),
            NSPredicate.init(ReceivedFyleMessageJoinWithStatus.Predicate.Key.receivedMessage, equalTo: receivedMessage),
        ])
    }

    
    static func isSentFyleMessageJoinWithStatusOfSentMessage(_ sentMessage: PersistedMessageSent) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(withEntity: SentFyleMessageJoinWithStatus.entity()),
            NSPredicate.init(SentFyleMessageJoinWithStatus.Predicate.Key.sentMessage, equalTo: sentMessage),
        ])
    }

    
    static func isFyleMessageJoinWithStatusOfMessage(_ message: PersistedMessage) -> NSPredicate {
        if let receivedMessage = message as? PersistedMessageReceived {
            return isReceivedFyleMessageJoinWithStatusOfReceivedMessage(receivedMessage)
        } else if let sentMessage = message as? PersistedMessageSent {
            return isSentFyleMessageJoinWithStatusOfSentMessage(sentMessage)
        } else {
            assertionFailure()
            return NSPredicate(value: true)
        }
    }

    
}


extension FyleMessageJoinWithStatus {

    private static func getFetchedResultsControllerForAllJoinsWithinDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, predicate: NSPredicate, within context: NSManagedObjectContext) -> NSFetchedResultsController<FyleMessageJoinWithStatus> {

        let fetchRequest: NSFetchRequest<FyleMessageJoinWithStatus> = FyleMessageJoinWithStatus.fetchRequest()
        // To the contrary of what we do, e.g., with `isReceivedFyleMessageJoinWithStatusInDiscussion`, we cannot test whether a `FyleMessageJoinWithStatus` is received or sent.
        // For this reason, we had to replicate the message sort index since a FyleMessageJoinWithStatus has no associated message (only subclasses have).
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: Predicate.Key.messageSortIndex.rawValue, ascending: false),
            NSSortDescriptor(key: FyleMessageJoinWithStatus.Predicate.Key.index.rawValue, ascending: true),
        ]
        fetchRequest.fetchBatchSize = 500
        fetchRequest.predicate = predicate

        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)

        return fetchedResultsController
    }

    public static func getFetchedResultsControllerForAllJoinsWithinDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, restrictToUTIs: [String], within context: NSManagedObjectContext) -> NSFetchedResultsController<FyleMessageJoinWithStatus> {

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isFyleMessageJoinWithStatusInDiscussion(discussionObjectID),
            NSCompoundPredicate(orPredicateWithSubpredicates: restrictToUTIs.map({ NSPredicate(Predicate.Key.uti, EqualToString: $0) })),
            Predicate.isWiped(is: false),
        ])
        return getFetchedResultsControllerForAllJoinsWithinDiscussion(discussionObjectID: discussionObjectID, predicate: predicate, within: context)
    }

    public static func getFetchedResultsControllerForAllJoinsWithinDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, excludedUTIs: [String], within context: NSManagedObjectContext) -> NSFetchedResultsController<FyleMessageJoinWithStatus> {

        var predicates = [NSPredicate]()
        predicates.append(Predicate.isFyleMessageJoinWithStatusInDiscussion(discussionObjectID))
        predicates.append(Predicate.isWiped(is: false))
        predicates.append(contentsOf: excludedUTIs.map({ NSPredicate(Predicate.Key.uti, NotEqualToString: $0) }))
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        return getFetchedResultsControllerForAllJoinsWithinDiscussion(discussionObjectID: discussionObjectID, predicate: predicate, within: context)
    }


    public static func getFetchedResultsControllerForAllJoinsWithinMessage(_ message: PersistedMessage) throws -> NSFetchedResultsController<FyleMessageJoinWithStatus> {
        
        guard let context = message.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        
        let fetchRequest: NSFetchRequest<FyleMessageJoinWithStatus> = FyleMessageJoinWithStatus.fetchRequest()
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: FyleMessageJoinWithStatus.Predicate.Key.index.rawValue, ascending: true),
        ]
        fetchRequest.fetchBatchSize = 500
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isFyleMessageJoinWithStatusOfMessage(message),
            Predicate.isWiped(is: false),
        ])
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        
        return fetchedResultsController
    }

}


// MARK: - Determining actions availability

extension FyleMessageJoinWithStatus {
    
    var copyActionCanBeMadeAvailable: Bool {
        if let receivedJoin = self as? ReceivedFyleMessageJoinWithStatus {
            return receivedJoin.copyActionCanBeMadeAvailableForReceivedJoin
        } else if let sentJoin = self as? SentFyleMessageJoinWithStatus {
            return sentJoin.copyActionCanBeMadeAvailableForSentJoin
        } else {
            assertionFailure("Unexpected FyleMessageJoinWithStatus subclass")
            return false
        }
    }
    
    public var shareActionCanBeMadeAvailable: Bool {
        if let receivedJoin = self as? ReceivedFyleMessageJoinWithStatus {
            return receivedJoin.shareActionCanBeMadeAvailableForReceivedJoin
        } else if let sentJoin = self as? SentFyleMessageJoinWithStatus {
            return sentJoin.shareActionCanBeMadeAvailableForSentJoin
        } else {
            assertionFailure("Unexpected FyleMessageJoinWithStatus subclass")
            return false
        }
    }
    
    
    public var deleteActionCanBeMadeAvailable: Bool {
        if isPreviewType {
            return false
        } else {
            return true
        }
    }
    
}
