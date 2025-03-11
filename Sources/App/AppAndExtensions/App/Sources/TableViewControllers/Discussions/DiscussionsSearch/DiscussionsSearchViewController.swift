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

import CoreData
import Foundation
import Combine
import ObvTypes
import ObvUICoreData
import UIKit
import ObvUI

@available(iOS 16.0, *)
final class DiscussionsSearchViewController: UIViewController, NSFetchedResultsControllerDelegate, UICollectionViewDelegate {
    
    private enum Section: Int, CaseIterable {
        case pinnedDiscussions
        case discussions
    }
    
    private enum Item: Hashable {
        case persistedDiscussion(TypeSafeManagedObjectID<PersistedDiscussion>)
    }

    private typealias DataSource = UICollectionViewDiffableDataSource<Section, Item>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<Section, Item>
    
    private var cancellables = Set<AnyCancellable>()

    let searchStore: DiscussionsSearchStore
    
    private var dataSource: DataSource!
    private weak var collectionView: UICollectionView!
    private weak var delegate: NewDiscussionsViewControllerDelegate?
    
    private var searchReturnedNoResults = false
    
    private var viewContext: NSManagedObjectContext {
        searchStore.viewContext
    }
    
    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    init(ownedCryptoId: ObvCryptoId, viewContext: NSManagedObjectContext, delegate: NewDiscussionsViewControllerDelegate?) {
        self.searchStore = DiscussionsSearchStore(ownedCryptoId: ownedCryptoId, restrictToActiveDiscussions: false, viewContext: viewContext)
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
        self.searchStore.setDelegate(self)
    }
    

    deinit {
        cancellables.forEach({ $0.cancel() })
    }

    
    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        configureDataSource()
        
        // Prevents a weird animation the first time this view controller is shown
        collectionView.contentInsetAdjustmentBehavior = .never
     
        continuouslyUpdateTheSelectedDiscussionCell()

    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { [weak self] in await self?.updateTheSelectedDiscussionCellOnViewWillAppear() }
    }
    
    
    func reloadCollectionViewData() {
        collectionView.reloadData()
    }
    
    
    public func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) {
        searchStore.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
    }
    
}


// MARK: - Setup
@available(iOS 16.0, *)
extension DiscussionsSearchViewController {
    
    /// Configures the view hierarchy to be used in this vc
    private func configureHierarchy() {
        let collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: createLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .onDrag
        view.addSubview(collectionView)
        
        self.collectionView = collectionView
        
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }
    
    /// Configures the datasource of this vc
    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<NewDiscussionsViewController.DiscussionCell, TypeSafeManagedObjectID<PersistedDiscussion>> { [weak self] cell, _, discussionId in
            guard let self else { return }
            guard let cellViewModel = NewDiscussionsViewController.DiscussionCell.ViewModel.createFromPersistedDiscussion(with: discussionId, within: viewContext) else { assertionFailure(); return }
            cell.configure(viewModel: cellViewModel)
        }

