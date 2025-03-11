/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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

/// UIViewController subclass used to recognize Key Input on a keyboard and propagate through notifications.
///
/// Warning: For some reason, we were unable to refactor this logic into some kind of KeyboardManager, preventing centralization of `windowKeyCommands` and `keyboardDidInputEscapeKey` in related controllers (KeyboardWindow, KeyboardViewController, and KeyboardHostingController)."
open class KeyboardViewController: UIViewController {

    private lazy var windowKeyCommands = [
        UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(keyboardDidInputEscapeKey))
    ]
    
    open override var keyCommands: [UIKeyCommand]? {
        var commands = super.keyCommands ?? []
        
        commands += windowKeyCommands
        
        return commands
    }
    
    @objc
    func keyboardDidInputEscapeKey(_ sender: Any?) {
        KeyboardNotification.keyboardDidInputEscapeKeyNotification.postOnDispatchQueue()
    }
}
