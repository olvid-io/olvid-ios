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


struct JsonZipDiscussion {
    let discussionIdentifier: JsonDiscussionIdentifier
    let discussionTitle: String?
    
    init(discussionIdentifier: JsonDiscussionIdentifier, discussionTitle: String?) {
        self.discussionIdentifier = discussionIdentifier
        self.discussionTitle = discussionTitle
    }
    
}


// MARK: - Implementing Codable

extension JsonZipDiscussion: Codable {
    
    enum CodingKeys: String, CodingKey {
        case discussionIdentifier = "discussion"
        case discussionTitle = "title"
    }
    
}


// MARK: - Helpers

extension JsonZipDiscussion {
    
    init(srcDiscussionRanges: SrcDiscussionRanges) {
        self.init(discussionIdentifier: srcDiscussionRanges.discussionIdentifier,
                  discussionTitle: srcDiscussionRanges.discussionTitle)
        
    }
    
}
