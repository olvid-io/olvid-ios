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

import Combine
import CoreData
import Foundation
import TipKit
import ObvTypes
import ObvUI
import ObvUICoreData
import OlvidUtils
import OSLog
import SwiftUI
import UIKit
import ObvDesignSystem
import ObvAppCoreConstants


protocol NewDiscussionsViewControllerDelegate: AnyObject {
    func userDidSelect(persistedDiscussion: PersistedDiscussion)
    func userAskedToDeleteDiscussion(_ persistedDiscussion: PersistedDiscussion, completionHandler: @escaping (Bool) -> Void)
    func userAskedToRefreshDiscussions() async throws
    func userWantsToStopSharingLocation() async throws
}


/// This view controller is an iOS 16 replacement for the old `DiscussionsTableViewController`.
@available(iOS 16.0, *)
final class NewDiscussionsViewController: UIViewController, NSFetchedResultsControllerDelegate, UICollectionViewDelegate, UISearchControllerDelegate {

    private enum Section: Int, CaseIterable {
        case progress
        case tips
        case location
        case pinnedDiscussions
        case discussions
    }
    
    private enum Item: Hashable {
        case progress(progress: AppCoordinatorsQueueMonitor.CoordinatorsOperationsProgress)
        case tip(tipToDisplay: DisplayableTip)
        case persistedDiscussion(TypeSafeManagedObjectID<PersistedDiscussion>)
        case location(TypeSafeManagedObjectID<PersistedLocationContinuousSent>)
    }

    private typealias DataSource = UICollectionViewDiffableDataSource<Section, Item>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<Section, Item>
        
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: NewDiscussionsViewController.self))
    
    private var cancellables = Set<AnyCancellable>()

    private var viewModel: ViewModel
    private var dataSource: DataSource!
    private weak var collectionView: UICollectionView!
    private var frc: NSFetchedResultsController<PersistedDiscussion>
    private var frcForLocationContinuousSent: NSFetchedResultsController<PersistedLocationContinuousSent>
    private var firstTimeFetch = true
    private var rightBarButtonItemsFromParentViewController: [UIBarButtonItem]?
    private weak var delegate: NewDiscussionsViewControllerDelegate?
    private var observationTokens = [NSObjectProtocol]()
    
    private var latestSnapshotForFrc: NSDiffableDataSourceSnapshot<String, NSManagedObjectID>?
    private var latestSnapshotForFrcForLocationContinuousSent: NSDiffableDataSourceSnapshot<String, NSManagedObjectID>?
    
    private var searchController: UISearchController?
    
    private var discussionsSearchViewController: DiscussionsSearchViewController? {
        return searchController?.searchResultsController as? DiscussionsSearchViewController
    }
    
    /// Internal variable used when pinning/unpinning discussions
    private let millisecondsToWaitAfterCallingHandler = 500
    
    /// Progress related variables
    
    @Published private var coordinatorsOperationsProgressToDisplay: AppCoordinatorsQueueMonitor.CoordinatorsOperationsProgress?
    
    /// Tip related variables

    /// Enumerates all the tips that can be displayed in a cell at the top of the list.
    private enum DisplayableTip: CaseIterable {
        case newSentMessageStatus
        case doSendReadReceiptTip
        case createBackupKeyTip
        case shouldPerformBackupTip
        case shouldVerifyBackupKeyTip
    }
    
    @Published private var tipToDisplay: DisplayableTip?

    private var observationTaskForTip = [DisplayableTip: Task<Void, Never>]()
    
    private var tipStructForTip: [DisplayableTip: Any] = {
        var result = [DisplayableTip: Any]()
        if #available(iOS 17, *) {
            for tip in DisplayableTip.allCases {
                switch tip {
                case .newSentMessageStatus:
                    result[tip] = OlvidTip.NewSentMessageStatus()
                case .doSendReadReceiptTip:
                    result[tip] = OlvidTip.DoSendReadReceipt()
                case .createBackupKeyTip:
                    result[tip] = OlvidTip.Backup.CreateBackupKey()
                case .shouldPerformBackupTip:
                    result[tip] = OlvidTip.Backup.ShouldPerformBackup()
                case .shouldVerifyBackupKeyTip:
                    result[tip] = OlvidTip.Backup.ShouldVerifyBackupKey()
                }
            }
        }
        return result
    }()
    
    
    /// Allows to differentiate between two different UX states this viewController may have during the `isEditing` state of its collectionView.
    /// When `isEditing` is set to true, based on the `isReordering` state, the user will be able to reorder pinned discussions.
    private var isReordering = false
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public init(viewModel: ViewModel, delegate: NewDiscussionsViewControllerDelegate) {
        self.viewModel = viewModel
        self.delegate = delegate
        frc = NSFetchedResultsController(fetchRequest: viewModel.fetchRequestControllerModel.fetchRequest,
                                         managedObjectContext: ObvStack.shared.viewContext,
                                         sectionNameKeyPath: viewModel.fetchRequestControllerModel.sectionNameKeyPath,
                                         cacheName: nil)
        frcForLocationContinuousSent = NSFetchedResultsController(fetchRequest: viewModel.fetchRequestControllerForLocationContinuousSentModel.fetchRequest,
                                                                  managedObjectContext: ObvStack.shared.viewContext,
                                                                  sectionNameKeyPath: viewModel.fetchRequestControllerForLocationContinuousSentModel.sectionNameKeyPath,
                                                                  cacheName: nil)
        super.init(nibName: nil, bundle: nil)
        frc.delegate = self
        frcForLocationContinuousSent.delegate = self
    }
    
    
    deinit {
        cancellables.forEach({ $0.cancel() })
    }
    
    // MARK: - Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureHierarchy()
        configureDataSource()
        setInitialData()
        configureGestureRecognizers()
        createSearchController()
        
        observeDiscussionLocalConfigurationHasBeenUpdatedNotifications()
        continuouslyUpdateTheSelectedDiscussionCell()
        continuouslyObserveProgressToDisplayOnViewDidLoad()
        
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if #available(iOS 17.0, *) {
            configureTipsOnViewDidAppear(animated: animated)
        }
    }
    
    
    /// Creates a search controller
    private func createSearchController() {
        
        guard self.searchController == nil else {
            assertionFailure("We should not be calling this method twice")
            return
        }
        
        let discussionsSearchVC = DiscussionsSearchViewController(ownedCryptoId: viewModel.ownedCryptoId, viewContext: ObvStack.shared.viewContext, delegate: delegate)
        let searchController = UISearchController(searchResultsController: discussionsSearchVC)
        searchController.delegate = self
        searchController.searchResultsUpdater = discussionsSearchVC.searchStore
        searchController.hidesNavigationBarDuringPresentation = true
        searchController.showsSearchResultsController = true // Set to true, as we want the search view controller to appear immediately since it might show archived discussions, not shown the list of recent discussions.
        definesPresentationContext = true

        self.searchController = searchController
        
    }

    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
                
        assert(parent != nil)
        assert(searchController != nil)
        
        parent?.navigationItem.searchController = searchController
        parent?.navigationItem.hidesSearchBarWhenScrolling = false

    }
    
    public override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        
        // When switching from the editing mode to the non-editing mode, we look for all selected items (sorted) and pin the discussions.
        let switchingFromEditingToNotEditing = collectionView.isEditing && !editing
        if switchingFromEditingToNotEditing {
            if let indexPathsForSelectedItems = collectionView.indexPathsForSelectedItems?.sorted() {
                var listItemIds = [TypeSafeManagedObjectID<PersistedDiscussion>]()
                for indexPath in indexPathsForSelectedItems {
                    guard let itemId = dataSource.itemIdentifier(for: indexPath) else { assertionFailure(); continue }
                    switch itemId {
                    case .progress:
                        break
                    case .tip:
                        break
                    case .location:
                        break
                    case .persistedDiscussion(let listItemID):
                        listItemIds += [listItemID]
                    }
                }

                setPinDiscussions(listItemIDs: listItemIds, handler: nil)
            }  else {
                setPinDiscussions(listItemIDs: [], handler: nil)
            }
        }
        
        collectionView.isEditing = editing
    }
    
}
    

