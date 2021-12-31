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
import os.log
import ObvEngine


class RecentDiscussionsViewController: ShowOwnedIdentityButtonUIViewController, ViewControllerWithEllipsisCircleRightBarButtonItem {

    @IBOutlet weak var tableViewControllerPlaceholder: UIView!
    private var discussionsTVC: DiscussionsTableViewController!

    weak var delegate: RecentDiscussionsViewControllerDelegate?
        
}


// MARK: - View Controller Lifecycle

extension RecentDiscussionsViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        addAndConfigureDiscussionsTableViewController()
        title = CommonString.Word.Discussions
        
        var rightBarButtonItems = [UIBarButtonItem]()

        if #available(iOS 14, *) {
            let ellipsisButton = getConfiguredEllipsisCircleRightBarButtonItem()
            rightBarButtonItems.append(ellipsisButton)
        } else if #available(iOS 13.0, *) {
            let ellipsisButton = getConfiguredEllipsisCircleRightBarButtonItem(selector: #selector(ellipsisButtonTappedSelector))
            rightBarButtonItems.append(ellipsisButton)
        }
        
        #if DEBUG
        rightBarButtonItems.append(UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(insertDebugMessagesInAllExistingDiscussions)))
        #endif

        navigationItem.rightBarButtonItems = rightBarButtonItems

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
        
        discussionsTVC = DiscussionsTableViewController(ownedCryptoId: ownedCryptoId,
                                                        allowDeletion: true,
                                                        withRefreshControl: true)
        if #available(iOS 13.0, *) {
            discussionsTVC.setFetchRequestsAndImages([
                (PersistedDiscussion.getFetchRequestForNonEmptyRecentDiscussionsForOwnedIdentity(with: ownedCryptoId), UIImage(systemName: "clock")!),
                (PersistedOneToOneDiscussion.getFetchRequestForAllOneToOneDiscussionsSortedByTitleForOwnedIdentity(with: ownedCryptoId), UIImage(systemName: "person")!),
                (PersistedGroupDiscussion.getFetchRequestForAllGroupDiscussionsSortedByTitleForOwnedIdentity(with: ownedCryptoId), UIImage(systemName: "person.3")!),
            ])
        } else {
            discussionsTVC.setFetchRequestsAndTitles([
                (PersistedDiscussion.getFetchRequestForNonEmptyRecentDiscussionsForOwnedIdentity(with: ownedCryptoId), DiscussionsTableViewController.Strings.latestDiscussions),
                (PersistedOneToOneDiscussion.getFetchRequestForAllOneToOneDiscussionsSortedByTitleForOwnedIdentity(with: ownedCryptoId), CommonString.Word.Contacts),
                (PersistedGroupDiscussion.getFetchRequestForAllGroupDiscussionsSortedByTitleForOwnedIdentity(with: ownedCryptoId), CommonString.Word.Groups),
            ])

        }

        discussionsTVC.view.translatesAutoresizingMaskIntoConstraints = false
        discussionsTVC.delegate = self
        
        discussionsTVC.willMove(toParent: self)
        self.addChild(discussionsTVC)
        discussionsTVC.didMove(toParent: self)
        
        self.tableViewControllerPlaceholder.addSubview(discussionsTVC.view)
        self.tableViewControllerPlaceholder.pinAllSidesToSides(of: discussionsTVC.view)
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
        guard self.discussionsTVC.tableView.numberOfRows(inSection: self.discussionsTVC.tableView.numberOfSections-1) > 0 else { return }
        self.discussionsTVC.tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
    }
    
}
