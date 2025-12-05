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

import SwiftUI
import ObvTypes
import ObvDesignSystem


@MainActor
protocol FullListOfGroupMembersInEditAdminsModeNavigationStackNavigation {
    func fullListOfGroupMembersInEditAdminsModeNavigationStackShouldBeDismissed(_ view: FullListOfGroupMembersInEditAdminsModeNavigationStack)
}

/// A navigation stack presented when the user taps the button to **edit the admins** of an existing group.
///
/// This view displays the full list of group members and allows the user to:
/// - Select or deselect members as admins.
/// - Confirm changes to update the group's admin roles.
///
/// **Usage Context:**
/// - Only used for **editing admin roles** in an existing group.
/// - Not used during group creation.
struct FullListOfGroupMembersInEditAdminsModeNavigationStack: View {

    let groupIdentifier: ObvGroupV2Identifier
    let subDataSources: SubDataSources
    let actions: any FullListOfGroupMembersViewActionsInEditAdminsMode
    let navigation: FullListOfGroupMembersInEditAdminsModeNavigationStackNavigation
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
    
    struct SubDataSources {
        let fullListOfGroupMembersViewDataSource: any FullListOfGroupMembersViewDataSource
        let fullListOfGroupMembersViewSubDataSources: FullListOfGroupMembersView.SubDataSources
    }
    
    
    private func cancelButtonTapped() {
        navigation.fullListOfGroupMembersInEditAdminsModeNavigationStackShouldBeDismissed(self)
    }
    
    var body: some View {
        NavigationStack {
            FullListOfGroupMembersView(mode: .editAdmins(groupIdentifier: groupIdentifier,
                                                         selectedGroupType: nil,
                                                         navigation: self,
                                                         actions: actions),
                                       dataSource: subDataSources.fullListOfGroupMembersViewDataSource,
                                       subDataSources: subDataSources.fullListOfGroupMembersViewSubDataSources,
                                       uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ObvButtonWithCancelRole(action: cancelButtonTapped)
                }
            }
        }
    }
    
}

extension FullListOfGroupMembersInEditAdminsModeNavigationStack: FullListOfGroupMembersViewNavigationDuringEdition {
    
    func hudWasDismissedAfterSuccessfulGroupEdition(_ view: FullListOfGroupMembersView.InternalView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        navigation.fullListOfGroupMembersInEditAdminsModeNavigationStackShouldBeDismissed(self)
    }
    
}
