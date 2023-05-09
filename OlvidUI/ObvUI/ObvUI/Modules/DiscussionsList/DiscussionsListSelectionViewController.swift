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
import ObvUICoreData
import UIKit


// A horizontally scrolling collectionViewController that shows selected discussions
@available(iOS 16.0, *)
public final class DiscussionsListSelectionViewController<T: DiscussionsListSelectionCellViewModelCreating>: UIViewController {
    private enum Sections: Int, CaseIterable {
        case placeholder
        case selectedDiscussions
    }
    
    public enum ListItemType: Hashable {
        case placeholder
        case selectedDiscussion(DiscussionsListSelectionCellViewModel)
    }
    
    private typealias SectionItem = Sections
    private typealias ListItemID = ListItemType
    private typealias DataSource = UICollectionViewDiffableDataSource<SectionItem, ListItemID>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<SectionItem, ListItemID>
    private typealias SectionSnapshot = NSDiffableDataSourceSectionSnapshot<ListItemID>
    
    private var dataSource: UICollectionViewDiffableDataSource<SectionItem, ListItemID>! = nil
    private weak var collectionView: UICollectionView! = nil
    @Published public var selectedDiscussions: [DiscussionsListSelectionCellViewModel]
    private var viewModel: DiscussionsListSelectionViewControllerViewModel<T>
    private var cancellables: [NSManagedObjectID: AnyCancellable] = [:]
    
    init(viewModel: DiscussionsListSelectionViewControllerViewModel<T>) {
        self.viewModel = viewModel
        self.selectedDiscussions = self.viewModel.cellViewModels
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Life Cycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureDataSource()
        setInitialData()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        collectionView.indexPathsForSelectedItems?.forEach({ [weak self] in
            self?.collectionView.deselectItem(at: $0, animated: false)
        })
    }
}


// MARK: - Internal functions
@available(iOS 16.0, *)
extension DiscussionsListSelectionViewController {
    
    var isEmpty: Bool {
        return selectedDiscussions.isEmpty
    }
    
    func add(itemId: TypeSafeManagedObjectID<T>) {
        guard let viewModel = T.createDiscussionsListSelectionCellViewModel(with: itemId.objectID) else { assertionFailure(); return; }
        selectedDiscussions.insert(viewModel, at: 0)
        var snapshot = dataSource.snapshot()
        
        if !snapshot.sectionIdentifiers.contains(where: { $0 == .selectedDiscussions }) {
            snapshot.appendSections([.selectedDiscussions])
        } else {
            snapshot.deleteItems(inSection: .selectedDiscussions)
        }
        
        let items = selectedDiscussions.map({ ListItemID.selectedDiscussion($0) })
        snapshot.appendItems(items, toSection: .selectedDiscussions)
        
        if snapshot.sectionIdentifiers.contains(where: { $0 == .placeholder }) {
            snapshot.deleteSections([.placeholder])
        }

        dataSource.apply(snapshot, animatingDifferences: true)
    }
    
    func remove(itemId: TypeSafeManagedObjectID<T>) {
        let objectId = itemId.objectID
        guard let selectedDiscussionToRemove = selectedDiscussions.first(where: { $0.objectId == objectId }) else { return }
        selectedDiscussions.removeAll(where: { $0 == selectedDiscussionToRemove })
        cancellables[objectId] = nil
        
        var snapshot = dataSource.snapshot()
        guard snapshot.sectionIdentifiers.contains(where: { $0 == .selectedDiscussions }) else { assertionFailure(); return; }
        
        snapshot.deleteItems([ListItemID.selectedDiscussion(selectedDiscussionToRemove)])
        
        if selectedDiscussions.isEmpty {
            addPlaceholderSectionAndCell(to: &snapshot)
        }
        
        dataSource.apply(snapshot, animatingDifferences: true)
    }
    
