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


/// A utility class for customizing the main menu in **iPadOS 26+** and **macOS** environments.
///
/// This class provides methods to extend or modify the system menu bar, including adding custom menu items,
/// keyboard shortcuts, and handling menu actions.
///
/// Note that on iPad, menus are available since iPadOS 26+.
final class ObvMenuController {
    
    init(with builder: UIMenuBuilder) {
        addNavigationCommands(builder)
    }
    
}


extension ObvMenuController {
    
    private func addNavigationCommands(_ builder: UIMenuBuilder) {
        
        // File menu
        
        do {
            
            let keyCommands: [UIKeyCommand] = [
                UIKeyCommand(title: String(localized: "KEY_COMMAND_NEW_MESSAGE"), action: #selector(MainFlowViewController.processUIKeyCommandForNewMessage), input: "N", modifierFlags: .command),
            ]
            
            builder.replaceChildren(ofMenu: .file) { children in
                return keyCommands + children
            }

        }
        
        // View menu
        
        do {
            
            let keyCommands: [UIKeyCommand] = [
                UIKeyCommand(title: String(localized: "Home"), action: #selector(MainFlowViewController.processUIKeyCommandForHome), input: "0", modifierFlags: .command),
                UIKeyCommand(title: String(localized: "Discussions"), action: #selector(MainFlowViewController.processUIKeyCommandForSwitchingToFlowLatestDiscussions), input: "1", modifierFlags: .command),
                UIKeyCommand(title: String(localized: "Contacts"), action: #selector(MainFlowViewController.processUIKeyCommandForSwitchingToFlowContacts), input: "2", modifierFlags: .command),
                UIKeyCommand(title: String(localized: "Groups"), action: #selector(MainFlowViewController.processUIKeyCommandForSwitchingToFlowGroups), input: "3", modifierFlags: .command),
                UIKeyCommand(title: String(localized: "Invitations"), action: #selector(MainFlowViewController.processUIKeyCommandForSwitchingToFlowInvitations), input: "4", modifierFlags: .command),
            ]
            
            builder.replaceChildren(ofMenu: .view) { children in
                return keyCommands + children
            }
            
        }
        
    }
    
}
