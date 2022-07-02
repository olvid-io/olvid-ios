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
import os.log
import OlvidUtils
import UniformTypeIdentifiers
import QuickLook


@available(iOS 15.0, *)
final class DiscussionGalleryViewController: UIViewController, NSFetchedResultsControllerDelegate, UICollectionViewDataSourcePrefetching, UICollectionViewDelegate, ObvErrorMaker, QLPreviewControllerDelegate {

    let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>

    private let cacheDelegate = DiscussionCacheManager()
    
    static let errorDomain = "DiscussionGalleryViewController"
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "DiscussionGalleryViewController")
    
    private var shownFilesViewer: NewFilesViewer?
    
    // See UTCoreTypes.h
    fileprivate static let acceptableImageUTIs: [String] = [UTType.jpeg.description, UTType.gif.description, UTType.png.description, UTType.image.description, UTType.tiff.description, UTType.rawImage.description, UTType.svg.description, UTType.heic.description, UTType.heif.description]
    fileprivate static let acceptableVideoUTIs: [String] = [UTType.movie.description, UTType.quickTimeMovie.description, UTType.mpeg4Movie.description, UTType.mpeg.description, UTType.avi.description]
    fileprivate static let acceptableUTIs: [String] = {
        var utis = [String]()
        utis.append(contentsOf: acceptableImageUTIs)
        utis.append(contentsOf: acceptableVideoUTIs)
        return utis
    }()

    init(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        self.discussionObjectID = discussionObjectID
        super.init(nibName: nil, bundle: nil)
    }
    
    private let toolbarLabel = UILabel()
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    private enum Section {
        case main
    }

    private var dataSource: UICollectionViewDiffableDataSource<Section, NSManagedObjectID>! = nil
    private var collectionView: UICollectionView! = nil
    private var frc: NSFetchedResultsController<FyleMessageJoinWithStatus>!

    private var typicalThumbnailSize: CGSize?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Word.Gallery
        configureHierarchy()
        configureDataSource()
        collectionView.delegate = self
        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = false
        collectionView.allowsMultipleSelectionDuringEditing = true
        configureBarButtonItems()
        setEditing(false, animated: false)
    }
    
    
    private func configureBarButtonItems() {
        let closeBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeButtonTapped))
        navigationItem.leftBarButtonItem = closeBarButtonItem
        let selectBarButtonItem = UIBarButtonItem(title: CommonString.Word.Select, style: .plain, target: self, action: #selector(rightBarButtonItemButtonItemTapped))
        navigationItem.rightBarButtonItem = selectBarButtonItem
    }

    
    @objc func closeButtonTapped() {
        dismiss(animated: true)
    }
    
    
    @objc func rightBarButtonItemButtonItemTapped() {
        setEditing(!isEditing, animated: true)
    }
    
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)

        collectionView.isEditing = editing
        
        if editing {
            refreshToolbar()
        } else {
            // Clear selection if leaving edit mode.
            collectionView.indexPathsForSelectedItems?.forEach({ (indexPath) in
                collectionView.deselectItem(at: indexPath, animated: animated)
            })
        }
        
        updateUserInterface()
    }
    
    
    private func updateUserInterface() {
        if let button = navigationItem.rightBarButtonItem {
            button.title = isEditing ? CommonString.Word.Cancel : CommonString.Word.Select
        }
        navigationController?.setToolbarHidden(!isEditing, animated: true)
    }

}


// MARK: - Selecting multiple images

