/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvUICoreData
import UIKit


final class RecentDiscussionsViewController: ShowOwnedIdentityButtonUIViewController, ViewControllerWithEllipsisCircleRightBarButtonItem, OlvidMenuProvider, DiscussionsTableViewControllerDelegate {

    weak var delegate: RecentDiscussionsViewControllerDelegate?

    private var isPerformingRefreshDiscussionsAction = false
    
    // MARK: - Switching current owned identity

    @MainActor
    override func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        await super.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
        if #available(iOS 16, *) {
            children.compactMap({ $0 as? NewDiscussionsViewController }).forEach { discussionsViewController in
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
        
        var rightBarButtonItems = [UIBarButtonItem]()

        let ellipsisButton = getConfiguredEllipsisCircleRightBarButtonItem()
        rightBarButtonItems.append(ellipsisButton)
        
//        #if DEBUG
//        rightBarButtonItems.append(UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(insertDebugMessagesInAllExistingDiscussions)))
//        #endif

        navigationItem.rightBarButtonItems = rightBarButtonItems
    }
    

    #if DEBUG
    @objc private func insertDebugMessagesInAllExistingDiscussions() {
//        ObvMessengerInternalNotification.insertDebugMessagesInAllExistingDiscussions
//            .postOnDispatchQueue()
        ObvMessengerInternalNotification.betaUserWantsToDebugCoordinatorsQueue
            .postOnDispatchQueue()
    }
    #endif

    private func addAndConfigureDiscussionsTableViewController() {
        removePreviousChildViewControllerIfAny()

        let vc: UIViewController
        if #available(iOS 16.0, *) {
            let viewModel = NewDiscussionsViewController.ViewModel(ownedCryptoId: currentOwnedCryptoId)
            vc = NewDiscussionsViewController(viewModel: viewModel, delegate: self)
        } else {
            vc = DiscussionsTableViewController(allowDeletion: true, withRefreshControl: true)
            (vc as? DiscussionsTableViewController)?.delegate = self
            (vc as? DiscussionsTableViewController)?.setFetchRequestsAndImages(DiscussionsFetchRequests(ownedCryptoId: currentOwnedCryptoId).allRequestsAndImages)
        }
        
        vc.willMove(toParent: self)
        addChild(vc)
        vc.didMove(toParent: self)
        
        view.addSubview(vc.view)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            vc.view.topAnchor.constraint(equalTo: view.topAnchor),
            vc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

    }
    
    
    private func removePreviousChildViewControllerIfAny() {
        guard let childViewController = children.first else { return }
        childViewController.view.removeFromSuperview()
        childViewController.willMove(toParent: nil)
        childViewController.removeFromParent()
        childViewController.didMove(toParent: nil)
    }
    
}


// MARK: - DiscussionsTableViewControllerDelegate and NewDiscussionsViewControllerDelegate

@available(iOS 16.0, *)
extension RecentDiscussionsViewController: NewDiscussionsViewControllerDelegate {
    
    func userWantsToShowMapToConsultLocationSharedContinously(_ vc: NewDiscussionsViewController, ownedCryptoId: ObvCryptoId) async throws {
        try await delegate?.userWantsToShowMapToConsultLocationSharedContinously(self, ownedCryptoId: ownedCryptoId)
    }
        
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice(_ vc: NewDiscussionsViewController) async throws {
        try await delegate?.userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice(self)
    }
    
    
    func userWantsToSetupNewBackups() {
        delegate?.userWantsToSetupNewBackups(self)
    }
    
    func userWantsToDisplayBackupKey() {
        delegate?.userWantsToDisplayBackupKey(self)
    }

}


extension RecentDiscussionsViewController {

    func userAskedToDeleteDiscussion(_ discussion: PersistedDiscussion, completionHandler: @escaping (Bool) -> Void) {
        delegate?.userWantsToDeleteDiscussion(discussion, completionHandler: completionHandler)
    }
    
