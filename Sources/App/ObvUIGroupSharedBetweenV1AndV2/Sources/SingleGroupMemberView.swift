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
public protocol SingleGroupMemberViewDataSource {
    func getAsyncSequenceOfSingleGroupMemberViewModels(_ view: SingleGroupMemberView, withIdentifier identifier: SingleGroupMemberView.Model.Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupMemberView.Model>)
    func finishAsyncSequenceOfSingleGroupMemberViewModels(_ view: SingleGroupMemberView, withIdentifier identifier: SingleGroupMemberView.Model.Identifier, streamUUID: UUID)
}


@MainActor
public protocol SingleGroupMemberViewActionsProtocol: SelectUsersToAddViewActionsForEdition {}


@MainActor
public protocol SingleGroupMemberViewNavigation {
    func userWantsToShowOtherUserProfile(_ view: SingleGroupMemberView.InternalView, contactIdentifier: ObvContactIdentifier) async
}


@MainActor
public protocol SingleGroupMemberViewActionsDuringCreation {
    func userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(_ view: SingleGroupMemberView.InternalView, creationSessionUUID: UUID, memberIdentifier: SingleGroupMemberView.Model.Identifier, newIsAnAdmin: Bool)
}






public struct MemberIdentifierAndPermissions: Sendable, Hashable {
    public let memberIdentifier: SingleGroupMemberView.Model.Identifier
    public let cryptoId: ObvCryptoId
    public let isAdmin: Bool
    public func hash(into hasher: inout Hasher) {
        hasher.combine(memberIdentifier)
    }
}


public struct SingleGroupMemberView: View {
    
    let mode: Mode
    let modelIdentifier: Model.Identifier
    let dataSource: SingleGroupMemberViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    @Binding var selectedMembers: Set<Model.Identifier> // Must be a binding
    @Binding var membersWithUpdatedAdminPermission: Set<MemberIdentifierAndPermissions> // Must be a binding

    public init(mode: SingleGroupMemberView.Mode, modelIdentifier: Model.Identifier, dataSource: SingleGroupMemberViewDataSource, avatarViewDataSource: ObvAvatarViewDataSource, selectedMembers: Binding<Set<Model.Identifier>>, membersWithUpdatedAdminPermission: Binding<Set<MemberIdentifierAndPermissions>>) {
        self.mode = mode
        self.modelIdentifier = modelIdentifier
        self.dataSource = dataSource
        self._selectedMembers = selectedMembers
        self._membersWithUpdatedAdminPermission = membersWithUpdatedAdminPermission
        self.avatarViewDataSource = avatarViewDataSource
    }
    
    public struct Model: Sendable, Equatable {
        
        public let contactIdentifier: ObvContactIdentifier
        let isKeycloakManaged: Bool
        let profilePictureInitial: String?
        let circleColors: InitialCircleView.Model.Colors
        let identityDetails: ObvIdentityDetails
        let isOneToOneContact: IsOneToOneContact
        let isRevokedAsCompromised: Bool
        public let isGroupAdmin: Bool
        let isPending: Bool
        let detailedProfileCanBeShown: Bool
        let customDisplayName: String?
        let customPhotoURL: URL?

        public enum IsOneToOneContact: Sendable, Equatable {
            case yes
            case no(canSendOneToOneInvitation: Bool)
        }
        
