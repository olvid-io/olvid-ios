/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
    }
    
    private enum ContactsRow {
        case contactSortOrder
    }
    private var shownContactsRows = [ContactsRow.contactSortOrder]

    private enum GroupsRow: Int, CaseIterable {
        case autoAcceptGroupInvitesFrom = 0
    }
    private var shownGroupsRows = [GroupsRow.autoAcceptGroupInvitesFrom]
    
    
    private func observeChangesMadeFromOtherOwnedDevices() {
        
        ObvMessengerSettingsObservableObject.shared.$autoAcceptGroupInviteFrom
            .compactMap { (autoAcceptGroupInviteFrom, changeMadeFromAnotherOwnedDevice, ownedCryptoId) in
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
        Section.allCases.count
    }
 
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { assertionFailure(); return 0 }
        switch section {
        case .contacts:
            return shownContactsRows.count
        case .groups:
            return shownGroupsRows.count
        }
    }
    
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        guard let section = Section(rawValue: indexPath.section) else { assertionFailure(); return UITableViewCell() }

        switch section {
            
        case .contacts:
            guard indexPath.row < shownContactsRows.count else { assertionFailure(); return UITableViewCell() }
            switch shownContactsRows[indexPath.row] {
            case .contactSortOrder:
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                var configuration = UIListContentConfiguration.valueCell()
                configuration.text = CommonString.Title.contactsSortOrder
                configuration.secondaryText = ObvMessengerSettings.Interface.contactsSortOrder.description
                cell.contentConfiguration = configuration
                cell.accessoryType = .disclosureIndicator
                return cell
            }
            
        case .groups:
            guard indexPath.row < shownGroupsRows.count else { assertionFailure(); return UITableViewCell() }
            switch shownGroupsRows[indexPath.row] {
            case .autoAcceptGroupInvitesFrom:
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                var configuration = UIListContentConfiguration.valueCell()
                configuration.text = DetailedSettingForAutoAcceptGroupInvitesViewController.Strings.autoAcceptGroupInvitesFrom
                configuration.secondaryText = ObvMessengerSettings.ContactsAndGroups.autoAcceptGroupInviteFrom.localizedDescription
                cell.contentConfiguration = configuration
                cell.accessoryType = .disclosureIndicator
                return cell
            }
        }
        
    }
    
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .contacts:
            return CommonString.Word.Contacts
        case .groups:
            return CommonString.Word.Groups
        }
    }

    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let section = Section(rawValue: indexPath.section) else { assertionFailure(); return }
        
        switch section {
            
        case .contacts:
            guard indexPath.row < shownContactsRows.count else { assertionFailure(); return }
            switch shownContactsRows[indexPath.row] {
            case .contactSortOrder:
                let vc = ContactsSortOrderChooserTableViewController(ownedCryptoId: ownedCryptoId)
                self.navigationController?.pushViewController(vc, animated: true)
            }

        case .groups:
            guard indexPath.row < shownGroupsRows.count else { assertionFailure(); return }
            switch shownGroupsRows[indexPath.row] {
            case .autoAcceptGroupInvitesFrom:
                let vc = DetailedSettingForAutoAcceptGroupInvitesViewController(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine)
                self.navigationController?.pushViewController(vc, animated: true)
            }

        }
        
    }
}
