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


public struct ObvUIGroupV2RouterDataSources {
    let avatarViewDataSource: ObvAvatarViewDataSource
    let listOfGroupMembersViewDataSource: any ListOfGroupMembersViewDataSource
    let ownedIdentityAsGroupMemberViewDataSource: any OwnedIdentityAsGroupMemberViewDataSource
    let singleGroupMemberViewDataSource: any SingleGroupMemberViewDataSource
    let oneToOneInvitableViewDataSource: any OneToOneInvitableViewDataSource
    let singleGroupV2MainViewDataSource: any SingleGroupV2MainViewDataSource
    let fullListOfGroupMembersViewDataSource: any FullListOfGroupMembersViewDataSource
    let onetoOneInvitableGroupMembersViewDataSource: any OnetoOneInvitableGroupMembersViewDataSource
    let onetoOneInvitableGroupMembersViewCellDataSource: any OnetoOneInvitableGroupMembersViewCellDataSource
    let editGroupNameAndPictureViewDataSource: any EditGroupNameAndPictureViewDataSource
    let editGroupTypeViewDataSource: any EditGroupTypeViewDataSource
    let selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource
    let listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource
    let groupCreationNavigationStackDataSource: any GroupCreationNavigationStackDataSource
    let selectUsersToRemoveViewDataSource: any SelectUsersToRemoveViewDataSource
    let listOfMembersWithAddAndRemoveButtonsViewDataSource: any ListOfMembersWithAddAndRemoveButtonsViewDataSource
    let listOfMembersWithSegmentedControlViewDataSource: any ListOfMembersWithSegmentedControlViewDataSource
    
    public init(avatarViewDataSource: ObvAvatarViewDataSource,
                listOfGroupMembersViewDataSource: any ListOfGroupMembersViewDataSource,
                ownedIdentityAsGroupMemberViewDataSource: any OwnedIdentityAsGroupMemberViewDataSource,
                singleGroupMemberViewDataSource: any SingleGroupMemberViewDataSource,
                oneToOneInvitableViewDataSource: any OneToOneInvitableViewDataSource,
                singleGroupV2MainViewDataSource: any SingleGroupV2MainViewDataSource,
                fullListOfGroupMembersViewDataSource: any FullListOfGroupMembersViewDataSource,
                onetoOneInvitableGroupMembersViewDataSource: any OnetoOneInvitableGroupMembersViewDataSource,
                onetoOneInvitableGroupMembersViewCellDataSource: any OnetoOneInvitableGroupMembersViewCellDataSource,
                editGroupNameAndPictureViewDataSource: any EditGroupNameAndPictureViewDataSource,
                editGroupTypeViewDataSource: any EditGroupTypeViewDataSource,
                selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource,
                listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource,
                groupCreationNavigationStackDataSource: any GroupCreationNavigationStackDataSource,
                selectUsersToRemoveViewDataSource: any SelectUsersToRemoveViewDataSource,
                listOfMembersWithAddAndRemoveButtonsViewDataSource: any ListOfMembersWithAddAndRemoveButtonsViewDataSource,
                listOfMembersWithSegmentedControlViewDataSource: any ListOfMembersWithSegmentedControlViewDataSource) {
        self.avatarViewDataSource = avatarViewDataSource
        self.listOfGroupMembersViewDataSource = listOfGroupMembersViewDataSource
        self.ownedIdentityAsGroupMemberViewDataSource = ownedIdentityAsGroupMemberViewDataSource
        self.singleGroupMemberViewDataSource = singleGroupMemberViewDataSource
        self.oneToOneInvitableViewDataSource = oneToOneInvitableViewDataSource
        self.singleGroupV2MainViewDataSource = singleGroupV2MainViewDataSource
        self.fullListOfGroupMembersViewDataSource = fullListOfGroupMembersViewDataSource
        self.onetoOneInvitableGroupMembersViewDataSource = onetoOneInvitableGroupMembersViewDataSource
        self.onetoOneInvitableGroupMembersViewCellDataSource = onetoOneInvitableGroupMembersViewCellDataSource
        self.editGroupNameAndPictureViewDataSource = editGroupNameAndPictureViewDataSource
        self.editGroupTypeViewDataSource = editGroupTypeViewDataSource
        self.selectUsersToAddViewDataSource = selectUsersToAddViewDataSource
        self.listOfUsersViewCellDataSource = listOfUsersViewCellDataSource
        self.groupCreationNavigationStackDataSource = groupCreationNavigationStackDataSource
        self.selectUsersToRemoveViewDataSource = selectUsersToRemoveViewDataSource
        self.listOfMembersWithAddAndRemoveButtonsViewDataSource = listOfMembersWithAddAndRemoveButtonsViewDataSource
        self.listOfMembersWithSegmentedControlViewDataSource = listOfMembersWithSegmentedControlViewDataSource
    }
    
