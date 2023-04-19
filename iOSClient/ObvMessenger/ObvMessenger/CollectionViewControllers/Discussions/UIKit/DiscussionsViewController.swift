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
  
import CoreData
import Foundation
import ObvTypes
import UIKit
import SwiftUI



/// This view controller is an iOS 16 replacement for the old `DiscussionsTableViewController`.
@available(iOS 16.0, *)
final class DiscussionsViewController: UIViewController {
    private enum Sections: CaseIterable {
        case segmentControl
        case discussions
    }
    
    private enum ListItemType: Hashable {
        case segmentControl
        case persistedDiscussion(TypeSafeManagedObjectID<PersistedDiscussion>)
    }

    private typealias SectionItem = Sections
    private typealias ListItemID = ListItemType
    private typealias Snapshot = NSDiffableDataSourceSnapshot<SectionItem, ListItemID>
    
    weak var delegate: DiscussionsTableViewControllerDelegate?
    
    private let fetchRequests: DiscussionsFetchRequests
    private var currentFetchRequest: NSFetchRequest<PersistedDiscussion>
    private var dataSource: UICollectionViewDiffableDataSource<SectionItem, ListItemID>!
    private weak var collectionView: UICollectionView!
    private var fetchedResultsController: NSFetchedResultsController<PersistedDiscussion>
    private var firstTimeFetch = true
    private var notificationTokens = [NSObjectProtocol]()
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(ownedCryptoId: ObvCryptoId) {
        self.fetchRequests = DiscussionsFetchRequests(ownedCryptoId: ownedCryptoId)
        self.currentFetchRequest = fetchRequests.forNonEmptyRecentDiscussionsForOwnedIdentity
        self.fetchedResultsController = PersistedDiscussion.getFetchedResultsController(fetchRequest: currentFetchRequest, within: ObvStack.shared.viewContext)
        super.init(nibName: nil, bundle: nil)
        self.fetchedResultsController.delegate = self
    }
}


// MARK: - Life Cycle
@available(iOS 16.0, *)
extension DiscussionsViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureDataSource()
        setInitialData()
        addObservers()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        collectionView.indexPathsForSelectedItems?.forEach({ [weak self] in
            self?.collectionView.deselectItem(at: $0, animated: false)
        })
    }
}


// MARK: - Setup
@available(iOS 16.0, *)
extension DiscussionsViewController {
    
    private func configureHierarchy() {
        let collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: createLayout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.refreshControl = UIRefreshControl()
        collectionView.refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        view.addSubview(collectionView)
        self.collectionView = collectionView
    }
    
    
    private func configureDataSource() {
        
        let segmentControlCellRegistration = UICollectionView.CellRegistration<DiscussionsFilterCell, AnyObject> { [weak self] cell, _, _ in
            guard let self else { return }
            let segmentImages = self.fetchRequests.allRequestsAndImages.map({ $0.image })
            let selectedSegmentIndex = self.fetchRequests.allRequestsAndImages.map({ $0.request }).firstIndex(of: self.currentFetchRequest) ?? 0
            cell.configure(segmentImages: segmentImages, selectedSegmentIndex: selectedSegmentIndex, delegate: self)
        }
        
        let discussionCellRegistration = UICollectionView.CellRegistration<DiscussionCell, PersistedDiscussion> { [weak self] cell, _, item in
            let content = DiscussionCell.Content(discussion: item)
            cell.configure(content: content, selectionStyle: (UIDevice.current.userInterfaceIdiom == .pad && self?.splitViewController != nil) ? .none : .default)
        }
        
        let invisibleCellRegistration = InvisibleCell.registration
        
        dataSource = UICollectionViewDiffableDataSource<SectionItem, ListItemID>(collectionView: collectionView) { (collectionView: UICollectionView, indexPath: IndexPath, itemID: ListItemID) -> UICollectionViewCell? in
            switch itemID {
            case .segmentControl:
                return collectionView.dequeueConfiguredReusableCell(using: segmentControlCellRegistration, for: indexPath, item: nil)
            case .persistedDiscussion(let listItemID):
                guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: listItemID, within: ObvStack.shared.viewContext) else {
                    return collectionView.dequeueConfiguredReusableCell(using: invisibleCellRegistration, for: indexPath, item: nil)
                }
                return collectionView.dequeueConfiguredReusableCell(using: discussionCellRegistration, for: indexPath, item: discussion)
            }
        }
    }
    
    
    private func setInitialData() {
        var snapshot = Snapshot()
        snapshot.appendSections(Sections.allCases)
        snapshot.appendItems([ListItemType.segmentControl], toSection: Sections.segmentControl)
        dataSource.apply(snapshot, animatingDifferences: false)
        
        do {
            try fetchedResultsController.performFetch()
        } catch let error {
            fatalError("Failed to fetch entities: \(error.localizedDescription)")
        }
    }
    
    
    private func createLayout() -> UICollectionViewLayout {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.trailingSwipeActionsConfigurationProvider = { [weak self] tvIndexPath in
            guard let selectedItem = self?.dataSource.itemIdentifier(for: tvIndexPath) else { return UISwipeActionsConfiguration(actions: []) }
            switch selectedItem {
            case .persistedDiscussion(let listItemID):
                let deleteAction = UIContextualAction(style: .destructive, title: CommonString.Word.Delete) { [weak self] (action, view, handler) in
                    guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: listItemID, within: ObvStack.shared.viewContext) else { return }
                    self?.delegate?.userAskedToDeleteDiscussion(discussion, completionHandler: handler)
                }
                let markAllAsNotNewAction = UIContextualAction(style: .normal, title: DiscussionsTableViewController.Strings.markAllAsRead) { (action, view, handler) in
                    guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: listItemID, within: ObvStack.shared.viewContext) else { return }
                    ObvMessengerInternalNotification.userWantsToMarkAllMessagesAsNotNewWithinDiscussion(persistedDiscussionObjectID: discussion.objectID, completionHandler: handler)
                        .postOnDispatchQueue()
                }
                let configuration = UISwipeActionsConfiguration(actions: [markAllAsNotNewAction, deleteAction])
                configuration.performsFirstActionWithFullSwipe = false
                return configuration
            case .segmentControl:
                return UISwipeActionsConfiguration(actions: [])
            }
        }
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }
    
    
    private func addObservers() {
        observeIdentityColorStyleDidChangeNotifications()
        observeDiscussionLocalConfigurationHasBeenUpdatedNotifications()
        observeCallLogItemWasUpdatedNotifications()
    }
}