@available(iOS 15.0, *)
extension DiscussionGalleryViewController {
    
    
    private func refreshToolbar() {
        let indexPathsForSelectedItems = collectionView.indexPathsForSelectedItems ?? []
        let numberOfChosenItems = indexPathsForSelectedItems.count
        let joins = indexPathsForSelectedItems.map({ frc.object(at: $0) })
        let allJoinsCanBeShared = joins.allSatisfy({ $0.shareActionCanBeMadeAvailable })
        let shareItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareBarButtonItemTapped))
        shareItem.isEnabled = numberOfChosenItems > 0 && allJoinsCanBeShared
        let labelItem = UIBarButtonItem(customView: toolbarLabel)
        let trashItem = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(trashBarButtonItemTapped))
        trashItem.isEnabled = numberOfChosenItems > 0
        toolbarLabel.text = Strings.chooseNumberOfItems(numberOfChosenItems: numberOfChosenItems)
        toolbarLabel.textAlignment = .center
        toolbarItems = [.fixedSpace(8), shareItem, .flexibleSpace(), labelItem, .flexibleSpace(), trashItem, .fixedSpace(8)]
    }
    
    
    @objc func shareBarButtonItemTapped() {
        let indexPathsForSelectedItems = collectionView.indexPathsForSelectedItems ?? []
        let joins = indexPathsForSelectedItems.map({ frc.object(at: $0) })
        let allJoinsCanBeShared = joins.allSatisfy({ $0.shareActionCanBeMadeAvailable })
        guard allJoinsCanBeShared else { return }
        let fyleElements = joins.compactMap({ $0.fyleElement })
        assert(fyleElements.count == joins.count)
        guard !fyleElements.isEmpty else { return }
        Task {
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
            ObvMessengerInternalNotification.requestHardLinkToFyle(fyleElement: fyleElement) { result in
                switch result {
                case .success(let hardlink):
                    continuation.resume(returning: hardlink)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }.postOnDispatchQueue()
        }
    }

    
    @objc func trashBarButtonItemTapped() {
        let indexPathsForSelectedItems = collectionView.indexPathsForSelectedItems ?? []
        let joinObjectIDs = Set(indexPathsForSelectedItems.map({ frc.object(at: $0).typedObjectID }))
        guard !joinObjectIDs.isEmpty else { return }
        wipeFyleMessageJoinWithStatus(joinObjectIDs: joinObjectIDs, confirmed: false)
    }
    
    
    private func wipeFyleMessageJoinWithStatus(joinObjectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>, confirmed: Bool) {
        if confirmed {
            ObvMessengerInternalNotification.userWantsToWipeFyleMessageJoinWithStatus(objectIDs: joinObjectIDs)
                .postOnDispatchQueue()
            setEditing(false, animated: true)
        } else {
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)
            alert.addAction(UIAlertAction.init(title: NSLocalizedString("DELETE_ITEMS", comment: ""), style: .destructive) { [weak self] _ in
                self?.wipeFyleMessageJoinWithStatus(joinObjectIDs: joinObjectIDs, confirmed: true)
            })
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel, handler: nil))
            present(alert, animated: true)
        }
    }
    
}


// MARK: - Configuring the view hierarchy

@available(iOS 15.0, *)
extension DiscussionGalleryViewController {
    
    private func configureHierarchy() {
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: createLayout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collectionView)
    }

    
    private func createLayout() -> UICollectionViewLayout {
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
    }

}


// MARK: - Configure the data source

@available(iOS 15.0, *)
extension DiscussionGalleryViewController {
    
    private func configureDataSource() {
        
        self.frc = FyleMessageJoinWithStatus.getFetchedResultsControllerForAllJoinsWithinDiscussion(discussionObjectID: discussionObjectID, restrictToUTIs: Self.acceptableUTIs, within: ObvStack.shared.viewContext)
        self.frc.delegate = self

        let cellRegistration = UICollectionView.CellRegistration<GalleryPhotoViewCell, FyleMessageJoinWithStatus> { [weak self] (cell, indexPath, join) in
            self?.updateGalleryPhotoViewCell(cell, at: indexPath, with: join)
        }
        
        dataSource = UICollectionViewDiffableDataSource<Section, NSManagedObjectID>(collectionView: collectionView) { (collectionView: UICollectionView, indexPath: IndexPath, objectID: NSManagedObjectID) -> UICollectionViewCell? in
            guard let join = try? FyleMessageJoinWithStatus.get(objectID: objectID, within: ObvStack.shared.viewContext) else { return nil }
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: join)
        }

        try? frc.performFetch()

