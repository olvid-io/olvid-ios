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
import MobileCoreServices
import PDFKit
import AVKit
import os.log
import QuickLook
import CoreData
import OlvidUtils
import ObvUI

protocol CustomQLPreviewControllerDelegate: QLPreviewControllerDelegate {
    func previewController(hasDisplayed joinID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>)
}

final class CustomQLPreviewController: QLPreviewController {
    
    var preventSharing = false {
        didSet {
            view.setNeedsLayout()
        }
    }

    private var hiddenToolbars = [UIToolbar: UIView]()
    private var disabledButtons = [UIBarButtonItem]()
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if preventSharing {
            self.hideToolBar()
            self.hideShareButtonFromNavigationBar()
        } else {
            self.unhideToolBar()
            self.unhideShareButtonFromNavigationBar()
        }
    }
        
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.view.setNeedsLayout()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.view.setNeedsLayout()
    }
    
    /// This is used when `preventSharing` is `true` to hide all bottom toolbar since they contain a sharing
    /// button when more than one items are previewed.
    private func hideToolBar() {
        let allToolbars = self.view.deepSearchAllSubview(ofClass: UIToolbar.self)
        for toolbar in allToolbars {
            if let hidingView = hiddenToolbars[toolbar] {
                hidingView.isHidden = false
            } else {
                let hidingView = UIView()
                hiddenToolbars[toolbar] = hidingView
                hidingView.translatesAutoresizingMaskIntoConstraints = false
                hidingView.backgroundColor = AppTheme.shared.colorScheme.systemBackground
                toolbar.addSubview(hidingView)
                hidingView.pinAllSidesToSides(of: toolbar)
            }
        }
    }
    
    
    private func unhideToolBar() {
        let hidingViews = hiddenToolbars.values
        hidingViews.forEach({ $0.isHidden = true })
    }
    
    
    /// This is used when `preventSharing` is `true` to hide all top right navigation button since one is shown
    /// when one item are previewed.
    private func hideShareButtonFromNavigationBar() {
        let allNavigationBars = self.view.deepSearchAllSubview(ofClass: UINavigationBar.self)
        for nav in allNavigationBars {
            if let button = nav.topItem?.rightBarButtonItem {
                button.isEnabled = false
                disabledButtons.append(button)
            }
            if let buttons = nav.topItem?.rightBarButtonItems, !buttons.isEmpty {
                buttons.forEach { $0.isEnabled = false }
                disabledButtons.append(contentsOf: buttons)
            }
        }
    }
    
    
    private func unhideShareButtonFromNavigationBar() {
        disabledButtons.forEach({ $0.isEnabled = true })
    }
    
}

// MARK: - FilesViewer

