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
import ObvEngine

class InterfaceSettingsTableViewController: UITableViewController {

    let ownedCryptoId: ObvCryptoId
    
    init(ownedCryptoId: ObvCryptoId) {
        self.ownedCryptoId = ownedCryptoId
        super.init(style: Self.settingsTableStyle)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Word.Interface
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
    
}

// MARK: - UITableViewDataSource

extension InterfaceSettingsTableViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        if #available(iOS 15, *) {
            return 3
        } else {
            return 1
        }
    }
    
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return 1 // For iOS 15 only, otherwise 2 sections only
        case 2: return 1 // For iOS 15 only, otherwise 2 sections only
        default: return 0
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell: UITableViewCell
        
        switch indexPath {
        case IndexPath(row: 0, section: 0):
            cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = Strings.identityColorStyle
            cell.detailTextLabel?.text = ObvMessengerSettings.Interface.identityColorStyle.description
            cell.accessoryType = .disclosureIndicator
        case IndexPath(row: 0, section: 1):
            let _cell = ObvTitleAndSwitchTableViewCell(reuseIdentifier: "UseOldDiscussionInterface")
            _cell.selectionStyle = .none
            _cell.title = Strings.useOldDiscussionInterface
            _cell.switchIsOn = ObvMessengerSettings.Interface.useOldDiscussionInterface
            _cell.blockOnSwitchValueChanged = { (value) in
                ObvMessengerSettings.Interface.useOldDiscussionInterface = value
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) {
                    tableView.reloadData()
                }
            }
            cell = _cell
        case IndexPath(row: 0, section: 2):
            cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            if #available(iOS 14, *) {
                var configuration = cell.defaultContentConfiguration()
                configuration.text = Strings.newComposeMessageViewActionOrder
                cell.contentConfiguration = configuration
            } else {
                cell.textLabel?.text = Strings.newComposeMessageViewActionOrder
            }
            cell.accessoryType = .disclosureIndicator
        default:
            cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            assert(false)
        }
        
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath {
        case IndexPath(row: 0, section: 0):
            let vc = IdentityColorStyleChooserTableViewController()
            self.navigationController?.pushViewController(vc, animated: true)
        case IndexPath(row: 0, section: 2):
            if #available(iOS 15, *) {
                let vc = ComposeMessageViewSettingsViewController(input: .global)
                self.navigationController?.pushViewController(vc, animated: true)
            }
        default:
            break
        }
    }

}

extension ContactsSortOrder: CustomStringConvertible {
    var description: String {
        switch self {
        case .byFirstName: return InterfaceSettingsTableViewController.Strings.firstNameThenLastName
        case .byLastName: return InterfaceSettingsTableViewController.Strings.lastNameThenFirstName
        }
    }


}


private extension InterfaceSettingsTableViewController {
    
    struct Strings {
        static let identityColorStyle = NSLocalizedString("Identity color style", comment: "")
        static let newComposeMessageViewActionOrder = NSLocalizedString("NEW_COMPOSE_MESSAGE_VIEW_PREFERENCES", comment: "")
        static let firstNameThenLastName = NSLocalizedString("FIRST_NAME_LAST_NAME", comment: "")
        static let lastNameThenFirstName = NSLocalizedString("LAST_NAME_FIRST_NAME", comment: "")
        static let useOldDiscussionInterface = NSLocalizedString("USE_OLD_DISCUSSION_INTERFACE", comment: "")
    }
    
}