        dataSource = DataSource(collectionView: collectionView) { (collectionView: UICollectionView, indexPath: IndexPath, item: Item) -> UICollectionViewCell? in
            switch item {
            case .persistedDiscussion(let discussionId):
                return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: discussionId)

            }
        }
        
    }
    
    /// Creates a layout to be used by the collection view
    /// - Parameter dataSource: The datasource used in this vc in case it's needed
    /// - Returns: A layout to be used by the collectionview
    private func createLayout() -> UICollectionViewLayout {
        let sectionProvider = { [weak self] (sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in
            
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            
            configuration.trailingSwipeActionsConfigurationProvider = { [weak self] tvIndexPath in
                self?.trailingSwipeActionsConfigurationProvider(tvIndexPath)
            }

            configuration.leadingSwipeActionsConfigurationProvider = { [weak self] tvIndexPath in
                self?.leadingSwipeActionsConfigurationProvider(tvIndexPath)
            }

            let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
            
            return section
        }
            
        return UICollectionViewCompositionalLayout(sectionProvider: sectionProvider)
    }
    
    
    private func trailingSwipeActionsConfigurationProvider(_ indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let selectedItem = dataSource.itemIdentifier(for: indexPath) else { return UISwipeActionsConfiguration(actions: []) }
        switch (selectedItem) {
        case .persistedDiscussion(let listItemID):

            var actions = [UIContextualAction]()
            actions += [createDeleteAllMessagesAction(for: listItemID)]
            if let archiveOrUnarchiveAction = createArchiveOrUnarchiveAction(for: listItemID) {
                actions += [archiveOrUnarchiveAction]
            }

            let configuration = UISwipeActionsConfiguration(actions: actions)
            configuration.performsFirstActionWithFullSwipe = false
            return configuration
        }
    }
    
    
    private func leadingSwipeActionsConfigurationProvider(_ indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let sectionKind = dataSource.sectionIdentifier(for: indexPath.section) else { return nil }
        switch sectionKind {
        case .pinnedDiscussions: // list
            guard let selectedItem = dataSource.itemIdentifier(for: indexPath) else { return UISwipeActionsConfiguration(actions: []) }
            switch (selectedItem) {
            case .persistedDiscussion(let listItemID):
                let markAllMessagesAsNotNewAction = createMarkAllMessagesAsNotNewAction(for: listItemID)
                let configuration = UISwipeActionsConfiguration(actions: [markAllMessagesAsNotNewAction])
                configuration.performsFirstActionWithFullSwipe = false
                return configuration
            }
        case .discussions: // list
            guard let selectedItem = dataSource.itemIdentifier(for: indexPath) else { return UISwipeActionsConfiguration(actions: []) }
            switch (selectedItem) {
            case .persistedDiscussion(let listItemID):
                let markAllMessagesAsNotNewAction = createMarkAllMessagesAsNotNewAction(for: listItemID)
                let configuration = UISwipeActionsConfiguration(actions: [markAllMessagesAsNotNewAction])
                configuration.performsFirstActionWithFullSwipe = false
                return configuration
            }
        }
    }
    
    
    private func createMarkAllMessagesAsNotNewAction(for listItemID: (ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>)) -> UIContextualAction {
        let viewContext = self.viewContext
        let markAllAsNotNewAction = UIContextualAction(style: UIContextualAction.Style.normal, title: PersistedMessage.Strings.markAllAsRead) { (action, view, handler) in
            guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: listItemID.objectID, within: viewContext) else { return }
            ObvMessengerInternalNotification.userWantsToMarkAllMessagesAsNotNewWithinDiscussion(persistedDiscussionObjectID: discussion.objectID, completionHandler: handler)
                .postOnDispatchQueue()
        }
        return markAllAsNotNewAction
    }

    
    private func createDeleteAllMessagesAction(for listItemID: (ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>)) -> UIContextualAction {
        let viewContext = self.viewContext
        let deleteAction = UIContextualAction(style: .destructive, title: CommonString.Word.Delete) { [weak self] (action, view, handler) in
            guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: listItemID.objectID, within: viewContext) else { return }
            self?.delegate?.userAskedToDeleteDiscussion(discussion, completionHandler: handler)
        }
        deleteAction.image = UIImage(systemIcon: .trash)
        return deleteAction
    }
    
    
    private func createArchiveOrUnarchiveAction(for listItemID: (ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>)) -> UIContextualAction? {
        guard let discussion = try? PersistedDiscussion.get(objectID: listItemID.objectID, within: viewContext) else { return nil }
        if discussion.isArchived {
            return createUnarchiveDiscussionAction(for: listItemID)
        } else {
            return createArchiveDiscussionAction(for: listItemID)
        }
    }

    
    private func createArchiveDiscussionAction(for listItemID: (ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>)) -> UIContextualAction {
        let archiveDiscussionAction = UIContextualAction(style: .normal, title: CommonString.Word.Archive) { [weak self] (action, view, handler) in
            self?.archiveDiscussion(listItemID: listItemID, handler: handler)
        }
        archiveDiscussionAction.backgroundColor = UIColor.systemOrange
        archiveDiscussionAction.image = UIImage(systemIcon: .archivebox)
        return archiveDiscussionAction
    }

    
    private func createUnarchiveDiscussionAction(for listItemID: (ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>)) -> UIContextualAction {
        let unarchiveDiscussionAction = UIContextualAction(style: .normal, title: CommonString.Word.Unarchive) { [weak self] (action, view, handler) in
            self?.unarchiveDiscussion(listItemID: listItemID, handler: handler)
        }
        unarchiveDiscussionAction.backgroundColor = UIColor.systemGreen
        unarchiveDiscussionAction.image = UIImage(systemIcon: .archivebox)
        return unarchiveDiscussionAction
    }

    
    /// Retrieves the persisted discussion object ids from the given snapshot
    /// - Parameter snapshot: The target snapshot
    /// - Returns: An array of object ids
    private static func retrieveDiscussionObjectIds(from snapshot: Snapshot) -> [NSManagedObjectID] {
        guard snapshot.indexOfSection(.pinnedDiscussions) != nil else { return [] }
        return snapshot.itemIdentifiers(inSection: .pinnedDiscussions).map({
            switch $0 {
            case .persistedDiscussion(let listItemID): return listItemID.objectID
            }
        })
    }
    
    private func archiveDiscussion(listItemID: (ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>), handler: ((Bool) -> Void)?) {
        guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: listItemID.objectID, within: viewContext) else { return }
        handler?(true)
        ObvMessengerInternalNotification.userWantsToArchiveDiscussion(discussionPermanentID: discussion.discussionPermanentID, completionHandler: nil)
            .postOnDispatchQueue()
    }

    
    private func unarchiveDiscussion(listItemID: (ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>), handler: ((Bool) -> Void)?) {
        guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: listItemID.objectID, within: viewContext) else { return }
        handler?(true)
        ObvMessengerInternalNotification.userWantsToUnarchiveDiscussion(discussionPermanentID: discussion.discussionPermanentID, updateTimestampOfLastMessage: false, completionHandler: nil)
            .postOnDispatchQueue()
    }

}