// MARK: - Progress related stuff

@available(iOS 16.0, *)
extension NewDiscussionsViewController {
    
    private func continuouslyObserveProgressToDisplayOnViewDidLoad() {
        
        // We experienced a crash for a few users under iOS 17.6.1, so we restrict to iOS 18+
        
        if #available(iOS 18, *) {
            
            AppCoordinatorsQueueMonitor.shared.$coordinatorsOperationsProgress
                .receive(on: OperationQueue.main)
                .sink { [weak self] newValue in
                    guard let self else { return }
                    self.coordinatorsOperationsProgressToDisplay = newValue
                }
                .store(in: &cancellables)
            
            $coordinatorsOperationsProgressToDisplay
                .receive(on: OperationQueue.main)
                .sink { [weak self] newValue in
                    guard let self else { return }
                    guard let dataSource else { assertionFailure(); return }
                    var snapshot = dataSource.snapshot()
                    configureProgressToDisplayInSnapshot(&snapshot, withCoordinatorsOperationsProgress: newValue)
                    applySnapshotToDatasource(snapshot, animated: true)
                }
                .store(in: &cancellables)
            
        }
        
    }
    
    
    /// Configure the ``snapshot`` to include/exclude a progress from the collection view.
    ///
    /// This is called both from:
    /// - ``continuouslyObserveProgressToDisplayOnViewDidLoad()`` when the the `progressToDisplay` published local variable changes.
    /// - ``controller(_:didChangeContentWith:)``, when the data source changes (e.g., when a discussion is updated), so as to make sure the data source keeps the progress to display on screen if required.
    ///
    /// If ``progressToDisplay`` is `nil`, we remove the `progress` section
    /// from the data source. If there is progress to display, we make sure there is a `progress` section with exactly one progress item in it.
    @available(iOS 18, *)
    @MainActor
    private func configureProgressToDisplayInSnapshot(_ snapshot: inout NSDiffableDataSourceSnapshot<NewDiscussionsViewController.Section, NewDiscussionsViewController.Item>, withCoordinatorsOperationsProgress progress: AppCoordinatorsQueueMonitor.CoordinatorsOperationsProgress?) {
        
        if let progress {
            // Make sure the progress section exists. Do not show this progress section if there is no other section yet.
            if !snapshot.sectionIdentifiers.contains(where: { $0 == .progress }) {
                guard let topSection = snapshot.sectionIdentifiers.first else { return }
                snapshot.insertSections([.progress], beforeSection: topSection)
            }
            // Remove any previous progress in the progress section and append the requested progress to display
            snapshot.deleteItems(snapshot.itemIdentifiers(inSection: .progress))
            snapshot.appendItems([.progress(progress: progress)], toSection: .progress)
        } else {
            // Remove the progress section if it exists
            if snapshot.sectionIdentifiers.contains(where: { $0 == .progress }) {
                snapshot.deleteSections([.progress])
            }
        }
        
    }
    
}


// MARK: - Tip related stuff
    
@available(iOS 16.0, *)
extension NewDiscussionsViewController {

