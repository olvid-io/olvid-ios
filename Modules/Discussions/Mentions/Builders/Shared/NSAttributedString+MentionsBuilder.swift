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
import Platform_Base
import ObvUICoreData
import _Discussions_Mentions_Builder_Internals

public extension Dictionary where Key == NSAttributedString.Key, Value == Any {
    /// Returns the necessary attributes for an attributed string suitable for displaying a mention within a user's message entry
    @inlinable
    static func compositionMentionAttributes(_ identity: MentionableIdentity) -> Self {
        return Key.compositionMentionAttributes..{
            $0[.mentionableIdentity] = identity
        }
    }

    /// Returns the necessary attributes for an attributed string suitable for displaying a mention within a message the user sent
    @inlinable
    static func sentMessageMentionAttributes(_ identity: MentionableIdentity) -> Self {
        return Key.sentMessageMentionAttributes..{
            $0[.mentionableIdentity] = identity
        }
    }

    /// Returns the necessary attributes for an attributed string suitable for displaying a mention within a message the user received
    @inlinable
    static func receivedMessageMentionAttributes(_ identity: MentionableIdentity) -> Self {
        return Key.receivedMessageMentionAttributes..{
            $0[.mentionableIdentity] = identity
        }
    }
}
