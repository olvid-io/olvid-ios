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

final class SettingsFlowViewController: UINavigationController {

    private(set) var ownedCryptoId: ObvCryptoId!
    
    // MARK: - Factory

    // Factory (required because creating a custom init does not work under iOS 12)
    static func create(ownedCryptoId: ObvCryptoId) -> SettingsFlowViewController {

        let allSettingsTableViewController = AllSettingsTableViewController(ownedCryptoId: ownedCryptoId)

        let vc = self.init(rootViewController: allSettingsTableViewController)

        vc.ownedCryptoId = ownedCryptoId

        allSettingsTableViewController.delegate = vc

        vc.title = CommonString.Word.Settings

        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let image = UIImage(systemName: "gear", withConfiguration: symbolConfiguration)
        vc.tabBarItem = UITabBarItem(title: nil, image: image, tag: 0)

        return vc
    }
    
    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
    }
        
    // Required in order to prevent a crash under iOS 12
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }
    
}


// MARK: - View controller lifecycle

extension SettingsFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        navigationBar.standardAppearance = appearance

    }
    
}


// MARK: - AllSettingsTableViewControllerDelegate

extension SettingsFlowViewController: AllSettingsTableViewControllerDelegate {
    
    func pushSetting(_ setting: AllSettingsTableViewController.Setting) {
        let settingViewController: UIViewController
        switch setting {
        case .contactsAndGroups:
            settingViewController = ContactsAndGroupsSettingsTableViewController(ownedCryptoId: ownedCryptoId)
        case .downloads:
            settingViewController = DownloadsSettingsTableViewController()
        case .interface:
            settingViewController = InterfaceSettingsTableViewController(ownedCryptoId: ownedCryptoId)
        case .discussions:
            settingViewController = DiscussionsDefaultSettingsHostingViewController()
        case .privacy:
            settingViewController = PrivacyTableViewController(ownedCryptoId: ownedCryptoId)
        case .backup:
            settingViewController = BackupTableViewController()
        case .about:
            settingViewController = AboutSettingsTableViewController()
        case .advanced:
            settingViewController = AdvancedSettingsViewController(ownedCryptoId: ownedCryptoId)
        case .voip:
            settingViewController = VoIPSettingsTableViewController()
        }
        settingViewController.navigationItem.largeTitleDisplayMode = .never
        
        if let allSettingsTableViewController = children.first as? AllSettingsTableViewController, allSettingsTableViewController.tableView.indexPathForSelectedRow == nil {
            allSettingsTableViewController.selectRowOfSetting(setting) { [weak self] in
                self?.pushViewController(settingViewController, animated: true)
            }
        } else {
            pushViewController(settingViewController, animated: true)
        }
    }
    
}
