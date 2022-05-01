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
import CoreData

class InfosOfReceivedMessageTableViewController: UITableViewController {

    // MARK: - Open API

    open var persistedMessageReceived: PersistedMessageReceived!

    // MARK: - Variables

    var _sortedMetadata: [(PersistedMessage.MetadataKind, Date)] {
        persistedMessageReceived.sortedMetadata
    }

    var _notificationTokens = [NSObjectProtocol]()

    let _dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .short
        df.timeStyle = .short
        df.locale = Locale.current
        return df
    }()

    // MARK: - Constructors

    init() {
        super.init(style: .grouped)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    // MARK: - Observing Metadata updates

    override func viewDidLoad() {
        super.viewDidLoad()
        _observeNewMetadataInsertion()
    }

    private func _observeNewMetadataInsertion() {
        _notificationTokens.append(ObvMessengerCoreDataNotification.observePersistedMessageHasNewMetadata(queue: OperationQueue.main) { [weak self] (messageObjectID) in
            guard self?.persistedMessageReceived.objectID == messageObjectID else { return }
            DispatchQueue.main.async { self?.tableView.reloadData() }
        })
    }

    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        guard persistedMessageReceived != nil else { return 0 }
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard persistedMessageReceived != nil else { return 0 }
        return _sortedMetadata.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell.init(style: UITableViewCell.CellStyle.value1, reuseIdentifier: nil)
        cell.selectionStyle = .none

        let metadataIdx = indexPath.row
        let (kind, date) = _sortedMetadata[metadataIdx]
        cell.textLabel?.text = kind.description
        cell.detailTextLabel?.text = _dateFormater.string(from: date)

        return cell
    }

}