        public init(contactIdentifier: ObvContactIdentifier, isGroupAdmin: Bool, isKeycloakManaged: Bool, profilePictureInitial: String? = nil, circleColors: InitialCircleView.Model.Colors, identityDetails: ObvIdentityDetails, isOneToOneContact: IsOneToOneContact, isRevokedAsCompromised: Bool, isPending: Bool, detailedProfileCanBeShown: Bool, customDisplayName: String?, customPhotoURL: URL?) {
            self.contactIdentifier = contactIdentifier
            self.isGroupAdmin = isGroupAdmin
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
        
        func withUpdatedGroupAdminPermissionSetTo(_ newIsGroupAdmin: Bool) -> Self {
            return .init(contactIdentifier: self.contactIdentifier,
                         isGroupAdmin: newIsGroupAdmin,
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
        }
        
        public enum Identifier: Hashable, Identifiable, Sendable {
            case contactIdentifierForExistingGroupForPreviews(groupIdentifier: ObvGroupIdentifier, contactIdentifier: ObvContactIdentifier)
            case contactIdentifierForCreatingGroupForPreviews(contactIdentifier: ObvContactIdentifier) // Used when testing group creation
            case objectIDOfPersistedGroupV2Member(groupIdentifier: ObvGroupV2Identifier, objectID: NSManagedObjectID) // Used when editing existing group
            case objectIDOfPersistedContact(objectID: NSManagedObjectID, usageContext: UsageContext) // Also used when creating a new group
            case objectIDOfPersistedPendingGroupMember(objectID: NSManagedObjectID) // Used when a GroupV1 pending member has yet to become a contact
            
            public enum UsageContext: Sendable, Equatable, Hashable, Identifiable {
                case groupCreation
                case groupV1Display(groupV1Identifier: ObvGroupV1Identifier)
                public var id: Data {
                    switch self {
                    case .groupCreation:
                        return Data(repeating: 0x00, count: 1)
                    case .groupV1Display(groupV1Identifier: let groupV1Identifier):
                        return Data(repeating: 0x00, count: 1) + groupV1Identifier.id
                    }
                }
            }
            
            public var id: Data {
                switch self {
                case .contactIdentifierForExistingGroupForPreviews(groupIdentifier: let groupIdentifier, contactIdentifier: let contactIdentifier):
                    return groupIdentifier.id + contactIdentifier.id
                case .contactIdentifierForCreatingGroupForPreviews(contactIdentifier: let contactIdentifier):
                    return contactIdentifier.id + contactIdentifier.id
                case .objectIDOfPersistedGroupV2Member(groupIdentifier: _, objectID: let objectID):
                    return objectID.uriRepresentation().dataRepresentation
                case .objectIDOfPersistedContact(objectID: let objectID, usageContext: let usageContext):
                    return objectID.uriRepresentation().dataRepresentation + usageContext.id
                case .objectIDOfPersistedPendingGroupMember(objectID: let objectID):
                    return objectID.uriRepresentation().dataRepresentation
                }
            }
            
            /// Nil when creating a group, non-nil when editing an existing group.
            public var groupIdentifier: ObvGroupIdentifier? {
                switch self {
                case .contactIdentifierForExistingGroupForPreviews(groupIdentifier: let groupIdentifier, _):
                    return groupIdentifier
                case .objectIDOfPersistedGroupV2Member(groupIdentifier: let groupIdentifier, _):
                    return .groupV2(groupIdentifier)
                case .contactIdentifierForCreatingGroupForPreviews, .objectIDOfPersistedContact:
                    return nil
                case .objectIDOfPersistedPendingGroupMember:
                    return nil
                }
            }
            
            public var groupV2Identifier: ObvGroupV2Identifier? {
                switch groupIdentifier {
                case .groupV1:
                    return nil
                case .groupV2(let obvGroupV2Identifier):
                    return obvGroupV2Identifier
                case nil:
                    return nil
                }
            }
            
        }

    }

    public enum Mode {
        case listMembers(groupIdentifier: ObvGroupIdentifier, commonActions: any SingleGroupMemberViewActionsProtocol, navigation: SingleGroupMemberViewNavigation)
        case removeMembers(groupIdentifier: ObvGroupIdentifier)
        case editAdmins(groupIdentifier: ObvGroupV2Identifier)
        case selectAdminsDuringGroupCreation(creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, preSelectedAdmins: Set<Model.Identifier>, actionsForCreation: SingleGroupMemberViewActionsDuringCreation)
    }

    @State private var model: Model?

    @State private var profilePicture: (url: URL, image: UIImage?)?
                    
    @Environment(\.editMode) private var editMode
    
    
    private var avatarSize: ObvDesignSystem.ObvAvatarSize {
        ObvDesignSystem.ObvAvatarSize.normal
    }
    
    
    private func updateProfilePictureIfRequired(model: Model, photoURL: URL?) async {
        guard self.profilePicture?.url != photoURL else { return }
        guard let photoURL else {
            withAnimation {
                self.profilePicture = nil
            }
            return
        }
        self.profilePicture = (photoURL, nil)
        do {
            let image = try await avatarViewDataSource.fetchAvatarForLegacyViews(photoURL: photoURL, avatarSize: avatarSize)
            guard self.profilePicture?.url == photoURL else { return } // The fetched photo is outdated
            withAnimation {
                self.profilePicture = (photoURL, image)
            }
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }
    

    private func onTaskForAsyncSequenceOfSingleGroupMemberViewModels() async {
        do {
            
            switch mode {
                
            case .listMembers, .removeMembers, .editAdmins:
                
                let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfSingleGroupMemberViewModels(self, withIdentifier: modelIdentifier)
                
                for await model in stream {
                    if self.model == nil {
                        self.model = model
                    } else {
                        withAnimation { self.model = model }
                    }
                    Task { await updateProfilePictureIfRequired(model: model, photoURL: model.customPhotoURL ?? model.identityDetails.photoURL) }
                    if model.isGroupAdmin {
                        // If the member becomes admin while we are editing the admins, remove any coherent (but obsolete) modification made locally
                        membersWithUpdatedAdminPermission.remove(.init(memberIdentifier: self.modelIdentifier, cryptoId: model.contactIdentifier.contactCryptoId, isAdmin: true))
                    } else {
                        // See above
                        membersWithUpdatedAdminPermission.remove(.init(memberIdentifier: self.modelIdentifier, cryptoId: model.contactIdentifier.contactCryptoId, isAdmin: false))
                    }
                }
                
                dataSource.finishAsyncSequenceOfSingleGroupMemberViewModels(self, withIdentifier: modelIdentifier, streamUUID: streamUUID)

            case .selectAdminsDuringGroupCreation(creationSessionUUID: _, ownedCryptoId: _, preSelectedAdmins: let preSelectedAdmins, actionsForCreation: _):
                
                let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfSingleGroupMemberViewModels(self, withIdentifier: modelIdentifier)

                for await model in stream {
                    // The model returned by the datasource is not aware of pre-selected admins, so we augment the received model
                    let modelWithPreSelectedAdminStatus: Model
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
                
                dataSource.finishAsyncSequenceOfSingleGroupMemberViewModels(self, withIdentifier: modelIdentifier, streamUUID: streamUUID)

            }
        } catch {
            // This happens when comming back to this view after a group member was removed from the group.
            // In that case, we receive a SingleGroupMemberViewModelStreamManagerForGroupEdition.ObvError.couldNotFindGroupMember
        }
    }
    
    
    public var body: some View {
        InternalView(mode: mode,
                     modelIdentifier: modelIdentifier,
                     avatarSize: avatarSize,
                     model: model,
                     selectedMembers: $selectedMembers,
                     profilePicture: profilePicture,
                     membersWithUpdatedAdminPermission: $membersWithUpdatedAdminPermission)
        .task(onTaskForAsyncSequenceOfSingleGroupMemberViewModels)
    }

    
    public struct InternalView: View {
        
        let mode: SingleGroupMemberView.Mode
        let modelIdentifier: Model.Identifier
        let avatarSize: ObvDesignSystem.ObvAvatarSize
        let model: Model?
        @Binding var selectedMembers: Set<Model.Identifier> // Must be a binding
        let profilePicture: (url: URL, image: UIImage?)?
        @Binding var membersWithUpdatedAdminPermission: Set<MemberIdentifierAndPermissions> // Must be a binding

        private var isSelected: Bool {
            selectedMembers.contains(self.modelIdentifier)
        }

        private func performButtonAction() {
            switch mode {
            case .editAdmins, .selectAdminsDuringGroupCreation:
                return
            case .listMembers(groupIdentifier: _, commonActions: _, navigation: let navigation):
                if let model, model.detailedProfileCanBeShown {
                    Task {
                        await navigation.userWantsToShowOtherUserProfile(self, contactIdentifier: model.contactIdentifier)
                    }
                }
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

        private func profilePictureViewModelContent(model: Model) -> ProfilePictureView.Model.Content {
            .init(text: model.profilePictureInitial,
                  icon: .person,
                  profilePicture: profilePicture?.image,
                  showGreenShield: model.isKeycloakManaged,
                  showRedShield: model.isRevokedAsCompromised)
        }

        private func profilePictureViewModel(model: Model) -> ProfilePictureView.Model {
            .init(content: profilePictureViewModelContent(model: model),
                  colors: model.circleColors,
                  circleDiameter: avatarSize.frameSize.width)
        }

        private func textViewModel(model: Model) -> TextView.Model {
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


        private func canShowOneToOneInvitationButton(isOneToOneContact: Model.IsOneToOneContact) -> Bool {
            switch isOneToOneContact {
            case .yes:
                return false
            case .no(canSendOneToOneInvitation: let canSendOneToOneInvitation):
                return canSendOneToOneInvitation
            }
        }
        
        private func showIsAdminLabel(model: Model) -> Bool {
            guard model.isGroupAdmin else { return false }
            switch mode {
            case .listMembers, .removeMembers:
                return true
            case .editAdmins, .selectAdminsDuringGroupCreation:
                return false
            }
        }

        private func getToggleIsAndAdmin(model: Model) -> Bool {
            if let memberIdentifierAndPermissions = self.membersWithUpdatedAdminPermission.first(where: { $0.memberIdentifier == self.modelIdentifier }) {
                return memberIdentifierAndPermissions.isAdmin
            } else {
                return model.isGroupAdmin
            }
        }

        private func setToggleIsAndAdmin(model: Model, newIsAnAdmin: Bool) {
            
            if let memberIdentifierAndPermissions = self.membersWithUpdatedAdminPermission.first(where: { $0.memberIdentifier == self.modelIdentifier }) {
                self.membersWithUpdatedAdminPermission.remove(memberIdentifierAndPermissions)
            }
            
            if newIsAnAdmin != model.isGroupAdmin {
                self.membersWithUpdatedAdminPermission.insert(.init(memberIdentifier: self.modelIdentifier, cryptoId: model.contactIdentifier.contactCryptoId, isAdmin: newIsAnAdmin))
            }

            switch mode {
            case .listMembers, .removeMembers, .editAdmins:
                break
            case .selectAdminsDuringGroupCreation(creationSessionUUID: let creationSessionUUID, ownedCryptoId: _, preSelectedAdmins: _, actionsForCreation: let actionsForCreation):
                // During a group creating, we immediately notify the router when an admin is added/removed, so as to keep the setting in memory
                // This allows to receive an up-to-date set of pre-selected admins even in the case where the user selects a few admins, hits the back button,
                // changes the group type, and re-open a new screen allowing to choose admins.
                actionsForCreation.userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(self, creationSessionUUID: creationSessionUUID, memberIdentifier: self.modelIdentifier, newIsAnAdmin: newIsAnAdmin)
            }
            
        }

        public var body: some View {
            
            if let model = self.model {
                
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
                                if model.isGroupAdmin {
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
                    
                case .removeMembers:
                    
                    Button(action: performButtonAction) {
                        HStack {
                            ProfilePictureView(model: profilePictureViewModel(model: model))
                            TextView(model: textViewModel(model: model))
                            Spacer()
                            Image(systemIcon: isSelected ? .personCropCircleFillBadgeMinus : .circle)
                                .font(.system(size: 20))
                                .foregroundStyle(isSelected ? .red : .secondary)
                                .animation(nil, value: isSelected)
                        }
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

private final class ActionsForPreviews {}

extension ActionsForPreviews: SelectUsersToAddViewActionsForEdition {
    func userWantsToAddSelectedUsersToExistingGroup(_ view: SelectUsersToAddView.InternalView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) async throws {}
}


extension ActionsForPreviews: SingleGroupMemberViewActionsProtocol {
}

extension ActionsForPreviews: SingleGroupMemberViewNavigation {
    func userWantsToShowOtherUserProfile(_ view: SingleGroupMemberView.InternalView, contactIdentifier: ObvTypes.ObvContactIdentifier) async {}
}

@MainActor
private final class DataSourceForPreviews {}

extension DataSourceForPreviews: SingleGroupMemberViewDataSource {

    func getAsyncSequenceOfSingleGroupMemberViewModels(_ view: SingleGroupMemberView, withIdentifier identifier: SingleGroupMemberView.Model.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupMemberView.Model>) {
        let stream = AsyncStream(SingleGroupMemberView.Model.self) { (continuation: AsyncStream<SingleGroupMemberView.Model>.Continuation) in
            assert(identifier == .contactIdentifierForExistingGroupForPreviews(groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
                                                                    contactIdentifier: PreviewsHelper.groupMembers[2].contactIdentifier))
            continuation.yield(PreviewsHelper.groupMembers[2])
        }
        return (UUID(), stream)
    }
    

    func finishAsyncSequenceOfSingleGroupMemberViewModels(_ view: SingleGroupMemberView, withIdentifier identifier: SingleGroupMemberView.Model.Identifier, streamUUID: UUID) {
        // Nothing to finish in these previews
    }
 

}

extension DataSourceForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.profilePictureForURL[photoURL]
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
    func fetchAvatarForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.profilePictureForURL[photoURL]
    }
    
    func fetchAvatarFromCacheForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
}


@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

@MainActor
private let actionsForPreviews = ActionsForPreviews()

@MainActor
private let modelForPreview =  PreviewsHelper.groupMembers[2]

#Preview {
    SingleGroupMemberView(
        mode: .listMembers(groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
                           commonActions: actionsForPreviews,
                           navigation: actionsForPreviews),
        modelIdentifier: .contactIdentifierForExistingGroupForPreviews(
            groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
            contactIdentifier: PreviewsHelper.groupMembers[2].contactIdentifier),
        dataSource: dataSourceForPreviews,
        avatarViewDataSource: dataSourceForPreviews,
        selectedMembers: .constant([]),
        membersWithUpdatedAdminPermission: .constant([]))
}

@MainActor
private struct PreviewWithRemove: View {
    
    @State private var selectedMembers: Set<SingleGroupMemberView.Model.Identifier> = []

    var body: some View {
        SingleGroupMemberView(mode: .removeMembers(groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0])),
                              modelIdentifier: .contactIdentifierForExistingGroupForPreviews(
                                groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
                                contactIdentifier: PreviewsHelper.groupMembers[2].contactIdentifier),
                              dataSource: dataSourceForPreviews,
                              avatarViewDataSource: dataSourceForPreviews,
                              selectedMembers: $selectedMembers,
                              membersWithUpdatedAdminPermission: .constant([]))
    }
}


#Preview("Remove") {
    PreviewWithRemove()
}


private struct PreviewWithEditAdmins: View {
    
    @State private var membersWithUpdatedAdminPermission: Set<MemberIdentifierAndPermissions> = []

    var body: some View {
        SingleGroupMemberView(mode: .editAdmins(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0]),
                              modelIdentifier: .contactIdentifierForExistingGroupForPreviews(
                                groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
                                contactIdentifier: PreviewsHelper.groupMembers[2].contactIdentifier),
                              dataSource: dataSourceForPreviews,
                              avatarViewDataSource: dataSourceForPreviews,
                              selectedMembers: .constant([]),
                              membersWithUpdatedAdminPermission: $membersWithUpdatedAdminPermission)
    }
}

#Preview("Edit Admins") {
    PreviewWithEditAdmins()
}


@MainActor
private final class DataSourceForPreviewsWithUpdate: SingleGroupMemberViewDataSource {

    func getAsyncSequenceOfSingleGroupMemberViewModels(_ view: SingleGroupMemberView, withIdentifier identifier: SingleGroupMemberView.Model.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupMemberView.Model>) {
        let stream = AsyncStream(SingleGroupMemberView.Model.self) { (continuation: AsyncStream<SingleGroupMemberView.Model>.Continuation) in
            Task {
                assert(identifier == .contactIdentifierForExistingGroupForPreviews(
                    groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
                    contactIdentifier: PreviewsHelper.groupMembers[2].contactIdentifier))
                continuation.yield(PreviewsHelper.groupMembers[2])
                try! await Task.sleep(seconds: 5)
                continuation.yield(PreviewsHelper.groupMembers[1]) // This changes the user identifier, which would not happen in practice
            }
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncSequenceOfSingleGroupMemberViewModels(_ view: SingleGroupMemberView, withIdentifier identifier: SingleGroupMemberView.Model.Identifier, streamUUID: UUID) {
        // Nothing to finish within these previews
    }
        
}

extension DataSourceForPreviewsWithUpdate: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.profilePictureForURL[photoURL]
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
    func fetchAvatarForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.profilePictureForURL[photoURL]
    }
    
    func fetchAvatarFromCacheForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
    
}

@MainActor
private let dataSourceForPreviewsWithUpdate = DataSourceForPreviewsWithUpdate()


#Preview("With update") {
    SingleGroupMemberView(
        mode: .listMembers(groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
                           commonActions: actionsForPreviews,
                           navigation: actionsForPreviews),
        modelIdentifier: .contactIdentifierForExistingGroupForPreviews(
            groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
            contactIdentifier: PreviewsHelper.groupMembers[2].contactIdentifier),
        dataSource: dataSourceForPreviewsWithUpdate,
        avatarViewDataSource: dataSourceForPreviewsWithUpdate,
        selectedMembers: .constant([]),
        membersWithUpdatedAdminPermission: .constant([]))
}

#endif