    func removeAll() {
        selectedDiscussions.removeAll()
        
        var snapshot = dataSource.snapshot()
        snapshot.deleteSections(SectionItem.allCases)
        addPlaceholderSectionAndCell(to: &snapshot)
        
        dataSource.apply(snapshot, animatingDifferences: true)
    }
}


// MARK: - Setup
@available(iOS 16.0, *)
extension DiscussionsListSelectionViewController {
    private func configureHierarchy() {
        let collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: UICollectionViewFlowLayout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = false
//        collectionView.delegate = self
        view.addSubview(collectionView)
        self.collectionView = collectionView
    }
    
    private func configureDataSource() {
        let placeholderCellRegistration = UICollectionView.CellRegistration<DiscussionsListSelectionPlaceholderCell, AnyObject> { cell, _, _ in
            cell.configure()
        }
        
        let selectedDiscussionCellRegistration = UICollectionView.CellRegistration<DiscussionsListSelectionCell, DiscussionsListSelectionCellViewModel> { [weak self] cell, _, item in
            cell.configure(viewModel: item)
            guard let self else { return }
            let objectId = item.objectId
            self.cancellables[objectId] = item.$removeTapped
                .filter({ $0 == true }) // only remove if true
                .sink(receiveValue: { [weak self] _ in
                    self?.remove(itemId: TypeSafeManagedObjectID<T>(objectID: objectId))
                })
        }

        dataSource = DataSource(collectionView: collectionView) { (collectionView: UICollectionView, indexPath: IndexPath, itemID: ListItemID) -> UICollectionViewCell? in
            
            switch itemID {
            case .placeholder:
                return collectionView.dequeueConfiguredReusableCell(using: placeholderCellRegistration, for: indexPath, item: nil)
            case .selectedDiscussion(let objectId):
                return collectionView.dequeueConfiguredReusableCell(using: selectedDiscussionCellRegistration, for: indexPath, item: objectId)
            }
        }
        collectionView.collectionViewLayout = createLayout(dataSource: dataSource)
    }
    
    private func setInitialData() {
        var snapshot = Snapshot()
        
        if !viewModel.cellViewModels.isEmpty {
            snapshot.appendSections([.selectedDiscussions])
            let items = viewModel.cellViewModels.map({ ListItemID.selectedDiscussion($0) })
            snapshot.appendItems(items, toSection: .selectedDiscussions)
        } else {
            snapshot.appendSections([.placeholder])
            snapshot.appendItems([ListItemID.placeholder], toSection: .placeholder)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    private func createLayout(dataSource: DataSource) -> UICollectionViewLayout {
        let sectionProvider = { [weak dataSource] (sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in
            
            guard let sectionKind = dataSource?.sectionIdentifier(for: sectionIndex) else { return nil }
            let section: NSCollectionLayoutSection
            switch sectionKind {
            case .placeholder:
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                item.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                section = NSCollectionLayoutSection(group: group)
                section.orthogonalScrollingBehavior = .none
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)

            case .selectedDiscussions: // orthogonal scrolling
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.55), heightDimension: .fractionalHeight(1.0))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = 4
                section.orthogonalScrollingBehavior = .groupPaging
                section.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10)
            }
            return section
        }
        return UICollectionViewCompositionalLayout(sectionProvider: sectionProvider)
    }
}

// MARK: - Extensions
@available(iOS 16.0, *)
private extension DiscussionsListSelectionViewController {
    private func addPlaceholderSectionAndCell(to snapshot: inout Snapshot) {
        snapshot.deleteSections([.selectedDiscussions])
        snapshot.appendSections([.placeholder])
        snapshot.appendItems([ListItemID.placeholder], toSection: .placeholder)
    }
}

// MARK: - UICollectionViewDelegate
//@available(iOS 16.0, *)
//extension SelectedDiscussionsViewController: UICollectionViewDelegate {
//
//    func collectionView(_ collectionView: UICollectionView, didSelectItemAt tvIndexPath: IndexPath) {
//    }
//
//    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt tvIndexPath: IndexPath) {
//    }
//}
