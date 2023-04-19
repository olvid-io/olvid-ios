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


/// This operation deletes enough messages (and their attachments) to make sure the discussion contains no more messages than its count based retention policy (if any).
final class DeleteMessagesWithExpiredCountBasedRetentionOperation: OperationWithSpecificReasonForCancel<DeleteMessagesWithExpiredCountBasedRetentionOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: DeleteMessagesWithExpiredCountBasedRetentionOperation.self))

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
                                
                guard let countBasedRetention = discussion.effectiveCountBasedRetention else { continue }

                // If we reach this point, there is a count based retention policy for the discussion.
                // We first check the total number of messages in the discussion. We add up:
                // - all outbound messages that are sent
                // - all inbound messages that are not new
                
                var totalNumberOfMessagesInDiscussion = 0
                
                do {
                    totalNumberOfMessagesInDiscussion += try PersistedMessageSent.countAllSentMessages(discussion: discussion)
                } catch {
                    os_log("Could not count sent messages: %{public}@", log: log, type: .fault, error.localizedDescription)
                    continue
                }
                do {
                    totalNumberOfMessagesInDiscussion += try PersistedMessageReceived.countAllNonNewMessages(discussion: discussion)
                } catch {
                    os_log("Could not get received messages to delete: %{public}@", log: log, type: .fault, error.localizedDescription)
                    // We continue anyway
                }
                
                guard totalNumberOfMessagesInDiscussion > countBasedRetention else { continue }
                
                // If we reach this point, the discussion contains more messages than the count based retention policy. We should delete a few messages.
                
                let numberOfMessagesToDelete = totalNumberOfMessagesInDiscussion - countBasedRetention

                do {
                    try PersistedMessage.deleteFirstMessages(discussion: discussion, count: numberOfMessagesToDelete)
                } catch {
                    os_log("Could not respect time based retention policy: deletion of %{public}d messages failed: %{public}@", log: log, type: .fault, numberOfMessagesToDelete, error.localizedDescription)
                    // We continue anyway
                }
                
            }
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

        }
        
    }
    
}


enum DeleteMessagesWithExpiredCountBasedRetentionOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    
    var logType: OSLogType {
        switch self {
        case .coreDataError:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }
    
}
