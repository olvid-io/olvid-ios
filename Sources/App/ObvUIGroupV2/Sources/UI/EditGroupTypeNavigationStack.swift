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
import ObvAppTypes
import ObvDesignSystem

public protocol EditGroupTypeNavigationStackActions: EditGroupTypeViewActionsForEdition, FullListOfGroupMembersViewActionsInEditAdminsMode {}

@MainActor
protocol EditGroupTypeNavigationStackNavigation {
    func userTappedOnTheCancelButtonOfTheEditGroupTypeNavigationStack(_ view: EditGroupTypeNavigationStack)
    func editGroupTypeNavigationStackShouldBeDismissed(_ view: EditGroupTypeNavigationStack)
    func editGroupTypeNavigationStackShouldBeDismissedAsGroupWasDisbanded(_ view: EditGroupTypeNavigationStack)
}


/// View presented when the user taps the "Group type" button in `SingleGroupV2MainView`.
///
/// This view manages the navigation flow for editing an **existing group's type** (not for creating new groups).
///
/// - **Standard Group Type:**
///   If the user selects the "Standard" group type and confirms, the view is dismissed immediately.
///
/// - **Controlled Group Type:**
///   If the user selects the "Controlled" group type, the view navigates to a subsequent screen for choosing group admins.
public struct EditGroupTypeNavigationStack: View {
    
    let groupIdentifier: ObvGroupV2Identifier
    let subDataSources: SubDataSources
    let actions: EditGroupTypeNavigationStackActions
    let navigation: EditGroupTypeNavigationStackNavigation
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
    
    @State private var navigateToFullListOfGroupMembersViewForAdminEdition: Bool = false
    @State private var selectedGroupType: ObvAppTypes.ObvGroupType?
    
    public struct SubDataSources {
        let fullListOfGroupMembersViewDataSource: any FullListOfGroupMembersViewDataSource
        let editGroupTypeViewDataSource: EditGroupTypeViewDataSource
        let fullListOfGroupMembersViewSubDataSources: FullListOfGroupMembersView.SubDataSources
        
        public init(fullListOfGroupMembersViewDataSource: any FullListOfGroupMembersViewDataSource,
                    editGroupTypeViewDataSource: EditGroupTypeViewDataSource,
                    fullListOfGroupMembersViewSubDataSources: FullListOfGroupMembersView.SubDataSources) {
            self.fullListOfGroupMembersViewDataSource = fullListOfGroupMembersViewDataSource
            self.editGroupTypeViewDataSource = editGroupTypeViewDataSource
            self.fullListOfGroupMembersViewSubDataSources = fullListOfGroupMembersViewSubDataSources
        }
    }

    private func cancelButtonTapped() {
        navigation.userTappedOnTheCancelButtonOfTheEditGroupTypeNavigationStack(self)
    }
    
    public var body: some View {
        NavigationStack {
            EditGroupTypeView(
                mode: .edition(groupIdentifier: groupIdentifier, navigation: self, actions: actions),
                dataSource: subDataSources.editGroupTypeViewDataSource)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ObvButtonWithCancelRole(action: cancelButtonTapped)
                }
            }
            .navigationDestination(isPresented: $navigateToFullListOfGroupMembersViewForAdminEdition) {
                FullListOfGroupMembersView(mode: .editAdmins(groupIdentifier: groupIdentifier,
                                                             selectedGroupType: selectedGroupType,
                                                             navigation: self,
                                                             actions: actions),
                                           dataSource: subDataSources.fullListOfGroupMembersViewDataSource,
                                           subDataSources: subDataSources.fullListOfGroupMembersViewSubDataSources,
                                           uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
            }
        }
    }
    
}


extension EditGroupTypeNavigationStack: EditGroupTypeViewNavigationDuringEdition {
    
    public func userChosedGroupTypeAndWantsToSelectAdmins(_ view: EditGroupTypeView, groupIdentifier: ObvTypes.ObvGroupV2Identifier, selectedGroupType: ObvAppTypes.ObvGroupType) {
        self.selectedGroupType = selectedGroupType
        switch selectedGroupType {
        case .standard:
            navigation.editGroupTypeNavigationStackShouldBeDismissed(self)
        case .managed:
            navigateToFullListOfGroupMembersViewForAdminEdition = true
        case .readOnly:
            navigateToFullListOfGroupMembersViewForAdminEdition = true
        case .advanced(isReadOnly: _, remoteDeleteAnythingPolicy: _):
            navigateToFullListOfGroupMembersViewForAdminEdition = true
        }
    }
    
    public func editGroupTypeViewShouldBeDismissed(_ view: EditGroupTypeView, groupIdentifier: ObvGroupV2Identifier) {
        navigation.editGroupTypeNavigationStackShouldBeDismissed(self)
    }
    
    public func userWantsToLeaveGroupFlowAsGroupWasDisbanded(_ view: EditGroupTypeView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        navigation.editGroupTypeNavigationStackShouldBeDismissedAsGroupWasDisbanded(self)
    }
    
    
}


extension EditGroupTypeNavigationStack: FullListOfGroupMembersViewNavigationDuringEdition {
    
    public func hudWasDismissedAfterSuccessfulGroupEdition(_ view: FullListOfGroupMembersView.InternalView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        navigation.editGroupTypeNavigationStackShouldBeDismissed(self)
    }
    
}
