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

import Combine
import CoreData
import Foundation
import ObvTypes
import ObvUICoreData
import SwiftUI
import UIKit


/// This view controller is an iOS 16 replacement for the old `DiscussionsTableViewController`.
@available(iOS 16.0, *)
open class DiscussionsListViewController<T:DiscussionsListViewControllerTypeTConforming>: UIViewController, NSFetchedResultsControllerDelegate, UICollectionViewDelegate, Coordinating {
    public enum Sections: Int, CaseIterable {
        case segmentControl
        case discussions
    }
    
    public enum ListItemType: Hashable {
        case segmentControl
        case persistedDiscussion(TypeSafeManagedObjectID<T>)
    }

    public typealias SectionItem = Sections
    public typealias ListItemID = ListItemType
    public typealias DataSource = UICollectionViewDiffableDataSource<SectionItem, ListItemID>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<SectionItem, ListItemID>
    private typealias SectionSnapshot = NSDiffableDataSourceSectionSnapshot<ListItemID>
    
    public var coordinator: Coordinator?
    
    private var viewModel: DiscussionsListViewControllerViewModel<T>
    private var currentFetchRequest: NSFetchRequest<T>
    private var dataSource: UICollectionViewDiffableDataSource<SectionItem, ListItemID>! = nil
    private weak var collectionView: UICollectionView! = nil
    private var frcDiscussionsSection: NSFetchedResultsController<T>
    private var firstTimeFetch = true
    private var notificationTokens = [NSObjectProtocol]()
    public var selectionViewController: DiscussionsListSelectionViewController<T>
    private weak var selectionViewControllerHeightConstraint: NSLayoutConstraint? = nil
    private var sections: [Sections] = [.segmentControl, .discussions]
    private var cancellables: [AnyCancellable] = []
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public init(viewModel: DiscussionsListViewControllerViewModel<T>) {
        self.viewModel = viewModel
        self.coordinator = viewModel.coordinator
        let currentFetchRequest = viewModel.frcForNonEmptyRecentDiscussionsForOwnedIdentity
        selectionViewController = DiscussionsListSelectionViewController<T>(viewModel: DiscussionsListSelectionViewControllerViewModel(selectedObjectIds: viewModel.selectedObjectIds))
        self.currentFetchRequest = currentFetchRequest
        self.frcDiscussionsSection = NSFetchedResultsController(fetchRequest: currentFetchRequest,
                                                                managedObjectContext: viewModel.context,
                                                                sectionNameKeyPath: nil,
                                                                cacheName: nil)
        super.init(nibName: nil, bundle: nil)
        self.frcDiscussionsSection.delegate = self
    }
    
    
    // MARK: - Life Cycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        
        configureHierarchy()
        configureDataSource()
        setInitialData()
        addListeners()
        
        isEditing = viewModel.startInEditMode

