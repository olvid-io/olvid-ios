/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

final class AboutSettingsTableViewController: UITableViewController {

    init() {
        super.init(style: .grouped)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Word.About
    }

}


// MARK: - UITableViewDataSource

extension AboutSettingsTableViewController {

    private enum Section: Int, CaseIterable {
        case version = 0
        case legal
        case alert
    }

    private enum VersionRows: Int, CaseIterable {
        case version = 0
    }

    private enum LegalRows: Int, CaseIterable {
        case termsOfUse = 0
        case privacyPolicy
        case acknowlegments
    }

    private enum AlertRows: Int, CaseIterable {
        case resetAllAlerts
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { assertionFailure(); return 0 }
        switch section {
        case .version: return VersionRows.allCases.count
        case .legal: return LegalRows.allCases.count
        case .alert: return AlertRows.allCases.count
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else { assertionFailure(); return UITableViewCell() }

        switch section {
        case .version:
            guard let row = VersionRows(rawValue: indexPath.row) else { assertionFailure(); return UITableViewCell() }
            switch row {
            case .version:
                let cell = tableView.dequeueReusableCell(withIdentifier: "AboutSettingsTableViewControllerCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "AboutSettingsTableViewControllerCell")
                cell.textLabel?.text = CommonString.Word.Version
                cell.detailTextLabel?.text = ObvMessengerConstants.fullVersion
                cell.selectionStyle = .none
                return cell
            }

        case .legal:
            guard let row = LegalRows(rawValue: indexPath.row) else { assertionFailure(); return UITableViewCell() }
            switch row {
            case .termsOfUse:
                let cell = tableView.dequeueReusableCell(withIdentifier: "AboutSettingsTableViewControllerCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "AboutSettingsTableViewControllerCell")
                cell.textLabel?.text = Strings.termsOfUse
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                cell.selectionStyle = .default
                if #available(iOS 14.0, *) {
                    let icon = NSTextAttachment()
                    icon.image = UIImage(systemIcon: .network)?.withTintColor(AppTheme.shared.colorScheme.link)
                    cell.detailTextLabel?.attributedText = NSMutableAttributedString(attachment: icon)
                }
                return cell
            case .privacyPolicy:
                let cell = tableView.dequeueReusableCell(withIdentifier: "AboutSettingsTableViewControllerCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "AboutSettingsTableViewControllerCell")
                cell.textLabel?.text = Strings.privacyPolicy
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                cell.selectionStyle = .default
                if #available(iOS 14.0, *) {
                    let icon = NSTextAttachment()
                    icon.image = UIImage(systemIcon: .network)?.withTintColor(AppTheme.shared.colorScheme.link)
                    cell.detailTextLabel?.attributedText = NSMutableAttributedString(attachment: icon)
                }
                return cell
            case .acknowlegments:
                let cell = tableView.dequeueReusableCell(withIdentifier: "AboutSettingsTableViewControllerCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "AboutSettingsTableViewControllerCell")
                cell.textLabel?.text = Strings.openSourceLicences
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
                return cell
            }

        case .alert:
            guard let row = AlertRows(rawValue: indexPath.row) else { assertionFailure(); return UITableViewCell() }
            switch row {
            case .resetAllAlerts:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ResetAlertsCell") ?? UITableViewCell(style: .default, reuseIdentifier: "ResetAlertsCell")
                cell.textLabel?.text = Strings.resetAlerts
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                return cell
            }
        }
    }
    
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let section = Section(rawValue: indexPath.section) else { assertionFailure(); return }

        switch section {
        case .version:
            break
        case .legal:
            guard let row = LegalRows(rawValue: indexPath.row) else { assertionFailure(); return }
            switch row {
            case .termsOfUse:
                let url = ObvMessengerConstants.urlToOlvidTermsOfUse
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                tableView.deselectRow(at: indexPath, animated: true)
            case .privacyPolicy:
                let url = ObvMessengerConstants.urlToOlvidPrivacyPolicy
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                tableView.deselectRow(at: indexPath, animated: true)
            case .acknowlegments:
                let vc = ExternalLibrariesViewController()
                self.navigationController?.pushViewController(vc, animated: true)
            }
        case .alert:
            guard let row = AlertRows(rawValue: indexPath.row) else { assertionFailure(); return }
            switch row {
            case .resetAllAlerts:
                ObvMessengerSettings.Alert.resetAllAlerts()
                ObvMessengerInternalNotification.UserRequestedToResetAllAlerts
                    .postOnDispatchQueue()
                tableView.deselectRow(at: indexPath, animated: true)
            }
        }
    }
    
}


// MARK: - Strings

extension AboutSettingsTableViewController {
    
    struct Strings {
        
        static let resetAlerts = NSLocalizedString("TITLE_RESET_ALL_ALERTS", comment: "")
        static let termsOfUse = NSLocalizedString("TERMS_OF_USE", comment: "")
        static let privacyPolicy = NSLocalizedString("PRIVACY_POLICY", comment: "")
        static let openSourceLicences = NSLocalizedString("OPEN_SOURCE_LICENCES", comment: "")

    }
    
}
