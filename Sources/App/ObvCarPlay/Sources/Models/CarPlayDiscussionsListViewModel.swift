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
import UIKit
import ObvDesignSystem
import ObvSystemIcon

public struct CarPlayDiscussionsListViewModel: Sendable, Equatable {
    
    let ownedCryptoId: ObvCryptoId
    let discussions: [CarPlayDiscussionViewModel]
    
    public init(ownedCryptoId: ObvCryptoId, discussions: [CarPlayDiscussionViewModel]) {
        self.ownedCryptoId = ownedCryptoId
        self.discussions = discussions
    }
    
    var isEmpty: Bool {
        return discussions.isEmpty
    }
    
}

public struct CarPlayDiscussionViewModel: Sendable, Equatable {
    
    let conversationIdentifier: String?
    let title: String
    let subtitle: String?
    /// The date of the latest message of the discussion. Kept as a date rather than as a formatted string: the format
    /// depends on the current calendar day, so only the list showing it knows when it must be recomputed.
    let latestMessageDate: Date?
    let image: UIImage?
    let unread: Bool
    let isPinned: Bool


    public init(
        conversationIdentifier: String?,
        title: String,
        subtitle: String?,
        latestMessageDate: Date?,
        image: UIImage?,
        unread: Bool,
        isPinned: Bool
    ) {
        self.conversationIdentifier = conversationIdentifier
        self.title = title
        self.subtitle = subtitle
        self.latestMessageDate = latestMessageDate
        self.image = image
        self.unread = unread
        self.isPinned = isPinned
    }
    
}