        selectAllPreselectedCells()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if isEditing == false {
            deselectAllCells()
        }
    }
    
    public override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        collectionView.isEditing = editing

        if !editing {
            selectionViewControllerHeightConstraint?.constant = 0
            selectionViewController.removeAll()
        } else {
            selectionViewControllerHeightConstraint?.constant = 80
        }
        
        if animated {
            UIView.animate(withDuration: 0.3) { [weak self] in
                self?.view.layoutIfNeeded()
            }
        } else {
            view.layoutIfNeeded()
        }
    }
    
    
    // MARK: - Refresh Control related
    @objc
    private func refresh() {
        guard viewModel.withRefreshControl else { return }
        let actionDate = Date()
        let completionHander = { [weak self] (  ) in
            let timeUntilStop: TimeInterval = max(0.0, 1.5 + actionDate.timeIntervalSinceNow) // The spinner should spin at least two second
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(Int(timeUntilStop*1000)), execute: { [weak self] in
                self?.collectionView?.refreshControl?.endRefreshing()
            })
        }
        coordinator?.eventOccurred(with: .refreshRequested(completion: completionHander))
    }


    // MARK: - NSFetchedResultsControllerDelegate
    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        
        let databaseSnapshot = snapshot as NSDiffableDataSourceSnapshot<String, NSManagedObjectID>
        var newSnapshot = dataSource.snapshot()
        
        // By deleting all the items of the .discussion section and readding items from the database snapshot, we ensure the ordering of discussions matches the ordering of data returned by our fetchrequest.
        // Note that readding items does not reconfigure cells for items that already existed in the previous snapshot of the datasource. For this reason, we have to manually reconfigure the items that are marked as "reloaded" in the database snapshot.
        newSnapshot.deleteItems(inSection: .discussions)
        newSnapshot.appendItems(databaseSnapshot.itemIdentifiers.compactMap(convertToListItemID(using:)), toSection: .discussions)
        newSnapshot.reconfigureItems(databaseSnapshot.reloadedItemIdentifiers.compactMap(convertToListItemID(using:)))
        
        applySnapshotToDatasource(newSnapshot, animated: !firstTimeFetch) // do not animate the first time we fetch data to have results already be present when switching to the discussion tab
        firstTimeFetch = false
    }
    
    private func convertToListItemID(using id: NSManagedObjectID) -> ListItemID? {
        return ListItemType.persistedDiscussion(TypeSafeManagedObjectID<T>(objectID: id))
    }
    
    
    // MARK: - UICollectionViewDelegate
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt tvIndexPath: IndexPath) {
        guard let selectedItem = dataSource.itemIdentifier(for: tvIndexPath) else { return }
        switch (selectedItem) {
        case .persistedDiscussion(let listItemID) where collectionView.isEditing:
            selectionViewController.add(itemId: listItemID)
        case .persistedDiscussion(let listItemID):
            guard let discussion = try? T.get(objectID: listItemID.objectID, within: viewModel.context) else { return }
            coordinator?.eventOccurred(with: .cellSelected(type: discussion))
        case .segmentControl:
            return
        }
    }
    
    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt tvIndexPath: IndexPath) {
        guard let selectedItem = dataSource.itemIdentifier(for: tvIndexPath) else { return }
        switch (selectedItem) {
        case .persistedDiscussion(let listItemID) where collectionView.isEditing:
            selectionViewController.remove(itemId: listItemID)
            
        case .persistedDiscussion(let listItemID):
            guard let discussion = try? T.get(objectID: listItemID.objectID, within: viewModel.context) else { return }
            coordinator?.eventOccurred(with: .cellDeselected(type: discussion))
        case .segmentControl:
            return
        }
    }
    
    open func createLayout(dataSource: DataSource) -> UICollectionViewLayout {
        let configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }
}


// MARK: - Setup
@available(iOS 16.0, *)
extension DiscussionsListViewController {
    
