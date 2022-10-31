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
import ObvEngine


final class SettingsFlowViewController: UINavigationController {

    private(set) var ownedCryptoId: ObvCryptoId!
    private(set) var obvEngine: ObvEngine!

    private weak var createPasscodeDelegate: CreatePasscodeDelegate?

    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine, createPasscodeDelegate: CreatePasscodeDelegate) {
        let allSettingsTableViewController = AllSettingsTableViewController(ownedCryptoId: ownedCryptoId)

        super.init(rootViewController: allSettingsTableViewController)

        self.ownedCryptoId = ownedCryptoId
        self.obvEngine = obvEngine
        self.createPasscodeDelegate = createPasscodeDelegate

        allSettingsTableViewController.delegate = self

        self.title = CommonString.Word.Settings

        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let image = UIImage(systemName: "gear", withConfiguration: symbolConfiguration)
        self.tabBarItem = UITabBarItem(title: nil, image: image, tag: 0)
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
            settingViewController = ContactsAndGroupsSettingsTableViewController(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine)
        case .downloads:
            settingViewController = DownloadsSettingsTableViewController()
        case .interface:
            settingViewController = InterfaceSettingsTableViewController(ownedCryptoId: ownedCryptoId)
        case .discussions:
            settingViewController = DiscussionsDefaultSettingsHostingViewController()
        case .privacy:
            guard let createPasscodeDelegate = self.createPasscodeDelegate else {
                assertionFailure(); return
            }
            settingViewController = PrivacyTableViewController(ownedCryptoId: ownedCryptoId, createPasscodeDelegate: createPasscodeDelegate)
        case .backup:
            settingViewController = BackupTableViewController(obvEngine: obvEngine)
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
