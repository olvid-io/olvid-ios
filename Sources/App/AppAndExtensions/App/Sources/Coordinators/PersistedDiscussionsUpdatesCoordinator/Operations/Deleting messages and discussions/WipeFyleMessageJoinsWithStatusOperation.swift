/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import OlvidUtils
import ObvUICoreData
import ObvTypes
import CoreData


/// This operation is typically called when the user selects several "attachments" (more precisely, `FyleMessageJoinWithStatus` instances) in the gallery of a discussion, and then requests their deletion. In practice, these joins are wiped.
final class WipeFyleMessageJoinsWithStatusOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable, OperationProvidingPersistedMessageObjectIDsToDelete {
    
    private let joinObjectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>
    
    /// When wiping an attachment (aka `FyleMessageJoinWithStatus`), we might end with an "empty" message. In that case we want to delete this message atomically.
    /// We do *not* delete this message in this operation. Instead we add its objectID to this set. The coordinator is in charge of queueing the appropriate operation that will delete
    /// the message properly.
    private(set) var persistedMessageObjectIDsToDelete = Set<TypeSafeManagedObjectID<PersistedMessage>>()
    let ownedCryptoId: ObvCryptoId
    let deletionType: DeletionType
    private let queueForPostingNotifications = DispatchQueue(label: "WipeFyleMessageJoinsWithStatusOperation internal queue for posting notifications")
    
    init(joinObjectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>, ownedCryptoId: ObvCryptoId, deletionType: DeletionType) {
        self.joinObjectIDs = joinObjectIDs
        self.ownedCryptoId = ownedCryptoId
        self.deletionType = deletionType
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        guard !joinObjectIDs.isEmpty else { return }
        
        do {
            
            for joinObjectID in joinObjectIDs {
                
                guard let join = try FyleMessageJoinWithStatus.get(objectID: joinObjectID.objectID, within: obvContext.context) else { continue }
                
                var messagesToRefreshInViewContext = Set<TypeSafeManagedObjectID<PersistedMessage>>()
                
                if let sentJoin = join as? SentFyleMessageJoinWithStatus {
                    do {
                        try sentJoin.wipe()
                        if sentJoin.sentMessage.shouldBeDeleted {
                            persistedMessageObjectIDsToDelete.insert(sentJoin.sentMessage.typedObjectID.downcast)
                        } else {
                            messagesToRefreshInViewContext.insert(sentJoin.sentMessage.typedObjectID.downcast)
                        }
                    } catch {
                        assertionFailure()
                        continue
                    }
                } else if let receivedJoin = join as? ReceivedFyleMessageJoinWithStatus {
                    do {
                        try receivedJoin.wipe()
                        if receivedJoin.receivedMessage.shouldBeDeleted {
                            persistedMessageObjectIDsToDelete.insert(receivedJoin.receivedMessage.typedObjectID.downcast)
                        } else {
                            messagesToRefreshInViewContext.insert(receivedJoin.receivedMessage.typedObjectID.downcast)
                        }
                    } catch {
                        assertionFailure()
                        continue
                    }
                } else {
                    assertionFailure("Unexpected FyleMessageJoinWithStatus subclass")
                    continue
                }
                
                // If the context is successfully saved, we want to notify that the join was wiped (so as to deleted hard links)
                
                if let discussionPermanentID = join.message?.discussion?.discussionPermanentID,
                   let messagePermanentID = join.message?.messagePermanentID {
                    let fyleMessageJoinPermanentID = join.fyleMessageJoinPermanentID
                    do {
                        let queueForPostingNotifications = self.queueForPostingNotifications
                        try obvContext.addContextDidSaveCompletionHandler { error in
                            guard error == nil else { return }
                            ObvMessengerInternalNotification.fyleMessageJoinWasWiped(discussionPermanentID: discussionPermanentID,
                                                                                     messagePermanentID: messagePermanentID,
                                                                                     fyleMessageJoinPermanentID: fyleMessageJoinPermanentID)
                            .postOnDispatchQueue(queueForPostingNotifications)
                        }
                    } catch {
                        assertionFailure() // Continue anyway
                    }
                }
                
                // Since we modified attachments, we probably need to refresh their associated messages.
                // All the messages that need to be refreshed in the view context are indicated in messagesToRefreshInViewContext.
                // In the following completion handler, we look for those that are indeed registered in the view context and refresh them.
                // If a refreshed message is an illustrative message for a discussion (and, as such, does appear in the list of recent discussions),
                // we also refresh the associated discussion.
                
                if !messagesToRefreshInViewContext.isEmpty {
                    do {
                        try obvContext.addContextDidSaveCompletionHandler { error in
                            guard error == nil else { return }
                            ObvStack.shared.viewContext.perform {
                                let messagesInViewContext = ObvStack.shared.viewContext.registeredObjects
                                    .filter({ !$0.isDeleted })
                                    .compactMap({ $0 as? PersistedMessage })
                                    .filter({ messagesToRefreshInViewContext.contains($0.typedObjectID) })
                                for message in messagesInViewContext {
                                    ObvStack.shared.viewContext.refresh(message, mergeChanges: false)
                                    if let discussion = message.discussion, discussion.illustrativeMessage == message {
                                        // The refreshed message is the illustrative message of its discussion. If that discussion is registered in the view context, we refresh it.
                                        if let discussionInViewContext = ObvStack.shared.viewContext.registeredObjects
                                            .filter({ !$0.isDeleted })
                                            .first(where: { $0.objectID == discussion.objectID }) {
                                            ObvStack.shared.viewContext.refresh(discussionInViewContext, mergeChanges: false)
                                        }
                                        
                                    }
                                }
                            }
                        }
                    } catch {
                        assertionFailure() // Continue anyway
                    }
                }
                
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