    private func configureHierarchy() {
        let collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: UICollectionViewFlowLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.allowsMultipleSelectionDuringEditing = true
        collectionView.delegate = self
        if viewModel.withRefreshControl {
            collectionView.refreshControl = UIRefreshControl()
            collectionView.refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        }
        view.addSubview(collectionView)
        
        self.collectionView = collectionView
        
        selectionViewController.view.translatesAutoresizingMaskIntoConstraints = false
        selectionViewController.view.backgroundColor = .red
        selectionViewController.willMove(toParent: self)
        view.addSubview(selectionViewController.view)
        addChild(selectionViewController)
        selectionViewController.didMove(toParent: self)
        
        let selectionViewControllerHeightConstraint = selectionViewController.view.heightAnchor.constraint(equalToConstant: 0)
        
        NSLayoutConstraint.activate([
            selectionViewController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            selectionViewController.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            selectionViewController.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            selectionViewControllerHeightConstraint,
            selectionViewController.view.bottomAnchor.constraint(equalTo: collectionView.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        
        self.selectionViewControllerHeightConstraint = selectionViewControllerHeightConstraint
    }
    
    private func configureDataSource() {
        
        let segmentControlCellRegistration = UICollectionView.CellRegistration<DiscussionsListSegmentControlCell, AnyObject> { [weak self] cell, _, _ in
            guard let self else { return }
            let segmentImages = self.viewModel.allRequestsAndImages.map({ $0.image })
            let selectedSegmentIndex = self.viewModel.allRequestsAndImages.map({ $0.request }).firstIndex(of: self.currentFetchRequest) ?? 0
            let viewModel = DiscussionsListSegmentControlCellViewModel(segmentImages: segmentImages, selectedSegmentIndex: selectedSegmentIndex, delegate: self)
            cell.configure(with: viewModel)
        }
        
        let discussionListCellRegistration = UICollectionView.CellRegistration<DiscussionsListCell, TypeSafeManagedObjectID<T>> { [weak self] cell, _, id in
            guard let viewModel = T.createDiscussionsListCellViewModel(with: id.objectID) else { assertionFailure(); return; }
            cell.configure(viewModel: viewModel, selectionStyle: (UIDevice.current.userInterfaceIdiom == .pad && self?.splitViewController != nil) ? .none : .default)
        }
        
        let discussionListShortCellRegistration = UICollectionView.CellRegistration<DiscussionsListShortCell, TypeSafeManagedObjectID<T>> { [weak self] cell, _, id in
            guard let viewModel = T.createDiscussionsListShortCellViewModel(with: id.objectID) else { assertionFailure(); return; }
            cell.configure(viewModel: viewModel, selectionStyle: (UIDevice.current.userInterfaceIdiom == .pad && self?.splitViewController != nil) ? .none : .default)
        }
        
        dataSource = DataSource(collectionView: collectionView) { [weak self] (collectionView: UICollectionView, indexPath: IndexPath, itemID: ListItemID) -> UICollectionViewCell? in
            guard let self else { return nil }
            switch itemID {
            case .segmentControl:
                return collectionView.dequeueConfiguredReusableCell(using: segmentControlCellRegistration, for: indexPath, item: nil)
            case .persistedDiscussion(let listItemID):
                switch self.viewModel.discussionsListCellType {
                case .standard:
                    return collectionView.dequeueConfiguredReusableCell(using: discussionListCellRegistration, for: indexPath, item: listItemID)
                case .short:
                    return collectionView.dequeueConfiguredReusableCell(using: discussionListShortCellRegistration, for: indexPath, item: listItemID)
                }
            }
        }
        
        collectionView.collectionViewLayout = createLayout(dataSource: dataSource)
    }
    
    private func setInitialData() {
        var snapshot = Snapshot()
        snapshot.appendSections(sections)
        for section in sections {
            switch section {
            case .segmentControl:
                snapshot.appendItems([ListItemType.segmentControl], toSection: Sections.segmentControl)
            case .discussions:
                continue
            }
        }
        
        applySnapshotToDatasource(snapshot, animated: false)
        
        do {
            try frcDiscussionsSection.performFetch()
        } catch let error {
            fatalError("Failed to fetch entities: \(error.localizedDescription)")
        }
    }
    
    private func addListeners() {
        listenToRemovedSelectedDiscussionsAndDeselectThem()
    }
    
    private func listenToRemovedSelectedDiscussionsAndDeselectThem() {
        self.selectionViewController.$selectedDiscussions
            .withPrevious()
            .compactMap({ (val) -> [DiscussionsListSelectionCellViewModel]? in
                guard let previous = val.previous else { return nil }
                let current = val.current
                if previous.count > current.count { // if selected discussions have been removed
                    return previous.filter({ previous in !current.contains(where: { $0 == previous }) }) // retrieve them
                } else {
                    return nil
                }
            })
            .sink(receiveValue: {
                // and deselect them
                $0.forEach({ [weak self] elem in
                    guard let self else { return }
                    guard let indexPath = self.retrieveIndexPath(for: elem) else {
                        // The indexpath won't be found in cases where the user switched frcs
                        // and removed a selected discussion not visible in the current fetch result.
                        return
                    }
                    self.collectionView.deselectItem(at: indexPath, animated: false)
                })
            })
            .store(in: &cancellables)
    }
    
    private func selectAllPreselectedCells() {
        viewModel.selectedObjectIds.forEach({ item in
            if let indexPath = dataSource.indexPath(for: .persistedDiscussion(item)) {
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: .top)
            }
        })
    }
}


// MARK: - Switching current owned identity
@available(iOS 16.0, *)
extension DiscussionsListViewController {
    
    @MainActor
    public func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        self.viewModel.reloadFrcs(using: newOwnedCryptoId)
        
        setFetchResultsController(using: viewModel.frcForNonEmptyRecentDiscussionsForOwnedIdentity)
        setInitialData()
    }
}


// MARK: - Helpers
@available(iOS 16.0, *)
extension DiscussionsListViewController {
    private func setFetchResultsController(using fetchRequest: NSFetchRequest<T>) {
        frcDiscussionsSection = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                           managedObjectContext: viewModel.context,
                                                           sectionNameKeyPath: nil,
                                                           cacheName: nil)
        currentFetchRequest = fetchRequest
        frcDiscussionsSection.delegate = self
        
