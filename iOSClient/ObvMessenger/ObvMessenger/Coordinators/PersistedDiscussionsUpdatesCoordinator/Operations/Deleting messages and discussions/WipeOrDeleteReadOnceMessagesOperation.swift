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

/// This operation is typically called when the user leaves a discussion. In that case, we may have read once messages that can be deleted or wiped.
/// For outbound messages, we delete all readOnce messages that are marked as "sent".
/// For inbound messages, we delete all readOnce messages that are marked as "read".
final class WipeOrDeleteReadOnceMessagesOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: WipeOrDeleteReadOnceMessagesOperation.self))
    
    /// If `true`, received messages remain untouched. Typically `true` when starting Olvid, and `false` when going to background.
    /// Setting this value to `true` makes it possible to avoid deleting messages when entering fast (e.g. by tapping a notification) in a discussion in auto-read mode.
    private let preserveReceivedMessages: Bool
    
    /// If set, we only consider messages within this discussion
    private let restrictToDiscussionWithObjectID: TypeSafeManagedObjectID<PersistedDiscussion>?
    
    init(preserveReceivedMessages: Bool, restrictToDiscussionWithObjectID: TypeSafeManagedObjectID<PersistedDiscussion>?) {
        self.preserveReceivedMessages = preserveReceivedMessages
        self.restrictToDiscussionWithObjectID = restrictToDiscussionWithObjectID
        super.init()
    }
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            
            var wipedMessageInfos = [(discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>, messageUriRepresentation: TypeSafeURL<PersistedMessage>)]()
            var deletedMessageInfos = [(discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>, messageUriRepresentation: TypeSafeURL<PersistedMessage>)]()

            // We deal with sent messages
            
            let sentMessages: [PersistedMessageSent]
            do {
                sentMessages = try PersistedMessageSent.getReadOnceThatWasSent(
                    restrictToDiscussionWithObjectID: restrictToDiscussionWithObjectID,
                    within: obvContext.context)
            } catch {
                os_log("Could not get all readOnce sent messages that should be deleted: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                cancel(withReason: .coreDataError(error: error))
                return
            }

            for sentMessage in sentMessages {
                if sentMessage.retainWipedOutboundMessages {
                    do {
                        try sentMessage.wipe()
                        wipedMessageInfos.append((sentMessage.discussion.typedObjectID.uriRepresentation(), sentMessage.typedObjectID.downcast.uriRepresentation()))
                    } catch {
                        assertionFailure()
                        deletedMessageInfos.append((sentMessage.discussion.typedObjectID.uriRepresentation(), sentMessage.typedObjectID.downcast.uriRepresentation()))
                        do {
                            try sentMessage.delete()
                        } catch {
                            assertionFailure()
                            os_log("Could not properly delete a sent message. Trying to force delete...: %{public}@", log: log, type: .fault, error.localizedDescription)
                            obvContext.context.delete(sentMessage)
                            // Continue anyway
                        }
                    }
                } else {
                    deletedMessageInfos.append((sentMessage.discussion.typedObjectID.uriRepresentation(), sentMessage.typedObjectID.downcast.uriRepresentation()))
                    do {
                        try sentMessage.delete()
                    } catch {
                        assertionFailure()
                        os_log("Could not properly delete a sent message. Trying to force delete...: %{public}@", log: log, type: .fault, error.localizedDescription)
                        obvContext.context.delete(sentMessage)
                        // Continue anyway
                    }
                }
            }

            // We deal with received messages
            
            if !preserveReceivedMessages {
            
                let receivedMessages: [PersistedMessageReceived]
                do {
                    receivedMessages = try PersistedMessageReceived.getReadOnceMarkedAsRead(
                        restrictToDiscussionWithObjectID: restrictToDiscussionWithObjectID,
                        within: obvContext.context)
                } catch {
                    os_log("Could not get all readOnce received messages that should be deleted: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    cancel(withReason: .coreDataError(error: error))
                    return
                }

                receivedMessages.forEach {
                    deletedMessageInfos.append(($0.discussion.typedObjectID.uriRepresentation(), $0.typedObjectID.downcast.uriRepresentation()))
                    do {
                        try $0.delete()
                    } catch {
                        os_log("Could not delete on of the read-once received messages marked as read", log: log, type: .fault)
                        assertionFailure()
                        // Continue anyway
                    }
                }

            }
            
            // We notify on context save
            
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
                }
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }
}
