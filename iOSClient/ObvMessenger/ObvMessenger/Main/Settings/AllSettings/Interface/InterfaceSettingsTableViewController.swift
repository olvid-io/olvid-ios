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
import ObvTypes
import ObvUICoreData
import ObvSettings


final class InterfaceSettingsTableViewController: UITableViewController {

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
        
        case discussion
        case identityColorStyle
        case singleDiscussionLayoutTests
        
        static var shown: [Section] {
            if ObvMessengerConstants.showExperimentalFeature {
                return Self.allCases
            } else {
                return [.discussion, .identityColorStyle]
            }
        }
        
        var numberOfItems: Int {
            switch self {
            case .discussion: return DiscussionItem.shown.count
            case .identityColorStyle: return IdentityColorStyleItem.shown.count
            case .singleDiscussionLayoutTests: return SingleDiscussionLayoutTestsItem.shown.count
            }
        }
        
        static func shownSectionAt(section: Int) -> Section? {
            return shown[safe: section]
        }
        
    }
    
    private enum DiscussionItem: CaseIterable {
        case customizeMessageComposeArea
        case sendMessageShortcut
        case hideLinks
        static var shown: [Self] {
            return Self.allCases
        }
        static func shownItemAt(item: Int) -> Self? {
            return shown[safe: item]
        }
        var cellIdentifier: String {
            switch self {
            case .customizeMessageComposeArea: return "customizeMessageComposeArea"
            case .sendMessageShortcut: return "SendMessageShortcutCell"
            case .hideLinks: return "hideLinks"
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

    
    private enum SingleDiscussionLayoutTestsItem: CaseIterable {
        case chooseLayoutType
        static var shown: [SingleDiscussionLayoutTestsItem] {
            return Self.allCases
        }
        static func shownItemAt(item: Int) -> SingleDiscussionLayoutTestsItem? {
            return shown[safe: item]
        }
        var cellIdentifier: String {
            switch self {
            case .chooseLayoutType: return "chooseLayoutType"
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
            
        case .discussion:
            
            guard let item = DiscussionItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            
            switch item {
                
            case .customizeMessageComposeArea:
                let cell = UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                var configuration = cell.defaultContentConfiguration()
                configuration.text = Strings.newComposeMessageViewActionOrder
                cell.contentConfiguration = configuration
                cell.accessoryType = .disclosureIndicator
                return cell
                
            case .sendMessageShortcut:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .value1, reuseIdentifier: item.cellIdentifier)
                var content = cell.defaultContentConfiguration()
                content.text = String(localized: "KEYBOARD_SHORTCUT_FOR_SENDING_MESSAGE")
                content.secondaryText = ObvMessengerSettings.Interface.sendMessageShortcutType.description
                cell.contentConfiguration = content
                cell.accessoryType = .disclosureIndicator
                return cell
                
            case .hideLinks:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) as? ObvTitleAndSwitchTableViewCell ?? ObvTitleAndSwitchTableViewCell(reuseIdentifier: item.cellIdentifier)
                var config = cell.defaultContentConfiguration()
                config.text = String(localized: "HIDE_TRAILING_URL_IN_MESSAGES_WHEN_PREVIEW_IS_AVAILABLE")
                cell.contentConfiguration = config
                cell.switchIsOn = ObvMessengerSettings.Interface.hideTrailingURLInMessagesWhenPreviewIsAvailable
                cell.blockOnSwitchValueChanged = { (value) in
                    ObvMessengerSettings.Interface.hideTrailingURLInMessagesWhenPreviewIsAvailable = value
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
                var configuration = cell.defaultContentConfiguration()
                configuration.text = Strings.identityColorStyle
                configuration.secondaryText = ObvMessengerSettings.Interface.identityColorStyle.description
                cell.contentConfiguration = configuration
                cell.accessoryType = .disclosureIndicator
                return cell
                
            }
            
        case .singleDiscussionLayoutTests:
            
            guard let item = SingleDiscussionLayoutTestsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            
            switch item {
                
            case .chooseLayoutType:
                let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
                var configuration = cell.defaultContentConfiguration()
                configuration.text = Strings.discussionLayoutType
                configuration.secondaryText = ObvMessengerSettings.Interface.discussionLayoutType.description
                cell.contentConfiguration = configuration
                cell.accessoryType = .disclosureIndicator
                return cell
                
            }
        }
    }

    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        guard let section = Section.shownSectionAt(section: indexPath.section) else { assertionFailure(); return }
        
        switch section {
            
        case .discussion:
            
            guard let item = DiscussionItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            
            switch item {
                
            case .customizeMessageComposeArea:
                let vc = ComposeMessageViewSettingsViewController(input: .global)
                navigationController?.pushViewController(vc, animated: true)
                
            case .sendMessageShortcut:
                let vc = SendMessageShortcutTableViewController()
                navigationController?.pushViewController(vc, animated: true)
                
            case .hideLinks:
                return

            }
            
        case .identityColorStyle:
            guard let item = IdentityColorStyleItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            switch item {
            case .identityColorStyle:
                let vc = IdentityColorStyleChooserTableViewController()
                navigationController?.pushViewController(vc, animated: true)
            }
            
        case .singleDiscussionLayoutTests:
            guard let item = SingleDiscussionLayoutTestsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            switch item {
            case .chooseLayoutType:
                let vc = SingleDiscussionLayoutTestsChooserViewController()
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
        static let discussionLayoutType = NSLocalizedString("DISCUSSION_LAYOUT_TYPE", comment: "")
    }
    
}


extension ObvMessengerSettings.Interface.DiscussionLayoutType {
    
    var description: String {
        switch self {
        case .productionLayout:
            return NSLocalizedString("PRODUCTION_LAYOUT", comment: "")
        case .listLayout:
            return NSLocalizedString("LIST_LAYOUT", comment: "")
        }
    }
    
}
