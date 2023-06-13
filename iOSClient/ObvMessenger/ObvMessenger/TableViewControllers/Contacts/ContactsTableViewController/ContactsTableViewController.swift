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
import ObvTypes
import ObvUICoreData
import ObvUI


class ContactsTableViewController: UITableViewController {
    
    // API
    
    let allowDeletion: Bool
    let disableContactsWithoutDevice: Bool
    let oneToOneStatus: PersistedObvContactIdentity.OneToOneStatus
    var titleChipTextForIdentity = [ObvCryptoId: String]()
    var cellBackgroundColor: UIColor?
    var customSelectionStyle = CustomSelectionStyle.system
    
    var predicate: NSPredicate! {
        didSet {
            self.fetchedResultsController = PersistedObvContactIdentity.getFetchedResultsController(predicate: predicate, whereOneToOneStatusIs: oneToOneStatus, within: ObvStack.shared.viewContext)
        }
    }
    private var fetchedResultsController: NSFetchedResultsController<PersistedObvContactIdentity>! {
        didSet {
            if let fetchedResultsController = self.fetchedResultsController {
                fetchedResultsController.delegate = self
                do {
                    try fetchedResultsController.performFetch()
                } catch let error {
                    fatalError("Failed to fetch entities: \(error.localizedDescription)")
                }
            }
        }
    }
    
    var extraBottomInset: CGFloat = 0.0 {
        didSet {
            resetTableViewContentInset()
        }
    }
    
    private func resetTableViewContentInset() {
        self.tableView?.contentInset = UIEdgeInsets(top: 0,
                                                    left: 0,
                                                    bottom: self.extraBottomInset,
                                                    right: 0)
    }
    
    // Selection style
    
    enum CustomSelectionStyle {
        case none
        case system // Default style
        case checkmark
        case xmark
    }
    
    // Constants
    
    private let defaultRowAnimation = UITableView.RowAnimation.automatic
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ContactsTableViewController.self))
    
    // Other variables
    
    private var kvObservations = [NSKeyValueObservation]()
    private var tableViewHeightAnchorConstraint: NSLayoutConstraint?
    private var notificationTokens = [NSObjectProtocol]()

    // Delegate
    
    weak var delegate: ContactsTableViewControllerDelegate?

    // Implementing search
    
    private(set) var searchController: UISearchController!
    private var searchPredicate: NSPredicate? {
        didSet {
            if let searchPredicate = self.searchPredicate {
                let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, searchPredicate])
                self.fetchedResultsController = PersistedObvContactIdentity.getFetchedResultsController(predicate: compoundPredicate, whereOneToOneStatusIs: oneToOneStatus, within: ObvStack.shared.viewContext)
            } else {
                self.fetchedResultsController = PersistedObvContactIdentity.getFetchedResultsController(predicate: predicate, whereOneToOneStatusIs: oneToOneStatus, within: ObvStack.shared.viewContext)
            }
            tableView.reloadData()
            reSelectSelectedContacts()
        }
    }
    
    private func reSelectSelectedContacts() {
        guard self.tableView.allowsMultipleSelection else { return }
        DispatchQueue.main.async { [weak self] in
            guard let _self = self else { return }
            for selectedContact in _self.selectedContacts {
                guard let indexPath = _self.fetchedResultsController.indexPath(forObject: selectedContact) else { continue }
                _self.tableView.selectRow(at: indexPath, animated: false, scrollPosition: UITableView.ScrollPosition.none)
                // Depending on the selection style, we might have to update the cell look
                _self.applyCustomSelectionStyleForCellAtIndexPath(indexPath)
            }
        }
    }
    
    private var selectedContacts = Set<PersistedObvContactIdentity>()
    private var selectedContactsDuringLastSearch = [PersistedObvContactIdentity]() // Reset each time the user starts a search
    
    // MARK: - Initializer
    
    init(disableContactsWithoutDevice: Bool, oneToOneStatus: PersistedObvContactIdentity.OneToOneStatus, allowDeletion: Bool = false) {
        self.disableContactsWithoutDevice = disableContactsWithoutDevice
        self.allowDeletion = allowDeletion
        self.oneToOneStatus = oneToOneStatus
        super.init(nibName: nil, bundle: nil)
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    
    // MARK: Mapping between index paths
    
    private func tvIndexPathFromFrcIndexPath(_ frcIndexPath: IndexPath) -> IndexPath {
        return frcIndexPath
    }
    
    
    private func frcIndexPathFromTvIndexPath(_ tvIndexPath: IndexPath) -> IndexPath {
        return tvIndexPath
    }
    
}


// MARK: - View Controller Lifecycle

