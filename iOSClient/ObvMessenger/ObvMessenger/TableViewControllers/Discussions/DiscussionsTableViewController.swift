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
import ObvTypes

class DiscussionsTableViewController: UITableViewController {
    
    enum CellSelectionStyle {
        case none
        case permanent
        case transient
        case automatic
    }
    
    // API

    private var allFetchRequests: [NSFetchRequest<PersistedDiscussion>] = [] {
        didSet {
            guard !allFetchRequests.isEmpty else { return }
            self.fetchRequest = allFetchRequests.first!
        }
    }
    
    private var allSegmentImages: [UIImage] = []
    
    private var fetchRequest: NSFetchRequest<PersistedDiscussion>! {
        didSet {
            self.fetchedResultsController = PersistedDiscussion.getFetchedResultsController(fetchRequest: fetchRequest, within: ObvStack.shared.viewContext)
        }
    }

    private var fetchedResultsController: NSFetchedResultsController<PersistedDiscussion>! {
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

    // Private vars
    
    private var spinner: UIRefreshControl?
    private let allowDeletion: Bool
    private let ownedCryptoId: ObvCryptoId
    
    private var showSegmentedControl: Bool {
        return allFetchRequests.count > 1
    }

    var cellSelectionStyle: CellSelectionStyle = .automatic
    
    // Other variables
    
    private var itemChanges = [(type: NSFetchedResultsChangeType, indexPath: IndexPath?, newIndexPath: IndexPath?)]()
    private var kvObservations = [NSKeyValueObservation]()
    private var tableViewHeightAnchorConstraint: NSLayoutConstraint?

    // Mapping TV sections <-> frc sections
    
    private func frcSectionFromTvSection(_ tvSection: Int) -> Int {
        if showSegmentedControl {
            assert(tvSection > 0)
            return tvSection - 1
        } else {
            return tvSection
        }
    }
    
    private func tvSectionFromFrcSection(_ frcSection: Int) -> Int {
        if showSegmentedControl {
            return frcSection + 1
        } else {
            return frcSection
        }
    }
    
    private func frcIndexPathFromTvIndexPath(_ tvIndexPath: IndexPath) -> IndexPath {
        let frcSection = frcSectionFromTvSection(tvIndexPath.section)
        let frcItem = tvIndexPath.item
        return IndexPath(item: frcItem, section: frcSection)
    }

    private func tvIndexPathFromFrcIndexPath(_ frcIndexPath: IndexPath) -> IndexPath {
        let tvSection = tvSectionFromFrcSection(frcIndexPath.section)
        let tvItem = frcIndexPath.item
        return IndexPath(item: tvItem, section: tvSection)
    }

    // Constants
    
    private let defaultRowAnimation = UITableView.RowAnimation.automatic
    
    private let log: OSLog = OSLog(subsystem: "io.olvid.messenger", category: "DiscussionsTableViewController")
    
    // Delegate
    
    weak var delegate: DiscussionsTableViewControllerDelegate?

    
    // MARK: - Initializer
    
    init(ownedCryptoId: ObvCryptoId, allowDeletion: Bool, withRefreshControl: Bool) {
        self.ownedCryptoId = ownedCryptoId
        if withRefreshControl {
            spinner = UIRefreshControl()
        }
        self.allowDeletion = allowDeletion
        super.init(nibName: nil, bundle: nil)
    }
    
    func setFetchRequestsAndImages(_ fetchRequestsAndImages: [(NSFetchRequest<PersistedDiscussion>, UIImage)]) {
        self.allFetchRequests = fetchRequestsAndImages.map { $0.0 }
        self.allSegmentImages = fetchRequestsAndImages.map { $0.1 }
    }

    private var notificationTokens = [NSObjectProtocol]()
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


// MARK: - View Controller Lifecycle

extension DiscussionsTableViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.clearsSelectionOnViewWillAppear = true
        self.tableView?.refreshControl = nil
        self.tableView?.rowHeight = UITableView.automaticDimension
        self.tableView?.estimatedRowHeight = UITableView.automaticDimension

        // This does not work in landscape under iOS12. We decided not to fix this.
        self.tableView?.refreshControl = self.spinner
        self.tableView?.refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        
        registerTableViewCell()
        
        observeIdentityColorStyleDidChangeNotifications()
        observeDiscussionLocalConfigurationHasBeenUpdatedNotifications()
        observeCallLogItemWasUpdatedNotifications()
    }

    
    private func observeIdentityColorStyleDidChangeNotifications() {
        let token = ObvMessengerInternalNotification.observeIdentityColorStyleDidChange(queue: OperationQueue.main) { [weak self] in
            self?.tableView.reloadData()
        }
        self.notificationTokens.append(token)
    }