// MARK: - UICollectionViewDelegate
@available(iOS 16.0, *)
extension DiscussionsSearchViewController {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt tvIndexPath: IndexPath) {
        guard let selectedItem = dataSource.itemIdentifier(for: tvIndexPath) else { return }
        guard case .persistedDiscussion(let listItemID) = selectedItem else { return }
        guard let discussion = try? PersistedDiscussion.get(objectID: listItemID.objectID, within: viewContext) else { return }
        delegate?.userDidSelect(persistedDiscussion: discussion)
    }
}


// MARK: - NSFetchedResultsControllerDelegate
@available(iOS 16.0, *)
extension DiscussionsSearchViewController {
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        let newSnapshot = Self.convert(snapshot)
        dataSource.apply(newSnapshot, animatingDifferences: true, completion: nil)
        
        if #available(iOS 17.0, *) {
            searchReturnedNoResults = controller.fetchedObjects?.isEmpty ?? true
            setNeedsUpdateContentUnavailableConfiguration()
        }
        
    }

    
    /// Converts the given snapshot reference to this definition's snapshot
    /// - Parameter snapshot: The snapshot reference to convert
    /// - Returns: The converted snapshot reference
    private static func convert(_ snapshot: NSDiffableDataSourceSnapshotReference) -> Snapshot {
        let databaseSnapshot = snapshot as NSDiffableDataSourceSnapshot<String, NSManagedObjectID>
        
        var newSnapshot = Snapshot()
        for rawSectionIdentifier in databaseSnapshot.sectionIdentifiers {
            guard let sectionIdentifier = PersistedDiscussion.PinnedSectionKeyPathValue(rawValue: rawSectionIdentifier) else {
                assertionFailure()
                continue
            }
            let section: Section
            switch sectionIdentifier {
            case .pinned:
                section = .pinnedDiscussions
            case .unpinned:
                section = .discussions
            }
            newSnapshot.appendSections([section])
            let items = databaseSnapshot.itemIdentifiers(inSection: rawSectionIdentifier)
            newSnapshot.appendItems(items.compactMap(convertToPersistedDiscussionListItemID(using:)), toSection: section)
        }
        
        newSnapshot.reconfigureItems(databaseSnapshot.reloadedItemIdentifiers.compactMap(convertToPersistedDiscussionListItemID(using:)))
        return newSnapshot
    }

    
    /// Converts the given managed object id to a list item id
    /// - Parameter id: The managed object id to convert
    /// - Returns: The list item id
    private static func convertToPersistedDiscussionListItemID(using id: NSManagedObjectID) -> Item {
        return Item.persistedDiscussion(TypeSafeManagedObjectID<PersistedDiscussion>(objectID: id))
    }
}


