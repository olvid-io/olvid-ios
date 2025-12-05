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
import ObvTypes
import ObvAppTypes
import ObvCircleAndTitlesView
import ObvDesignSystem



public struct OnetoOneInvitableGroupMembersViewModel: Sendable, Equatable {
    
    let invitableGroupMembers: [Identifier] // Those identifiers also include already invited members
    let notInvitableGroupMembers: [Identifier]
    let oneToOneContactsAmongMembers: [Identifier]
    
    public init(invitableGroupMembers: [Identifier], notInvitableGroupMembers: [Identifier], oneToOneContactsAmongMembers: [Identifier]) {
        self.invitableGroupMembers = invitableGroupMembers
        self.notInvitableGroupMembers = notInvitableGroupMembers
        self.oneToOneContactsAmongMembers = oneToOneContactsAmongMembers
    }
    
    public enum Identifier: Identifiable, Sendable, Equatable {
        
        case contactIdentifier(contactIdentifier: ObvContactIdentifier)
        case objectIDOfPersistedGroupV2Member(objectID: NSManagedObjectID) // For group V2
        case objectIDOfPersistedPendingGroupMember(objectID: NSManagedObjectID) // For group V1
        case objectIDOfPersistedObvContactIdentity(objectID: NSManagedObjectID)
        
        public var id: Data {
            switch self {
            case .contactIdentifier(let contactIdentifier):
                return contactIdentifier.ownedCryptoId.getIdentity() + contactIdentifier.contactCryptoId.getIdentity()
            case .objectIDOfPersistedGroupV2Member(let objectID):
                return objectID.uriRepresentation().dataRepresentation
            case .objectIDOfPersistedPendingGroupMember(let objectID):
                return objectID.uriRepresentation().dataRepresentation
            case .objectIDOfPersistedObvContactIdentity(let objectID):
                return objectID.uriRepresentation().dataRepresentation
            }
        }
        
    }

}


@MainActor
public protocol OnetoOneInvitableGroupMembersViewDataSource {
    func getAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(_ view: OnetoOneInvitableGroupMembersView, groupIdentifier: ObvGroupIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<OnetoOneInvitableGroupMembersViewModel>)
    func finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(_ view: OnetoOneInvitableGroupMembersView, streamUUID: UUID)
}

@MainActor
public protocol OnetoOneInvitableGroupMembersViewActionsProtocol: AnyObject, OnetoOneInvitableGroupMembersViewCellActionsProtocol {
    func userWantsToSendOneToOneInvitationsTo(_ view: OnetoOneInvitableGroupMembersView.InternalView, contactIdentifiers: [OnetoOneInvitableGroupMembersViewModel.Identifier]) async throws
}

/// This view shows all the group members, split in 3 categories:
/// - Thoses that are not yet one2one contacts, but that can be invited to a one to one discussion (those are exactly the group
///   group members that have an associated `PersistedObvContactIdentity` that is not one2one). Note that certain
///   of these members may already have been invited, so we won't allow a second invitation to be sent.
/// - Thoses that are not yet one2one contacts, but that can not yet be invited (pending members not contacts)
/// - Those that are already one2one contacts and that do not need to be invited.
public struct OnetoOneInvitableGroupMembersView: View {
    
    let groupIdentifier: ObvGroupIdentifier
    let dataSource: OnetoOneInvitableGroupMembersViewDataSource
    let onetoOneInvitableGroupMembersViewCellDataSource: OnetoOneInvitableGroupMembersViewCellDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let actions: OnetoOneInvitableGroupMembersViewActionsProtocol
    
    public init(groupIdentifier: ObvGroupIdentifier, dataSource: OnetoOneInvitableGroupMembersViewDataSource, onetoOneInvitableGroupMembersViewCellDataSource: OnetoOneInvitableGroupMembersViewCellDataSource, avatarViewDataSource: ObvAvatarViewDataSource, actions: OnetoOneInvitableGroupMembersViewActionsProtocol) {
        self.groupIdentifier = groupIdentifier
        self.dataSource = dataSource
        self.onetoOneInvitableGroupMembersViewCellDataSource = onetoOneInvitableGroupMembersViewCellDataSource
        self.avatarViewDataSource = avatarViewDataSource
        self.actions = actions
    }
    
