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
import ObvOwnedIdentityChooser
import ObvEngine
import ObvSharedDataSources
import CoreData
import ObvInvitationFlow
import ObvProfilePictureBarButtonItem
import ObvDiscussionsList
import ObvGroupsList
import ObvCells
import ObvTypes
import ObvLicenceActivationFlow
import ObvSidebar
import ObvSingleDiscussion
import ObvSingleContact
import ObvUIGroupV1
import ObvUIGroupV2
import ObvUIGroupSharedBetweenV1AndV2
import ObvAppNavigation
import ObvSingleOwnedIdentity
import ObvSubscription


/// Allows to easily inject all the datasources required by the children view controller
struct ObvDataSources {
    let avatarViewDataSource: ObvAvatarViewDataSource
    let ownedIdentityChooserViewDataSource: OwnedIdentityChooserViewDataSource
    let profilePictureBarButtonItemViewDataSource: ObvProfilePictureBarButtonItemViewDataSource
    let groupsListViewDataSource: ObvGroupsListViewDataSource
    let groupCellViewDataSource: ObvGroupCellViewDataSource
    let qrCodeViewDataSource: ObvQRCodeViewDataSource
    let contactInvitationViewDataSource: ObvContactInvitationViewDataSource
    let scannerViewDataSource: ObvNewScannerViewDataSource
    let scanValidationViewDataSource: ObvScanValidationViewDataSource
    let sharingProfileViewDataSource: ObvSharingProfileViewDataSource
    let externalInvitationHandlerViewDataSource: ObvExternalInvitationHandlerViewDataSource
    let invitationContactsListViewDataSource: ListOfContactsAndGroupsViewDataSource
    let singleContactViewDataSource: ObvSingleContactViewAppDataSource
    let listOfCommonGroupsWithContactViewDataSource: ObvListOfCommonGroupsWithContactViewDataSource
    let contactDetailedInfosViewDataSource: ObvContactDetailedInfosViewDataSource
    let licenseActivationViewDataSource: NewLicenseActivationViewDataSource
    let listOfContactDevicesViewDataSource: any ObvCells.ObvListOfContactDevicesViewDataSource
    let pollViewDataSource: PollViewDataSource
    let sideBarViewAppDataSource: ObvSideBarViewAppDataSource
    let messageReactionsViewDataSource: any ObvMessageReactionsViewDataSource
    let trustOriginsListViewDataSource: ObvTrustOriginsListViewDataSource
    
    let archivedDiscussionsCellAppDataSource: any ArchivedDiscussionsCellDataSource
    let discussionsArchivedListViewAppDataSource: any ObvDiscussionsListViewDataSource
    let discussionsListViewDataSource: any ObvDiscussionsListViewDataSource
    let locationsCellViewDataSource: any ObvLocationsCellViewDataSource
    let tipCellViewAppDataSource: any TipCellViewDataSource

    let listOfGroupMembersViewDataSource: any ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersViewDataSource & ObvUIGroupV2.FullListOfGroupMembersViewDataSource
    let ownedIdentityAsGroupMemberViewDataSource: any ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberViewDataSource
    let singleGroupMemberViewDataSource: any ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberViewDataSource
    let selectUsersToAddViewDataSource: any ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewDataSource
    let listOfUsersViewCellDataSource: any ObvUIGroupSharedBetweenV1AndV2.ListOfUsersViewCellDataSource
    let editGroupNameAndPictureViewDataSource: any ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureViewDataSource
    let oneToOneInvitableViewDataSource: any ObvUIGroupSharedBetweenV1AndV2.OneToOneInvitableViewDataSource
    let onetoOneInvitableGroupMembersViewDataSource: any ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewDataSource
    let onetoOneInvitableGroupMembersViewCellDataSource: any ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewCellDataSource
    let selectUsersToRemoveViewDataSource: any ObvUIGroupSharedBetweenV1AndV2.SelectUsersToRemoveViewDataSource
    let listOfMembersWithAddAndRemoveButtonsViewDataSource: any ObvUIGroupSharedBetweenV1AndV2.ListOfMembersWithAddAndRemoveButtonsViewDataSource
    let listOfMembersWithSegmentedControlViewDataSource: any ObvUIGroupSharedBetweenV1AndV2.ListOfMembersWithSegmentedControlViewDataSource
    let listOfMembersWithAddAndRemoveButtonsViewDataSources: ObvUIGroupSharedBetweenV1AndV2.ListOfMembersWithAddAndRemoveButtonsView.DataSources
    let addAndRemoveMembersButtonsViewDataSources: ObvUIGroupSharedBetweenV1AndV2.AddAndRemoveMembersButtonsView.DataSources
    let selectUsersToRemoveViewDataSources: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToRemoveView.DataSources
    let singleGroupMembersListViewDataSources: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMembersListView.DataSources
    let listOfMembersWithSegmentedControlViewDataSources: ObvUIGroupSharedBetweenV1AndV2.ListOfMembersWithSegmentedControlView.DataSources
    
