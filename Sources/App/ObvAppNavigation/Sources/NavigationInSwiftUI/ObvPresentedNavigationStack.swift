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
import ObvUIGroupV1
import ObvUIGroupV2
import ObvUIGroupSharedBetweenV1AndV2
import ObvDesignSystem
import ObvSingleContact
import ObvCells


@MainActor
public protocol ObvPresentedNavigationStackActions: SingleGroupV1MainViewActionsProtocol, ListOfMembersWithAddAndRemoveButtonsViewActions, ListOfMembersWithSegmentedControlViewActions, OnetoOneInvitableGroupMembersViewActionsProtocol, SingleGroupV2MainViewActionsProtocol, ObvSingleContactViewActions, ObvListOfContactDevicesViewActions {
    
}

/// Most of the navigation can be handled by the `ObvPresentedNavigationStack`. Certain views are still managed by the app itself. For those we forward the navigation calls to our delegate.
@MainActor
public protocol ObvPresentedNavigationStackNavigation {
    
    func userWantsToNavigateToOneToOneDiscussionWithContact(_ view: ObvPresentedNavigationStack, contactIdentifier: ObvTypes.ObvContactIdentifier) throws
    func userWantsToNavigateToGroupDiscussion(_ view: ObvPresentedNavigationStack, groupIdentifier: ObvAppTypes.ObvGroupIdentifier)
    
    func userWantsToCallContact(_ view: ObvPresentedNavigationStack, contactIdentifier: ObvTypes.ObvContactIdentifier)
    func userWantsToCall(_ view: ObvPresentedNavigationStack, groupIdentifier: ObvAppTypes.ObvGroupIdentifier)

    func userWantsToEditContactNicknameAndCustomPicture(_ view: ObvPresentedNavigationStack, contactIdentifier: ObvTypes.ObvContactIdentifier)
    func userWantsToEditGroupNicknameAndCustomPicture(_ view: ObvPresentedNavigationStack, groupIdentifier: ObvAppTypes.ObvGroupIdentifier)
    
    func userWantsToIntroduceOneContactToAnother(_ view: ObvPresentedNavigationStack, contactIdentifier: ObvTypes.ObvContactIdentifier) throws
    func userWantsToCreateNewGroupWithContact(_ view: ObvPresentedNavigationStack, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws
    
    func userWantsToCloneGroup(_ view: ObvPresentedNavigationStack, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) async throws
    
    func userWantsToDismissPresentedNavigationStack(_ view: ObvPresentedNavigationStack)

}

/// A navigation stack presented modally when the user initiates an action requiring detailed information.
///
/// This view is used to display a navigation stack starting with one of the following detailed views:
/// - **Contact Detail View**: Shows comprehensive information about a specific contact.
/// - **Group v1 Detail View**: Displays details for a group using the v1 group model.
/// - **Group v2 Detail View**: Displays details for a group using the v2 group model.
///
/// The navigation stack allows users to navigate through related subviews (e.g., editing contact/group details, or managing group members).
///
/// # Usage
/// `ObvPresentedNavigationStack` is presented in scenarios such as:
/// - When the user taps the title of a discussion.
public struct ObvPresentedNavigationStack: View {

    let root: NavigationStackRootView
    let dataSources: DataSources
    let actions: any ObvPresentedNavigationStackActions
    let navigation: any ObvPresentedNavigationStackNavigation
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
    
    public enum NavigationStackRootView: Equatable {
        case contactDetails(contactIdentifier: ObvContactIdentifier)
        case groupV1Details(groupV1Identifier: ObvGroupV1Identifier)
        case groupV2Details(groupV2Identifier: ObvGroupV2Identifier)
    }
    
