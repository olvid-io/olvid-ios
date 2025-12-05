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
import ObvCircleAndTitlesView
import ObvDesignSystem
import ObvAppTypes
import ObvSystemIcon
import ObvUIGroupSharedBetweenV1AndV2


public enum SingleGroupV1MainViewModelOrNotFound: Sendable, Equatable {
    case groupNotFound
    case model(model: SingleGroupV1MainView.Model)
}

@MainActor
public protocol SingleGroupV1MainViewDataSource {
    func getAsyncSequenceOfSingleGroupV1MainViewModel(_ view: SingleGroupV1MainView, groupIdentifier: ObvGroupV1Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV1MainViewModelOrNotFound>)
    func finishAsyncSequenceOfSingleGroupV1MainViewModel(_ view: SingleGroupV1MainView, streamUUID: UUID)
}

@MainActor
public protocol SingleGroupV1MainViewActionsProtocol: PublishedDetailsValidationViewActionsProtocol, SelectUsersToAddViewActionsForEdition, SingleGroupMemberViewActionsProtocol, PersonalNoteEditorViewActions, EditGroupNameAndPictureViewActionsForEdition, EditGroupNameAndPictureViewActionsProtocol {
    func userWantsToLeaveGroup(_ view: SingleGroupV1MainView, groupIdentifier: ObvGroupV1Identifier) async throws
    func userWantsToDisbandGroup(_ view: SingleGroupV1MainView, groupIdentifier: ObvGroupV1Identifier) async throws
}

@MainActor
public protocol SingleGroupV1MainViewNavigation: ListOfGroupMembersViewNavigation, OneToOneInvitableViewNavigation {
    func userWantsToNavigateToViewAllowingToModifyMembers(_ view: SingleGroupV1MainView, groupIdentifier: ObvGroupV1Identifier) async
    func userWantsToChat(_ view: SingleGroupV1MainView, groupIdentifier: ObvGroupV1Identifier) async
    func userWantsToCall(_ view: SingleGroupV1MainView, groupIdentifier: ObvGroupV1Identifier)
    func userWantsToLeaveGroupFlow(_ view: SingleGroupV1MainView)
    func userWantsToEditGroupNicknameAndCustomPicture(_ view: SingleGroupV1MainView, groupIdentifier: ObvGroupV1Identifier)
    func userWantsToCloneGroup(_ view: SingleGroupV1MainView, groupIdentifier: ObvGroupV1Identifier) async throws
}

// MARK: - SingleGroupV1MainView

/// This is the main "single group" view, shown when the user wishes to consult the details of a particular group.
public struct SingleGroupV1MainView: View {
    
    let groupIdentifier: ObvGroupV1Identifier
    let dataSources: DataSources
    let actions: any SingleGroupV1MainViewActionsProtocol
    let navigation: any SingleGroupV1MainViewNavigation
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
    
    public init(groupIdentifier: ObvGroupV1Identifier,
                dataSources: DataSources,
                actions: SingleGroupV1MainViewActionsProtocol,
                navigation: any SingleGroupV1MainViewNavigation,
                uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet) {
        self.groupIdentifier = groupIdentifier
        self.dataSources = dataSources
        self.actions = actions
        self.navigation = navigation
        self.uiKitDelegateForSwiftUISheet = uiKitDelegateForSwiftUISheet
    }

    public struct DataSources {
        let dataSource: any SingleGroupV1MainViewDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        let listOfGroupMembersViewDataSource: any ListOfGroupMembersViewDataSource
        let ownedIdentityAsGroupMemberViewDataSource: any OwnedIdentityAsGroupMemberViewDataSource
        let singleGroupMemberViewDataSource: any SingleGroupMemberViewDataSource
        let selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource
        let listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource
        let oneToOneInvitableViewDataSource: any OneToOneInvitableViewDataSource
        let editGroupNameAndPictureViewDataSource: any EditGroupNameAndPictureViewDataSource
        
