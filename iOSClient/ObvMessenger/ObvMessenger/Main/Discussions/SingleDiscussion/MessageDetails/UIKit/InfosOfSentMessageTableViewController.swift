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

/// This class serves as a superclass for concrete UITableViewController subclasses
class InfosOfSentMessageTableViewController: UITableViewController {

    // MARK: - Open API

    open var persistedMessageSent: PersistedMessageSent!

    // MARK: - Variables

    var _sortedMetadata: [(PersistedMessage.MetadataKind, Date)] {
        persistedMessageSent.sortedMetadata
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
            guard self?.persistedMessageSent.objectID == messageObjectID else { return }
            DispatchQueue.main.async { self?.tableView.reloadData() }
        })
    }

}
