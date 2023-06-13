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
  

import Foundation
import UIKit
import ObvUICoreData

class GracePeriodsChooserTableViewController: UITableViewController {

    let dateComponentsFormatter: DateComponentsFormatter = {
        let df = DateComponentsFormatter()
        df.allowedUnits = [.hour, .minute, .second]
        df.unitsStyle = .full
        return df
    }()

    init() {
        super.init(style: Self.settingsTableStyle)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Title.gracePeriod
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return ObvMessengerSettings.Privacy.gracePeriods.count
    }


    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let gracePeriod = ObvMessengerSettings.Privacy.gracePeriods[indexPath.row]

        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)

        if gracePeriod == 0 {
            cell.textLabel?.text = CommonString.Word.Immediately
        } else if let duration = dateComponentsFormatter.string(from: gracePeriod) {
            cell.textLabel?.text = CommonString.gracePeriodTitle(duration)
        } else {
            assertionFailure()
        }

        cell.selectionStyle = .none

        if gracePeriod == ObvMessengerSettings.Privacy.lockScreenGracePeriod {
            cell.accessoryType = .checkmark
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let gracePeriod = ObvMessengerSettings.Privacy.gracePeriods[indexPath.row]

        ObvMessengerSettings.Privacy.lockScreenGracePeriod = gracePeriod
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if ObvMessengerSettings.Privacy.lockScreenGracePeriod == 0 {
            return PrivacyTableViewController.Strings.noGracePeriodExplanation
        } else {
            guard let duration = dateComponentsFormatter.string(from: ObvMessengerSettings.Privacy.lockScreenGracePeriod) else {
                assertionFailure(); return nil
            }
            return PrivacyTableViewController.Strings.gracePeriodExplanation(duration)
        }
    }

}
