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
import CoreData
import ObvCircleAndTitlesView
import ObvDesignSystem
import ObvTypes
import ObvAppTypes


@MainActor
protocol SingleGroupMemberViewActionsProtocol {
    func userWantsToInviteOtherUserToOneToOne(contactIdentifier: ObvContactIdentifier) async throws
    func userWantsToShowOtherUserProfile(contactIdentifier: ObvContactIdentifier) async
    func userWantsToRemoveOtherUserFromGroup(groupIdentifier: ObvGroupV2Identifier, contactIdentifier: ObvContactIdentifier) async throws
    func userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(creationSessionUUID: UUID, memberIdentifier: SingleGroupMemberViewModelIdentifier, newIsAnAdmin: Bool)
}

public enum SingleGroupMemberViewModelIdentifier: Hashable, Identifiable, Sendable {
    case contactIdentifierForExistingGroup(groupIdentifier: ObvGroupV2Identifier, contactIdentifier: ObvContactIdentifier)
    case contactIdentifierForCreatingGroup(contactIdentifier: ObvContactIdentifier)
    case objectIDOfPersistedGroupV2Member(groupIdentifier: ObvGroupV2Identifier, objectID: NSManagedObjectID) // Used when editing existing group
    case objectIDOfPersistedContact(objectID: NSManagedObjectID) // Used when creating a new group
    
    public var id: Data {
        switch self {
        case .contactIdentifierForExistingGroup(groupIdentifier: let groupIdentifier, contactIdentifier: let contactIdentifier):
            return groupIdentifier.ownedCryptoId.getIdentity() + groupIdentifier.identifier.appGroupIdentifier + contactIdentifier.contactCryptoId.getIdentity()
        case .contactIdentifierForCreatingGroup(contactIdentifier: let contactIdentifier):
            return contactIdentifier.ownedCryptoId.getIdentity() + contactIdentifier.contactCryptoId.getIdentity()
        case .objectIDOfPersistedGroupV2Member(groupIdentifier: _, objectID: let objectID):
            return objectID.uriRepresentation().dataRepresentation
        case .objectIDOfPersistedContact(objectID: let objectID):
            return objectID.uriRepresentation().dataRepresentation
        }
    }
    
    /// Nil when creating a group, non-nil when editing an existing group.
    public var groupIdentifier: ObvGroupV2Identifier? {
        switch self {
        case .contactIdentifierForExistingGroup(groupIdentifier: let groupIdentifier, _),
                .objectIDOfPersistedGroupV2Member(groupIdentifier: let groupIdentifier, _):
            return groupIdentifier
        case .contactIdentifierForCreatingGroup, .objectIDOfPersistedContact:
            return nil
        }
    }
    
}


@MainActor
protocol SingleGroupMemberViewDataSource {
    
    func getAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupMemberViewModel>)
    func finishAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier, streamUUID: UUID)
    
    func getAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<GroupLightweightModel>) // Not called when creating a group, only when editing an existing one
    func finishAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: ObvGroupV2Identifier, streamUUID: UUID)
    
    func getGroupLightweightModelDuringGroupCreation(creationSessionUUID: UUID) throws -> GroupLightweightModel // Only called when creating a group, not when editing an existing one
    
    func fetchAvatarImageForGroupMember(contactIdentifier: ObvContactIdentifier, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
    
}


public struct SingleGroupMemberViewModel: Sendable {
    
    let contactIdentifier: ObvContactIdentifier
    let isKeycloakManaged: Bool
    let profilePictureInitial: String?
    let circleColors: InitialCircleView.Model.Colors
    let identityDetails: ObvIdentityDetails
    let isOneToOneContact: IsOneToOneContact
    let isRevokedAsCompromised: Bool
    let permissions: Set<ObvGroupV2.Permission>
    let isPending: Bool
    let detailedProfileCanBeShown: Bool
    let customDisplayName: String?
    let customPhotoURL: URL?

    public enum IsOneToOneContact: Sendable {
        case yes
        case no(canSendOneToOneInvitation: Bool)
    }
    
