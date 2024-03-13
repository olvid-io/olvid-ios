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
import MobileCoreServices
import ObvUI
import ObvUICoreData
import OlvidUtils
import os.log
import QuickLook
import UIKit
import UniformTypeIdentifiers
import UI_SystemIcon
import ObvDesignSystem
import ObvEncoder


fileprivate enum JoinKind: Int, CaseIterable {
    case medias = 0
    case links
    case documents

    var title: String {
        switch self {
        case .medias: return CommonString.Word.Medias
        case .links: return CommonString.Word.Links
        case .documents: return CommonString.Word.Documents
        }
    }
}

protocol DiscussionGalleryViewControllerDelegate: AnyObject {
    func refreshToolbar()
    func setEditing(_ editing: Bool, animated: Bool)
}


// MARK: - DiscussionGalleryViewController

/// This view controller is a container view controller. It displays a `UISegmentedControl` allowing to switch between two galleries: one for the medias (images, movies,...) , one for the links and one for the other types of files.
/// The three children view controllers are instances of the `JoinGalleryViewController` defined bellow.
final class DiscussionGalleryViewController: UIViewController, DiscussionGalleryViewControllerDelegate {

    private let segmentedControl = UISegmentedControl(items: JoinKind.allCases.map({ $0.title }))
    private let toolbarLabel = UILabel()

    private let mediasCollectionView: JoinGalleryViewController
    private let linksCollectionView: JoinGalleryViewController
    private let documentsCollectionView: JoinGalleryViewController

    private var currentKind: JoinKind = .medias

    private var currentChildViewController: JoinGalleryViewController {
        childViewControllerOfKind(self.currentKind)
    }
    
    private var selectBarButtonItem: UIBarButtonItem?
    
    private func childViewControllerOfKind(_ kind: JoinKind) -> JoinGalleryViewController {
        switch kind {
        case .medias: return mediasCollectionView
        case .links: return linksCollectionView
        case .documents: return documentsCollectionView
        }
    }

    init(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        self.mediasCollectionView = JoinGalleryViewController(discussionObjectID: discussionObjectID, kind: .medias)
        self.linksCollectionView = JoinGalleryViewController(discussionObjectID: discussionObjectID, kind: .links)
        self.documentsCollectionView = JoinGalleryViewController(discussionObjectID: discussionObjectID, kind: .documents)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        debugPrint("DiscussionGalleryViewController deinit")
    }

    private func configureBarButtonItems() {
        let closeBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeButtonTapped))
        navigationItem.leftBarButtonItem = closeBarButtonItem
        let selectBarButtonItem = UIBarButtonItem(title: CommonString.Word.Select, style: .plain, target: self, action: #selector(rightBarButtonItemButtonItemTapped))
        navigationItem.rightBarButtonItem = selectBarButtonItem
        self.selectBarButtonItem = selectBarButtonItem
    }

    @objc func closeButtonTapped() {
        dismiss(animated: true)
    }

    @objc func rightBarButtonItemButtonItemTapped() {
        setEditing(!isEditing, animated: true)
    }


    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)

        currentChildViewController.setEditing(editing, animated: animated)

        if editing {
            refreshToolbar()
        } else {
            // Clear selection if leaving edit mode.
            currentChildViewController.clearSelection(animated: animated)
        }

        updateUserInterface()
    }

    func refreshToolbar() {
        let joins = currentChildViewController.selectedJoins()
        let allJoinsCanBeShared = joins.allSatisfy({ $0.shareActionCanBeMadeAvailable })
        let shareItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareBarButtonItemTapped))
        let numberOfChosenItems = joins.count
        shareItem.isEnabled = numberOfChosenItems > 0 && allJoinsCanBeShared
        let labelItem = UIBarButtonItem(customView: toolbarLabel)
        let trashItem = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(trashBarButtonItemTapped))
        trashItem.isEnabled = numberOfChosenItems > 0
        toolbarLabel.text = Strings.chooseNumberOfItems(numberOfChosenItems: numberOfChosenItems)
        toolbarLabel.textAlignment = .center
        toolbarItems = [.fixedSpace(8), shareItem, .flexibleSpace(), labelItem, .flexibleSpace(), trashItem, .fixedSpace(8)]
    }

    @objc func shareBarButtonItemTapped() {
        currentChildViewController.shareSelectedItems()
    }

    @objc func trashBarButtonItemTapped() {
        currentChildViewController.wipeSelectedItems()
    }

    
    private func updateUserInterface() {
        if let button = navigationItem.rightBarButtonItem {
            button.title = isEditing ? CommonString.Word.Cancel : CommonString.Word.Select
        }
        navigationController?.setToolbarHidden(!isEditing, animated: true)
    }

    
    private func configureHierarchy() {
        
        // Add all the child view controllers (we deal with their views later)
        
        for kind in JoinKind.allCases {
            let childViewController = childViewControllerOfKind(kind)
            childViewController.delegate = self
            childViewController.willMove(toParent: self)
            addChild(childViewController)
            childViewController.didMove(toParent: self)
            childViewController.view.translatesAutoresizingMaskIntoConstraints = false
        }
        
        // Depending on the current kind, we show the appropriate view controller's view
        
        self.view.addSubview(currentChildViewController.view)
        self.view.pinAllSidesToSides(of: currentChildViewController.view)

    }

    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        segmentedControl.selectedSegmentIndex = currentKind.rawValue
        segmentedControl.addTarget(self, action: #selector(segmentedControlValueChanged), for: .valueChanged)
        self.navigationItem.titleView = segmentedControl
        configureBarButtonItems()
    }

    
    @objc private func segmentedControlValueChanged() {
        guard let kind = JoinKind(rawValue: segmentedControl.selectedSegmentIndex) else {
            assertionFailure(); return
        }
        
        if kind == .links {
            navigationItem.rightBarButtonItem = nil
        } else {
            navigationItem.rightBarButtonItem = selectBarButtonItem
        }
        
        setEditing(false, animated: true)
        transitionToViewControllerOfKind(kind)
        refreshToolbar()
    }

    
    private func transitionToViewControllerOfKind(_ newKind: JoinKind) {

        guard self.currentKind != newKind else { return }

        let from = currentChildViewController
        let to = childViewControllerOfKind(newKind)
        
        assert(from.view.superview == self.view)
        assert(to.view.superview == nil)

        transition(from: from, to: to, duration: 0, options: [], animations: {
            to.view.pinAllSidesToSides(of: self.view)
        }) { [weak self] _ in
            self?.currentKind = newKind
        }
        
    }

}