        collectionView.prefetchDataSource = self
        
    }
    
    
    @MainActor
    private func updateGalleryPhotoViewCell(_ cell: GalleryPhotoViewCell, at indexPath: IndexPath, with join: FyleMessageJoinWithStatus) {
        
        if let receivedJoin = join as? ReceivedFyleMessageJoinWithStatus, receivedJoin.receivedMessage.readingRequiresUserAction {
            cell.updateWhenReadingRequiresUserAction(join: join)
            return
        }
        
        let thumbnailSize = CGSize(width: cell.bounds.size.width, height: cell.bounds.size.height)
        
        typicalThumbnailSize = thumbnailSize
        
        if let thumbnail = cacheDelegate.getCachedPreparedImage(for: join.typedObjectID, size: thumbnailSize) {
            cell.updateWith(join: join, thumbnail: thumbnail)
        } else {
            cell.updateWith(join: join, thumbnail: nil)
            Task {
                assert(Thread.isMainThread)
                do {
                    try await cacheDelegate.requestPreparedImage(objectID: join.typedObjectID, size: thumbnailSize)
                } catch {
                    os_log("The request for a prepared image failed (1): %{public}@", log: Self.log, type: .error, error.localizedDescription)
                    return
                }
                joinNeedsUpdate(objectID: join.typedObjectID)
            }
        }
        
    }
    
}

// MARK: - Localization

@available(iOS 15.0, *)
extension DiscussionGalleryViewController {

    private struct Strings {
        static func chooseNumberOfItems(numberOfChosenItems: Int) -> String {
            String.localizedStringWithFormat(NSLocalizedString("NUMBER_OF_ITEMS_SELECTED", comment: ""), numberOfChosenItems)
        }
    }
    
}


// MARK: - NSFetchedResultsControllerDelegate

@available(iOS 15.0, *)
extension DiscussionGalleryViewController {
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {

        let collectionView = self.collectionView!
        guard let dataSource = collectionView.dataSource as? UICollectionViewDiffableDataSource<Section, NSManagedObjectID> else { assertionFailure(); return }
        
        let newSnapshot = snapshot as NSDiffableDataSourceSnapshot<Section, NSManagedObjectID>
        
        dataSource.apply(newSnapshot, animatingDifferences: true)

    }
    
    
    private func joinNeedsUpdate(objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) {
        
        let collectionView = self.collectionView!
        guard let dataSource = collectionView.dataSource as? UICollectionViewDiffableDataSource<Section, NSManagedObjectID> else { assertionFailure(); return }

        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([objectID.objectID])
        dataSource.apply(snapshot, animatingDifferences: true)

    }
    
}


// MARK: - UICollectionViewDataSourcePrefetching

