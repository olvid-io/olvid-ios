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
import CoreData
import Foundation
import ObvTypes
import ObvUICoreData
import ObvUI


@available(iOS 16.0, *)
final class DiscussionsListViewModel {

    private var selectedDiscussionsListener: AnyCancellable?
    var discussionsViewModel: DiscussionsViewModel
    var ownedCryptoId: ObvCryptoId
    
    var selectedObjectIds: [ObvUICoreData.TypeSafeManagedObjectID<PersistedDiscussion>] {
        return discussionsViewModel.selectedDiscussions.map({ ObvUICoreData.TypeSafeManagedObjectID(objectID: ($0.discussionUI as PersistedDiscussion).objectID) })
    }
    
    init(ownedCryptoId: ObvCryptoId, discussionsViewModel: DiscussionsViewModel) {
        self.ownedCryptoId = ownedCryptoId
        self.discussionsViewModel = discussionsViewModel
    }
    
    func listenToSelectedDiscussions(on vc: DiscussionsListViewController<PersistedDiscussion>) {
        selectedDiscussionsListener = vc.selectionViewController.$selectedDiscussions.map({ (val) -> [DiscussionViewModel] in
            let discussionViewModels: [DiscussionViewModel] = val
                .compactMap({ PersistedDiscussion.create(from: $0) as? PersistedDiscussionUI })
                .map({ DiscussionViewModel(discussionUI: $0, selected: true) })
            return discussionViewModels
        }).sink(receiveValue: { [weak self] val in
            self?.discussionsViewModel.discussions.forEach({ discussion in
                discussion.selected = val.contains(where: { $0.discussionUI == discussion.discussionUI })
            })
        })
    }
}

private extension PersistedDiscussion {
    static func create(from viewModel: DiscussionsListSelectionCellViewModel) -> PersistedDiscussion? {
        return try? PersistedDiscussion.get(objectID: viewModel.objectId, within: ObvStack.shared.viewContext)
    }
}
