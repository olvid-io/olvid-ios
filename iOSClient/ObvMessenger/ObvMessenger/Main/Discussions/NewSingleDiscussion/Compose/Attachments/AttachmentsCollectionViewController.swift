/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import QuickLook


@available(iOS 14.0, *)
final class AttachmentsCollectionViewController: UIViewController, NSFetchedResultsControllerDelegate {
    
    private let draftObjectID: TypeSafeManagedObjectID<PersistedDraft>
    private var frc: NSFetchedResultsController<PersistedDraftFyleJoin>!
    private var dataSource: UICollectionViewDiffableDataSource<Section, NSManagedObjectID>!
    private var collectionView: UICollectionView!
    private let attachmentTrashView: AttachmentTrashView
    static let cellSize = CGFloat(80)
    private var viewDidAppearWasCalled = false
    
    private var constraintWhenNotEmpty = [NSLayoutConstraint]()

    enum Section {
        case main
    }

    weak var delegate: ViewShowingHardLinksDelegate?
    weak var cacheDelegate: DiscussionCacheDelegate?
    
    init(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, delegate: ViewShowingHardLinksDelegate, cacheDelegate: DiscussionCacheDelegate?) {
        assert(cacheDelegate != nil)
        self.draftObjectID = draftObjectID
        self.cacheDelegate = cacheDelegate
        self.attachmentTrashView = AttachmentTrashView(draftObjectID: draftObjectID)
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        debugPrint("AttachmentsCollectionViewController deinit")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureDataSource()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppearWasCalled = true
    }

    @Published private(set) var numberOfAttachments = 0
    
    private func configureHierarchy() {

        self.view.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(attachmentTrashView)
        attachmentTrashView.translatesAutoresizingMaskIntoConstraints = false
        
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: createLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .none
        view.addSubview(collectionView)
        
        let heightConstraint = collectionView.heightAnchor.constraint(equalToConstant: AttachmentsCollectionViewController.cellSize)
        heightConstraint.priority = .defaultHigh
        constraintWhenNotEmpty = [
            
            attachmentTrashView.topAnchor.constraint(equalTo: self.view.topAnchor),
            attachmentTrashView.trailingAnchor.constraint(equalTo: collectionView.leadingAnchor),
            attachmentTrashView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            attachmentTrashView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),

            collectionView.topAnchor.constraint(equalTo: self.view.topAnchor),
            collectionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),

            heightConstraint,
        ]
    }

    
    private func createLayout() -> UICollectionViewLayout {
        let cellSize = AttachmentsCollectionViewController.cellSize
        let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(cellSize),
                                              heightDimension: .absolute(cellSize))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        
        let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(cellSize),
                                               heightDimension: .absolute(cellSize))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize,
                                                       subitems: [item])
        
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 1.0
        
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = .horizontal
        let layout = UICollectionViewCompositionalLayout(section: section, configuration: configuration)
        return layout
    }
    
    
    private func configureDataSource() {
        let collectionView = self.collectionView!

        self.frc = PersistedDraftFyleJoin.getFetchedResultsControllerForAllDraftFyleJoinsOfDraft(withObjectID: draftObjectID, within: ObvStack.shared.viewContext)
        self.frc.delegate = self

        let cellRegistration = UICollectionView.CellRegistration<AttachmentCell, DraftFyleJoin> { [weak self] (cell, indexPath, draftFyleJoin) in
            assert(self != nil)
            assert(self?.delegate != nil) // This typically happens if there is a memory cycle.
            cell.updateWith(draftFyleJoin: draftFyleJoin, indexPath: indexPath, delegate: self?.delegate, cacheDelegate: self?.cacheDelegate)
        }
        
        dataSource = UICollectionViewDiffableDataSource<Section, NSManagedObjectID>(collectionView: collectionView) { (collectionView: UICollectionView, indexPath: IndexPath, objectID: NSManagedObjectID) -> UICollectionViewCell? in
            guard let attachment = try? PersistedDraftFyleJoin.get(withObjectID: objectID, within: ObvStack.shared.viewContext) else { return nil }
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: attachment)
        }

        // Initial data
        try? self.frc.performFetch()
    }

}


// MARK: - NSFetchedResultsControllerDelegate

@available(iOS 14.0, *)
extension AttachmentsCollectionViewController {
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        
        let collectionView = self.collectionView!
        guard let dataSource = collectionView.dataSource as? UICollectionViewDiffableDataSource<Section, NSManagedObjectID> else { assertionFailure(); return }
        
        let newSnapshot = snapshot as NSDiffableDataSourceSnapshot<Section, NSManagedObjectID>

        NSLayoutConstraint.activate(constraintWhenNotEmpty)

        dataSource.apply(newSnapshot, animatingDifferences: true) { [weak self] in
            guard let _self = self else { return }
            if let fetchedObjects = controller.fetchedObjects, !fetchedObjects.isEmpty {
                NSLayoutConstraint.activate(_self.constraintWhenNotEmpty)
            } else {
                NSLayoutConstraint.deactivate(_self.constraintWhenNotEmpty)
            }
            self?.numberOfAttachments = controller.fetchedObjects?.count ?? 0
            UIView.animate(withDuration: 0.3) {
                self?.view.alpha = (self?.numberOfAttachments == 0) ? 0.0 : 1.0
            }
        }
        
    }
    
}


// MARK: - Returning all the views and hardlinks shown

@available(iOS 14.0, *)
extension AttachmentsCollectionViewController {

    /// Returns all the views (`AttachmentCell`) currently shown and the hardlink they display.
    func getAllShownHardLink() -> [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)] {
        var hardlinks = [(HardLinkToFyle, UIView)]()
        for cell in collectionView.visibleCells {
            guard let attachmentCell = cell as? AttachmentCell else { assertionFailure(); continue }
            hardlinks.append(contentsOf: attachmentCell.getAllShownHardLink())
        }
        return hardlinks
    }

    /// Request all the hardlinks to the `PersistedDraftFyleJoin` that a currently fetched
    func requestAllHardLinksToFetchedDraftFyleJoins(completionHandler: @escaping ([HardLinkToFyle?]) -> Void) {
        guard let draftFyleJoins = frc.fetchedObjects else { assertionFailure(); return }
        let fyleElements = draftFyleJoins.compactMap({ $0.fyleElement })
        guard fyleElements.count == draftFyleJoins.count else { assertionFailure(); return }
        ObvMessengerInternalNotification.requestAllHardLinksToFyles(fyleElements: fyleElements) { hardlinks in
            completionHandler(hardlinks)
        }.postOnDispatchQueue()
    }
    
}
