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


public protocol HorizontalListOfSelectedDiscussionsViewControllerDelegate: AnyObject {
    func userWantsToDeselectItem(with discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
}


// A horizontally scrolling collectionViewController that shows selected discussions
@available(iOS 16.0, *)
final class HorizontalListOfSelectedDiscussionsViewController: UIViewController {
    
    private enum Section: Int, CaseIterable {
        case placeholder
        case selectedDiscussions
    }
    
    enum Item: Hashable {
        case placeholder
        case selectedDiscussion(Cell.ViewModel)
    }
    
    private typealias DataSource = UICollectionViewDiffableDataSource<Section, Item>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<Section, Item>

    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>! = nil
    private weak var collectionView: UICollectionView! = nil
    weak var delegate: HorizontalListOfSelectedDiscussionsViewControllerDelegate?

    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureDataSource()
        setInitialData()
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        collectionView.indexPathsForSelectedItems?.forEach({ [weak self] in
            self?.collectionView.deselectItem(at: $0, animated: false)
        })
    }
    
}


// MARK: - Internal functions
@available(iOS 16.0, *)
extension HorizontalListOfSelectedDiscussionsViewController {
    
    func setSelectedDiscussion(to selectedDiscussion: [Cell.ViewModel]) {
        var snapshot = Snapshot()
        snapshot.appendSections([.placeholder])
        if selectedDiscussion.isEmpty {
            snapshot.appendItems([.placeholder], toSection: .placeholder)
        } else {
            snapshot.appendSections([.selectedDiscussions])
            let items = selectedDiscussion.map { Item.selectedDiscussion($0) }
            snapshot.appendItems(items, toSection: .selectedDiscussions)
        }
        dataSource.apply(snapshot, animatingDifferences: true)
    }
    
}


// MARK: - Setup
@available(iOS 16.0, *)
extension HorizontalListOfSelectedDiscussionsViewController {
    
    private func configureHierarchy() {
        let collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: createLayout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = false
        view.addSubview(collectionView)
        self.collectionView = collectionView
    }
    
    private func configureDataSource() {
        
        let placeholderCellRegistration = UICollectionView.CellRegistration<PlaceholderCell, AnyObject> { cell, _, _ in
            cell.configure()
        }
        
        let selectedDiscussionCellRegistration = UICollectionView.CellRegistration<Cell, Cell.ViewModel> { [weak self] cell, _, cellViewModel in
            cell.configure(viewModel: cellViewModel, delegate: self?.delegate)
        }

        dataSource = DataSource(collectionView: collectionView) { (collectionView: UICollectionView, indexPath: IndexPath, item: Item) -> UICollectionViewCell? in
            switch item {
            case .placeholder:
                return collectionView.dequeueConfiguredReusableCell(using: placeholderCellRegistration, for: indexPath, item: nil)
            case .selectedDiscussion(let objectId):
                return collectionView.dequeueConfiguredReusableCell(using: selectedDiscussionCellRegistration, for: indexPath, item: objectId)
            }
        }
                
    }
    
    
    private func setInitialData() {
        var snapshot = Snapshot()
        snapshot.appendSections([.placeholder])
        snapshot.appendItems([.placeholder], toSection: .placeholder)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    
    private func createLayout() -> UICollectionViewLayout {
        let sectionProvider = { (sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in
            
            guard let sectionKind = HorizontalListOfSelectedDiscussionsViewController.Section(rawValue: sectionIndex) else { return nil }
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
