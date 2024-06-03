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

// MARK: - Convenience DB getters

extension PersistedMessage.Predicate {
    static func inboundMessageThatIsNotNewAnymore(within context: NSManagedObjectContext) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            isInboundMessage(within: context),
            PersistedMessageReceived.Predicate.isNotNewAnymore,
        ])
    }
    static func withSectionIdentifier(_ sectionIdentifier: String) -> NSPredicate {
        NSPredicate(Key.sectionIdentifier, EqualToString: sectionIdentifier)
    }
    static func outboundMessageThatWasSent(within context: NSManagedObjectContext) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            isOutboundMessage(within: context),
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

    
    public static func getAll(with objectIDs: [NSManagedObjectID], within context: NSManagedObjectContext) throws -> [PersistedMessage] {
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

    
    public static func getLastMessage(in discussion: PersistedDiscussion) throws -> PersistedMessage? {
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
    
    public static func getFetchRequestPredicateForAllMessagesWithinDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, includeMembersOfGroupV2WereUpdated: Bool, within context: NSManagedObjectContext) -> NSPredicate {
        
        if includeMembersOfGroupV2WereUpdated {
            return Predicate.withinDiscussion(discussionObjectID)
        } else {
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withinDiscussion(discussionObjectID),
                NSCompoundPredicate(notPredicateWithSubpredicate: Predicate.isSystemMessageForMembersOfGroupV2WereUpdated(within: context))
            ])
        }

    }

    
    private static func getFetchRequestForAllMessagesWithinDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, includeMembersOfGroupV2WereUpdated: Bool, within context: NSManagedObjectContext) -> FetchRequestControllerModel<PersistedMessage> {
        
        let fetchRequest: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        
        fetchRequest.predicate = Self.getFetchRequestPredicateForAllMessagesWithinDiscussion(
            discussionObjectID: discussionObjectID,
            includeMembersOfGroupV2WereUpdated: includeMembersOfGroupV2WereUpdated,
            within: context)
        
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: true)]
        fetchRequest.fetchBatchSize = 500
        // 2024-02-27 Commenting the following lines
//        fetchRequest.propertiesToFetch = [
//            Predicate.Key.body.rawValue,
//            Predicate.Key.rawStatus.rawValue,
//            Predicate.Key.rawVisibilityDuration.rawValue,
//            Predicate.Key.readOnce.rawValue,
//            Predicate.Key.sectionIdentifier.rawValue,
//            Predicate.Key.senderSequenceNumber.rawValue,
//            Predicate.Key.sortIndex.rawValue,
//            Predicate.Key.timestamp.rawValue,
//        ]
        //fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.shouldRefreshRefetchedObjects = true

        return .init(fetchRequest: fetchRequest, sectionNameKeyPath: Predicate.Key.sectionIdentifier.rawValue)
        
    }

    
    /// Method used when navigating to a single discussion, to populate all the cells of a single discussion collection view.
    public static func getFetchedResultsControllerForAllMessagesWithinDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, includeMembersOfGroupV2WereUpdated: Bool, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedMessage> {
        let fetchRequestModel = Self.getFetchRequestForAllMessagesWithinDiscussion(
            discussionObjectID: discussionObjectID,
            includeMembersOfGroupV2WereUpdated: includeMembersOfGroupV2WereUpdated,
            within: context)
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequestModel.fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: fetchRequestModel.sectionNameKeyPath,
                                                                  cacheName: nil)
        return fetchedResultsController
    }
    
    
    public static func searchForAllMessagesWithinDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, searchTerm: String, within context: NSManagedObjectContext) throws -> [TypeSafeManagedObjectID<PersistedMessage>] {
        
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: Self.globalEntityName)
        request.resultType = .managedObjectIDResultType
        
        var subPredicates = [Predicate.withinDiscussion(discussionObjectID)]
        do {
            let searchTerms = searchTerm.trimmingWhitespacesAndNewlines().split(separator: " ").map({ String($0) })
            let searchTermsPredicates = searchTerms.map({ Predicate.whereBodyContains(searchTerm: $0) })
            let searchTermsPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: searchTermsPredicates)
            subPredicates.append(searchTermsPredicate)
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subPredicates)
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: true)]
        
        let objectIDs = try context.fetch(request) as? [NSManagedObjectID] ?? []
        
        let returnedValues = objectIDs.map { TypeSafeManagedObjectID<PersistedMessage>(objectID: $0) }

        return returnedValues
        
    }


    /// This method deletes the first outbound/inbound messages of the discussion, up to the `count` parameter.
    /// Outbound messages only concerns sent messages. Inbound messages only concerns non-new messages.
    public static func deleteFirstMessages(discussion: PersistedDiscussion, count: Int) throws {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        guard count > 0 else { return }
        let fetchRequest: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: true)]
        fetchRequest.fetchLimit = count
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                Predicate.outboundMessageThatWasSent(within: context),
                Predicate.inboundMessageThatIsNotNewAnymore(within: context),
            ]),
        ])
        let messages = try context.fetch(fetchRequest)
        messages.forEach { context.delete($0) }
    }

}