    var isAdmin: Bool {
        permissions.contains(.groupAdmin)
    }
    
    public init(contactIdentifier: ObvContactIdentifier, permissions: Set<ObvGroupV2.Permission>, isKeycloakManaged: Bool, profilePictureInitial: String? = nil, circleColors: InitialCircleView.Model.Colors, identityDetails: ObvIdentityDetails, isOneToOneContact: IsOneToOneContact, isRevokedAsCompromised: Bool, isPending: Bool, detailedProfileCanBeShown: Bool, customDisplayName: String?, customPhotoURL: URL?) {
        self.contactIdentifier = contactIdentifier
        self.permissions = permissions
        self.isKeycloakManaged = isKeycloakManaged
        self.profilePictureInitial = profilePictureInitial
        self.circleColors = circleColors
        self.identityDetails = identityDetails
        self.isOneToOneContact = isOneToOneContact
        self.isRevokedAsCompromised = isRevokedAsCompromised
        self.isPending = isPending
        self.detailedProfileCanBeShown = detailedProfileCanBeShown
        self.customDisplayName = customDisplayName
        self.customPhotoURL = customPhotoURL
    }
    
    func withUpdatedGroupAdminPermissionSetTo(_ isAdmin: Bool) -> Self {
        switch (isAdmin, self.permissions.contains(.groupAdmin)) {
        case (false, false):
            return self
        case (false, true):
            let newPermission = self.permissions.filter({ $0 != .groupAdmin })
            return .init(contactIdentifier: self.contactIdentifier,
                         permissions: newPermission,
                         isKeycloakManaged: self.isKeycloakManaged,
                         profilePictureInitial: self.profilePictureInitial,
                         circleColors: self.circleColors,
                         identityDetails: self.identityDetails,
                         isOneToOneContact: self.isOneToOneContact,
                         isRevokedAsCompromised: self.isRevokedAsCompromised,
                         isPending: self.isPending,
                         detailedProfileCanBeShown: self.detailedProfileCanBeShown,
                         customDisplayName: self.customDisplayName,
                         customPhotoURL: self.customPhotoURL)
        case (true, false):
            let newPermission = Set(self.permissions + [.groupAdmin])
            return .init(contactIdentifier: self.contactIdentifier,
                         permissions: newPermission,
                         isKeycloakManaged: self.isKeycloakManaged,
                         profilePictureInitial: self.profilePictureInitial,
                         circleColors: self.circleColors,
                         identityDetails: self.identityDetails,
                         isOneToOneContact: self.isOneToOneContact,
                         isRevokedAsCompromised: self.isRevokedAsCompromised,
                         isPending: self.isPending,
                         detailedProfileCanBeShown: self.detailedProfileCanBeShown,
                         customDisplayName: self.customDisplayName,
                         customPhotoURL: self.customPhotoURL)
        case (true, true):
            return self
        }
    }
    
}


public struct GroupLightweightModel: Sendable {
    let ownedIdentityIsAdmin: Bool
    let groupType: ObvGroupType?
    let updateInProgressDuringGroupEdition: Bool // Always false during group creation
    let isKeycloakManaged: Bool
    
    public init(ownedIdentityIsAdmin: Bool, groupType: ObvGroupType?, updateInProgressDuringGroupEdition: Bool, isKeycloakManaged: Bool) {
        self.ownedIdentityIsAdmin = ownedIdentityIsAdmin
        self.groupType = groupType
        self.updateInProgressDuringGroupEdition = updateInProgressDuringGroupEdition
        self.isKeycloakManaged = isKeycloakManaged
    }
    
}

struct MemberIdentifierAndPermissions: Sendable, Hashable {
    let memberIdentifier: SingleGroupMemberViewModelIdentifier
    let cryptoId: ObvCryptoId
    let isAdmin: Bool
    func hash(into hasher: inout Hasher) {
        hasher.combine(memberIdentifier)
    }
}

struct SingleGroupMemberView: View {
    
