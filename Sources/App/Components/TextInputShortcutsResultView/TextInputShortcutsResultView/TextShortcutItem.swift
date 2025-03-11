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
import ObvUIObvCircledInitials

@available(iOSApplicationExtension 14.0, *)
public extension TextInputShortcutsResultView {
    /// Represents a shortcut item
    /// A shortcut item is something invoked when the user enters a special keystroke (i.e. `@` for mentions, `:` for emojis, etc.)
    struct TextShortcutItem: Hashable {
        /// Available accessories for text shortcuts
        ///
        /// - `circledInitialsView`: Represents the configuration for `NewCircledInitialsView`. See also `CircledInitialsConfiguration`
        public enum Accessory: Hashable {
            /// Represents the configuration for `NewCircledInitialsView`. See also `CircledInitialsConfiguration`
            case circledInitialsView(configuration: CircledInitialsConfiguration)
        }

        /// The user-facing visible title that will be presented from a dropdown menu
        public let title: String

        /// A user-facing subtitle that will be presented from a dropdown menu
        public let subtitle: String?

        /// An optional accessory associated with ``title``
        public let accessory: Accessory?

        /// The actual value that will be rendered within the text
        /// An instance of `NSAttributedString` is exposed as such to pass special attributes
        ///
        /// - SeeAlso: `NSAttributedString.Key`
        public let value: NSAttributedString

        /// The range that should be replaced by ``TextInputShortcutsResultView/TextShortcutItem/value``
        public let range: NSRange

        /// Initializer for `TextShortcutItem`
        /// - Parameters:
        ///   - title: The user-facing visible title that will be presented from a dropdown menu
        ///   - subtitle: A user-facing subtitle that will be presented from a dropdown menu
        ///   - accessory: An optional accessory associated with ``title``
        ///   - value: The actual value that will be rendered within the text. See ``value``
        ///   - range: The range that should be replaced by ``TextInputShortcutsResultView/TextShortcutItem/value``
        public init(title: String, subtitle: String? = nil, accessory: TextShortcutItem.Accessory? = nil, value: NSAttributedString, range: NSRange) {
            self.title = title
            self.subtitle = subtitle
            self.accessory = accessory
            self.value = value
            self.range = range
        }
    }
}
