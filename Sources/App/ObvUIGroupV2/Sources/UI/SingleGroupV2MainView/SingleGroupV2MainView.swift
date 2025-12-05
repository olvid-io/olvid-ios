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


public enum SingleGroupV2MainViewModelOrNotFound: Sendable, Equatable {
    case groupNotFound
    case model(model: SingleGroupV2MainViewModel)
}


public struct SingleGroupV2MainViewModel: Sendable, Equatable {
    
    let groupIdentifier: ObvGroupV2Identifier
    let trustedName: String
    let trustedDescription: String?
    let trustedPhotoURL: URL?
    let customPhotoURL: URL?
    let nickname: String?
    let isKeycloakManaged: Bool
    let circleColors: InitialCircleView.Model.Colors
    let updateInProgress: Bool
    let ownedIdentityIsAdmin: Bool
    let ownedIdentityCanLeaveGroup: CanLeaveGroup
    let publishedDetailsForValidation: PublishedDetailsValidationViewModel?
    let personalNote: String?
    let groupType: ObvGroupType
    
    public enum CanLeaveGroup: Sendable, Equatable {
        case canLeaveGroup
        case cannotLeaveGroupAsWeAreTheOnlyAdmin
        case cannotLeaveGroupAsThisIsKeycloakGroup
    }

    public init(groupIdentifier: ObvGroupV2Identifier, trustedName: String, trustedDescription: String?, trustedPhotoURL: URL?, customPhotoURL: URL?, nickname: String?, isKeycloakManaged: Bool, circleColors: InitialCircleView.Model.Colors, updateInProgress: Bool, ownedIdentityIsAdmin: Bool, ownedIdentityCanLeaveGroup: CanLeaveGroup, publishedDetailsForValidation: PublishedDetailsValidationViewModel?, personalNote: String?, groupType: ObvGroupType) {
        self.groupIdentifier = groupIdentifier
        self.trustedName = trustedName
        self.trustedDescription = trustedDescription
        self.trustedPhotoURL = trustedPhotoURL
        self.customPhotoURL = customPhotoURL
        self.nickname = nickname
        self.isKeycloakManaged = isKeycloakManaged
        self.circleColors = circleColors
        self.updateInProgress = updateInProgress
        self.ownedIdentityIsAdmin = ownedIdentityIsAdmin
        self.ownedIdentityCanLeaveGroup = ownedIdentityCanLeaveGroup
        self.publishedDetailsForValidation = publishedDetailsForValidation
        self.personalNote = personalNote
        self.groupType = groupType
    }
    
}


@MainActor
public protocol SingleGroupV2MainViewDataSource {
    func getAsyncSequenceOfSingleGroupV2MainViewModel(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV2MainViewModelOrNotFound>)
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(_ view: SingleGroupV2MainView, streamUUID: UUID)
}


@MainActor
public protocol SingleGroupV2MainViewActionsProtocol: AnyObject, PublishedDetailsValidationViewActionsProtocol, SingleGroupMemberViewActionsProtocol, EditGroupNameAndPictureViewActionsProtocol, EditGroupTypeViewActionsForEdition, PersonalNoteEditorViewActions, EditGroupTypeNavigationStackActions, EditGroupNameAndPictureViewActionsForEdition {
    func userWantsToLeaveGroup(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier) async throws
    func userWantsToDisbandGroup(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier) async throws
    func userTappedOnManualResyncOfGroupV2Button(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier) async throws
}

@MainActor
public protocol SingleGroupV2MainViewNavigation: GroupAdministrationViewNavigation, ListOfGroupMembersViewNavigation, OneToOneInvitableViewNavigation {
    func userWantsToChat(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier) async
    func userWantsToCall(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier)
    func userWantsToLeaveGroupFlow(_ view: SingleGroupV2MainView)
    func userWantsToEditGroupNicknameAndCustomPicture(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier)
    func userWantsToCloneGroup(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier) async throws
}


// MARK: - SingleGroupV2MainView

/// This is the main "single group" view, shown when the user wishes to consult the details of a particular group.
public struct SingleGroupV2MainView: View {
    
    let groupIdentifier: ObvGroupV2Identifier
    let dataSource: any SingleGroupV2MainViewDataSource
    let subDataSources: SubDataSources
    let actions: any SingleGroupV2MainViewActionsProtocol
    let navigation: any SingleGroupV2MainViewNavigation
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
    
    public init(groupIdentifier: ObvGroupV2Identifier,
                dataSource: any SingleGroupV2MainViewDataSource,
                subDataSources: SubDataSources,
                actions: any SingleGroupV2MainViewActionsProtocol,
                navigation: SingleGroupV2MainViewNavigation,
                uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet) {
        self.groupIdentifier = groupIdentifier
        self.dataSource = dataSource
        self.subDataSources = subDataSources
        self.actions = actions
        self.navigation = navigation
        self.uiKitDelegateForSwiftUISheet = uiKitDelegateForSwiftUISheet
    }
    
    public struct SubDataSources {
        let listOfGroupMembersViewDataSource: any ListOfGroupMembersViewDataSource
        let ownedIdentityAsGroupMemberViewDataSource: any OwnedIdentityAsGroupMemberViewDataSource
        let singleGroupMemberViewDataSource: any SingleGroupMemberViewDataSource
        let oneToOneInvitableViewDataSource: any OneToOneInvitableViewDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        let editGroupNameAndPictureViewDataSource: any EditGroupNameAndPictureViewDataSource
        let editGroupTypeViewDataSource: any EditGroupTypeViewDataSource
        let selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource
        let listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource
        let editGroupTypeNavigationStackSubDataSources: EditGroupTypeNavigationStack.SubDataSources
        
        public init(listOfGroupMembersViewDataSource: any ListOfGroupMembersViewDataSource,
                    ownedIdentityAsGroupMemberViewDataSource: any OwnedIdentityAsGroupMemberViewDataSource,
                    singleGroupMemberViewDataSource: any SingleGroupMemberViewDataSource,
                    oneToOneInvitableViewDataSource: any OneToOneInvitableViewDataSource,
                    avatarViewDataSource: any ObvAvatarViewDataSource,
                    editGroupNameAndPictureViewDataSource: any EditGroupNameAndPictureViewDataSource,
                    editGroupTypeViewDataSource: any EditGroupTypeViewDataSource,
                    selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource,
                    listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource,
                    editGroupTypeNavigationStackSubDataSources: EditGroupTypeNavigationStack.SubDataSources) {
            self.listOfGroupMembersViewDataSource = listOfGroupMembersViewDataSource
            self.ownedIdentityAsGroupMemberViewDataSource = ownedIdentityAsGroupMemberViewDataSource
            self.singleGroupMemberViewDataSource = singleGroupMemberViewDataSource
            self.oneToOneInvitableViewDataSource = oneToOneInvitableViewDataSource
            self.avatarViewDataSource = avatarViewDataSource
            self.editGroupNameAndPictureViewDataSource = editGroupNameAndPictureViewDataSource
            self.editGroupTypeViewDataSource = editGroupTypeViewDataSource
            self.selectUsersToAddViewDataSource = selectUsersToAddViewDataSource
            self.listOfUsersViewCellDataSource = listOfUsersViewCellDataSource
            self.editGroupTypeNavigationStackSubDataSources = editGroupTypeNavigationStackSubDataSources
        }
    }

