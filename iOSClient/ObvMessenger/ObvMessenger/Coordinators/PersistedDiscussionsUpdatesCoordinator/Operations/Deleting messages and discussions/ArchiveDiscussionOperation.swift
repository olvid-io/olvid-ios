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


final class ArchiveDiscussionOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>
    let action: Action
    
    enum Action {
        case archive
        case unarchive(updateTimestampOfLastMessage: Bool)
    }
    
    init(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, action: Action) {
        self.discussionPermanentID = discussionPermanentID
        self.action = action
        super.init()
    }
    
    override func main() {
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            do {
                guard let discussion = try PersistedDiscussion.getManagedObject(withPermanentID: discussionPermanentID, within: obvContext.context) else { return }
                switch action {
                case .archive:
                    try discussion.archive()
                case .unarchive(updateTimestampOfLastMessage: let updateTimestampOfLastMessage):
                    if updateTimestampOfLastMessage {
                        // Unarchive and update the timestampOfLastMessage so that the unarchived discussion is shown at the top of the list.
                        // The reasoning behind this is that when a user unarchives a discussion, the intention is to interact with it.
                        // Not updating the timestamp would mean that in a long discussions list, the previously archived discussion would be
                        // shown at the very bottom.
                        discussion.unarchiveAndUpdateTimestampOfLastMessage()
                    } else {
                        discussion.unarchive()
                    }
                }
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
    }
}
