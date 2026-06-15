/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvAppTypes
import ObvTypes


extension ObvAppTypes.UpdateMessageJSON {
    
    public init(persistedMessageSentToEdit msg: PersistedMessageSent,
                newBodyAndMentions: StringAndUserMentions?,
                locationJSON: LocationJSON?) throws {
        guard let msgRef = msg.toMessageReferenceJSON() else {
            throw ObvErrorCoreData.couldNotCreateMessageReferenceJSON
        }
        guard let discussion = msg.discussion else {
            throw ObvErrorCoreData.discussionIsNil
        }
        let messageToEdit = msgRef
        let locationJSON = locationJSON
        let discussionIdentifier = try discussion.discussionIdentifier
        self.init(discussionIdentifier: discussionIdentifier,
                  messageToEdit: messageToEdit,
                  newBodyAndMentions: newBodyAndMentions,
                  locationJSON: locationJSON)
    }
    
}


extension ObvAppTypes.UpdateMessageJSON {
    
    public enum ObvErrorCoreData: Error {
        case couldNotCreateMessageReferenceJSON
        case discussionIsNil
        case couldNotFindDiscussionKind
        case couldNotCastDiscussion
        case couldNotDetermineGroupV1Uid
        case couldNotDetermineGroupV2Uid
    }
    
}
