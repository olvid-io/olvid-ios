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
import CoreData

final class InfosOfSentMessageInOneToOneDiscussionTableViewController: InfosOfSentMessageTableViewController {

    // MARK: - Variables

    private var infos: PersistedMessageSentRecipientInfos? {
        assert(Thread.isMainThread)
        return persistedMessageSent.unsortedRecipientsInfos.first
    }

    // MARK: - Observing PersistedMessageSentRecipientInfos updates

    override func viewDidLoad() {
        super.viewDidLoad()
        observePersistedMessageSentRecipientInfosUpdates()
    }
    
    private func observePersistedMessageSentRecipientInfosUpdates() {
        let NotificationName = Notification.Name.NSManagedObjectContextDidSave
        let token = NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { [weak self] (notification) in
            guard let _self = self else { return }
            guard let context = notification.object as? NSManagedObjectContext else { return }
            guard context.concurrencyType != .mainQueueConcurrencyType else { return }
            context.performAndWait {
                guard let userInfo = notification.userInfo else { return }
                guard let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> else { return }
                guard !updatedObjects.isEmpty else { return }
                let updatedInfos = updatedObjects.compactMap { $0 as? PersistedMessageSentRecipientInfos }
                guard !updatedInfos.isEmpty else { return }
                let objectIDs = updatedInfos.map { $0.objectID }
                DispatchQueue.main.async {
                    guard let infosObjectID = _self.infos?.objectID else { return }
                    guard objectIDs.contains(infosObjectID) else { return }
                    _self.persistedMessageSent.managedObjectContext?.mergeChanges(fromContextDidSave: notification)
                    self?.tableView.reloadData()
                }
            }
        }
        _notificationTokens.append(token)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        guard persistedMessageSent != nil else { return 0 }
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard persistedMessageSent != nil else { return 0 }
        return 3 + _sortedMetadata.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell.init(style: UITableViewCell.CellStyle.value1, reuseIdentifier: nil)
        cell.selectionStyle = .none
        
        cell.detailTextLabel?.text = "-"

        switch indexPath.row {
        case 0:
            cell.textLabel?.text = CommonString.Word.Read
            if let timestamp = infos?.timestampRead {
                cell.detailTextLabel?.text = _dateFormater.string(from: timestamp)
            }
        case 1:
            cell.textLabel?.text = CommonString.Word.Delivered
            if let timestamp = infos?.timestampDelivered {
                cell.detailTextLabel?.text = _dateFormater.string(from: timestamp)
            }
        case 2:
            cell.textLabel?.text = CommonString.Word.Sent
            if let timestamp = infos?.timestampMessageSent {
                cell.detailTextLabel?.text = _dateFormater.string(from: timestamp)
            } else {
                cell.detailTextLabel?.text = "-"
            }
        default:
            let metadataIdx = indexPath.row - 3
            let (kind, date) = _sortedMetadata[metadataIdx]
            cell.textLabel?.text = kind.description
            cell.detailTextLabel?.text = _dateFormater.string(from: date)
        }

        return cell
    }

}
