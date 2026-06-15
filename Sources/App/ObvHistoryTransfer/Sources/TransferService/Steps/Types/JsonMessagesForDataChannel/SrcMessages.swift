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
import ObvTypes


public struct SrcMessages: Sendable {
    
    let discussionIdentifier: JsonDiscussionIdentifier
    let sender: ObvCryptoId
    let threadId: UUID
    let messages: [JsonMessageInThread]
    let missingMessageCount: Int

    public init(discussionIdentifier: JsonDiscussionIdentifier,
                sender: ObvCryptoId,
                threadId: UUID,
                messages: [JsonMessageInThread],
                missingMessageCount: Int) {
        self.discussionIdentifier = discussionIdentifier
        self.sender = sender
        self.threadId = threadId
        self.messages = messages
        self.missingMessageCount = missingMessageCount
    }
    
}


extension SrcMessages: Codable {
    
    enum CodingKeys: String, CodingKey {
        case discussionIdentifier = "discussion"
        case sender = "sender"
        case threadId = "threadId"
        case messages = "messages"
        case missingMessageCount = "missingMessageCount"
    }
    
}
