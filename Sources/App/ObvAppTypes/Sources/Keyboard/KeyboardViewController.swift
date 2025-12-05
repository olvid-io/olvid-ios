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

import UIKit

/// UIViewController subclass used to recognize Key Input on a keyboard and propagate through notifications.
///
/// Warning: For some reason, we were unable to refactor this logic into some kind of KeyboardManager, preventing centralization of `windowKeyCommands` and `keyboardDidInputEscapeKey` in related controllers (KeyboardWindow, KeyboardViewController, and KeyboardHostingController)."
open class KeyboardViewController: UIViewController {

    // MARK: Attributes - Private - Notifications
    private var isRegisteredToKeyboardNotifications = false
    private var keyBoardObservationTokens = [NSObjectProtocol]()
    public override var canBecomeFirstResponder: Bool { true }
    
    private func registerForNotification() {
        guard !isRegisteredToKeyboardNotifications else { return }
        isRegisteredToKeyboardNotifications = true
        
        keyBoardObservationTokens.append(contentsOf: [
            KeyboardNotification.observeKeyboardDidInputEscapeKeyNotification { [weak self] in
                OperationQueue.main.addOperation {
                    self?.escapeKeyPressed()
                }
            },
        ])
    }
    
    // MARK: Life Cycle
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        registerForNotification()
    }
    
    deinit {
        keyBoardObservationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    open func escapeKeyPressed() {
        dismiss(animated: true)
    }
}

open class KeyboardNavigationController: UINavigationController {

    // MARK: Attributes - Private - Notifications
    private var isRegisteredToKeyboardNotifications = false
    private var keyBoardObservationTokens = [NSObjectProtocol]()
    public override var canBecomeFirstResponder: Bool { true }
    
    private func registerForNotification() {
        guard !isRegisteredToKeyboardNotifications else { return }
        isRegisteredToKeyboardNotifications = true
        
        keyBoardObservationTokens.append(contentsOf: [
            KeyboardNotification.observeKeyboardDidInputEscapeKeyNotification { [weak self] in
                OperationQueue.main.addOperation {
                    self?.escapeKeyPressed()
                }
            },
        ])
    }
    
    // MARK: Life Cycle
    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        registerForNotification()
    }
    
    deinit {
        keyBoardObservationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    open func escapeKeyPressed() {
        if viewControllers.count <= 1 {
            self.dismiss(animated: true)
        } else {
            self.popViewController(animated: true)
        }
    }
}

open class KeyboardTableViewController: UITableViewController {

    // MARK: Attributes - Private - Notifications
    private var isRegisteredToKeyboardNotifications = false
    private var keyBoardObservationTokens = [NSObjectProtocol]()
    public override var canBecomeFirstResponder: Bool { true }
    
    private func registerForNotification() {
        guard !isRegisteredToKeyboardNotifications else { return }
        isRegisteredToKeyboardNotifications = true
        
        keyBoardObservationTokens.append(contentsOf: [
            KeyboardNotification.observeKeyboardDidInputEscapeKeyNotification { [weak self] in
                OperationQueue.main.addOperation {
                    self?.escapeKeyPressed()
                }
            },
        ])
    }
    
    // MARK: Life Cycle
    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        registerForNotification()
    }
    
    deinit {
        keyBoardObservationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    open func escapeKeyPressed() {
        dismiss(animated: true)
    }
}
