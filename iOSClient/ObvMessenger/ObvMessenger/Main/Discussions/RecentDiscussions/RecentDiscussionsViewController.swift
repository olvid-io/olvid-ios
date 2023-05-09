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
import os.log
import ObvEngine
import ObvTypes
import ObvUI
import UIKit


final class RecentDiscussionsViewController: ShowOwnedIdentityButtonUIViewController, ViewControllerWithEllipsisCircleRightBarButtonItem {

    @IBOutlet weak var tableViewControllerPlaceholder: UIView!

    private var cancellables = [AnyCancellable]()

    weak var delegate: RecentDiscussionsViewControllerDelegate?
    
    private var discussionsListCoordinator: Coordinator?
    
    deinit {
        cancellables.forEach({ $0.cancel() })
        cancellables.removeAll()
    }

    
    // MARK: - Switching current owned identity

    @MainActor
    override func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        await super.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
        if #available(iOS 16, *) {
            children.compactMap({ $0 as? DiscussionsListViewController<PersistedDiscussion> }).forEach { discussionsViewController in
                Task { await discussionsViewController.switchCurrentOwnedCryptoId(to: newOwnedCryptoId) }
            }
        } else {
            children.compactMap({ $0 as? DiscussionsTableViewController }).forEach { discussionsTableViewController in
                Task { await discussionsTableViewController.switchCurrentOwnedCryptoId(to: newOwnedCryptoId) }
            }
        }
    }
}


// MARK: - View Controller Lifecycle

extension RecentDiscussionsViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        addAndConfigureDiscussionsTableViewController()
        observeUseOldListOfDiscussionsInterfaceInAppSettings()
        
        var rightBarButtonItems = [UIBarButtonItem]()

        if #available(iOS 14, *) {
            let ellipsisButton = getConfiguredEllipsisCircleRightBarButtonItem()
            rightBarButtonItems.append(ellipsisButton)
        } else {
            let ellipsisButton = getConfiguredEllipsisCircleRightBarButtonItem(selector: #selector(ellipsisButtonTappedSelector))
            rightBarButtonItems.append(ellipsisButton)
        }
        
        #if DEBUG
        rightBarButtonItems.append(UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(insertDebugMessagesInAllExistingDiscussions)))
        #endif

        navigationItem.rightBarButtonItems = rightBarButtonItems
    }
    
    
    private func observeUseOldListOfDiscussionsInterfaceInAppSettings() {
        ObvMessengerSettingsObservableObject.shared.$useOldListOfDiscussionsInterface
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                assert(Thread.isMainThread)
                self?.addAndConfigureDiscussionsTableViewController()
            }
            .store(in: &cancellables)
    }

    
    @available(iOS, introduced: 13.0, deprecated: 14.0, message: "Used because iOS 13 does not support UIMenu on UIBarButtonItem")
    @objc private func ellipsisButtonTappedSelector() {
        ellipsisButtonTapped(sourceBarButtonItem: navigationItem.rightBarButtonItem)
    }
    
    
    #if DEBUG
    @objc private func insertDebugMessagesInAllExistingDiscussions() {
        ObvMessengerInternalNotification.insertDebugMessagesInAllExistingDiscussions
            .postOnDispatchQueue()
    }
    #endif
    
    private func addAndConfigureDiscussionsTableViewController() {
        removePreviousChildViewControllerIfAny()

        let vc: UIViewController
        if #available(iOS 16.0, *), !ObvMessengerSettings.Interface.useOldListOfDiscussionsInterface {
            discussionsListCoordinator = DiscussionsListCoordinator(navigationController: navigationController,
                                                                    ownedCryptoId: currentOwnedCryptoId,
                                                                    parentVC: self,
                                                                    tableViewControllerPlaceholder: tableViewControllerPlaceholder,
                                                                    delegate: self)
            discussionsListCoordinator?.start()
        } else {
            let discussionsTVC = DiscussionsTableViewController(allowDeletion: true, withRefreshControl: true)
            discussionsTVC.delegate = self
            vc = discussionsTVC
            vc.view.translatesAutoresizingMaskIntoConstraints = false
            
            vc.willMove(toParent: self)
            self.addChild(vc)
            (vc as? DiscussionsTableViewController)?.setFetchRequestsAndImages(DiscussionsFetchRequests(ownedCryptoId: currentOwnedCryptoId).allRequestsAndImages)
            vc.didMove(toParent: self)
            
            self.tableViewControllerPlaceholder.addSubview(vc.view)
            self.tableViewControllerPlaceholder.pinAllSidesToSides(of: vc.view)
        }
    }
    
    
    private func removePreviousChildViewControllerIfAny() {
        guard let childViewController = children.first else { return }
        childViewController.view.removeFromSuperview()
        childViewController.willMove(toParent: nil)
        childViewController.removeFromParent()
        childViewController.didMove(toParent: nil)
    }
    
}


// MARK: - DiscussionsTableViewControllerDelegate

extension RecentDiscussionsViewController: DiscussionsTableViewControllerDelegate {
    
    func userDidSelect(persistedDiscussion discussion: PersistedDiscussion) {
        assert(Thread.current == Thread.main)
        assert(discussion.managedObjectContext == ObvStack.shared.viewContext)
        delegate?.userWantsToDisplay(persistedDiscussion: discussion)
    }
    
    func userDidDeselect(_ discussion: PersistedDiscussion) {}
    
    func userAskedToDeleteDiscussion(_ discussion: PersistedDiscussion, completionHandler: @escaping (Bool) -> Void) {
        delegate?.userWantsToDeleteDiscussion(discussion, completionHandler: completionHandler)
    }
    
    func userAskedToRefreshDiscussions(completionHandler: @escaping () -> Void) {
        delegate?.userAskedToRefreshDiscussions(completionHandler: completionHandler)
    }
}

// MARK: - CanScrollToTop

extension RecentDiscussionsViewController: CanScrollToTop {
    
    func scrollToTop() {
        children.forEach({ ($0 as? CanScrollToTop)?.scrollToTop() })
    }
}
