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

import Foundation
import UIKit
import ObvSettings


/// This view controller allows the user to choose the keyboard shortcut used to send a message.
class SendMessageShortcutTableViewController: UITableViewController {

    init() {
        super.init(style: Self.settingsTableStyle)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = ""
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return ObvMessengerSettings.Interface.SendMessageShortcutType.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let shortcut = ObvMessengerSettings.Interface.SendMessageShortcutType.allCases[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = shortcut.description
        cell.selectionStyle = .none

        let currentShortcut = ObvMessengerSettings.Interface.sendMessageShortcutType
        if currentShortcut == shortcut {
            cell.accessoryType = .checkmark
        }
        
        return cell
        
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let shortcut = ObvMessengerSettings.Interface.SendMessageShortcutType.allCases[indexPath.row]

        ObvMessengerSettings.Interface.sendMessageShortcutType = shortcut
        
        tableView.reloadData()
    }

}


extension ObvMessengerSettings.Interface.SendMessageShortcutType: CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .enter:
            return String(localized: "NAME_OF_ENTER_KEYBOARD_KEY")
        case .commandEnter:
            return String(localized: "NAME_OF_COMMAND_PLUS_ENTER_KEYBOARD_KEY")
        }
    }
    
}
