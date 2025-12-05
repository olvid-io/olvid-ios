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
import ObvAppTypes
import ObvUIGroupSharedBetweenV1AndV2
import ObvDesignSystem


public final class FullListOfGroupMembersViewController: UIHostingController<FullListOfGroupMembersView> {
    
    private let mode: FullListOfGroupMembersView.Mode
    
    public init(mode: FullListOfGroupMembersView.Mode,
                dataSource: any FullListOfGroupMembersViewDataSource,
                subDataSources: FullListOfGroupMembersView.SubDataSources,
                uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet) {
        self.mode = mode
        let rootView = FullListOfGroupMembersView(mode: mode,
                                                  dataSource: dataSource,
                                                  subDataSources: subDataSources,
                                                  uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
        super.init(rootView: rootView)
    }
    
    var groupIdentifier: ObvGroupV2Identifier? {
        switch mode {
        case .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _, navigation: _, actions: _),
                .administrateAdmins(groupIdentifier: let groupIdentifier, actions: _, navigation: _):
            return groupIdentifier
        case .selectAdminsDuringGroupCreation:
            return nil
        }
    }

    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
