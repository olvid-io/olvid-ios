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

import Foundation
import ObvDesignSystem
import ObvUIGroupSharedBetweenV1AndV2

public struct ObvUIGroupV1RouterDataSources {
    
    let singleGroupV1MainViewDataSource: any SingleGroupV1MainViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let listOfGroupMembersViewDataSource: any ListOfGroupMembersViewDataSource
    let ownedIdentityAsGroupMemberViewDataSource: any OwnedIdentityAsGroupMemberViewDataSource
    let singleGroupMemberViewDataSource: any SingleGroupMemberViewDataSource
    let selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource
    let listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource
    let oneToOneInvitableViewDataSource: any OneToOneInvitableViewDataSource
    let onetoOneInvitableGroupMembersViewDataSource: any OnetoOneInvitableGroupMembersViewDataSource
    let onetoOneInvitableGroupMembersViewCellDataSource: any OnetoOneInvitableGroupMembersViewCellDataSource
    let selectUsersToRemoveViewDataSource: any SelectUsersToRemoveViewDataSource
    let istOfMembersWithAddAndRemoveButtonsViewDataSource: any ListOfMembersWithAddAndRemoveButtonsViewDataSource
    let listOfMembersWithSegmentedControlViewDataSource: any ListOfMembersWithSegmentedControlViewDataSource
    let editGroupNameAndPictureViewDataSource: any EditGroupNameAndPictureViewDataSource
    let groupV1CreationNavigationStackDataSource: any GroupV1CreationNavigationStackDataSource
    
    let selectUsersToRemoveViewDataSources: SelectUsersToRemoveView.DataSources
    let addAndRemoveMembersButtonsViewDataSources: AddAndRemoveMembersButtonsView.DataSources
    let singleGroupMembersListViewDataSources: SingleGroupMembersListView.DataSources
    let listOfMembersWithAddAndRemoveButtonsViewDataSources: ListOfMembersWithAddAndRemoveButtonsView.DataSources
    let listOfMembersWithSegmentedControlViewDataSources: ListOfMembersWithSegmentedControlView.DataSources
    let singleGroupV1MainViewDataSources: SingleGroupV1MainView.DataSources
    let groupV1CreationNavigationStackDataSources: GroupV1CreationNavigationStack.DataSources
    
