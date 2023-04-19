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
import OlvidUtils


/// This operation is typically called when the user selects several "attachments" (more precisely, `FyleMessageJoinWithStatus` instances) in the gallery of a discussion, and then requests their deletion. In practice, these joins are wiped.
final class WipeFyleMessageJoinsWithStatusOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, OperationProvidingPersistedMessageObjectIDsToDelete, ObvErrorMaker {
    
    private let joinObjectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>
    static let errorDomain = "WipeFyleMessageJoinsWithStatusOperation"
    
    /// When wiping an attachment (aka `FyleMessageJoinWithStatus`), we might end with an "empty" message. In that case we want to delete this message atomically.
    /// We do *not* delete this message in this operation. Instead we add its objectID to this set. The coordinator is in charge of queueing the appropriate operation that will delete
    /// the message properly.
    private(set) var persistedMessageObjectIDsToDelete = Set<TypeSafeManagedObjectID<PersistedMessage>>()
    let requester: RequesterOfMessageDeletion
    private let queueForPostingNotifications = DispatchQueue(label: "WipeFyleMessageJoinsWithStatusOperation internal queue for posting notifications")
    
    init(joinObjectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>, requester: RequesterOfMessageDeletion) {
        self.joinObjectIDs = joinObjectIDs
        self.requester = requester
        super.init()
    }
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        guard !joinObjectIDs.isEmpty else { return }
        
        switch requester {
        case .ownedIdentity:
            break
        case .contact:
            assertionFailure()
            return cancel(withReason: .coreDataError(error: Self.makeError(message: "Unexpected deletion requester")))
        }
        
        obvContext.performAndWait {
            
            do {
                
                for joinObjectID in joinObjectIDs {
                    
                    guard let join = try FyleMessageJoinWithStatus.get(objectID: joinObjectID.objectID, within: obvContext.context) else { continue }
                    
                    if let sentJoin = join as? SentFyleMessageJoinWithStatus {
                        do {
                            try sentJoin.wipe()
                            if sentJoin.sentMessage.shouldBeDeleted {
                                persistedMessageObjectIDsToDelete.insert(sentJoin.sentMessage.typedObjectID.downcast)
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
                                
                    if let discussionPermanentID = join.message?.discussion.discussionPermanentID,
                       let messagePermanentID = join.message?.messagePermanentID {
                        let fyleMessageJoinPermanentID = join.fyleMessageJoinPermanentID
                        do {
                            let queueForPostingNotifications = self.queueForPostingNotifications
                            try obvContext.addContextDidSaveCompletionHandler { error in
                                guard error == nil else { return }
                                ObvMessengerCoreDataNotification.fyleMessageJoinWasWiped(discussionPermanentID: discussionPermanentID,
                                                                                         messagePermanentID: messagePermanentID,
                                                                                         fyleMessageJoinPermanentID: fyleMessageJoinPermanentID)
                                .postOnDispatchQueue(queueForPostingNotifications)
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
    
}
