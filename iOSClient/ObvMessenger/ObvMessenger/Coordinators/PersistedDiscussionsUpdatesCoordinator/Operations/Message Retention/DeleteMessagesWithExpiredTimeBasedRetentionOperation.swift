/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


/// This operation deletes all sent/received messages (and attachments) that were sent/received at a time that is longer than their time based retention time (if any).
final class DeleteMessagesWithExpiredTimeBasedRetentionOperation: OperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    private(set) var numberOfDeletedMessages = 0
    
    private let restrictToDiscussionWithObjectID: NSManagedObjectID?
    
    init(restrictToDiscussionWithObjectID: NSManagedObjectID?) {
        self.restrictToDiscussionWithObjectID = restrictToDiscussionWithObjectID
        super.init()
    }
    
    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            let allDiscussions: [PersistedDiscussion]
            do {
                if let discussionObjectID = restrictToDiscussionWithObjectID {
                    guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: context) else {
                        /// We allow here that this given discussion no longer exists
                        return
                    }
                    allDiscussions = [discussion]
                } else {
                    allDiscussions = try PersistedDiscussion.getAllSortedByTimestampOfLastMessage(within: context)
                }
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

            for discussion in allDiscussions {
                
                var localNumberOfDeletions = 0
                
                guard let discussionRetentionDate = discussion.effectiveTimeBasedRetentionDate else { continue }
                // If we reach this point:
                // - all sent messages prior the date should be deleted
                // - all non-new inbound messages that were received prior the date should be deleted
                do {
                    let messages = try PersistedMessageSent.getAllSentMessagesCreatedBeforeDate(discussion: discussion, date: discussionRetentionDate)
                    localNumberOfDeletions += messages.count
                    messages.forEach({ context.delete($0) })
                } catch {
                    os_log("Could not get sent messages to delete: %{public}@", log: log, type: .fault, error.localizedDescription)
                    // We continue anyway
                }
                do {
                    let messages = try PersistedMessageReceived.getAllNonNewReceivedMessagesCreatedBeforeDate(discussion: discussion, date: discussionRetentionDate)
                    localNumberOfDeletions += messages.count
                    messages.forEach({ context.delete($0) })
                } catch {
                    os_log("Could not get received messages to delete: %{public}@", log: log, type: .fault, error.localizedDescription)
                    // We continue anyway
                }
                
                // We save the context each time the work is done for a specific discussion
                do {
                    try context.save(logOnFailure: log)
                } catch {
                    cancel(withReason: .coreDataError(error: error))
                    return
                }
                
                numberOfDeletedMessages += localNumberOfDeletions
                
            }
            
        }
        
    }
    
}