    let singleGroupV1MainViewDataSource: any ObvUIGroupV1.SingleGroupV1MainViewDataSource
    
    let singleGroupV2MainViewDataSource: any ObvUIGroupV2.SingleGroupV2MainViewDataSource & ObvUIGroupV2.EditGroupTypeViewDataSource
    var fullListOfGroupMembersViewDataSource: any ObvUIGroupV2.FullListOfGroupMembersViewDataSource { listOfGroupMembersViewDataSource }
    var editGroupTypeViewDataSource: any ObvUIGroupV2.EditGroupTypeViewDataSource { singleGroupV2MainViewDataSource }
    let groupCreationNavigationStackDataSource: any ObvUIGroupV2.GroupCreationNavigationStackDataSource & ObvUIGroupV1.GroupV1CreationNavigationStackDataSource
    let singleGroupV2MainViewSubDataSources: ObvUIGroupV2.SingleGroupV2MainView.SubDataSources
    let editGroupTypeNavigationStackSubDataSources: ObvUIGroupV2.EditGroupTypeNavigationStack.SubDataSources
    let groupV2RouterDataSources: ObvUIGroupV2.ObvUIGroupV2RouterDataSources

    let invitationFlowHostingControllerDataSources: ObvInvitationFlow.InvitationFlowHostingControllerDataSources
    
    let groupV1RouterDataSources: ObvUIGroupV1.ObvUIGroupV1RouterDataSources
    let singleGroupV1MainViewDataSources: ObvUIGroupV1.SingleGroupV1MainView.DataSources
    
    let groupV1CreationNavigationStackDataSources: GroupV1CreationNavigationStack.DataSources
    
    let groupV2CreationNavigationStackDataSources: GroupV2CreationNavigationStack.DataSources

    let fullListOfGroupMembersViewSubDataSources: FullListOfGroupMembersView.SubDataSources
    
    let singleContactViewDataSources: ObvSingleContact.ObvSingleContactView.DataSources
    let listOfCommonGroupsWithContactViewDataSources: ObvSingleContact.ObvListOfCommonGroupsWithContactView.DataSources

    let presentedNavigationStackDataSources: ObvAppNavigation.ObvPresentedNavigationStack.DataSources
    
    let appNavigationRouterDataSources: ObvAppNavigationRouter.DataSources
    
    let editOwnedDetailsViewDataSource: any ObvSingleOwnedIdentity.EditOwnedDetailsViewDataSource
    let singleOwnedIdentityViewDataSource: any ObvSingleOwnedIdentity.ObvSingleOwnedIdentityViewDataSource
    let chooseDeviceToReactivateViewDataSource: any ObvSingleOwnedIdentity.ObvChooseDeviceToReactivateViewDataSource
    let ownedDevicesListViewDataSource: any ObvSingleOwnedIdentity.OwnedDevicesListViewDataSource
    let ownedDeviceViewDataSource: any ObvSingleOwnedIdentity.OwnedDeviceViewDataSource
    let ownedDetailedInfosViewDataSource: any ObvSingleOwnedIdentity.ObvOwnedDetailedInfosViewDataSource
    let editOwnedDetailsViewDataSources: ObvSingleOwnedIdentity.EditOwnedDetailsView.DataSources
    let singleOwnedIdentityViewDataSources: ObvSingleOwnedIdentity.ObvSingleOwnedIdentityView.DataSources
    let singleOwnedIdentityViewStackDataSources: ObvSingleOwnedIdentity.ObvSingleOwnedIdentityViewStack.DataSources
    let ownedDevicesListViewDataSources: ObvSingleOwnedIdentity.OwnedDevicesListView.DataSources
    let ownedDetailedInfosViewDataSources: ObvSingleOwnedIdentity.ObvOwnedDetailedInfosView.DataSources
    