        public init(dataSource: any SingleGroupV1MainViewDataSource,
             avatarViewDataSource: any ObvAvatarViewDataSource,
             listOfGroupMembersViewDataSource: any ListOfGroupMembersViewDataSource,
             ownedIdentityAsGroupMemberViewDataSource: any OwnedIdentityAsGroupMemberViewDataSource,
             singleGroupMemberViewDataSource: any SingleGroupMemberViewDataSource,
             selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource,
             listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource,
             oneToOneInvitableViewDataSource: any OneToOneInvitableViewDataSource,
             editGroupNameAndPictureViewDataSource: any EditGroupNameAndPictureViewDataSource) {
            self.dataSource = dataSource
            self.avatarViewDataSource = avatarViewDataSource
            self.listOfGroupMembersViewDataSource = listOfGroupMembersViewDataSource
            self.ownedIdentityAsGroupMemberViewDataSource = ownedIdentityAsGroupMemberViewDataSource
            self.singleGroupMemberViewDataSource = singleGroupMemberViewDataSource
            self.selectUsersToAddViewDataSource = selectUsersToAddViewDataSource
            self.listOfUsersViewCellDataSource = listOfUsersViewCellDataSource
            self.oneToOneInvitableViewDataSource = oneToOneInvitableViewDataSource
            self.editGroupNameAndPictureViewDataSource = editGroupNameAndPictureViewDataSource
        }
        
        fileprivate var groupAdministrationViewDataSources: GroupAdministrationView.DataSources {
            .init(editGroupNameAndPictureViewDataSource: editGroupNameAndPictureViewDataSource,
                  avatarViewDataSource: avatarViewDataSource)
        }

        var listOfGroupMembersViewSubDataSources: ListOfGroupMembersView.SubDataSources {
            .init(ownedIdentityAsGroupMemberViewDataSource: self.ownedIdentityAsGroupMemberViewDataSource,
                  singleGroupMemberViewDataSource: self.singleGroupMemberViewDataSource,
                  avatarViewDataSource: self.avatarViewDataSource,
                  selectUsersToAddViewDataSource: self.selectUsersToAddViewDataSource,
                  listOfUsersViewCellDataSource: self.listOfUsersViewCellDataSource)
        }

    }
    
    @State private var streamedModel: Model? = nil
    @State private var streamedModelWasSetAtLeastOnce: Bool = false
    @State private var streamUUID: UUID?

    @State private var trustedPhoto: UIImage?
    @State private var customPhoto: UIImage?
    
    @State private var userIsDisbandingGroup: Bool = false
    @State private var hudCategory: HUDView.Category? = nil
    @State private var userIsLeavingGroup: Bool = false

    public struct Model: Sendable, Equatable {
        let groupIdentifier: ObvGroupV1Identifier
        let trustedName: String
        let trustedDescription: String?
        let circleColors: InitialCircleView.Model.Colors
        let nickname: String?
        let trustedPhotoURL: URL?
        let customPhotoURL: URL?
        let personalNote: String?
        let publishedDetailsForValidation: PublishedDetailsValidationViewModel?
        let ownedIdentityIsAdmin: Bool
        