    public struct DataSources {
        let singleGroupV1MainViewDataSource: any SingleGroupV1MainViewDataSource
        let singleGroupV2MainViewDataSource: any SingleGroupV2MainViewDataSource
        let onetoOneInvitableGroupMembersViewDataSource: any OnetoOneInvitableGroupMembersViewDataSource
        let onetoOneInvitableGroupMembersViewCellDataSource: any OnetoOneInvitableGroupMembersViewCellDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        let fullListOfGroupMembersViewDataSource: any FullListOfGroupMembersViewDataSource
        let listOfContactDevicesViewDataSource: any ObvListOfContactDevicesViewDataSource
        let trustOriginsListViewDataSource: any ObvTrustOriginsListViewDataSource
        let listOfMembersWithAddAndRemoveButtonsViewDataSources: ListOfMembersWithAddAndRemoveButtonsView.DataSources
        let listOfMembersWithSegmentedControlViewDataSources: ListOfMembersWithSegmentedControlView.DataSources
        let singleGroupV2MainViewSubDataSources: SingleGroupV2MainView.SubDataSources
        let fullListOfGroupMembersViewSubDataSources: FullListOfGroupMembersView.SubDataSources
        let singleContactViewDataSources: ObvSingleContactView.DataSources
        let listOfCommonGroupsWithContactViewDataSources: ObvListOfCommonGroupsWithContactView.DataSources
        let singleGroupV1MainViewDataSources: SingleGroupV1MainView.DataSources
        
        public init(singleGroupV1MainViewDataSource: any SingleGroupV1MainViewDataSource,
             singleGroupV2MainViewDataSource: any SingleGroupV2MainViewDataSource,
             onetoOneInvitableGroupMembersViewDataSource: any OnetoOneInvitableGroupMembersViewDataSource,
             onetoOneInvitableGroupMembersViewCellDataSource: any OnetoOneInvitableGroupMembersViewCellDataSource,
             avatarViewDataSource: any ObvAvatarViewDataSource,
             fullListOfGroupMembersViewDataSource: any FullListOfGroupMembersViewDataSource,
             listOfContactDevicesViewDataSource: any ObvListOfContactDevicesViewDataSource,
             trustOriginsListViewDataSource: any ObvTrustOriginsListViewDataSource,
             listOfMembersWithAddAndRemoveButtonsViewDataSources: ListOfMembersWithAddAndRemoveButtonsView.DataSources,
             listOfMembersWithSegmentedControlViewDataSources: ListOfMembersWithSegmentedControlView.DataSources,
             singleGroupV2MainViewSubDataSources: SingleGroupV2MainView.SubDataSources,
             fullListOfGroupMembersViewSubDataSources: FullListOfGroupMembersView.SubDataSources,
             singleContactViewDataSources: ObvSingleContactView.DataSources,
             listOfCommonGroupsWithContactViewDataSources: ObvListOfCommonGroupsWithContactView.DataSources,
             singleGroupV1MainViewDataSources: SingleGroupV1MainView.DataSources) {
            self.singleGroupV1MainViewDataSource = singleGroupV1MainViewDataSource
            self.singleGroupV2MainViewDataSource = singleGroupV2MainViewDataSource
            self.onetoOneInvitableGroupMembersViewDataSource = onetoOneInvitableGroupMembersViewDataSource
            self.onetoOneInvitableGroupMembersViewCellDataSource = onetoOneInvitableGroupMembersViewCellDataSource
            self.avatarViewDataSource = avatarViewDataSource
            self.fullListOfGroupMembersViewDataSource = fullListOfGroupMembersViewDataSource
            self.listOfContactDevicesViewDataSource = listOfContactDevicesViewDataSource
            self.trustOriginsListViewDataSource = trustOriginsListViewDataSource
            self.listOfMembersWithAddAndRemoveButtonsViewDataSources = listOfMembersWithAddAndRemoveButtonsViewDataSources
            self.listOfMembersWithSegmentedControlViewDataSources = listOfMembersWithSegmentedControlViewDataSources
            self.singleGroupV2MainViewSubDataSources = singleGroupV2MainViewSubDataSources
            self.fullListOfGroupMembersViewSubDataSources = fullListOfGroupMembersViewSubDataSources
            self.singleContactViewDataSources = singleContactViewDataSources
            self.listOfCommonGroupsWithContactViewDataSources = listOfCommonGroupsWithContactViewDataSources
            self.singleGroupV1MainViewDataSources = singleGroupV1MainViewDataSources
        }
        
    }
    
    @State private var path = [Route]()
    
    fileprivate enum Route: Hashable {
        case contactDetails(contactIdentifier: ObvContactIdentifier)
        case groupDetails(groupIdentifier: ObvGroupIdentifier)
        case listOfMembersWithAddAndRemoveButtons(groupIdentifier: ObvGroupIdentifier)
        case listOfMembersWithSegmentedControl(groupIdentifier: ObvGroupIdentifier)
        case onetoOneInvitableGroupMembers(groupIdentifier: ObvGroupIdentifier)
        case fullListOfGroupMembersInEditAdminsMode(groupV2Identifier: ObvGroupV2Identifier)
        case listOfContactDevices(contactIdentifier: ObvContactIdentifier)
        case listOfTrustOrigins(contactIdentifier: ObvContactIdentifier)
        case listOfCommonGroupsWithContact(contactIdentifier: ObvContactIdentifier)
    }
    
    
    private func userWantsToDismissPresentedNavigationStack() {
        navigation.userWantsToDismissPresentedNavigationStack(self)
    }
    