    private func observeDiscussionLocalConfigurationHasBeenUpdatedNotifications() {
        let token = ObvMessengerInternalNotification.observeDiscussionLocalConfigurationHasBeenUpdated(queue: OperationQueue.main) { [weak self] value, objectId in
            guard case .muteNotificationsDuration = value else { return }
            self?.tableView.reloadData()
        }
        self.notificationTokens.append(token)
    }

    private func observeCallLogItemWasUpdatedNotifications() {
        let token = ObvMessengerInternalNotification.observeCallHasBeenUpdated(queue: OperationQueue.main) { [weak self] _, _ in
            self?.tableView.reloadData()
        }
        self.notificationTokens.append(token)
    }

    private func registerTableViewCell() {
        self.tableView?.register(UINib(nibName: ObvSubtitleTableViewCell.nibName, bundle: nil), forCellReuseIdentifier: ObvSubtitleTableViewCell.identifier)
        self.tableView?.register(UINib(nibName: ObvSegmentedControlTableViewCell.nibName, bundle: nil), forCellReuseIdentifier: ObvSegmentedControlTableViewCell.identifier)
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let indexPaths = tableView?.indexPathsForSelectedRows {
            indexPaths.forEach { tableView?.deselectRow(at: $0, animated: false) }
        }
    }
    
    @objc
    private func refresh() {
        let actionDate = Date()
        let completionHander = { [weak self] in
            let timeUntilStop: TimeInterval = max(0.0, 1.5 + actionDate.timeIntervalSinceNow) // The spinner should spin at least two second
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(Int(timeUntilStop*1000)), execute: { [weak self] in
                self?.tableView?.refreshControl?.endRefreshing()
            })
            return
        }
        delegate?.userAskedToRefreshDiscussions(completionHandler: completionHander)
    }
 
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        guard let splitViewController = splitViewController else { return }
        if splitViewController.isCollapsed {
            
        }
    }
    
}


// MARK: - NSFetchedResultsControllerDelegate and helpers

extension DiscussionsTableViewController: NSFetchedResultsControllerDelegate {

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at frcIndexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
                
        let newFrcIndexPath = newIndexPath

        switch type {
        case .insert:
            let newTvIndexPath = tvIndexPathFromFrcIndexPath(newFrcIndexPath!)
            tableView?.insertRows(at: [newTvIndexPath], with: defaultRowAnimation)
        case .delete:
            let tvIndexPath = tvIndexPathFromFrcIndexPath(frcIndexPath!)
            tableView?.deleteRows(at: [tvIndexPath], with: defaultRowAnimation)
        case .update:
            let tvIndexPath = tvIndexPathFromFrcIndexPath(frcIndexPath!)
            guard let discussion = anObject as? PersistedDiscussion else { return }
            configureCell(atIndexPath: tvIndexPath, with: discussion)
        case .move:
            let tvIndexPath = tvIndexPathFromFrcIndexPath(frcIndexPath!)
            let newTvIndexPath = tvIndexPathFromFrcIndexPath(newFrcIndexPath!)
            guard let discussion = anObject as? PersistedDiscussion else { return }
            configureCell(atIndexPath: tvIndexPath, with: discussion)
            tableView?.moveRow(at: tvIndexPath, to: newTvIndexPath)
        @unknown default:
            assertionFailure()
         }
        
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }
}