// MARK: Localization

extension DiscussionGalleryViewController {

    private struct Strings {
        static func chooseNumberOfItems(numberOfChosenItems: Int) -> String {
            String.localizedStringWithFormat(NSLocalizedString("NUMBER_OF_ITEMS_SELECTED", comment: ""), numberOfChosenItems)
        }
    }

}


// MARK: - JoinGalleryViewController

final class JoinGalleryViewController: UIViewController, NSFetchedResultsControllerDelegate, UICollectionViewDataSourcePrefetching, UICollectionViewDelegate, ObvErrorMaker, CustomQLPreviewControllerDelegate {

    let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
    fileprivate let kind: JoinKind
    private let cacheDelegate = DiscussionCacheManager()
    
    static let errorDomain = "DiscussionGalleryViewController"
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "DiscussionGalleryViewController")
    
    private var shownFilesViewer: FilesViewer?

    private var observationTokens = [NSObjectProtocol]()

    // See UTCoreTypes.h
    fileprivate static let acceptableImageUTIs: [String] = [UTType.jpeg.description, UTType.gif.description, UTType.png.description, UTType.image.description, UTType.tiff.description, UTType.rawImage.description, UTType.svg.description, UTType.heic.description, UTType.heif.description]
    fileprivate static let acceptableVideoUTIs: [String] = [UTType.movie.description, UTType.quickTimeMovie.description, UTType.mpeg4Movie.description, UTType.mpeg.description, UTType.avi.description]
    fileprivate static let acceptablePreviewUTIs: [String] = [UTType.olvidLinkPreview.description]
    fileprivate static let acceptableMediaUTIs: [String] = acceptableImageUTIs + acceptableVideoUTIs

    fileprivate init(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, kind: JoinKind) {
        self.discussionObjectID = discussionObjectID
        self.kind = kind
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    private enum Section {
        case main
    }

    private var dataSource: UICollectionViewDiffableDataSource<Section, NSManagedObjectID>! = nil
    private var collectionView: UICollectionView! = nil
    private var frc: NSFetchedResultsController<FyleMessageJoinWithStatus>!

    weak var delegate: DiscussionGalleryViewControllerDelegate?

    private var typicalThumbnailSize: CGSize?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureDataSource()
        collectionView.delegate = self
        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = false
        collectionView.allowsMultipleSelectionDuringEditing = true
        observeDeletedFyleMessageJoinNotifications()
        setEditing(false, animated: false)
    }

    func selectedJoins() -> [FyleMessageJoinWithStatus] {
        guard let indexPathsForSelectedItems = collectionView?.indexPathsForSelectedItems else {
            return []
        }
        return indexPathsForSelectedItems.map({ frc.object(at: $0) })
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        collectionView.isEditing = editing
    }

    func clearSelection(animated: Bool) {
        collectionView.indexPathsForSelectedItems?.forEach({ (indexPath) in
            collectionView.deselectItem(at: indexPath, animated: animated)
        })
    }

}


// MARK: Selecting multiple images

extension JoinGalleryViewController {
    
    func shareSelectedItems() {
        let indexPathsForSelectedItems = collectionView.indexPathsForSelectedItems ?? []
        let joins = indexPathsForSelectedItems.map({ frc.object(at: $0) })
        let allJoinsCanBeShared = joins.allSatisfy({ $0.shareActionCanBeMadeAvailable })
        guard allJoinsCanBeShared else { return }
        let fyleElements = joins.compactMap({ $0.fyleElement })
        assert(fyleElements.count == joins.count)
        guard !fyleElements.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            let hardlinks: [HardLinkToFyle]
            do {
                hardlinks = try await Self.requestHardLinkToFyleForFyleElements(fyleElements)
            } catch {
                os_log("Could not share items: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            let itemProviders = hardlinks.compactMap({ $0.activityItemProvider })
            assert(itemProviders.count == hardlinks.count)
            DispatchQueue.main.async { [weak self] in
                let uiActivityVC = UIActivityViewController(activityItems: itemProviders, applicationActivities: nil)
                self?.present(uiActivityVC, animated: true)
            }
        }
    }
    
    
    private static func requestHardLinkToFyleForFyleElements(_ fyleElements: [FyleElement]) async throws -> [HardLinkToFyle] {
        return try await withThrowingTaskGroup(of: HardLinkToFyle.self, returning: [HardLinkToFyle].self) { taskGroup in
            for fyleElement in fyleElements {
                taskGroup.addTask {
                    return try await Self.requestHardLinkToFyleForFyleElement(fyleElement)
                }
            }
            var hardlinks = [HardLinkToFyle]()
            for try await value in taskGroup {
                hardlinks.append(value)
            }
            return hardlinks
        }
    }
    
    
    private static func requestHardLinkToFyleForFyleElement(_ fyleElement: FyleElement) async throws -> HardLinkToFyle {
        return try await withCheckedThrowingContinuation { continuation in
            HardLinksToFylesNotifications.requestHardLinkToFyle(fyleElement: fyleElement) { result in
                switch result {
                case .success(let hardlink):
                    continuation.resume(returning: hardlink)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }.postOnDispatchQueue()
        }
    }

    func wipeSelectedItems() {
        let indexPathsForSelectedItems = collectionView.indexPathsForSelectedItems ?? []
        wipeItems(at: indexPathsForSelectedItems, completionHandler: { _ in })
    }

    private func wipeItems(at indexPaths: [IndexPath], completionHandler: @escaping (Bool) -> Void) {
        let joinObjectIDs = Set(indexPaths.map({ frc.object(at: $0).typedObjectID }))
        guard !joinObjectIDs.isEmpty else { return }
        wipeFyleMessageJoinWithStatus(joinObjectIDs: joinObjectIDs, confirmed: false, completionHandler: completionHandler)
    }
    
    private func wipeFyleMessageJoinWithStatus(joinObjectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>, confirmed: Bool, completionHandler: @escaping (Bool) -> Void) {
        assert(Thread.isMainThread)
        if confirmed {
            guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else { return }
            guard let ownedCryptoId = discussion.ownedIdentity?.cryptoId else { return }
            ObvMessengerInternalNotification.userWantsToWipeFyleMessageJoinWithStatus(ownedCryptoId: ownedCryptoId, objectIDs: joinObjectIDs)
                .postOnDispatchQueue()
            delegate?.setEditing(false, animated: true)
            completionHandler(true)
        } else {
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)
            alert.addAction(UIAlertAction.init(title: NSLocalizedString("DELETE_ITEMS", comment: ""), style: .destructive) { [weak self] _ in
                self?.wipeFyleMessageJoinWithStatus(joinObjectIDs: joinObjectIDs, confirmed: true, completionHandler: completionHandler)
            })
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel) { _ in
                completionHandler(false)
            })
            present(alert, animated: true)
        }
    }
    
}