    @available(iOS 17.0, *)
    private func configureTipsOnViewDidAppear(animated: Bool) {

        continuouslyObserveTipToDisplay()

        for displayableTip in DisplayableTip.allCases {
            
            guard let tip = self.tipStructForTip[displayableTip] as? (any Tip) else { assertionFailure(); return }
            self.observationTaskForTip[displayableTip] = self.observationTaskForTip[displayableTip] ?? Task { @MainActor [weak self] in
                guard let self else { return }
                for await shouldDisplay in tip.shouldDisplayUpdates {
                    if shouldDisplay {
                        if self.tipToDisplay != displayableTip { self.tipToDisplay = displayableTip }
                    } else {
                        if self.tipToDisplay == displayableTip { self.tipToDisplay = nil }
                    }
                }
            }

        }

    }
    
    
    /// When the `tipToDisplay` published local variable is changed in the task deciding which tip to display, this
    /// method calls the ``configureTipInDataSource(tipToDisplay:)`` to update the data source accordingly.
    @available(iOS 17.0, *)
    private func continuouslyObserveTipToDisplay() {
        $tipToDisplay
            .removeDuplicates()
            .receive(on: OperationQueue.main)
            .sink { [weak self] newValue in
                guard let self else { return }
                guard let dataSource else { assertionFailure(); return }
                var snapshot = dataSource.snapshot()
                configureTipToDisplayInSnapshot(&snapshot, withTipToDisplay: tipToDisplay)
                applySnapshotToDatasource(snapshot, animated: true)
            }
            .store(in: &cancellables)
    }
    

    /// Configure the ``snapshot`` to include/exclude a tip from the collection view.
    ///
    /// This is called both from:
    /// - ``continuouslyObserveTipToDisplay()`` when the the `tipToDisplay` published local variable changes.
    /// - ``controller(_:didChangeContentWith:)``, when the data source changes (e.g., when a discussion is updated), so as to make sure the data source keeps the tip to display on screen if required.
    ///
    /// If ``tipToDisplay`` is `nil`, we remove the `tips` section
    /// from the data source. If there is tip to display, we make sure there is a `tips` section with exactly one appripriate tip in it.
    @available(iOS 17.0, *)
    @MainActor
    private func configureTipToDisplayInSnapshot(_ snapshot: inout NSDiffableDataSourceSnapshot<NewDiscussionsViewController.Section, NewDiscussionsViewController.Item>, withTipToDisplay tipToDisplay: DisplayableTip?) {
        
        if let tipToDisplay {
            // Make sure the tips section exists. Do not show this tips section if there is no discussion section yet.
            if !snapshot.sectionIdentifiers.contains(where: { $0 == .tips }) {
                guard let discussionsSection = snapshot.sectionIdentifiers.first(where: { $0 == .discussions }) else { return }
                snapshot.insertSections([.tips], beforeSection: discussionsSection)
            }
            // Remove any previous tip in the tips section and append the requested tip to display
            snapshot.deleteItems(snapshot.itemIdentifiers(inSection: .tips))
            snapshot.appendItems([.tip(tipToDisplay: tipToDisplay)], toSection: .tips)
        } else {
            // Remove the tips section if it exists
            if snapshot.sectionIdentifiers.contains(where: { $0 == .tips }) {
                snapshot.deleteSections([.tips])
            }
        }

    }
    
    
    /// Called when the tip cell registration needs to configure a `TipUICollectionViewCell`
    @available(iOS 17.0, *)
    private func configureTipUICollectionViewCell(_ tipCell: UICollectionViewCell, with tipToDisplay: DisplayableTip) {
        guard let tipCell = tipCell as? TipUICollectionViewCell else { assertionFailure(); return }
        guard let tip = self.tipStructForTip[tipToDisplay] as? (any Tip) else { assertionFailure(); return }
        tipCell.configureTip(tip)
        tipCell.imageSize = CGSize(width: 20, height: 20)
    }
    
    
    // MARK: - Reacting to changes made in the Core Data persistend store

