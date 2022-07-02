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

}


extension FyleMessageJoinWithStatus {
    
    static func getFetchedResultsControllerForAllJoinsWithinDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, restrictToUTIs: [String], within context: NSManagedObjectContext) -> NSFetchedResultsController<FyleMessageJoinWithStatus> {
        
        let fetchRequest: NSFetchRequest<FyleMessageJoinWithStatus> = FyleMessageJoinWithStatus.fetchRequest()
        // To the contrary of what we do, e.g., with `isReceivedFyleMessageJoinWithStatusInDiscussion`, we cannot test whether a `FyleMessageJoinWithStatus` is received or sent.
        // For this reason, we had to replicate the message sort index since a FyleMessageJoinWithStatus has no associated message (only subclasses have).
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: Predicate.Key.messageSortIndex.rawValue, ascending: false),
            NSSortDescriptor(key: FyleMessageJoinWithStatus.Predicate.Key.index.rawValue, ascending: true),
        ]
        fetchRequest.fetchBatchSize = 500
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isFyleMessageJoinWithStatusInDiscussion(discussionObjectID),
            NSCompoundPredicate(orPredicateWithSubpredicates: restrictToUTIs.map({ NSPredicate(Predicate.Key.uti, EqualToString: $0) })),
            Predicate.isWiped(is: false),
        ])
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        
        return fetchedResultsController
    }
    
    
    var fyleElement: FyleElement? {
        if let receivedJoin = self as? ReceivedFyleMessageJoinWithStatus {
            return receivedJoin.fyleElementOfReceivedJoin
        } else if let sentJoin = self as? SentFyleMessageJoinWithStatus {
            return sentJoin.fyleElementOfSentJoin
        } else {
            assertionFailure("Unexpected FyleMessageJoinWithStatus subclass")
            return nil
        }
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
    
    var shareActionCanBeMadeAvailable: Bool {
        if let receivedJoin = self as? ReceivedFyleMessageJoinWithStatus {
            return receivedJoin.shareActionCanBeMadeAvailableForReceivedJoin
        } else if let sentJoin = self as? SentFyleMessageJoinWithStatus {
            return sentJoin.shareActionCanBeMadeAvailableForSentJoin
        } else {
            assertionFailure("Unexpected FyleMessageJoinWithStatus subclass")
            return false
        }
    }
    
}
