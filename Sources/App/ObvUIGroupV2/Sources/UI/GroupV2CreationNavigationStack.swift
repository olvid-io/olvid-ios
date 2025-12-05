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
import ObvUIGroupSharedBetweenV1AndV2
import ObvAppTypes
import ObvDesignSystem


@MainActor
public protocol GroupV2CreationNavigationStackActions {
    func userWantsObtainAvatarDuringGroupCreation(_ view: GroupV2CreationNavigationStack, avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
    func userWantsToSaveImageToTempFileDuringGroupCreation(_ view: GroupV2CreationNavigationStack, image: UIImage) async throws -> URL
    func userWantsToPublishCreatedGroupV2(_ view: GroupV2CreationNavigationStack, ownedCryptoId: ObvCryptoId, groupDetails: ObvTypes.ObvGroupDetails, groupType: ObvGroupType, otherGroupMembers: Set<ObvGroupV2.IdentityAndPermissions>) async throws
}

@MainActor
public protocol GroupCreationNavigationStackDataSource {
    func getContactIdentifierOfGroupMember(_ view: GroupV2CreationNavigationStack, contactIdentifier: SingleGroupMemberView.Model.Identifier) async throws -> ObvContactIdentifier
    func getContactIdentifierOfGroupMember(_ view: GroupV2CreationNavigationStack, contactIdentifier: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier) async throws -> ObvTypes.ObvContactIdentifier
}


@MainActor
public protocol GroupCreationNavigationStackNavigation {
    func presentedGroupCreationFlowShouldBeDismissed(_ view: GroupV2CreationNavigationStack)
}

public struct GroupV2CreationNavigationStack: View {

    @State var creationSession: CreationSession
    let dataSources: DataSources
    let actions: any GroupV2CreationNavigationStackActions
    let navigation: any GroupCreationNavigationStackNavigation
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
    
    init(ownedCryptoId: ObvCryptoId,
         creationMode: ObvGroupV2CreationRouter.CreationMode,
         dataSources: DataSources,
         actions: GroupV2CreationNavigationStackActions,
         navigation: any GroupCreationNavigationStackNavigation,
         uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet) {
        self.creationSession = .init(ownedCryptoId: ownedCryptoId)
        self.dataSources = dataSources
        self.actions = actions
        self.navigation = navigation
        self.uiKitDelegateForSwiftUISheet = uiKitDelegateForSwiftUISheet
        switch creationMode {
        case .fromScratch:
            break
        case .cloneExistingGroup(valuesOfGroupToClone: let valuesOfGroupToClone):
            creationSession.userIdentifiersOfAddedUsers = valuesOfGroupToClone.userIdentifiersOfAddedUsers
            creationSession.selectedAdmins = valuesOfGroupToClone.selectedAdmins
            creationSession.selectedGroupType = valuesOfGroupToClone.selectedGroupType
            creationSession.selectedPhoto = valuesOfGroupToClone.selectedPhoto
            if let sanitizedSelectedGroupName = valuesOfGroupToClone.selectedGroupName?.mapToNilIfZeroLength() {
                creationSession.selectedGroupName = String(localizedInThisBundle: "CLONED_GROUP_NAME_FROM_ORIGINAL_NAME_\(sanitizedSelectedGroupName)")
            } else {
                creationSession.selectedGroupName = nil
            }
            creationSession.selectedGroupDescription = valuesOfGroupToClone.selectedGroupDescription
        }

    }
    
    public struct DataSources {
        let groupCreationNavigationStackDataSource: any GroupCreationNavigationStackDataSource
        let selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource
        let listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        let editGroupTypeViewDataSource: any EditGroupTypeViewDataSource
        let fullListOfGroupMembersViewDataSource: any FullListOfGroupMembersViewDataSource
        let fullListOfGroupMembersViewSubDataSources: FullListOfGroupMembersView.SubDataSources

        public init(groupCreationNavigationStackDataSource: any GroupCreationNavigationStackDataSource,
                    selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource,
                    listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource,
                    avatarViewDataSource: any ObvAvatarViewDataSource,
                    editGroupTypeViewDataSource: any EditGroupTypeViewDataSource,
                    fullListOfGroupMembersViewDataSource: any FullListOfGroupMembersViewDataSource,
                    fullListOfGroupMembersViewSubDataSources: FullListOfGroupMembersView.SubDataSources) {
            self.groupCreationNavigationStackDataSource = groupCreationNavigationStackDataSource
            self.selectUsersToAddViewDataSource = selectUsersToAddViewDataSource
            self.listOfUsersViewCellDataSource = listOfUsersViewCellDataSource
            self.avatarViewDataSource = avatarViewDataSource
            self.editGroupTypeViewDataSource = editGroupTypeViewDataSource
            self.fullListOfGroupMembersViewDataSource = fullListOfGroupMembersViewDataSource
            self.fullListOfGroupMembersViewSubDataSources = fullListOfGroupMembersViewSubDataSources
        }
    }
    