    let mode: GroupMembersListMode
    let modelIdentifier: SingleGroupMemberViewModelIdentifier
    let dataSource: SingleGroupMemberViewDataSource
    let actions: SingleGroupMemberViewActionsProtocol
    @Binding var selectedMembers: Set<SingleGroupMemberViewModelIdentifier> // Must be a binding
    @Binding var hudCategory: HUDView.Category? // Must be a binding
    @Binding var membersWithUpdatedAdminPermission: Set<MemberIdentifierAndPermissions> // Must be a binding

    @State private var model: SingleGroupMemberViewModel?
    @State private var streamUUID: UUID?
    
    @State private var groupLightweightModel: GroupLightweightModel?
    @State private var groupLightweightModelStreamUUID: UUID?

    @State private var profilePicture: (url: URL, image: UIImage?)?
                    
    @Environment(\.editMode) private var editMode
    
    
    private var avatarSize: ObvDesignSystem.ObvAvatarSize {
        ObvDesignSystem.ObvAvatarSize.normal
    }
    
    
    private func updateProfilePictureIfRequired(model: SingleGroupMemberViewModel, photoURL: URL?) async {
        guard self.profilePicture?.url != photoURL else { return }
        guard let photoURL else {
            withAnimation {
                self.profilePicture = nil
            }
            return
        }
        self.profilePicture = (photoURL, nil)
        do {
            let image = try await dataSource.fetchAvatarImageForGroupMember(contactIdentifier: model.contactIdentifier, photoURL: photoURL, avatarSize: avatarSize)
            guard self.profilePicture?.url == photoURL else { return } // The fetched photo is outdated
            withAnimation {
                self.profilePicture = (photoURL, image)
            }
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }
    

    private func onAppear() {
        Task {
            do {
                
                switch mode {
                    
                case .listMembers, .removeMembers, .editAdmins:
                    
                    let (streamUUID, stream) = try dataSource.getAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier: modelIdentifier)
                    if let previousStreamUUID = self.streamUUID {
                        dataSource.finishAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier: modelIdentifier, streamUUID: previousStreamUUID)
                    }
                    self.streamUUID = streamUUID
                    for await model in stream {
                        if self.model == nil {
                            self.model = model
                        } else {
                            withAnimation { self.model = model }
                        }
                        Task { await updateProfilePictureIfRequired(model: model, photoURL: model.customPhotoURL ?? model.identityDetails.photoURL) }
                        if model.isAdmin {
                            // If the member becomes admin while we are editing the admins, remove any coherent (but obsolete) modification made locally
                            membersWithUpdatedAdminPermission.remove(.init(memberIdentifier: self.modelIdentifier, cryptoId: model.contactIdentifier.contactCryptoId, isAdmin: true))
                        } else {
                            // See above
                            membersWithUpdatedAdminPermission.remove(.init(memberIdentifier: self.modelIdentifier, cryptoId: model.contactIdentifier.contactCryptoId, isAdmin: false))
                        }
                    }
                    
                case .selectAdminsDuringGroupCreation(creationSessionUUID: _, ownedCryptoId: _, preSelectedAdmins: let preSelectedAdmins):
                    
                    let (streamUUID, stream) = try dataSource.getAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier: modelIdentifier)
                    if let previousStreamUUID = self.streamUUID {
                        dataSource.finishAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier: modelIdentifier, streamUUID: previousStreamUUID)
                    }
                    self.streamUUID = streamUUID
                    for await model in stream {
                        // The model returned by the datasource is not aware of pre-selected admins, so we augment the received model
                        let modelWithPreSelectedAdminStatus: SingleGroupMemberViewModel
                        if preSelectedAdmins.contains(self.modelIdentifier) {
                            modelWithPreSelectedAdminStatus = model.withUpdatedGroupAdminPermissionSetTo(true)
                        } else {
                            modelWithPreSelectedAdminStatus = model.withUpdatedGroupAdminPermissionSetTo(false)
                        }
                        if self.model == nil {
                            self.model = modelWithPreSelectedAdminStatus
                        } else {
                            withAnimation { self.model = modelWithPreSelectedAdminStatus }
                        }
                        Task { await updateProfilePictureIfRequired(model: model, photoURL: model.customPhotoURL ?? model.identityDetails.photoURL) }
                    }

                    
                }
                
            } catch {
                assertionFailure()
            }
        }
        Task {
            
            switch mode {
            case .listMembers(groupIdentifier: let groupIdentifier),
                    .removeMembers(groupIdentifier: let groupIdentifier),
                    .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _):
                
                do {
                    let (streamUUID, stream) = try dataSource.getAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: groupIdentifier)
                    if let previousStreamUUID = self.groupLightweightModelStreamUUID {
                        dataSource.finishAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: groupIdentifier, streamUUID: previousStreamUUID)
                    }
                    self.groupLightweightModelStreamUUID = streamUUID
                    for await model in stream {
                        if self.groupLightweightModel == nil {
                            self.groupLightweightModel = model
                        } else {
                            withAnimation { self.groupLightweightModel = model }
                        }
                    }
                } catch {
                    assertionFailure()
                }

            case .selectAdminsDuringGroupCreation(creationSessionUUID: let creationSessionUUID, ownedCryptoId: _, preSelectedAdmins: _):
                
                do {
                    let model = try dataSource.getGroupLightweightModelDuringGroupCreation(creationSessionUUID: creationSessionUUID)
                    if self.groupLightweightModel == nil {
                        self.groupLightweightModel = model
                    } else {
                        withAnimation { self.groupLightweightModel = model }
                    }
                } catch {
                    assertionFailure()
                }

            }

        }
    }
    
    
    private func onDisappear() {
        if let streamUUID = self.streamUUID {
            dataSource.finishAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier: modelIdentifier, streamUUID: streamUUID)
            self.streamUUID = nil
        }
        switch mode {
        case .listMembers(groupIdentifier: let groupIdentifier),
                .removeMembers(groupIdentifier: let groupIdentifier),
                .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _):
            if let streamUUID = self.groupLightweightModelStreamUUID {
                // We are in the listMembers, removeMembers, or editAdmins mode for an existing group.
                // This is not called in the selectAdminsDuringGroupCreation during the creation of a new group.
                dataSource.finishAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: groupIdentifier, streamUUID: streamUUID)
                self.groupLightweightModelStreamUUID = nil
            }
        case .selectAdminsDuringGroupCreation:
            break
        }
    }
    
    
    var body: some View {
        InternalView(mode: mode,
                     modelIdentifier: modelIdentifier,
                     avatarSize: avatarSize,
                     model: model,
                     groupLightweightModel: groupLightweightModel,
                     selectedMembers: $selectedMembers,
                     profilePicture: profilePicture,
                     hudCategory: $hudCategory,
                     membersWithUpdatedAdminPermission: $membersWithUpdatedAdminPermission,
                     actions: actions)
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
    }

    
    private struct InternalView: View {
        
        let mode: GroupMembersListMode
        let modelIdentifier: SingleGroupMemberViewModelIdentifier
        let avatarSize: ObvDesignSystem.ObvAvatarSize
        let model: SingleGroupMemberViewModel?
        let groupLightweightModel: GroupLightweightModel?
        @Binding var selectedMembers: Set<SingleGroupMemberViewModelIdentifier> // Must be a binding
        let profilePicture: (url: URL, image: UIImage?)?
        @Binding var hudCategory: HUDView.Category? // Must be a binding
        @Binding var membersWithUpdatedAdminPermission: Set<MemberIdentifierAndPermissions> // Must be a binding
        let actions: SingleGroupMemberViewActionsProtocol

        @State private var showDialog: Bool = false
        @State private var showRemoveFromGroupAlert: Bool = false

        private var isSelected: Bool {
            selectedMembers.contains(self.modelIdentifier)
        }

        private func performButtonAction() {
            switch mode {
            case .editAdmins, .selectAdminsDuringGroupCreation:
                return
            case .listMembers:
                showDialog = true
            case .removeMembers:
                if isSelected {
                    withAnimation {
                        _ = selectedMembers.remove(self.modelIdentifier)
                    }
                } else {
                    withAnimation {
                        _ = selectedMembers.insert(self.modelIdentifier)
                    }
                }
            }
        }

        private func profilePictureViewModelContent(model: SingleGroupMemberViewModel) -> ProfilePictureView.Model.Content {
            .init(text: model.profilePictureInitial,
                  icon: .person,
                  profilePicture: profilePicture?.image,
                  showGreenShield: model.isKeycloakManaged,
                  showRedShield: model.isRevokedAsCompromised)
        }

        private func profilePictureViewModel(model: SingleGroupMemberViewModel) -> ProfilePictureView.Model {
            .init(content: profilePictureViewModelContent(model: model),
                  colors: model.circleColors,
                  circleDiameter: avatarSize.frameSize.width)
        }

        private func textViewModel(model: SingleGroupMemberViewModel) -> TextView.Model {
            let coreDetails = model.identityDetails.coreDetails
            if let customDisplayName = model.customDisplayName, !customDisplayName.isEmpty {
                return .init(titlePart1: nil,
                             titlePart2: customDisplayName,
                             subtitle: coreDetails.getDisplayNameWithStyle(.firstNameThenLastName),
                             subsubtitle: coreDetails.getDisplayNameWithStyle(.positionAtCompany))
            } else {
                return .init(titlePart1: coreDetails.firstName,
                             titlePart2: coreDetails.lastName,
                             subtitle: coreDetails.position,
                             subsubtitle: coreDetails.company)
            }
        }

        private func userTappedShowProfile(model: SingleGroupMemberViewModel) {
            Task {
                await actions.userWantsToShowOtherUserProfile(contactIdentifier: model.contactIdentifier)
            }
        }
        
        private func canShowOneToOneInvitationButton(isOneToOneContact: SingleGroupMemberViewModel.IsOneToOneContact) -> Bool {
            switch isOneToOneContact {
            case .yes:
                return false
            case .no(canSendOneToOneInvitation: let canSendOneToOneInvitation):
                return canSendOneToOneInvitation
            }
        }
        
        private func userTappedInviteToOneToOne(model: SingleGroupMemberViewModel) {
            Task {
                do {
                    try await actions.userWantsToInviteOtherUserToOneToOne(contactIdentifier: model.contactIdentifier)
                    hudCategory = .checkmark
                } catch {
                    hudCategory = .xmark
                    assertionFailure()
                }
                try? await Task.sleep(seconds: 1)
                hudCategory = nil
            }
        }

        private func userTappedRemoveFromGroup(model: SingleGroupMemberViewModel) {
            switch mode {
            case .listMembers(groupIdentifier: let groupIdentifier),
                    .removeMembers(groupIdentifier: let groupIdentifier):
                Task {
                    do {
                        try await actions.userWantsToRemoveOtherUserFromGroup(groupIdentifier: groupIdentifier, contactIdentifier: model.contactIdentifier)
                    } catch {
                        assertionFailure()
                    }
                }
            case .editAdmins, .selectAdminsDuringGroupCreation:
                assertionFailure("The button is only shown in listMembers and removeMembers mode. So this is unexpected.")
                return
            }
        }

        private func showIsAdminLabel(model: SingleGroupMemberViewModel) -> Bool {
            //if model.isAdmin && mode != .editAdmins
            guard model.isAdmin else { return false }
            switch mode {
            case .listMembers, .removeMembers:
                return true
            case .editAdmins, .selectAdminsDuringGroupCreation:
                return false
            }
        }

        private func getToggleIsAndAdmin(model: SingleGroupMemberViewModel) -> Bool {
            if let memberIdentifierAndPermissions = self.membersWithUpdatedAdminPermission.first(where: { $0.memberIdentifier == self.modelIdentifier }) {
                return memberIdentifierAndPermissions.isAdmin
            } else {
                return model.isAdmin
            }
        }

        private func setToggleIsAndAdmin(model: SingleGroupMemberViewModel, newIsAnAdmin: Bool) {
            
            if let memberIdentifierAndPermissions = self.membersWithUpdatedAdminPermission.first(where: { $0.memberIdentifier == self.modelIdentifier }) {
                self.membersWithUpdatedAdminPermission.remove(memberIdentifierAndPermissions)
            }
            
            if newIsAnAdmin != model.isAdmin {
                self.membersWithUpdatedAdminPermission.insert(.init(memberIdentifier: self.modelIdentifier, cryptoId: model.contactIdentifier.contactCryptoId, isAdmin: newIsAnAdmin))
            }

            switch mode {
            case .listMembers, .removeMembers, .editAdmins:
                break
            case .selectAdminsDuringGroupCreation(creationSessionUUID: let creationSessionUUID, ownedCryptoId: _, preSelectedAdmins: _):
                // During a group creating, we immediately notify the router when an admin is added/removed, so as to keep the setting in memory
                // This allows to receive an up-to-date set of pre-selected admins even in the case where the user selects a few admins, hits the back button,
                // changes the group type, and re-open a new screen allowing to choose admins.
                actions.userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(creationSessionUUID: creationSessionUUID, memberIdentifier: self.modelIdentifier, newIsAnAdmin: newIsAnAdmin)
            }
            
        }

        var body: some View {
            
            if let model = self.model, let groupLightweightModel = self.groupLightweightModel {
                
                switch mode {
                    
                case .listMembers:
                    
                    Button(action: performButtonAction) {
                        HStack {
                            ProfilePictureView(model: profilePictureViewModel(model: model))
                            TextView(model: textViewModel(model: model))
                            Spacer()
                            VStack {
                                if model.isPending {
                                    Text("PENDING")
                                }
                                if model.isAdmin {
                                    Text("ADMIN")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .tint(.secondary)
                            if model.detailedProfileCanBeShown {
                                ObvChevronRight()
                            }
                        }
                    }
                    .confirmationDialog(Text("WHAT_DO_YOU_WANT_TO_DO_WITH_THIS_USER"), isPresented: $showDialog) {
                        if model.detailedProfileCanBeShown {
                            Button(String(localizedInThisBundle: "SHOW_PROFILE"), role: .none, action: { userTappedShowProfile(model: model) })
                        }
                        if canShowOneToOneInvitationButton(isOneToOneContact: model.isOneToOneContact) {
                            Button(String(localizedInThisBundle: "INVITE_USER_TO_ONE_TO_ONE"), role: .none, action: { userTappedInviteToOneToOne(model: model) })
                        }
                        if groupLightweightModel.ownedIdentityIsAdmin {
                            Button(String(localizedInThisBundle: "REMOVE_USER_FROM_GROUP"), role: .destructive, action: { showRemoveFromGroupAlert = true })
                        }
                    }
                    .alert(String(localizedInThisBundle: "ARE_YOU_SURE_YOU_WANT_TO_REMOVE_\(model.identityDetails.getDisplayNameWithStyle(.firstNameThenLastName))_FROM_THIS_GROUP"), isPresented: $showRemoveFromGroupAlert) {
                        Button(String(localizedInThisBundle: "REMOVE_USER_FROM_GROUP"), role: .destructive, action: { userTappedRemoveFromGroup(model: model) })
                    }
                    
                case .removeMembers:
                    
                    Button(action: performButtonAction) {
                        HStack {
                            ProfilePictureView(model: profilePictureViewModel(model: model))
                            TextView(model: textViewModel(model: model))
                            Spacer()
                            //Image(systemIcon: isSelected ? .checkmarkCircleFill : .circle)
                            Image(systemIcon: isSelected ? .personCropCircleFillBadgeMinus : .circle)
                                .font(.system(size: 20))
                                .foregroundStyle(isSelected ? .red : .secondary)
                                .animation(nil, value: isSelected)
                        }
                    }
                    .alert(String(localizedInThisBundle: "ARE_YOU_SURE_YOU_WANT_TO_REMOVE_\(model.identityDetails.getDisplayNameWithStyle(.firstNameThenLastName))_FROM_THIS_GROUP"), isPresented: $showRemoveFromGroupAlert) {
                        Button(String(localizedInThisBundle: "REMOVE_USER_FROM_GROUP"), role: .destructive, action: { userTappedRemoveFromGroup(model: model) })
                    }
                    
                case .editAdmins, .selectAdminsDuringGroupCreation:
                    
                    HStack {
                        ProfilePictureView(model: profilePictureViewModel(model: model))
                        TextView(model: textViewModel(model: model))
                        Spacer()
                        if showIsAdminLabel(model: model) {
                            Text("ADMIN")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .tint(.secondary)
                        }
                        VStack(alignment: .trailing) {
                            Toggle(String("IS_AN_ADMIN"), isOn: .init(
                                get: {
                                    getToggleIsAndAdmin(model: model)
                                }, set: { newIsAnAdmin in
                                    setToggleIsAndAdmin(model: model, newIsAnAdmin: newIsAnAdmin)
                                }))
                            .labelsHidden()
                            Text(getToggleIsAndAdmin(model: model) ? "IS_ADMIN" : "IS_NOT_ADMIN")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                }
                
            } else {
                
                PlaceholderForUserCell(avatarSize: avatarSize)
                                
            }
        }
        
    }
    
}

// MARK: - Previews

#if DEBUG

private final class ActionsForPreviews: SingleGroupMemberViewActionsProtocol {
    
    private var index = 0
    
    func userWantsToInviteOtherUserToOneToOne(contactIdentifier: ObvContactIdentifier) async throws {
        // Nothing to simulate
    }
    
    func userWantsToShowOtherUserProfile(contactIdentifier: ObvTypes.ObvContactIdentifier) async {
        // Nothing to simulate
    }
    
    func userWantsToRemoveOtherUserFromGroup(groupIdentifier: ObvGroupV2Identifier, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        // Nothing to simulate
    }
    
    func userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(creationSessionUUID: UUID, memberIdentifier: SingleGroupMemberViewModelIdentifier, newIsAnAdmin: Bool) {
        // Nothing to simulate
    }
    
}


private final class DataSourceForPreviews: SingleGroupMemberViewDataSource {

    func getAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupMemberViewModel>) {
        let stream = AsyncStream(SingleGroupMemberViewModel.self) { (continuation: AsyncStream<SingleGroupMemberViewModel>.Continuation) in
            assert(identifier == .contactIdentifierForExistingGroup(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0],
                                                                    contactIdentifier: PreviewsHelper.groupMembers[2].contactIdentifier))
            continuation.yield(PreviewsHelper.groupMembers[2])
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier, streamUUID: UUID) {
        // Nothing to finish in these previews
    }
 
    
    func getGroupLightweightModelDuringGroupCreation(creationSessionUUID: UUID) throws -> GroupLightweightModel {
        return GroupLightweightModel(ownedIdentityIsAdmin: true, groupType: .standard, updateInProgressDuringGroupEdition: false, isKeycloakManaged: false)
    }
    
    
    func getAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<GroupLightweightModel>) {
        let stream = AsyncStream(GroupLightweightModel.self) { (continuation: AsyncStream<GroupLightweightModel>.Continuation) in
            continuation.yield(.init(ownedIdentityIsAdmin: true, groupType: .standard, updateInProgressDuringGroupEdition: false, isKeycloakManaged: false))
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, streamUUID: UUID) {
        // Nothing to finish in these previews
    }
    

    func fetchAvatarImageForGroupMember(contactIdentifier: ObvContactIdentifier, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.profilePictureForURL[photoURL]
    }
    
}


@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

@MainActor
private let actions = ActionsForPreviews()

@MainActor
private let modelForPreview =  PreviewsHelper.groupMembers[2]

#Preview {
    SingleGroupMemberView(mode: .listMembers(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0]),
                             modelIdentifier: .contactIdentifierForExistingGroup(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0],
                                                                                 contactIdentifier: PreviewsHelper.groupMembers[2].contactIdentifier),
                             dataSource: dataSourceForPreviews,
                             actions: actions,
                             selectedMembers: .constant([]),
                             hudCategory: .constant(nil),
                             membersWithUpdatedAdminPermission: .constant([]))
}

