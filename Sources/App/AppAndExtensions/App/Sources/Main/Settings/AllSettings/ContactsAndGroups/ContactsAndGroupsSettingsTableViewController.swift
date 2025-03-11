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
import ObvEngine
import ObvUICoreData
import Combine
import ObvSettings


final class ContactsAndGroupsSettingsTableViewController: UITableViewController {
    
    private let ownedCryptoId: ObvCryptoId
    private let obvEngine: ObvEngine
    
    /// Allows to observe changes made to certain settings made from other owned devices
    private var cancellables = Set<AnyCancellable>()

    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine) {
        self.ownedCryptoId = ownedCryptoId
        self.obvEngine = obvEngine
        super.init(style: Self.settingsTableStyle)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Title.contactsAndGroups
        observeChangesMadeFromOtherOwnedDevices()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    
    private enum Section: Int, CaseIterable {
        
        case contacts = 0
        case groups = 1
        case hideGroupMemberChangeMessages = 2
        
        static var shown: [Section] {
            Self.allCases
        }
        
        var numberOfItems: Int {
            switch self {
            case .contacts: return ContactsItem.shown.count
            case .groups: return GroupsItem.shown.count
            case .hideGroupMemberChangeMessages: return HideGroupMemberChangeMessagesItem.shown.count
            }
        }

        static func shownSectionAt(section: Int) -> Section? {
            guard section < shown.count else { assertionFailure(); return nil }
            return shown[section]
        }

    }
    
    
    private enum ContactsItem: CaseIterable {
        case contactSortOrder
        
        static var shown: [Self] {
            return Self.allCases
        }
        
        static func shownItemAt(item: Int) -> Self? {
            guard item < shown.count else { assertionFailure(); return nil }
            return shown[item]
        }

        var cellIdentifier: String {
            switch self {
            case .contactSortOrder: return "ContactSortOrderCell"
            }
        }

    }

    
    private enum GroupsItem: Int, CaseIterable {
        case autoAcceptGroupInvitesFrom
        
        static var shown: [Self] {
            return Self.allCases
        }
        
        static func shownItemAt(item: Int) -> Self? {
            guard item < shown.count else { assertionFailure(); return nil }
            return shown[item]
        }

        var cellIdentifier: String {
            switch self {
            case .autoAcceptGroupInvitesFrom: return "AutoAcceptGroupInvitesFromCell"
            }
        }

    }
    
    
    private enum HideGroupMemberChangeMessagesItem: CaseIterable {
        case hideGroupMemberChangeMessages

        static var shown: [Self] {
            return Self.allCases
        }
        
        static func shownItemAt(item: Int) -> Self? {
            guard item < shown.count else { assertionFailure(); return nil }
            return shown[item]
        }

        var cellIdentifier: String {
            switch self {
            case .hideGroupMemberChangeMessages: return "HideGroupMemberChangeMessagesCell"
            }
        }

    }
    
    
    private func observeChangesMadeFromOtherOwnedDevices() {
        
        ObvMessengerSettingsObservableObject.shared.$autoAcceptGroupInviteFrom
            .compactMap { (autoAcceptGroupInviteFrom, changeMadeFromAnotherOwnedDevice) in
                // We only observe changes made from other owned devices
                guard changeMadeFromAnotherOwnedDevice else { return nil }
                return autoAcceptGroupInviteFrom
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (autoAcceptGroupInviteFrom: ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom) in
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)

    }

}


// MARK: - UITableViewDataSource

extension ContactsAndGroupsSettingsTableViewController {
    
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.shown.count
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
            
        case .contacts:
            
            guard let item = ContactsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            
            switch item {
                
            case .contactSortOrder:
                let cell = UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                var configuration = UIListContentConfiguration.valueCell()
                configuration.text = CommonString.Title.contactsSortOrder
                configuration.secondaryText = ObvMessengerSettings.Interface.contactsSortOrder.description
                cell.contentConfiguration = configuration
                cell.accessoryType = .disclosureIndicator
                return cell
                
            }
            
        case .groups:
            
            guard let item = GroupsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }

            switch item {
            
            case .autoAcceptGroupInvitesFrom:
                let cell = UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                var configuration = UIListContentConfiguration.valueCell()
                configuration.text = DetailedSettingForAutoAcceptGroupInvitesViewController.Strings.autoAcceptGroupInvitesFrom
                configuration.secondaryText = ObvMessengerSettings.ContactsAndGroups.autoAcceptGroupInviteFrom.localizedDescription
                cell.contentConfiguration = configuration
                cell.accessoryType = .disclosureIndicator
                return cell
                            
            }
            
        case .hideGroupMemberChangeMessages:
            
            guard let item = HideGroupMemberChangeMessagesItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            
            switch item {
                
            case .hideGroupMemberChangeMessages:
                
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) as? ObvTitleAndSwitchTableViewCell ?? ObvTitleAndSwitchTableViewCell(reuseIdentifier: item.cellIdentifier)
                var config = cell.defaultContentConfiguration()
                config.text = String(localized: "HIDE_GROUP_MEMBER_CHANGE_MESSAGES_CELL_TITLE")
                //config.secondaryText = String(localized: "HIDE_GROUP_MEMBER_CHANGE_MESSAGES_CELL_SUBTITLE")
                cell.contentConfiguration = config
                cell.switchIsOn = ObvMessengerSettings.ContactsAndGroups.hideGroupMemberChangeMessages
                cell.blockOnSwitchValueChanged = { (value) in
                    ObvMessengerSettings.ContactsAndGroups.hideGroupMemberChangeMessages = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) {
                        tableView.reloadData()
                    }
                }
                return cell

            }

        }
        
    }
    
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        
        guard let section = Section.shownSectionAt(section: section) else {
            assertionFailure()
            return nil
        }

        switch section {
        case .contacts:
            return CommonString.Word.Contacts
        case .groups:
            return CommonString.Word.Groups
        case .hideGroupMemberChangeMessages:
            return nil
        }
        
    }
    
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        
        guard let section = Section.shownSectionAt(section: section) else {
            assertionFailure()
            return nil
        }

        switch section {
        case .contacts:
            return nil
        case .groups:
            return nil
        case .hideGroupMemberChangeMessages:
            return String(localized: "HIDE_GROUP_MEMBER_CHANGE_MESSAGES_CELL_SUBTITLE")
        }

    }

    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        guard let section = Section.shownSectionAt(section: indexPath.section) else { assertionFailure(); return }

        switch section {
            
        case .contacts:
            
            guard let item = ContactsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            
            switch item {
                
            case .contactSortOrder:
                
                let vc = ContactsSortOrderChooserTableViewController(ownedCryptoId: ownedCryptoId)
                self.navigationController?.pushViewController(vc, animated: true)

            }

        case .groups:
            
            guard let item = GroupsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }

            switch item {
                
            case .autoAcceptGroupInvitesFrom:
                
                let vc = DetailedSettingForAutoAcceptGroupInvitesViewController(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine)
                self.navigationController?.pushViewController(vc, animated: true)
                
            }
            
        case .hideGroupMemberChangeMessages:
            
            guard let item = HideGroupMemberChangeMessagesItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            
            switch item {
                
            case .hideGroupMemberChangeMessages:
                
                return
                
            }

        }
        
    }
}
