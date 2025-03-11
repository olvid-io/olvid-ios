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

import ObvUI
import UIKit
import ObvUICoreData
import ObvSettings
import ObvDesignSystem


/// This view controller is pushed when the user decides to configure the layout used by the collection view of the single discussion screen.
/// This setting is typically only available when the beta options are activated, and used to test the efficiency of different layout options.
final class SingleDiscussionLayoutTestsChooserViewController: UITableViewController {

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
        return ObvMessengerSettings.Interface.DiscussionLayoutType.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let style = ObvMessengerSettings.Interface.DiscussionLayoutType.allCases[indexPath.row]
        
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = style.description
        cell.selectionStyle = .none

        let currentDiscussionLayoutType = ObvMessengerSettings.Interface.discussionLayoutType
        if currentDiscussionLayoutType == style {
            cell.accessoryType = .checkmark
        }
        
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let selectedStyle = ObvMessengerSettings.Interface.DiscussionLayoutType.allCases[indexPath.row]
        
        ObvMessengerSettings.Interface.discussionLayoutType = selectedStyle
        
        tableView.reloadData()
    }

}