// MARK: - Configuring the view hierarchy

extension JoinGalleryViewController {
    
    private func configureHierarchy() {
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: createLayout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collectionView)
    }

    
    private func createLayout() -> UICollectionViewLayout {
        switch kind {
        case .medias:
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1/3),
                                                  heightDimension: .fractionalHeight(1.0))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)

            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                   heightDimension: .fractionalWidth(1/3))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize,
                                                           subitems: [item])

            let section = NSCollectionLayoutSection(group: group)

            let layout = UICollectionViewCompositionalLayout(section: section)
            return layout
        case .links:
            let configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            return UICollectionViewCompositionalLayout.list(using: configuration)
        case .documents:
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                var actions = [UIContextualAction]()
                let deleteAction = UIContextualAction(style: .destructive, title: CommonString.Word.Delete) { [weak self] (action, view, completion) in
                    self?.wipeItems(at: [indexPath], completionHandler: completion)
                }
                actions += [deleteAction]
                return UISwipeActionsConfiguration(actions: actions)
            }
            return UICollectionViewCompositionalLayout.list(using: configuration)
        }
    }

}


// MARK: - Configure the data source

extension JoinGalleryViewController {
    
    private func makeFrc() -> NSFetchedResultsController<FyleMessageJoinWithStatus> {
        switch kind {
        case .medias:
            return FyleMessageJoinWithStatus.getFetchedResultsControllerForAllJoinsWithinDiscussion(discussionObjectID: discussionObjectID, restrictToUTIs: Self.acceptableMediaUTIs, within: ObvStack.shared.viewContext)
        case .links:
            return FyleMessageJoinWithStatus.getFetchedResultsControllerForAllJoinsWithinDiscussion(discussionObjectID: discussionObjectID, restrictToUTIs: Self.acceptablePreviewUTIs, within: ObvStack.shared.viewContext)
        case .documents:
            return FyleMessageJoinWithStatus.getFetchedResultsControllerForAllJoinsWithinDiscussion(discussionObjectID: discussionObjectID, excludedUTIs: Self.acceptableMediaUTIs + Self.acceptablePreviewUTIs, within: ObvStack.shared.viewContext)
        }
    }
    
    private func configureDataSource() {
        
        self.frc = makeFrc()
        self.frc.delegate = self

        let mediaRegistration = UICollectionView.CellRegistration<MediaViewCell, FyleMessageJoinWithStatus> { [weak self] (cell, _, join) in
            let thumbnailSize = CGSize(width: cell.bounds.size.width, height: cell.bounds.size.height)
            self?.updateGalleryViewCell(cell, with: join, thumbnailSize: thumbnailSize)
        }
        let linkRegistration = UICollectionView.CellRegistration<LinkViewCell, FyleMessageJoinWithStatus> { [weak self] (cell, _, join) in
            let thumbnailSize = CGSize(width: cell.bounds.size.height * 1.414, height: cell.bounds.size.height) // A4 ratio
            self?.updateGalleryViewCellFromLink(cell, with: join, thumbnailSize: thumbnailSize)
        }
        
        let documentRegistration = UICollectionView.CellRegistration<DocumentViewCell, FyleMessageJoinWithStatus> { [weak self] (cell, _, join) in
            let thumbnailSize = CGSize(width: 40.0, height: 40.0) // A4 ratio
            self?.updateGalleryViewCell(cell, with: join, thumbnailSize: thumbnailSize)
        }

        dataSource = UICollectionViewDiffableDataSource<Section, NSManagedObjectID>(collectionView: collectionView) { [weak self] (collectionView: UICollectionView, indexPath: IndexPath, objectID: NSManagedObjectID) -> UICollectionViewCell? in
            guard let self else { return nil }
            guard let join = try? FyleMessageJoinWithStatus.get(objectID: objectID, within: ObvStack.shared.viewContext) else { return nil }
            switch self.kind {
            case .medias:
                return collectionView.dequeueConfiguredReusableCell(using: mediaRegistration, for: indexPath, item: join)
            case .links:
                return collectionView.dequeueConfiguredReusableCell(using: linkRegistration, for: indexPath, item: join)
            case .documents:
                return collectionView.dequeueConfiguredReusableCell(using: documentRegistration, for: indexPath, item: join)
            }
        }

        try? frc.performFetch()

        collectionView.prefetchDataSource = self
    }
    
    
    @MainActor
    private func updateGalleryViewCell(_ cell: GalleryViewCell, with join: FyleMessageJoinWithStatus, thumbnailSize: CGSize) {
        
        if let receivedJoin = join as? ReceivedFyleMessageJoinWithStatus, receivedJoin.receivedMessage.readingRequiresUserAction {
            cell.updateWhenReadingRequiresUserAction(join: join)
            return
        }

        typicalThumbnailSize = thumbnailSize
        
        if let thumbnail = cacheDelegate.getCachedPreparedImage(for: join.typedObjectID, size: thumbnailSize) {
            cell.updateWith(join: join, thumbnail: .computed(thumbnail))
        } else {
            cell.updateWith(join: join, thumbnail: .computing)
            Task { [weak self] in
                guard let self else { return }
                assert(Thread.isMainThread)
                do {
                    try await cacheDelegate.requestPreparedImage(objectID: join.typedObjectID, size: thumbnailSize)
                } catch {
                    cell.updateWith(join: join, thumbnail: .error(contentType: join.contentType))
                    return
                }
                joinNeedsUpdate(objectID: join.typedObjectID)
            }
        }
    }
    
