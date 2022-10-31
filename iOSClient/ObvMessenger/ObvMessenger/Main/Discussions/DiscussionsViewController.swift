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
import CoreData
import ObvEngine
import ObvTypes

@available(iOS 15.0, *)
final class DiscussionsViewController: UIViewController {

    let ownedCryptoId: ObvCryptoId
    let confirmedSelectionOfPersistedDiscussions: (Set<TypeSafeManagedObjectID<PersistedDiscussion>>) -> Void

    init(ownedCryptoId: ObvCryptoId, confirmedSelectionOfPersistedDiscussions: @escaping (Set<TypeSafeManagedObjectID<PersistedDiscussion>>) -> Void) {
        self.ownedCryptoId = ownedCryptoId
        self.confirmedSelectionOfPersistedDiscussions = confirmedSelectionOfPersistedDiscussions
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureBarButtonItems() {
        let closeBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeButtonTapped))
        navigationItem.leftBarButtonItem = closeBarButtonItem
        let selectBarButtonItem = UIBarButtonItem(title: CommonString.Word.Choose, style: .plain, target: self, action: #selector(rightBarButtonItemButtonItemTapped))
        navigationItem.rightBarButtonItem = selectBarButtonItem
    }

    @objc func closeButtonTapped() {
        dismiss(animated: true)
    }

    @objc func rightBarButtonItemButtonItemTapped() {
        let indexPathsForSelectedItems = collectionView.indexPathsForSelectedItems ?? []
        let discussions = indexPathsForSelectedItems.map({ frc.object(at: $0) })
        let discussionObjectIDs = Set(discussions.map({ $0.typedObjectID }))
        confirmedSelectionOfPersistedDiscussions(discussionObjectIDs)
        dismiss(animated: true)
    }

    private enum Section {
        case main
    }

    private var dataSource: UICollectionViewDiffableDataSource<Section, NSManagedObjectID>! = nil
    private var collectionView: UICollectionView! = nil
    private var frc: NSFetchedResultsController<PersistedDiscussion>!

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureDataSource()
        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = false
        collectionView.allowsMultipleSelectionDuringEditing = true
        collectionView.isEditing = true
        configureBarButtonItems()
        self.title = CommonString.Word.Forward
    }

}

// MARK: Configuring the view hierarchy

@available(iOS 15.0, *)
extension DiscussionsViewController {

    private func configureHierarchy() {
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: createLayout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collectionView)
    }

    private func createLayout() -> UICollectionViewLayout {
        let configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }
}

// MARK: Configuring the view hierarchy

@available(iOS 15.0, *)
extension DiscussionsViewController {

    private func makeFrc() -> NSFetchedResultsController<PersistedDiscussion> {
        let fetchRequest = PersistedDiscussion.getFetchRequestForAllActiveRecentDiscussionsForOwnedIdentity(with: ownedCryptoId)
        return PersistedDiscussion.getFetchedResultsController(fetchRequest: fetchRequest, within: ObvStack.shared.viewContext)
    }

    
    private func configureDataSource() {

        self.frc = makeFrc()
        self.frc.delegate = self

        let cellRegistration = UICollectionView.CellRegistration<DiscussionViewCell, PersistedDiscussion> { [weak self] (cell, indexPath, discussion) in
            self?.updateDiscussionViewCell(cell, at: indexPath, with: discussion)
        }

        dataSource = UICollectionViewDiffableDataSource<Section, NSManagedObjectID>(collectionView: collectionView) { (collectionView: UICollectionView, indexPath: IndexPath, objectID: NSManagedObjectID) -> UICollectionViewCell? in
            guard let discussion = try? PersistedDiscussion.get(objectID: objectID, within: ObvStack.shared.viewContext) else { return nil }
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: discussion)
        }

        try? frc.performFetch()
    }


    @MainActor
    private func updateDiscussionViewCell(_ cell: DiscussionViewCell, at indexPath: IndexPath, with discussion: PersistedDiscussion) {
        cell.updateWith(discussion: discussion)
    }

}

// MARK: NSFetchedResultsControllerDelegate

@available(iOS 15.0, *)
extension DiscussionsViewController: NSFetchedResultsControllerDelegate {

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {

        let collectionView = self.collectionView!
        guard let dataSource = collectionView.dataSource as? UICollectionViewDiffableDataSource<Section, NSManagedObjectID> else { assertionFailure(); return }

        let newSnapshot = snapshot as NSDiffableDataSourceSnapshot<Section, NSManagedObjectID>

        dataSource.apply(newSnapshot, animatingDifferences: true)
    }
}

// MARK: - DiscussionViewCell

@available(iOS 15.0, *)
final class DiscussionViewCell: UICollectionViewListCell {

    private func defaultListContentConfiguration() -> UIListContentConfiguration { return .subtitleCell() }
    private lazy var listContentView = UIListContentView(configuration: defaultListContentConfiguration())
    private var viewsSetupWasPerformed = false

    private(set) var discussion: PersistedDiscussion?

    let circledInitials = NewCircledInitialsView()

    private let verticalPadding: CGFloat = 8.0

    func updateWith(discussion: PersistedDiscussion) {
        self.discussion = discussion
        setNeedsUpdateConfiguration()
    }

    private func setupViewsIfNeeded() {

        // Make sure we setup the views exactly once
        guard !viewsSetupWasPerformed else { return }
        defer { viewsSetupWasPerformed = true }

        contentView.addSubview(circledInitials)
        circledInitials.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(listContentView)
        listContentView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            listContentView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: verticalPadding),
            listContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            listContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -verticalPadding),
            listContentView.leadingAnchor.constraint(equalTo: circledInitials.trailingAnchor),

            circledInitials.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16.0),
            circledInitials.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            circledInitials.widthAnchor.constraint(equalToConstant: 40.0),
            circledInitials.heightAnchor.constraint(equalToConstant: 40.0),
        ])
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        setupViewsIfNeeded()

        var content = defaultListContentConfiguration().updated(for: state)
        guard let discussion = discussion else {
            return
        }

        content.text = discussion.title
        let textStyle = UIFont.TextStyle.callout
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle).withDesign(.rounded)?.withSymbolicTraits(.traitBold) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle)
        content.textProperties.font = UIFont(descriptor: fontDescriptor, size: 0)
        content.textProperties.color = AppTheme.shared.colorScheme.label

        listContentView.configuration = content

        if let circledInitialsConfiguration = discussion.circledInitialsConfiguration {
            circledInitials.configureWith(circledInitialsConfiguration)
        }

        accessories = [.multiselect()]
    }


}
