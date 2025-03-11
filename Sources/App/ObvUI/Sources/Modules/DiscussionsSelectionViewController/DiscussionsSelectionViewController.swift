/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvTypes
import ObvUICoreData
import ObvDesignSystem


public protocol DiscussionsSelectionViewControllerDelegate: AnyObject {
    func userAcceptedlistOfSelectedDiscussions(_ listOfSelectedDiscussions: Set<ObvManagedObjectPermanentID<PersistedDiscussion>>, in discussionsSelectionViewController: UIViewController)
}

/// VC responsible for selection discussions -- e.g. when forwarding a message.
/// Under iOS 16, we should use ``NewDiscussionsSelectionViewController`` instead.
@available(iOS 15.0, *)
public final class DiscussionsSelectionViewController: UIViewController, UICollectionViewDelegate {

    let ownedCryptoId: ObvCryptoId
    let viewContext: NSManagedObjectContext
    private let acceptSelectionButton = ObvImageButton()
    private weak var delegate: DiscussionsSelectionViewControllerDelegate?
    private var selectedDiscussions = Set<ObvManagedObjectPermanentID<PersistedDiscussion>>() 

    public init(ownedCryptoId: ObvCryptoId, within viewContext: NSManagedObjectContext, preselectedDiscussions: Set<ObvManagedObjectPermanentID<PersistedDiscussion>>, delegate: DiscussionsSelectionViewControllerDelegate?, acceptButtonTitle: String) {
        assert(delegate != nil)
        self.ownedCryptoId = ownedCryptoId
        self.viewContext = viewContext
        self.selectedDiscussions = preselectedDiscussions
        self.delegate = delegate
        self.acceptSelectionButton.setTitle(acceptButtonTitle, for: .normal)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private enum Section {
        case main
    }

    private var dataSource: UICollectionViewDiffableDataSource<Section, NSManagedObjectID>! = nil
    private var collectionView: UICollectionView! = nil
    private var frc: NSFetchedResultsController<PersistedDiscussion>!

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureHierarchy()
        configureDataSource()
        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = false
        collectionView.allowsMultipleSelectionDuringEditing = true
        collectionView.isEditing = true
        // configureBarButtonItems()
        selectAllPreselectedDiscussions()
        self.title = CommonString.Word.Forward
    }

    
    private func selectAllPreselectedDiscussions() {
        guard !selectedDiscussions.isEmpty else { return }
        let indexPathsOfPreselectedDiscussions: [IndexPath] = selectedDiscussions.compactMap { preselectedDiscussion in
            guard let discussion = try? PersistedDiscussion.getManagedObject(withPermanentID: preselectedDiscussion, within: viewContext) else { assertionFailure(); return nil }
            guard let indexPath = dataSource.indexPath(for: discussion.objectID) else { assertionFailure(); return nil }
            return indexPath
        }
        indexPathsOfPreselectedDiscussions.forEach { indexPath in
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: .centeredVertically)
        }
    }
    
    
    @objc private func acceptSelectionButtonTapped() {
        delegate?.userAcceptedlistOfSelectedDiscussions(selectedDiscussions, in: self)
    }
    
}


// MARK: - UICollectionViewDelegate

@available(iOS 15.0, *)
extension DiscussionsSelectionViewController {
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        consolidateListOfSelectedDiscussions(collectionView)
    }
    
    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        consolidateListOfSelectedDiscussions(collectionView)
    }
    
    private func consolidateListOfSelectedDiscussions(_ collectionView: UICollectionView) {
        let indexPathsOfPreselectedDiscussions: [IndexPath] = collectionView.indexPathsForSelectedItems ?? []
        let newSelectedDiscussions = indexPathsOfPreselectedDiscussions
            .compactMap { indexPath in
                self.frc.safeObject(at: indexPath)
            }
            .compactMap { persistedDiscussion in
                persistedDiscussion.discussionPermanentID
            }
        self.selectedDiscussions = Set(newSelectedDiscussions)
    }
    
}

// MARK: Configuring the view hierarchy

@available(iOS 15.0, *)
extension DiscussionsSelectionViewController {

    private func configureHierarchy() {

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: createLayout())

        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        
        self.view.addSubview(acceptSelectionButton)
        acceptSelectionButton.translatesAutoresizingMaskIntoConstraints = false
        acceptSelectionButton.addTarget(self, action: #selector(acceptSelectionButtonTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: acceptSelectionButton.topAnchor),

            acceptSelectionButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            acceptSelectionButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            acceptSelectionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])

    }

    private func createLayout() -> UICollectionViewLayout {
        let configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }
}

// MARK: Configuring the view hierarchy

@available(iOS 15.0, *)
extension DiscussionsSelectionViewController {

    private func makeFrc() -> NSFetchedResultsController<PersistedDiscussion> {
        let fetchRequestControllerModel = PersistedDiscussion.getFetchRequestForAllActiveRecentDiscussionsForOwnedIdentity(with: ownedCryptoId)
        return PersistedDiscussion.getFetchedResultsController(model: fetchRequestControllerModel, within: viewContext)
    }

    
    private func configureDataSource() {

        self.frc = makeFrc()
        self.frc.delegate = self

        let cellRegistration = UICollectionView.CellRegistration<DiscussionSelectionViewCell, PersistedDiscussion> { [weak self] (cell, indexPath, discussion) in
            self?.updateDiscussionViewCell(cell, at: indexPath, with: discussion)
        }

        let viewContext = self.viewContext
        
        dataSource = UICollectionViewDiffableDataSource<Section, NSManagedObjectID>(collectionView: collectionView) { (collectionView: UICollectionView, indexPath: IndexPath, objectID: NSManagedObjectID) -> UICollectionViewCell? in
            guard let discussion = try? PersistedDiscussion.get(objectID: objectID, within: viewContext) else { return nil }
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: discussion)
        }

        try? frc.performFetch()
    }


    @MainActor
    private func updateDiscussionViewCell(_ cell: DiscussionSelectionViewCell, at indexPath: IndexPath, with discussion: PersistedDiscussion) {
        cell.updateWith(discussion: discussion)
    }

}

// MARK: NSFetchedResultsControllerDelegate

@available(iOS 15.0, *)
extension DiscussionsSelectionViewController: NSFetchedResultsControllerDelegate {

    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {

        let collectionView = self.collectionView!
        guard let dataSource = collectionView.dataSource as? UICollectionViewDiffableDataSource<Section, NSManagedObjectID> else { assertionFailure(); return }

        let newSnapshot = snapshot as NSDiffableDataSourceSnapshot<Section, NSManagedObjectID>

        dataSource.apply(newSnapshot, animatingDifferences: true)
    }
}

// MARK: - DiscussionViewCell

@available(iOS 15.0, *)
final class DiscussionSelectionViewCell: UICollectionViewListCell {

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
            circledInitials.configure(with: circledInitialsConfiguration)
        }

        accessories = [.multiselect()]
    }


}
