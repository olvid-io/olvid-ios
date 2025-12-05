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

import UIKit
import SwiftUI
import ObvTypes
import ObvProfilePictureBarButtonItem
import ObvDesignSystem
import ObvOwnedIdentityChooser
import ObvCells


public final class ObvGroupsListViewController: UIHostingController<ObvGroupsListView> {
    
    private var itemToScrollToWrapper: ItemToScrollToWrapper?
    
    public init(currentOwnedCryptoId: ObvCryptoId,
                dataSource: ObvGroupsListViewDataSource,
                groupCellViewDataSource: ObvGroupCellViewDataSource,
                profilePictureBarButtonItemViewDataSource: ObvProfilePictureBarButtonItemViewDataSource,
                avatarViewDataSource: ObvAvatarViewDataSource,
                ownedIdentityChooserViewDataSource: OwnedIdentityChooserViewDataSource,
                navigation: any ObvGroupsListViewNavigation,
                actions: ObvGroupsListViewActions) {
        let itemToScrollToWrapper = ItemToScrollToWrapper()
        let rootView = ObvGroupsListView(
            currentOwnedCryptoId: currentOwnedCryptoId,
            dataSource: dataSource,
            groupCellViewDataSource: groupCellViewDataSource,
            profilePictureBarButtonItemViewDataSource: profilePictureBarButtonItemViewDataSource,
            avatarViewDataSource: avatarViewDataSource,
            ownedIdentityChooserViewDataSource: ownedIdentityChooserViewDataSource,
            actions: actions,
            navigation: navigation,
            itemToScrollToWrapper: itemToScrollToWrapper)
        super.init(rootView: rootView)
        self.itemToScrollToWrapper = itemToScrollToWrapper
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


// MARK: - Programmatic scroll

extension ObvGroupsListViewController {
    
    /// In production, use an `.objectIDOfDisplayedContactGroup` identifier.
    public func scrollToItem(_ item: ObvGroupCellViewModel.GroupIdentifier) {
        assert(itemToScrollToWrapper != nil)
        itemToScrollToWrapper?.itemToScrollTo = item
    }
    
    public func scrollToTop() {
        assert(itemToScrollToWrapper != nil)
        itemToScrollToWrapper?.scrollToTop = true
    }
    
}