    let olvidShopViewDataSource: any ObvSubscription.OlvidShopViewDataSource
    let olvidShopViewDataSources: ObvSubscription.OlvidShopView.DataSources

    @MainActor
    init(avatarViewAppDataSourceDelegate: any ObvAvatarViewAppDataSourceDelegate,
         singleContactViewAppDataSourceDelegate: ObvSingleContactViewAppDataSourceDelegate,
         licenseActivationViewControllerAppDataSourceDelegate: NewLicenseActivationViewControllerAppDataSourceDelegate,
         trustOriginsListViewAppDataSourceDelegate: ObvTrustOriginsListViewAppDataSourceDelegate,
         singleGroupV1MainViewAppDataSourceDelegate: SingleGroupV1MainViewAppDataSourceDelegate,
         editGroupNameAndPictureViewAppDataSourceDelegate: any EditGroupNameAndPictureViewAppDataSourceDelegate,
         chooseDeviceToReactivateViewAppDataSourceDelegate: any ObvChooseDeviceToReactivateViewAppDataSourceDelegate,
         ownedDetailedInfosViewAppDataSourceDelegate: any ObvOwnedDetailedInfosViewAppDataSourceDelegate,
         obvEngine: ObvEngine,
         backgroundContext: NSManagedObjectContext,
         viewContext: NSManagedObjectContext) {
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        backgroundContext.automaticallyMergesChangesFromParent = true
        
        // ForDiscussionsList
        
        self.archivedDiscussionsCellAppDataSource = ArchivedDiscussionsCellAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.discussionsArchivedListViewAppDataSource = ObvDiscussionsArchivedListViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.discussionsListViewDataSource = ObvDiscussionsListViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.locationsCellViewDataSource = ObvLocationsCellViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.tipCellViewAppDataSource = TipCellViewAppDataSource()

        // ForGroupsList
        
        self.groupCellViewDataSource = ObvGroupCellViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.groupsListViewDataSource = ObvGroupsListViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)

        // ForInvitationFlow
        
