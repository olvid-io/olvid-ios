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
import ObvSettings


extension ObvMessengerSettings.Interface.SendMessageShortcutType {

    /// What this shortcut is called, for the menu on the settings row that chooses it.
    ///
    /// **In the app target rather than beside the enum in `ObvSettings`**, and that is not where it would naturally go. `String(localized:)`
    /// resolves against the bundle of the module it is *written in*, so these two keys — which live in the app's `Localizable.xcstrings` —
    /// would come back as `NAME_OF_ENTER_KEYBOARD_KEY` if this extension were moved next to the type it extends.
    ///
    /// It arrived here when `SendMessageShortcutTableViewController` was deleted, the row that pushed it having become a menu chosen in place.
    ///
    /// The second value names two keys, *Cmd+Enter and Shift+Enter*: under that preference ⇧↩ sends as ⌘↩ does, ↩ being free to mean a newline, and the
    /// menu is the one place a reader can learn it. The key of the string keeps its older name.
    public var description: String {
        switch self {
        case .enter:
            return String(localized: "NAME_OF_ENTER_KEYBOARD_KEY")
        case .commandEnter:
            return String(localized: "NAME_OF_COMMAND_PLUS_ENTER_KEYBOARD_KEY")
        }
    }

}