/// This files viewer is similar to the "old" FileViewer, except that this one is more efficient as it does not preload all the hardlinks of the previewed files.
/// Moreover, this class is similar to FilesViewer but is instantiated with a fetched results controler
final class FilesViewer: NSObject, NSFetchedResultsControllerDelegate, ObvErrorMaker {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: FilesViewer.self))

    enum FetchedResultsControllerType {
        case fyleMessageJoinWithStatus(frc: NSFetchedResultsController<FyleMessageJoinWithStatus>)
        case persistedDraftFyleJoin(frc: NSFetchedResultsController<PersistedDraftFyleJoin>)
    }
    
    static let errorDomain = "FilesViewer"

    let frcType: FetchedResultsControllerType
    
    private weak var viewController: UIViewController?

    private var hardLinkToFyleForJoin = [NSManagedObjectID: HardLinkToFyle]()

    private var previewControllerIsShown = false

    private let previewController = CustomQLPreviewController()
    
    private var section: Int? // Section of the initial index path
    
    private let queueForRequestingHardlinks = DispatchQueue(label: "FilesViewer internal queue for requesting hardlinks")
    
    private var observationTokens = [NSObjectProtocol]()

    private var reloadDataOnNextControllerDidChangeContent = false
    
    init(frc: NSFetchedResultsController<FyleMessageJoinWithStatus>, qlPreviewControllerDelegate: CustomQLPreviewControllerDelegate) {
        assert(frc.delegate == nil)
        self.frcType = .fyleMessageJoinWithStatus(frc: frc)
        previewController.delegate = qlPreviewControllerDelegate
        super.init()
        observeCurrentItemToPreventSharingIfNecessary()
        observeCurrentItemToSendReadReceiptIfNecessary()
        if case .fyleMessageJoinWithStatus(frc: let frc) = frcType {
            frc.delegate = self
        }
    }

    
    init(frc: NSFetchedResultsController<PersistedDraftFyleJoin>, qlPreviewControllerDelegate: CustomQLPreviewControllerDelegate) {
        self.frcType = .persistedDraftFyleJoin(frc: frc)
        previewController.delegate = qlPreviewControllerDelegate
        super.init()
        // No need to observe current item to prevent sharing
    }

    private var kvoTokens = [NSKeyValueObservation]()
    
    private func observeCurrentItemToPreventSharingIfNecessary() {
        let token = previewController.observe(\.currentPreviewItemIndex, options: [.new, .prior]) { [weak self] _, change in
            guard case let .fyleMessageJoinWithStatus(frc) = self?.frcType else { return }
            if change.isPrior {
                // When we receive a "prior" notification, we do not have access to the new index yet.
                // By precaution, we hide the sharing options
                self?.previewController.preventSharing = true
            } else {
                guard let section = self?.section else { return }
                guard let index = change.newValue else { assertionFailure(); return }
                let indexPath = IndexPath(item: index, section: section)
                guard section < frc.sections?.count ?? 0 else { return }
                guard let sectionInfos = frc.sections?[section] else { return }
                guard index < sectionInfos.numberOfObjects else { return }
                let join = frc.object(at: indexPath)
                self?.previewController.preventSharing = !join.shareActionCanBeMadeAvailable
            }
        }
        kvoTokens.append(token)
    }

    private func observeCurrentItemToSendReadReceiptIfNecessary() {
        let token = previewController.observe(\.currentPreviewItemIndex, options: [.new, .prior]) { [weak self] _, change in
            guard case let .fyleMessageJoinWithStatus(frc) = self?.frcType else { return }
            guard !change.isPrior else { return }
            guard let section = self?.section else { return }
            guard let index = change.newValue else { assertionFailure(); return }
            let indexPath = IndexPath(item: index, section: section)
            guard section < frc.sections?.count ?? 0 else { return }
            guard let sectionInfos = frc.sections?[section] else { return }
            guard index < sectionInfos.numberOfObjects else { return }
            let join = frc.object(at: indexPath)

            guard let receivedJoin = join as? ReceivedFyleMessageJoinWithStatus else { return }
            guard let customDelegate = self?.previewController.delegate as? CustomQLPreviewControllerDelegate else { assertionFailure(); return }
            customDelegate.previewController(hasDisplayed: receivedJoin.typedObjectID)
        }
        kvoTokens.append(token)
    }
    
    
    func tryToShowFile(atIndexPath indexPath: IndexPath, within viewController: UIViewController) {
        self.viewController = viewController
        self.section = indexPath.section
        Task {
            await requestHardLinkToFyleForIndexPathsCloseTo(indexPath: IndexPath(item: 0, section: indexPath.section))
            await requestHardLinkToFyleForIndexPathsCloseTo(indexPath: indexPath)
            await tryToPresentQLPreviewController(indexPathToShow: indexPath)
        }
    }
    
    
    func tryToShowFyleMessageJoinWithStatus(_ join: FyleMessageJoinWithStatus, within viewController: UIViewController) throws {
        guard case .fyleMessageJoinWithStatus(let frc) = frcType else { throw Self.makeError(message: "Unexpected frc type") }
        guard let indexPath = frc.indexPath(forObject: join) else { throw Self.makeError(message: "Could not find join") }
        tryToShowFile(atIndexPath: indexPath, within: viewController)
    }
    
    
    var currentPreviewItemIndexPath: IndexPath? {
        guard let section = self.section else { assertionFailure(); return nil }
        return IndexPath(item: previewController.currentPreviewItemIndex, section: section)
    }
    
    
    var currentPreviewFyleMessageJoinWithStatus: FyleMessageJoinWithStatus? {
        guard case .fyleMessageJoinWithStatus(let frc) = frcType else { assertionFailure(); return nil }
        guard let indexPath = currentPreviewItemIndexPath else { return nil }
        return frc.object(at: indexPath)
    }

    
    /// Asynchronously requests all the hardlinks to fyles "around" the index path.
    @MainActor
    private func requestHardLinkToFyleForIndexPathsCloseTo(indexPath: IndexPath) async {
        assert(Thread.isMainThread)
        guard case let .fyleMessageJoinWithStatus(frc) = frcType else { return }
        let section = indexPath.section
        let range = 2
        let firstItem = max(0, indexPath.item-range)
        let lastItem = min(numberOfItems-1, indexPath.item+range)
        for item in firstItem...lastItem {
            let indexPath = IndexPath(item: item, section: section)
            let join = frc.object(at: indexPath)
            guard !hardLinkToFyleForJoin.keys.contains(join.objectID) else { continue }
            guard let fyleElement = join.fyleElement else {
                // This typicially happens for received join where the associated received message requires user interaction to be read
                continue
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                HardLinksToFylesNotifications.requestHardLinkToFyle(fyleElement: fyleElement) { result in
                    assert(!Thread.isMainThread)
                    switch result {
                    case .success(let hardLinkToFyle):
                        DispatchQueue.main.async { [weak self] in
                            self?.hardLinkToFyleForJoin[join.objectID] = hardLinkToFyle
                            continuation.resume()
                        }
                    case .failure(let error):
                        assertionFailure(error.localizedDescription)
                        continuation.resume()
                    }
                }.postOnDispatchQueue(queueForRequestingHardlinks)
            }
        }
    }
    
    
    /// When the fetched results controller changes content (e.g., when a file expires), we reload the preview controller.
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if reloadDataOnNextControllerDidChangeContent {
            previewController.reloadData()
        }
        reloadDataOnNextControllerDidChangeContent = false
    }

    /// Only reload data if one of the changes is insert, delete or move.
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert, .delete, .move:
            reloadDataOnNextControllerDidChangeContent = true
        case .update:
            break
        @unknown default:
            assertionFailure()
        }
    }
    
    
    @MainActor
    private func tryToPresentQLPreviewController(indexPathToShow: IndexPath) {

        guard let viewController = self.viewController else { return }

        // We check that we are not already showing the QLPreviewController
        guard !previewControllerIsShown else { return }
        previewControllerIsShown = true
        
        // If we reach this point, we are ready to show the QLPreviewController
        previewController.dataSource = self
        previewController.currentPreviewItemIndex = indexPathToShow.item
        viewController.navigationController?.present(previewController, animated: true, completion: nil)

    }

    
    private final class FailedQLPreviewItem: NSObject, QLPreviewItem {
        let previewItemTitle: String? = CommonString.Word.Oups
        let previewItemURL: URL? = nil
    }
    
    private final class FlameQLPreviewItem: NSObject, QLPreviewItem {
        let previewItemTitle: String? = "🔥"
        let previewItemURL: URL? = nil
    }
    
    private var numberOfItems: Int {
        let sections: [NSFetchedResultsSectionInfo]
        switch frcType {
        case .fyleMessageJoinWithStatus(let frc):
            guard let _sections = frc.sections else { return 0 }
            sections = _sections
        case .persistedDraftFyleJoin(let frc):
            guard let _sections = frc.sections else { return 0 }
            sections = _sections
        }
        guard let section = self.section else { return 0 }
        guard section < sections.count else { return 0 }
        return sections[section].numberOfObjects
    }
    
}


