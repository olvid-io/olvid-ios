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

import UIKit

/// Extension containing default values used for decorating attributed strings
public extension NSAttributedString.Key {
    /// Returns the default attributes to be used for the text input when the user types a mention
    static let compositionMentionAttributes: [Self: Any] = {
        return [.font: UIFont.preferredFont(forTextStyle: .body, compatibleWith: .init(legibilityWeight: .bold)),
                .foregroundColor: UIColor.systemBlue] // temporary workaround, we don't have an actual tint color set for our toolbar, so it's the system's
    }()

    /// Returns the default attributes for a mention within a sent message
    static let sentMessageMentionAttributes: [Self: Any] = {
        return [.font: UIFont.preferredFont(forTextStyle: .body, compatibleWith: .init(legibilityWeight: .bold)),
                .foregroundColor: UIColor.white] // determine appropriate color, the theme color is wrong
    }()

    /// Returns the default attributes for a mention within a received message
    static let receivedMessageMentionAttributes: [Self: Any] = {
        return [.font: UIFont.preferredFont(forTextStyle: .body, compatibleWith: .init(legibilityWeight: .bold)),
                .foregroundColor: UIColor.systemBlue] // temporary workaround, we don't have an actual tint color set for our toolbar, so it's the system's
    }()
}
