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
import OlvidUtils
import ObvUICoreData
import ObvSettings


class VoIPSettingsTableViewController: UITableViewController {

    init() {
        super.init(style: Self.settingsTableStyle)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Word.VoIP
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
    
    
    private let kbsFormatter = KbsFormatter()
    
    
    private enum Section: CaseIterable {
        
        case normal
        case experimental
        
        static var shown: [Section] {
            if ObvMessengerConstants.showExperimentalFeature {
                return Section.allCases
            } else {
                return [.normal]
            }
        }
        
        var numberOfItems: Int {
            switch self {
            case .normal: return NormalItem.shown.count
            case .experimental: return ExperimentalItem.shown.count
            }
        }

        static func shownSectionAt(section: Int) -> Section? {
            guard section < shown.count else { assertionFailure(); return nil }
            return shown[section]
        }

    }
    
    
    private enum NormalItem: CaseIterable {
        case receiveCallsOnThisDevice
        case includesCallsInRecents
        
        static var shown: [NormalItem] {
            if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
                return [.receiveCallsOnThisDevice]
            } else {
                return [.receiveCallsOnThisDevice, .includesCallsInRecents]
            }
        }

        static func shownItemAt(item: Int) -> NormalItem? {
            guard item < shown.count else { assertionFailure(); return nil }
            return shown[item]
        }

        var cellIdentifier: String {
            switch self {
            case .receiveCallsOnThisDevice: return "ReceiveCallsOnThisDeviceCell"
            case .includesCallsInRecents: return "IncludesCallsInRecentsCell"
            }
        }
        
    }
    
    
    private enum ExperimentalItem: CaseIterable {
        
        case maxaveragebitrate
        
        static var shown: [ExperimentalItem] {
            return ExperimentalItem.allCases
        }

        static func shownItemAt(item: Int) -> ExperimentalItem? {
            guard item < shown.count else { assertionFailure(); return nil }
            return shown[item]
        }

        var cellIdentifier: String {
            switch self {
            case .maxaveragebitrate: return "MaxAverageBitrateCell"
            }
        }
        
    }
    
}

// MARK: - UITableViewDataSource

extension VoIPSettingsTableViewController {
    
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

        case .normal:
            
            guard let item = NormalItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            
            switch item {
                
            case .receiveCallsOnThisDevice:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) as? ObvTitleAndSwitchTableViewCell ?? ObvTitleAndSwitchTableViewCell(reuseIdentifier: item.cellIdentifier)
                cell.title = Strings.receiveCallsOnThisDevice
                cell.switchIsOn = ObvMessengerSettings.VoIP.receiveCallsOnThisDevice
                cell.blockOnSwitchValueChanged = { (value) in
                    ObvMessengerSettings.VoIP.receiveCallsOnThisDevice = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) {
                        tableView.reloadData()
                    }
                }
                return cell
                
            case .includesCallsInRecents:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) as? ObvTitleAndSwitchTableViewCell ?? ObvTitleAndSwitchTableViewCell(reuseIdentifier: item.cellIdentifier)
                cell.title = Strings.includesCallsInRecents
                cell.switchIsOn = ObvMessengerSettings.VoIP.isIncludesCallsInRecentsEnabled
                cell.blockOnSwitchValueChanged = { (value) in
                    ObvMessengerSettings.VoIP.isIncludesCallsInRecentsEnabled = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) {
                        tableView.reloadData()
                    }
                }
                return cell
                
            }

        case .experimental:

            guard let item = ExperimentalItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            
            switch item {

            case .maxaveragebitrate:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .value1, reuseIdentifier: nil)
                cell.textLabel?.text = Strings.maxaveragebitrate
                if let maxaveragebitrate = ObvMessengerSettings.VoIP.maxaveragebitrate {
                    cell.detailTextLabel?.text = kbsFormatter.string(from: maxaveragebitrate as NSNumber)
                } else {
                    cell.detailTextLabel?.text = CommonString.Word.None
                }
                cell.accessoryType = .disclosureIndicator
                return cell

            }
            

        }

    }
 
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        guard let section = Section.shownSectionAt(section: indexPath.section) else { assertionFailure(); return }

        switch section {

        case .normal:

            return
            
        case .experimental:

            guard let item = ExperimentalItem.shownItemAt(item: indexPath.item) else { return }

            switch item {
            case .maxaveragebitrate:
                let vc = MaxAverageBitrateChooserTableViewController()
                self.navigationController?.pushViewController(vc, animated: true)
            }
            
        }
        
    }

}


extension VoIPSettingsTableViewController {
    
    private struct Strings {
        static let receiveCallsOnThisDevice = NSLocalizedString("RECEIVE_CALLS_ON_THIS_DEVICE", comment: "")
        static let includesCallsInRecents = NSLocalizedString("INCLUDE_CALL_IN_RECENTS", comment: "")
        static let maxaveragebitrate = NSLocalizedString("MAX_AVG_BITRATE", comment: "")
    }
    
}
