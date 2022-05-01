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


final class DetailedSettingForAutoAcceptGroupInvitesViewController: UITableViewController {
    
    private let ownedCryptoId: ObvCryptoId

    init(ownedCryptoId: ObvCryptoId) {
        self.ownedCryptoId = ownedCryptoId
        super.init(style: Self.settingsTableStyle)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    private var shownRows = ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom.allCases

}


// MARK: - UITableViewDataSource

extension DetailedSettingForAutoAcceptGroupInvitesViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return (section == 0) ? ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom.allCases.count : 0
    }
    
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.row < shownRows.count else { assertionFailure(); return UITableViewCell(style: .default, reuseIdentifier: nil) }
        let autoAcceptType = shownRows[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = autoAcceptType.localizedDescription
        cell.selectionStyle = .none
        cell.accessoryType = .none
        if autoAcceptType == ObvMessengerSettings.ContactsAndGroups.autoAcceptGroupInviteFrom {
            cell.accessoryType = .checkmark
        }
        return cell
    }

    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        return Strings.autoAcceptGroupInvitesFrom
    }
    
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 0 else { return }
        guard indexPath.row < shownRows.count else { assertionFailure(); return }
        let selectedAutoAcceptType = shownRows[indexPath.row]
        guard ObvMessengerSettings.ContactsAndGroups.autoAcceptGroupInviteFrom != selectedAutoAcceptType else { return }
        Task {
            do {
                let acceptableAutoAcceptType = try await suggestAutoAcceptingCurrentGroupInvitationsNowIfRequired(
                    selectedAutoAcceptType: selectedAutoAcceptType,
                    currentAutoAcceptType: ObvMessengerSettings.ContactsAndGroups.autoAcceptGroupInviteFrom)
                ObvMessengerSettings.ContactsAndGroups.autoAcceptGroupInviteFrom = acceptableAutoAcceptType
                tableView.reloadData()
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
 
    
}


// MARK: - Checking existing invitations before accepting a new setting

extension DetailedSettingForAutoAcceptGroupInvitesViewController {
    
    /// In certain case, like changing the setting from `.nobody` to `.everyone`, the user might need to accept to automatically confirm all pending group invites.
    /// This method check whether we are in such a case. If we are, it request a confirmation to the user. Eventually, it returns the most appropriate value for the setting.
    private func suggestAutoAcceptingCurrentGroupInvitationsNowIfRequired(selectedAutoAcceptType: ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom, currentAutoAcceptType: ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom) async throws -> ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom {
        switch(currentAutoAcceptType, selectedAutoAcceptType) {
        case (_, .noOne):
            return .noOne
        case (.everyone, .oneToOneContactsOnly):
            return .oneToOneContactsOnly
        case (_, .oneToOneContactsOnly):
            let groupInvites = try PersistedInvitation.getAllGroupInvitesFromOneToOneContacts(within: ObvStack.shared.viewContext)
            if groupInvites.isEmpty {
                return .oneToOneContactsOnly
            } else {
                // We need to ask the user whether it is ok to auto-accept the fetched invitations
                if try await userConfirmedHerChoiceAndAutoAccepted(groupInvites: groupInvites) {
                    return .oneToOneContactsOnly
                } else {
                    return currentAutoAcceptType
                }
            }
        case (_, .everyone):
            let groupInvites = try PersistedInvitation.getAllGroupInvites(within: ObvStack.shared.viewContext)
            if groupInvites.isEmpty {
                return .everyone
            } else {
                // We need to ask the user whether it is ok to auto-accept the fetched invitations
                if try await userConfirmedHerChoiceAndAutoAccepted(groupInvites: groupInvites) {
                    return .everyone
                } else {
                    return currentAutoAcceptType
                }
            }
        }
    }
    
    
    private func userConfirmedHerChoiceAndAutoAccepted(groupInvites: [PersistedInvitation]) async throws -> Bool {
        assert(Thread.isMainThread)
        guard !groupInvites.isEmpty else { return true }
        let traitCollection = self.traitCollection
        return try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Bool, Error>) in
            assert(Thread.isMainThread)
            let alert = UIAlertController(title: Strings.Alert.title,
                                          message: Strings.Alert.message(numberOfInvitations: groupInvites.count),
                                          preferredStyleForTraitCollection: traitCollection)
            let okAction = UIAlertAction(title: Strings.Alert.AcceptAction.title(numberOfInvitations: groupInvites.count), style: .default) { [weak self] _ in
                do {
                    try groupInvites.forEach {
                        guard var localDialog = $0.obvDialog else { assertionFailure(); return }
                        try localDialog.setResponseToAcceptGroupInvite(acceptInvite: true)
                        self?.obvEngine.respondTo(localDialog)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
                continuation.resume(returning: true)
            }
            let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: .cancel) { _ in
                continuation.resume(returning: false)
            }
            alert.addAction(okAction)
            alert.addAction(cancelAction)
            alert.preferredAction = okAction
            self?.present(alert, animated: true)
        }
    }
    
    
    
}


extension DetailedSettingForAutoAcceptGroupInvitesViewController {
    
    struct Strings {
        static let autoAcceptGroupInvitesFrom = NSLocalizedString("AUTO_ACCEPT_GROUP_INVITES_FROM", comment: "")
        struct Alert {
            static let title = NSLocalizedString("AUTO_ACCEPT_GROUP_INVITATIONS_ALERT_TITLE", comment: "")
            static func message(numberOfInvitations: Int) -> String { String.localizedStringWithFormat(NSLocalizedString("AUTO_ACCEPT_GROUP_INVITATIONS_ALERT_MESSAGE", comment: ""), numberOfInvitations) }
            struct AcceptAction {
                static func title(numberOfInvitations: Int) -> String { String.localizedStringWithFormat(NSLocalizedString("AUTO_ACCEPT_GROUP_INVITATIONS_ALERT_ACCEPT_ACTION_TITLE", comment: ""), numberOfInvitations) }
            }
        }
    }
    
}