    @MainActor
    private func updateGalleryViewCellFromLink(_ cell: GalleryViewCell, with join: FyleMessageJoinWithStatus, thumbnailSize: CGSize) {
        Task { [weak self] in
            guard let self else { return }
            guard let linkCell = cell as? LinkViewCell else { return }
            guard let fallbackURL = URL(string: join.fileName), let fyleURL = join.fyle?.url else {
                linkCell.linkMetadata = nil
                cell.updateWith(join: join, thumbnail: .error(contentType: UTType.olvidLinkPreview))
                return
            }
            
            if FileManager.default.fileExists(atPath: fyleURL.path),
               let data = try? Data(contentsOf: fyleURL),
               let obvEncoded = ObvEncoded(withRawData: data) {
                guard let preview = ObvLinkMetadata.decode(obvEncoded, fallbackURL: fallbackURL), let previewImage = preview.image else {
                    linkCell.linkMetadata = nil
                    linkCell.updateWith(join: join, thumbnail: .error(contentType: UTType.olvidLinkPreview))
                    joinNeedsUpdate(objectID: join.typedObjectID)
                    return
                }
                
                linkCell.linkMetadata = preview
                linkCell.updateWith(join: join, thumbnail: .computed(previewImage))
            } else {
                linkCell.linkMetadata = nil
                linkCell.updateWith(join: join, thumbnail: .error(contentType: UTType.olvidLinkPreview))
            }
        }
    }
    
}


// MARK: - Dismissing the files viewer when an attachment expires

extension JoinGalleryViewController {

    private func observeDeletedFyleMessageJoinNotifications() {
        let NotificationName = NSNotification.Name.NSManagedObjectContextObjectsDidChange
        let token = NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { [weak self] (notification) in
            
            // Make sure we are considering changes made in the view context, i.e., posted on the main thread
            
            guard Thread.isMainThread else { return }
            
            // Construct a set of FyleMessageJoinWithStatus currently shown by the file viewer
            
            guard let filesViewer = self?.shownFilesViewer else { return }
            guard case .fyleMessageJoinWithStatus(frc: let frcOfFilesViewer) = filesViewer.frcType else { return }
            guard let shownObjectIDs = frcOfFilesViewer.fetchedObjects?.map({ $0.objectID }) else { return }

            // Construct a set of deleted/wiped FyleMessageJoinWithStatus
            
            var objectIDs = Set<NSManagedObjectID>()
            do {
                if let deletedObjects = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>, !deletedObjects.isEmpty {
                    let deletedFyleMessageJoinWithStatuses = deletedObjects.compactMap({ $0 as? FyleMessageJoinWithStatus })
                    objectIDs.formUnion(Set(deletedFyleMessageJoinWithStatuses.map({ $0.objectID })))
                }
                if let updatedObjects = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>, !updatedObjects.isEmpty {
                    let wipedFyleMessageJoinWithStatuses = updatedObjects
                        .compactMap { $0 as? FyleMessageJoinWithStatus }
                        .filter { $0.isWiped }
                    objectIDs.formUnion(Set(wipedFyleMessageJoinWithStatuses.map({ $0.objectID })))
                }
            }
            
            guard !objectIDs.isEmpty else { return }
            
            // Construct a set of FyleMessageJoinWithStatus shown by the file viewer
            
            guard !objectIDs.isDisjoint(with: shownObjectIDs) else { return }
            DispatchQueue.main.async {
                (self?.presentedViewController as? QLPreviewController)?.dismiss(animated: true, completion: {
                    self?.shownFilesViewer = nil
                })
            }
        }
        observationTokens.append(token)
    }
    
}


// MARK: - NSFetchedResultsControllerDelegate

extension JoinGalleryViewController {
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {

        let collectionView = self.collectionView!
        guard let dataSource = collectionView.dataSource as? UICollectionViewDiffableDataSource<Section, NSManagedObjectID> else { assertionFailure(); return }
        
        let newSnapshot = snapshot as NSDiffableDataSourceSnapshot<Section, NSManagedObjectID>
        
        dataSource.apply(newSnapshot, animatingDifferences: true)

        // When in select mode, we want to refresh the toobar in case we had selected an element that was just deleted.
        delegate?.refreshToolbar()
    }
    
    
    private func joinNeedsUpdate(objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) {
        
        let collectionView = self.collectionView!
        guard let dataSource = collectionView.dataSource as? UICollectionViewDiffableDataSource<Section, NSManagedObjectID> else { assertionFailure(); return }

        var snapshot = dataSource.snapshot()
        if snapshot.itemIdentifiers.contains(where: { $0 == objectID.objectID}) {
            snapshot.reconfigureItems([objectID.objectID])
        }
        dataSource.apply(snapshot, animatingDifferences: true)

    }
    
}


// MARK: - UICollectionViewDataSourcePrefetching

extension JoinGalleryViewController {

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {

        guard let thumbnailSize = typicalThumbnailSize else { return }

        for indexPath in indexPaths {
            let objectID = frc.object(at: indexPath).typedObjectID
            if cacheDelegate.getCachedPreparedImage(for: objectID, size: thumbnailSize) == nil {
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await cacheDelegate.requestPreparedImage(objectID: objectID, size: thumbnailSize)
                    } catch {
                        os_log("The request for a prepared image failed (2): %{public}@", log: Self.log, type: .error, error.localizedDescription)
                    }
                }
            }
        }

    }
    
}