    @State private var model: OnetoOneInvitableGroupMembersViewModel?
    @State private var streamUUID: UUID?

    
    private func onAppear() {
        Task {
            let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(self, groupIdentifier: groupIdentifier)
            if let previousStreamUUID = self.streamUUID {
                dataSource.finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(self, streamUUID: previousStreamUUID)
            }
            self.streamUUID = streamUUID
            for await item in stream {
                withAnimation {
                    self.model = item
                }
            }
        }
    }
    
    
    private func onDisappear() {
        guard let previousStreamUUID = self.streamUUID else { return }
        dataSource.finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(self, streamUUID: previousStreamUUID)
        self.streamUUID = nil
    }
    
    
    public var body: some View {
        InternalView(model: model,
                     dataSource: dataSource,
                     onetoOneInvitableGroupMembersViewCellDataSource: onetoOneInvitableGroupMembersViewCellDataSource,
                     avatarViewDataSource: avatarViewDataSource,
                     actions: actions)
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
    }
    
    
    public struct InternalView: View {
        
        let model: OnetoOneInvitableGroupMembersViewModel?
        let dataSource: OnetoOneInvitableGroupMembersViewDataSource
        let onetoOneInvitableGroupMembersViewCellDataSource: OnetoOneInvitableGroupMembersViewCellDataSource
        let avatarViewDataSource: ObvAvatarViewDataSource
        let actions: OnetoOneInvitableGroupMembersViewActionsProtocol
        
        @State private var disabledInviteAllButton: Bool = false
        @State private var showInviteThemAllConfirmation: Bool = false

        private func userTappedOnTheInviteThemAllButton(confirmed: Bool) {
            if !confirmed {
                showInviteThemAllConfirmation = true
            } else {
                guard let model else { assertionFailure(); return }
                let invitableGroupMembers = model.invitableGroupMembers
                disabledInviteAllButton = true
                Task {
                    do {
                        try await actions.userWantsToSendOneToOneInvitationsTo(self, contactIdentifiers: invitableGroupMembers)
                    } catch {
                        assertionFailure()
                    }
                    disabledInviteAllButton = false
                }
            }
        }

