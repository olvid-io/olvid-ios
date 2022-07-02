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


final class FilesViewer: NSObject {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: FilesViewer.self))
    
    /// Empty when using the initialiser using hard links
    let shownFyleMessageJoins: [FyleMessageJoinWithStatus]
    private var hardLinksToFyles: [HardLinkToFyle?]
    
    weak var delegate: QLPreviewControllerDelegate?
    
    var cellIndexPath: IndexPath?
    
    private let previewController = CustomQLPreviewController()

    // These two variables are set when the tryToShowFile(...) is called.
    private var indexToShow: Int?
    weak private var viewController: UIViewController?
    
    private var previewControllerIsShown = false
    private var alwaysPreventSharing = false
    
    // MARK: - Initializers
    
    init(_ fyleMessageJoins: [FyleMessageJoinWithStatus]) throws {
        
        self.shownFyleMessageJoins = fyleMessageJoins
        
        self.hardLinksToFyles = [HardLinkToFyle?](repeating: nil, count: fyleMessageJoins.count)
        super.init()

        for (index, fyleMessageJoin) in fyleMessageJoins.enumerated() {
            
            let completionHandler = { [weak self] (result: Result<HardLinkToFyle,Error>) in
                switch result {
                case .success(let hardLinkToFyle):
                    self?.hardLinksToFyles[index] = hardLinkToFyle
                case .failure(let error):
                    assertionFailure(error.localizedDescription)
                }
                DispatchQueue.main.async {
                    self?.tryToPresentQLPreviewController()
                }
            }

            if let fyleElement = fyleMessageJoin.fyleElement {
                ObvMessengerInternalNotification.requestHardLinkToFyle(fyleElement: fyleElement, completionHandler: completionHandler).postOnDispatchQueue()
            }
            
        }

        observeCurrentItemToPreventSharingIfNecessary()

    }
    
    init(hardLinksToFyles: [HardLinkToFyle], alwaysPreventSharing: Bool) {
        self.shownFyleMessageJoins = []
        self.hardLinksToFyles = hardLinksToFyles
        self.alwaysPreventSharing = alwaysPreventSharing
        super.init()
        observeCurrentItemToPreventSharingIfNecessary()
    }
    
    
    private var kvo: NSKeyValueObservation?

    
    private func observeCurrentItemToPreventSharingIfNecessary() {
        kvo = previewController.observe(\.currentPreviewItemIndex, options: [.new, .prior]) { [weak self] _, change in
            guard let _self = self else { return }
            if change.isPrior {
                // When we receive a "prior" notification, we do not have access to the new index yet.
                // By precaution, we hide the sharing options
                self?.previewController.preventSharing = true
            } else {
                guard let index = change.newValue else { assertionFailure(); return }
                guard index < _self.shownFyleMessageJoins.count else {
                    self?.previewController.preventSharing = _self.alwaysPreventSharing
                    return
                }
                let join = _self.shownFyleMessageJoins[index]
                self?.previewController.preventSharing = !join.shareActionCanBeMadeAvailable
            }
        }
    }

    
    // MARK: - Other methods
    
    func tryToShowFile(atIndex index: Int, within viewController: UIViewController) {
        self.indexToShow = index
        self.viewController = viewController
        tryToPresentQLPreviewController()
    }
    
    
    private func tryToPresentQLPreviewController() {

        // We check whether showing the QLPreviewController was already requested
        guard let indexToShow = self.indexToShow, let viewController = self.viewController else { return }

        // We check that all the hardlinks are ready
        guard !self.hardLinksToFyles.contains(nil) else { return }

        // We check that we are not already showing the QLPreviewController
        guard !previewControllerIsShown else { return }
        previewControllerIsShown = true
        
        // If we reach this point, we are ready to show the QLPreviewController
        previewController.dataSource = self
        previewController.delegate = self.delegate
        previewController.currentPreviewItemIndex = indexToShow
        viewController.navigationController?.present(previewController, animated: true, completion: nil)

    }
}


// MARK: - QLPreviewControllerDataSource

extension FilesViewer: QLPreviewControllerDataSource {
    
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return self.hardLinksToFyles.count
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return self.hardLinksToFyles[index]!
    }
    
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

// MARK: - NewFilesViewer