// MARK: - UICollectionViewDelegate

extension JoinGalleryViewController {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // This gets called when the user selects the cell, i.e., touches then lifts her finger.
        if collectionView.isEditing {
            delegate?.refreshToolbar()
        } else if let linkCell = collectionView.cellForItem(at: indexPath) as? LinkViewCell {
            collectionView.deselectItem(at: indexPath, animated: true)
            guard let url = linkCell.linkMetadata?.url else { return }
            // the user tapped on a link
            Task { await UIApplication.shared.userSelectedURL(url, within: self) }
        } else {
            // In that case, we want to show a large preview of the image.
            collectionView.deselectItem(at: indexPath, animated: false)
            assert(shownFilesViewer == nil)
            let newFrc = makeFrc()
            try? newFrc.performFetch()
            shownFilesViewer = FilesViewer(frc: newFrc, qlPreviewControllerDelegate: self)
            shownFilesViewer?.tryToShowFile(atIndexPath: indexPath, within: self)
        }
    }
    
    
    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        delegate?.refreshToolbar()
    }
    
    
    func collectionView(_ collectionView: UICollectionView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        // Returning `true` automatically sets `collectionView.isEditing` to `true`. The app sets it to `false` after the user taps the Cancel button.
        return true
    }
    
    
    func collectionView(_ collectionView: UICollectionView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        // Replace the Select button with Cancel, and put the collection view into editing mode.
        delegate?.setEditing(true, animated: true)
    }

}


// MARK: - CustomQLPreviewControllerDelegate

extension JoinGalleryViewController {
    
    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        shownFilesViewer = nil
    }
    
    
    func previewController(_ controller: QLPreviewController, transitionViewFor item: QLPreviewItem) -> UIView? {
        guard let shownFilesViewer = self.shownFilesViewer else { assertionFailure(); return nil }
        guard let currentPreviewItemIndexPath = shownFilesViewer.currentPreviewItemIndexPath else { assertionFailure(); return nil }
        let cell = collectionView.cellForItem(at: currentPreviewItemIndexPath)
        switch kind {
        case .medias:
            return cell
        case .links:
            guard let documentViewCell = cell as? LinkViewCell else { assertionFailure(); return nil }
            if case .computed = documentViewCell.thumbnail {
                return (cell as? DocumentViewCell)?.galleryImageView
            } else {
                return nil
            }
        case .documents:
            guard let documentViewCell = cell as? DocumentViewCell else { assertionFailure(); return nil }
            if case .computed = documentViewCell.thumbnail {
                return (cell as? DocumentViewCell)?.galleryImageView
            } else {
                return nil
            }
        }
    }

    func previewController(hasDisplayed joinID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) {
        ObvMessengerInternalNotification.userHasOpenedAReceivedAttachment(receivedFyleJoinID: joinID).postOnDispatchQueue()
    }

}


// MARK: - UIContextMenuConfiguration

extension JoinGalleryViewController {
    
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {

        guard let cell = collectionView.cellForItem(at: indexPath) as? GalleryViewCell else { return nil }
        guard let join = cell.join else { return nil }

        let actionProvider = makeActionProvider(forForJoin: join)

        let menuConfiguration = UIContextMenuConfiguration(indexPath: indexPath,
                                                           previewProvider: nil,
                                                           actionProvider: actionProvider)

        return menuConfiguration
    }


    private func makeActionProvider(forForJoin join: FyleMessageJoinWithStatus) -> (([UIMenuElement]) -> UIMenu?) {
        return { (suggestedActions) in

            var children = [UIMenuElement]()

            // Share action

            if join.shareActionCanBeMadeAvailable {
                
                let action = UIAction(title: CommonString.Word.Share) { (_) in
                    guard let fyleElement = join.fyleElement else { assertionFailure(); return }
                    Task { [weak self] in
                        do {
                            let hardlink = try await Self.requestHardLinkToFyleForFyleElement(fyleElement)
                            guard let itemProvider = hardlink.activityItemProvider else { throw Self.makeError(message: "Could not get activity item provider") }
                            DispatchQueue.main.async { [weak self] in
                                let uiActivityVC = UIActivityViewController(activityItems: [itemProvider], applicationActivities: nil)
                                self?.present(uiActivityVC, animated: true)
                            }
                        } catch {
                            os_log("Could not share item: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                            assertionFailure()
                            return
                        }
                    }
                }
                action.image = UIImage(systemIcon: .squareAndArrowUp)
                children.append(action)
                
            }
            
            // Show in discussion action

            if let messagePermanentID = join.message?.messagePermanentID, let ownedCryptoId = join.message?.discussion?.ownedIdentity?.cryptoId {
                let action = UIAction(title: NSLocalizedString("SHOW_IN_DISCUSSION", comment: "")) { (_) in
                    let deepLink = ObvDeepLink.message(ownedCryptoId: ownedCryptoId, objectPermanentID: messagePermanentID)
                    ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                        .postOnDispatchQueue()
                }
                action.image = UIImage(systemIcon: .bubbleLeftAndBubbleRight)
                children.append(action)
            }
            
            // Delete action
            
            if join.deleteActionCanBeMadeAvailable {
                let joinObjectID = join.typedObjectID
                let action = UIAction(title: CommonString.Word.Delete) { [weak self] (_) in
                    self?.wipeFyleMessageJoinWithStatus(joinObjectIDs: [joinObjectID], confirmed: false) { _ in }
                }
                action.image = UIImage(systemIcon: .trash)
                action.attributes = [.destructive]
                children.append(action)
            }

            return UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: children)
            
        }
    }
    
}

// MARK: - Cells

fileprivate protocol GalleryViewCell: UICollectionViewCell {
    var join: FyleMessageJoinWithStatus? { get }
    func updateWith(join: FyleMessageJoinWithStatus, thumbnail: ThumbnailValue)
    func updateWhenReadingRequiresUserAction(join: FyleMessageJoinWithStatus)
}