        do {
            try frcDiscussionsSection.performFetch()
        } catch let error {
            fatalError("Failed to fetch entities: \(error.localizedDescription)")
        }
    }
    
    @MainActor private func applySnapshotToDatasource(_ snapshot: Snapshot, animated: Bool = true, completion: (() -> Void)? = nil) {
        dataSource.apply(snapshot, animatingDifferences: animated, completion: completion)
    }
    
    @MainActor private func applySectionSnapshotToDatasource(_ sectionSnapshot: SectionSnapshot, to section: SectionItem, animated: Bool = true, completion: (() -> Void)? = nil) {
        dataSource.apply(sectionSnapshot, to: section, animatingDifferences: animated, completion: completion)
    }
    
    private func deselectAllCells() {
        collectionView.indexPathsForSelectedItems?.forEach({ [weak self] in
            self?.collectionView.deselectItem(at: $0, animated: false)
        })
    }
    
    private func retrieveIndexPath(for viewModel: DiscussionsListSelectionCellViewModel) -> IndexPath? {
        return dataSource.indexPath(for: .persistedDiscussion(TypeSafeManagedObjectID<T>(objectID: viewModel.objectId)))
    }
}


// MARK: - ObvSegmentedControlTableViewCellDelegate
@available(iOS 16.0, *)
extension DiscussionsListViewController: DiscussionsListSegmentControlCellDelegate {
    func segmentedControlValueChanged(toIndex: Int) {
        guard let newFetchRequest = viewModel.allRequestsAndImages[safe: toIndex]?.request else { assertionFailure(); return }
        
        let reselectAllSelectedDiscussionsStillVisibleAfterSwitchingFrc: (() -> Void)?
        if isEditing {
            deselectAllCells()
            
            reselectAllSelectedDiscussionsStillVisibleAfterSwitchingFrc = { [weak self] in
                self?.selectionViewController.selectedDiscussions
                    .compactMap({ [weak self] elem in return self?.retrieveIndexPath(for: elem) })
                    .forEach({ [weak self] elem in self?.collectionView.selectItem(at: elem, animated: false, scrollPosition: .top )})
            }
        } else {
            reselectAllSelectedDiscussionsStillVisibleAfterSwitchingFrc = nil
        }
        
        setFetchResultsController(using: newFetchRequest)
        
        var newSnapshot = dataSource.snapshot()
        newSnapshot.reloadSections([.discussions])
        applySnapshotToDatasource(newSnapshot, completion: reselectAllSelectedDiscussionsStillVisibleAfterSwitchingFrc)
    }
}
