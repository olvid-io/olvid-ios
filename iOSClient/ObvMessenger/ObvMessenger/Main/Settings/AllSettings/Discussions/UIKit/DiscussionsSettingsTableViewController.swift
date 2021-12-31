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

class DiscussionsSettingsTableViewController: UITableViewController {

    init() {
        super.init(style: .grouped)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Word.Discussions
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
    
}

// MARK: - UITableViewDataSource

extension DiscussionsSettingsTableViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        if #available(iOS 13, *) {
            // Include the section for rich link previews
            return 2
        } else {
            return 1
        }
    }
    
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return 1
        default: return 0
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell: UITableViewCell
        
        switch indexPath {
        case IndexPath(row: 0, section: 0):
            let _cell = ObvTitleAndSwitchTableViewCell(reuseIdentifier: "SendReadReceiptCell")
            _cell.selectionStyle = .none
            _cell.title = CommonString.Title.sendReadRecceipts
            _cell.switchIsOn = ObvMessengerSettings.Discussions.doSendReadReceipt
            _cell.blockOnSwitchValueChanged = { (value) in
                ObvMessengerSettings.Discussions.doSendReadReceipt = value
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) {
                    tableView.reloadData()
                }
            }
            cell = _cell
        case IndexPath(row: 0, section: 1):
            cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = Strings.RichLinks.title
            switch ObvMessengerSettings.Discussions.doFetchContentRichURLsMetadata {
            case .never:
                cell.detailTextLabel?.text = CommonString.Word.Never
            case .withinSentMessagesOnly:
                cell.detailTextLabel?.text = Strings.RichLinks.sentMessagesOnly
            case .always:
                cell.detailTextLabel?.text = CommonString.Word.Always
            }
            cell.accessoryType = .disclosureIndicator

        default:
            cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            assert(false)
        }
        
        return cell
    }
    
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        return ObvMessengerSettings.Discussions.doSendReadReceipt ? Strings.SendReadRecceipts.explanationWhenYes : Strings.SendReadRecceipts.explanationWhenNo
    }
    
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath {
        case IndexPath(row: 0, section: 1):
            let vc = FetchContentRichURLsMetadataChooserTableViewController()
            self.navigationController?.pushViewController(vc, animated: true)
        default:
            break
        }
    }

}