    var singleGroupV2MainViewSubDataSources: SingleGroupV2MainView.SubDataSources {
        .init(listOfGroupMembersViewDataSource: listOfGroupMembersViewDataSource,
              ownedIdentityAsGroupMemberViewDataSource: ownedIdentityAsGroupMemberViewDataSource,
              singleGroupMemberViewDataSource: singleGroupMemberViewDataSource,
              oneToOneInvitableViewDataSource: oneToOneInvitableViewDataSource,
              avatarViewDataSource: avatarViewDataSource,
              editGroupNameAndPictureViewDataSource: editGroupNameAndPictureViewDataSource,
              editGroupTypeViewDataSource: editGroupTypeViewDataSource,
              selectUsersToAddViewDataSource: selectUsersToAddViewDataSource,
              listOfUsersViewCellDataSource: listOfUsersViewCellDataSource,
              editGroupTypeNavigationStackSubDataSources: editGroupTypeNavigationStackSubDataSources)
    }
    
    var fullListOfGroupMembersViewSubDataSources: FullListOfGroupMembersView.SubDataSources {
        .init(singleGroupMemberViewDataSource: singleGroupMemberViewDataSource,
              selectUsersToAddViewDataSource: selectUsersToAddViewDataSource,
              listOfUsersViewCellDataSource: listOfUsersViewCellDataSource,
              ownedIdentityAsGroupMemberViewDataSource: ownedIdentityAsGroupMemberViewDataSource,
              avatarViewDataSource: avatarViewDataSource,
              listOfGroupMembersViewDataSource: listOfGroupMembersViewDataSource,
              selectUsersToRemoveViewDataSource: selectUsersToRemoveViewDataSource)
    }
    
    var editGroupTypeNavigationStackSubDataSources: EditGroupTypeNavigationStack.SubDataSources {
        .init(fullListOfGroupMembersViewDataSource: fullListOfGroupMembersViewDataSource,
              editGroupTypeViewDataSource: editGroupTypeViewDataSource,
              fullListOfGroupMembersViewSubDataSources: fullListOfGroupMembersViewSubDataSources)
    }
    
    var groupCreationNavigationStackDataSources: GroupV2CreationNavigationStack.DataSources {
        .init(groupCreationNavigationStackDataSource: groupCreationNavigationStackDataSource,
              selectUsersToAddViewDataSource: selectUsersToAddViewDataSource,
              listOfUsersViewCellDataSource: listOfUsersViewCellDataSource,
              avatarViewDataSource: avatarViewDataSource,
              editGroupTypeViewDataSource: editGroupTypeViewDataSource,
              fullListOfGroupMembersViewDataSource: fullListOfGroupMembersViewDataSource,
              fullListOfGroupMembersViewSubDataSources: fullListOfGroupMembersViewSubDataSources)
    }
    
    var selectUsersToRemoveViewDataSources: SelectUsersToRemoveView.DataSources {
        .init(dataSource: selectUsersToRemoveViewDataSource,
              ownedIdentityAsGroupMemberViewDataSource: ownedIdentityAsGroupMemberViewDataSource,
              avatarViewDataSource: avatarViewDataSource,
              singleGroupMemberViewDataSource: singleGroupMemberViewDataSource)
    }
    
    var addAndRemoveMembersButtonsViewDataSources: AddAndRemoveMembersButtonsView.DataSources {
        .init(selectUsersToAddViewDataSource: selectUsersToAddViewDataSource,
              listOfUsersViewCellDataSource: listOfUsersViewCellDataSource,
              avatarViewDataSource: avatarViewDataSource,
              selectUsersToRemoveViewDataSources: selectUsersToRemoveViewDataSources)
    }
    
    var singleGroupMembersListViewDataSources: SingleGroupMembersListView.DataSources {
        .init(ownedIdentityAsGroupMemberViewDataSource: ownedIdentityAsGroupMemberViewDataSource,
              avatarViewDataSource: avatarViewDataSource,
              singleGroupMemberViewDataSource: singleGroupMemberViewDataSource)
    }
    
    var listOfMembersWithAddAndRemoveButtonsViewDataSources: ListOfMembersWithAddAndRemoveButtonsView.DataSources {
        .init(dataSource: listOfMembersWithAddAndRemoveButtonsViewDataSource,
              addAndRemoveMembersButtonsViewDataSources: addAndRemoveMembersButtonsViewDataSources,
              singleGroupMembersListViewDataSources: singleGroupMembersListViewDataSources)
    }
    
    var listOfMembersWithSegmentedControlViewDataSources: ListOfMembersWithSegmentedControlView.DataSources {
        .init(dataSource: listOfMembersWithSegmentedControlViewDataSource,
              singleGroupMembersListViewDataSources: singleGroupMembersListViewDataSources)
    }
    
    var groupV2CreationNavigationStackDataSources: GroupV2CreationNavigationStack.DataSources {
        .init(groupCreationNavigationStackDataSource: groupCreationNavigationStackDataSource,
              selectUsersToAddViewDataSource: selectUsersToAddViewDataSource,
              listOfUsersViewCellDataSource: listOfUsersViewCellDataSource,
              avatarViewDataSource: avatarViewDataSource,
              editGroupTypeViewDataSource: editGroupTypeViewDataSource,
              fullListOfGroupMembersViewDataSource: fullListOfGroupMembersViewDataSource,
              fullListOfGroupMembersViewSubDataSources: fullListOfGroupMembersViewSubDataSources)
    }
    
}
