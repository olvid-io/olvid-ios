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
import CoreData
import os.log
import OlvidUtils
import ObvUICoreData
import ObvAppCoreConstants


/// This operation deletes all sent/received messages (and attachments) that were sent/received at a time that is longer than their time based retention time (if any).
final class DeleteMessagesWithExpiredTimeBasedRetentionOperation: OperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: DeleteMessagesWithExpiredTimeBasedRetentionOperation.self))

    private(set) var numberOfDeletedMessages = 0
    
    private let restrictToDiscussionWithPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>?
    
    init(restrictToDiscussionWithPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>?) {
        self.restrictToDiscussionWithPermanentID = restrictToDiscussionWithPermanentID
        super.init()
    }
    
    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            let allDiscussions: [PersistedDiscussion]
            do {
                if let discussionPermanentID = restrictToDiscussionWithPermanentID {
                    guard let discussion = try PersistedDiscussion.getManagedObject(withPermanentID: discussionPermanentID, within: context) else {
                        /// We allow here that this given discussion no longer exists
                        return
                    }
                    allDiscussions = [discussion]
                } else {
                    allDiscussions = try PersistedDiscussion.getAllSortedByTimestampOfLastMessageForAllOwnedIdentities(within: context)
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
                    assertionFailure()
                    // We continue anyway
                }
                do {
                    let messages = try PersistedMessageReceived.getAllNonNewReceivedMessagesCreatedBeforeDate(discussion: discussion, date: discussionRetentionDate)
                    localNumberOfDeletions += messages.count
                    messages.forEach({ context.delete($0) })
                } catch {
                    os_log("Could not get received messages to delete: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    // We continue anyway
                }
                                
                numberOfDeletedMessages += localNumberOfDeletions
                
            }
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                numberOfDeletedMessages = 0
                return cancel(withReason: .coreDataError(error: error))
            }

        }
        
    }
    
}
