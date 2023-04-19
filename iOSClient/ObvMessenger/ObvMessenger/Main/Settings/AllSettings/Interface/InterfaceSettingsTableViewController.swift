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
        case interfaceOptions
        case identityColorStyle
        static var shown: [Section] {
            var result = [Section]()
            if #available(iOS 15, *) {
                result += [customizeMessageComposeArea]
                result += [interfaceOptions]
            }
            result += [identityColorStyle]
            return result
        }
        var numberOfItems: Int {
            switch self {
            case .customizeMessageComposeArea: return CustomizeMessageComposeAreaItem.shown.count
            case .interfaceOptions: return InterfaceOptionsItem.shown.count
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
            if #available(iOS 15, *) {
                result += [customizeMessageComposeArea]
            }
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

    
    private enum InterfaceOptionsItem: CaseIterable {
        case useOldDiscussionInterface
        case useOldListOfDiscussionsInterface
        static var shown: [InterfaceOptionsItem] {
            var result = [InterfaceOptionsItem]()
            if #available(iOS 15, *) {
                result += [useOldDiscussionInterface]
            }
            if #available(iOS 16, *) {
                result += [useOldListOfDiscussionsInterface]
            }
            return result
        }
        static func shownItemAt(item: Int) -> InterfaceOptionsItem? {
            return shown[safe: item]
        }
        var cellIdentifier: String {
            switch self {
            case .useOldDiscussionInterface: return "useOldDiscussionInterface"
            case .useOldListOfDiscussionsInterface: return "useOldListOfDiscussionsInterface"
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
                if #available(iOS 14, *) {
                    var configuration = cell.defaultContentConfiguration()
                    configuration.text = Strings.newComposeMessageViewActionOrder
                    cell.contentConfiguration = configuration
                } else {
                    cell.textLabel?.text = Strings.newComposeMessageViewActionOrder
                }
                cell.accessoryType = .disclosureIndicator
                return cell
            }
        case .interfaceOptions:
            guard let item = InterfaceOptionsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            switch item {
            case .useOldDiscussionInterface:
                let cell = ObvTitleAndSwitchTableViewCell(reuseIdentifier: item.cellIdentifier)
                cell.selectionStyle = .none
                cell.title = Strings.useOldDiscussionInterface
                cell.switchIsOn = ObvMessengerSettings.Interface.useOldDiscussionInterface
                cell.blockOnSwitchValueChanged = { (value) in
                    ObvMessengerSettings.Interface.useOldDiscussionInterface = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) {
                        tableView.reloadData()
                    }
                }
                return cell
            case .useOldListOfDiscussionsInterface:
                let cell = ObvTitleAndSwitchTableViewCell(reuseIdentifier: item.cellIdentifier)
                cell.selectionStyle = .none
                cell.title = Strings.useOldListOfDiscussionsInterface
                cell.switchIsOn = ObvMessengerSettings.Interface.useOldListOfDiscussionsInterface
                cell.blockOnSwitchValueChanged = { (value) in
                    ObvMessengerSettings.Interface.useOldListOfDiscussionsInterface = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) {
                        tableView.reloadData()
                    }
                }
                return cell
            }
        case .identityColorStyle:
            guard let item = IdentityColorStyleItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            switch item {
            case .identityColorStyle:
                let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
                if #available(iOS 14, *) {
                    var configuration = cell.defaultContentConfiguration()
                    configuration.text = Strings.identityColorStyle
                    configuration.secondaryText = ObvMessengerSettings.Interface.identityColorStyle.description
                    cell.contentConfiguration = configuration
                } else {
                    cell.textLabel?.text = Strings.identityColorStyle
                    cell.detailTextLabel?.text = ObvMessengerSettings.Interface.identityColorStyle.description
                }
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
                if #available(iOS 15, *) {
                    let vc = ComposeMessageViewSettingsViewController(input: .global)
                    navigationController?.pushViewController(vc, animated: true)
                }
            }
        case .interfaceOptions:
            return
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
        static let useOldListOfDiscussionsInterface = NSLocalizedString("USE_OLD_LIST_OF_DISCUSSIONS_INTERFACE", comment: "")
    }
    
}