        public init(groupIdentifier: ObvGroupV1Identifier, trustedName: String, trustedDescription: String?, circleColors: InitialCircleView.Model.Colors, nickname: String?, trustedPhotoURL: URL?, customPhotoURL: URL?, personalNote: String?, publishedDetailsForValidation: PublishedDetailsValidationViewModel?, ownedIdentityIsAdmin: Bool) {
            self.groupIdentifier = groupIdentifier
            self.trustedName = trustedName
            self.trustedDescription = trustedDescription
            self.circleColors = circleColors
            self.nickname = nickname
            self.trustedPhotoURL = trustedPhotoURL
            self.customPhotoURL = customPhotoURL
            self.personalNote = personalNote
            self.publishedDetailsForValidation = publishedDetailsForValidation
            self.ownedIdentityIsAdmin = ownedIdentityIsAdmin
        }
        
    }
    
    
    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSources.dataSource.getAsyncSequenceOfSingleGroupV1MainViewModel(self, groupIdentifier: groupIdentifier)
            if let previousStreamUUID = self.streamUUID {
                dataSources.dataSource.finishAsyncSequenceOfSingleGroupV1MainViewModel(self, streamUUID: previousStreamUUID)
            }
            self.streamUUID = streamUUID
            for await item in stream {
                
                switch item {
                    
                case .groupNotFound:
                    
                    // This typically happens if userIsLeavingGroup or userIsDisbandingGroup is true,
                    // or when the group is disbanded by another user while the current user is displaying this view
                    
                    withAnimation {
                        self.streamedModel = nil
                        self.trustedPhoto = nil
                        self.customPhoto = nil
                    }
                    
                    navigation.userWantsToLeaveGroupFlow(self)
                    
                case .model(let model):
                    let previousCustomPhotoURL = self.streamedModel?.customPhotoURL
                    let previousTrustedPhotoURL = self.streamedModel?.trustedPhotoURL
                    
                    if self.streamedModel == nil {
                        self.streamedModel = model
                    } else {
                        withAnimation {
                            self.streamedModel = model
                        }
                    }
                    
                    let newCustomPhotoURL = self.streamedModel?.customPhotoURL
                    let newTrustedPhotoURL = self.streamedModel?.trustedPhotoURL
                    
                    try? await fetchAndSetCustomPhoto(previousCustomPhotoURL: previousCustomPhotoURL, newCustomPhotoURL: newCustomPhotoURL)
                    try? await fetchAndSetTrustedPhoto(previousTrustedPhotoURL: previousTrustedPhotoURL, newTrustedPhotoURL: newTrustedPhotoURL)
                }
                
            }
            if let previousStreamUUID = self.streamUUID {
                dataSources.dataSource.finishAsyncSequenceOfSingleGroupV1MainViewModel(self, streamUUID: previousStreamUUID)
                self.streamUUID = nil
            }
        } catch {
            assertionFailure()
        }
    }
    
    
    private func fetchAndSetCustomPhoto(previousCustomPhotoURL: URL?, newCustomPhotoURL: URL?) async throws {
        guard previousCustomPhotoURL != newCustomPhotoURL else { return }
        withAnimation {
            self.customPhoto = nil
        }
        guard let newCustomPhotoURL else { return }
        // Quick and dirty: we enforce a `.xLarge` avatar size as this is coherent with the `.header` display mode chosen in circleAndTitlesViewModelForHeader.
        let customPhoto = try await dataSources.avatarViewDataSource.fetchAvatarForLegacyViews(photoURL: newCustomPhotoURL, avatarSize: .xLarge)
        if streamedModel?.customPhotoURL == newCustomPhotoURL {
            self.customPhoto = customPhoto
        }
    }
    
    
    private func fetchAndSetTrustedPhoto(previousTrustedPhotoURL: URL?, newTrustedPhotoURL: URL?) async throws {
        guard previousTrustedPhotoURL != newTrustedPhotoURL else { return }
        withAnimation {
            self.trustedPhoto = nil
        }
        guard let newTrustedPhotoURL else { return }
        // Quick and dirty: we enforce a `.xLarge` avatar size as this is coherent with the `.header` display mode chosen in circleAndTitlesViewModelForHeader.
        let trustedPhoto = try await dataSources.avatarViewDataSource.fetchAvatarForLegacyViews(photoURL: newTrustedPhotoURL, avatarSize: .xLarge)
        if streamedModel?.trustedPhotoURL == newTrustedPhotoURL {
            self.trustedPhoto = trustedPhoto
        }
    }

    @State private var isPersonalNoteEditorViewPresented: Bool = false
    @State private var showDisbandConfirmationDialog: Bool = false

    private func userTappedOnTheEditCustomNameAndPhotoButton() {
        navigation.userWantsToEditGroupNicknameAndCustomPicture(self, groupIdentifier: groupIdentifier)
    }

    private func userTappedOnCloneGroupButton() {
        Task {
            do {
                try await navigation.userWantsToCloneGroup(self, groupIdentifier: groupIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
    private func userTappedTheDisbandGroupButtonInTheMenu() {
        showDisbandConfirmationDialog = true
    }

    private var systemIconForMenu: SystemIcon {
        if #available(iOS 26, *) {
            return .ellipsis
        } else {
            return .ellipsisCircle
        }
    }

    private func userConfirmedSheWantsToDisbandTheGroup() {
        userIsDisbandingGroup = true
        hudCategory = .progress
        Task {
            defer { hudCategory = nil }
            do {
                try await actions.userWantsToDisbandGroup(self, groupIdentifier: groupIdentifier)
                guard !Task.isCancelled else { return }
                hudCategory = .checkmark
            } catch {
                hudCategory = .xmark
                userIsLeavingGroup = false
                assertionFailure()
            }
            try? await Task.sleep(seconds: 2)
        }
    }
    
    public var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .ignoresSafeArea(.all)
            if let streamedModel {
                InternalMainView(groupIdentifier: groupIdentifier,
                                 model: streamedModel,
                                 trustedPhoto: trustedPhoto,
                                 customPhoto: customPhoto,
                                 actions: self,
                                 dataSources: dataSources,
                                 navigation: navigation,
                                 uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet,
                                 hudCategory: $hudCategory)
            } else {
                if streamedModelWasSetAtLeastOnce {
                    ObvContentUnavailableView(
                        title: String(localizedInThisBundle: "GROUP_WAS_DELETED_TITLE"),
                        systemIcon: .person2SlashFill,
                        description: String(localizedInThisBundle: "GROUP_WAS_DELETED_DESCRIPTION"))
                } else {
                    ObvCenteredProgressView()
                }
            }
        }
        .task(onTask)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Section {
                        Button(action: { isPersonalNoteEditorViewPresented = true }) {
                            Label { Text("EDIT_PERSONAL_NOTE") } icon: { Image(systemIcon: .noteText) }
                        }
                        if groupIdentifier.groupType == .joined {
                            Button(action: userTappedOnTheEditCustomNameAndPhotoButton) {
                                Label { Text("EDIT_NICKNAME_AND_CUSTOM_PHOTO") } icon: { Image(systemIcon: .camera(.none)) }
                            }
                        }
                    }
                    Section {
                        Button(action: userTappedOnCloneGroupButton) {
                            Label { Text("CLONE_THIS_GROUP") } icon: { Image(systemIcon: .docOnDoc) }
                        }
                    }
                    Section {
                        if let streamedModel, streamedModel.ownedIdentityIsAdmin {
                            Button(role: .destructive, action: userTappedTheDisbandGroupButtonInTheMenu) {
                                Label { Text("DISBAND_GROUP") } icon: { Image(systemIcon: .trash) }
                            }
                        }
                    }
                } label: {
                    Image(systemIcon: systemIconForMenu)
                }
                .confirmationDialog(String(localizedInThisBundle: "SINGLE_GROUP_V1_VIEW_SHEET_CONFIRM_DISBAND_GROUP_TITLE"),
                                    isPresented: $showDisbandConfirmationDialog,
                                    titleVisibility: .visible) {
                    Button(String(localizedInThisBundle: "DISBAND_GROUP"), role: .destructive, action: userConfirmedSheWantsToDisbandTheGroup)
                } message: {
                    Text("SINGLE_GROUP_V1_VIEW_SHEET_CONFIRM_DISBAND_GROUP_MESSAGE")
                }

            }
        }
        .onChange(of: streamedModel) { newValue in
            if newValue != nil { streamedModelWasSetAtLeastOnce = true }
        }
        .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isPersonalNoteEditorViewPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
            if let streamedModel {
                PersonalNoteEditorView(model: .init(initialText: streamedModel.personalNote,
                                                    about: .groupV1(streamedModel.groupIdentifier)),
                                       actions: actions,
                                       navigation: self)
            }
        }
        .navigationTitle(streamedModel?.nickname ?? streamedModel?.trustedName ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
    
}


