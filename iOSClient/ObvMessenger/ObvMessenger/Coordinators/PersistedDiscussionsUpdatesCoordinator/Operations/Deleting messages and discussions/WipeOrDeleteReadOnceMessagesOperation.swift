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
import ObvUICoreData

/// This operation is typically executed when the user leaves a discussion. In that case, we may have read once messages that can be deleted or wiped.
/// For outbound messages, we delete all readOnce messages that are marked as "sent".
/// For inbound messages, we delete all readOnce messages that are marked as "read".
final class WipeOrDeleteReadOnceMessagesOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: WipeOrDeleteReadOnceMessagesOperation.self))
    
    /// If `true`, received messages remain untouched. Typically `true` when starting Olvid, and `false` when going to background.
    /// Setting this value to `true` makes it possible to avoid deleting messages when entering fast (e.g. by tapping a notification) in a discussion in auto-read mode.
    private let preserveReceivedMessages: Bool
    
    /// If set, we only consider messages within this discussion
    private let restrictToDiscussionWithPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>?
    
    init(preserveReceivedMessages: Bool, restrictToDiscussionWithPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>?) {
        self.preserveReceivedMessages = preserveReceivedMessages
        self.restrictToDiscussionWithPermanentID = restrictToDiscussionWithPermanentID
        super.init()
    }
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {

            // We deal with sent messages
            
            let sentMessages: [PersistedMessageSent]
            do {
                sentMessages = try PersistedMessageSent.getReadOnceThatWasSent(
                    restrictToDiscussionWithPermanentID: restrictToDiscussionWithPermanentID,
                    within: obvContext.context)
            } catch {
                os_log("Could not get all readOnce sent messages that should be deleted: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                cancel(withReason: .coreDataError(error: error))
                return
            }

            var infos = [InfoAboutWipedOrDeletedPersistedMessage]()

            for sentMessage in sentMessages {
                do {
                    let info = try sentMessage.wipeOrDelete(requester: nil)
                    infos += [info]
                } catch {
                    os_log("Could not wipe readOnce sent message: %{public}@", log: log, type: .fault, error.localizedDescription)
                }
            }

            // We deal with received messages
            
            if !preserveReceivedMessages {
            
                let receivedMessages: [PersistedMessageReceived]
                do {
                    receivedMessages = try PersistedMessageReceived.getReadOnceMarkedAsRead(
                        restrictToDiscussionWithPermanentID: restrictToDiscussionWithPermanentID,
                        within: obvContext.context)
                } catch {
                    os_log("Could not get all readOnce received messages that should be deleted: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    cancel(withReason: .coreDataError(error: error))
                    return
                }

                for receivedMessage in receivedMessages {
                    do {
                        let info = try receivedMessage.delete(requester: nil)
                        infos += [info]
                    } catch {
                        os_log("Could not delete readOnce received message: %{public}@", log: log, type: .fault, error.localizedDescription)
                    }
                }
            }
            
            // We notify on context save
            
            do {
                if !infos.isEmpty {
                    try obvContext.addContextDidSaveCompletionHandler { error in
                        guard error == nil else { return }
                        // We wiped/deleted some persisted messages. We notify about that.
                        
                        InfoAboutWipedOrDeletedPersistedMessage.notifyThatMessagesWereWipedOrDeleted(infos)
                        
                        // Refresh objects in the view context
                        if let viewContext = self.viewContext {
                            InfoAboutWipedOrDeletedPersistedMessage.refresh(viewContext: viewContext, infos)
                        }
                    }
                }
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }
}