// MARK: - Updating the selected discussion

@available(iOS 16.0, *)
extension DiscussionsSearchViewController {

    private func continuouslyUpdateTheSelectedDiscussionCell() {
        OlvidUserActivitySingleton.shared.$currentUserActivity
            .removeDuplicates()
            .map { ($0?.ownedCryptoId, $0?.currentDiscussion?.toDiscussionIdentifier()) }
            .sink { (ownedCryptoId, discussionId) in
                Task { [weak self] in
                    self?.deselectAll(but: discussionId, ownedCryptoId: ownedCryptoId)
                }
            }
            .store(in: &cancellables)
        
    }
    
    
    @MainActor
    private func updateTheSelectedDiscussionCellOnViewWillAppear() async {
        guard let currentUserActivity = OlvidUserActivitySingleton.shared.currentUserActivity else { return }
        let ownedCryptoId = currentUserActivity.ownedCryptoId
        let discussionId = currentUserActivity.currentDiscussion?.toDiscussionIdentifier()
        deselectAll(but: discussionId, ownedCryptoId: ownedCryptoId)
    }
    
    
    @MainActor
    private func deselectAll(but discussionId: DiscussionIdentifier?, ownedCryptoId: ObvCryptoId?) {
        guard let ownedCryptoId else { return }
        guard self.searchStore.ownedCryptoId == ownedCryptoId else { return }
        if let discussionId {
            guard let dataSource else { return }
            guard let discussion = try? PersistedDiscussion.getPersistedDiscussion(ownedCryptoId: ownedCryptoId, discussionId: discussionId, within: ObvStack.shared.viewContext) else { return }
            guard let indexPathToSelect = dataSource.indexPath(for: .persistedDiscussion(discussion.typedObjectID)) else { return }
            // Under macOS, if the discussion is not visible, scroll to it
            if ObvMessengerConstants.targetEnvironmentIsMacCatalyst && !collectionView.indexPathsForVisibleItems.contains(where: { $0 == indexPathToSelect }) {
                collectionView.selectItem(at: indexPathToSelect, animated: true, scrollPosition: .centeredVertically)
            } else {
                collectionView.selectItem(at: indexPathToSelect, animated: true, scrollPosition: [])
            }
            guard let indexPathsForSelectedItems = collectionView.indexPathsForSelectedItems else { return }
            indexPathsForSelectedItems
                .filter { $0 != indexPathToSelect }
                .forEach { collectionView.deselectItem(at: $0, animated: false) }
        } else {
            guard let indexPathsForSelectedItems = collectionView.indexPathsForSelectedItems else { return }
            indexPathsForSelectedItems.forEach { collectionView.deselectItem(at: $0, animated: false) }
        }
    }
        
}



// MARK: - Managing the empty state

@available(iOS 17.0, *)
extension DiscussionsSearchViewController {
    
    override func updateContentUnavailableConfiguration(using state: UIContentUnavailableConfigurationState) {
        
        var config: UIContentUnavailableConfiguration?
        if searchReturnedNoResults {
            config = .search()
        }
        self.contentUnavailableConfiguration = config
        
    }
    
}
