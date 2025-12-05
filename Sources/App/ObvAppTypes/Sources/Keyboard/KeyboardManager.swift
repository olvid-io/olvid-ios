/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import UIKit

open class KeyboardManager: NSObject {
    
    public static var shared: KeyboardManager = KeyboardManager()
    
    var windowKeyCommands = [
        UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(UIViewController.keyboardDidInputEscapeKey))
    ]
}

extension UIViewController {
    
    override open var keyCommands: [UIKeyCommand]? {
        var commands = super.keyCommands ?? []
        
        commands += KeyboardManager.shared.windowKeyCommands
        
        return commands
    }
    
    @objc
    static func keyboardDidInputEscapeKey(_ sender: Any?) {
        KeyboardNotification.keyboardDidInputEscapeKeyNotification.postOnDispatchQueue()
    }
    
}

extension UIWindow {
    
    open override var keyCommands: [UIKeyCommand]? {
        var commands = super.keyCommands ?? []
        
        commands += KeyboardManager.shared.windowKeyCommands
        
        return commands
    }
    
    @objc
    func keyboardDidInputEscapeKey(_ sender: Any?) {
        KeyboardNotification.keyboardDidInputEscapeKeyNotification.postOnDispatchQueue()
    }
    
}

