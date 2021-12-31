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
import os.log
import CoreData
import ObvEngine

class ContactGroupsTableViewController: UITableViewController {

    // API
    
    let fetchedResultsController: NSFetchedResultsController<PersistedContactGroup>
    
    var cellBackgroundColor: UIColor?
    
    // Constants
    
    private let defaultRowAnimation = UITableView.RowAnimation.automatic
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    
    // Other variables
    
    private var kvObservations = [NSKeyValueObservation]()
    private var tableViewHeightAnchorConstraint: NSLayoutConstraint?
    private var notificationTokens = [NSObjectProtocol]()

    // Delegate
    
    weak var delegate: ContactGroupsTableViewControllerDelegate?

    // MARK: - Initializer
    
    init(fetchedResultsController: NSFetchedResultsController<PersistedContactGroup>) {
        self.fetchedResultsController = fetchedResultsController
        super.init(nibName: nil, bundle: nil)
        fetchedResultsController.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tableView.reloadData()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


// MARK: - View Controller Lifecycle

extension ContactGroupsTableViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.clearsSelectionOnViewWillAppear = true
        self.tableView?.refreshControl = nil
        self.tableView?.rowHeight = UITableView.automaticDimension
        self.tableView?.estimatedRowHeight = UITableView.automaticDimension
        
        registerTableViewCell()

        do {
            try fetchedResultsController.performFetch()
        } catch let error {
            fatalError("Failed to fetch entities: \(error.localizedDescription)")
        }

        observeIdentityColorStyleDidChangeNotifications()
    }
    
    
    private func observeIdentityColorStyleDidChangeNotifications() {
        let token = ObvMessengerInternalNotification.observeIdentityColorStyleDidChange(queue: OperationQueue.main) { [weak self] in
            self?.tableView.reloadData()
        }
        self.notificationTokens.append(token)
    }

    
    private func registerTableViewCell() {
        let nib = UINib(nibName: ObvSubtitleTableViewCell.nibName, bundle: nil)
        self.tableView?.register(nib, forCellReuseIdentifier: ObvSubtitleTableViewCell.identifier)
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if let indexPaths = tableView?.indexPathsForSelectedRows {
            indexPaths.forEach { tableView?.deselectRow(at: $0, animated: false) }
        }
        
    }
    
}


// MARK: - NSFetchedResultsControllerDelegate and helpers

extension ContactGroupsTableViewController: NSFetchedResultsControllerDelegate {

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView?.beginUpdates()
    }


    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {

        switch type {
        case .insert:
            tableView?.insertSections([sectionIndex], with: defaultRowAnimation)
        case .delete:
            tableView?.deleteSections([sectionIndex], with: defaultRowAnimation)
        case .update:
            break
        case .move:
            break
        @unknown default:
            assertionFailure()
        }

    }


    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {

        switch type {
        case .insert:
            tableView?.insertRows(at: [newIndexPath!], with: defaultRowAnimation)
        case .delete:
            tableView?.deleteRows(at: [indexPath!], with: defaultRowAnimation)
        case .update:
            guard let contactGroup = anObject as? PersistedContactGroup else { return }
            configureCell(atIndexPath: indexPath!, with: contactGroup)
        case .move:
            guard let contactGroup = anObject as? PersistedContactGroup else { return }
            configureCell(atIndexPath: indexPath!, with: contactGroup)
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

extension ContactGroupsTableViewController {

    override func numberOfSections(in tableView: UITableView) -> Int {
        return fetchedResultsController.sections?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionInfo = fetchedResultsController.sections![section]
        return sectionInfo.numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ObvSubtitleTableViewCell.identifier) as! ObvSubtitleTableViewCell
        configure(cell, withObjectAtIndexPath: indexPath)
        return cell
    }

    private func configureCell(atIndexPath indexPath: IndexPath, with contactGroup: PersistedContactGroup) {
        guard let cell = tableView?.cellForRow(at: indexPath) as? ObvSubtitleTableViewCell else { return }
        configure(cell, with: contactGroup)
    }

    private func configure(_ cell: ObvSubtitleTableViewCell, withObjectAtIndexPath indexPath: IndexPath) {
        let contactGroup = fetchedResultsController.object(at: indexPath)
        configure(cell, with: contactGroup)
    }

    private func configure(_ cell: ObvSubtitleTableViewCell, with contactGroup: PersistedContactGroup) {
        cell.title = contactGroup.displayName
        cell.subtitle = (contactGroup.contactIdentities.map { $0.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName) }).joined(separator: ", ")
        if let photoURL = contactGroup.displayPhotoURL {
            cell.circledImageURL = photoURL
        } else {
            cell.circledImage = AppTheme.shared.images.groupImage
        }
        cell.identityColors = AppTheme.shared.groupColors(forGroupUid: contactGroup.groupUid)
        cell.showRedShield = false
        cell.showGreenShield = false
        if let contactGroupJoined = contactGroup as? PersistedContactGroupJoined {
            switch contactGroupJoined.status {
            case .noNewPublishedDetails:
                cell.removeChipLabelAndChipImageView()
            case .seenPublishedDetails:
                if let image = UIImage(named: "account_card_no_borders") {
                    cell.setChipImage(to: image, withBadge: false)
                }
            case .unseenPublishedDetails:
                if let image = UIImage(named: "account_card_no_borders") {
                    cell.setChipImage(to: image, withBadge: true)
                }

            }
        }

        if let cellBackgroundColor = self.cellBackgroundColor {
            cell.backgroundColor = cellBackgroundColor
        }
    }


    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sectionInfo = fetchedResultsController.sections?[section] else { return nil }
        switch sectionInfo.name {
        case "\(PersistedContactGroup.Category.owned.rawValue)":
            return Strings.ownedGroups
        case "\(PersistedContactGroup.Category.joined.rawValue)":
            return Strings.joinedGroups
        default:
            return nil
        }
    }
}


// MARK: - Table view delegate

extension ContactGroupsTableViewController {
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let contactGroup = fetchedResultsController.object(at: indexPath)
        delegate?.userDidSelect(contactGroup)
    }
    
}


// MARK: - Other methods

extension ContactGroupsTableViewController {
    
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
    
    
    /// This method is used when deeplinks need to navigate through the hierarchy
    func selectRowOfContactGroup(_ contactGroup: PersistedContactGroup) {
        guard let tableView = self.tableView else { return }
        if let ip = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: ip, animated: false)
        }
        let ip = fetchedResultsController.indexPath(forObject: contactGroup)
        tableView.selectRow(at: ip, animated: true, scrollPosition: .middle)
    }
}
