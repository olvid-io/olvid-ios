/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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



final class FetchContentRichURLsMetadataChooserTableViewController: UITableViewController {
    
    init() {
        super.init(style: Self.settingsTableStyle)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()        
        title = Strings.RichLinks.title
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 3
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let choiceForCell = ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice(rawValue: indexPath.row)!
                
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        switch choiceForCell {
        case .never:
            cell.textLabel?.text = CommonString.Word.Never
        case .withinSentMessagesOnly:
            cell.textLabel?.text = Strings.RichLinks.sentMessagesOnly
        case .always:
            cell.textLabel?.text = CommonString.Word.Always
        }
        cell.selectionStyle = .none
        
        if choiceForCell == ObvMessengerSettings.Discussions.doFetchContentRichURLsMetadata {
            cell.accessoryType = .checkmark
        }
        
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        guard let selected = ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice(rawValue: indexPath.row) else { return }
        
        ObvMessengerSettings.Discussions.doFetchContentRichURLsMetadata = selected
        
        tableView.reloadData()
        
    }
    
    
}


extension FetchContentRichURLsMetadataChooserTableViewController {
    
        struct Strings {
            struct RichLinks {
                static let title = NSLocalizedString("Rich link preview", comment: "Cell title")
                static let sentMessagesOnly = NSLocalizedString("Sent messages only", comment: "")
            }
        }
    
}