    /// A `CreationSession` instance keeps track of the user's choice during the successive steps of the group creation.
    final class CreationSession {
        
        let ownedCryptoId: ObvCryptoId
        let uuid = UUID()

        var userIdentifiersOfAddedUsers = [SelectUsersToAddViewModel.User.Identifier]()
        var selectedAdmins = Set<SingleGroupMemberView.Model.Identifier>()
        var selectedGroupType: ObvGroupType?
        var selectedPhoto: UIImage?
        var selectedGroupName: String?
        var selectedGroupDescription: String?

        init(ownedCryptoId: ObvCryptoId) {
            self.ownedCryptoId = ownedCryptoId
        }
        
    }

    @State private var path: NavigationPath = NavigationPath()

    private enum Route: Hashable, Identifiable {
        case editGroupType
        case editAdmins // Only shown for certain group types
        case editGroupNameAndPicture
        
        var id: Self {
            return self
        }
    }
    
    private func userTappedCancelButton() {
        navigation.presentedGroupCreationFlowShouldBeDismissed(self)
    }

    public var body: some View {
        NavigationStack(path: $path) {
            SelectUsersToAddView(mode: .creation(ownedCryptoId: creationSession.ownedCryptoId,
                                                 creationSessionUUID: creationSession.uuid,
                                                 preselectedUserIdentifiers: creationSession.userIdentifiersOfAddedUsers,
                                                 actionsForCreation: self,
                                                 navigation: self),
                                 dataSource: dataSources.selectUsersToAddViewDataSource,
                                 listOfUsersViewCellDataSource: dataSources.listOfUsersViewCellDataSource,
                                 avatarViewDataSource: dataSources.avatarViewDataSource)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .editGroupType:
                    EditGroupTypeView(mode: .creation(creationSessionUUID: creationSession.uuid,
                                                      ownedCryptoId: creationSession.ownedCryptoId,
                                                      preSelectedGroupType: creationSession.selectedGroupType ?? .standard,
                                                      navigation: self),
                                      dataSource: dataSources.editGroupTypeViewDataSource)
                case .editAdmins:
                    FullListOfGroupMembersView(
                        mode: .selectAdminsDuringGroupCreation(
                            creationSessionUUID: creationSession.uuid,
                            ownedCryptoId: creationSession.ownedCryptoId,
                            preSelectedAdmins: creationSession.selectedAdmins,
                            userIdentifiersOfAddedUsers: creationSession.userIdentifiersOfAddedUsers,
                            actionsForCreation: self,
                            navigation: self),
                        dataSource: dataSources.fullListOfGroupMembersViewDataSource,
                        subDataSources: dataSources.fullListOfGroupMembersViewSubDataSources,
                        uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                case .editGroupNameAndPicture:
                    EditGroupNameAndPictureView(
                        mode: .creation(creationSessionUUID: creationSession.uuid,
                                        ownedCryptoId: creationSession.ownedCryptoId,
                                        preSelectedPhoto: creationSession.selectedPhoto,
                                        preSelectedGroupName: creationSession.selectedGroupName,
                                        preSelectedGroupDescription: creationSession.selectedGroupDescription,
                                        navigation: self,
                                        actions: self),
                        actions: self)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ObvButtonWithCancelRole(action: userTappedCancelButton)
                }
            }
        }
    }
    
}


extension GroupV2CreationNavigationStack: FullListOfGroupMembersViewActionsForCreation {
    
    public func getGroupLightweightModelDuringGroupCreation(_ view: FullListOfGroupMembersView, creationSessionUUID: UUID) throws -> ObvGroupLightweightModel {
        return ObvGroupLightweightModel(ownedIdentityIsAdmin: true,
                                        groupType: creationSession.selectedGroupType,
                                        updateInProgressDuringGroupEdition: false,
                                        isKeycloakManaged: false)
    }
    
}


extension GroupV2CreationNavigationStack: FullListOfGroupMembersViewNavigationDuringCreation {
    
    public func userConfirmedTheAdminsChoiceDuringGroupCreationAndWantsToNavigateToNextScreen(_ view: FullListOfGroupMembersView.InternalView, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId) {
        path.append(Route.editGroupNameAndPicture)
    }
    
}

extension GroupV2CreationNavigationStack: SingleGroupMemberViewActionsDuringCreation {
    
    public func userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(_ view: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.InternalView, creationSessionUUID: UUID, memberIdentifier: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model.Identifier, newIsAnAdmin: Bool) {
        if newIsAnAdmin {
            creationSession.selectedAdmins.insert(memberIdentifier)
        } else {
            creationSession.selectedAdmins.remove(memberIdentifier)
        }
    }
    
}


extension GroupV2CreationNavigationStack: SelectUsersToAddViewActionsForCreation {
    