// MARK: - Observation
@available(iOS 16.0, *)
extension DiscussionsViewController {
    
    private func observeIdentityColorStyleDidChangeNotifications() {
        let token = ObvMessengerSettingsNotifications.observeIdentityColorStyleDidChange {
            OperationQueue.main.addOperation { [weak self] in
                self?.collectionView.reloadData()
            }
        }
        self.notificationTokens.append(token)
    }

    
    private func observeDiscussionLocalConfigurationHasBeenUpdatedNotifications() {
        let token = ObvMessengerInternalNotification.observeDiscussionLocalConfigurationHasBeenUpdated { value, objectId in
            OperationQueue.main.addOperation { [weak self] in
                guard case .muteNotificationsDuration = value else { return }
                self?.collectionView.reloadData()
            }
        }
        self.notificationTokens.append(token)
    }

    
    private func observeCallLogItemWasUpdatedNotifications() {
        let token = VoIPNotification.observeCallHasBeenUpdated { _, _ in
            OperationQueue.main.addOperation { [weak self] in
                self?.collectionView.reloadData()
            }
        }
        self.notificationTokens.append(token)
    }
}


// MARK: - Refresh Control related
@available(iOS 16.0, *)
extension DiscussionsViewController {
    
    @objc
    private func refresh() {
        let actionDate = Date()
        let completionHander = { [weak self] in
            let timeUntilStop: TimeInterval = max(0.0, 1.5 + actionDate.timeIntervalSinceNow) // The spinner should spin at least two second
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(Int(timeUntilStop*1000)), execute: { [weak self] in
                self?.collectionView?.refreshControl?.endRefreshing()
            })
        }
        delegate?.userAskedToRefreshDiscussions(completionHandler: completionHander)
    }
}


// MARK: - Helpers
@available(iOS 16.0, *)
extension DiscussionsViewController {
    private func setFetchResultsController(using fetchRequest: NSFetchRequest<PersistedDiscussion>) {
        fetchedResultsController = PersistedDiscussion.getFetchedResultsController(fetchRequest: fetchRequest, within: ObvStack.shared.viewContext)
        currentFetchRequest = fetchRequest
        fetchedResultsController.delegate = self
        
        do {
            try fetchedResultsController.performFetch()
        } catch let error {
            fatalError("Failed to fetch entities: \(error.localizedDescription)")
        }
    }
}