    private func observeDiscussionLocalConfigurationHasBeenUpdatedNotifications() {
        self.observationTokens.append(ObvMessengerCoreDataNotification.observeDiscussionLocalConfigurationHasBeenUpdated { [weak self] value, objectId in
            guard case .muteNotificationsEndDate = value else { return }
            Task { try? await self?.reconfigureDiscussionItemAssociatedWithLocalConfiguration(withObjectID: objectId) }
        })
    }
    
    
    @MainActor
    private func reconfigureDiscussionItemAssociatedWithLocalConfiguration(withObjectID localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) async throws {
        guard let localConfig = try PersistedDiscussionLocalConfiguration.get(with: localConfigurationObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        guard let discussion = localConfig.discussion else { assertionFailure(); return }
        ObvStack.shared.viewContext.refresh(localConfig, mergeChanges: false)
        ObvStack.shared.viewContext.refresh(discussion, mergeChanges: false)
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([.persistedDiscussion(TypeSafeManagedObjectID(objectID: discussion.objectID))])
        applySnapshotToDatasource(snapshot)
    }
    
    
    // MARK: - Refresh Control related

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
            
            collectionView?.refreshControl?.endRefreshing()
            
        } catch {
            assertionFailure()
        }
        
    }


    // MARK: - NSFetchedResultsControllerDelegate
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        

        if controller == self.frc {
                        
            self.latestSnapshotForFrc = snapshot as NSDiffableDataSourceSnapshot<String, NSManagedObjectID>
            
        } else if controller == self.frcForLocationContinuousSent {

            self.latestSnapshotForFrcForLocationContinuousSent = snapshot as NSDiffableDataSourceSnapshot<String, NSManagedObjectID>

        }
        
        var newSnapshot = Snapshot()

        if let latestSnapshotForFrcForLocationContinuousSent {
            
            newSnapshot.appendSections([.location])
            let itemIdentifiers = latestSnapshotForFrcForLocationContinuousSent.itemIdentifiers
            let items = itemIdentifiers.map({ itemIdentifier in
                return Item.location(TypeSafeManagedObjectID<PersistedLocationContinuousSent>(objectID: itemIdentifier))
            })
            newSnapshot.appendItems(items, toSection: .location)
            
        }

        if let latestSnapshotForFrc {
            
            for rawSectionIdentifier in latestSnapshotForFrc.sectionIdentifiers {
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
                let items = latestSnapshotForFrc.itemIdentifiers(inSection: rawSectionIdentifier)
                newSnapshot.appendItems(items.compactMap(convertToPersistedDiscussionListItemID(using:)), toSection: section)
            }
            
            newSnapshot.reconfigureItems(latestSnapshotForFrc.reloadedItemIdentifiers.compactMap(convertToPersistedDiscussionListItemID(using:)))
            
        }
                
        if #available(iOS 18.0, *) {
            configureProgressToDisplayInSnapshot(&newSnapshot, withCoordinatorsOperationsProgress: AppCoordinatorsQueueMonitor.shared.coordinatorsOperationsProgress)
        }
        
        if #available(iOS 17.0, *) {
            configureTipToDisplayInSnapshot(&newSnapshot, withTipToDisplay: tipToDisplay)
        }
        
        applySnapshotToDatasource(newSnapshot, animated: !firstTimeFetch) // do not animate the first time we fetch data to have results already be present when switching to the discussion tab
        firstTimeFetch = false
        
        if #available(iOS 17.0, *) {
            setNeedsUpdateContentUnavailableConfiguration()
        }
            
    }
    

    /// Converts the given managed object id to a list item id
    /// - Parameter id: The managed object id to convert
    /// - Returns: The list item id
    private func convertToPersistedDiscussionListItemID(using id: NSManagedObjectID) -> Item {
        return Item.persistedDiscussion(TypeSafeManagedObjectID<PersistedDiscussion>(objectID: id))
    }
    
    
    // MARK: - UICollectionViewDelegate
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt tvIndexPath: IndexPath) {
        guard let selectedItem = dataSource.itemIdentifier(for: tvIndexPath) else { return }
        switch (selectedItem) {
        case .progress:
            break
        case .tip:
            break
        case .location:
            break
        case .persistedDiscussion(let discussionId):
            if !collectionView.isEditing {
                guard let discussion = try? PersistedDiscussion.get(objectID: discussionId.objectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
                delegate?.userDidSelect(persistedDiscussion: discussion)
            }
        }
    }
    

    func collectionView(_ collectionView: UICollectionView, targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath, toProposedIndexPath proposedIndexPath: IndexPath) -> IndexPath {
        if originalIndexPath.section == proposedIndexPath.section { // ensure that we can only reorder items within the same section
            return proposedIndexPath
        }
        return originalIndexPath
    }
    

    func collectionView(_ collectionView: UICollectionView, canEditItemAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    
    // MARK: - Managing the empty state
    
    @available(iOS 17.0, *)
    override func updateContentUnavailableConfiguration(using state: UIContentUnavailableConfigurationState) {
        
        var config: UIContentUnavailableConfiguration?
        if let fetchedObjects = frc.fetchedObjects, fetchedObjects.isEmpty, let fetchedLocations = frcForLocationContinuousSent.fetchedObjects, fetchedLocations.isEmpty {
            config = .empty()
            config?.text = NSLocalizedString("CONTENT_UNAVAILABLE_RECENT_DISCUSSIONS_TEXT", comment: "")
            if #available(iOS 18, *) {
                config?.secondaryText = NSLocalizedString("CONTENT_UNAVAILABLE_RECENT_DISCUSSIONS_SECONDARY_TEXT_WHEN_USING_FLOATING_BUTTON", comment: "")
            } else {
                config?.secondaryText = NSLocalizedString("CONTENT_UNAVAILABLE_RECENT_DISCUSSIONS_SECONDARY_TEXT", comment: "")
            }
            config?.image = UIImage(systemIcon: .bubbleLeftAndBubbleRight)
        }
        self.contentUnavailableConfiguration = config

    }
    
    // MARK: - Protected functions
    
    /// Creates a layout to be used by the collection view
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
            
            // Hide the separators around the "progress" section when it is shown
            configuration.itemSeparatorHandler = { [weak self] itemIndexPath, sectionSeparatorConfiguration in
                guard let self else { return sectionSeparatorConfiguration }
                guard let sectionIdentifier = dataSource.sectionIdentifier(for: itemIndexPath.section) else { return sectionSeparatorConfiguration }
                var configuration = sectionSeparatorConfiguration
                if sectionIdentifier == .progress || sectionIdentifier == .location {
                    configuration.topSeparatorVisibility = .hidden
                    configuration.bottomSeparatorVisibility = .hidden
                }
                return configuration
            }

            let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
            
            return section
            
        }
            
        return UICollectionViewCompositionalLayout(sectionProvider: sectionProvider)
        
    }
    
    
    private func trailingSwipeActionsConfigurationProvider(_ indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let selectedItem = dataSource.itemIdentifier(for: indexPath) else { return UISwipeActionsConfiguration(actions: []) }
        switch (selectedItem) {
        case .tip, .progress, .location:
            return nil
        case .persistedDiscussion(let listItemID):
            let deleteAllMessagesAction = self.createDeleteAllMessagesContextualAction(for: listItemID)
            let archiveDiscussionAction = self.createArchiveDiscussionContextualAction(for: listItemID)
            let configuration = UISwipeActionsConfiguration(actions: [deleteAllMessagesAction, archiveDiscussionAction])
            configuration.performsFirstActionWithFullSwipe = false
            return configuration
        }
    }
    
    
    private func leadingSwipeActionsConfigurationProvider(_ indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let sectionKind = dataSource.sectionIdentifier(for: indexPath.section) else { return nil }
        switch sectionKind {
        case .progress:
            return nil
        case .tips:
            return nil
        case .location:
            return nil
        case .pinnedDiscussions: // list
            guard let selectedItem = dataSource.itemIdentifier(for: indexPath) else { return UISwipeActionsConfiguration(actions: []) }
            switch (selectedItem) {
            case .tip, .progress, .location:
                return nil
            case .persistedDiscussion(let listItemID):
                let unpinAction = self.createUnpinContextualAction(for: listItemID)
                let markAllMessagesAsNotNewAction = self.createMarkAllMessagesAsNotNewContextualAction(for: listItemID)
                let configuration = UISwipeActionsConfiguration(actions: [unpinAction, markAllMessagesAsNotNewAction])
                configuration.performsFirstActionWithFullSwipe = false
                return configuration
            }
        case .discussions: // list
            guard let selectedItem = dataSource.itemIdentifier(for: indexPath) else { return UISwipeActionsConfiguration(actions: []) }
            switch (selectedItem) {
            case .tip, .progress, .location:
                return nil
            case .persistedDiscussion(let listItemID):
                let pinAction = self.createPinContextualAction(for: listItemID)
                let markAllMessagesAsNotNewAction = self.createMarkAllMessagesAsNotNewContextualAction(for: listItemID)
                let configuration = UISwipeActionsConfiguration(actions: [pinAction, markAllMessagesAsNotNewAction])
                configuration.performsFirstActionWithFullSwipe = false
                return configuration
            }
        }
    }
    
    
    private func createMarkAllMessagesAsNotNewContextualAction(for listItemID: (ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>)) -> UIContextualAction {
        let markAllAsNotNewAction = UIContextualAction(style: UIContextualAction.Style.normal, title: PersistedMessage.Strings.markAllAsRead) { (action, view, handler) in
            guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: listItemID.objectID, within: ObvStack.shared.viewContext) else { return }
            ObvMessengerInternalNotification.userWantsToMarkAllMessagesAsNotNewWithinDiscussion(persistedDiscussionObjectID: discussion.objectID, completionHandler: handler)
                .postOnDispatchQueue()
        }
        return markAllAsNotNewAction
    }
    
    
    private func createMarkAllMessagesAsNotNewAction(for listItemID: (ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>)) -> UIAction {
        let title = NSLocalizedString("MENU_ACTION_TITLE_MARK_ALL_MESSAGES_AS_READ", comment: "")
        return UIAction(title: title) { _ in
            guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: listItemID.objectID, within: ObvStack.shared.viewContext) else { return }
            ObvMessengerInternalNotification.userWantsToMarkAllMessagesAsNotNewWithinDiscussion(persistedDiscussionObjectID: discussion.objectID, completionHandler: { _ in })
                .postOnDispatchQueue()
        }
    }

    
    private func createDeleteAllMessagesContextualAction(for listItemID: (ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>)) -> UIContextualAction {
        let deleteAction = UIContextualAction(style: .destructive, title: CommonString.Word.Delete) { [weak self] (action, view, handler) in
            guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: listItemID.objectID, within: ObvStack.shared.viewContext) else { return }
            self?.delegate?.userAskedToDeleteDiscussion(discussion, completionHandler: handler)
        }
        deleteAction.image = UIImage(systemIcon: .trash)
        return deleteAction
    }
    
    
    private func createDeleteAllMessagesAction(for listItemID: (ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>)) -> UIAction {
        let title = NSLocalizedString("MENU_ACTION_TITLE_DELETE_ALL_MESSAGES", comment: "")
        return UIAction(title: title, attributes: .destructive) { [weak self] _ in
            guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: listItemID.objectID, within: ObvStack.shared.viewContext) else { return }
            self?.delegate?.userAskedToDeleteDiscussion(discussion, completionHandler: { _ in })
        }
    }

    
    private func createPinContextualAction(for listItemID: (TypeSafeManagedObjectID<PersistedDiscussion>)) -> UIContextualAction {
        let pinAction = UIContextualAction(style: .normal, title: CommonString.Word.Pin) { [weak self] (action, view, handler) in
            self?.pinDiscussion(listItemID: listItemID, handler: handler)
        }
        pinAction.backgroundColor = AppTheme.shared.colorScheme.green
        pinAction.image = UIImage(systemIcon: .pin)
        return pinAction
    }

    
    private func createPinAction(for listItemID: (TypeSafeManagedObjectID<PersistedDiscussion>)) -> UIAction {
        let title = NSLocalizedString("MENU_ACTION_TITLE_PIN_DISCUSSION", comment: "")
        return UIAction(title: title) { [weak self] _ in
            self?.pinDiscussion(listItemID: listItemID, handler: { _ in })
        }
    }

    
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {

        // Only provide a menu on a Mac
        
        guard ObvMessengerConstants.targetEnvironmentIsMacCatalyst else {
            return nil
        }
        
        // For now, we only show a menu for one item at a time

        guard let indexPath = indexPaths.first, indexPaths.count == 1 else {
            debugPrint(indexPaths)
            return nil
        }
        guard let sectionKind = dataSource.sectionIdentifier(for: indexPath.section) else { return nil }
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return nil }

        // Create the actions

        var actions = [UIAction]()
        switch item {
        case .tip, .progress, .location:
            return nil
        case .persistedDiscussion(let listItemID):
            actions += [createMarkAllMessagesAsNotNewAction(for: listItemID)]
            switch sectionKind {
            case .tips, .progress, .location:
                break
            case .pinnedDiscussions:
                actions += [createUnpinAction(for: listItemID)]
            case .discussions:
                actions += [createPinAction(for: listItemID)]
            }
            actions += [createArchiveDiscussionAction(for: listItemID)]
            actions += [createDeleteAllMessagesAction(for: listItemID)]
        }
        
        return UIContextMenuConfiguration(actionProvider: { _ in
            return UIMenu(children: actions)
        })
        
    }
    
    
    private func pinDiscussion(listItemID: (TypeSafeManagedObjectID<PersistedDiscussion>), handler: ((Bool) -> Void)?) {
        
        guard let dataSource else { return }
        
        let snapshot = dataSource.snapshot()
        var discussionObjectIds: [NSManagedObjectID] = []
        
        if snapshot.sectionIdentifiers.contains(where: { $0 == .pinnedDiscussions }) {
            discussionObjectIds = Self.retrieveDiscussionObjectIds(from: snapshot)
        }
        
        discussionObjectIds.append(listItemID.objectID)
        guard !discussionObjectIds.isEmpty else { handler?(false); return; }
        
        handler?(true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(millisecondsToWaitAfterCallingHandler)) {
            ObvMessengerInternalNotification.userWantsToReorderDiscussions(discussionObjectIds: discussionObjectIds, ownedIdentity: self.viewModel.ownedCryptoId, completionHandler: nil)
                .postOnDispatchQueue()
        }

    }


    private func createUnpinContextualAction(for listItemID: (TypeSafeManagedObjectID<PersistedDiscussion>)) -> UIContextualAction {
        let unpinAction = UIContextualAction(style: .normal, title: CommonString.Word.Unpin) { [weak self] (action, view, handler) in
            self?.unpinDiscussion(listItemID: listItemID, handler: handler)
        }
        unpinAction.backgroundColor = AppTheme.shared.colorScheme.orange
        unpinAction.image = UIImage(systemIcon: .unpin)
        return unpinAction
    }
    
    
    private func createUnpinAction(for listItemID: (TypeSafeManagedObjectID<PersistedDiscussion>)) -> UIAction {
        let title = NSLocalizedString("MENU_ACTION_TITLE_UNPIN_DISCUSSION", comment: "")
        return UIAction(title: title) { [weak self] _ in
            self?.unpinDiscussion(listItemID: listItemID, handler: nil)
        }
    }
    

    private func createArchiveDiscussionContextualAction(for listItemID: (ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>)) -> UIContextualAction {
        let archiveDiscussionAction = UIContextualAction(style: .destructive, title: CommonString.Word.Archive) { [weak self] (action, view, handler) in
            self?.archiveDiscussion(listItemID: listItemID, handler: handler)
        }
        archiveDiscussionAction.backgroundColor = UIColor.systemOrange
        archiveDiscussionAction.image = UIImage(systemIcon: .archivebox)
        return archiveDiscussionAction
    }
    
    
    private func createArchiveDiscussionAction(for listItemID: (ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>)) -> UIAction {
        let title = NSLocalizedString("MENU_ACTION_TITLE_ARCHIVE_DISCUSSION", comment: "")
        return UIAction(title: title) { [weak self] _ in
            self?.archiveDiscussion(listItemID: listItemID, handler: nil)
        }
    }
    
    
    private func unpinDiscussion(listItemID: (ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>), handler: ((Bool) -> Void)?) {
        var discussionObjectIds = Self.retrieveDiscussionObjectIds(from: dataSource.snapshot())
        discussionObjectIds.removeAll(where: { $0 == listItemID.objectID })
        
        handler?(true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(millisecondsToWaitAfterCallingHandler)) {
            ObvMessengerInternalNotification.userWantsToReorderDiscussions(discussionObjectIds: discussionObjectIds, ownedIdentity: self.viewModel.ownedCryptoId, completionHandler: nil)
                .postOnDispatchQueue()
        }
    }

    
    private func archiveDiscussion(listItemID: (ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>), handler: ((Bool) -> Void)?) {
        guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: listItemID.objectID, within: ObvStack.shared.viewContext) else { return }
        // We do not call the handler as this causes an animation glitch
        ObvMessengerInternalNotification.userWantsToArchiveDiscussion(discussionPermanentID: discussion.discussionPermanentID, completionHandler: nil)
            .postOnDispatchQueue()
    }

    
    /// Retrieves the persisted discussion object ids from the given snapshot
    /// - Parameter snapshot: The target snapshot
    /// - Returns: An array of object ids
    private static func retrieveDiscussionObjectIds(from snapshot: Snapshot) -> [NSManagedObjectID] {
        guard snapshot.indexOfSection(.pinnedDiscussions) != nil else { return [] }
        return snapshot.itemIdentifiers(inSection: .pinnedDiscussions).compactMap({
            switch $0 {
            case .progress: return nil
            case .tip: return nil
            case .location: return nil
            case .persistedDiscussion(let listItemID): return listItemID.objectID
            }
        })
    }


    private func reorderingCompleted() {
        let snapshot = dataSource.snapshot()
        guard snapshot.sectionIdentifiers.contains(where: { $0 == .pinnedDiscussions }) else { return }
        let discussionObjectIds: [NSManagedObjectID] = snapshot.itemIdentifiers(inSection: .pinnedDiscussions).compactMap {
            switch $0 {
            case .tip, .progress, .location:
                return nil
            case .persistedDiscussion(let listItemID):
                return listItemID.objectID
            }
        }
        guard !discussionObjectIds.isEmpty else { return }

        ObvMessengerInternalNotification.userWantsToReorderDiscussions(discussionObjectIds: discussionObjectIds, ownedIdentity: viewModel.ownedCryptoId, completionHandler: nil).postOnDispatchQueue()
    }

    
    /// Defines the complete list of pinned discussions. Any discussion not in the list will be unpinned.
    private func setPinDiscussions(listItemIDs: [TypeSafeManagedObjectID<PersistedDiscussion>], handler: ((Bool) -> Void)?) {
        let discussionObjectIds = listItemIDs.map { $0.objectID }
        ObvMessengerInternalNotification.userWantsToReorderDiscussions(discussionObjectIds: discussionObjectIds, ownedIdentity: self.viewModel.ownedCryptoId, completionHandler: nil).postOnDispatchQueue()
    }

    
    // MARK: - Gesture recognizer callbacks
    
    
    /// Callback for the longpress gesture recognizer
    /// - Parameter sender: The gesture recognizer
    @objc func userLongPressedOnDiscussion(_ sender: UILongPressGestureRecognizer) {
        guard let selectedIndex = collectionView.indexPathForItem(at: sender.location(in: collectionView)) else {
            collectionView.cancelInteractiveMovement()
            return
        }

        switch sender.state {
        case .began:
            guard dataSource.sectionIdentifier(for: selectedIndex.section) == .pinnedDiscussions else { return }
            collectionView.beginInteractiveMovementForItem(at: selectedIndex)
            
        case .changed:
            collectionView.updateInteractiveMovementTargetPosition(sender.location(in: sender.view!))
            
        case .ended:
            collectionView.endInteractiveMovement()
            
        default:
            collectionView.cancelInteractiveMovement()
        }
    }
}


