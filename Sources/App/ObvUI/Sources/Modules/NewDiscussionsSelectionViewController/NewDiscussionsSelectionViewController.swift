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
import CoreData
import ObvUICoreData


public protocol NewDiscussionsSelectionViewControllerDelegate: AnyObject {
    func userAcceptedlistOfSelectedDiscussions(_ listOfSelectedDiscussions: [TypeSafeManagedObjectID<PersistedDiscussion>], in newDiscussionsSelectionViewController: UIViewController)
}


/// This view controller is intended to be used anywhere we need to select one or more discussions (e.g., in the share extension or in the app, when forwarding a message).
/// Under iOS 15, we should use ``DiscussionsSelectionViewController`` instead.
@available(iOS 16.0, *)
public final class NewDiscussionsSelectionViewController: UIViewController, NSFetchedResultsControllerDelegate, UICollectionViewDelegate, HorizontalListOfSelectedDiscussionsViewControllerDelegate {

    private enum Section: Int, CaseIterable {
        case pinnedDiscussions
        case discussions
    }
    
    private enum Item: Hashable, Equatable {
        case persistedDiscussion(TypeSafeManagedObjectID<PersistedDiscussion>)
    }

    private typealias DataSource = UICollectionViewDiffableDataSource<Section, Item>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<Section, Item>
        
    private let viewModel: ViewModel
    private var dataSource: DataSource!
    private weak var collectionView: UICollectionView!
    private var firstTimeFetch = true
    private var horizontalListOfSelectedDiscussionsVC: HorizontalListOfSelectedDiscussionsViewController
    private weak var delegate: NewDiscussionsSelectionViewControllerDelegate?
    
    private let searchStore: DiscussionsSearchStore
    private var searchController: UISearchController!
 
    private let acceptSelectionButton = ObvImageButton()
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    

    public init(viewModel: ViewModel, delegate: NewDiscussionsSelectionViewControllerDelegate?) {
        assert(delegate != nil)
        self.viewModel = viewModel
        self.horizontalListOfSelectedDiscussionsVC = HorizontalListOfSelectedDiscussionsViewController()
        self.delegate = delegate
        self.searchStore = DiscussionsSearchStore(ownedCryptoId: viewModel.ownedCryptoId, restrictToActiveDiscussions: viewModel.restrictToActiveDiscussions, viewContext: viewModel.viewContext)
        self.selectedDiscussions = viewModel.preselectedDiscussions
        super.init(nibName: nil, bundle: nil)
        self.horizontalListOfSelectedDiscussionsVC.delegate = self
        self.searchStore.setDelegate(self) // setting the delegate means that we'll receive search request related snapshots in this vc
    }
    
    
    // MARK: - Life Cycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        
        configureHierarchy()
        configureDataSource()
        configureSearchBar()
        searchStore.performInitialFetch()

    }
    
    
    public override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent != nil && searchController == nil && viewModel.attachSearchControllerToParent {
            configureSearchBar()
        }
    }

    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        matchCellsOfHorizontalListOfSelectedDiscussionsVC(with: selectedDiscussions)
    }

    
    // MARK: - Managing the list of sorted selected discussions
    
    private var selectedDiscussions: [TypeSafeManagedObjectID<PersistedDiscussion>] {
        didSet {
            matchSelectedCellsOfCollectionView(with: Set(selectedDiscussions))
            matchCellsOfHorizontalListOfSelectedDiscussionsVC(with: selectedDiscussions)
        }
    }
    
    
    /// Each time ``selectedDiscussions`` is updated, this method is called. It makes sure the displayed list of selected cells in the collection view matches these ``selectedDiscussions``.
    private func matchSelectedCellsOfCollectionView(with selectedDiscussions: Set<TypeSafeManagedObjectID<PersistedDiscussion>>) {
        // Get the exact set of indexPaths that we want to be selected by the end of this method
        let visibleIndexPathsOfSelectedDiscussions = selectedDiscussions.compactMap { dataSource.indexPath(for: .persistedDiscussion($0)) }
        // Start by deselecting cells that are selected but not part of indexPathsOfCellsToSelect
        let indexPathsToDeselect = Set(collectionView.indexPathsForSelectedItems ?? []).subtracting(visibleIndexPathsOfSelectedDiscussions)
        indexPathsToDeselect.forEach { indexPath in
            collectionView.deselectItem(at: indexPath, animated: false)
        }
        // At this point, the set of currently selected indexPaths is a subset of indexPathsOfCellsToSelect. Select the rest.
        let indexPathsToSelect = Set(visibleIndexPathsOfSelectedDiscussions).subtracting(Set(collectionView.indexPathsForSelectedItems ?? []))
        indexPathsToSelect.forEach { indexPath in
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: .centeredVertically)
        }
    }
    
    
    private func matchCellsOfHorizontalListOfSelectedDiscussionsVC(with selectedDiscussions: [TypeSafeManagedObjectID<PersistedDiscussion>]) {
        let selectedItems = selectedDiscussions.compactMap { discussionObjectId in
            HorizontalListOfSelectedDiscussionsViewController.Cell.ViewModel.createFromPersistedDiscussion(with: discussionObjectId, within: viewModel.viewContext)
        }
        horizontalListOfSelectedDiscussionsVC.setSelectedDiscussion(to: selectedItems)
    }

    
    // MARK: - NSFetchedResultsControllerDelegate
    
    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        
        defer {
            firstTimeFetch = false
        }
        
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
            newSnapshot.appendItems(items.compactMap(itemFromPersistedDiscussion(with:)), toSection: section)
        }
        
        newSnapshot.reconfigureItems(databaseSnapshot.reloadedItemIdentifiers.compactMap(itemFromPersistedDiscussion(with:)))

        // Set the datasource and do not animate the first time we fetch data to have results already be present when switching to the discussion tab
        dataSource.apply(newSnapshot, animatingDifferences: !firstTimeFetch)
        
    }
    

    private func itemFromPersistedDiscussion(with objectID: NSManagedObjectID) -> Item {
        return Item.persistedDiscussion(TypeSafeManagedObjectID<PersistedDiscussion>(objectID: objectID))
    }
    
    
    // MARK: - UICollectionViewDelegate
    
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt tvIndexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: tvIndexPath) else { assertionFailure(); return }
        switch item {
        case .persistedDiscussion(let discussionObjectID):
            if !selectedDiscussions.contains(where: { $0 == discussionObjectID }) {
                selectedDiscussions.insert(discussionObjectID, at: 0)
            }
        }
    }
    
    
    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt tvIndexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: tvIndexPath) else { assertionFailure(); return }
        switch item {
        case .persistedDiscussion(let discussionObjectID):
            selectedDiscussions.removeAll(where: { $0 == discussionObjectID })
        }
    }
        
}


