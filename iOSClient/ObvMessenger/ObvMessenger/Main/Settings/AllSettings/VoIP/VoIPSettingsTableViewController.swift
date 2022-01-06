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

class VoIPSettingsTableViewController: UITableViewController {

    init() {
        super.init(style: .grouped)
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
    
}

// MARK: - UITableViewDataSource

extension VoIPSettingsTableViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return ObvMessengerConstants.showExperimentalFeature ? 3 : 2
    }
    
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            var rows = 1
            if isCallKitEnabled { rows += 1 } // For includesCallsInRecents
            return rows
        case 1:
            return 1 // Maxaveragebitrate
        default:
            return 0
        }
    }

    private var isCallKitEnabled: Bool {
        get { ObvMessengerSettings.VoIP.isCallKitEnabled }
        set { ObvMessengerSettings.VoIP.isCallKitEnabled = newValue }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell: UITableViewCell
        
        switch indexPath {
        case IndexPath(row: 0, section: 0):
            let _cell = ObvTitleAndSwitchTableViewCell(reuseIdentifier: "UseCallKitCell")
            _cell.selectionStyle = .none
            _cell.title = Strings.useCallKit
            _cell.switchIsOn = isCallKitEnabled
            _cell.blockOnSwitchValueChanged = { (value) in
                ObvMessengerSettings.VoIP.isCallKitEnabled = value
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) {
                    tableView.reloadData()
                }
            }
            cell = _cell
        case IndexPath(row: 1, section: 0):
            let _cell = ObvTitleAndSwitchTableViewCell(reuseIdentifier: "IncludesCallsInRecents")
            _cell.selectionStyle = .none
            _cell.title = Strings.includesCallsInRecents
            _cell.switchIsOn = ObvMessengerSettings.VoIP.isIncludesCallsInRecentsEnabled
            _cell.blockOnSwitchValueChanged = { (value) in
                ObvMessengerSettings.VoIP.isIncludesCallsInRecentsEnabled = value
            }
            cell = _cell
        case IndexPath(row: 0, section: 1):
            cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = Strings.maxaveragebitrate
            if let maxaveragebitrate = ObvMessengerSettings.VoIP.maxaveragebitrate {
                cell.detailTextLabel?.text = kbsFormatter.string(from: maxaveragebitrate as NSNumber)
            } else {
                cell.detailTextLabel?.text = CommonString.Word.None
            }
            cell.accessoryType = .disclosureIndicator
        default:
            cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            assert(false)
        }
        
        return cell
    }
 
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath {
        case IndexPath(row: 0, section: 1):
            let vc = MaxAverageBitrateChooserTableViewController()
            self.navigationController?.pushViewController(vc, animated: true)
        default:
            break
        }
    }

}


extension VoIPSettingsTableViewController {
    
    private struct Strings {
        static let useCallKit = NSLocalizedString("USE_CALLKIT", comment: "")
        static let includesCallsInRecents = NSLocalizedString("INCLUDE_CALL_IN_RECENTS", comment: "")
        static let useLoadBalancedTurnServers = NSLocalizedString("USE_LOAD_BALANCED_TURN_SERVERS", comment: "")
        static let maxaveragebitrate = NSLocalizedString("MAX_AVG_BITRATE", comment: "")
    }
    
}