        self.invitationContactsListViewDataSource = ListOfContactsAndGroupsViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.contactInvitationViewDataSource = ObvContactInvitationViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.externalInvitationHandlerViewDataSource = ObvExternalInvitationHandlerViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.scannerViewDataSource = ObvNewScannerViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.qrCodeViewDataSource = ObvQRCodeViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.scanValidationViewDataSource = ObvScanValidationViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.sharingProfileViewDataSource = ObvSharingProfileViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext, obvEngine: obvEngine)

        // ForLicenses
        
        self.licenseActivationViewDataSource = NewLicenseActivationViewControllerAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext, delegate: licenseActivationViewControllerAppDataSourceDelegate)

        // ForListOfContactDevices

        self.listOfContactDevicesViewDataSource = ObvListOfContactDevicesViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        
        // ForPolls
        
        self.pollViewDataSource = PollViewDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        
        // ForProfilePictureBarButtonItem
        
        self.profilePictureBarButtonItemViewDataSource = ProfilePictureBarButtonItemViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)

        // ForSidebar
        
        self.sideBarViewAppDataSource = ObvSideBarViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        
        // ForSingleContact
        
        self.singleContactViewDataSource = ObvSingleContactViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext, delegate: singleContactViewAppDataSourceDelegate)
        self.listOfCommonGroupsWithContactViewDataSource = ObvListOfCommonGroupsWithContactViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.contactDetailedInfosViewDataSource = ObvContactDetailedInfosViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        
        // ForTrustOrigins
        
        self.trustOriginsListViewDataSource = ObvTrustOriginsListViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext, delegate: trustOriginsListViewAppDataSourceDelegate)

        // ObvSingleDiscussion
        
        self.messageReactionsViewDataSource = ObvMessageReactionsViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        
        // ForAvatars
        
        self.avatarViewDataSource = ObvAvatarViewAppDataSource(delegate: avatarViewAppDataSourceDelegate)

        // ForOwnedIdentityChooser
        
        self.ownedIdentityChooserViewDataSource = OwnedIdentityChooserViewAppDataSource(viewContext: viewContext, anyContext: backgroundContext)
        
        // For ObvUIGroupSharedBetweenV1AndV2
        
        self.listOfGroupMembersViewDataSource = ListOfGroupMembersViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.ownedIdentityAsGroupMemberViewDataSource = OwnedIdentityAsGroupMemberViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.singleGroupMemberViewDataSource = SingleGroupMemberViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.editGroupNameAndPictureViewDataSource = EditGroupNameAndPictureViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext, delegate: editGroupNameAndPictureViewAppDataSourceDelegate)
        self.oneToOneInvitableViewDataSource = OneToOneInvitableViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.onetoOneInvitableGroupMembersViewDataSource = OnetoOneInvitableGroupMembersViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.onetoOneInvitableGroupMembersViewCellDataSource = OnetoOneInvitableGroupMembersViewCellAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.selectUsersToRemoveViewDataSource = SelectUsersToRemoveViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.listOfMembersWithAddAndRemoveButtonsViewDataSource = ListOfMembersWithAddAndRemoveButtonsViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.listOfMembersWithSegmentedControlViewDataSource = ListOfMembersWithSegmentedControlViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)

        // For ObvUIGroupV1
        
        self.singleGroupV1MainViewDataSource = SingleGroupV1MainViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext, delegate: singleGroupV1MainViewAppDataSourceDelegate)
        
        // For ObvUIGroupV2
        
        self.singleGroupV2MainViewDataSource = SingleGroupV2MainViewModelOrNotFoundAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.selectUsersToAddViewDataSource = SelectUsersToAddViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.listOfUsersViewCellDataSource = ListOfUsersViewCellAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.groupCreationNavigationStackDataSource = GroupCreationNavigationStackAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        
        // For ObvSingleOwnedIdentity
        
        self.editOwnedDetailsViewDataSource = EditOwnedDetailsViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.singleOwnedIdentityViewDataSource = ObvSingleOwnedIdentityViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.chooseDeviceToReactivateViewDataSource = ObvChooseDeviceToReactivateViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext, delegate: chooseDeviceToReactivateViewAppDataSourceDelegate)
        self.ownedDevicesListViewDataSource = OwnedDevicesListViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.ownedDeviceViewDataSource = OwnedDeviceViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext)
        self.ownedDetailedInfosViewDataSource = ObvOwnedDetailedInfosViewAppDataSource(viewContext: viewContext, backgroundContext: backgroundContext, delegate: ownedDetailedInfosViewAppDataSourceDelegate)
        
        // For ObvSubscription
        
        self.olvidShopViewDataSource = OlvidShopViewAppDataSource()

        // For convenience
        
        self.invitationFlowHostingControllerDataSources = .init(
            sharingProfileViewDataSource: sharingProfileViewDataSource,
            scanValidationViewDataSource: scanValidationViewDataSource,
            avatarViewDataSource: avatarViewDataSource,
            groupCellViewDataSource: groupCellViewDataSource,
            qrCodeViewDataSource: qrCodeViewDataSource,
            scannerViewDataSource: scannerViewDataSource,
            contactInvitationViewDataSource: contactInvitationViewDataSource,
            externalInvitationHandlerViewDataSource: externalInvitationHandlerViewDataSource,
            invitationContactsListViewDataSource: invitationContactsListViewDataSource)
        
        self.groupV1RouterDataSources = .init(
            singleGroupV1MainViewDataSource: singleGroupV1MainViewDataSource,
            avatarViewDataSource: avatarViewDataSource,
            listOfGroupMembersViewDataSource: listOfGroupMembersViewDataSource,
            ownedIdentityAsGroupMemberViewDataSource: ownedIdentityAsGroupMemberViewDataSource,
            singleGroupMemberViewDataSource: singleGroupMemberViewDataSource,
            selectUsersToAddViewDataSource: selectUsersToAddViewDataSource,
            listOfUsersViewCellDataSource: listOfUsersViewCellDataSource,
            oneToOneInvitableViewDataSource: oneToOneInvitableViewDataSource,
            onetoOneInvitableGroupMembersViewDataSource: onetoOneInvitableGroupMembersViewDataSource,
            onetoOneInvitableGroupMembersViewCellDataSource: onetoOneInvitableGroupMembersViewCellDataSource,
            selectUsersToRemoveViewDataSource: selectUsersToRemoveViewDataSource,
            listOfMembersWithAddAndRemoveButtonsViewDataSource: listOfMembersWithAddAndRemoveButtonsViewDataSource,
            listOfMembersWithSegmentedControlViewDataSource: listOfMembersWithSegmentedControlViewDataSource,
            editGroupNameAndPictureViewDataSource: editGroupNameAndPictureViewDataSource,
            groupV1CreationNavigationStackDataSource: groupCreationNavigationStackDataSource)
        
        self.groupV2RouterDataSources = .init(
            avatarViewDataSource: avatarViewDataSource,
            listOfGroupMembersViewDataSource: listOfGroupMembersViewDataSource,
            ownedIdentityAsGroupMemberViewDataSource: ownedIdentityAsGroupMemberViewDataSource,
            singleGroupMemberViewDataSource: singleGroupMemberViewDataSource,
            oneToOneInvitableViewDataSource: oneToOneInvitableViewDataSource,
            singleGroupV2MainViewDataSource: singleGroupV2MainViewDataSource,
            fullListOfGroupMembersViewDataSource: listOfGroupMembersViewDataSource, // DataSource reuse
            onetoOneInvitableGroupMembersViewDataSource: onetoOneInvitableGroupMembersViewDataSource,
            onetoOneInvitableGroupMembersViewCellDataSource: onetoOneInvitableGroupMembersViewCellDataSource,
            editGroupNameAndPictureViewDataSource: editGroupNameAndPictureViewDataSource,
            editGroupTypeViewDataSource: singleGroupV2MainViewDataSource, // DataSource reuse
            selectUsersToAddViewDataSource: selectUsersToAddViewDataSource,
            listOfUsersViewCellDataSource: listOfUsersViewCellDataSource,
            groupCreationNavigationStackDataSource: groupCreationNavigationStackDataSource,
            selectUsersToRemoveViewDataSource: selectUsersToRemoveViewDataSource,
            listOfMembersWithAddAndRemoveButtonsViewDataSource: listOfMembersWithAddAndRemoveButtonsViewDataSource,
            listOfMembersWithSegmentedControlViewDataSource: listOfMembersWithSegmentedControlViewDataSource)
        
        self.fullListOfGroupMembersViewSubDataSources = .init(
            singleGroupMemberViewDataSource: singleGroupMemberViewDataSource,
            selectUsersToAddViewDataSource: selectUsersToAddViewDataSource,
            listOfUsersViewCellDataSource: listOfUsersViewCellDataSource,
            ownedIdentityAsGroupMemberViewDataSource: ownedIdentityAsGroupMemberViewDataSource,
            avatarViewDataSource: avatarViewDataSource,
            listOfGroupMembersViewDataSource: listOfGroupMembersViewDataSource,
            selectUsersToRemoveViewDataSource: selectUsersToRemoveViewDataSource)
        
        self.groupV1CreationNavigationStackDataSources = .init(
            groupV1CreationNavigationStackDataSource: groupCreationNavigationStackDataSource,
            selectUsersToAddViewDataSource: selectUsersToAddViewDataSource,
            listOfUsersViewCellDataSource: listOfUsersViewCellDataSource,
            avatarViewDataSource: avatarViewDataSource)
        
        self.groupV2CreationNavigationStackDataSources = .init(
            groupCreationNavigationStackDataSource: groupCreationNavigationStackDataSource,
            selectUsersToAddViewDataSource: selectUsersToAddViewDataSource,
            listOfUsersViewCellDataSource: listOfUsersViewCellDataSource,
            avatarViewDataSource: avatarViewDataSource,
            editGroupTypeViewDataSource: singleGroupV2MainViewDataSource, // DataSource reuse
            fullListOfGroupMembersViewDataSource: listOfGroupMembersViewDataSource, // DataSource reuse
            fullListOfGroupMembersViewSubDataSources: fullListOfGroupMembersViewSubDataSources)
        
        self.singleContactViewDataSources = .init(
            dataSource: singleContactViewDataSource,
            avatarViewDataSource: avatarViewDataSource,
            contactDetailedInfosViewDataSource: contactDetailedInfosViewDataSource)
        
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
            dataSource: listOfMembersWithAddAndRemoveButtonsViewDataSource,
            addAndRemoveMembersButtonsViewDataSources: addAndRemoveMembersButtonsViewDataSources,
            singleGroupMembersListViewDataSources: singleGroupMembersListViewDataSources)
        
        self.listOfMembersWithSegmentedControlViewDataSources = .init(
            dataSource: listOfMembersWithSegmentedControlViewDataSource,
            singleGroupMembersListViewDataSources: singleGroupMembersListViewDataSources)
        
        self.editGroupTypeNavigationStackSubDataSources = .init(
            fullListOfGroupMembersViewDataSource: listOfGroupMembersViewDataSource, // DataSource reuse
            editGroupTypeViewDataSource: singleGroupV2MainViewDataSource, // DataSource reuse
            fullListOfGroupMembersViewSubDataSources: fullListOfGroupMembersViewSubDataSources)
        
        self.singleGroupV2MainViewSubDataSources = .init(
            listOfGroupMembersViewDataSource: listOfGroupMembersViewDataSource,
            ownedIdentityAsGroupMemberViewDataSource: ownedIdentityAsGroupMemberViewDataSource,
            singleGroupMemberViewDataSource: singleGroupMemberViewDataSource,
            oneToOneInvitableViewDataSource: oneToOneInvitableViewDataSource,
            avatarViewDataSource: avatarViewDataSource,
            editGroupNameAndPictureViewDataSource: editGroupNameAndPictureViewDataSource,
            editGroupTypeViewDataSource: singleGroupV2MainViewDataSource, // DataSource reuse
            selectUsersToAddViewDataSource: selectUsersToAddViewDataSource,
            listOfUsersViewCellDataSource: listOfUsersViewCellDataSource,
            editGroupTypeNavigationStackSubDataSources: editGroupTypeNavigationStackSubDataSources)
        
        self.listOfCommonGroupsWithContactViewDataSources = .init(
            dataSource: listOfCommonGroupsWithContactViewDataSource,
            groupCellViewDataSource: groupCellViewDataSource,
            avatarViewDataSource: avatarViewDataSource)
        
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
        
        self.presentedNavigationStackDataSources = .init(
            singleGroupV1MainViewDataSource: singleGroupV1MainViewDataSource,
            singleGroupV2MainViewDataSource: singleGroupV2MainViewDataSource,
            onetoOneInvitableGroupMembersViewDataSource: onetoOneInvitableGroupMembersViewDataSource,
            onetoOneInvitableGroupMembersViewCellDataSource: onetoOneInvitableGroupMembersViewCellDataSource,
            avatarViewDataSource: avatarViewDataSource,
            fullListOfGroupMembersViewDataSource: listOfGroupMembersViewDataSource, // DataSource reuse
            listOfContactDevicesViewDataSource: listOfContactDevicesViewDataSource,
            trustOriginsListViewDataSource: trustOriginsListViewDataSource,
            listOfMembersWithAddAndRemoveButtonsViewDataSources: listOfMembersWithAddAndRemoveButtonsViewDataSources,
            listOfMembersWithSegmentedControlViewDataSources: listOfMembersWithSegmentedControlViewDataSources,
            singleGroupV2MainViewSubDataSources: singleGroupV2MainViewSubDataSources,
            fullListOfGroupMembersViewSubDataSources: fullListOfGroupMembersViewSubDataSources,
            singleContactViewDataSources: singleContactViewDataSources,
            listOfCommonGroupsWithContactViewDataSources: listOfCommonGroupsWithContactViewDataSources,
            singleGroupV1MainViewDataSources: singleGroupV1MainViewDataSources)
        
        self.appNavigationRouterDataSources = .init(
            listOfContactDevicesViewDataSource: listOfContactDevicesViewDataSource,
            trustOriginsListViewDataSource: trustOriginsListViewDataSource,
            singleGroupV2MainViewDataSource: singleGroupV2MainViewDataSource,
            onetoOneInvitableGroupMembersViewDataSource: onetoOneInvitableGroupMembersViewDataSource,
            onetoOneInvitableGroupMembersViewCellDataSource: onetoOneInvitableGroupMembersViewCellDataSource,
            avatarViewDataSource: avatarViewDataSource,
            fullListOfGroupMembersViewDataSource: listOfGroupMembersViewDataSource, // DataSource reuse
            singleContactViewDataSources: singleContactViewDataSources,
            listOfCommonGroupsWithContactViewDataSources: listOfCommonGroupsWithContactViewDataSources,
            singleGroupV1MainViewDataSources: singleGroupV1MainViewDataSources,
            singleGroupV2MainViewSubDataSources: singleGroupV2MainViewSubDataSources,
            listOfMembersWithAddAndRemoveButtonsViewDataSources: listOfMembersWithAddAndRemoveButtonsViewDataSources,
            listOfMembersWithSegmentedControlViewDataSources: listOfMembersWithSegmentedControlViewDataSources,
            fullListOfGroupMembersViewSubDataSources: fullListOfGroupMembersViewSubDataSources,
            presentedNavigationStackDataSources: presentedNavigationStackDataSources)
        
        self.olvidShopViewDataSources = .init(
            dataSource: olvidShopViewDataSource)
        
        self.ownedDetailedInfosViewDataSources = .init(dataSource: ownedDetailedInfosViewDataSource,
                                                       avatarViewDataSource: avatarViewDataSource)

        self.editOwnedDetailsViewDataSources = .init(
            dataSource: editOwnedDetailsViewDataSource,
            avatarViewDataSource: avatarViewDataSource)
        self.singleOwnedIdentityViewDataSources = .init(
            dataSource: singleOwnedIdentityViewDataSource,
            avatarViewDataSource: avatarViewDataSource,
            chooseDeviceToReactivateViewDataSource: chooseDeviceToReactivateViewDataSource,
            olvidShopViewDataSources: olvidShopViewDataSources,
            ownedDetailedInfosViewDataSources: ownedDetailedInfosViewDataSources)
                
        self.ownedDevicesListViewDataSources = .init(
            dataSource: ownedDevicesListViewDataSource,
            ownedDeviceViewDataSource: ownedDeviceViewDataSource)
        
        self.singleOwnedIdentityViewStackDataSources = .init(
            olvidShopViewDataSources: olvidShopViewDataSources,
            singleOwnedIdentityViewDataSources: singleOwnedIdentityViewDataSources,
            editOwnedDetailsViewDataSources: editOwnedDetailsViewDataSources,
            ownedDevicesListViewDataSources: ownedDevicesListViewDataSources)
        
    }
    

    public func fetchAvatarImage(localPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let avatarViewDataSource = avatarViewDataSource as? ObvAvatarViewAppDataSource else {
            assertionFailure(); throw ObvError.internalError
        }
        return try await avatarViewDataSource.fetchAvatarImage(localPhotoURL: localPhotoURL, avatarSize: avatarSize)
    }
    
    
    public func fetchAvatarImage(profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let avatarViewDataSource = avatarViewDataSource as? ObvAvatarViewAppDataSource else {
            assertionFailure(); return nil
        }
        return await avatarViewDataSource.fetchAvatarImage(profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    
    
    enum ObvError: Error {
        case internalError
    }
    
}