    public var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch root {
                case .contactDetails(contactIdentifier: let contactIdentifier):
                    ObvSingleContactView(
                        contactIdentifier: contactIdentifier,
                        dataSources: dataSources.singleContactViewDataSources,
                        actions: actions,
                        navigation: self,
                        uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                case .groupV1Details(groupV1Identifier: let groupV1Identifier):
                    SingleGroupV1MainView(
                        groupIdentifier: groupV1Identifier,
                        dataSources: dataSources.singleGroupV1MainViewDataSources,
                        actions: actions,
                        navigation: self,
                        uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                case .groupV2Details(groupV2Identifier: let groupV2Identifier):
                    SingleGroupV2MainView(
                        groupIdentifier: groupV2Identifier,
                        dataSource: dataSources.singleGroupV2MainViewDataSource,
                        subDataSources: dataSources.singleGroupV2MainViewSubDataSources,
                        actions: actions,
                        navigation: self,
                        uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .contactDetails(contactIdentifier: let contactIdentifier):
                    ObvSingleContactView(
                        contactIdentifier: contactIdentifier,
                        dataSources: dataSources.singleContactViewDataSources,
                        actions: actions,
                        navigation: self,
                        uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                case .listOfMembersWithAddAndRemoveButtons(groupIdentifier: let groupIdentifier):
                    ListOfMembersWithAddAndRemoveButtonsView(
                        groupIdentifier: groupIdentifier,
                        dataSources: dataSources.listOfMembersWithAddAndRemoveButtonsViewDataSources,
                        actions: actions,
                        navigation: self,
                        uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                case .listOfMembersWithSegmentedControl(groupIdentifier: let groupIdentifier):
                    ListOfMembersWithSegmentedControlView(
                        groupIdentifier: groupIdentifier,
                        dataSources: dataSources.listOfMembersWithSegmentedControlViewDataSources,
                        actions: actions,
                        navigation: self)
                case .onetoOneInvitableGroupMembers(groupIdentifier: let groupIdentifier):
                    OnetoOneInvitableGroupMembersView(
                        groupIdentifier: groupIdentifier,
                        dataSource: dataSources.onetoOneInvitableGroupMembersViewDataSource,
                        onetoOneInvitableGroupMembersViewCellDataSource: dataSources.onetoOneInvitableGroupMembersViewCellDataSource,
                        avatarViewDataSource: dataSources.avatarViewDataSource,
                        actions: actions)
                case .fullListOfGroupMembersInEditAdminsMode(groupV2Identifier: let groupV2Identifier):
                    FullListOfGroupMembersView(
                        mode: .editAdmins(groupIdentifier: groupV2Identifier,
                                          selectedGroupType: nil,
                                          navigation: self,
                                          actions: actions),
                        dataSource: dataSources.fullListOfGroupMembersViewDataSource,
                        subDataSources: dataSources.fullListOfGroupMembersViewSubDataSources,
                        uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                case .listOfContactDevices(contactIdentifier: let contactIdentifier):
                    ObvListOfContactDevicesView(
                        contactIdentifier: contactIdentifier,
                        dataSource: dataSources.listOfContactDevicesViewDataSource,
                        actions: actions)
                case .listOfTrustOrigins(contactIdentifier: let contactIdentifier):
                    ObvTrustOriginsListView(
                        contactIdentifier: contactIdentifier,
                        dataSource: dataSources.trustOriginsListViewDataSource)
                case .listOfCommonGroupsWithContact(contactIdentifier: let contactIdentifier):
                    ObvListOfCommonGroupsWithContactView(
                        contactIdentifier: contactIdentifier,
                        dataSources: dataSources.listOfCommonGroupsWithContactViewDataSources,
                        navigation: self)
                case .groupDetails(groupIdentifier: let groupIdentifier):
                    switch groupIdentifier {
                    case .groupV1(let groupV1Identifier):
                        SingleGroupV1MainView(
                            groupIdentifier: groupV1Identifier,
                            dataSources: dataSources.singleGroupV1MainViewDataSources,
                            actions: actions,
                            navigation: self,
                            uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                    case .groupV2(let groupV2Identifier):
                        SingleGroupV2MainView(
                            groupIdentifier: groupV2Identifier,
                            dataSource: dataSources.singleGroupV2MainViewDataSource,
                            subDataSources: dataSources.singleGroupV2MainViewSubDataSources,
                            actions: actions,
                            navigation: self,
                            uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ObvButtonWithCancelRole(action: userWantsToDismissPresentedNavigationStack)
                }
            }
        }
    }
    
}


extension ObvPresentedNavigationStack: SingleGroupV1MainViewNavigation {
    
    public func userWantsToChat(_ view: ObvUIGroupV1.SingleGroupV1MainView, groupIdentifier: ObvTypes.ObvGroupV1Identifier) async {
        navigation.userWantsToNavigateToGroupDiscussion(self, groupIdentifier: .groupV1(groupIdentifier))
    }
    
    public func userWantsToCall(_ view: ObvUIGroupV1.SingleGroupV1MainView, groupIdentifier: ObvTypes.ObvGroupV1Identifier) {
        navigation.userWantsToCall(self, groupIdentifier: .groupV1(groupIdentifier))
    }
    
    public func userWantsToLeaveGroupFlow(_ view: ObvUIGroupV1.SingleGroupV1MainView) {
        // We do nothing
    }
    
    public func userWantsToEditGroupNicknameAndCustomPicture(_ view: ObvUIGroupV1.SingleGroupV1MainView, groupIdentifier: ObvTypes.ObvGroupV1Identifier) {
        navigation.userWantsToEditGroupNicknameAndCustomPicture(self, groupIdentifier: .groupV1(groupIdentifier))
    }
    
    public func userWantsToCloneGroup(_ view: ObvUIGroupV1.SingleGroupV1MainView, groupIdentifier: ObvTypes.ObvGroupV1Identifier) async throws {
        try await navigation.userWantsToCloneGroup(self, groupIdentifier: .groupV1(groupIdentifier))
    }
    
    
    public func userWantsToNavigateToViewAllowingToModifyMembers(_ view: ObvUIGroupV1.SingleGroupV1MainView, groupIdentifier: ObvTypes.ObvGroupV1Identifier) async {
        path.append(Route.listOfMembersWithAddAndRemoveButtons(groupIdentifier: .groupV1(groupIdentifier)))
    }
    
    public func userWantsToNavigateToFullListOfOtherGroupMembers(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) async {
        path.append(Route.listOfMembersWithSegmentedControl(groupIdentifier: groupIdentifier))
    }
    
    public func userWantsToNavigateToViewAllowingToSelectGroupMembersToInviteToOneToOne(_ view: ObvUIGroupSharedBetweenV1AndV2.OneToOneInvitableView.InternalView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {
        path.append(Route.onetoOneInvitableGroupMembers(groupIdentifier: groupIdentifier))
    }
    
    
}


extension ObvPresentedNavigationStack: SingleGroupV2MainViewNavigation {
        
    public func userWantsToNavigateToViewAllowingToModifyMembers(_ view: GroupAdministrationView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        path.append(Route.listOfMembersWithAddAndRemoveButtons(groupIdentifier: .groupV2(groupIdentifier)))
    }
    
    public func userWantsToNavigateToViewAllowingToManageAdmins(_ view: GroupAdministrationView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        path.append(Route.fullListOfGroupMembersInEditAdminsMode(groupV2Identifier: groupIdentifier))
    }
    
    public func userWantsToChat(_ view: ObvUIGroupV2.SingleGroupV2MainView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        navigation.userWantsToNavigateToGroupDiscussion(self, groupIdentifier: .groupV2(groupIdentifier))
    }
    
    public func userWantsToCall(_ view: ObvUIGroupV2.SingleGroupV2MainView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        navigation.userWantsToCall(self, groupIdentifier: .groupV2(groupIdentifier))
    }
    
    public func userWantsToLeaveGroupFlow(_ view: ObvUIGroupV2.SingleGroupV2MainView) {
        // We do nothing
    }
    
    public func userWantsToEditGroupNicknameAndCustomPicture(_ view: ObvUIGroupV2.SingleGroupV2MainView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        navigation.userWantsToEditGroupNicknameAndCustomPicture(self, groupIdentifier: .groupV2(groupIdentifier))
    }
    
    public func userWantsToCloneGroup(_ view: ObvUIGroupV2.SingleGroupV2MainView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws {
        try await navigation.userWantsToCloneGroup(self, groupIdentifier: .groupV2(groupIdentifier))
    }

}


extension ObvPresentedNavigationStack: FullListOfGroupMembersViewNavigationDuringEdition {
    
    public func hudWasDismissedAfterSuccessfulGroupEdition(_ view: FullListOfGroupMembersView.InternalView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
        // Nothing to do in particular
    }

}


extension ObvPresentedNavigationStack: SingleGroupMemberViewNavigation {
    public func userWantsToShowOtherUserProfile(_ view: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.InternalView, contactIdentifier: ObvTypes.ObvContactIdentifier) async {
        if let index = path.firstIndex(where: { $0 == .contactDetails(contactIdentifier: contactIdentifier) }) {
            path = [Route](path.prefix(index+1))
        } else {
            if root == .contactDetails(contactIdentifier: contactIdentifier) {
                path.removeAll()
            } else {
                path.append(Route.contactDetails(contactIdentifier: contactIdentifier))
            }
        }
    }
}


extension ObvPresentedNavigationStack: ListOfMembersWithAddAndRemoveButtonsViewNavigation {
    // Other protocol conformances are enough
}

extension ObvPresentedNavigationStack: ListOfMembersWithSegmentedControlViewNavigation {
    // Other protocol conformances are enough
}


extension ObvPresentedNavigationStack: ObvSingleContactViewNavigation {
    
    public func userWantsToNavigateToListOfContactDevices(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        path.append(Route.listOfContactDevices(contactIdentifier: contactIdentifier))
    }
    
    public func userWantsToNavigateToListOfTrustOrigins(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        path.append(Route.listOfTrustOrigins(contactIdentifier: contactIdentifier))
    }
    
    public func userWantsToNavigateToOneToOneDiscussionWithContact(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        try navigation.userWantsToNavigateToOneToOneDiscussionWithContact(self, contactIdentifier: contactIdentifier)
    }
    
    public func userWantsToIntroduceOneContactToAnother(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        try navigation.userWantsToIntroduceOneContactToAnother(self, contactIdentifier: contactIdentifier)
    }
    
    public func userWantsToCallContact(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) {
        navigation.userWantsToCallContact(self, contactIdentifier: contactIdentifier)
    }
    
    public func userWantsToNavigateToListOfCommonGroupsWithContact(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        path.append(Route.listOfCommonGroupsWithContact(contactIdentifier: contactIdentifier))
    }
    
    public func userWantsToCreateNewGroupWithContact(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        try await navigation.userWantsToCreateNewGroupWithContact(self, contactIdentifier: contactIdentifier)
    }
    
    public func userWantsToEditContactNicknameAndCustomPicture(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) {
        navigation.userWantsToEditContactNicknameAndCustomPicture(self, contactIdentifier: contactIdentifier)
    }
    
}

extension ObvPresentedNavigationStack: ObvGroupCellViewNavigation {
    
    public func userDidPressOnObvGroupCellView(_ view: ObvCells.ObvGroupCellView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, expectedNavigation: ObvCells.ObvGroupCellView.ExpectedNavigation) throws {
        switch expectedNavigation {
        case .groupDiscussion:
            navigation.userWantsToNavigateToGroupDiscussion(self, groupIdentifier: groupIdentifier)
        case .groupDetails:
            if let index = path.firstIndex(where: { $0 == .groupDetails(groupIdentifier: groupIdentifier) }) {
                path = [Route](path.prefix(index+1))
            } else {
                switch groupIdentifier {
                case .groupV1(let groupV1Identifier):
                    if root == .groupV1Details(groupV1Identifier: groupV1Identifier) {
                        path.removeAll()
                    } else {
                        path.append(Route.groupDetails(groupIdentifier: groupIdentifier))
                    }
                case .groupV2(let groupV2Identifier):
                    if root == .groupV2Details(groupV2Identifier: groupV2Identifier) {
                        path.removeAll()
                    } else {
                        path.append(Route.groupDetails(groupIdentifier: groupIdentifier))
                    }
                }
            }
        }
    }

}

extension ObvPresentedNavigationStack: ObvListOfCommonGroupsWithContactViewNavigation {
    // Other protocol conformances are enough
}