enum ThumbnailValue: Hashable {
    case computing
    case computed(_: UIImage)
    case error(contentType: UTType)
}

final class MediaViewCell: UICollectionViewCell, GalleryViewCell {
    
    private(set) var join: FyleMessageJoinWithStatus?
    private(set) var thumbnail: ThumbnailValue?
    private(set) var readingRequiresUserAction = false
    private(set) var isReadOnce = false

    func updateWith(join: FyleMessageJoinWithStatus, thumbnail: ThumbnailValue) {
        self.join = join
        self.thumbnail = thumbnail
        self.readingRequiresUserAction = false
        self.isReadOnce = join.readOnce
        setNeedsUpdateConfiguration()
    }
    
    func updateWhenReadingRequiresUserAction(join: FyleMessageJoinWithStatus) {
        self.join = join
        self.thumbnail = nil
        self.readingRequiresUserAction = true
        self.isReadOnce = join.readOnce
    }
    
    override func updateConfiguration(using state: UICellConfigurationState) {
        var content = MediaViewCellContentConfiguration().updated(for: state)
        content.thumbnail = thumbnail
        content.readingRequiresUserAction = readingRequiresUserAction
        content.isReadOnce = isReadOnce
        if let uti = join?.uti {
            content.joinIsPlayable = JoinGalleryViewController.acceptableVideoUTIs.contains(uti)
        } else {
            content.joinIsPlayable = false
        }
        contentConfiguration = content
    }
    
}

struct DocumentCellConfiguration: ImageCellConfiguration {
    let thumbnail: ThumbnailValue?
    let readingRequiresUserAction: Bool
    let isReadOnce: Bool
    let joinIsPlayable: Bool
    let isMedia = false
}

final class DocumentViewCell: UICollectionViewListCell, GalleryViewCell {

    private func defaultListContentConfiguration() -> UIListContentConfiguration { return .subtitleCell() }
    private lazy var listContentView = UIListContentView(configuration: defaultListContentConfiguration())

    private(set) var join: FyleMessageJoinWithStatus?
    private(set) var thumbnail: ThumbnailValue?
    private(set) var readingRequiresUserAction = false
    private(set) var isReadOnce = false
    private let byteCountFormatter = ByteCountFormatter()
    private var viewsSetupWasPerformed = false
    let galleryImageView = GalleryImageView()

    func updateWith(join: FyleMessageJoinWithStatus, thumbnail: ThumbnailValue) {
        self.join = join
        self.thumbnail = thumbnail
        self.readingRequiresUserAction = false
        self.isReadOnce = join.readOnce
        setNeedsUpdateConfiguration()
    }

    func updateWhenReadingRequiresUserAction(join: FyleMessageJoinWithStatus) {
        self.join = join
        self.thumbnail = nil
        self.readingRequiresUserAction = true
        self.isReadOnce = join.readOnce
    }

    
    private func setupViewsIfNeeded() {

        // Make sure we setup the views exactly once
        guard !viewsSetupWasPerformed else { return }
        defer { viewsSetupWasPerformed = true }

        contentView.addSubview(galleryImageView)
        galleryImageView.translatesAutoresizingMaskIntoConstraints = false
        galleryImageView.layer.borderWidth = 1
        galleryImageView.layer.borderColor = AppTheme.shared.colorScheme.label.withAlphaComponent(0.1).cgColor
        galleryImageView.layer.cornerRadius = 3.0

        contentView.addSubview(listContentView)
        listContentView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            listContentView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: verticalPadding),
            listContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            listContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -verticalPadding),
            listContentView.leadingAnchor.constraint(equalTo: galleryImageView.trailingAnchor),

            galleryImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16.0),
            galleryImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            galleryImageView.widthAnchor.constraint(equalToConstant: 40),
            galleryImageView.heightAnchor.constraint(equalToConstant: 40 * 1.414), // a4 paper ratio
        ])
        
    }

    private let verticalPadding: CGFloat = 8.0

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .short
        df.timeStyle = .short
        df.locale = Locale.current
        return df
    }()

    override func updateConfiguration(using state: UICellConfigurationState) {
        setupViewsIfNeeded()

        var content = defaultListContentConfiguration().updated(for: state)
        guard let join = join else {
            return
        }

        if readingRequiresUserAction {
            content.text = NSLocalizedString("EPHEMERAL_MESSAGE", comment: "")
        } else {
            content.text = join.fileName
        }
        let textStyle = UIFont.TextStyle.callout
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle).withDesign(.rounded)?.withSymbolicTraits(.traitBold) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle)
        content.textProperties.font = UIFont(descriptor: fontDescriptor, size: 0)
        content.textProperties.color = AppTheme.shared.colorScheme.label

        var subtitleElements = [String]()
        if let date = join.message?.timestamp {
            let dateString = dateFormatter.string(from: date)
            subtitleElements.append(dateString)
        }
        let contentType = join.contentType
        let fileSize = Int(join.totalByteCount)
        subtitleElements.append(byteCountFormatter.string(fromByteCount: Int64(fileSize)))
        if let type = contentType.localizedDescription {
            subtitleElements.append(type)
        }
        content.secondaryText = subtitleElements.joined(separator: " - ")
        let secondaryTextStyle = UIFont.TextStyle.footnote
        let secondaryFontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: secondaryTextStyle).withDesign(.rounded) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: secondaryTextStyle)
        content.secondaryTextProperties.font = UIFont(descriptor: secondaryFontDescriptor, size: 0)
        content.secondaryTextProperties.color = AppTheme.shared.colorScheme.secondaryLabel

        content.textToSecondaryTextVerticalPadding = verticalPadding / 2

        listContentView.configuration = content

        let joinIsPlayable: Bool
        joinIsPlayable = contentType.conforms(to: .audio)

        let imageConfiguration = DocumentCellConfiguration(thumbnail: self.thumbnail,
                                                           readingRequiresUserAction: self.readingRequiresUserAction,
                                                           isReadOnce: self.isReadOnce,
                                                           joinIsPlayable: joinIsPlayable)


        galleryImageView.apply(configuration: imageConfiguration)

        accessories = [.multiselect()]
    }

}


