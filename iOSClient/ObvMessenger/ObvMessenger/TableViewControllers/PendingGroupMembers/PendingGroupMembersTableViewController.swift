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
import os.log
import CoreData
import ObvEngine
import ObvUICoreData
import ObvUI


class PendingGroupMembersTableViewController: UITableViewController {

    // API
    
    let fetchedResultsController: NSFetchedResultsController<PersistedPendingGroupMember>
    let cellSelectionStyle: UITableViewCell.SelectionStyle
    var cellBackgroundColor: UIColor?
    
    // Constants
    
    private let defaultRowAnimation = UITableView.RowAnimation.automatic
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: PendingGroupMembersTableViewController.self))
    
    // Other variables
    
    private var kvObservations = [NSKeyValueObservation]()
    private var tableViewHeightAnchorConstraint: NSLayoutConstraint?
    private var notificationTokens = [NSObjectProtocol]()

    weak var delegate: PendingGroupMembersTableViewControllerDelegate?
    
    // MARK: - Initializer
    
    init(fetchedResultsController: NSFetchedResultsController<PersistedPendingGroupMember>, cellSelectionStyle: UITableViewCell.SelectionStyle) {
        self.fetchedResultsController = fetchedResultsController
        self.cellSelectionStyle = cellSelectionStyle
        super.init(nibName: nil, bundle: nil)
        fetchedResultsController.delegate = self
    }

    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        kvObservations.removeAll()
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
}


// MARK: - View Controller Lifecycle

extension PendingGroupMembersTableViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.clearsSelectionOnViewWillAppear = true
        self.tableView?.refreshControl = nil
        self.tableView?.rowHeight = UITableView.automaticDimension
        self.tableView?.estimatedRowHeight = 44.0

        registerTableViewCell()

        do {
            try fetchedResultsController.performFetch()
        } catch let error {
            fatalError("Failed to fetch entities: \(error.localizedDescription)")
        }

        observeIdentityColorStyleDidChangeNotifications()
    }
    
    
    private func observeIdentityColorStyleDidChangeNotifications() {
        let token = ObvMessengerSettingsNotifications.observeIdentityColorStyleDidChange {
            DispatchQueue.main.async { [weak self] in
                self?.tableView.reloadData()
            }
        }
        self.notificationTokens.append(token)
    }

    
    private func registerTableViewCell() {
        let nib = UINib(nibName: ObvTitleTableViewCell.nibName, bundle: nil)
        self.tableView?.register(nib, forCellReuseIdentifier: ObvTitleTableViewCell.identifier)
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if let indexPaths = tableView?.indexPathsForSelectedRows {
            indexPaths.forEach { tableView?.deselectRow(at: $0, animated: false) }
        }
    }

}


// MARK: - NSFetchedResultsControllerDelegate and helpers

extension PendingGroupMembersTableViewController: NSFetchedResultsControllerDelegate {
    
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView?.beginUpdates()
    }

    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        
        switch type {
        case .insert:
            tableView?.insertRows(at: [newIndexPath!], with: defaultRowAnimation)
        case .delete:
            tableView?.deleteRows(at: [indexPath!], with: defaultRowAnimation)
        case .update:
            guard let pendingMember = anObject as? PersistedPendingGroupMember else { return }
            configureCell(atIndexPath: indexPath!, with: pendingMember)
        case .move:
            guard let pendingMember = anObject as? PersistedPendingGroupMember else { return }
            configureCell(atIndexPath: indexPath!, with: pendingMember)
            tableView?.moveRow(at: indexPath!, to: newIndexPath!)
        @unknown default:
            assertionFailure()
        }
        
    }

    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView?.endUpdates()
    }
    
}


// MARK: - Table view data source

extension PendingGroupMembersTableViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return fetchedResultsController.sections!.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionInfo = fetchedResultsController.sections![section]
        return sectionInfo.numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ObvTitleTableViewCell.identifier) as! ObvTitleTableViewCell
        configure(cell, withObjectAtIndexPath: indexPath)
        return cell
    }

    private func configureCell(atIndexPath indexPath: IndexPath, with pendingMember: PersistedPendingGroupMember) {
        guard let cell = tableView?.cellForRow(at: indexPath) as? ObvTitleTableViewCell else { return }
        configure(cell, with: pendingMember)
    }

    private func configure(_ cell: ObvTitleTableViewCell, withObjectAtIndexPath indexPath: IndexPath) {
        let pendingMember = fetchedResultsController.object(at: indexPath)
        configure(cell, with: pendingMember)
    }

    private func configure(_ cell: ObvTitleTableViewCell, with pendingMember: PersistedPendingGroupMember) {
        cell.title = pendingMember.identityCoreDetails.getDisplayNameWithStyle(.full)
        cell.identityColors = pendingMember.cryptoId.colors
        if pendingMember.declined {
            cell.sideTitle = Strings.invitationDeclined.localizedUppercase
            cell.sideLabel.numberOfLines = 2
        } else {
            cell.sideTitle = nil
        }
        cell.selectionStyle = self.cellSelectionStyle
        if let cellBackgroundColor = self.cellBackgroundColor {
            cell.backgroundColor = cellBackgroundColor
        }
    }

}


// MARK: - Other methods

extension PendingGroupMembersTableViewController {
    
    func constraintHeightToContentHeight(blockOnNewHeight: @escaping (CGFloat) -> Void) {
        self.tableView.isScrollEnabled = false
        self.view.layoutIfNeeded()
        let kvObservation = self.tableView.observe(\.contentSize) { [weak self] (object, change) in
            guard let _self = self else { return }
            _self.tableViewHeightAnchorConstraint?.isActive = false
            _self.tableViewHeightAnchorConstraint = _self.view.heightAnchor.constraint(equalToConstant: _self.tableView.contentSize.height)
            _self.tableViewHeightAnchorConstraint?.isActive = true
            blockOnNewHeight(_self.tableView.contentSize.height)
            _self.view.layoutIfNeeded()
        }
        kvObservations.append(kvObservation)
    }
    
}


// MARK: - Table view delegate

extension PendingGroupMembersTableViewController {
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let persistedPendingGroupMember = fetchedResultsController.object(at: indexPath)
        let completionHandler = {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        delegate?.userDidSelect(persistedPendingGroupMember, completionHandler: completionHandler)
        
    }
    
}
