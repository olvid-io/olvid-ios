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

class InfosOfSentMessageInGroupDiscussionTableViewController: InfosOfSentMessageTableViewController {

    // MARK: - Variables

    private var unsortedInfos: Set<PersistedMessageSentRecipientInfos> {
        assert(Thread.isMainThread)
        return persistedMessageSent.unsortedRecipientsInfos
    }

    private var readInfos: [PersistedMessageSentRecipientInfos] {
        let infos = unsortedInfos.filter { $0.timestampRead != nil }
        return infos.sorted { $0.timestampRead! < $1.timestampRead! }
            .sorted { $0.recipientName < $1.recipientName }
            .sorted { $0.recipientCryptoId < $1.recipientCryptoId }
    }
    
    private var deliveredInfos: [PersistedMessageSentRecipientInfos] {
        let infos = unsortedInfos.filter { $0.timestampRead == nil && $0.timestampDelivered != nil }
        return infos.sorted { $0.timestampDelivered! < $1.timestampDelivered! }
            .sorted { $0.recipientName < $1.recipientName }
            .sorted { $0.recipientCryptoId < $1.recipientCryptoId }
    }
    
    private var sentInfos: [PersistedMessageSentRecipientInfos] {
        let infos = unsortedInfos.filter { $0.timestampRead == nil && $0.timestampDelivered == nil && $0.timestampMessageSent != nil }
        return infos.sorted { $0.timestampMessageSent! < $1.timestampMessageSent! }
            .sorted { $0.recipientName < $1.recipientName }
            .sorted { $0.recipientCryptoId < $1.recipientCryptoId }
    }
    
    private var pendingInfos: [PersistedMessageSentRecipientInfos] {
        let infos = unsortedInfos.filter { $0.timestampRead == nil && $0.timestampDelivered == nil && $0.timestampMessageSent == nil }
        return infos.sorted { $0.timestampMessageSent! < $1.timestampMessageSent! }
            .sorted { $0.recipientName < $1.recipientName }
            .sorted { $0.recipientCryptoId < $1.recipientCryptoId }
    }
    
    private var displayedInfos: [(title: String, data: [(name: String, timestamp: Date?)])] {
        var infos = [(title: String, data: [(name: String, timestamp: Date?)])]()
        if !readInfos.isEmpty {
            infos.append((CommonString.Word.Read, readInfos.map { ($0.recipientName, $0.timestampRead!) }))
        }
        if !deliveredInfos.isEmpty {
            infos.append((CommonString.Word.Delivered, deliveredInfos.map { ($0.recipientName, $0.timestampDelivered!) }))
        }
        if !sentInfos.isEmpty {
            infos.append((CommonString.Word.Sent, sentInfos.map { ($0.recipientName, $0.timestampMessageSent!) }))
        }
        if !pendingInfos.isEmpty {
            infos.append((CommonString.Word.Pending, pendingInfos.map { ($0.recipientName, nil) }))
        }
        if !_sortedMetadata.isEmpty {
            infos.append((CommonString.Word.Metadata, _sortedMetadata.map { ($0.description, $1 )}))
        }
        return infos
    }

    private var unsortedInfosObjectIDs: [NSManagedObjectID] {
        return unsortedInfos.map { $0.objectID }
    }

    // MARK: - Observing PersistedMessageSentRecipientInfos updates

    override func viewDidLoad() {
        super.viewDidLoad()
        assert(unsortedInfos.first?.messageSent.discussion is PersistedGroupDiscussion)
        tableView.allowsSelection = false
        observeUpdates()
    }


    override func numberOfSections(in tableView: UITableView) -> Int {
        displayedInfos.count
    }
    
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        displayedInfos[section].data.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let infos = displayedInfos[indexPath.section].data[indexPath.row]
        let cell = UITableViewCell(style: UITableViewCell.CellStyle.value1, reuseIdentifier: nil)
        cell.textLabel?.text = infos.name
        if let timestamp = infos.timestamp {
            cell.detailTextLabel?.text = _dateFormater.string(from: timestamp)
        }
        cell.selectionStyle = .none
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return displayedInfos[section].title
    }
    
    
    private func observeUpdates() {

        let NotificationName = Notification.Name.NSManagedObjectContextDidSave
        let token = NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: OperationQueue.main) { [weak self] (notification) in
            
            assert(Thread.current.isMainThread)
            
            guard let _self = self else { return }
            guard let userInfo = notification.userInfo else { return }

            var doReloadData = false

            if let insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> {
                let insertedInfos = insertedObjects.filter { $0 is PersistedMessageSentRecipientInfos }
                doReloadData = doReloadData || !insertedInfos.isEmpty
            }

            if let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
                let updatedInfos = updatedObjects.filter { $0 is PersistedMessageSentRecipientInfos }
                let importantInfos = updatedInfos.filter { _self.unsortedInfosObjectIDs.contains($0.objectID) }
                doReloadData = doReloadData || !importantInfos.isEmpty
            }

            if doReloadData {
                self?.tableView.reloadData()
            }

        }
        _notificationTokens.append(token)
    }

}