// MARK: - Setup
@available(iOS 16.0, *)
extension NewDiscussionsViewController {
    
    /// Configures the view hierarchy to be used in this vc
    private func configureHierarchy() {
        let collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: createLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.allowsMultipleSelectionDuringEditing = true
        collectionView.delegate = self
        collectionView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: ObvMessengerConstants.contentInsetBottomWithFloatingButton, right: 0.0)

        collectionView.refreshControl = UIRefreshControl()
        collectionView.refreshControl?.addTarget(self, action: #selector(refreshControlWasPulledDown), for: .valueChanged)

        view.addSubview(collectionView)
        
        self.collectionView = collectionView
                
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    /// Configures any gesture recognizers used in this vc
    private func configureGestureRecognizers() {
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(userLongPressedOnDiscussion(_:)))
        collectionView.addGestureRecognizer(longPressGesture)
    }
    
    /// Configures the datasource of this vc
    private func configureDataSource() {
        
        if #available(iOS 17, *) {
            collectionView.register(TipUICollectionViewCell.self, forCellWithReuseIdentifier: "TipUICollectionViewCell")
        }
        
        let cellRegistration = UICollectionView.CellRegistration<DiscussionCell, TypeSafeManagedObjectID<PersistedDiscussion>> { [weak self] cell, _, discussionId in
            guard let self else { return }
            guard let cellViewModel = DiscussionCell.ViewModel.createFromPersistedDiscussion(with: discussionId, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
            cell.configure(viewModel: cellViewModel)
            cell.accessories = self.accessoriesForListCellItem(cellViewModel)
        }
        
        let progressCellRegistration = UICollectionView.CellRegistration<ProgressCell, AppCoordinatorsQueueMonitor.CoordinatorsOperationsProgress> { cell, _, progress in
            cell.configure(progress: progress)
        }
        
        let locationCellRegistration = UICollectionView.CellRegistration<LocationCell, TypeSafeManagedObjectID<PersistedLocationContinuousSent>> { cell, _, locationId in
            guard let location = try? PersistedLocationContinuousSent.getPersistedLocationContinuousSent(objectID: locationId, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
            cell.configure(numberOfSentMessagesWithLocationContinuousSentFromCurrentOwnedDevice: location.sentMessages.count, delegate: self)
        }
                
        dataSource = DataSource(collectionView: collectionView) { [weak self] (collectionView: UICollectionView, indexPath: IndexPath, item: Item) -> UICollectionViewCell? in

            switch item {
                
            case .progress(progress: let progress):
                return collectionView.dequeueConfiguredReusableCell(using: progressCellRegistration, for: indexPath, item: progress)

            case .tip(tipToDisplay: let tipToDisplay):
                let tipCell = collectionView.dequeueReusableCell(withReuseIdentifier: "TipUICollectionViewCell", for: indexPath)
                if #available(iOS 17.0, *) {
                    self?.configureTipUICollectionViewCell(tipCell, with: tipToDisplay)
                }
                return tipCell
                
            case .location(let locationId):
                return collectionView.dequeueConfiguredReusableCell(using: locationCellRegistration, for: indexPath, item: locationId)
                
            case .persistedDiscussion(let discussionId):
                return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: discussionId)

            }
        }
        