// MARK: - Table view data source

extension DiscussionsTableViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        if showSegmentedControl {
            return fetchedResultsController.sections!.count + 1
        } else {
            return fetchedResultsController.sections!.count
        }
    }

    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection tvSection: Int) -> Int {
        guard !(showSegmentedControl && tvSection == 0) else {
            return 1
        }
        let frcSection = frcSectionFromTvSection(tvSection)
        let sectionInfo = fetchedResultsController.sections![frcSection]
        return sectionInfo.numberOfObjects
    }
    
    
    override func tableView(_ tableView: UITableView, cellForRowAt tvIndexPath: IndexPath) -> UITableViewCell {
        guard !(showSegmentedControl && tvIndexPath.section == 0) else {
            let cell = tableView.dequeueReusableCell(withIdentifier: ObvSegmentedControlTableViewCell.identifier) as! ObvSegmentedControlTableViewCell
            cell.delegate = self
            cell.selectionStyle = .none
            for index in 0..<self.allFetchRequests.count {
                assert(index < allSegmentImages.count)
                cell.segmentedControl.insertSegment(with: allSegmentImages[index], at: index, animated: false)
            }
            cell.segmentedControl.selectedSegmentIndex = allFetchRequests.firstIndex(of: fetchRequest) ?? 0
            return cell
        }
        let frcIndexPath = frcIndexPathFromTvIndexPath(tvIndexPath)
        let cell = tableView.dequeueReusableCell(withIdentifier: ObvSubtitleTableViewCell.identifier) as! ObvSubtitleTableViewCell
        cell.selectionStyle = .none
        configure(cell, withObjectAtIndexPath: frcIndexPath)
        switch self.cellSelectionStyle {
        case .none: cell.selectionStyle = .none
        case .permanent: cell.selectionStyle = .default
        case .transient: cell.selectionStyle = .none
        case .automatic:
            if let splitViewController = splitViewController, !splitViewController.isCollapsed {
                cell.selectionStyle = .none
            } else {
                cell.selectionStyle = .default
            }
        }
        return cell
    }

    
    private func configureCell(atIndexPath indexPath: IndexPath, with discussion: PersistedDiscussion) {
        guard let cell = tableView?.cellForRow(at: indexPath) as? ObvSubtitleTableViewCell else { return }
        configure(cell, with: discussion)
    }

    
    private func configure(_ cell: ObvSubtitleTableViewCell, withObjectAtIndexPath indexPath: IndexPath) {
        let discussion = fetchedResultsController.object(at: indexPath)
        configure(cell, with: discussion)
    }

    
    private func configure(_ cell: ObvSubtitleTableViewCell, with discussion: PersistedDiscussion) {
        cell.title = discussion.title
        if let oneToOneDiscussion = discussion as? PersistedOneToOneDiscussion {
            cell.identityColors = oneToOneDiscussion.contactIdentity?.cryptoId.colors
            cell.circledImageURL = oneToOneDiscussion.contactIdentity?.customPhotoURL ?? oneToOneDiscussion.contactIdentity?.photoURL
            cell.showRedShield = (oneToOneDiscussion.contactIdentity?.isActive == false)
            cell.showGreenShield = (oneToOneDiscussion.contactIdentity?.isCertifiedByOwnKeycloak == true)
        } else if let groupDiscussion = discussion as? PersistedGroupDiscussion {
            cell.identityColors = AppTheme.shared.groupColors(forGroupUid: groupDiscussion.contactGroup?.groupUid ?? UID.zero)
            cell.circledImage = AppTheme.shared.images.groupImage
            cell.circledImageURL = groupDiscussion.contactGroup?.displayPhotoURL
            cell.showRedShield = false
            cell.showGreenShield = false
        } else {
            let lightColor = AppTheme.shared.colorScheme.secondarySystemBackground
            let darkColor = AppTheme.shared.colorScheme.secondarySystemFill
            cell.identityColors = (lightColor, darkColor)
            cell.circledImage = UIImage(named: "lock")
            cell.showRedShield = false
            cell.showGreenShield = false
        }

        do {
            cell.setDefaultSubtitleFont()
            if let message = try PersistedMessage.getAppropriateIllustrativeMessage(in: discussion) {
                if message.isLocallyWiped {
                    cell.subtitle = Strings.messageWasWiped
                    cell.makeSubtitleItalic()
                } else if message.isRemoteWiped {
                    cell.subtitle = Strings.lastMessageWasRemotelyWiped
                    cell.makeSubtitleItalic()
                } else if message is PersistedMessageSystem {
                    cell.subtitle = message.textBody ?? ""
                    cell.makeSubtitleItalic()
                } else if !message.readOnce && message.initialExistenceDuration == nil && message.visibilityDuration == nil {
                    cell.subtitle = message.textBody ?? ""
                    // If the subtitle is empty, there might be attachments
                    if let fyleMessageJoinWithStatus = message.fyleMessageJoinWithStatus, cell.subtitle.isEmpty, fyleMessageJoinWithStatus.count > 0 {
                        cell.subtitle = Strings.countAttachments(fyleMessageJoinWithStatus.count)
                        cell.makeSubtitleItalic()
                    }
                } else {
                    // Message with ephemerality, we should be careful
                    if let sentMessage = message as? PersistedMessageSent {
                        assert(!sentMessage.isWiped)
                        cell.subtitle = sentMessage.textBody ?? ""
                        // If the subtitle is empty, there might be attachments
                        if let fyleMessageJoinWithStatus = sentMessage.fyleMessageJoinWithStatus, cell.subtitle.isEmpty, fyleMessageJoinWithStatus.count > 0 {
                            cell.subtitle = Strings.countAttachments(fyleMessageJoinWithStatus.count)
                            cell.makeSubtitleItalic()
                        }
                    } else if let receivedMessage = message as? PersistedMessageReceived {
                        if message.readOnce || message.visibilityDuration != nil {
                            // Ephemeral received message with readOnce or limited visibility
                            switch receivedMessage.status {
                            case .new, .unread:
                                cell.subtitle = Strings.unreadEphemeralMessage
                                cell.makeSubtitleItalic()
                            case .read:
                                assert(!message.isWiped)
                                cell.subtitle = message.textBody ?? ""
                                // If the subtitle is empty, there might be attachments
                                if let fyleMessageJoinWithStatus = message.fyleMessageJoinWithStatus, cell.subtitle.isEmpty, fyleMessageJoinWithStatus.count > 0 {
                                    cell.subtitle = Strings.countAttachments(fyleMessageJoinWithStatus.count)
                                    cell.makeSubtitleItalic()
                                }
                            }
                        } else {
                            // Ephemeral received message with limited existence only
                            assert(!message.isWiped)
                            cell.subtitle = message.textBody ?? ""
                            // If the subtitle is empty, there might be attachments
                            if let fyleMessageJoinWithStatus = message.fyleMessageJoinWithStatus, cell.subtitle.isEmpty, fyleMessageJoinWithStatus.count > 0 {
                                cell.subtitle = Strings.countAttachments(fyleMessageJoinWithStatus.count)
                                cell.makeSubtitleItalic()
                            }
                        }
                    } else {
                        assertionFailure()
                        cell.subtitle = ""
                    }
                }
            } else {
                cell.subtitle = NSLocalizedString("NO_MESSAGE", comment: "")
                cell.makeSubtitleItalic()
            }
        } catch {
            os_log("Could not get last message in discussion", log: log, type: .error)
        }

        if discussion.shouldMuteNotifications {
            cell.setChipMute()
        } else {
            let numberOfNewMessages = discussion.computeNumberOfNewReceivedMessages()
            if numberOfNewMessages > 0 {
                cell.setChipLabel(text: "\(numberOfNewMessages)")
            } else {
                cell.removeChipLabelAndChipImageView()
            }
        }
    }
    
}