/// This files viewer is similar to the "old" FileViewer, except that this one is more efficient as it does not preload all the hardlinks of the previewed files.
/// Moreover, this class is similar to FilesViewer but is instantiated with a fetched results controler
@MainActor
final class NewFilesViewer: NSObject {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: NewFilesViewer.self))

    private let frc: NSFetchedResultsController<FyleMessageJoinWithStatus>
    
    private weak var viewController: UIViewController?

    private var hardLinkToFyleForJoin = [FyleMessageJoinWithStatus: HardLinkToFyle]()

    private var previewControllerIsShown = false

    private let previewController = CustomQLPreviewController()
    
    private var section: Int? // Section of the initial index path
    
    private let queueForRequestingHardlinks = DispatchQueue(label: "NewFilesViewer internal queue for requesting hardlinks")
    
    init(frc: NSFetchedResultsController<FyleMessageJoinWithStatus>, qlPreviewControllerDelegate: QLPreviewControllerDelegate) {
        self.frc = frc
        previewController.delegate = qlPreviewControllerDelegate
        super.init()
        observeCurrentItemToPreventSharingIfNecessary()
    }
    
    private var kvo: NSKeyValueObservation?

    
    private func observeCurrentItemToPreventSharingIfNecessary() {
        kvo = previewController.observe(\.currentPreviewItemIndex, options: [.new, .prior]) { [weak self] _, change in
            guard let _self = self else { return }
            if change.isPrior {
                // When we receive a "prior" notification, we do not have access to the new index yet.
                // By precaution, we hide the sharing options
                self?.previewController.preventSharing = true
            } else {
                guard let section = self?.section else { return }
                guard let index = change.newValue else { assertionFailure(); return }
                let indexPath = IndexPath(item: index, section: section)
                guard section < _self.frc.sections?.count ?? 0 else { return }
                guard let sectionInfos = _self.frc.sections?[section] else { return }
                guard index < sectionInfos.numberOfObjects else { return }
                let join = _self.frc.object(at: indexPath)
                self?.previewController.preventSharing = !join.shareActionCanBeMadeAvailable
            }
        }
    }
    
    
    func tryToShowFile(atIndexPath indexPath: IndexPath, within viewController: UIViewController) {
        self.viewController = viewController
        self.section = indexPath.section
        Task {
            await requestHardLinkToFyleForIndexPathsCloseTo(indexPath: IndexPath(item: 0, section: indexPath.section))
            await requestHardLinkToFyleForIndexPathsCloseTo(indexPath: indexPath)
            tryToPresentQLPreviewController(indexPathToShow: indexPath)
        }
    }
    
    
    var currentPreviewItemIndexPath: IndexPath? {
        guard let section = self.section else { assertionFailure(); return nil }
        return IndexPath(item: previewController.currentPreviewItemIndex, section: section)
    }
    
    
    /// Asynchronously requests all the hardlinks to fyles "around" the index path.
    private func requestHardLinkToFyleForIndexPathsCloseTo(indexPath: IndexPath) async {
        assert(Thread.isMainThread)
        let section = indexPath.section
        let range = 2
        let firstItem = max(0, indexPath.item-range)
        let lastItem = min(numberOfItems-1, indexPath.item+range)
        for item in firstItem...lastItem {
            let indexPath = IndexPath(item: item, section: section)
            let join = frc.object(at: indexPath)
            guard !hardLinkToFyleForJoin.keys.contains(join) else { continue }
            guard let fyleElement = join.fyleElement else {
                // This typicially happens for received join where the associated received message requires user interaction to be read
                continue
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                ObvMessengerInternalNotification.requestHardLinkToFyle(fyleElement: fyleElement) { result in
                    assert(!Thread.isMainThread)
                    switch result {
                    case .success(let hardLinkToFyle):
                        DispatchQueue.main.async { [weak self] in
                            self?.hardLinkToFyleForJoin[join] = hardLinkToFyle
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
        guard let sections = frc.sections, let section = self.section else { return 0 }
        guard section < sections.count else { return 0 }
        return sections[section].numberOfObjects
    }
    
}


// MARK: - NewFilesViewer QLPreviewControllerDataSource

extension NewFilesViewer: QLPreviewControllerDataSource {
    
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

        let join = frc.object(at: indexPathToShow)

        if let hardLinkToFyle = hardLinkToFyleForJoin[join] {
            
            // The hardlink was cached, we can return it immediately
            
            return hardLinkToFyle

        } else if let fyleElement = join.fyleElement {
            
            // The hardlink is not cached yet, but we have the required elements allowing to request it.
            // Since the hardlink API is asynchronous, we must block the main thread until the hardlink is available (yes, we know...)
            
            let dispatchGroup = DispatchGroup()
            dispatchGroup.enter()
            ObvMessengerInternalNotification.requestHardLinkToFyle(fyleElement: fyleElement) { [weak self] result in
                switch result {
                case .success(let hardLinkToFyle):
                    self?.hardLinkToFyleForJoin[join] = hardLinkToFyle
                case .failure(let error):
                    assertionFailure(error.localizedDescription)
                }
                dispatchGroup.leave()
            }.postOnDispatchQueue(queueForRequestingHardlinks)
            dispatchGroup.wait()

            if let hardLinkToFyle = hardLinkToFyleForJoin[join] {
                return hardLinkToFyle
            } else {
                assertionFailure()
                return FailedQLPreviewItem()
            }
               
        } else if let receivedJoin = join as? ReceivedFyleMessageJoinWithStatus, receivedJoin.receivedMessage.readingRequiresUserAction {
            
            return FlameQLPreviewItem()
            
        } else {
            
            // This case should not occur in practice
            
            assertionFailure()
            return FailedQLPreviewItem()
            
        }

    }
    
}