@available(iOS 15.0, *)
extension DiscussionGalleryViewController {

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {

        guard let thumbnailSize = typicalThumbnailSize else { return }

        for indexPath in indexPaths {
            let objectID = frc.object(at: indexPath).typedObjectID
            if cacheDelegate.getCachedPreparedImage(for: objectID, size: thumbnailSize) == nil {
                Task {
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

@available(iOS 15.0, *)
extension DiscussionGalleryViewController {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // This gets called when the user selects the cell, i.e., touches then lifts her finger.
        if collectionView.isEditing {
            refreshToolbar()
        } else {
            // In that case, we want to show a large preview of the image.
            collectionView.deselectItem(at: indexPath, animated: false)
            assert(shownFilesViewer == nil)
            shownFilesViewer = NewFilesViewer(frc: frc, qlPreviewControllerDelegate: self)
            shownFilesViewer?.tryToShowFile(atIndexPath: indexPath, within: self)
        }
    }
    
    
    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        debugPrint(collectionView.indexPathsForSelectedItems as Any)
        refreshToolbar()
    }
    
    
    func collectionView(_ collectionView: UICollectionView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        // Returning `true` automatically sets `collectionView.isEditing` to `true`. The app sets it to `false` after the user taps the Cancel button.
        return true
    }
    
    
    func collectionView(_ collectionView: UICollectionView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        // Replace the Select button with Cancel, and put the collection view into editing mode.
        setEditing(true, animated: true)
    }

}


// MARK: - QLPreviewControllerDelegate

@available(iOS 15.0, *)
extension DiscussionGalleryViewController {
    
    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        shownFilesViewer = nil
    }
    
    
    func previewController(_ controller: QLPreviewController, transitionViewFor item: QLPreviewItem) -> UIView? {
        guard let shownFilesViewer = self.shownFilesViewer else { assertionFailure(); return nil }
        guard let currentPreviewItemIndexPath = shownFilesViewer.currentPreviewItemIndexPath else { assertionFailure(); return nil }
        let cell = collectionView.cellForItem(at: currentPreviewItemIndexPath)
        return cell
    }
    
}


// MARK: - UIContextMenuConfiguration

@available(iOS 15.0, *)
extension DiscussionGalleryViewController {
    
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {

        guard let cell = collectionView.cellForItem(at: indexPath) as? GalleryPhotoViewCell else { return nil }
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
                    Task {
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

            if let messageObjectURI = join.message?.objectID.uriRepresentation() {
                let action = UIAction(title: NSLocalizedString("SHOW_IN_DISCUSSION", comment: "")) { (_) in
                    let deepLink = ObvDeepLink.message(messageObjectURI: messageObjectURI)
                    ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                        .postOnDispatchQueue()
                }
                action.image = UIImage(systemIcon: .bubbleLeftAndBubbleRight)
                children.append(action)
            }
            
            // Delete action
            
            do {
                let joinObjectID = join.typedObjectID
                let action = UIAction(title: CommonString.Word.Delete) { [weak self] (_) in
                    self?.wipeFyleMessageJoinWithStatus(joinObjectIDs: [joinObjectID], confirmed: false)
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

@available(iOS 15.0, *)
final class GalleryPhotoViewCell: UICollectionViewCell {
    
    static let reuseIdentifier = "GalleryPhotoViewCell"
    
    private(set) var join: FyleMessageJoinWithStatus?
    private(set) var thumbnail: UIImage?
    private(set) var readingRequiresUserAction = false
    private(set) var isReadOnce = false

    func updateWith(join: FyleMessageJoinWithStatus, thumbnail: UIImage?) {
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
        var content = GalleryPhotoViewCellCustomContentConfiguration().updated(for: state)
        content.thumbnail = thumbnail
        content.readingRequiresUserAction = readingRequiresUserAction
        content.isReadOnce = isReadOnce
        if let uti = join?.uti {
            content.joinIsVideo = DiscussionGalleryViewController.acceptableVideoUTIs.contains(uti)
        } else {
            content.joinIsVideo = false
        }
        contentConfiguration = content
    }
    
}


// MARK: - GalleryPhotoViewCellCustomContentConfiguration

@available(iOS 15.0, *)
fileprivate struct GalleryPhotoViewCellCustomContentConfiguration: UIContentConfiguration, Hashable {
    
    var joinObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>?

    var thumbnail: UIImage?
    var readingRequiresUserAction = false
    var isReadOnce = false
    var joinIsVideo = false
    private(set) var showSelectedCheckMark = false

    func makeContentView() -> UIView & UIContentView {
        return GalleryPhotoViewCellContentView(configuration: self)
    }

    func updated(for state: UIConfigurationState) -> Self {
        guard let state = state as? UICellConfigurationState else { return self }
        var updatedConfig = self
        updatedConfig.showSelectedCheckMark = state.isSelected
        return updatedConfig
    }

}


// MARK: - GalleryPhotoViewCellContentView

@available(iOS 15.0, *)
final class GalleryPhotoViewCellContentView: UIView, UIContentView {

    fileprivate init(configuration: GalleryPhotoViewCellCustomContentConfiguration) {
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
            guard let newConfig = newValue as? GalleryPhotoViewCellCustomContentConfiguration else { return }
            apply(configuration: newConfig)
        }
    }

    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let checkMarkView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        return UIImageView(image: UIImage(systemIcon: .checkmarkCircleFill, withConfiguration: configuration)?.withRenderingMode(.alwaysOriginal))
    }()
    private let playCircleView: UIImageView = {
        let sizeConfiguration = UIImage.SymbolConfiguration(pointSize: 35, weight: .bold)
        let colorConfiguration = UIImage.SymbolConfiguration(paletteColors: [UIColor.gray.withAlphaComponent(0.9), UIColor.white.withAlphaComponent(0.9)])
        return UIImageView(image: UIImage(systemIcon: .playCircleFill, withConfiguration: sizeConfiguration)?.applyingSymbolConfiguration(colorConfiguration))
    }()
    private let semiOpaqueView = UIView()
    private let flameView = FlameView()

    let flameIndicator: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        return UIImageView(image: UIImage(systemIcon: .flameFill, withConfiguration: configuration))
    }()

    private func setupInternalViews() {
        
        backgroundColor = appTheme.colorScheme.systemFill

        addSubview(flameView)
        flameView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(spinner)
        spinner.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        
        imageView.addSubview(semiOpaqueView)
        semiOpaqueView.translatesAutoresizingMaskIntoConstraints = false
        semiOpaqueView.backgroundColor = appTheme.colorScheme.systemFill
        
        imageView.addSubview(playCircleView)
        playCircleView.translatesAutoresizingMaskIntoConstraints = false
        playCircleView.tintColor = appTheme.colorScheme.secondaryLabel
        
        imageView.addSubview(flameIndicator)
        flameIndicator.translatesAutoresizingMaskIntoConstraints = false
        flameIndicator.tintColor = .red

        addSubview(checkMarkView)
        checkMarkView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),

            playCircleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            playCircleView.centerYAnchor.constraint(equalTo: centerYAnchor),

            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            semiOpaqueView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            semiOpaqueView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            semiOpaqueView.topAnchor.constraint(equalTo: imageView.topAnchor),
            semiOpaqueView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            
            checkMarkView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8.0),
            checkMarkView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8.0),
            
            flameView.leadingAnchor.constraint(equalTo: leadingAnchor),
            flameView.trailingAnchor.constraint(equalTo: trailingAnchor),
            flameView.topAnchor.constraint(equalTo: topAnchor),
            flameView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            flameIndicator.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 4),
            flameIndicator.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -4),

        ])

        imageView.preferredSymbolConfiguration = .init(font: .preferredFont(forTextStyle: .body), scale: .large)
        imageView.isHidden = true
                
    }
    
    private var appliedConfiguration: GalleryPhotoViewCellCustomContentConfiguration!

    private func apply(configuration: GalleryPhotoViewCellCustomContentConfiguration) {
        guard appliedConfiguration != configuration else { return }
        appliedConfiguration = configuration

        checkMarkView.isHidden = !configuration.showSelectedCheckMark
        
        if configuration.thumbnail == nil || configuration.readingRequiresUserAction {
            
            if configuration.readingRequiresUserAction {
                
                flameIndicator.isHidden = true
                playCircleView.isHidden = true
                flameView.isHidden = false
                spinner.isHidden = true
                spinner.stopAnimating()
                imageView.isHidden = true
                imageView.alpha = 0
                semiOpaqueView.isHidden = true

            } else {
                
                flameIndicator.isHidden = true
                playCircleView.isHidden = true
                flameView.isHidden = true
                spinner.isHidden = false
                spinner.startAnimating()
                imageView.isHidden = true
                imageView.alpha = 0
                semiOpaqueView.isHidden = true
                
            }
            
        } else {

            flameIndicator.isHidden = !configuration.isReadOnce
            playCircleView.isHidden = !configuration.joinIsVideo
            flameView.isHidden = true
            spinner.isHidden = true
            spinner.stopAnimating()
            imageView.isHidden = false
            imageView.image = configuration.thumbnail
            imageView.alpha = 1
            semiOpaqueView.isHidden = !configuration.showSelectedCheckMark

        }
                
    }

}


final class FlameView: UIView {
    
    let flameView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        return UIImageView(image: UIImage(systemIcon: .flameFill, withConfiguration: configuration))
    }()

    
    init() {
        super.init(frame: .zero)

        backgroundColor = .clear
        
        addSubview(flameView)
        flameView.translatesAutoresizingMaskIntoConstraints = false
        flameView.tintColor = .red
        
        NSLayoutConstraint.activate([
            flameView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            flameView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
        ])

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
