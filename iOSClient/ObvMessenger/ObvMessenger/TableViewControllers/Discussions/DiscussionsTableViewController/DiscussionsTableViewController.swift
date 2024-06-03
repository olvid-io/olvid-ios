/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvCrypto
import ObvEngine
import ObvTypes
import ObvUI
import ObvUICoreData
import ObvDesignSystem
import ObvSettings


/// This view controller is replaced by NewDiscussionsViewController under iOS 16
@available(iOS, deprecated: 16.0, message: "Use NewDiscussionsViewController instead")
final class DiscussionsTableViewController: UITableViewController {
    
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
            let frcModel = FetchRequestControllerModel(fetchRequest: fetchRequest, sectionNameKeyPath: nil)
            self.fetchedResultsController = PersistedDiscussion.getFetchedResultsController(model: frcModel, within: ObvStack.shared.viewContext)
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
    
    private var showSegmentedControl: Bool {
        return allFetchRequests.count > 1
    }

    var cellSelectionStyle: CellSelectionStyle = .automatic
    
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
    
    @available(iOS, deprecated: 16.0, message: "Use NewDiscussionsViewController instead")
    init(allowDeletion: Bool, withRefreshControl: Bool) {
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
    
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
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

        self.tableView?.refreshControl = self.spinner
        self.tableView?.refreshControl?.addTarget(self, action: #selector(refreshControlWasPulledDown), for: .valueChanged)
        
        registerTableViewCell()
        
        observeIdentityColorStyleDidChangeNotifications()
        observeDiscussionLocalConfigurationHasBeenUpdatedNotifications()
    }

    
    private func observeIdentityColorStyleDidChangeNotifications() {
        let token = ObvMessengerSettingsNotifications.observeIdentityColorStyleDidChange {
            DispatchQueue.main.async { [weak self] in
                self?.tableView.reloadData()
            }
        }
        self.notificationTokens.append(token)
    }

    private func observeDiscussionLocalConfigurationHasBeenUpdatedNotifications() {
        let token = ObvMessengerCoreDataNotification.observeDiscussionLocalConfigurationHasBeenUpdated { [weak self] value, objectId in
            DispatchQueue.main.async {
                guard case .muteNotificationsEndDate = value else { return }
                self?.tableView.reloadData()
            }
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
    
    
    /// Callback for the refresh control when pulling down
    @objc private func refreshControlWasPulledDown() {
        Task { [weak self] in await self?.userAskedToRefreshDiscussions() }
    }
    
    
    @MainActor
    private func userAskedToRefreshDiscussions() async {
        guard let delegate else { assertionFailure(); return }
        
        do {
            
            let actionDate = Date()
            
            try await delegate.userAskedToRefreshDiscussions()
            
            let elapsedTime = Date.now.timeIntervalSince(actionDate)
            try? await Task.sleep(seconds: max(0, 1.5 - elapsedTime)) // Spin for at least 1.5 seconds
            
            tableView?.refreshControl?.endRefreshing()
            
        } catch {
            assertionFailure()
        }
        
    }
    
    
}


// MARK: - Switching current owned identity

extension DiscussionsTableViewController {
    
    @MainActor
    func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        setFetchRequestsAndImages(DiscussionsFetchRequests(ownedCryptoId: newOwnedCryptoId).allRequestsAndImages)
        tableView.reloadData()
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
        cell.circledInitialsConfiguration = discussion.circledInitialsConfiguration

        do {
            cell.setDefaultSubtitleFont()
            if let message = try PersistedMessage.getAppropriateIllustrativeMessage(in: discussion) {
                if message.isLocallyWiped {
                    cell.subtitle = PersistedMessage.Strings.messageWasWiped
                    cell.makeSubtitleItalic()
                } else if message.isRemoteWiped {
                    cell.subtitle = PersistedMessage.Strings.lastMessageWasRemotelyWiped
                    cell.makeSubtitleItalic()
                } else if message is PersistedMessageSystem {
                    cell.subtitle = message.textBody ?? ""
                    cell.makeSubtitleItalic()
                } else if !message.readOnce && message.initialExistenceDuration == nil && message.visibilityDuration == nil {
                    cell.subtitle = message.textBody ?? ""
                    // If the subtitle is empty, there might be attachments
                    if let fyleMessageJoinWithStatus = message.fyleMessageJoinWithStatus, cell.subtitle.isEmpty, fyleMessageJoinWithStatus.count > 0 {
                        cell.subtitle = PersistedMessage.Strings.countAttachments(fyleMessageJoinWithStatus.count)
                        cell.makeSubtitleItalic()
                    }
                } else {
                    // Message with ephemerality, we should be careful
                    if let sentMessage = message as? PersistedMessageSent {
                        assert(!sentMessage.isWiped)
                        cell.subtitle = sentMessage.textBody ?? ""
                        // If the subtitle is empty, there might be attachments
                        if let fyleMessageJoinWithStatus = sentMessage.fyleMessageJoinWithStatus, cell.subtitle.isEmpty, fyleMessageJoinWithStatus.count > 0 {
                            cell.subtitle = PersistedMessage.Strings.countAttachments(fyleMessageJoinWithStatus.count)
                            cell.makeSubtitleItalic()
                        }
                    } else if let receivedMessage = message as? PersistedMessageReceived {
                        if message.readOnce || message.visibilityDuration != nil {
                            // Ephemeral received message with readOnce or limited visibility
                            switch receivedMessage.status {
                            case .new, .unread:
                                cell.subtitle = PersistedMessage.Strings.unreadEphemeralMessage
                                cell.makeSubtitleItalic()
                            case .read:
                                assert(!message.isWiped)
                                cell.subtitle = message.textBody ?? ""
                                // If the subtitle is empty, there might be attachments
                                if let fyleMessageJoinWithStatus = message.fyleMessageJoinWithStatus, cell.subtitle.isEmpty, fyleMessageJoinWithStatus.count > 0 {
                                    cell.subtitle = PersistedMessage.Strings.countAttachments(fyleMessageJoinWithStatus.count)
                                    cell.makeSubtitleItalic()
                                }
                            }
                        } else {
                            // Ephemeral received message with limited existence only
                            assert(!message.isWiped)
                            cell.subtitle = message.textBody ?? ""
                            // If the subtitle is empty, there might be attachments
                            if let fyleMessageJoinWithStatus = message.fyleMessageJoinWithStatus, cell.subtitle.isEmpty, fyleMessageJoinWithStatus.count > 0 {
                                cell.subtitle = PersistedMessage.Strings.countAttachments(fyleMessageJoinWithStatus.count)
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

        if discussion.hasNotificationsMuted {
            cell.setChipMute()
        } else {
            let numberOfNewMessages = discussion.numberOfNewMessages
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
        let markAllAsNotNewAction = UIContextualAction(style: UIContextualAction.Style.normal, title: PersistedMessage.Strings.markAllAsRead) { [weak self] (action, view, handler) in
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


// MARK: - CanScrollToTop
extension DiscussionsTableViewController: CanScrollToTop {
    func scrollToTop() {
        guard tableView.numberOfRows(inSection: tableView.numberOfSections-1) > 0 else { return }
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
    }
}