// MARK: - HorizontalListOfSelectedDiscussionsViewControllerDelegate

@available(iOS 16.0, *)
extension NewDiscussionsSelectionViewController {
    
    public func userWantsToDeselectItem(with discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        selectedDiscussions.removeAll(where: { $0 == discussionObjectID })
    }
    
}


// MARK: - Setup

@available(iOS 16.0, *)
extension NewDiscussionsSelectionViewController {
    
    /// Configures the view hierarchy to be used in this vc
    private func configureHierarchy() {
        
        let collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: createLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.allowsMultipleSelection = true
        collectionView.delegate = self
        view.addSubview(collectionView)
        
        self.collectionView = collectionView
        
        horizontalListOfSelectedDiscussionsVC.view.translatesAutoresizingMaskIntoConstraints = false
        horizontalListOfSelectedDiscussionsVC.view.backgroundColor = .red
        horizontalListOfSelectedDiscussionsVC.willMove(toParent: self)
        view.addSubview(horizontalListOfSelectedDiscussionsVC.view)
        addChild(horizontalListOfSelectedDiscussionsVC)
        horizontalListOfSelectedDiscussionsVC.didMove(toParent: self)
        
        self.view.addSubview(acceptSelectionButton)
        acceptSelectionButton.translatesAutoresizingMaskIntoConstraints = false
        acceptSelectionButton.addTarget(self, action: #selector(acceptSelectionButtonTapped), for: .touchUpInside)
        acceptSelectionButton.setTitle(viewModel.buttonTitle, for: .normal)
        if let systemIcon = viewModel.buttonSystemIcon {
            acceptSelectionButton.setImage(systemIcon, for: .normal)
        }
        
        NSLayoutConstraint.activate([
            horizontalListOfSelectedDiscussionsVC.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            horizontalListOfSelectedDiscussionsVC.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            horizontalListOfSelectedDiscussionsVC.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            horizontalListOfSelectedDiscussionsVC.view.heightAnchor.constraint(equalToConstant: 80),
            horizontalListOfSelectedDiscussionsVC.view.bottomAnchor.constraint(equalTo: collectionView.topAnchor),
            
            collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: acceptSelectionButton.topAnchor),
            
            acceptSelectionButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            acceptSelectionButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            acceptSelectionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
        
    }
    
    
    @objc private func acceptSelectionButtonTapped() {
        delegate?.userAcceptedlistOfSelectedDiscussions(selectedDiscussions, in: self)
    }
    
    
    /// Creates a layout to be used by the collection view
    /// - Returns: A layout to be used by the collectionview
    private func createLayout() -> UICollectionViewLayout {
        let configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }
    
    
    /// Configures the datasource of this vc
    private func configureDataSource() {
        
        let cellRegistration = UICollectionView.CellRegistration<Cell, TypeSafeManagedObjectID<PersistedDiscussion>> { [weak self] cell, indexPath, discussionId in
            guard let self else { return }
            guard let cellViewModel = Cell.ViewModel.createFromPersistedDiscussion(with: discussionId, within: self.viewModel.viewContext) else { assertionFailure(); return }
            cell.configure(viewModel: cellViewModel, selectionStyle: (UIDevice.current.userInterfaceIdiom == .pad && self.splitViewController != nil) ? .none : .default)
            cell.accessories = [.multiselect(displayed: .always)]
            if self.selectedDiscussions.contains(discussionId) {
                self.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: .centeredHorizontally)
            } else {
                self.collectionView.deselectItem(at: indexPath, animated: false)
            }
        }
        
        dataSource = DataSource(collectionView: collectionView) { (collectionView: UICollectionView, indexPath: IndexPath, item: Item) -> UICollectionViewCell? in
            switch item {
            case .persistedDiscussion(let discussionId):
                return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: discussionId)
            }
        }
        
    }
    
    
    private func configureSearchBar() {
        let searchController = UISearchController(searchResultsController: nil)
        // searchController.delegate = self
        searchController.searchResultsUpdater = searchStore
        definesPresentationContext = true
        let navigationItemForSearchController: UINavigationItem
        if viewModel.attachSearchControllerToParent {
            guard let parent else { return } // This method will be called again in didMove(toParent parent: UIViewController?)
            navigationItemForSearchController = parent.navigationItem
        } else {
            navigationItemForSearchController = navigationItem
        }
        navigationItemForSearchController.searchController = searchController
        navigationItemForSearchController.hidesSearchBarWhenScrolling = false
        self.searchController = searchController
    }
    
}
