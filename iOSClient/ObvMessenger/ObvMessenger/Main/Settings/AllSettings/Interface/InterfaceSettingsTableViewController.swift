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
import ObvTypes
import ObvUICoreData
import ObvSettings


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
    
    
    private enum Section: CaseIterable {
        case customizeMessageComposeArea
        case identityColorStyle
        static var shown: [Section] {
            Section.allCases
        }
        var numberOfItems: Int {
            switch self {
            case .customizeMessageComposeArea: return CustomizeMessageComposeAreaItem.shown.count
            case .identityColorStyle: return IdentityColorStyleItem.shown.count
            }
        }
        static func shownSectionAt(section: Int) -> Section? {
            return shown[safe: section]
        }
    }
    
    
    private enum CustomizeMessageComposeAreaItem: CaseIterable {
        case customizeMessageComposeArea
        static var shown: [CustomizeMessageComposeAreaItem] {
            var result = [CustomizeMessageComposeAreaItem]()
            result += [customizeMessageComposeArea]
            return result
        }
        static func shownItemAt(item: Int) -> CustomizeMessageComposeAreaItem? {
            return shown[safe: item]
        }
        var cellIdentifier: String {
            switch self {
            case .customizeMessageComposeArea: return "customizeMessageComposeArea"
            }
        }
    }

    
    private enum IdentityColorStyleItem: CaseIterable {
        case identityColorStyle
        static var shown: [IdentityColorStyleItem] {
            return self.allCases
        }
        static func shownItemAt(item: Int) -> IdentityColorStyleItem? {
            return shown[safe: item]
        }
        var cellIdentifier: String {
            switch self {
            case .identityColorStyle: return "identityColorStyle"
            }
        }
    }

}

// MARK: - UITableViewDataSource

extension InterfaceSettingsTableViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.shown.count
    }
    
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section.shownSectionAt(section: section) else { return 0 }
        return section.numberOfItems
    }
    
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cellInCaseOfError = UITableViewCell(style: .default, reuseIdentifier: nil)

        guard let section = Section.shownSectionAt(section: indexPath.section) else {
            assertionFailure()
            return cellInCaseOfError
        }

        switch section {
        case .customizeMessageComposeArea:
            guard let item = CustomizeMessageComposeAreaItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            switch item {
            case .customizeMessageComposeArea:
                let cell = UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                var configuration = cell.defaultContentConfiguration()
                configuration.text = Strings.newComposeMessageViewActionOrder
                cell.contentConfiguration = configuration
                cell.accessoryType = .disclosureIndicator
                return cell
            }
        case .identityColorStyle:
            guard let item = IdentityColorStyleItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            switch item {
            case .identityColorStyle:
                let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
                var configuration = cell.defaultContentConfiguration()
                configuration.text = Strings.identityColorStyle
                configuration.secondaryText = ObvMessengerSettings.Interface.identityColorStyle.description
                cell.contentConfiguration = configuration
                cell.accessoryType = .disclosureIndicator
                return cell
            }
        }
    }

    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let section = Section.shownSectionAt(section: indexPath.section) else { assertionFailure(); return }
        switch section {
        case .customizeMessageComposeArea:
            guard let item = CustomizeMessageComposeAreaItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            switch item {
            case .customizeMessageComposeArea:
                let vc = ComposeMessageViewSettingsViewController(input: .global)
                navigationController?.pushViewController(vc, animated: true)
            }
        case .identityColorStyle:
            guard let item = IdentityColorStyleItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            switch item {
            case .identityColorStyle:
                let vc = IdentityColorStyleChooserTableViewController()
                navigationController?.pushViewController(vc, animated: true)
            }
        }
    }

}


extension ContactsSortOrder: CustomStringConvertible {
    public var description: String {
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
