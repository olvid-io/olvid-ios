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
  
import CoreData
import Foundation
import ObvUI
import ObvTypes
import SwiftUI


@available(iOS 16.0, *)
struct DiscussionsListView: UIViewControllerRepresentable {
    typealias UIViewControllerType = DiscussionsListViewController<PersistedDiscussion>
    
    private let viewModel: DiscussionsListViewModel
    
    init(ownedCryptoId: ObvCryptoId, discussionsViewModel: DiscussionsViewModel) {
        self.viewModel = DiscussionsListViewModel(ownedCryptoId: ownedCryptoId, discussionsViewModel: discussionsViewModel)
    }
    
    func makeUIViewController(context: Context) -> UIViewControllerType {
        let frcsCreationClosure = { (ownedCryptoId: ObvCryptoId) -> DiscussionsListViewControllerViewModel.Frcs in
            let frcForNonEmpty = PersistedDiscussion.getFetchRequestForNonEmptyRecentDiscussionsForOwnedIdentity(with: ownedCryptoId)
            let frcForAllActive = PersistedOneToOneDiscussion.getFetchRequestForAllActiveOneToOneDiscussionsSortedByTitleForOwnedIdentity(with: ownedCryptoId)
            let forAllGroup = PersistedGroupDiscussion.getFetchRequestForAllGroupDiscussionsSortedByTitleForOwnedIdentity(with: ownedCryptoId)
            
            return DiscussionsListViewControllerViewModel.Frcs(frcForNonEmpty: frcForNonEmpty,
                                                               frcForAllActive: frcForAllActive,
                                                               frcForAllGroup: forAllGroup)
        }
        let selectedObjectIds = viewModel.selectedObjectIds
        
        let vcViewModel = DiscussionsListViewControllerViewModel<PersistedDiscussion>(
            frcCreationClosure: frcsCreationClosure,
            cryptoId: viewModel.ownedCryptoId,
            context: ObvStack.shared.viewContext,
            coordinator: nil,
            discussionsListCellType: .short,
            selectedObjectIds: selectedObjectIds,
            withRefreshControl: false,
            startInEditMode: true)
        
        let vc = DiscussionsListViewController<PersistedDiscussion>(viewModel: vcViewModel)
        viewModel.listenToSelectedDiscussions(on: vc)
        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
        // Updates the state of the specified view controller with new information from SwiftUI.
    }
}

@available(iOS 16.0, *)
extension PersistedDiscussion: DiscussionsListViewControllerPersistedObjectRetrieving {}