// MARK: - Cell manipulation
@available(iOS 16.0, *)
extension DiscussionsViewController {
    // 2022-11-15 This method does not work yet, see issue #1683
    private func highlightItem(at tvIndexPath: IndexPath) {
        guard let sectionId = dataSource.sectionIdentifier(for: tvIndexPath.section) else { return }
        switch sectionId {
        case .segmentControl:
            break
        case .discussions where UIDevice.current.userInterfaceIdiom == .pad:
            guard let cell = collectionView.cellForItem(at: tvIndexPath) else { return }
            let effectColor = AppTheme.shared.colorScheme.secondarySystemFill
            cell.contentView.applyRippleEffect(withColor: effectColor)
        case .discussions:
            break
        }
    }
}


// MARK: - UICollectionViewDelegate
@available(iOS 16.0, *)
extension DiscussionsViewController: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt tvIndexPath: IndexPath) {
        guard let selectedItem = dataSource.itemIdentifier(for: tvIndexPath) else { return }
        switch selectedItem {
        case .persistedDiscussion(let listItemID):
            guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: listItemID, within: ObvStack.shared.viewContext) else { return }
            if let splitViewController = splitViewController, !splitViewController.isCollapsed {
                highlightItem(at: tvIndexPath)
            }
            delegate?.userDidSelect(persistedDiscussion: discussion)
        case .segmentControl:
            return
        }
    }
    
    
    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt tvIndexPath: IndexPath) {
        guard let selectedItem = dataSource.itemIdentifier(for: tvIndexPath) else { return }
        switch selectedItem {
        case .persistedDiscussion(let listItemID):
            guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: listItemID, within: ObvStack.shared.viewContext) else { return }
            delegate?.userDidDeselect(discussion)
        case .segmentControl:
            return
        }
    }
}


// MARK: - NSFetchedResultsControllerDelegate
@available(iOS 16.0, *)
extension DiscussionsViewController: NSFetchedResultsControllerDelegate {
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {

        let databaseSnapshot = snapshot as NSDiffableDataSourceSnapshot<String, NSManagedObjectID>
        var newSnapshot = dataSource.snapshot()
        
        // By deleting all the items of the .discussion section and readding items from the database snapshot, we ensure the ordering of discussions matches the ordering of data returned by our fetchrequest.
        // Note that readding items does not reconfigure cells for items that already existed in the previous snapshot of the datasource. For this reason, we have to manually reconfigure the items that are marked as "reloaded" in the database snapshot.
        newSnapshot.deleteItems(inSection: .discussions)
        newSnapshot.appendItems(databaseSnapshot.itemIdentifiers.compactMap(convertToListItemID(using:)), toSection: .discussions)
        newSnapshot.reconfigureItems(databaseSnapshot.reloadedItemIdentifiers.compactMap(convertToListItemID(using:)))
        
        dataSource.apply(newSnapshot, animatingDifferences: !firstTimeFetch) // do not animate the first time we fetch data to have results already be present when switching to the discussion tab
        firstTimeFetch = false
    }
    
    private func convertToListItemID(using id: NSManagedObjectID) -> ListItemID? {
        return ListItemType.persistedDiscussion(TypeSafeManagedObjectID(objectID: id))
    }
}


// MARK: - ObvSegmentedControlTableViewCellDelegate
@available(iOS 16.0, *)
extension DiscussionsViewController: ObvSegmentedControlTableViewCellDelegate {
    func segmentedControlValueChanged(toIndex: Int) {
        guard let newFetchRequest = fetchRequests.allRequestsAndImages[safe: toIndex]?.request else { assertionFailure(); return }
        setFetchResultsController(using: newFetchRequest)
        
        var newSnapshot = dataSource.snapshot()
        newSnapshot.reloadSections([.discussions])
        dataSource.apply(newSnapshot)
    }
}


// MARK: - CanScrollToTop
@available(iOS 16.0, *)
extension DiscussionsViewController: CanScrollToTop {
    func scrollToTop() {
        guard collectionView.numberOfSections > 0 && collectionView.numberOfItems(inSection: 0) > 0 else { return }
        collectionView.scrollToItem(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
    }
}


// MARK: - DiscussionCell.Content extension

@available(iOS 16.0, *)
extension DiscussionCell.Content {
    
    init(discussion: PersistedDiscussion) {
        numberOfNewReceivedMessages = discussion.numberOfNewMessages
        circledInitialsConfig = discussion.circledInitialsConfiguration
        shouldMuteNotifications = discussion.shouldMuteNotifications
        title = discussion.title
        timestampOfLastMessage = discussion.timestampOfLastMessage.discussionCellFormat
        if let illustrativeMessage = discussion.illustrativeMessage {
            (subtitle, isSubtitleInItalics) = illustrativeMessage.subtitle
        } else {
            subtitle = NSLocalizedString("NO_MESSAGE", comment: "")
            isSubtitleInItalics = true
        }
    }

}