    @State private var groupModel: SingleGroupV2MainViewModel?
    @State private var groupModelWasSetAtLeastOnce: Bool = false
    @State private var streamUUID: UUID?
    
    @State private var trustedPhoto: UIImage?
    @State private var customPhoto: UIImage?
    
    @State private var showDisbandConfirmationDialog: Bool = false
    @State private var userIsDisbandingGroup: Bool = false
    @State private var hudCategory: HUDView.Category? = nil
    @State private var userIsLeavingGroup: Bool = false
    
    
    private func userTappedOnTheEditCustomNameAndPhotoButton() {
        navigation.userWantsToEditGroupNicknameAndCustomPicture(self, groupIdentifier: groupIdentifier)
    }
    
    private func userTappedTheDisbandGroupButton() {
        showDisbandConfirmationDialog = true
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
    
    private func userTappedOnCloneGroupButton() {
        Task {
            do {
                try await navigation.userWantsToCloneGroup(self, groupIdentifier: groupIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
    private func userTappedOnManualResyncOfGroupV2Button() {
        hudCategory = .progress
        Task {
            do {
                try await actions.userTappedOnManualResyncOfGroupV2Button(self, groupIdentifier: groupIdentifier)
                hudCategory = .checkmark
            } catch {
                assertionFailure()
                hudCategory = .xmark
            }
            try? await Task.sleep(seconds: 1)
            hudCategory = nil
        }
    }
    
    private var systemIconForMenu: SystemIcon {
        if #available(iOS 26, *) {
            return .ellipsis
        } else {
            return .ellipsisCircle
        }
    }
    
    @State private var isPersonalNoteEditorViewPresented: Bool = false
    
    public var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .ignoresSafeArea(.all)
            InternalView(groupIdentifier: groupIdentifier,
                         dataSource: dataSource,
                         subDataSources: subDataSources,
                         internalActions: self,
                         actions: actions,
                         navigation: navigation,
                         uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet,
                         groupModel: groupModel,
                         trustedPhoto: trustedPhoto,
                         customPhoto: customPhoto,
                         userIsDisbandingGroup: userIsDisbandingGroup,
                         hudCategory: $hudCategory,
                         userIsLeavingGroup: $userIsLeavingGroup)
            if groupModel == nil {
                if groupModelWasSetAtLeastOnce {
                    ObvContentUnavailableView(
                        title: String(localizedInThisBundle: "GROUP_WAS_DELETED_TITLE"),
                        systemIcon: .person2SlashFill,
                        description: String(localizedInThisBundle: "GROUP_WAS_DELETED_DESCRIPTION"))
                } else {
                    ProgressView()
                }
            }
            if let hudCategory = self.hudCategory {
                HUDView(category: hudCategory)
            }
        }
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Section {
                        Button(action: { isPersonalNoteEditorViewPresented = true }) {
                            Label { Text("EDIT_PERSONAL_NOTE") } icon: { Image(systemIcon: .noteText) }
                        }
                        Button(action: userTappedOnTheEditCustomNameAndPhotoButton) {
                            Label { Text("EDIT_NICKNAME_AND_CUSTOM_PHOTO") } icon: { Image(systemIcon: .camera(.none)) }
                        }
                    }
                    Section {
                        Button(action: userTappedOnCloneGroupButton) {
                            Label { Text("CLONE_THIS_GROUP") } icon: { Image(systemIcon: .docOnDoc) }
                        }
                    }
                    Section {
                        Button(action: userTappedOnManualResyncOfGroupV2Button) {
                            Label { Text("MANUAL_RESYNC_OF_GROUP_V2") } icon: { Image(systemIcon: .arrowTriangle2CirclepathCircle) }
                        }
                        if let groupModel, groupModel.ownedIdentityIsAdmin {
                            Button(role: .destructive, action: userTappedTheDisbandGroupButton) {
                                Label { Text("DISBAND_GROUP") } icon: { Image(systemIcon: .trash) }
                            }
                        }
                    }
                } label: {
                    Image(systemIcon: systemIconForMenu)
                }
                
            }
        }
        .onChange(of: groupModel) { newValue in
            if newValue != nil { groupModelWasSetAtLeastOnce = true }
        }
        .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isPersonalNoteEditorViewPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
            if let groupModel {
                PersonalNoteEditorView(model: .init(initialText: groupModel.personalNote,
                                                    about: .groupV2(groupModel.groupIdentifier)),
                                       actions: actions,
                                       navigation: self)
            }
        }
        .confirmationDialog(String(localizedInThisBundle: "SINGLE_GROUP_V2_VIEW_SHEET_CONFIRM_DISBAND_GROUP_TITLE"),
                            isPresented: $showDisbandConfirmationDialog,
                            titleVisibility: .visible) {
            Button(String(localizedInThisBundle: "DISBAND_GROUP"), role: .destructive, action: userConfirmedSheWantsToDisbandTheGroup)
        } message: { Text("SINGLE_GROUP_V2_VIEW_SHEET_CONFIRM_DISBAND_GROUP_MESSAGE") }
            .navigationTitle(groupModel?.nickname ?? groupModel?.trustedName ?? "")
    }
    
    
    private struct InternalView: View {
        
        let groupIdentifier: ObvGroupV2Identifier
        
        let dataSource: any SingleGroupV2MainViewDataSource
        let subDataSources: SubDataSources
        let internalActions: any InternalViewActions
        let actions: any SingleGroupV2MainViewActionsProtocol
        let navigation: any SingleGroupV2MainViewNavigation
        let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
        
        let groupModel: SingleGroupV2MainViewModel?
        let trustedPhoto: UIImage?
        let customPhoto: UIImage?
        let userIsDisbandingGroup: Bool
        @Binding var hudCategory: HUDView.Category? // Must be a binding
        @Binding var userIsLeavingGroup: Bool // Must be a binding
        
        private func circleAndTitlesViewModelForHeader(model: SingleGroupV2MainViewModel) -> CircleAndTitlesView.Model {
            .init(content: circleAndTitlesViewModelContentForHeaderOrTrustedDetails(model: model),
                  colors: initialCircleViewModelColorsForHeaderOrTrustedDetails(model: model),
                  displayMode: .header,
                  editionMode: .none)
        }
        
        private func circleAndTitlesViewModelContentForHeaderOrTrustedDetails(model: SingleGroupV2MainViewModel) -> CircleAndTitlesView.Model.Content {
            .init(textViewModel: textViewModelForHeaderOrTrustedDetails(model: model),
                  profilePictureViewModelContent: profilePictureViewModelContentForHeaderOrTrustedDetails(model: model))
        }
        
        private func textViewModelForHeaderOrTrustedDetails(model: SingleGroupV2MainViewModel) -> TextView.Model {
            .init(titlePart1: model.nickname ?? model.trustedName,
                  titlePart2: nil,
                  subtitle: model.trustedDescription,
                  subsubtitle: nil)
        }
        
        private func initialCircleViewModelColorsForHeaderOrTrustedDetails(model: SingleGroupV2MainViewModel) -> InitialCircleView.Model.Colors {
            model.circleColors
        }
        
        private func profilePictureViewModelContentForHeaderOrTrustedDetails(model: SingleGroupV2MainViewModel) -> ProfilePictureView.Model.Content {
            .init(text: nil,
                  icon: .person3Fill,
                  profilePicture: customPhoto ?? trustedPhoto,
                  showGreenShield: model.isKeycloakManaged,
                  showRedShield: false)
        }
        
        private func userTappedTheChatButton() -> Void {
            internalActions.userTappedTheChatButton()
        }
        
        private func userTappedTheCallButton() -> Void {
            internalActions.userTappedTheCallButton()
        }
        
        private func adminsCanBeChanged(groupModel: SingleGroupV2MainViewModel) -> Bool {
            return ObvGroupType.adminCanSelectSpecificAdmins(groupType: groupModel.groupType)
        }
        
        private func userWantsToLeaveGroup() {
            internalActions.userWantsToLeaveGroup()
        }
        
        private var listOfGroupMembersViewSubDataSources: ListOfGroupMembersView.SubDataSources {
            .init(ownedIdentityAsGroupMemberViewDataSource: subDataSources.ownedIdentityAsGroupMemberViewDataSource,
                  singleGroupMemberViewDataSource: subDataSources.singleGroupMemberViewDataSource,
                  avatarViewDataSource: subDataSources.avatarViewDataSource,
                  selectUsersToAddViewDataSource: subDataSources.selectUsersToAddViewDataSource,
                  listOfUsersViewCellDataSource: subDataSources.listOfUsersViewCellDataSource)
        }
        
        private var groupAdministrationViewSubDataSources: GroupAdministrationView.SubDataSources {
            .init(editGroupNameAndPictureViewDataSource: subDataSources.editGroupNameAndPictureViewDataSource,
                  editGroupTypeViewDataSource: subDataSources.editGroupTypeViewDataSource,
                  avatarViewDataSource: subDataSources.avatarViewDataSource,
                  editGroupTypeNavigationStackSubDataSources: subDataSources.editGroupTypeNavigationStackSubDataSources)
        }
        
        var body: some View {
            ScrollView {
                if let model = self.groupModel {
                    
                    VStack {
                        
                        // Header
                        
                        CircleAndTitlesView(model: circleAndTitlesViewModelForHeader(model: model))
                            .padding(.top, 16)
                        
                        // Chat and call buttons
                        
                        ObvChatAndCallButtonsView(callButtonIsDisabled: false,
                                                  userTappedTheChatButton: userTappedTheChatButton,
                                                  userTappedTheCallButton: userTappedTheCallButton)
                        .padding(.top, 16)
                        
                        // Personal note viewer
                        
                        if let personalNote = model.personalNote, !personalNote.isEmpty {
                            PersonalNoteStaticView(personalNote: personalNote)
                                .padding(.top, 16)
                        }
                        
                        // View shown when an update is in progress
                        
                        if model.updateInProgress {
                            UpdateInProgressView()
                                .padding(.top, 16)
                        }
                        
                        // Card shown when there are published details that the user needs to accept
                        
                        if let publishedDetailsForValidation = model.publishedDetailsForValidation, !publishedDetailsForValidation.differences.isEmpty {
                            GroupPublishedDetailsValidationView(
                                model: publishedDetailsForValidation,
                                avatarViewDataSource: subDataSources.avatarViewDataSource,
                                actions: actions)
                            .padding(.top, 16)
                        }
                        
                        // Group Administration
                        
                        if model.ownedIdentityIsAdmin {
                            GroupAdministrationView(
                                groupIdentifier: groupIdentifier,
                                adminsCanBeChanged: adminsCanBeChanged(groupModel: model),
                                subDataSources: groupAdministrationViewSubDataSources,
                                navigation: navigation,
                                actions: actions,
                                uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                            .padding(.top, 16)
                        }
                        
                        // Group members
                        
                        ListOfGroupMembersView(groupIdentifier: .groupV2(model.groupIdentifier),
                                               maximumNumberOfGroupMembersShown: 5,
                                               dataSource: subDataSources.listOfGroupMembersViewDataSource,
                                               subDataSources: listOfGroupMembersViewSubDataSources,
                                               actions: actions,
                                               navigation: navigation,
                                               uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                        .padding(.top, 16)
                        
                        // Group members that can be invited to a one-to-one discussion
                        
                        OneToOneInvitableView(groupIdentifier: .groupV2(groupIdentifier),
                                              dataSource: subDataSources.oneToOneInvitableViewDataSource,
                                              navigation: navigation)
                        .padding(.top, 16)
                        
                        // Leave group button
                        
                        LeaveGroupButtonAndConfirmationsView(ownedIdentityCanLeaveGroup: model.ownedIdentityCanLeaveGroup,
                                                             userWantsToLeaveGroup: userWantsToLeaveGroup)
                        .padding(.top, 16)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                    .disabled(userIsLeavingGroup || userIsDisbandingGroup)
                    
                } else {
                    
                    // Prevents an animation glitch on the tabbar
                    // This rectangle must be inside the ScrollView
                    Rectangle()
                        .opacity(0)
                        .frame(height: UIScreen.main.bounds.size.height)
                    
                }
            }
        }
        
    }
    
}



extension SingleGroupV2MainView: PersonalNoteEditorViewNavigation {

    public func userWantsToDismissPersonalNoteEditorView(_ view: PersonalNoteEditorView) {
        self.isPersonalNoteEditorViewPresented = false
    }

}


extension SingleGroupV2MainView {
    
    private func onAppear() {
        Task {
            do {
                let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfSingleGroupV2MainViewModel(self, groupIdentifier: groupIdentifier)
                if let previousStreamUUID = self.streamUUID {
                    dataSource.finishAsyncSequenceOfSingleGroupV2MainViewModel(self, streamUUID: previousStreamUUID)
                }
                self.streamUUID = streamUUID
                for await item in stream {
                    
                    switch item {
                        
                    case .groupNotFound:
                        
                        // This typically happens if userIsLeavingGroup or userIsDisbandingGroup is true,
                        // or when the group is disbanded by another user while the current user is displaying this view
                        
                        withAnimation {
                            self.groupModel = nil
                            self.trustedPhoto = nil
                            self.customPhoto = nil
                        }
                        
                        navigation.userWantsToLeaveGroupFlow(self)
                        
                    case .model(let model):
                        let previousCustomPhotoURL = self.groupModel?.customPhotoURL
                        let previousTrustedPhotoURL = self.groupModel?.trustedPhotoURL
                        
                        if self.groupModel == nil {
                            self.groupModel = model
                        } else {
                            withAnimation {
                                self.groupModel = model
                            }
                        }
                        
                        let newCustomPhotoURL = self.groupModel?.customPhotoURL
                        let newTrustedPhotoURL = self.groupModel?.trustedPhotoURL
                        
                        try? await fetchAndSetCustomPhoto(previousCustomPhotoURL: previousCustomPhotoURL, newCustomPhotoURL: newCustomPhotoURL)
                        try? await fetchAndSetTrustedPhoto(previousTrustedPhotoURL: previousTrustedPhotoURL, newTrustedPhotoURL: newTrustedPhotoURL)
                    }
                    
                }
            } catch {
                // Do nothing for now
            }
        }
    }
    
    
    private func onDisappear() {
        guard let previousStreamUUID = self.streamUUID else { return }
        dataSource.finishAsyncSequenceOfSingleGroupV2MainViewModel(self, streamUUID: previousStreamUUID)
        self.streamUUID = nil
    }
    
    
    private func fetchAndSetCustomPhoto(previousCustomPhotoURL: URL?, newCustomPhotoURL: URL?) async throws {
        guard previousCustomPhotoURL != newCustomPhotoURL else { return }
        withAnimation {
            self.customPhoto = nil
        }
        guard let newCustomPhotoURL else { return }
        // Quick and dirty: we enforce a `.xLarge` avatar size as this is coherent with the `.header` display mode chosen in circleAndTitlesViewModelForHeader.
        let customPhoto = try await subDataSources.avatarViewDataSource.fetchAvatarForLegacyViews(photoURL: newCustomPhotoURL, avatarSize: .xLarge)
        if groupModel?.customPhotoURL == newCustomPhotoURL {
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
        let trustedPhoto = try await subDataSources.avatarViewDataSource.fetchAvatarForLegacyViews(photoURL: newTrustedPhotoURL, avatarSize: .xLarge)
        if groupModel?.trustedPhotoURL == newTrustedPhotoURL {
            self.trustedPhoto = trustedPhoto
        }
    }

}


extension SingleGroupV2MainView: InternalViewActions {
    
    func userTappedTheChatButton() {
        Task {
            await navigation.userWantsToChat(self, groupIdentifier: groupIdentifier)
        }
    }
    
    func userTappedTheCallButton() {
        navigation.userWantsToCall(self, groupIdentifier: groupIdentifier)
    }
    
    func userWantsToLeaveGroup() {
        userIsLeavingGroup = true
        hudCategory = .progress
        Task {
            defer { hudCategory = nil }
            do {
                try await actions.userWantsToLeaveGroup(self, groupIdentifier: groupIdentifier)
                guard !Task.isCancelled else { return }
                hudCategory = .checkmark
            } catch {
                hudCategory = .xmark
                userIsLeavingGroup = false
                assertionFailure()
            }
        }
    }
    
}


@MainActor
private protocol InternalViewActions {
    func userTappedTheChatButton() -> Void
    func userTappedTheCallButton() -> Void
    func userWantsToLeaveGroup()
}




// MARK: - Subview: Leave group button and confirmations

private struct LeaveGroupButtonAndConfirmationsView: View {
    
    let ownedIdentityCanLeaveGroup: SingleGroupV2MainViewModel.CanLeaveGroup
    let userWantsToLeaveGroup: () -> Void

    @State private var showLeaveGroupDialog: Bool = false
    @State private var showCannotLeaveGroupAsWeAreTheOnlyAdminAlert: Bool = false
    @State private var showCannotLeaveGroupAsThisIsKeycloakGroupAlert: Bool = false

    private func action() {
        switch ownedIdentityCanLeaveGroup {
        case .canLeaveGroup:
            showLeaveGroupDialog = true
        case .cannotLeaveGroupAsWeAreTheOnlyAdmin:
            showCannotLeaveGroupAsWeAreTheOnlyAdminAlert = true
        case .cannotLeaveGroupAsThisIsKeycloakGroup:
            showCannotLeaveGroupAsThisIsKeycloakGroupAlert = true
        }
    }
    
    var body: some View {
        OlvidButtonNew(action: action) {
            Label(title: { Text("LEAVE_GROUP") }, icon: { Image(systemIcon: .xmarkOctagon) })
        }
        .tint(.red)
        .alert(String(localizedInThisBundle: "SINGLE_GROUP_V2_VIEW_ALERT_CANNOT_LEAVE_GROUP_TITLE"),
               isPresented: $showCannotLeaveGroupAsWeAreTheOnlyAdminAlert,
               actions: {},
               message: { Text("SINGLE_GROUP_V2_VIEW_ALERT_CANNOT_LEAVE_GROUP_MESSAGE") })
        .alert(String(localizedInThisBundle: "SINGLE_GROUP_V2_VIEW_ALERT_CANNOT_LEAVE_GROUP_AS_KEYCLOAK_TITLE"),
               isPresented: $showCannotLeaveGroupAsThisIsKeycloakGroupAlert,
               actions: {},
               message: { Text("SINGLE_GROUP_V2_VIEW_ALERT_CANNOT_LEAVE_GROUP_AS_KEYCLOAK_MESSAGE") })
        .confirmationDialog(String(localizedInThisBundle: "SINGLE_GROUP_V2_VIEW_SHEET_CONFIRM_LEAVE_GROUP_TITLE"),
                            isPresented: $showLeaveGroupDialog,
                            titleVisibility: .visible) {
            Button(String(localizedInThisBundle: "LEAVE_GROUP"), role: .destructive, action: userWantsToLeaveGroup)
        } message: { Text("SINGLE_GROUP_V2_VIEW_SHEET_CONFIRM_LEAVE_GROUP_MESSAGE") }
    }
    
    
}


// MARK: - Subview: Group administration

@MainActor
public protocol GroupAdministrationViewNavigation {
    func userWantsToNavigateToViewAllowingToModifyMembers(_ view: GroupAdministrationView, groupIdentifier: ObvGroupV2Identifier)
    func userWantsToNavigateToViewAllowingToManageAdmins(_ view: GroupAdministrationView, groupIdentifier: ObvGroupV2Identifier)
}

public struct GroupAdministrationView: View {
    
    let groupIdentifier: ObvGroupV2Identifier
    let adminsCanBeChanged: Bool
    let subDataSources: SubDataSources
    let navigation: any GroupAdministrationViewNavigation
    let actions: any EditGroupNameAndPictureViewActionsProtocol & EditGroupTypeViewActionsForEdition & EditGroupTypeNavigationStackActions & EditGroupNameAndPictureViewActionsForEdition
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
    
    struct SubDataSources {
        let editGroupNameAndPictureViewDataSource: any EditGroupNameAndPictureViewDataSource
        let editGroupTypeViewDataSource: any EditGroupTypeViewDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        let editGroupTypeNavigationStackSubDataSources: EditGroupTypeNavigationStack.SubDataSources
    }
    
    @State private var isEditGroupNameAndPictureViewPresented: Bool = false
    @State private var isEditGroupTypeNavigationStackPresented: Bool = false
    
    private func modifyGroupNameButtonTapped() {
        isEditGroupNameAndPictureViewPresented = true
    }
    
    private func modifyMemberButtonTapped() {
        navigation.userWantsToNavigateToViewAllowingToModifyMembers(self, groupIdentifier: groupIdentifier)
    }
    
    private func groupTypesButtonTapped() {
        isEditGroupTypeNavigationStackPresented = true
    }
    
    private func manageAdminsButtonTapped() {
        navigation.userWantsToNavigateToViewAllowingToManageAdmins(self, groupIdentifier: groupIdentifier)
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
    
    public var body: some View {
        
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
                    DividerWithLeadingPadding()
                    Button(action: groupTypesButtonTapped) {
                        ButtonContent(systemIcon: .wrenchAdjustableFill,
                                      systemIconSize: 14,
                                      systemIconColor: .white,
                                      backgroundColor: .cyan,
                                      text: String(localizedInThisBundle: "GROUP_TYPES_BUTTON_TITLE"))
                    }
                    if adminsCanBeChanged {
                        DividerWithLeadingPadding()
                        Button(action: manageAdminsButtonTapped) {
                            ButtonContent(systemIcon: .starFill,
                                          systemIconSize: 17,
                                          systemIconColor: .white,
                                          backgroundColor: .indigo,
                                          text: String(localizedInThisBundle: "MANAGE_ADMINS_BUTTON_TITLE"))
                        }
                    }
                }
            }

        }
        .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isEditGroupNameAndPictureViewPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
            NavigationStack {
                EditGroupNameAndPictureView(
                    mode: .edition(groupIdentifier: .groupV2(groupIdentifier),
                                   navigation: self,
                                   dataSource: subDataSources.editGroupNameAndPictureViewDataSource,
                                   avatarViewDataSource: subDataSources.avatarViewDataSource,
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
        .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isEditGroupTypeNavigationStackPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
            EditGroupTypeNavigationStack(groupIdentifier: groupIdentifier,
                                         subDataSources: subDataSources.editGroupTypeNavigationStackSubDataSources,
                                         actions: actions,
                                         navigation: self,
                                         uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
        }
        
    }
}


extension GroupAdministrationView: EditGroupTypeNavigationStackNavigation {

    func editGroupTypeNavigationStackShouldBeDismissedAsGroupWasDisbanded(_ view: EditGroupTypeNavigationStack) {
        isEditGroupTypeNavigationStackPresented = false
    }
    
    func editGroupTypeNavigationStackShouldBeDismissed(_ view: EditGroupTypeNavigationStack) {
        isEditGroupTypeNavigationStackPresented = false
    }
    
    func userTappedOnTheCancelButtonOfTheEditGroupTypeNavigationStack(_ view: EditGroupTypeNavigationStack) {
        isEditGroupTypeNavigationStackPresented = false
    }
    
}


extension GroupAdministrationView: EditGroupNameAndPictureViewNavigationDuringEdition {
    
    public func userWantsToLeaveGroupFlow(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {
        isEditGroupNameAndPictureViewPresented = false
    }
    
    public func groupDetailsWereSuccessfullyUpdated(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.InternalView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {
        isEditGroupNameAndPictureViewPresented = false
    }
        
}















// MARK: - Previews

#if DEBUG


private final class SingleGroupV2MainViewNavigationForPreviews {
}

extension SingleGroupV2MainViewNavigationForPreviews: GroupAdministrationViewNavigation {
    func userWantsToNavigateToViewAllowingToModifyMembers(_ view: GroupAdministrationView, groupIdentifier: ObvGroupV2Identifier) {}
    func userWantsToNavigateToViewAllowingToManageAdmins(_ view: GroupAdministrationView, groupIdentifier: ObvGroupV2Identifier) {}
}

extension SingleGroupV2MainViewNavigationForPreviews: SingleGroupMemberViewNavigation {
    func userWantsToShowOtherUserProfile(_ view: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.InternalView, contactIdentifier: ObvTypes.ObvContactIdentifier) async {}
}

extension SingleGroupV2MainViewNavigationForPreviews: ListOfGroupMembersViewNavigation {
    func userWantsToNavigateToFullListOfOtherGroupMembers(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) async {}
}

extension SingleGroupV2MainViewNavigationForPreviews: OneToOneInvitableViewNavigation {
    func userWantsToNavigateToViewAllowingToSelectGroupMembersToInviteToOneToOne(_ view: OneToOneInvitableView.InternalView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {}
}

extension SingleGroupV2MainViewNavigationForPreviews: EditGroupNameAndPictureViewNavigationDuringEdition, EditGroupNameAndPictureViewNavigationDuringCreation {
    func userWantsToLeaveGroupFlow(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {}
    func groupDetailsWereSuccessfullyUpdated(_ view: ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.InternalView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {}
    func groupWasSuccessfullyCreated(_ view: EditGroupNameAndPictureView.InternalView, ownedCryptoId: ObvCryptoId) {}
}

extension SingleGroupV2MainViewNavigationForPreviews: EditGroupTypeViewNavigationDuringEdition, EditGroupTypeViewNavigationDuringCreation {
    func userWantsToLeaveGroupFlowAsGroupWasDisbanded(_ view: EditGroupTypeView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {}
    func userChosedGroupTypeAndWantsToSelectAdmins(_ view: EditGroupTypeView, groupIdentifier: ObvTypes.ObvGroupV2Identifier, selectedGroupType: ObvAppTypes.ObvGroupType) {}
    func userChosedGroupTypeDuringGroupCreation(_ view: EditGroupTypeView, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, selectedGroupType: ObvAppTypes.ObvGroupType) {}
    func editGroupTypeViewShouldBeDismissed(_ view: EditGroupTypeView, groupIdentifier: ObvGroupV2Identifier) {}
}

extension SingleGroupV2MainViewNavigationForPreviews: SingleGroupV2MainViewNavigation {
    func userWantsToChat(_ view: SingleGroupV2MainView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {}
    func userWantsToCall(_ view: SingleGroupV2MainView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {}
    func userWantsToLeaveGroupFlow(_ view: SingleGroupV2MainView) {}
    func userWantsToEditGroupNicknameAndCustomPicture(_ view: SingleGroupV2MainView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {}
    func userWantsToCloneGroup(_ view: SingleGroupV2MainView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws {}
}

extension SingleGroupV2MainViewNavigationForPreviews: UIKitDelegateForSwiftUISheet {
    func userWantsToPresentView<Content>(_ view: some View, content: @escaping () -> Content) where Content : View {
        // We don't implement this method. Consequently certain views cannot be presented when showing previews on catalyst.
    }
    func userWantsToDismissPresentedView(_ view: some View) {}
}

@MainActor
private let actionsForPreviews = GenericActionsForPreviews()

@MainActor
private let dataSourceForPreviews = GenericDataSourceForPreviews()

@MainActor
private let navigationForPreviews = SingleGroupV2MainViewNavigationForPreviews()

@MainActor
private let subDataSourcesForPreviews: SingleGroupV2MainView.SubDataSources = .init(
    listOfGroupMembersViewDataSource: dataSourceForPreviews,
    ownedIdentityAsGroupMemberViewDataSource: dataSourceForPreviews,
    singleGroupMemberViewDataSource: dataSourceForPreviews,
    oneToOneInvitableViewDataSource: dataSourceForPreviews,
    avatarViewDataSource: dataSourceForPreviews,
    editGroupNameAndPictureViewDataSource: dataSourceForPreviews,
    editGroupTypeViewDataSource: dataSourceForPreviews,
    selectUsersToAddViewDataSource: dataSourceForPreviews,
    listOfUsersViewCellDataSource: dataSourceForPreviews,
    editGroupTypeNavigationStackSubDataSources: .init(
        fullListOfGroupMembersViewDataSource: dataSourceForPreviews,
        editGroupTypeViewDataSource: dataSourceForPreviews,
        fullListOfGroupMembersViewSubDataSources: .init(
            singleGroupMemberViewDataSource: dataSourceForPreviews,
            selectUsersToAddViewDataSource: dataSourceForPreviews,
            listOfUsersViewCellDataSource: dataSourceForPreviews,
            ownedIdentityAsGroupMemberViewDataSource: dataSourceForPreviews,
            avatarViewDataSource: dataSourceForPreviews,
            listOfGroupMembersViewDataSource: dataSourceForPreviews,
            selectUsersToRemoveViewDataSource: dataSourceForPreviews))
    )

#Preview {
    SingleGroupV2MainView(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0],
                          dataSource: dataSourceForPreviews,
                          subDataSources: subDataSourcesForPreviews,
                          actions: actionsForPreviews,
                          navigation: navigationForPreviews,
                          uiKitDelegateForSwiftUISheet: navigationForPreviews)
}

@MainActor
private final class DataSourceWithMemberUpdatesForPreviews {}

extension DataSourceWithMemberUpdatesForPreviews {
    
    enum ObvError: Error {
        case error
    }
    
}

extension DataSourceWithMemberUpdatesForPreviews: SingleGroupV2MainViewDataSource {

    func getAsyncSequenceOfSingleGroupV2MainViewModel(_ view: SingleGroupV2MainView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV2MainViewModelOrNotFound>) {
        let stream = AsyncStream(SingleGroupV2MainViewModelOrNotFound.self) { (continuation: AsyncStream<SingleGroupV2MainViewModelOrNotFound>.Continuation) in
            let model = PreviewsHelper.singleGroupV2MainViewModels[0]
            continuation.yield(.model(model: model))
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(_ view: SingleGroupV2MainView, streamUUID: UUID) {
        // Nothing to terminate in these previews
    }
    
}


extension DataSourceWithMemberUpdatesForPreviews: ListOfGroupMembersViewDataSource {
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel>) {
        let stream = AsyncStream(ListOfSingleGroupMemberViewModel.self) { (continuation: AsyncStream<ListOfSingleGroupMemberViewModel>.Continuation) in
            Task {
                let oneGroupMember: [SingleGroupMemberView.Model.Identifier] = [.contactIdentifierForExistingGroupForPreviews(groupIdentifier: groupIdentifier, contactIdentifier: PreviewsHelper.groupMembers.first!.contactIdentifier)]
                let modelWithOneGroupMember = ListOfSingleGroupMemberViewModel(otherGroupMembers: oneGroupMember)
                continuation.yield(modelWithOneGroupMember)
                try! await Task.sleep(seconds: 5)
                let twoGroupMembers = oneGroupMember + [.contactIdentifierForExistingGroupForPreviews(groupIdentifier: groupIdentifier, contactIdentifier: PreviewsHelper.groupMembers[1].contactIdentifier)]
                let modelWithTwoGroupMembers = ListOfSingleGroupMemberViewModel(otherGroupMembers: twoGroupMembers)
                continuation.yield(modelWithTwoGroupMembers)
                try! await Task.sleep(seconds: 5)
                let threeGroupMembers = twoGroupMembers + [.contactIdentifierForExistingGroupForPreviews(groupIdentifier: groupIdentifier, contactIdentifier: PreviewsHelper.groupMembers[2].contactIdentifier)]
                let modelWithThreeGroupMembers = ListOfSingleGroupMemberViewModel(otherGroupMembers: threeGroupMembers)
                continuation.yield(modelWithThreeGroupMembers)
            }
        }
        return (UUID(), stream)
    }
    
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, streamUUID: UUID, searchText: String?) {}
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, streamUUID: UUID) {}
    
}


extension DataSourceWithMemberUpdatesForPreviews: OwnedIdentityAsGroupMemberViewDataSource {
    
    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberViewModel>) {
        let stream = AsyncStream(OwnedIdentityAsGroupMemberViewModel.self) { (continuation: AsyncStream<OwnedIdentityAsGroupMemberViewModel>.Continuation) in
            let model = OwnedIdentityAsGroupMemberViewModel.sampleData
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, streamUUID: UUID) {}
    
}


extension DataSourceWithMemberUpdatesForPreviews: SingleGroupMemberViewDataSource {
    
    func getAsyncSequenceOfSingleGroupMemberViewModels(_ view: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView, withIdentifier identifier: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model>) {
        switch identifier {
        case .contactIdentifierForExistingGroupForPreviews(_, let contactIdentifier), .contactIdentifierForCreatingGroupForPreviews(contactIdentifier: let contactIdentifier):
            let stream = AsyncStream(SingleGroupMemberView.Model.self) { (continuation: AsyncStream<SingleGroupMemberView.Model>.Continuation) in
                if let groupMember = PreviewsHelper.groupMembers.first(where: { $0.contactIdentifier == contactIdentifier }) {
                    continuation.yield(groupMember)
                }
            }
            return (UUID(), stream)
        case .objectIDOfPersistedGroupV2Member, .objectIDOfPersistedContact, .objectIDOfPersistedPendingGroupMember:
            throw ObvError.error
        }
    }
    
    func finishAsyncSequenceOfSingleGroupMemberViewModels(_ view: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView, withIdentifier identifier: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model.Identifier, streamUUID: UUID) {}
        
}


extension DataSourceWithMemberUpdatesForPreviews: OneToOneInvitableViewDataSource {
    
    func getAsyncSequenceOfOneToOneInvitableViewModel(_ view: OneToOneInvitableView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<OneToOneInvitableViewModel>) {
        let stream = AsyncStream(OneToOneInvitableViewModel.self) { (continuation: AsyncStream<OneToOneInvitableViewModel>.Continuation) in
            let model = OneToOneInvitableViewModel(numberOfGroupMembersThatAreContactsButNotOneToOne: 2, numberOfOneToOneInvitationsSent: 2, numberOfPendingMembersWithNoAssociatedContact: 0, groupHasNoOtherMember: false)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOneToOneInvitableViewModel(_ view: OneToOneInvitableView, streamUUID: UUID) {}
    
}


@MainActor
private let dataSourceWithUpdates = DataSourceWithMemberUpdatesForPreviews()

@MainActor
private let genericDataSourceForPreviews = GenericDataSourceForPreviews()

#Preview("Update members") {
    SingleGroupV2MainView(
        groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0],
        dataSource: dataSourceWithUpdates,
        subDataSources: .init(listOfGroupMembersViewDataSource: dataSourceWithUpdates,
                              ownedIdentityAsGroupMemberViewDataSource: dataSourceWithUpdates,
                              singleGroupMemberViewDataSource: dataSourceWithUpdates,
                              oneToOneInvitableViewDataSource: dataSourceWithUpdates,
                              avatarViewDataSource: genericDataSourceForPreviews,
                              editGroupNameAndPictureViewDataSource: genericDataSourceForPreviews,
                              editGroupTypeViewDataSource: genericDataSourceForPreviews,
                              selectUsersToAddViewDataSource: dataSourceForPreviews,
                              listOfUsersViewCellDataSource: dataSourceForPreviews,
                              editGroupTypeNavigationStackSubDataSources: .init(
                                fullListOfGroupMembersViewDataSource: genericDataSourceForPreviews,
                                editGroupTypeViewDataSource: genericDataSourceForPreviews,
                                fullListOfGroupMembersViewSubDataSources: .init(
                                    singleGroupMemberViewDataSource: dataSourceWithUpdates,
                                    selectUsersToAddViewDataSource: genericDataSourceForPreviews,
                                    listOfUsersViewCellDataSource: genericDataSourceForPreviews,
                                    ownedIdentityAsGroupMemberViewDataSource: dataSourceWithUpdates,
                                    avatarViewDataSource: genericDataSourceForPreviews,
                                    listOfGroupMembersViewDataSource: genericDataSourceForPreviews,
                                    selectUsersToRemoveViewDataSource: genericDataSourceForPreviews))),
        actions: actionsForPreviews,
        navigation: navigationForPreviews,
        uiKitDelegateForSwiftUISheet: navigationForPreviews)
}


@MainActor
private final class DataSourceAllowingToAcceptPublishedDetails {
    
    var model = PreviewsHelper.singleGroupV2MainViewModels[0]
    var continuations = [UUID: AsyncStream<SingleGroupV2MainViewModelOrNotFound>.Continuation]()
    
}

extension DataSourceAllowingToAcceptPublishedDetails: SingleGroupV2MainViewDataSource {
        
    func updateModel(model: SingleGroupV2MainViewModel) {
        self.model = model
        continuations.values.forEach { continuation in
            continuation.yield(.model(model: model))
        }
    }
     
    
    func getAsyncSequenceOfSingleGroupV2MainViewModel(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV2MainViewModelOrNotFound>) {
        let streamUUID = UUID()
        let stream = AsyncStream(SingleGroupV2MainViewModelOrNotFound.self) { (continuation: AsyncStream<SingleGroupV2MainViewModelOrNotFound>.Continuation) in
            continuations[streamUUID] = continuation
            continuation.yield(.model(model: model))
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(_ view: SingleGroupV2MainView, streamUUID: UUID) {
        if let continuation = continuations.removeValue(forKey: streamUUID) {
            continuation.finish()
        }
    }
    
    enum ObvError: Error {
        case error
    }
    
}



@MainActor
private class ActionsAllowingToAcceptPublishedDetailsForPreviews: GenericActionsForPreviews {
    
    let dataSource = DataSourceAllowingToAcceptPublishedDetails()

    override func userWantsToReplaceTrustedDetailsByPublishedDetails(_ view: GroupPublishedDetailsValidationView, publishedDetails: PublishedDetailsValidationViewModel) async throws {
        let model = dataSource.model
        let newModel = SingleGroupV2MainViewModel(
            groupIdentifier: model.groupIdentifier,
            trustedName: publishedDetails.publishedName,
            trustedDescription: publishedDetails.publishedDescription,
            trustedPhotoURL: publishedDetails.publishedPhotoURL,
            customPhotoURL: model.customPhotoURL,
            nickname: model.nickname,
            isKeycloakManaged: model.isKeycloakManaged,
            circleColors: model.circleColors,
            updateInProgress: model.updateInProgress,
            ownedIdentityIsAdmin: model.ownedIdentityIsAdmin,
            ownedIdentityCanLeaveGroup: model.ownedIdentityCanLeaveGroup,
            publishedDetailsForValidation: nil,
            personalNote: model.personalNote,
            groupType: .standard)
        dataSource.updateModel(model: newModel)
    }

}


extension DataSourceAllowingToAcceptPublishedDetails: ListOfGroupMembersViewDataSource {
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel>) {
        let stream = AsyncStream(ListOfSingleGroupMemberViewModel.self) { (continuation: AsyncStream<ListOfSingleGroupMemberViewModel>.Continuation) in
            Task {
                let oneGroupMember: [SingleGroupMemberView.Model.Identifier] = [.contactIdentifierForExistingGroupForPreviews(groupIdentifier: groupIdentifier, contactIdentifier: PreviewsHelper.groupMembers.first!.contactIdentifier)]
                let modelWithOneGroupMember = ListOfSingleGroupMemberViewModel(otherGroupMembers: oneGroupMember)
                continuation.yield(modelWithOneGroupMember)
                try! await Task.sleep(seconds: 5)
                let twoGroupMembers = oneGroupMember + [.contactIdentifierForExistingGroupForPreviews(groupIdentifier: groupIdentifier, contactIdentifier: PreviewsHelper.groupMembers[1].contactIdentifier)]
                let modelWithTwoGroupMembers = ListOfSingleGroupMemberViewModel(otherGroupMembers: twoGroupMembers)
                continuation.yield(modelWithTwoGroupMembers)
                try! await Task.sleep(seconds: 5)
                let threeGroupMembers = twoGroupMembers + [.contactIdentifierForExistingGroupForPreviews(groupIdentifier: groupIdentifier, contactIdentifier: PreviewsHelper.groupMembers[2].contactIdentifier)]
                let modelWithThreeGroupMembers = ListOfSingleGroupMemberViewModel(otherGroupMembers: threeGroupMembers)
                continuation.yield(modelWithThreeGroupMembers)
            }
        }
        return (UUID(), stream)
    }
    
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, streamUUID: UUID, searchText: String?) {}
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, streamUUID: UUID) {}
    
}


extension DataSourceAllowingToAcceptPublishedDetails: OwnedIdentityAsGroupMemberViewDataSource {
    
    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberViewModel>) {
        let stream = AsyncStream(OwnedIdentityAsGroupMemberViewModel.self) { (continuation: AsyncStream<OwnedIdentityAsGroupMemberViewModel>.Continuation) in
            let model = OwnedIdentityAsGroupMemberViewModel.sampleData
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, streamUUID: UUID) {}
    
}


extension DataSourceAllowingToAcceptPublishedDetails: SingleGroupMemberViewDataSource {
    
    func getAsyncSequenceOfSingleGroupMemberViewModels(_ view: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView, withIdentifier identifier: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model>) {
        switch identifier {
        case .contactIdentifierForExistingGroupForPreviews(_, let contactIdentifier), .contactIdentifierForCreatingGroupForPreviews(contactIdentifier: let contactIdentifier):
            let stream = AsyncStream(SingleGroupMemberView.Model.self) { (continuation: AsyncStream<SingleGroupMemberView.Model>.Continuation) in
                if let groupMember = PreviewsHelper.groupMembers.first(where: { $0.contactIdentifier == contactIdentifier }) {
                    continuation.yield(groupMember)
                }
            }
            return (UUID(), stream)
        case .objectIDOfPersistedGroupV2Member, .objectIDOfPersistedContact, .objectIDOfPersistedPendingGroupMember:
            throw ObvError.error
        }
    }
    
    func finishAsyncSequenceOfSingleGroupMemberViewModels(_ view: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView, withIdentifier identifier: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model.Identifier, streamUUID: UUID) {}
        
}


extension DataSourceAllowingToAcceptPublishedDetails: OneToOneInvitableViewDataSource {
    
    func getAsyncSequenceOfOneToOneInvitableViewModel(_ view: OneToOneInvitableView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<OneToOneInvitableViewModel>) {
        let stream = AsyncStream(OneToOneInvitableViewModel.self) { (continuation: AsyncStream<OneToOneInvitableViewModel>.Continuation) in
            let model = OneToOneInvitableViewModel(numberOfGroupMembersThatAreContactsButNotOneToOne: 2, numberOfOneToOneInvitationsSent: 2, numberOfPendingMembersWithNoAssociatedContact: 0, groupHasNoOtherMember: false)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOneToOneInvitableViewModel(_ view: OneToOneInvitableView, streamUUID: UUID) {}
    
}

@MainActor
private let actionsAllowingToAcceptPublishedDetailsForPreviews = ActionsAllowingToAcceptPublishedDetailsForPreviews()


#Preview("Accept Published") {
    SingleGroupV2MainView(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0],
                          dataSource: actionsAllowingToAcceptPublishedDetailsForPreviews.dataSource,
                          subDataSources: .init(listOfGroupMembersViewDataSource: actionsAllowingToAcceptPublishedDetailsForPreviews.dataSource,
                                                ownedIdentityAsGroupMemberViewDataSource: actionsAllowingToAcceptPublishedDetailsForPreviews.dataSource,
                                                singleGroupMemberViewDataSource: actionsAllowingToAcceptPublishedDetailsForPreviews.dataSource,
                                                oneToOneInvitableViewDataSource: actionsAllowingToAcceptPublishedDetailsForPreviews.dataSource,
                                                avatarViewDataSource: genericDataSourceForPreviews,
                                                editGroupNameAndPictureViewDataSource: genericDataSourceForPreviews,
                                                editGroupTypeViewDataSource: genericDataSourceForPreviews,
                                                selectUsersToAddViewDataSource: dataSourceForPreviews,
                                                listOfUsersViewCellDataSource: dataSourceForPreviews,
                                                editGroupTypeNavigationStackSubDataSources: .init(
                                                    fullListOfGroupMembersViewDataSource: genericDataSourceForPreviews,
                                                    editGroupTypeViewDataSource: genericDataSourceForPreviews,
                                                    fullListOfGroupMembersViewSubDataSources: .init(
                                                        singleGroupMemberViewDataSource: actionsAllowingToAcceptPublishedDetailsForPreviews.dataSource,
                                                        selectUsersToAddViewDataSource: genericDataSourceForPreviews,
                                                        listOfUsersViewCellDataSource: genericDataSourceForPreviews,
                                                        ownedIdentityAsGroupMemberViewDataSource: actionsAllowingToAcceptPublishedDetailsForPreviews.dataSource,
                                                        avatarViewDataSource: genericDataSourceForPreviews,
                                                        listOfGroupMembersViewDataSource: genericDataSourceForPreviews,
                                                        selectUsersToRemoveViewDataSource: genericDataSourceForPreviews))),
                          actions: actionsAllowingToAcceptPublishedDetailsForPreviews,
                          navigation: navigationForPreviews,
                          uiKitDelegateForSwiftUISheet: navigationForPreviews)
}

#endif