// MARK: - Determining actions availability

extension PersistedMessage {
    
    public var copyActionCanBeMadeAvailable: Bool {
        if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.copyActionCanBeMadeAvailableForReceivedMessage
        } else if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.copyActionCanBeMadeAvailableForSentMessage
        } else {
            return false
        }
    }

    public var shareActionCanBeMadeAvailable: Bool {
        if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.shareActionCanBeMadeAvailableForReceivedMessage
        } else if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.shareActionCanBeMadeAvailableForSentMessage
        } else {
            return false
        }
    }
    
    public var forwardActionCanBeMadeAvailable: Bool {
        if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.forwardActionCanBeMadeAvailableForReceivedMessage
        } else if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.forwardActionCanBeMadeAvailableForSentMessage
        } else {
            return false
        }
    }
    
    public var infoActionCanBeMadeAvailable: Bool {
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
    
    public var replyToActionCanBeMadeAvailable: Bool {
        assert(Thread.isMainThread)
        
        guard !self.isWiped else { return false }
        
        do {
            
            guard let context = self.managedObjectContext else {
                assertionFailure()
                return false
            }
            guard context.concurrencyType == .mainQueueConcurrencyType else {
                assertionFailure()
                return false
            }

            let childViewContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            childViewContext.parent = context
            
            guard let selfInChildViewContext = try? PersistedMessage.get(with: self.typedObjectID, within: childViewContext) else {
                assertionFailure()
                return false
            }
            
            guard let discussionInChildViewContext = selfInChildViewContext.discussion else {
                assertionFailure()
                return false
            }
            
            // Simulate the creation of a reply to make sure we are allowed to do so.
            _ = try PersistedMessageSent.createPersistedMessageSentWhenReplyingFromTheNotificationExtensionNotification(body: "", discussion: discussionInChildViewContext, effectiveReplyTo: selfInChildViewContext as? PersistedMessageReceived)
            
        } catch {
            return false
        }
        
        return true

    }

    /// Returns `true` iff the edit body action can be made available for this message. This is expected to be called on the main thread to allow the UI to determine if the edit action can be shown to the user.
    ///
    /// We implement this by simulating what would happen if the edit action was performed. We return `true` iff the call succeeds. This is performed on a child view context to prevent any unwanted side-effect.
    public var editBodyActionCanBeMadeAvailable: Bool {
        if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.editBodyActionCanBeMadeAvailableForSentMessage
        } else {
            return false
        }
    }
    
    public var callActionCanBeMadeAvailable: Bool {
        if let systemMessage = self as? PersistedMessageSystem {
            return systemMessage.callActionCanBeMadeAvailableForSystemMessage
        } else {
            return false
        }
    }
    

    public var deleteOwnReactionActionCanBeMadeAvailable: Bool {
        if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.deleteOwnReactionActionCanBeMadeAvailableForReceivedMessage
        } else if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.deleteOwnReactionActionCanBeMadeAvailableForSentMessage
        } else {
            return false
        }
    }
    
    
    /// This is expected to be called from the UI in order to determine which deletion types can be shown.
    ///
    /// This is implemented by creating a child context in which we simulate the deletion of the message.
    /// Of course, the child context is not saved to prevent any side-effect (view contexts are never saved anyway).
    public var deletionTypesThatCanBeMadeAvailableForThisMessage: Set<DeletionType> {
        assert(Thread.isMainThread)
        
        guard let context = self.managedObjectContext else {
            assertionFailure()
            return Set()
        }
        guard context.concurrencyType == .mainQueueConcurrencyType else {
            assertionFailure()
            return Set()
        }
        
        var acceptableDeletionTypes = Set<DeletionType>()
        
        for deletionType in DeletionType.allCases {
            
            let childViewContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            childViewContext.parent = context
            guard let messageInChildViewContext = try? PersistedMessage.get(with: self.typedObjectID, within: childViewContext) else {
                assertionFailure()
                return Set()
            }
            guard let discussionInChildViewContext = messageInChildViewContext.discussion else {
                assertionFailure()
                return Set()
            }
            guard let ownedIdentityInChildViewContext = discussionInChildViewContext.ownedIdentity else {
                assertionFailure()
                return Set()
            }

            do {
                _ = try ownedIdentityInChildViewContext.processMessageDeletionRequestRequestedFromCurrentDeviceOfThisOwnedIdentity(persistedMessageObjectID: messageInChildViewContext.objectID, deletionType: deletionType)
                acceptableDeletionTypes.insert(deletionType)
            } catch {
                continue
            }
            
        }
        
        return acceptableDeletionTypes
    }

}