private struct PreviewWithRemove: View {
    
    @State private var selectedMembers: Set<SingleGroupMemberViewModelIdentifier> = []

    var body: some View {
        SingleGroupMemberView(mode: .removeMembers(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0]),
                                 modelIdentifier: .contactIdentifierForExistingGroup(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0],
                                                                     contactIdentifier: PreviewsHelper.groupMembers[2].contactIdentifier),
                                 dataSource: dataSourceForPreviews,
                                 actions: actions,
                                 selectedMembers: $selectedMembers,
                                 hudCategory: .constant(nil),
                                 membersWithUpdatedAdminPermission: .constant([]))
    }
}

#Preview("Remove") {
    PreviewWithRemove()
}


private struct PreviewWithEditAdmins: View {
    
    @State private var membersWithUpdatedAdminPermission: Set<MemberIdentifierAndPermissions> = []

    var body: some View {
        SingleGroupMemberView(mode: .editAdmins(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0], selectedGroupType: nil),
                                 modelIdentifier: .contactIdentifierForExistingGroup(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0],
                                                                                     contactIdentifier: PreviewsHelper.groupMembers[2].contactIdentifier),
                                 dataSource: dataSourceForPreviews,
                                 actions: actions,
                                 selectedMembers: .constant([]),
                                 hudCategory: .constant(nil),
                                 membersWithUpdatedAdminPermission: $membersWithUpdatedAdminPermission)
    }
}

