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
  
import Combine
import CoreData
import Foundation
import ObvTypes
import ObvUICoreData
import ObvUI


@available(iOS 16.0, *)
final class NewDiscussionsListViewModel: NewDiscussionsSelectionViewControllerDelegate {

    let discussionsViewModel: DiscussionsViewModel
    let ownedCryptoId: ObvCryptoId
    let restrictToActiveDiscussions: Bool
    
    var selectedObjectIds: [ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>] {
        return discussionsViewModel.selectedDiscussions.map({ ObvUICoreData.TypeSafeManagedObjectID(objectID: $0.persistedDiscussion.objectID) })
    }
    
    init(ownedCryptoId: ObvCryptoId, restrictToActiveDiscussions: Bool, discussionsViewModel: DiscussionsViewModel) {
        self.ownedCryptoId = ownedCryptoId
        self.discussionsViewModel = discussionsViewModel
        self.restrictToActiveDiscussions = restrictToActiveDiscussions
    }
    
    // MARK: - NewDiscussionsSelectionViewControllerDelegate
    
    func userAcceptedlistOfSelectedDiscussions(_ listOfSelectedDiscussions: [TypeSafeManagedObjectID<PersistedDiscussion>], in newDiscussionsSelectionViewController: UIViewController) {
        discussionsViewModel.discussions.forEach { discussion in
            discussion.selected = listOfSelectedDiscussions.contains(where: { $0 == discussion.persistedDiscussion.typedObjectID })
        }
        newDiscussionsSelectionViewController.dismiss(animated: true)
    }
    
}



@available(iOS 15.0, *)
final class DiscussionsListViewModel: DiscussionsSelectionViewControllerDelegate {
        
    let discussionsViewModel: DiscussionsViewModel
    let ownedCryptoId: ObvCryptoId

    init(ownedCryptoId: ObvCryptoId, discussionsViewModel: DiscussionsViewModel) {
        self.ownedCryptoId = ownedCryptoId
        self.discussionsViewModel = discussionsViewModel
    }

    var preselectedDiscussions: Set<ObvManagedObjectPermanentID<PersistedDiscussion>> {
        return Set(discussionsViewModel.selectedDiscussions.map({ $0.persistedDiscussion.discussionPermanentID }))
    }
    
    // MARK: - DiscussionsSelectionViewControllerDelegate
    
    func userAcceptedlistOfSelectedDiscussions(_ listOfSelectedDiscussions: Set<ObvManagedObjectPermanentID<PersistedDiscussion>>, in discussionsSelectionViewController: UIViewController) {
        discussionsViewModel.discussions.forEach { discussion in
            discussion.selected = listOfSelectedDiscussions.contains(where: { $0 == discussion.persistedDiscussion.discussionPermanentID })
        }
        discussionsSelectionViewController.dismiss(animated: true)
    }
}