struct LinkCellConfiguration: ImageCellConfiguration {
    let thumbnail: ThumbnailValue?
    let readingRequiresUserAction: Bool
    let isReadOnce: Bool
    let joinIsPlayable: Bool
    let isMedia = false
}

final class LinkViewCell: UICollectionViewListCell, GalleryViewCell {

    private func defaultListContentConfiguration() -> UIListContentConfiguration { return .subtitleCell() }
    private lazy var listContentView = UIListContentView(configuration: defaultListContentConfiguration())

    private(set) var join: FyleMessageJoinWithStatus?
    private(set) var thumbnail: ThumbnailValue?
    private(set) var readingRequiresUserAction = false
    private(set) var isReadOnce = false
    private var viewsSetupWasPerformed = false
    
    public var linkMetadata: ObvLinkMetadata?
    
    let galleryImageView = GalleryImageView()

    func updateWith(join: FyleMessageJoinWithStatus, thumbnail: ThumbnailValue) {
        self.join = join
        self.thumbnail = thumbnail
        self.readingRequiresUserAction = false
        self.isReadOnce = join.readOnce
        setNeedsUpdateConfiguration()
    }

    func updateWhenReadingRequiresUserAction(join: FyleMessageJoinWithStatus) {
        self.join = join
        self.thumbnail = nil
        self.readingRequiresUserAction = true
        self.isReadOnce = join.readOnce
    }

    
    private func setupViewsIfNeeded() {

        // Make sure we setup the views exactly once
        guard !viewsSetupWasPerformed else { return }
        defer { viewsSetupWasPerformed = true }

        contentView.addSubview(galleryImageView)
        galleryImageView.translatesAutoresizingMaskIntoConstraints = false
        galleryImageView.layer.borderWidth = 1
        galleryImageView.layer.borderColor = AppTheme.shared.colorScheme.label.withAlphaComponent(0.1).cgColor
        galleryImageView.layer.cornerRadius = 3.0

        contentView.addSubview(listContentView)
        listContentView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            listContentView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: verticalPadding),
            listContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            listContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -verticalPadding),
            listContentView.leadingAnchor.constraint(equalTo: galleryImageView.trailingAnchor),

            galleryImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16.0),
            galleryImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            galleryImageView.widthAnchor.constraint(equalToConstant: 40),
            galleryImageView.heightAnchor.constraint(equalToConstant: 40), // a4 paper ratio
        ])
        
    }

    private let verticalPadding: CGFloat = 8.0

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .short
        df.timeStyle = .short
        df.locale = Locale.current
        return df
    }()

    override func updateConfiguration(using state: UICellConfigurationState) {
        setupViewsIfNeeded()

        var content = defaultListContentConfiguration().updated(for: state)
        guard let join = join else {
            return
        }

        if readingRequiresUserAction {
            content.text = NSLocalizedString("EPHEMERAL_MESSAGE", comment: "")
            content.secondaryText = nil
        } else {
            content.text = join.fileName
            content.secondaryTextProperties.numberOfLines = 2
            content.secondaryText = linkMetadata?.desc
        }
        let textStyle = UIFont.TextStyle.callout
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle).withDesign(.rounded)?.withSymbolicTraits(.traitBold) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle)
        content.textProperties.font = UIFont(descriptor: fontDescriptor, size: 0)
        content.textProperties.color = AppTheme.shared.colorScheme.label

        let secondaryTextStyle = UIFont.TextStyle.footnote
        let secondaryFontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: secondaryTextStyle).withDesign(.rounded) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: secondaryTextStyle)
        content.secondaryTextProperties.font = UIFont(descriptor: secondaryFontDescriptor, size: 0)
        content.secondaryTextProperties.color = AppTheme.shared.colorScheme.secondaryLabel

        content.textToSecondaryTextVerticalPadding = verticalPadding / 2

        listContentView.configuration = content

        let imageConfiguration = DocumentCellConfiguration(thumbnail: self.thumbnail,
                                                           readingRequiresUserAction: self.readingRequiresUserAction,
                                                           isReadOnce: self.isReadOnce,
                                                           joinIsPlayable: false)


        galleryImageView.apply(configuration: imageConfiguration)

        accessories = [.multiselect()]
    }

}

// MARK: - Configurations

fileprivate struct MediaViewCellContentConfiguration: UIContentConfiguration, Hashable, ImageCellConfiguration {
    
    var joinObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>?

    var thumbnail: ThumbnailValue?
    var readingRequiresUserAction = false
    var isReadOnce = false
    var joinIsPlayable = false
    private(set) var showSelectedCheckMark = false
    let isMedia = true

    func makeContentView() -> UIView & UIContentView {
        return MediaViewCellContentView(configuration: self)
    }

    func updated(for state: UIConfigurationState) -> Self {
        guard let state = state as? UICellConfigurationState else { return self }
        var updatedConfig = self
        updatedConfig.showSelectedCheckMark = state.isSelected
        return updatedConfig
    }

}

// MARK: - Views

final class MediaViewCellContentView: UIView, UIContentView {

    fileprivate init(configuration: MediaViewCellContentConfiguration) {
        super.init(frame: .zero)
        setupInternalViews()
        apply(configuration: configuration)
    }


    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    var configuration: UIContentConfiguration {
        get { appliedConfiguration }
        set {
            guard let newConfig = newValue as? MediaViewCellContentConfiguration else { return }
            apply(configuration: newConfig)
        }
    }