        dataSource.reorderingHandlers.canReorderItem = { _ -> Bool in return true }
        dataSource.reorderingHandlers.didReorder = { [weak self] _ in
            self?.reorderingCompleted()
        }
        
    }
    
    /// Sets the initial data to be displayed by this vc
    private func setInitialData() {
        do {
            try frc.performFetch()
            try frcForLocationContinuousSent.performFetch()
        } catch let error {
            fatalError("Failed to fetch entities: \(error.localizedDescription)")
        }
    }
    
}


// MARK: - NewDiscussionsViewControllerLocationCellDelegate

@available(iOS 16.0, *)
extension NewDiscussionsViewController: NewDiscussionsViewControllerLocationCellDelegate {
    
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice() {
        Task {
            try? await delegate?.userWantsToStopSharingLocation()
        }
    }
    
}


// MARK: - Switching current owned identity
@available(iOS 16.0, *)
extension NewDiscussionsViewController {
    
    @MainActor
    /// Switches between user profiles
    /// - Parameter newOwnedCryptoId: The crypto id of the profile to switch to
    public func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        self.viewModel = ViewModel(ownedCryptoId: newOwnedCryptoId)
        setFetchResultsController(using: viewModel.fetchRequestControllerModel)
        setInitialData()
        
        guard let searchVc = self.discussionsSearchViewController else { assertionFailure(); return }
        searchVc.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
    }
}