        public var body: some View {
            ZStack {
                
                Color(AppTheme.shared.colorScheme.systemBackground)
                    .edgesIgnoringSafeArea(.all)

                if let model {
                    
                    ScrollView {
                        LazyVStack {
                            
                            if !model.invitableGroupMembers.isEmpty {
                                
                                ObvCardView(padding: 0) {
                                    Group {
                                        VStack {
                                            VStack {
                                                HStack {
                                                    Text("THE_FOLLOWING_\(model.invitableGroupMembers.count)_GROUP_MEMBERS_ARE_NOT_YET_PART_OF_YOUR_CONTACTS_BUT_YOU_CAN_INVITE_THEM")
                                                        .foregroundStyle(.secondary)
                                                        .accessibilityAddTraits(.isHeader)
                                                    Spacer(minLength: 0)
                                                }
                                                Button(action: { userTappedOnTheInviteThemAllButton(confirmed: false) } ) {
                                                    HStack {
                                                        Spacer(minLength: 0)
                                                        Text("INVITE_THEM_ALL")
                                                        Spacer(minLength: 0)
                                                    }.padding(.vertical, 4)
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .disabled(disabledInviteAllButton)
                                                .confirmationDialog(Text("ARE_YOU_SURE_YOU_WANT_TO_SEND_ONE_TO_ONE_INVITATION_TO_\(model.invitableGroupMembers.count)_USERS"), isPresented: $showInviteThemAllConfirmation, titleVisibility: .visible) {
                                                    Button(String(localizedInThisBundle: "SEND_THE_\(model.invitableGroupMembers.count)_ONE_TO_ONE_INVITATIONS")) {
                                                        userTappedOnTheInviteThemAllButton(confirmed: true)
                                                    }
                                                }

                                            }.padding(.horizontal)
                                            Divider()
                                            LazyVStack {
                                                ForEach(model.invitableGroupMembers) { invitableGroupMember in
                                                    OnetoOneInvitableGroupMembersViewCell(
                                                        identifier: invitableGroupMember,
                                                        dataSource: onetoOneInvitableGroupMembersViewCellDataSource,
                                                        avatarViewDataSource: avatarViewDataSource,
                                                        actions: actions)
                                                    .padding(.horizontal)
                                                    if invitableGroupMember.id != model.invitableGroupMembers.last?.id {
                                                        Divider()
                                                            .padding(.leading, 70)
                                                    }
                                                }
                                            }
                                        }
                                    }.padding(.vertical)
                                }
                                .padding(.horizontal)
                                .padding(.bottom)
                                
                            }
                            
                            if !model.notInvitableGroupMembers.isEmpty {
                                
                                ObvCardView(padding: 0) {
                                    Group {
                                        VStack {
                                            HStack {
                                                Text("THE_FOLLOWING_\(model.notInvitableGroupMembers.count)_GROUP_MEMBERS_ARE_NOT_YET_PART_OF_YOUR_CONTACTS_AND_MUST_ACCEPT_GROUP_INVITATION")
                                                    .foregroundStyle(.secondary)
                                                    .accessibilityAddTraits(.isHeader)
                                                Spacer(minLength: 0)
                                            }.padding(.horizontal)
                                            Divider()
                                            ForEach(model.notInvitableGroupMembers) { notInvitableGroupMember in
                                                OnetoOneInvitableGroupMembersViewCell(
                                                    identifier: notInvitableGroupMember,
                                                    dataSource: onetoOneInvitableGroupMembersViewCellDataSource,
                                                    avatarViewDataSource: avatarViewDataSource,
                                                    actions: actions)
                                                .padding(.horizontal)
                                                if notInvitableGroupMember.id != model.notInvitableGroupMembers.last?.id {
                                                    Divider()
                                                        .padding(.leading, 70)
                                                }
                                            }
                                        }
                                    }.padding(.vertical)
                                }
                                .padding(.horizontal)
                                .padding(.bottom)

                            }
                            
                            if !model.oneToOneContactsAmongMembers.isEmpty {
                                
                                ObvCardView(padding: 0) {
                                    Group {
                                        VStack {
                                            HStack {
                                                Text("THE_FOLLOWING_\(model.oneToOneContactsAmongMembers.count)_GROUP_MEMBERS_ARE_ALREADY_PART_OF_YOUR_CONTACTS")
                                                    .foregroundStyle(.secondary)
                                                    .accessibilityAddTraits(.isHeader)
                                                Spacer(minLength: 0)
                                            }.padding(.horizontal)
                                            Divider()
                                            ForEach(model.oneToOneContactsAmongMembers) { oneToOneContactsAmongMember in
                                                OnetoOneInvitableGroupMembersViewCell(
                                                    identifier: oneToOneContactsAmongMember,
                                                    dataSource: onetoOneInvitableGroupMembersViewCellDataSource,
                                                    avatarViewDataSource: avatarViewDataSource,
                                                    actions: actions)
                                                .padding(.horizontal)
                                                if oneToOneContactsAmongMember.id != model.oneToOneContactsAmongMembers.last?.id {
                                                    Divider()
                                                        .padding(.leading, 70)
                                                }
                                            }
                                        }
                                    }.padding(.vertical)
                                }.padding(.horizontal)
                                
                            }
                        }
                    }
                } else {
                    VStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
    }
    
}


// MARK: - Subview: OnetoOneInvitableGroupMembersViewCell


/// This model is similar (but not exactly identical) to `SingleGroupMemberViewModel`.
public struct OnetoOneInvitableGroupMembersViewCellModel: Sendable, Equatable {
    
    let contactIdentifier: ObvContactIdentifier
    let isKeycloakManaged: Bool
    let profilePictureInitial: String?
    let circleColors: InitialCircleView.Model.Colors
    let identityDetails: ObvIdentityDetails
    let kind: Kind
    let isRevokedAsCompromised: Bool
    let detailedProfileCanBeShown: Bool
    let customDisplayName: String?
    let customPhotoURL: URL?

    public init(contactIdentifier: ObvContactIdentifier, isKeycloakManaged: Bool, profilePictureInitial: String?, circleColors: InitialCircleView.Model.Colors, identityDetails: ObvIdentityDetails, kind: Kind, isRevokedAsCompromised: Bool, detailedProfileCanBeShown: Bool, customDisplayName: String?, customPhotoURL: URL?) {
        self.contactIdentifier = contactIdentifier
        self.isKeycloakManaged = isKeycloakManaged
        self.profilePictureInitial = profilePictureInitial
        self.circleColors = circleColors
        self.identityDetails = identityDetails
        self.kind = kind
        self.isRevokedAsCompromised = isRevokedAsCompromised
        self.detailedProfileCanBeShown = detailedProfileCanBeShown
        self.customDisplayName = customDisplayName
        self.customPhotoURL = customPhotoURL
    }

    public enum Kind: Sendable, Equatable {
        case invitableGroupMembers(invitationSentAlready: Bool)
        case notInvitableGroupMembers
        case oneToOneContactsAmongMembers
    }

}


@MainActor
public protocol OnetoOneInvitableGroupMembersViewCellDataSource: AnyObject {

    func getAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(_ view: OnetoOneInvitableGroupMembersViewCell, identifier: OnetoOneInvitableGroupMembersViewModel.Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<OnetoOneInvitableGroupMembersViewCellModel>)
    func finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(_ view: OnetoOneInvitableGroupMembersViewCell, identifier: OnetoOneInvitableGroupMembersViewModel.Identifier, streamUUID: UUID)

    //func fetchAvatarImageForGroupMember(_ view: OnetoOneInvitableGroupMembersViewCell, contactIdentifier: ObvContactIdentifier, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
    
}


@MainActor
public protocol OnetoOneInvitableGroupMembersViewCellActionsProtocol {
    func userWantsToSendOneToOneInvitationTo(_ view: OnetoOneInvitableGroupMembersViewCell.InternalView, contactIdentifier: ObvContactIdentifier) async throws
    func userWantsToCancelOneToOneInvitationSentTo(_ view: OnetoOneInvitableGroupMembersViewCell.InternalView, contactIdentifier: ObvContactIdentifier) async throws
}

public struct OnetoOneInvitableGroupMembersViewCell: View {
    
    let identifier: OnetoOneInvitableGroupMembersViewModel.Identifier
    let dataSource: OnetoOneInvitableGroupMembersViewCellDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let actions: OnetoOneInvitableGroupMembersViewCellActionsProtocol

    @State private var member: OnetoOneInvitableGroupMembersViewCellModel?
    @State private var streamUUID: UUID?
    @State private var profilePicture: (url: URL, image: UIImage?)?

    private var avatarSize: ObvDesignSystem.ObvAvatarSize {
        ObvDesignSystem.ObvAvatarSize.normal
    }

    private func onAppear() {
        Task {
            let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(self, identifier: identifier)
            if let previousStreamUUID = self.streamUUID {
                dataSource.finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(self, identifier: identifier, streamUUID: previousStreamUUID)
            }
            self.streamUUID = streamUUID
            for await model in stream {
                if self.member == nil {
                    self.member = model
                } else {
                    withAnimation { self.member = model }
                }
                Task { await updateProfilePictureIfRequired(member: model, photoURL: model.customPhotoURL ?? model.identityDetails.photoURL) }
            }
        }
    }
    
    private func updateProfilePictureIfRequired(member: OnetoOneInvitableGroupMembersViewCellModel, photoURL: URL?) async {
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

    private func onDisappear() {
        if let streamUUID = self.streamUUID {
            dataSource.finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(self, identifier: identifier, streamUUID: streamUUID)
            self.streamUUID = nil
        }
    }
    
    public var body: some View {
        InternalView(member: member, profilePicture: profilePicture?.image, avatarSize: avatarSize, actions: actions)
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
    }
    
    public struct InternalView: View {
        
        let member: OnetoOneInvitableGroupMembersViewCellModel?
        let profilePicture: UIImage?
        let avatarSize: ObvDesignSystem.ObvAvatarSize
        let actions: OnetoOneInvitableGroupMembersViewCellActionsProtocol

        @State private var isSendingOneToOneInvitation: Bool = false
        @State private var showCancelOneToOneInvitationSentConfirmation: Bool = false

        private func profilePictureViewModelContent(member: OnetoOneInvitableGroupMembersViewCellModel) -> ProfilePictureView.Model.Content {
            .init(text: member.profilePictureInitial,
                  icon: .person,
                  profilePicture: profilePicture,
                  showGreenShield: member.isKeycloakManaged,
                  showRedShield: member.isRevokedAsCompromised)
        }

        private func profilePictureViewModel(member: OnetoOneInvitableGroupMembersViewCellModel) -> ProfilePictureView.Model {
            .init(content: profilePictureViewModelContent(member: member),
                  colors: member.circleColors,
                  circleDiameter: avatarSize.frameSize.width)
        }

        private func textViewModel(member: OnetoOneInvitableGroupMembersViewCellModel) -> TextView.Model {
            let coreDetails = member.identityDetails.coreDetails
            if let customDisplayName = member.customDisplayName, !customDisplayName.isEmpty {
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

        private func userWantsToSendInvitationTo(contactIdentifier: ObvContactIdentifier) {
            isSendingOneToOneInvitation = true
            Task {
                do {
                    try await actions.userWantsToSendOneToOneInvitationTo(self, contactIdentifier: contactIdentifier)
                    isSendingOneToOneInvitation = false
                } catch {
                    isSendingOneToOneInvitation = false
                }
            }
        }

        private func oneToOneInvitationSentButtonTapped(contactIdentifier: ObvContactIdentifier) {
            showCancelOneToOneInvitationSentConfirmation = true
        }

        private func userConfirmedSheWantsToCancelOneToOneInvitationSent(contactIdentifier: ObvContactIdentifier) {
            isSendingOneToOneInvitation = true
            Task {
                do {
                    try await actions.userWantsToCancelOneToOneInvitationSentTo(self, contactIdentifier: contactIdentifier)
                    isSendingOneToOneInvitation = false
                } catch {
                    isSendingOneToOneInvitation = false
                }
            }
        }
        
        public var body: some View {
            if let member {
                switch member.kind {
                case .invitableGroupMembers(invitationSentAlready: let invitationSentAlready):
                    HStack {
                        ProfilePictureView(model: profilePictureViewModel(member: member))
                            .accessibilityHidden(true)
                        TextView(model: textViewModel(member: member))
                        Spacer()
                        if invitationSentAlready {
                            VStack(alignment: .center) {
                                Button {
                                    oneToOneInvitationSentButtonTapped(contactIdentifier: member.contactIdentifier)
                                } label: {
                                    Text("BUTTON_TITLE_ONE_TO_ONE_INVITATION_SENT")
                                }
                                .buttonStyle(.borderless)
                                .frame(maxWidth: 70)
                                .confirmationDialog(Text("ARE_YOU_SURE_YOU_WANT_TO_CANCEL_THIS_ONE_TO_ONE_INVITATION"), isPresented: $showCancelOneToOneInvitationSentConfirmation, titleVisibility: .visible) {
                                    Button(String(localizedInThisBundle: "CANCEL_ONE_TO_ONE_INVITATION_BUTTON_TITLE"), role: .destructive) {
                                        userConfirmedSheWantsToCancelOneToOneInvitationSent(contactIdentifier: member.contactIdentifier)
                                    }
                                }
                            }
                        } else {
                            Button {
                                userWantsToSendInvitationTo(contactIdentifier: member.contactIdentifier)
                            } label: {
                                Text("BUTTON_TITLE_SEND_ONE_TO_ONE_INVITATION")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSendingOneToOneInvitation)
                        }
                    }
                    .accessibilityElement(children: .combine)
                case .notInvitableGroupMembers:
                    HStack {
                        ProfilePictureView(model: profilePictureViewModel(member: member))
                        TextView(model: textViewModel(member: member))
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                case .oneToOneContactsAmongMembers:
                    HStack {
                        ProfilePictureView(model: profilePictureViewModel(member: member))
                        TextView(model: textViewModel(member: member))
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                PlaceholderForUserCell(avatarSize: avatarSize)
            }
        }
    }
    
}















// MARK: - Previews

#if DEBUG

@MainActor
private final class DataSourceForPreviews {}

extension DataSourceForPreviews: OnetoOneInvitableGroupMembersViewDataSource {
    
    func getAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(_ view: OnetoOneInvitableGroupMembersView, groupIdentifier: ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<OnetoOneInvitableGroupMembersViewModel>) {
        let stream = AsyncStream(OnetoOneInvitableGroupMembersViewModel.self) { (continuation: AsyncStream<OnetoOneInvitableGroupMembersViewModel>.Continuation) in
            let model = PreviewsHelper.onetoOneInvitableGroupMembersViewModels[0]
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(_ view: OnetoOneInvitableGroupMembersView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
}

extension DataSourceForPreviews: OnetoOneInvitableGroupMembersViewCellDataSource {
    
    func getAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(_ view: OnetoOneInvitableGroupMembersViewCell, identifier: OnetoOneInvitableGroupMembersViewModel.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OnetoOneInvitableGroupMembersViewCellModel>) {
        let stream = AsyncStream(OnetoOneInvitableGroupMembersViewCellModel.self) { (continuation: AsyncStream<OnetoOneInvitableGroupMembersViewCellModel>.Continuation) in
            switch identifier {
            case .objectIDOfPersistedGroupV2Member:
                assertionFailure("Unexpected identifier")
                return
            case .objectIDOfPersistedObvContactIdentity:
                assertionFailure("Unexpected identifier")
                return
            case .objectIDOfPersistedPendingGroupMember:
                assertionFailure("Unexpected identifier")
                return
            case .contactIdentifier(contactIdentifier: let contactIdentifier):
                guard let model = PreviewsHelper.onetoOneInvitableGroupMembersViewCellModel[contactIdentifier] else { assertionFailure(); return }
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(_ view: OnetoOneInvitableGroupMembersViewCell, identifier: OnetoOneInvitableGroupMembersViewModel.Identifier, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
    
    
}


extension DataSourceForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        if let image = PreviewsHelper.profilePictureForURL[photoURL] {
            return image
        } else {
            return nil
        }
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
    func fetchAvatarForLegacyViews(photoURL: URL, avatarSize: ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        if let image = PreviewsHelper.profilePictureForURL[photoURL] {
            return image
        } else {
            return nil
        }
    }
    
}

final private class ActionsForPreviews: OnetoOneInvitableGroupMembersViewActionsProtocol {
    
    func userWantsToSendOneToOneInvitationsTo(_ view: OnetoOneInvitableGroupMembersView.InternalView, contactIdentifiers: [OnetoOneInvitableGroupMembersViewModel.Identifier]) async throws {
        // We do nothing in these previews
        try await Task.sleep(seconds: 1)
    }
    
}

extension ActionsForPreviews: OnetoOneInvitableGroupMembersViewCellActionsProtocol {
    
    func userWantsToSendOneToOneInvitationTo(_ view: OnetoOneInvitableGroupMembersViewCell.InternalView, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        // We do nothing in these previews
        try await Task.sleep(seconds: 1)
    }
    
    func userWantsToCancelOneToOneInvitationSentTo(_ view: OnetoOneInvitableGroupMembersViewCell.InternalView, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        // We do nothing in these previews
        try await Task.sleep(seconds: 1)
    }
    
    
}

@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

@MainActor
private let actionsForPreviews = ActionsForPreviews()

#Preview {
    OnetoOneInvitableGroupMembersView(groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
                                      dataSource: dataSourceForPreviews,
                                      onetoOneInvitableGroupMembersViewCellDataSource: dataSourceForPreviews,
                                      avatarViewDataSource: dataSourceForPreviews,
                                      actions: actionsForPreviews)
}

#endif