extension SingleGroupV1MainView: PersonalNoteEditorViewNavigation {
    
    public func userWantsToDismissPersonalNoteEditorView(_ view: PersonalNoteEditorView) {
        self.isPersonalNoteEditorViewPresented = false
    }

}


extension SingleGroupV1MainView: InternalMainViewViewActions {
    
    func userTappedTheChatButton() {
        Task {
            await navigation.userWantsToChat(self, groupIdentifier: groupIdentifier)
        }
    }
    
    func userTappedTheCallButton() {
        navigation.userWantsToCall(self, groupIdentifier: groupIdentifier)
    }
    
    fileprivate func userWantsToLeaveGroupAndHasConfirmed(_ view: LeaveOrDisbandGroupButtonAndConfirmationsView) {
        Task {
            do {
                try await actions.userWantsToLeaveGroup(self, groupIdentifier: groupIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
    fileprivate func userWantsToDisbandGroupAndHasConfirmed(_ view: LeaveOrDisbandGroupButtonAndConfirmationsView) {
        Task {
            do {
                try await actions.userWantsToDisbandGroup(self, groupIdentifier: groupIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
    func userTappedCloneButton() {
        Task {
            do {
                try await navigation.userWantsToCloneGroup(self, groupIdentifier: groupIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
}

extension SingleGroupV1MainView: SingleGroupMemberViewActionsProtocol {
//    public func userWantsToShowOtherUserProfile(_ view: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.InternalView, contactIdentifier: ObvTypes.ObvContactIdentifier) async {
//        await actions.userWantsToShowOtherUserProfile(view, contactIdentifier: contactIdentifier)
//    }
}

extension SingleGroupV1MainView: GroupAdministrationViewActionsProtocol {
    
    fileprivate func userWantsToNavigateToViewAllowingToModifyMembers(_ view: GroupAdministrationView) async {
        await navigation.userWantsToNavigateToViewAllowingToModifyMembers(self, groupIdentifier: groupIdentifier)
    }
    
}

extension SingleGroupV1MainView: EditGroupNameAndPictureViewActionsForEdition {
    
    public func userWantsToUpdateGroupNameAndPicture(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.InternalView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, changes: Set<ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.Change>) async throws {
        try await actions.userWantsToUpdateGroupNameAndPicture(view, groupIdentifier: groupIdentifier, changes: changes)
    }
    
}

extension SingleGroupV1MainView: EditGroupNameAndPictureViewActionsProtocol {
    
    public func userWantsObtainAvatar(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.InternalView, avatarSource: ObvAppTypes.ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await actions.userWantsObtainAvatar(view, avatarSource: avatarSource, avatarSize: avatarSize)
    }
    
    public func userWantsToSaveImageToTempFile(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.InternalView, image: UIImage) async throws -> URL {
        try await actions.userWantsToSaveImageToTempFile(view, image: image)
    }
    
}

extension SingleGroupV1MainView: PublishedDetailsValidationViewActionsProtocol {
    
    public func userWantsToReplaceTrustedDetailsByPublishedDetails(_ view: ObvUIGroupSharedBetweenV1AndV2.GroupPublishedDetailsValidationView, publishedDetails: ObvUIGroupSharedBetweenV1AndV2.PublishedDetailsValidationViewModel) async throws {
        try await actions.userWantsToReplaceTrustedDetailsByPublishedDetails(view, publishedDetails: publishedDetails)
    }
    
    public func userHasSeenPublishedDetails(_ view: GroupPublishedDetailsValidationView, publishedDetails: PublishedDetailsValidationViewModel) async throws {
        try await actions.userHasSeenPublishedDetails(view, publishedDetails: publishedDetails)
    }
    
}

extension SingleGroupV1MainView: SelectUsersToAddViewActionsForEdition {
    public func userWantsToAddSelectedUsersToExistingGroup(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddView.InternalView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, withIdentifiers userIdentifiers: [ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier]) async throws {
        try await actions.userWantsToAddSelectedUsersToExistingGroup(view, groupIdentifier: groupIdentifier, withIdentifiers: userIdentifiers)
    }
}

// MARK: - Internal view

@MainActor
private protocol InternalMainViewViewActions: PublishedDetailsValidationViewActionsProtocol, GroupAdministrationViewActionsProtocol, SingleGroupMemberViewActionsProtocol, LeaveOrDisbandGroupButtonAndConfirmationsViewActions {
    func userTappedTheChatButton()
    func userTappedTheCallButton()
    func userTappedCloneButton()
}

extension SingleGroupV1MainView {
    
    private struct InternalMainView: View {
        
        let groupIdentifier: ObvGroupV1Identifier
        let model: Model
        let trustedPhoto: UIImage?
        let customPhoto: UIImage?
        let actions: InternalMainViewViewActions
        let dataSources: DataSources
        let navigation: any SingleGroupV1MainViewNavigation
        let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
        @Binding var hudCategory: HUDView.Category? // Must be a binding

        private func profilePictureViewModelContentForHeaderOrTrustedDetails(model: Model) -> ProfilePictureView.Model.Content {
            .init(text: nil,
                  icon: .person3Fill,
                  profilePicture: customPhoto ?? trustedPhoto,
                  showGreenShield: false,
                  showRedShield: false)
        }

        private func textViewModelForHeaderOrTrustedDetails(model: Model) -> TextView.Model {
            .init(titlePart1: model.nickname ?? model.trustedName,
                  titlePart2: nil,
                  subtitle: model.trustedDescription,
                  subsubtitle: nil)
        }

        private func circleAndTitlesViewModelContentForHeaderOrTrustedDetails(model: Model) -> CircleAndTitlesView.Model.Content {
            .init(textViewModel: textViewModelForHeaderOrTrustedDetails(model: model),
                  profilePictureViewModelContent: profilePictureViewModelContentForHeaderOrTrustedDetails(model: model))
        }

        private func initialCircleViewModelColorsForHeaderOrTrustedDetails(model: Model) -> InitialCircleView.Model.Colors {
            model.circleColors
        }

        private func circleAndTitlesViewModelForHeader(model: Model) -> CircleAndTitlesView.Model {
            .init(content: circleAndTitlesViewModelContentForHeaderOrTrustedDetails(model: model),
                  colors: initialCircleViewModelColorsForHeaderOrTrustedDetails(model: model),
                  displayMode: .header,
                  editionMode: .none)
        }

        private func userTappedCloneButton() {
            actions.userTappedCloneButton()
        }
        
        var body: some View {
            ScrollView {
                
                VStack {
                    
                    // Header
                    
                    CircleAndTitlesView(model: circleAndTitlesViewModelForHeader(model: model))
                        .padding(.top, 16)
                    
                    // Chat and call buttons
                    
                    ObvChatAndCallButtonsView(callButtonIsDisabled: false,
                                              userTappedTheChatButton: actions.userTappedTheChatButton,
                                              userTappedTheCallButton: actions.userTappedTheCallButton)
                    .padding(.top, 16)

                    // Clone groupV1 into groupV2
                    
                    ObvCardView {
                        VStack {
                            Text("EXPLANATION_FOR_CLONING_A_GROUP_V1_TO_GROUP_V2")
                                .foregroundStyle(.secondary)
                                .padding(.bottom)
                            OlvidButtonNew(action: userTappedCloneButton) {
                                Label(title: { Text("CLONE_THIS_GROUP_V1_TO_GROUP_V2") }, icon: { Image(systemIcon: .docOnDoc) })
                            }
                        }
                    }
                    .padding(.top, 16)

                    // Personal note viewer
                    
                    if let personalNote = model.personalNote, !personalNote.isEmpty {
                        PersonalNoteStaticView(personalNote: personalNote)
                            .padding(.top, 16)
                    }

                    // Card shown when there are published details that the user needs to accept
                    
                    if let publishedDetailsForValidation = model.publishedDetailsForValidation, !publishedDetailsForValidation.differences.isEmpty {
                        GroupPublishedDetailsValidationView(
                            model: publishedDetailsForValidation,
                            avatarViewDataSource: dataSources.avatarViewDataSource,
                            actions: actions)
                        .padding(.top, 16)
                    }

                    // Group Administration
                    
                    if model.ownedIdentityIsAdmin {
                        GroupAdministrationView(
                            groupIdentifier: groupIdentifier,
                            actions: actions,
                            dataSources: dataSources.groupAdministrationViewDataSources,
                            uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                        .padding(.top, 16)
                    }

                    // Group members
                    
                    ListOfGroupMembersView(groupIdentifier: .groupV1(model.groupIdentifier),
                                           maximumNumberOfGroupMembersShown: 5,
                                           dataSource: dataSources.listOfGroupMembersViewDataSource,
                                           subDataSources: dataSources.listOfGroupMembersViewSubDataSources,
                                           actions: actions,
                                           navigation: navigation,
                                           uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                    .padding(.top, 16)

                    // Group members that can be invited to a one-to-one discussion
                    
                    OneToOneInvitableView(groupIdentifier: .groupV1(groupIdentifier),
                                          dataSource: dataSources.oneToOneInvitableViewDataSource,
                                          navigation: navigation)
                    .padding(.top, 16)

                    // Leave group button
                    
                    LeaveOrDisbandGroupButtonAndConfirmationsView(ownedIdentityIsAdmin: model.ownedIdentityIsAdmin,
                                                                  actions: actions)
                    .padding(.top, 16)

                }
                .padding(.horizontal)
                .padding(.bottom, 32)

            }
        }
    }
    
}


// MARK: - Subview: Leave group button and confirmations

@MainActor
private protocol LeaveOrDisbandGroupButtonAndConfirmationsViewActions {
    func userWantsToLeaveGroupAndHasConfirmed(_ view: LeaveOrDisbandGroupButtonAndConfirmationsView)
    func userWantsToDisbandGroupAndHasConfirmed(_ view: LeaveOrDisbandGroupButtonAndConfirmationsView)
}

private struct LeaveOrDisbandGroupButtonAndConfirmationsView: View {
    
    let ownedIdentityIsAdmin: Bool
    let actions: any LeaveOrDisbandGroupButtonAndConfirmationsViewActions

    @State private var showLeaveGroupDialog: Bool = false
    @State private var showDisbandGroupDialog: Bool = false

    private func action() {
        if ownedIdentityIsAdmin {
            showDisbandGroupDialog = true
        } else {
            showLeaveGroupDialog = true
        }
    }
    
    private var title: String {
        ownedIdentityIsAdmin ? String(localizedInThisBundle: "DISBAND_GROUP") : String(localizedInThisBundle: "LEAVE_GROUP")
    }
    
    private var systemIcon: SystemIcon {
        ownedIdentityIsAdmin ? .trash : .xmarkOctagon
    }
    
    private func userWantsToLeaveGroupAndHasConfirmed() {
        actions.userWantsToLeaveGroupAndHasConfirmed(self)
    }
    
    private func userWantsToDisbandGroupAndHasConfirmed() {
        actions.userWantsToDisbandGroupAndHasConfirmed(self)
    }
    
    var body: some View {
        OlvidButtonNew(action: action) {
            Label(title: { Text(title) }, icon: { Image(systemIcon: systemIcon) })
        }
        .tint(.red)
        .confirmationDialog(String(localizedInThisBundle: "SINGLE_GROUP_V1_VIEW_SHEET_CONFIRM_LEAVE_GROUP_TITLE"),
                            isPresented: $showLeaveGroupDialog,
                            titleVisibility: .visible) {
            Button(String(localizedInThisBundle: "LEAVE_GROUP"), role: .destructive, action: userWantsToLeaveGroupAndHasConfirmed)
        } message: {
            Text("SINGLE_GROUP_V1_VIEW_SHEET_CONFIRM_LEAVE_GROUP_MESSAGE")
        }
        .confirmationDialog(String(localizedInThisBundle: "SINGLE_GROUP_V1_VIEW_SHEET_CONFIRM_DISBAND_GROUP_TITLE"),
                            isPresented: $showDisbandGroupDialog,
                            titleVisibility: .visible) {
            Button(String(localizedInThisBundle: "DISBAND_GROUP"), role: .destructive, action: userWantsToDisbandGroupAndHasConfirmed)
        } message: {
            Text("SINGLE_GROUP_V1_VIEW_SHEET_CONFIRM_DISBAND_GROUP_MESSAGE")
        }
    }
    
    
}


// MARK: - Subview: Group administration

@MainActor
private protocol GroupAdministrationViewActionsProtocol: EditGroupNameAndPictureViewActionsForEdition, EditGroupNameAndPictureViewActionsProtocol {
    func userWantsToNavigateToViewAllowingToModifyMembers(_ view: GroupAdministrationView) async
}

private struct GroupAdministrationView: View {
    
    let groupIdentifier: ObvGroupV1Identifier
    let actions: GroupAdministrationViewActionsProtocol
    let dataSources: DataSources
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
    
    struct DataSources {
        let editGroupNameAndPictureViewDataSource: any EditGroupNameAndPictureViewDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
    }
    
    @State private var isEditGroupNameAndPictureViewPresented: Bool = false

    private func modifyMemberButtonTapped() {
        Task { await actions.userWantsToNavigateToViewAllowingToModifyMembers(self) }
    }
    
    private func modifyGroupNameButtonTapped() {
        isEditGroupNameAndPictureViewPresented = true
    }
    
    private struct ButtonContent: View {
        let systemIcon: SystemIcon
        let systemIconSize: CGFloat
        let systemIconColor: Color
        let backgroundColor: Color
        let text: String
        
        init(systemIcon: SystemIcon, systemIconSize: CGFloat = 17.0, systemIconColor: Color, backgroundColor: Color, text: String) {
            self.systemIcon = systemIcon
            self.systemIconSize = systemIconSize
            self.systemIconColor = systemIconColor
            self.backgroundColor = backgroundColor
            self.text = text
        }
        
        var body: some View {
            HStack {
                Image(systemIcon: systemIcon)
                    .font(.system(size: systemIconSize))
                    .tint(systemIconColor)
                    .frame(width: 29, height: 29)
                    .background(
                        RoundedRectangle(cornerSize: .init(width: 8, height: 8), style: .circular)
                            .foregroundStyle(backgroundColor)
                    )
                    .padding(.horizontal, 4)
                Text(text)
                    .padding(.horizontal, 4)
                    .tint(.primary)
                Spacer()
                ObvChevronRight()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }
    
    
    private struct DividerWithLeadingPadding: View {
        var body: some View {
            Divider()
                .padding(.leading, 65)
        }
        
    }
    

    var body: some View {
        
        VStack {
            
            HStack {
                Text("GROUP_ADMINISTRATION_TITLE")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            
            ObvCardView(padding: 0) {
                VStack(spacing: 0) {
                    Button(action: modifyGroupNameButtonTapped) {
                        ButtonContent(systemIcon: .pencil(.none),
                                      systemIconColor: .white,
                                      backgroundColor: .blue,
                                      text: String(localizedInThisBundle: "MODIFY_GROUP_NAME_AND_PHOTO_BUTTON_TITLE"))
                    }
                    DividerWithLeadingPadding()
                    Button(action: modifyMemberButtonTapped) {
                        ButtonContent(systemIcon: .person2Fill,
                                      systemIconSize: 14,
                                      systemIconColor: .white,
                                      backgroundColor: .pink,
                                      text: String(localizedInThisBundle: "MODIFY_MEMBERS_BUTTON_TITLE"))
                    }
                }
            }

        }
        .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isEditGroupNameAndPictureViewPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
            NavigationStack {
                EditGroupNameAndPictureView(
                    mode: .edition(groupIdentifier: .groupV1(groupIdentifier),
                                   navigation: self,
                                   dataSource: dataSources.editGroupNameAndPictureViewDataSource,
                                   avatarViewDataSource: dataSources.avatarViewDataSource,
                                   actions: actions),
                    actions: actions)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        ObvButtonWithCancelRole(action: { isEditGroupNameAndPictureViewPresented = false })
                    }
                }
            }
        }

    }
}


extension GroupAdministrationView: EditGroupNameAndPictureViewNavigationDuringEdition {
    
    func userWantsToLeaveGroupFlow(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {
        isEditGroupNameAndPictureViewPresented = false
    }
    
    func groupDetailsWereSuccessfullyUpdated(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.InternalView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {
        isEditGroupNameAndPictureViewPresented = false
    }
    
}