// MARK: - Updating the selected discussion

@available(iOS 16.0, *)
extension NewDiscussionsViewController {

    private func continuouslyUpdateTheSelectedDiscussionCell() {
        OlvidUserActivitySingleton.shared.$currentUserActivity
            .removeDuplicates()
            .map { ($0?.ownedCryptoId, $0?.currentDiscussion?.toDiscussionIdentifier()) }
            .sink { (ownedCryptoId, discussionId) in
                Task { [weak self] in
                    await self?.deselectAll(but: discussionId, ownedCryptoId: ownedCryptoId)
                }
            }
            .store(in: &cancellables)
        
    }
    
    @MainActor
    private func deselectAll(but discussionId: DiscussionIdentifier?, ownedCryptoId: ObvCryptoId?) async {
        guard let ownedCryptoId else { return }
        guard self.viewModel.ownedCryptoId == ownedCryptoId else { return }
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

// MARK: - Helpers
@available(iOS 16.0, *)
extension NewDiscussionsViewController {
    
    /// Sets the fetch results controller to the given model
    /// - Parameter frcModel: The fetch results controller model to apply
    private func setFetchResultsController(using frcModel: FetchRequestControllerModel<PersistedDiscussion>) {
        frc = NSFetchedResultsController(fetchRequest: frcModel.fetchRequest,
                                         managedObjectContext: ObvStack.shared.viewContext,
                                         sectionNameKeyPath: frcModel.sectionNameKeyPath,
                                         cacheName: nil)
        frc.delegate = self
        
        do {
            try frc.performFetch()
        } catch let error {
            fatalError("Failed to fetch entities: \(error.localizedDescription)")
        }
    }
    
    
    /// Applies the given snapshot to the datasource in a thread safe manner
    /// - Parameters:
    ///   - snapshot: The snapshot to apply
    ///   - animated: Animated or not
    ///   - completion: An optional completion closure to execute
    @MainActor
    private func applySnapshotToDatasource(_ snapshot: Snapshot, animated: Bool = true, completion: (() -> Void)? = nil) {
        
        // If we are in reordering mode, we make sure all pinned discussions are selected
        let newCompletion = { [weak self] in
            guard let self else { return }
            completion?()
            if self.isReordering {
                self.selectAllItemsInPinnedDiscussionsSection()
            }
        }
        
        dataSource.apply(snapshot, animatingDifferences: animated, completion: newCompletion)
        
    }
    
    
    /// Select all items of the collection view that are found in the `.pinnedDiscussions` section.
    /// This is typically used when applying a new snapshot while in reordering mode.
    private func selectAllItemsInPinnedDiscussionsSection() {
        let snapshot = dataSource.snapshot()
        guard let sectionIndex = snapshot.indexOfSection(.pinnedDiscussions) else { return }
        guard self.collectionView.numberOfSections > sectionIndex else { return }
        for item in 0..<self.collectionView.numberOfItems(inSection: sectionIndex) {
            let indexPath = IndexPath(item: item, section: sectionIndex)
            self.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: .bottom)
        }
    }

    
    /// Switches the the reordering state on/off
    public func toggleIsReordering() {
        
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.impactOccurred()
        
        self.isReordering = !isReordering

        setEditing(isReordering, animated: true)
        
        var newSnapshot = dataSource.snapshot()
        newSnapshot.reconfigureItems(newSnapshot.itemIdentifiers)
        applySnapshotToDatasource(newSnapshot)

        // When switching to reordering mode, we remove the existing bar buttons items (we keep them for later) and we show a 'Done' button.
        // This button allows to go back to the normal state and to restore the previous bar buttons items.
        
        if self.isReordering {
            self.rightBarButtonItemsFromParentViewController = parent?.navigationItem.rightBarButtonItems
            let doneButtonAction = UIAction { [weak self] _ in self?.toggleIsReordering() }
            let doneButton = UIBarButtonItem(systemItem: .done, primaryAction: doneButtonAction)
            parent?.navigationItem.rightBarButtonItems = [doneButton]
        } else {
            parent?.navigationItem.rightBarButtonItems = self.rightBarButtonItemsFromParentViewController
            self.rightBarButtonItemsFromParentViewController = nil
        }
        
    }
    
    
    private func accessoriesForListCellItem(_ cellViewModel: DiscussionCell.ViewModel) -> [UICellAccessory] {
        let accessories: [UICellAccessory]
        if collectionView.isEditing {
            if self.isReordering == true {
                if cellViewModel.isPinned {
                    accessories = [.multiselect(displayed: .whenEditing), .reorder(displayed: .whenEditing)]
                } else {
                    accessories = [.multiselect(displayed: .whenEditing)]
                }
            } else {
                accessories = [.multiselect(displayed: .whenEditing)]
            }
        } else {
            accessories = []
        }
        return accessories
    }

    
}

// MARK: - CanScrollToTop
@available(iOS 16.0, *)
extension NewDiscussionsViewController {
    public func scrollToTop() {
        guard collectionView.numberOfSections > 0 else { return }
        guard collectionView.numberOfItems(inSection: 0) > 0 else { return }
        collectionView.scrollToItem(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
    }
}


// MARK: - UISearchControllerDelegate

@available(iOS 16.0, *)
extension NewDiscussionsViewController {
    
    func willPresentSearchController(_ searchController: UISearchController) {

        // This prevents a bug where the collection shows "behind" the navigation bar (or the tab bar) while presenting the search view controller.
        // When dismissing the search view controller, we unhide the collection view.
        UIView.animate(withDuration: 0.3) { [weak self] in
            self?.collectionView.alpha = 0
            self?.discussionsSearchViewController?.view.alpha = 1
        }

        // This operation will update the normalizedSearchKey of all discussions for the given crypto id.
        // The normalizedSearchKey is the attribute on PersistedDiscussion on which searches are made.
        ObvMessengerInternalNotification.updateNormalizedSearchKeyOnPersistedDiscussions(ownedIdentity: viewModel.ownedCryptoId, completionHandler: nil)
            .postOnDispatchQueue()
        
        discussionsSearchViewController?.reloadCollectionViewData()

    }
    
    
    func willDismissSearchController(_ searchController: UISearchController) {
        UIView.animate(withDuration: 0.3) { [weak self] in
            self?.collectionView.alpha = 1
            self?.discussionsSearchViewController?.view.alpha = 0
        }
    }
}
