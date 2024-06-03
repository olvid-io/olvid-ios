/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvUICoreData
import ObvSettings


final class DownloadsSettingsTableViewController: UITableViewController {

    init() {
        super.init(style: Self.settingsTableStyle)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.clearsSelectionOnViewWillAppear = true
        title = CommonString.Word.Downloads
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        default: return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell: UITableViewCell
        
        switch indexPath {
        case IndexPath(row: 0, section: 0):
            cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = CommonString.Word.Size
            cell.detailTextLabel?.text = Int64(ObvMessengerSettings.Downloads.maxAttachmentSizeForAutomaticDownload).obvFormattedWithPositiveByteCount
            cell.accessoryType = .disclosureIndicator
        default:
            cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            assert(false)
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        return DownloadsSettingsTableViewController.Strings.downloadSizeTitle
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        if ObvMessengerSettings.Downloads.maxAttachmentSizeForAutomaticDownload >= 0 {
            let sizeString = Int64(ObvMessengerSettings.Downloads.maxAttachmentSizeForAutomaticDownload).obvFormattedWithPositiveByteCount
            return DownloadsSettingsTableViewController.Strings.downloadSizeExplanation(sizeString)
        } else {
            return DownloadsSettingsTableViewController.Strings.downloadSizeExplanationWhenUnlimited
        }
    }
    
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath {
        case IndexPath(row: 0, section: 0):
            let vc = SizeChooserForAutomaticDownloadsTableViewController()
            self.navigationController?.pushViewController(vc, animated: true)
        default:
            break
        }
    }
}
