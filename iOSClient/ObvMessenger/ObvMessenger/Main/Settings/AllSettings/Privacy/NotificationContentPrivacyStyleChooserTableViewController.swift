/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import ObvUICoreData
import ObvSettings


class NotificationContentPrivacyStyleChooserTableViewController: UITableViewController {

    init() {
        super.init(style: Self.settingsTableStyle)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Word.Notifications
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 3
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let choiceForCell = ObvMessengerSettings.Privacy.HideNotificationContentType(rawValue: indexPath.row)!
                
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        switch choiceForCell {
        case .no:
            cell.textLabel?.text = CommonString.Word.No
        case .partially:
            cell.textLabel?.text = CommonString.Word.Partially
        case .completely:
            cell.textLabel?.text = CommonString.Word.Completely
        }
        cell.selectionStyle = .none

        if choiceForCell == ObvMessengerSettings.Privacy.hideNotificationContent {
            cell.accessoryType = .checkmark
        }
        
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        guard let selected = ObvMessengerSettings.Privacy.HideNotificationContentType(rawValue: indexPath.row) else { return }

        ObvMessengerSettings.Privacy.hideNotificationContent = selected

        tableView.reloadData()
        
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        return PrivacyTableViewController.Strings.notificationContentPrivacyStyle.title
    }

    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        switch ObvMessengerSettings.Privacy.hideNotificationContent {
        case .no: return PrivacyTableViewController.Strings.notificationContentPrivacyStyle.explanation.whenNo
        case .partially: return PrivacyTableViewController.Strings.notificationContentPrivacyStyle.explanation.whenPartially
        case .completely: return PrivacyTableViewController.Strings.notificationContentPrivacyStyle.explanation.whenCompletely
        }
    }
}
