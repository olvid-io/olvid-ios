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
import OlvidUtils

class MaxAverageBitrateChooserTableViewController: UITableViewController {

    init() {
        super.init(style: .grouped)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "maxaveragebitrate"
    }

    private let kbsFormatter = KbsFormatter()

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return ObvMessengerSettings.VoIP.maxaveragebitratePossibleValues.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let currentMaxAverageBitrate = ObvMessengerSettings.VoIP.maxaveragebitratePossibleValues[indexPath.row]
        
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = currentMaxAverageBitrate == nil ? CommonString.Word.None : kbsFormatter.string(from: currentMaxAverageBitrate! as NSNumber)
        cell.selectionStyle = .none
        
        if currentMaxAverageBitrate == ObvMessengerSettings.VoIP.maxaveragebitrate {
            cell.accessoryType = .checkmark
        }
        
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        let selectedMaxAverageBitrate = ObvMessengerSettings.VoIP.maxaveragebitratePossibleValues[indexPath.row]
        ObvMessengerSettings.VoIP.maxaveragebitrate = selectedMaxAverageBitrate
        
        tableView.reloadData()
        
    }
    
}