// MARK: - Table view delegate

extension DiscussionsTableViewController {
    
    override func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let configuration = UISwipeActionsConfiguration(actions: [])
        return configuration
    }
    
    
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt tvIndexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard allowDeletion else {
            let configuration = UISwipeActionsConfiguration(actions: [])
            return configuration
        }
        guard !(showSegmentedControl && tvIndexPath.section == 0) else {
            let configuration = UISwipeActionsConfiguration(actions: [])
            return configuration
        }
        let deleteAction = UIContextualAction(style: .destructive, title: CommonString.Word.Delete) { [weak self] (action, view, handler) in
            guard let frcIndexPath = self?.frcIndexPathFromTvIndexPath(tvIndexPath) else { return }
            guard let discussion = self?.fetchedResultsController.object(at: frcIndexPath) else { return }
            self?.delegate?.userAskedToDeleteDiscussion(discussion, completionHandler: handler)
        }
        let markAllAsNotNewAction = UIContextualAction(style: UIContextualAction.Style.normal, title: Strings.markAllAsRead) { [weak self] (action, view, handler) in
            guard let frcIndexPath = self?.frcIndexPathFromTvIndexPath(tvIndexPath) else { return }
            guard let discussion = self?.fetchedResultsController.object(at: frcIndexPath) else { return }
            ObvMessengerInternalNotification.userWantsToMarkAllMessagesAsNotNewWithinDiscussion(persistedDiscussionObjectID: discussion.objectID, completionHandler: handler)
                .postOnDispatchQueue()
        }
        let configuration = UISwipeActionsConfiguration(actions: [markAllAsNotNewAction, deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
    
    
    override func tableView(_ tableView: UITableView, didSelectRowAt tvIndexPath: IndexPath) {
        guard !(showSegmentedControl && tvIndexPath.section == 0) else { return }
        let frcIndexPath = frcIndexPathFromTvIndexPath(tvIndexPath)
        let discussion = fetchedResultsController.object(at: frcIndexPath)
        switch self.cellSelectionStyle {
        case .none, .permanent:
            break
        case .transient:
            highlightItem(at: tvIndexPath)
        case .automatic:
            if let splitViewController = splitViewController, !splitViewController.isCollapsed {
                highlightItem(at: tvIndexPath)
            }
        }
        delegate?.userDidSelect(persistedDiscussion: discussion)
    }
    
    
    private func highlightItem(at tvIndexPath: IndexPath) {
        guard !(showSegmentedControl && tvIndexPath.section == 0) else { return }
        guard let cell = tableView.cellForRow(at: tvIndexPath) else { return }
        let effectColor = AppTheme.shared.colorScheme.secondarySystemBackground
        cell.applyRippleEffect(withColor: effectColor)
    }
    
    override func tableView(_ tableView: UITableView, didDeselectRowAt tvIndexPath: IndexPath) {
        guard !(showSegmentedControl && tvIndexPath.section == 0) else { return }
        let frcIndexPath = frcIndexPathFromTvIndexPath(tvIndexPath)
        let discussion = fetchedResultsController.object(at: frcIndexPath)
        delegate?.userDidDeselect(discussion)
    }
}


// MARK: - ObvSegmentedControlTableViewCellDelegate

extension DiscussionsTableViewController: ObvSegmentedControlTableViewCellDelegate {
    
    func segmentedControlValueChanged(toIndex: Int) {
        guard showSegmentedControl else { return } // This means we will reload section 1
        self.fetchRequest = allFetchRequests[toIndex]
        tableView.reloadSections([1], with: .automatic)
    }
    
}

// MARK: - Other methods

extension DiscussionsTableViewController {

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