    public init(singleGroupV1MainViewDataSource: any SingleGroupV1MainViewDataSource,
                avatarViewDataSource: ObvAvatarViewDataSource,
                listOfGroupMembersViewDataSource: any ListOfGroupMembersViewDataSource,
                ownedIdentityAsGroupMemberViewDataSource: any OwnedIdentityAsGroupMemberViewDataSource,
                singleGroupMemberViewDataSource: any SingleGroupMemberViewDataSource,
                selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource,
                listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource,
                oneToOneInvitableViewDataSource: any OneToOneInvitableViewDataSource,
                onetoOneInvitableGroupMembersViewDataSource: any OnetoOneInvitableGroupMembersViewDataSource,
                onetoOneInvitableGroupMembersViewCellDataSource: any OnetoOneInvitableGroupMembersViewCellDataSource,
                selectUsersToRemoveViewDataSource: any SelectUsersToRemoveViewDataSource,
                listOfMembersWithAddAndRemoveButtonsViewDataSource: any ListOfMembersWithAddAndRemoveButtonsViewDataSource,
                listOfMembersWithSegmentedControlViewDataSource: any ListOfMembersWithSegmentedControlViewDataSource,
                editGroupNameAndPictureViewDataSource: any EditGroupNameAndPictureViewDataSource,
                groupV1CreationNavigationStackDataSource: any GroupV1CreationNavigationStackDataSource) {
        
        self.singleGroupV1MainViewDataSource = singleGroupV1MainViewDataSource
        self.avatarViewDataSource = avatarViewDataSource
        self.listOfGroupMembersViewDataSource = listOfGroupMembersViewDataSource
        self.ownedIdentityAsGroupMemberViewDataSource = ownedIdentityAsGroupMemberViewDataSource
        self.singleGroupMemberViewDataSource = singleGroupMemberViewDataSource
        self.selectUsersToAddViewDataSource = selectUsersToAddViewDataSource
        self.listOfUsersViewCellDataSource = listOfUsersViewCellDataSource
        self.oneToOneInvitableViewDataSource = oneToOneInvitableViewDataSource
        self.onetoOneInvitableGroupMembersViewDataSource = onetoOneInvitableGroupMembersViewDataSource
        self.onetoOneInvitableGroupMembersViewCellDataSource = onetoOneInvitableGroupMembersViewCellDataSource
        self.selectUsersToRemoveViewDataSource = selectUsersToRemoveViewDataSource
        self.istOfMembersWithAddAndRemoveButtonsViewDataSource = listOfMembersWithAddAndRemoveButtonsViewDataSource
        self.listOfMembersWithSegmentedControlViewDataSource = listOfMembersWithSegmentedControlViewDataSource
        self.editGroupNameAndPictureViewDataSource = editGroupNameAndPictureViewDataSource
        self.groupV1CreationNavigationStackDataSource = groupV1CreationNavigationStackDataSource
        
        self.selectUsersToRemoveViewDataSources = .init(
            dataSource: selectUsersToRemoveViewDataSource,
            ownedIdentityAsGroupMemberViewDataSource: ownedIdentityAsGroupMemberViewDataSource,
            avatarViewDataSource: avatarViewDataSource,
            singleGroupMemberViewDataSource: singleGroupMemberViewDataSource)
        self.addAndRemoveMembersButtonsViewDataSources = .init(
            selectUsersToAddViewDataSource: selectUsersToAddViewDataSource,
            listOfUsersViewCellDataSource: listOfUsersViewCellDataSource,
            avatarViewDataSource: avatarViewDataSource,
            selectUsersToRemoveViewDataSources: selectUsersToRemoveViewDataSources)
        self.singleGroupMembersListViewDataSources = .init(
            ownedIdentityAsGroupMemberViewDataSource: ownedIdentityAsGroupMemberViewDataSource,
            avatarViewDataSource: avatarViewDataSource,
            singleGroupMemberViewDataSource: singleGroupMemberViewDataSource)
        self.listOfMembersWithAddAndRemoveButtonsViewDataSources = .init(
            dataSource: istOfMembersWithAddAndRemoveButtonsViewDataSource,
            addAndRemoveMembersButtonsViewDataSources: addAndRemoveMembersButtonsViewDataSources,
            singleGroupMembersListViewDataSources: singleGroupMembersListViewDataSources)
        self.listOfMembersWithSegmentedControlViewDataSources = .init(
            dataSource: listOfMembersWithSegmentedControlViewDataSource,
            singleGroupMembersListViewDataSources: singleGroupMembersListViewDataSources)
        self.singleGroupV1MainViewDataSources = .init(
            dataSource: singleGroupV1MainViewDataSource,
            avatarViewDataSource: avatarViewDataSource,
            listOfGroupMembersViewDataSource: listOfGroupMembersViewDataSource,
            ownedIdentityAsGroupMemberViewDataSource: ownedIdentityAsGroupMemberViewDataSource,
            singleGroupMemberViewDataSource: singleGroupMemberViewDataSource,
            selectUsersToAddViewDataSource: selectUsersToAddViewDataSource,
            listOfUsersViewCellDataSource: listOfUsersViewCellDataSource,
            oneToOneInvitableViewDataSource: oneToOneInvitableViewDataSource,
            editGroupNameAndPictureViewDataSource: editGroupNameAndPictureViewDataSource)
        self.groupV1CreationNavigationStackDataSources = .init(
            groupV1CreationNavigationStackDataSource: groupV1CreationNavigationStackDataSource,
            selectUsersToAddViewDataSource: selectUsersToAddViewDataSource,
            listOfUsersViewCellDataSource: listOfUsersViewCellDataSource,
            avatarViewDataSource: avatarViewDataSource)
    }
    
}