    func userAskedToRefreshDiscussions() async throws {
        try await delegate?.userAskedToRefreshDiscussions()
    }

    func userDidDeselect(_ discussion: PersistedDiscussion) {}

    func userDidSelect(persistedDiscussion discussion: PersistedDiscussion) {
        assert(Thread.current == Thread.main)
        assert(discussion.managedObjectContext == ObvStack.shared.viewContext)
        delegate?.userWantsToDisplay(persistedDiscussion: discussion)
    }
    
}


// MARK: - CanScrollToTop

extension RecentDiscussionsViewController: CanScrollToTop {
    
    func scrollToTop() {
        children.forEach({ ($0 as? CanScrollToTop)?.scrollToTop() })
    }
}


// MARK: - OlvidMenuProvider

extension RecentDiscussionsViewController {

    private struct Strings {
        static let toggleEditPinnedState = NSLocalizedString("TOGGLE_EDIT_PINNED_STATE", comment: "")
    }
    
    func provideMenu() -> UIMenu {
        
        // Update the parents menu
        var menuElements = [UIMenuElement]()
        if let parentMenu = parent?.getFirstMenuAvailable() {
            menuElements.append(contentsOf: parentMenu.children)
        }
        
        // Under iOS16+, discussions can be pinned.
        // We provide an action allowing to toggle edit mode
        
        if #available(iOS 16, *) {
            
            let togglePinAction = UIAction(title: Strings.toggleEditPinnedState, image: UIImage(systemIcon: .pinFill)) { [weak self] _ in
                guard let self else { return }
                guard let vc = self.children.compactMap({ $0 as? NewDiscussionsViewController }).first else { assertionFailure(); return }
                vc.toggleIsReordering()
            }
            
            menuElements.append(togglePinAction)

            // Under macOS, add an action allowing to refresh the messages
            
            if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
                
                let refreshDiscussionsAction = UIAction(title: String(localized: "ACTION_TITLE_FETCH_NEW_MESSAGES")) { [weak self] _ in
                    Task { [weak self] in await self?.performRefreshDiscussionsAction() }
                }
                
                menuElements.append(refreshDiscussionsAction)

            }
            
            
        }

        let menu = UIMenu(title: "", children: menuElements)
        return menu
    }
    
}


// MARK: - Refreshing discussions under macOS

extension RecentDiscussionsViewController {
    
    @MainActor
    private func performRefreshDiscussionsAction() async {
        
        // Never refresh twice at the same time
        
        guard !isPerformingRefreshDiscussionsAction else { return }
        isPerformingRefreshDiscussionsAction = true
        defer { isPerformingRefreshDiscussionsAction = false }

        addSpinnerToRightBarButtonItems()

        do {
            
            let actionDate = Date()
                        
            try await delegate?.userAskedToRefreshDiscussions()
            
            let elapsedTime = Date.now.timeIntervalSince(actionDate)
            try? await Task.sleep(seconds: max(0, 1.0 - elapsedTime)) // Spin for at least 1 second
            
        } catch {
            assertionFailure()
            // In production, continue any
        }
            
        removeSpinnerFromRightBarButtonItems()
        
    }
    
    
    private func addSpinnerToRightBarButtonItems() {
        
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.hidesWhenStopped = true
        spinner.startAnimating()

        var currentRightBarButtonItems = navigationItem.rightBarButtonItems ?? []
        currentRightBarButtonItems.append(.init(customView: spinner))
        navigationItem.rightBarButtonItems = currentRightBarButtonItems
        
    }
    
    
    private func removeSpinnerFromRightBarButtonItems() {
        
        var currentRightBarButtonItems = navigationItem.rightBarButtonItems
        currentRightBarButtonItems?.removeAll(where: { $0.customView is UIActivityIndicatorView })
        navigationItem.rightBarButtonItems = currentRightBarButtonItems
        
    }
    
}