extension ContactsTableViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.tableView?.refreshControl = nil
        self.tableView?.rowHeight = UITableView.automaticDimension
        self.tableView?.estimatedRowHeight = UITableView.automaticDimension

        resetTableViewContentInset()
        registerTableViewCell()
        configureSearchController()
        
        definesPresentationContext = false
        
        observeIdentityColorStyleDidChangeNotifications()
    }

    
    private func observeIdentityColorStyleDidChangeNotifications() {
        let token = ObvMessengerSettingsNotifications.observeIdentityColorStyleDidChange {
            DispatchQueue.main.async {  [weak self] in
                self?.tableView.reloadData()
            }
        }
        self.notificationTokens.append(token)
    }

    
    private func configureSearchController() {
        self.searchController = UISearchController(searchResultsController: nil)
        self.searchController.searchResultsUpdater = self
                
        self.searchController.obscuresBackgroundDuringPresentation = false
        self.searchController.hidesNavigationBarDuringPresentation = true
        self.searchController.delegate = self
    }
    
    
    private func registerTableViewCell() {
        let nib = UINib(nibName: ObvSubtitleTableViewCell.nibName, bundle: nil)
        self.tableView?.register(nib, forCellReuseIdentifier: ObvSubtitleTableViewCell.identifier)
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if searchPredicate != nil {
            self.searchController.isActive = true
        }
    }
    

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        selectedContactsDuringLastSearch.removeAll()
    }

}


// MARK: - NSFetchedResultsControllerDelegate and helpers

extension ContactsTableViewController: NSFetchedResultsControllerDelegate {

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        assert(Thread.current == Thread.main)
        tableView?.beginUpdates()
    }
    
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at frcIndexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath newFrcIndexPath: IndexPath?) {
        
        switch type {
        case .insert:
            let newTvIndexPath = tvIndexPathFromFrcIndexPath(newFrcIndexPath!)
            tableView?.insertRows(at: [newTvIndexPath], with: defaultRowAnimation)
        case .delete:
            let tvIndexPath = tvIndexPathFromFrcIndexPath(frcIndexPath!)
            tableView?.deleteRows(at: [tvIndexPath], with: defaultRowAnimation)
        case .update:
            guard let contact = anObject as? PersistedObvContactIdentity else { return }
            let tvIndexPath = tvIndexPathFromFrcIndexPath(frcIndexPath!)
            configureCell(atIndexPath: tvIndexPath, with: contact)
        case .move:
            guard let contact = anObject as? PersistedObvContactIdentity else { return }
            let tvIndexPath = tvIndexPathFromFrcIndexPath(frcIndexPath!)
            let newTvIndexPath = tvIndexPathFromFrcIndexPath(newFrcIndexPath!)
            configureCell(atIndexPath: tvIndexPath, with: contact)
            tableView?.moveRow(at: tvIndexPath, to: newTvIndexPath)
        @unknown default:
            assertionFailure()
        }
        
    }
    
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView?.endUpdates()
    }

}


// MARK: - Table view data source

extension ContactsTableViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        guard fetchedResultsController.sections != nil else { return 0 }
        return fetchedResultsController.sections!.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionInfo = fetchedResultsController.sections![section]
        return sectionInfo.numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ObvSubtitleTableViewCell.identifier) as! ObvSubtitleTableViewCell
        // Configure the selection style
        switch customSelectionStyle {
        case .none: cell.selectionStyle = .none
        case .system: cell.selectionStyle = .default
        case .checkmark: cell.selectionStyle = .none
        case .xmark: cell.selectionStyle = .none
        }
        configure(cell, withObjectAtIndexPath: indexPath)
        return cell
    }

    
    private func configureCell(atIndexPath indexPath: IndexPath, with contact: PersistedObvContactIdentity) {
        guard let cell = tableView?.cellForRow(at: indexPath) as? ObvSubtitleTableViewCell else { return }
        configure(cell, with: contact)
    }
    
    
    private func configure(_ cell: ObvSubtitleTableViewCell, withObjectAtIndexPath frcIndexPath: IndexPath) {
        let contact = fetchedResultsController.object(at: frcIndexPath)
        configure(cell, with: contact)
    }

    
    private func configure(_ cell: ObvSubtitleTableViewCell, with contact: PersistedObvContactIdentity) {
        if let customDisplayName = contact.customDisplayName {
            cell.title = customDisplayName
            cell.subtitle = contact.identityCoreDetails?.getDisplayNameWithStyle(.full) ?? contact.fullDisplayName
        } else {
            cell.title = contact.identityCoreDetails?.getDisplayNameWithStyle(.firstNameThenLastName) ?? contact.fullDisplayName
            cell.subtitle = contact.identityCoreDetails?.getDisplayNameWithStyle(.positionAtCompany) ?? ""
        }
        cell.circledInitialsConfiguration = contact.circledInitialsConfiguration
        switch contact.status {
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
        if contact.devices.isEmpty {
            cell.startSpinner()
        } else {
            cell.stopSpinner()
        }
        if let titleChipText = titleChipTextForIdentity[contact.cryptoId] {
            cell.setTitleChip(text: titleChipText)
        } else {
            cell.removeTitleChip()
        }
        
        if let cellBackgroundColor = self.cellBackgroundColor {
            cell.backgroundColor = cellBackgroundColor
        }
        
        if selectedContacts.contains(contact) {
            applyCustomSelectionStyleForCell(cell)
        }

    }

}


