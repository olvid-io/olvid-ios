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


final class WipeExpiredMessagesOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: WipeExpiredMessagesOperation.self))

    let launchedByBackgroundTask: Bool
    
    init(launchedByBackgroundTask: Bool) {
        self.launchedByBackgroundTask = launchedByBackgroundTask
        super.init()
    }

    override func main() {
        
        debugPrint("💾 WipeExpiredMessagesOperation")
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            
            var objectIDsOfDiscussionToRefresh = Set<NSManagedObjectID>()
            var objectIDsOfMessagesToRefresh = Set<NSManagedObjectID>()

            var wipedMessageInfos = [(discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>, messageUriRepresentation: TypeSafeURL<PersistedMessage>)]()
            var deletedMessageInfos = [(discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>, messageUriRepresentation: TypeSafeURL<PersistedMessage>)]()

            // Deal with sent messages
            
            do {
                let now = Date()
                let expiredMessages = try PersistedMessageSent.getSentMessagesThatExpired(before: now, within: obvContext.context)
                debugPrint("💾 Found \(expiredMessages.count) expired messages")
                for message in expiredMessages {
                    if let expirationForSentLimitedExistence = message.expirationForSentLimitedExistence, expirationForSentLimitedExistence.expirationDate < now {
                        debugPrint("💾 Found 1 message with expiration for sent limited existence")
                        objectIDsOfDiscussionToRefresh.insert(message.discussion.objectID)
                        do {
                            try message.delete()
                            deletedMessageInfos.append((message.discussion.typedObjectID.uriRepresentation(), message.typedObjectID.downcast.uriRepresentation()))
                        } catch {
                            os_log("Could not delete message", log: log, type: .fault)
                        }
                    } else if let expirationForSentLimitedVisibility = message.expirationForSentLimitedVisibility, expirationForSentLimitedVisibility.expirationDate < now {
                        debugPrint("💾 Found 1 message with expiration for sent limited visibility")
                        if expirationForSentLimitedVisibility.retainWipedMessageSent {
                            for join in message.fyleMessageJoinWithStatuses {
                                join.wipe()
                            }
                            do {
                                if !message.isWiped {
                                    try message.wipe()
                                    wipedMessageInfos.append((message.discussion.typedObjectID.uriRepresentation(), message.typedObjectID.downcast.uriRepresentation()))
                                    objectIDsOfMessagesToRefresh.insert(message.objectID)
                                    objectIDsOfDiscussionToRefresh.insert(message.discussion.objectID)
                                }
                            } catch {
                                os_log("Could not wipe a message sent with expired visibility", log: log, type: .fault)
                                assertionFailure()
                                // Continue anyway
                            }
                        } else {
                            objectIDsOfDiscussionToRefresh.insert(message.discussion.objectID)
                            deletedMessageInfos.append((message.discussion.typedObjectID.uriRepresentation(), message.typedObjectID.downcast.uriRepresentation()))
                            obvContext.context.delete(message)
                        }
                    } else {
                        assertionFailure("A message that we fetched because it expired has not expiration before now. Weird.")
                    }
                }
            } catch {
                cancel(withReason: .coreDataError(error: error))
                return
            }

            // Deal with received messages

            do {
                let expiredMessages = try PersistedMessageReceived.getReceivedMessagesThatExpired(within: obvContext.context)
                for message in expiredMessages {
                    objectIDsOfDiscussionToRefresh.insert(message.discussion.objectID)
                    obvContext.context.delete(message)
                    deletedMessageInfos.append((message.discussion.typedObjectID.uriRepresentation(), message.typedObjectID.downcast.uriRepresentation()))
                }
            } catch {
                cancel(withReason: .coreDataError(error: error))
                return
            }

            // Notify on context save
            
            do {
                try obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    
                    // We wiped/deleted some persisted messages. We notify about that.
                    
                    for discussionUriRepresentation in wipedMessageInfos.map({ $0.discussionUriRepresentation }) {
                        let messageUriRepresentations = Set(wipedMessageInfos.filter({ $0.discussionUriRepresentation == discussionUriRepresentation }).map({ $0.messageUriRepresentation }))
                        ObvMessengerCoreDataNotification.persistedMessagesWereWiped(discussionUriRepresentation: discussionUriRepresentation, messageUriRepresentations: messageUriRepresentations)
                            .postOnDispatchQueue()
                    }
                    for discussionUriRepresentation in deletedMessageInfos.map({ $0.discussionUriRepresentation }) {
                        let messageUriRepresentations = Set(deletedMessageInfos.filter({ $0.discussionUriRepresentation == discussionUriRepresentation }).map({ $0.messageUriRepresentation }))
                        ObvMessengerCoreDataNotification.persistedMessagesWereDeleted(discussionUriRepresentation: discussionUriRepresentation, messageUriRepresentations: messageUriRepresentations)
                            .postOnDispatchQueue()
                    }

                    // Refresh objects in the view context
                    
                    if let viewContext = self.viewContext {
                        viewContext.perform {
                            for messageObjectID in objectIDsOfMessagesToRefresh {
                                guard let message = try? PersistedMessage.get(with: messageObjectID, within: viewContext) else { assertionFailure(); continue }
                                viewContext.refresh(message, mergeChanges: false)
                            }
                            for discussionObjectID in objectIDsOfDiscussionToRefresh {
                                guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: viewContext) else { assertionFailure(); continue }
                                viewContext.refresh(discussion, mergeChanges: false)
                            }
                        }
                    }
                    
                }
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }
    
}