    private let imageView = GalleryImageView()
    private let checkMarkView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        return UIImageView(image: UIImage(systemIcon: .checkmarkCircleFill, withConfiguration: configuration)?.withRenderingMode(.alwaysOriginal))
    }()
    private let semiOpaqueView = UIView()

    private func setupInternalViews() {

        backgroundColor = appTheme.colorScheme.systemFill

        addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.pinAllSidesToSides(of: self)

        imageView.addSubview(semiOpaqueView)
        semiOpaqueView.translatesAutoresizingMaskIntoConstraints = false
        semiOpaqueView.backgroundColor = appTheme.colorScheme.systemFill

        addSubview(checkMarkView)
        checkMarkView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            semiOpaqueView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            semiOpaqueView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            semiOpaqueView.topAnchor.constraint(equalTo: imageView.topAnchor),
            semiOpaqueView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),

            checkMarkView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8.0),
            checkMarkView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8.0),
        ])

    }

    private var appliedConfiguration: MediaViewCellContentConfiguration!

    private func apply(configuration: MediaViewCellContentConfiguration) {
        guard appliedConfiguration != configuration else { return }
        appliedConfiguration = configuration

        imageView.apply(configuration: configuration)
        checkMarkView.isHidden = !configuration.showSelectedCheckMark
        if configuration.thumbnail == nil || configuration.readingRequiresUserAction {
            semiOpaqueView.isHidden = true
        } else {
            semiOpaqueView.isHidden = !configuration.showSelectedCheckMark
        }
    }

}

protocol ImageCellConfiguration {
    var thumbnail: ThumbnailValue? { get }
    var readingRequiresUserAction: Bool { get }
    var isReadOnce: Bool { get }
    var joinIsPlayable: Bool { get }
    var isMedia: Bool { get } // or Documents
}

extension ImageCellConfiguration {
    var showFlameIndicator: Bool {
        if thumbnail == nil { return true }
        if readingRequiresUserAction { return true }
        return isReadOnce
    }
    var showPlayButton: UIImage.SymbolConfiguration? {
        if readingRequiresUserAction { return nil }
        guard joinIsPlayable else { return nil }
        return UIImage.SymbolConfiguration(pointSize: isMedia ? 35 : 20, weight: .bold)
    }
    var showImage: UIImage? {
        if readingRequiresUserAction { return nil }
        guard let thumbnail = thumbnail else { return nil }
        switch thumbnail {
        case .computing:
            return nil
        case .error:
            return nil
        case .computed(let image):
            return image
        }
    }
    var showIcon: IconView.Configuration? {
        if readingRequiresUserAction {
            return IconView.Configuration(icon: .flameFill, tintColor: .red)
        }
        if showPlayButton != nil { return nil }
        guard let thumbnail = thumbnail else { return nil }
        switch thumbnail {
        case .computing:
            return nil
        case .error(contentType: let contentType):
            let icon = contentType.systemIcon
            return IconView.Configuration(icon: icon, tintColor: .secondaryLabel)
        case .computed:
            return nil
        }
    }
    var showSpinner: Bool {
        if readingRequiresUserAction { return false }
        if thumbnail == nil { return true }
        return false
    }

}

final class GalleryImageView: UIView {

    fileprivate init() {
        super.init(frame: .zero)
        setupInternalViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let iconView = IconView()
    private let playCircleView = UIImageView()

    let flameIndicator: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        return UIImageView(image: UIImage(systemIcon: .flameFill, withConfiguration: configuration))
    }()

    private func setupInternalViews() {

        backgroundColor = appTheme.colorScheme.systemFill

        addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(spinner)
        spinner.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        addSubview(playCircleView)
        playCircleView.translatesAutoresizingMaskIntoConstraints = false
        playCircleView.tintColor = appTheme.colorScheme.secondaryLabel

        imageView.addSubview(flameIndicator)
        flameIndicator.translatesAutoresizingMaskIntoConstraints = false
        flameIndicator.tintColor = .red

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),

            playCircleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            playCircleView.centerYAnchor.constraint(equalTo: centerYAnchor),

            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: trailingAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor),
            iconView.bottomAnchor.constraint(equalTo: bottomAnchor),

            flameIndicator.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 4),
            flameIndicator.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -4),
        ])

        imageView.preferredSymbolConfiguration = .init(font: .preferredFont(forTextStyle: .body), scale: .large)
        imageView.isHidden = true

    }

    fileprivate func apply(configuration: ImageCellConfiguration) {
        // Flame
        flameIndicator.isHidden = !configuration.showFlameIndicator

        // Play
        if let sizeConfiguration = configuration.showPlayButton {
            playCircleView.isHidden = false
            let colorConfiguration = UIImage.SymbolConfiguration(paletteColors: [UIColor.gray.withAlphaComponent(0.9), UIColor.white.withAlphaComponent(0.9)])
            playCircleView.image = UIImage(systemIcon: .playCircleFill, withConfiguration: sizeConfiguration)?.applyingSymbolConfiguration(colorConfiguration)
        } else {
            playCircleView.isHidden = true
        }

        // Image
        if let image = configuration.showImage {
            imageView.image = image
            imageView.isHidden = false
            imageView.alpha = 1
        } else {
            imageView.image = nil
            imageView.isHidden = true
            imageView.alpha = 0
        }

        // Icon
        if let iconConfiguration = configuration.showIcon {
            iconView.isHidden = false
            iconView.setConfiguration(newConfiguration: iconConfiguration)
        } else {
            iconView.isHidden = true
        }

        // Spinner
        if configuration.showSpinner {
            spinner.isHidden = false
            spinner.startAnimating()
        } else {
            spinner.isHidden = true
            spinner.stopAnimating()
        }
    }

}

final class IconView: UIView {

    let iconView = UIImageView()

    struct Configuration: Equatable {
        let icon: SystemIcon
        let tintColor: UIColor?
    }

    private var currentConfiguration: Configuration?

    func setConfiguration(newConfiguration: Configuration) {
        guard newConfiguration != currentConfiguration else { return }
        self.currentConfiguration = newConfiguration
        iconView.tintColor = newConfiguration.tintColor
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        iconView.image = UIImage(systemIcon: newConfiguration.icon, withConfiguration: configuration)
    }

    
    init() {
        super.init(frame: .zero)

        backgroundColor = .clear
        
        addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
        ])

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
