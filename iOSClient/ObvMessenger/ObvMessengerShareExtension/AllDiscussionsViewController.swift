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
import CoreDataStack
import CoreData

final class AllDiscussionsViewController: UIViewController {
    
    private var observationTokens = [NSObjectProtocol]()

    // Delegates
    
    weak var delegate: AllDiscussionsViewControllerDelegate?
}

extension AllDiscussionsViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()

        addAndConfigureDiscussionsTableViewController()
    }
 
    
    private func addAndConfigureDiscussionsTableViewController() {

        let ownedIdentities: [PersistedObvOwnedIdentity]
        do {
            ownedIdentities = try PersistedObvOwnedIdentity.getAll(within: ObvStack.shared.viewContext)
        } catch {
            assertionFailure()
            return
        }
        
        guard ownedIdentities.count == 1 else {
            assertionFailure()
            return
        }
        
        let ownedCryptoId = ownedIdentities.first!.cryptoId
        
        let discussionsTVC = DiscussionsTableViewController(ownedCryptoId: ownedCryptoId,
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
        
        self.view.addSubview(discussionsTVC.view)
        self.view.pinAllSidesToSides(of: discussionsTVC.view)
    }
}


extension AllDiscussionsViewController: DiscussionsTableViewControllerDelegate {
    
    func userDidSelect(persistedDiscussion discussion: PersistedDiscussion) {
        delegate?.userDidSelect(discussion)
    }
    
    func userDidDeselect(_: PersistedDiscussion) {}
    
    func userAskedToDeleteDiscussion(_: PersistedDiscussion, completionHandler: @escaping (Bool) -> Void) {}
    
    func userAskedToRefreshDiscussions(completionHandler: @escaping () -> Void) {}
    
}
