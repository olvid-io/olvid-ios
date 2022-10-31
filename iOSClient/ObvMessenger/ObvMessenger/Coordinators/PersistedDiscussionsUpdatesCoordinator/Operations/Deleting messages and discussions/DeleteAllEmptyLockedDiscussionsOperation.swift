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


final class DeleteAllEmptyLockedDiscussionsOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
 
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: DeleteAllEmptyLockedDiscussionsOperation.self))

    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {

            let persistedDiscussionLockedWithNoMessage: [PersistedDiscussion]
            do {
                persistedDiscussionLockedWithNoMessage = try PersistedDiscussion.getAllLockedWithNoMessage(within: obvContext.context)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            guard !persistedDiscussionLockedWithNoMessage.isEmpty else { return }
            for discussion in persistedDiscussionLockedWithNoMessage {
                do {
                    try discussion.deleteDiscussion(requester: nil)
                } catch {
                    os_log("One of the empty locked discussion could not be deleted", log: log, type: .fault)
                }
            }

        }
        
    }

}