#Preview("Edit Admins") {
    PreviewWithEditAdmins()
}


@MainActor
private final class DataSourceForPreviewsWithUpdate: SingleGroupMemberViewDataSource {

    func getAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupMemberViewModel>) {
        let stream = AsyncStream(SingleGroupMemberViewModel.self) { (continuation: AsyncStream<SingleGroupMemberViewModel>.Continuation) in
            Task {
                assert(identifier == .contactIdentifierForExistingGroup(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0],
                                                                        contactIdentifier: PreviewsHelper.groupMembers[2].contactIdentifier))
                continuation.yield(PreviewsHelper.groupMembers[2])
                try! await Task.sleep(seconds: 5)
                continuation.yield(PreviewsHelper.groupMembers[1]) // This changes the user identifier, which would not happen in practice
            }
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier, streamUUID: UUID) {
        // Nothing to finish within these previews
    }
    
    
    func getGroupLightweightModelDuringGroupCreation(creationSessionUUID: UUID) throws -> GroupLightweightModel {
        return GroupLightweightModel(ownedIdentityIsAdmin: true, groupType: .standard, updateInProgressDuringGroupEdition: false, isKeycloakManaged: false)
    }

    
    func getAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<GroupLightweightModel>) {
        let stream = AsyncStream(GroupLightweightModel.self) { (continuation: AsyncStream<GroupLightweightModel>.Continuation) in
            continuation.yield(.init(ownedIdentityIsAdmin: true, groupType: .standard, updateInProgressDuringGroupEdition: false, isKeycloakManaged: false))
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, streamUUID: UUID) {
        // Nothing to finish in these previews
    }

    
    func fetchAvatarImageForGroupMember(contactIdentifier: ObvContactIdentifier, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.profilePictureForURL[photoURL]
    }
    
}

@MainActor
private let dataSourceForPreviewsWithUpdate = DataSourceForPreviewsWithUpdate()


#Preview("With update") {
    SingleGroupMemberView(mode: .listMembers(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0]),
                             modelIdentifier: .contactIdentifierForExistingGroup(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0],
                                                                                 contactIdentifier: PreviewsHelper.groupMembers[2].contactIdentifier),
                             dataSource: dataSourceForPreviewsWithUpdate,
                             actions: actions,
                             selectedMembers: .constant([]),
                             hudCategory: .constant(nil),
                             membersWithUpdatedAdminPermission: .constant([]))
}

#endif