    public func userWantsToAddSelectedUsersToCreatingGroup(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddView.InternalView, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, withIdentifiers userIdentifiers: [ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier]) {
        creationSession.userIdentifiersOfAddedUsers = userIdentifiers
    }

}


extension GroupV2CreationNavigationStack: SelectUsersToAddViewNavigationForCreation {
    
    public func userDidFinishSelectingUsersToAddAndWantsToNavigateToNextScreen(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddView.InternalView) {
        path.append(Route.editGroupType)
    }
    
}


extension GroupV2CreationNavigationStack: EditGroupTypeViewNavigationDuringCreation {
    
    public func userChosedGroupTypeDuringGroupCreation(_ view: EditGroupTypeView, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, selectedGroupType: ObvAppTypes.ObvGroupType) {
        assert(creationSession.ownedCryptoId == ownedCryptoId)
        creationSession.selectedGroupType = selectedGroupType
        switch selectedGroupType {
        case .standard:
            path.append(Route.editGroupNameAndPicture)
        case .managed,
                .readOnly,
                .advanced:
            path.append(Route.editAdmins)
        }
    }
    
}


extension GroupV2CreationNavigationStack: EditGroupNameAndPictureViewNavigationDuringCreation {
    
    public func groupWasSuccessfullyCreated(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.InternalView, ownedCryptoId: ObvTypes.ObvCryptoId) {
        // Called after `userWantsToPublishCreatedGroupWithDetails`. At this point, we already made the request to create the group, so we only have to exit the group
        // creation flow.
        navigation.presentedGroupCreationFlowShouldBeDismissed(self)
    }
    
}


extension GroupV2CreationNavigationStack: EditGroupNameAndPictureViewActionsProtocol {
    
    public func userWantsObtainAvatar(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.InternalView, avatarSource: ObvAppTypes.ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return try await actions.userWantsObtainAvatarDuringGroupCreation(self, avatarSource: avatarSource, avatarSize: avatarSize)
    }
    
    public func userWantsToSaveImageToTempFile(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.InternalView, image: UIImage) async throws -> URL {
        return try await actions.userWantsToSaveImageToTempFileDuringGroupCreation(self, image: image)
    }
    
}


extension GroupV2CreationNavigationStack: EditGroupNameAndPictureViewActionsForCreation {
    
    public func userWantsToPublishCreatedGroupWithDetails(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.InternalView, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, groupDetails: ObvTypes.ObvGroupDetails) async throws {
        // Called when the user confirms they want to publish the group. We create the group and wait for the `groupWasSuccessfullyCreated` method to be called to exit the group creation flow.
        
        guard let selectedGroupType = creationSession.selectedGroupType else {
            assertionFailure("Since we went through the group type selection screen, this is unexpected")
            throw ObvError.selectedGroupTypeIsNil
        }
        
        var adminsCryptoIds = Set<ObvCryptoId>()
        for admin in creationSession.selectedAdmins {
            let contactIdentifier = try await dataSources.groupCreationNavigationStackDataSource.getContactIdentifierOfGroupMember(self, contactIdentifier: admin)
            guard contactIdentifier.ownedCryptoId == ownedCryptoId else {
                assertionFailure()
                throw ObvError.unexpectedOwnedIdentity
            }
            adminsCryptoIds.insert(contactIdentifier.contactCryptoId)
        }
        
        let permissionsForAdmins = ObvGroupType.exactPermissions(of: .admin, forGroupType: selectedGroupType)
        let permissionsForRegularMember = ObvGroupType.exactPermissions(of: .regularMember, forGroupType: selectedGroupType)
        
        var otherGroupMembers = Set<ObvGroupV2.IdentityAndPermissions>()
        for userIdentifierOfAddedUser in creationSession.userIdentifiersOfAddedUsers {
            let contactIdentifier = try await dataSources.groupCreationNavigationStackDataSource.getContactIdentifierOfGroupMember(self, contactIdentifier: userIdentifierOfAddedUser)
            guard contactIdentifier.ownedCryptoId == ownedCryptoId else {
                assertionFailure()
                throw ObvError.unexpectedOwnedIdentity
            }
            let contactCryptoId = contactIdentifier.contactCryptoId
            if adminsCryptoIds.contains(contactCryptoId) {
                otherGroupMembers.insert(.init(identity: contactCryptoId, permissions: permissionsForAdmins))
            } else {
                otherGroupMembers.insert(.init(identity: contactCryptoId, permissions: permissionsForRegularMember))
            }
        }
        
        try await actions.userWantsToPublishCreatedGroupV2(self,
                                                           ownedCryptoId: ownedCryptoId,
                                                           groupDetails: groupDetails,
                                                           groupType: selectedGroupType,
                                                           otherGroupMembers: otherGroupMembers)
    }
    
}


extension GroupV2CreationNavigationStack {
    
    enum ObvError: Error {
        case selectedGroupTypeIsNil
        case unexpectedOwnedIdentity
    }
    
}
