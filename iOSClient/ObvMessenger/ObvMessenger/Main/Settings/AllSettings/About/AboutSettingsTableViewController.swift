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

import ObvUI
import UIKit

final class AboutSettingsTableViewController: UITableViewController {

    init() {
        super.init(style: Self.settingsTableStyle)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Word.About
    }


    // MARK: - UITableViewDataSource


    private enum Section: Int, CaseIterable {
        case version = 0
        case minimumVersionsFromServer
        case legal
        case alert
    }

    private enum VersionRows: Int, CaseIterable {
        case version = 0
    }
    
    private enum MinimumVersionsFromServerRow: Int, CaseIterable {
        case minimumSupportedVersion = 0
        case minimumRecommendedVersion
        case goToAppStore
        
    }
    
    private var shownMinimumVersionsFromServerRows = Set<MinimumVersionsFromServerRow>()

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
        case .minimumVersionsFromServer:
            shownMinimumVersionsFromServerRows.formUnion([.minimumRecommendedVersion, .minimumSupportedVersion])
            if ObvMessengerConstants.bundleVersionAsInt < max(ObvMessengerSettings.AppVersionAvailable.latest ?? 0, ObvMessengerSettings.AppVersionAvailable.minimum ?? 0) {
                shownMinimumVersionsFromServerRows.insert(.goToAppStore)
            }
            return shownMinimumVersionsFromServerRows.count
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

        case .minimumVersionsFromServer:
            guard let row = MinimumVersionsFromServerRow(rawValue: indexPath.row) else { assertionFailure(); return UITableViewCell() }
            switch row {
            case .minimumSupportedVersion:
                let cell = tableView.dequeueReusableCell(withIdentifier: "AboutSettingsTableViewControllerCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "AboutSettingsTableViewControllerCell")
                cell.selectionStyle = .none
                if #available(iOS 14, *) {
                    var configuration = cell.defaultContentConfiguration()
                    configuration.text = Strings.minimumSupportedVersion
                    if let version = ObvMessengerSettings.AppVersionAvailable.minimum {
                        configuration.secondaryText = String(describing: version)
                    } else {
                        configuration.secondaryText = CommonString.Word.Unavailable
                    }
                    cell.contentConfiguration = configuration
                } else {
                    cell.textLabel?.text = Strings.minimumSupportedVersion
                    if let version = ObvMessengerSettings.AppVersionAvailable.minimum {
                        cell.detailTextLabel?.text = String(describing: version)
                    } else {
                        cell.detailTextLabel?.text = CommonString.Word.Unavailable
                    }
                    cell.selectionStyle = .none
                }
                return cell
            case .minimumRecommendedVersion:
                let cell = tableView.dequeueReusableCell(withIdentifier: "AboutSettingsTableViewControllerCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "AboutSettingsTableViewControllerCell")
                if #available(iOS 14, *) {
                    var configuration = cell.defaultContentConfiguration()
                    configuration.text = Strings.minimumRecommendedVersion
                    if let version = ObvMessengerSettings.AppVersionAvailable.latest {
                        configuration.secondaryText = String(describing: version)
                    } else {
                        configuration.secondaryText = CommonString.Word.Unavailable
                    }
                    cell.contentConfiguration = configuration
                } else {
                    cell.textLabel?.text = Strings.minimumRecommendedVersion
                    if let version = ObvMessengerSettings.AppVersionAvailable.latest {
                        cell.detailTextLabel?.text = String(describing: version)
                    } else {
                        cell.detailTextLabel?.text = CommonString.Word.Unavailable
                    }
                    cell.selectionStyle = .none
                }
                return cell
            case .goToAppStore:
                let cell = tableView.dequeueReusableCell(withIdentifier: "AboutSettingsTableViewControllerCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "AboutSettingsTableViewControllerCell")
                if #available(iOS 14, *) {
                    var configuration = cell.defaultContentConfiguration()
                    configuration.text = Strings.upgradeOlvidNow
                    configuration.textProperties.color = AppTheme.shared.colorScheme.link
                    cell.contentConfiguration = configuration
                } else {
                    cell.textLabel?.text = Strings.upgradeOlvidNow
                    cell.detailTextLabel?.text = nil
                    cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                }
                cell.selectionStyle = .default
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

        defer {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        
        switch section {
        case .version:
            break
        case .minimumVersionsFromServer:
            guard let row = MinimumVersionsFromServerRow(rawValue: indexPath.row) else { assertionFailure(); return }
            switch row {
            case .minimumSupportedVersion, .minimumRecommendedVersion:
                break
            case .goToAppStore:
                guard UIApplication.shared.canOpenURL(ObvMessengerConstants.shortLinkToOlvidAppIniTunes) else { assertionFailure(); return }
                UIApplication.shared.open(ObvMessengerConstants.shortLinkToOlvidAppIniTunes, options: [:], completionHandler: nil)
            }
        case .legal:
            guard let row = LegalRows(rawValue: indexPath.row) else { assertionFailure(); return }
            switch row {
            case .termsOfUse:
                let url = ObvMessengerConstants.urlToOlvidTermsOfUse
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            case .privacyPolicy:
                let url = ObvMessengerConstants.urlToOlvidPrivacyPolicy
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
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
            }
        }
    }
    
    
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let section = Section(rawValue: indexPath.section) else { assertionFailure(); return nil }
        switch section {
        case .version:
            
            return UIContextMenuConfiguration.init(indexPath: indexPath, previewProvider: nil) { suggestedActions in
                let copyAction = UIAction(title: CommonString.Word.Copy, image: UIImage(systemIcon: .docOnClipboardFill)) { _ in
                    // Copy the version and build number in the pasteboard
                    guard let cell = tableView.cellForRow(at: indexPath) else { return }
                    guard let detailTextLabel = cell.detailTextLabel?.text else { return }
                    UIPasteboard.general.string = detailTextLabel
                }
                let menuConfiguration = UIMenu(title: "", children: [copyAction])
                return menuConfiguration
            }

        default:
            return nil
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
        static let minimumSupportedVersion = NSLocalizedString("MINIMUM_SUPPORTED_VERSION", comment: "")
        static let minimumRecommendedVersion = NSLocalizedString("MINIMUM_RECOMMENDED_VERSION", comment: "")
        static let upgradeOlvidNow = NSLocalizedString("UPGRADE_OLVID_NOW", comment: "")

    }
    
}
