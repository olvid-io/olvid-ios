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

class ContactsSortOrderChooserTableViewController: UITableViewController {

    let ownedCryptoId: ObvCryptoId
    private var notificationTokens = [NSObjectProtocol]()

    init(ownedCryptoId: ObvCryptoId) {
        self.ownedCryptoId = ownedCryptoId
        super.init(style: Self.settingsTableStyle)
        observeContactsSortOrderDidChangeNotifications()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = ""
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return ContactsSortOrder.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let sortOrder = ContactsSortOrder.allCases[indexPath.row]

        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = sortOrder.description
        cell.selectionStyle = .none

        let currentContactsSortOrder = ObvMessengerSettings.Interface.contactsSortOrder
        if currentContactsSortOrder == sortOrder {
            cell.accessoryType = .checkmark
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        let sortOrder = ContactsSortOrder.allCases[indexPath.row]

        ObvMessengerInternalNotification.userWantsToChangeContactsSortOrder(ownedCryptoId: ownedCryptoId,
                                                                            sortOrder: sortOrder).postOnDispatchQueue()

        tableView.reloadData()
    }


    private func observeContactsSortOrderDidChangeNotifications() {
        let token = ObvMessengerInternalNotification.observeContactsSortOrderDidChange(queue: OperationQueue.main) {
            self.tableView.reloadData()
        }
        notificationTokens.append(token)
    }


}
