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
import ObvUIGroupSharedBetweenV1AndV2
import ObvTypes
import ObvDesignSystem
import ObvAppTypes

@MainActor
public protocol GroupV1CreationNavigationStackActions {
    func userWantsObtainAvatarDuringGroupV1Creation(_ view: GroupV1CreationNavigationStack, avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
    func userWantsToSaveImageToTempFileDuringGroupV1Creation(_ view: GroupV1CreationNavigationStack, image: UIImage) async throws -> URL
    func userWantsToPublishCreatedGroupV1(_ view: GroupV1CreationNavigationStack, ownedCryptoId: ObvCryptoId, groupDetails: ObvTypes.ObvGroupDetails, otherGroupMembers: Set<ObvCryptoId>) async throws
}

@MainActor
public protocol GroupV1CreationNavigationStackDataSource {
    func getContactIdentifierOfGroupMember(_ view: GroupV1CreationNavigationStack, contactIdentifier: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier) async throws -> ObvContactIdentifier
}

@MainActor
public protocol GroupV1CreationNavigationStackNavigation {
    func presentedGroupCreationFlowShouldBeDismissed(_ view: GroupV1CreationNavigationStack)
}

public struct GroupV1CreationNavigationStack: View {
    
    @State var creationSession: CreationSession
    let dataSources: DataSources
    let actions: any GroupV1CreationNavigationStackActions
    let navigation: any GroupV1CreationNavigationStackNavigation

    init(ownedCryptoId: ObvCryptoId, dataSources: DataSources, actions: any GroupV1CreationNavigationStackActions, navigation: any GroupV1CreationNavigationStackNavigation) {
        self.creationSession = .init(ownedCryptoId: ownedCryptoId)
        self.dataSources = dataSources
        self.navigation = navigation
        self.actions = actions
    }
    
    public struct DataSources {
        let groupV1CreationNavigationStackDataSource: any GroupV1CreationNavigationStackDataSource
        let selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource
        let listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        
        public init(groupV1CreationNavigationStackDataSource: GroupV1CreationNavigationStackDataSource,
                    selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource,
                    listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource,
                    avatarViewDataSource: any ObvAvatarViewDataSource) {
            self.groupV1CreationNavigationStackDataSource = groupV1CreationNavigationStackDataSource
            self.selectUsersToAddViewDataSource = selectUsersToAddViewDataSource
            self.listOfUsersViewCellDataSource = listOfUsersViewCellDataSource
            self.avatarViewDataSource = avatarViewDataSource
        }
    }
    
    @State private var path: NavigationPath = NavigationPath()
    
    private enum Route: Hashable, Identifiable {
        case editGroupNameAndPicture
        
        var id: Self {
            return self
        }
    }

    /// A `CreationSession` instance keeps track of the user's choice during the successive steps of the group creation.
    final class CreationSession {
        
        let ownedCryptoId: ObvCryptoId
        let uuid = UUID()

        var userIdentifiersOfAddedUsers = [SelectUsersToAddViewModel.User.Identifier]()
        var selectedPhoto: UIImage?
        var selectedGroupName: String?
        var selectedGroupDescription: String?

        init(ownedCryptoId: ObvCryptoId) {
            self.ownedCryptoId = ownedCryptoId
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


extension GroupV1CreationNavigationStack: SelectUsersToAddViewActionsForCreation {
    
    public func userWantsToAddSelectedUsersToCreatingGroup(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddView.InternalView, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, withIdentifiers userIdentifiers: [ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier]) {
        creationSession.userIdentifiersOfAddedUsers = userIdentifiers
    }

}

extension GroupV1CreationNavigationStack: SelectUsersToAddViewNavigationForCreation {
    
    public func userDidFinishSelectingUsersToAddAndWantsToNavigateToNextScreen(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddView.InternalView) {
        path.append(Route.editGroupNameAndPicture)
    }
    
}


extension GroupV1CreationNavigationStack: EditGroupNameAndPictureViewNavigationDuringCreation {
    
    public func groupWasSuccessfullyCreated(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.InternalView, ownedCryptoId: ObvTypes.ObvCryptoId) {
        // Called after `userWantsToPublishCreatedGroupWithDetails`. At this point, we already made the request to create the group, so we only have to exit the group
        // creation flow.
        navigation.presentedGroupCreationFlowShouldBeDismissed(self)
    }
        
}


extension GroupV1CreationNavigationStack: EditGroupNameAndPictureViewActionsForCreation {
    
    public func userWantsToPublishCreatedGroupWithDetails(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.InternalView, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, groupDetails: ObvTypes.ObvGroupDetails) async throws {
        
        var otherGroupMembers = Set<ObvCryptoId>()
        for identifier in creationSession.userIdentifiersOfAddedUsers {
            let contactIdentifier = try await self.dataSources.groupV1CreationNavigationStackDataSource.getContactIdentifierOfGroupMember(self, contactIdentifier: identifier)
            guard contactIdentifier.ownedCryptoId == ownedCryptoId else { assertionFailure(); return }
            otherGroupMembers.insert(contactIdentifier.contactCryptoId)
        }
        
        try await actions.userWantsToPublishCreatedGroupV1(self, ownedCryptoId: ownedCryptoId, groupDetails: groupDetails, otherGroupMembers: otherGroupMembers)

    }
    
    
}


extension GroupV1CreationNavigationStack: EditGroupNameAndPictureViewActionsProtocol {
    
    public func userWantsObtainAvatar(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.InternalView, avatarSource: ObvAppTypes.ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return try await actions.userWantsObtainAvatarDuringGroupV1Creation(self, avatarSource: avatarSource, avatarSize: avatarSize)
    }
    
    public func userWantsToSaveImageToTempFile(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.InternalView, image: UIImage) async throws -> URL {
        return try await actions.userWantsToSaveImageToTempFileDuringGroupV1Creation(self, image: image)
    }
    
    
}