// MARK: - FilesViewer QLPreviewControllerDataSource

extension FilesViewer: QLPreviewControllerDataSource {
    
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return numberOfItems
    }

    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        
        // Get the corresponding join
        
        guard let section = self.section else { assertionFailure(); return FailedQLPreviewItem() }
        let indexPathToShow = IndexPath(item: index, section: section)
        
        // Request all hardlinks around the one requested (we do not wait for the result)
        
        Task {
            await requestHardLinkToFyleForIndexPathsCloseTo(indexPath: indexPathToShow)
        }
        
        // If the HardLinkToFyle is already known for this join (we hope so), return it

        let hardLinkToFyle: HardLinkToFyle?
        let fyleElement: FyleElement?
        let joinObject: NSManagedObject
        switch frcType {
        case .fyleMessageJoinWithStatus(frc: let frc):
            let join = frc.object(at: indexPathToShow)
            hardLinkToFyle = hardLinkToFyleForJoin[join.objectID]
            fyleElement = join.fyleElement
            joinObject = join
        case .persistedDraftFyleJoin(frc: let frc):
            let join = frc.object(at: indexPathToShow)
            hardLinkToFyle = hardLinkToFyleForJoin[join.objectID]
            fyleElement = join.fyleElement
            joinObject = join
        }
        
        if let hardLinkToFyle = hardLinkToFyle {
            
            // The hardlink was cached, we can return it immediately
            
            return hardLinkToFyle

        } else if let fyleElement = fyleElement {
            
            // The hardlink is not cached yet, but we have the required elements allowing to request it.
            // Since the hardlink API is asynchronous, we must block the main thread until the hardlink is available (yes, we know...)
            
            let dispatchGroup = DispatchGroup()
            dispatchGroup.enter()
            HardLinksToFylesNotifications.requestHardLinkToFyle(fyleElement: fyleElement) { [weak self] result in
                switch result {
                case .success(let hardLinkToFyle):
                    self?.hardLinkToFyleForJoin[joinObject.objectID] = hardLinkToFyle
                case .failure(let error):
                    assertionFailure(error.localizedDescription)
                }
                dispatchGroup.leave()
            }.postOnDispatchQueue(queueForRequestingHardlinks)
            dispatchGroup.wait()

            if let hardLinkToFyle = hardLinkToFyleForJoin[joinObject.objectID] {
                return hardLinkToFyle
            } else {
                assertionFailure()
                return FailedQLPreviewItem()
            }
               
        } else if let receivedJoin = joinObject as? ReceivedFyleMessageJoinWithStatus, receivedJoin.receivedMessage.readingRequiresUserAction {

            return FlameQLPreviewItem()
            
        } else {
            
            // This case should not occur in practice
            
            assertionFailure()
            return FailedQLPreviewItem()
            
        }

    }
    
}
