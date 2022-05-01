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


class AllSettingsTableViewController: UITableViewController {

    let ownedCryptoId: ObvCryptoId
    weak var delegate: AllSettingsTableViewControllerDelegate?
    
    init(ownedCryptoId: ObvCryptoId) {
        self.ownedCryptoId = ownedCryptoId
        super.init(style: Self.settingsTableStyle)
        title = CommonString.Word.Settings
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
    
    
    // Order of cases declaration matters
    enum Setting: CaseIterable {

        // Section 0
        case contactsAndGroups
        case downloads
        case interface
        case discussions
        case privacy
        case backup
        case voip

        // Section 1
        case about
        case advanced

        private var section: Int {
            // Please follow Setting declaration order
            switch self {
            case .contactsAndGroups, .downloads, .interface, .discussions, .privacy, .backup, .voip: return 0
            case .about, .advanced: return 1
            }
        }

        var isAvailable: Bool {
            switch self {
            case .voip: return ObvMessengerConstants.developmentMode || ObvMessengerConstants.isTestFlight || ObvMessengerSettings.BetaConfiguration.showBetaSettings
            case .advanced: if #available(iOS 13, *) { return true } else { return false }
            default: return true
            }
        }

        static var allAvailableCases: [Setting] {
            return Setting.allCases.filter { $0.isAvailable }
        }
        
        var title: String {
            switch self {
            case .contactsAndGroups: return CommonString.Title.contactsAndGroups
            case .downloads: return CommonString.Word.Downloads
            case .interface: return CommonString.Word.Interface
            case .discussions: return CommonString.Word.Discussions
            case .privacy: return CommonString.Word.Privacy
            case .about: return CommonString.Word.About
            case .advanced: return CommonString.Word.Advanced
            case .backup: return CommonString.Word.Backup
            case .voip: return CommonString.Word.VoIP
            }
        }
        
        var image: UIImage? {
            switch self {
            case .contactsAndGroups: return UIImage(named: "settings_icon_contacts_and_groups")
            case .downloads: return UIImage(named: "settings_icon_downloads")
            case .interface: return UIImage(named: "settings_icon_interface")
            case .discussions: return UIImage(named: "settings_icon_discussions")
            case .privacy: return UIImage(named: "settings_icon_privacy")
            case .about: return UIImage(named: "settings_icon_infos")
            case .advanced: return UIImage(named: "settings_icon_debug")
            case .backup: return UIImage(named: "settings_icon_backup")
            case .voip: return UIImage(named: "settings_icon_voip")
            }
        }
        
        var indexPath: IndexPath {
            let siblingSettings = Setting.allAvailableCases.filter { $0.section == section }
            let row = siblingSettings.firstIndex(of: self)!
            return IndexPath(row: row, section: section)
        }
        
        static func forIndexPath(_ indexPath: IndexPath) -> Setting? {
            return Setting.allAvailableCases.first(where: { $0.indexPath == indexPath })
        }
    }
    
}

// MARK: - UITableViewDataSource

extension AllSettingsTableViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Set(Setting.allAvailableCases.map { $0.indexPath.section }).count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Setting.allAvailableCases.filter { $0.indexPath.section == section }.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "AllSettingsTableViewControllerCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "AllSettingsTableViewControllerCell")
        cell.accessoryType = .disclosureIndicator
        if let setting = Setting.forIndexPath(indexPath) {
            cell.textLabel?.text = setting.title
            let inset: CGFloat = 50
            cell.imageView?.image = setting.image?.imageWithInsets(insets: UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset))
        }
        return cell
    }
    
    
    func selectRowOfSetting(_ setting: Setting, completion: @escaping () -> Void) {
        let indexPath = setting.indexPath
        tableView.selectRow(at: indexPath, animated: true, scrollPosition: .middle)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: completion)
    }
    
}


// MARK: - UITableViewDelegate

extension AllSettingsTableViewController {
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let setting = Setting.forIndexPath(indexPath) {
            delegate?.pushSetting(setting)
        }
    }
    
}