// MARK: - Table view delegate

extension ContactsTableViewController {
    
    override func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let configuration = UISwipeActionsConfiguration(actions: [])
        return configuration
    }
    
    
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let log = self.log
        let frcIndexPath: IndexPath
        frcIndexPath = indexPath
        guard allowDeletion else {
            let configuration = UISwipeActionsConfiguration(actions: [])
            return configuration
        }
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] (action, view, handler) in
            guard let contact = self?.fetchedResultsController.object(at: frcIndexPath) else { return }
            guard let ownedIdentity = contact.ownedIdentity else {
                os_log("Could not find owned identity. This is ok if it was just deleted.", log: log, type: .error)
                return
            }
            self?.delegate?.userWantsToDeleteContact(with: contact.cryptoId, forOwnedCryptoId: ownedIdentity.cryptoId, completionHandler: handler)
        }
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
    
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let frcIndexPath: IndexPath
        frcIndexPath = indexPath
        let persistedContactIdentity = fetchedResultsController.object(at: frcIndexPath)
        
        guard !disableContactsWithoutDevice || !persistedContactIdentity.devices.isEmpty else {
            return
        }
        
        selectedContacts.insert(persistedContactIdentity)
        
        if !selectedContactsDuringLastSearch.contains(persistedContactIdentity) {
            selectedContactsDuringLastSearch.append(persistedContactIdentity)
        }
        
        delegate?.userDidSelect(persistedContactIdentity)
        
        // Depending on the selection style, we might have to update the cell look
        applyCustomSelectionStyleForCellAtIndexPath(indexPath)
    }
    
    
    private func applyCustomSelectionStyleForCellAtIndexPath(_ indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) as? ObvSubtitleTableViewCell else { assertionFailure(); return }
        applyCustomSelectionStyleForCell(cell)
    }
    
    
    private func applyCustomSelectionStyleForCell(_ cell: ObvSubtitleTableViewCell) {
        // Depending on the selection style, we might have to update the cell look
        switch customSelectionStyle {
        case .none, .system:
            break // Nothing to do in that case
        case .checkmark:
            cell.setChipCheckmark()
        case .xmark:
            cell.setChipXmark()
        }
    }
    
    private func removeCustomSelectionStyleForCellAtIndexPath(_ indexPath: IndexPath) {
        switch customSelectionStyle {
        case .none, .system:
            break // Nothing to do in that case
        case .checkmark,
             .xmark:
            let cell = tableView.cellForRow(at: indexPath) as? ObvSubtitleTableViewCell
            assert(cell != nil)
            cell?.removeChipLabelAndChipImageView()
        }
    }
    
    
    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        let frcIndexPath: IndexPath
        frcIndexPath = indexPath
        
        let persistedContactIdentity = fetchedResultsController.object(at: frcIndexPath)
        
        selectedContacts.remove(persistedContactIdentity)
        
        if let index = selectedContactsDuringLastSearch.lastIndex(of: persistedContactIdentity) {
            selectedContactsDuringLastSearch.remove(at: index)
        }

        delegate?.userDidDeselect(persistedContactIdentity)
        
        // Depending on the selection style, we might have to update the cell look
        removeCustomSelectionStyleForCellAtIndexPath(indexPath)
    }
}


// MARK: - Other methods

extension ContactsTableViewController {
    
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
    func selectRowOfContactIdentity(_ contactIdentity: PersistedObvContactIdentity) {
        guard let tableView = self.tableView else { return }
        if let ip = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: ip, animated: false)
        }
        guard let frcIp = fetchedResultsController.indexPath(forObject: contactIdentity) else { return }
        let tvIp = tvIndexPathFromFrcIndexPath(frcIp)
        tableView.selectRow(at: tvIp, animated: true, scrollPosition: .middle)
    }

}


// MARK: - UISearchResultsUpdating

extension ContactsTableViewController: UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {
        if let searchedText = searchController.searchBar.text, !searchedText.isEmpty {
            self.searchPredicate = NSPredicate(format: "%K contains[cd] %@",
                                               PersistedObvContactIdentity.Predicate.Key.fullDisplayName.rawValue, searchedText)
        } else {
            self.searchPredicate = nil
        }
    }
    
}


// MARK: - UISearchControllerDelegate

extension ContactsTableViewController: UISearchControllerDelegate {
    
    func willPresentSearchController(_ searchController: UISearchController) {
        selectedContactsDuringLastSearch.removeAll()
    }
    
    func didDismissSearchController(_ searchController: UISearchController) {
        // When the user dismisses the search, we scroll to the last selected contact
        guard let lastSelectedContact = selectedContactsDuringLastSearch.last else { return }
        guard let frcIndexPath = fetchedResultsController.indexPath(forObject: lastSelectedContact) else { return }
        let tvIndexPath = tvIndexPathFromFrcIndexPath(frcIndexPath)
        tableView.scrollToRow(at: tvIndexPath, at: UITableView.ScrollPosition.middle, animated: true)
    }
    
}
