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


public enum SingleGroupV2MainViewModelOrNotFound: Sendable {
    case groupNotFound
    case model(model: SingleGroupV2MainViewModel)
}


public struct SingleGroupV2MainViewModel: Sendable {
    
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
    let groupType: ObvGroupType?
    
    public enum CanLeaveGroup: Sendable {
        case canLeaveGroup
        case cannotLeaveGroupAsWeAreTheOnlyAdmin
        case cannotLeaveGroupAsThisIsKeycloakGroup
    }

    public init(groupIdentifier: ObvGroupV2Identifier, trustedName: String, trustedDescription: String?, trustedPhotoURL: URL?, customPhotoURL: URL?, nickname: String?, isKeycloakManaged: Bool, circleColors: InitialCircleView.Model.Colors, updateInProgress: Bool, ownedIdentityIsAdmin: Bool, ownedIdentityCanLeaveGroup: CanLeaveGroup, publishedDetailsForValidation: PublishedDetailsValidationViewModel?, personalNote: String?, groupType: ObvGroupType?) {
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



public struct ListOfSingleGroupMemberViewModel: Sendable {
    
    // let groupIdentifier: ObvGroupV2Identifier
    let otherGroupMembers: [SingleGroupMemberViewModelIdentifier]
    
    public init(otherGroupMembers: [SingleGroupMemberViewModelIdentifier]) {
        //self.groupIdentifier = groupIdentifier
        self.otherGroupMembers = otherGroupMembers
    }
    
}



@MainActor
protocol SingleGroupV2MainViewDataSource: ListOfGroupMembersViewDataSource, SingleGroupMemberViewDataSource, PublishedDetailsValidationViewDataSource, OneToOneInvitableViewDataSource {
    func getAsyncSequenceOfSingleGroupV2MainViewModel(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV2MainViewModelOrNotFound>)
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(streamUUID: UUID)
    func getTrustedPhotoForGroup(groupIdentifier: ObvGroupV2Identifier, trustedPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
    func getCustomPhotoForGroup(groupIdentifier: ObvGroupV2Identifier, customPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
}



@MainActor
protocol SingleGroupV2MainViewActionsProtocol: AnyObject, PublishedDetailsValidationViewActionsProtocol, ListOfGroupMembersViewActionsProtocol, GroupAdministrationViewActionsProtocol, OneToOneInvitableViewActionsProtocol {
    func userWantsToLeaveGroup(groupIdentifier: ObvGroupV2Identifier) async throws
    func userWantsToDisbandGroup(groupIdentifier: ObvGroupV2Identifier) async throws
    func userWantsToChat(groupIdentifier: ObvGroupV2Identifier) async
    func userWantsToCall(groupIdentifier: ObvGroupV2Identifier) async
    func userWantsToLeaveGroupFlow()
    func userTappedOnTheEditPersonalNoteButton(groupIdentifier: ObvGroupV2Identifier, currentPersonalNote: String?)
    func userTappedOnTheEditCustomNameAndPhotoButton()
    func userTappedOnCloneGroupButton(groupIdentifier: ObvGroupV2Identifier) async throws
    func userTappedOnManualResyncOfGroupV2Button(groupIdentifier: ObvGroupV2Identifier) async throws
}



// MARK: - SingleGroupV2MainView

/// This is the main "single group" view, shown when the user wishes to consult the details of a particular group.
struct SingleGroupV2MainView: View {
    
    let groupIdentifier: ObvGroupV2Identifier
    let dataSource: SingleGroupV2MainViewDataSource
    let actions: SingleGroupV2MainViewActionsProtocol
    
    @State private var groupModel: SingleGroupV2MainViewModel?
    @State private var streamUUID: UUID?
    
    @State private var trustedPhoto: UIImage?
    @State private var customPhoto: UIImage?
    
    @State private var showDisbandConfirmationDialog: Bool = false
    @State private var userIsDisbandingGroup: Bool = false
    @State private var hudCategory: HUDView.Category? = nil
    @State private var userIsLeavingGroup: Bool = false
    
    private func onAppear() {
        Task {
            do {
                let (streamUUID, stream) = try dataSource.getAsyncSequenceOfSingleGroupV2MainViewModel(groupIdentifier: groupIdentifier)
                if let previousStreamUUID = self.streamUUID {
                    dataSource.finishAsyncSequenceOfSingleGroupV2MainViewModel(streamUUID: previousStreamUUID)
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
                        
                        actions.userWantsToLeaveGroupFlow()
                        
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
        dataSource.finishAsyncSequenceOfSingleGroupV2MainViewModel(streamUUID: previousStreamUUID)
        self.streamUUID = nil
    }
    
    
    private func fetchAndSetCustomPhoto(previousCustomPhotoURL: URL?, newCustomPhotoURL: URL?) async throws {
        guard previousCustomPhotoURL != newCustomPhotoURL else { return }
        withAnimation {
            self.customPhoto = nil
        }
        guard let newCustomPhotoURL else { return }
        // Quick and dirty: we enforce a `.xLarge` avatar size as this is coherent with the `.header` display mode chosen in circleAndTitlesViewModelForHeader.
        let customPhoto = try await dataSource.getCustomPhotoForGroup(groupIdentifier: groupIdentifier, customPhotoURL: newCustomPhotoURL, avatarSize: .xLarge)
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
        let trustedPhoto = try await dataSource.getTrustedPhotoForGroup(groupIdentifier: groupIdentifier, trustedPhotoURL: newTrustedPhotoURL, avatarSize: .xLarge)
        if groupModel?.trustedPhotoURL == newTrustedPhotoURL {
            self.trustedPhoto = trustedPhoto
        }
    }
    
    
    private func userTappedOnTheEditPersonalNoteButton() {
        guard let groupModel else { return }
        actions.userTappedOnTheEditPersonalNoteButton(groupIdentifier: groupModel.groupIdentifier, currentPersonalNote: groupModel.personalNote)
    }
    
    
    private func userTappedOnTheEditCustomNameAndPhotoButton() {
        actions.userTappedOnTheEditCustomNameAndPhotoButton()
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
                try await actions.userWantsToDisbandGroup(groupIdentifier: groupIdentifier)
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
                try await actions.userTappedOnCloneGroupButton(groupIdentifier: groupIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
    private func userTappedOnManualResyncOfGroupV2Button() {
        hudCategory = .progress
        Task {
            do {
                try await actions.userTappedOnManualResyncOfGroupV2Button(groupIdentifier: groupIdentifier)
                hudCategory = .checkmark
            } catch {
                assertionFailure()
                hudCategory = .xmark
            }
            try? await Task.sleep(seconds: 1)
            hudCategory = nil
        }
    }
    
    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .ignoresSafeArea(.all)
            InternalView(groupIdentifier: groupIdentifier,
                         dataSource: dataSource,
                         actions: actions,
                         groupModel: groupModel,
                         trustedPhoto: trustedPhoto,
                         customPhoto: customPhoto,
                         userIsDisbandingGroup: userIsDisbandingGroup,
                         hudCategory: $hudCategory,
                         userIsLeavingGroup: $userIsLeavingGroup)
            if groupModel == nil {
                ProgressView()
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
                    Button(action: userTappedOnTheEditPersonalNoteButton) {
                        Label { Text("EDIT_PERSONAL_NOTE") } icon: { Image(systemIcon: .pencil(.none)) }
                    }
                    Button(action: userTappedOnTheEditCustomNameAndPhotoButton) {
                        Label { Text("EDIT_NICKNAME_AND_CUSTOM_PHOTO") } icon: { Image(systemIcon: .camera(.none)) }
                    }
                    Divider()
                    Button(action: userTappedOnCloneGroupButton) {
                        Label { Text("CLONE_THIS_GROUP") } icon: { Image(systemIcon: .docOnDoc) }
                    }
                    Divider()
                    Button(action: userTappedOnManualResyncOfGroupV2Button) {
                        Label { Text("MANUAL_RESYNC_OF_GROUP_V2") } icon: { Image(systemIcon: .arrowTriangle2CirclepathCircle) }
                    }
                    if let groupModel, groupModel.ownedIdentityIsAdmin {
                        Button(role: .destructive, action: userTappedTheDisbandGroupButton) {
                            Label { Text("DISBAND_GROUP") } icon: { Image(systemIcon: .trash) }
                        }
                    }
                    
                } label: {
                    Image(systemIcon: .ellipsisCircle)
                }
                
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
        let dataSource: SingleGroupV2MainViewDataSource
        let actions: SingleGroupV2MainViewActionsProtocol
        
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
            Task {
                await actions.userWantsToChat(groupIdentifier: groupIdentifier)
            }
        }
        
        private func userTappedTheCallButton() -> Void {
            Task {
                await actions.userWantsToCall(groupIdentifier: groupIdentifier)
            }
        }
        
        private func adminsCanBeChanged(groupModel: SingleGroupV2MainViewModel) -> Bool {
            guard let groupType = groupModel.groupType else { assertionFailure(); return false }
            return ObvGroupType.adminCanSelectSpecificAdmins(groupType: groupType)
        }
        
        private func userWantsToLeaveGroup() {
            userIsLeavingGroup = true
            hudCategory = .progress
            Task {
                defer { hudCategory = nil }
                do {
                    try await actions.userWantsToLeaveGroup(groupIdentifier: groupIdentifier)
                    guard !Task.isCancelled else { return }
                    hudCategory = .checkmark
                } catch {
                    hudCategory = .xmark
                    userIsLeavingGroup = false
                    assertionFailure()
                }
            }
        }
        
        var body: some View {
            ScrollView {
                if let model = self.groupModel {
                    
                    VStack {
                        
                        // Header
                        
                        CircleAndTitlesView(model: circleAndTitlesViewModelForHeader(model: model))
                            .padding(.top, 16)
                        
                        // Chat and call buttons
                        
                        ChatAndCallButtons(userTappedTheChatButton: userTappedTheChatButton,
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
                            PublishedDetailsValidationView(model: publishedDetailsForValidation,
                                                           dataSource: dataSource,
                                                           actions: actions)
                            .padding(.top, 16)
                        }
                        
                        // Group Administration
                        
                        if model.ownedIdentityIsAdmin {
                            GroupAdministrationView(actions: actions,
                                                    adminsCanBeChanged: adminsCanBeChanged(groupModel: model))
                            .padding(.top, 16)
                        }
                        
                        // Group members
                        
                        ListOfGroupMembersView(hudCategory: $hudCategory,
                                               groupIdentifier: model.groupIdentifier,
                                               dataSource: dataSource,
                                               actions: actions)
                        .padding(.top, 16)
                        
                        // Group members that can be invited to a one-to-one discussion
                        
                        OneToOneInvitableView(groupIdentifier: groupIdentifier,
                                              dataSource: dataSource,
                                              actions: actions)
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


// MARK: - Subview: Invite group members to one2one

public struct OneToOneInvitableViewModel: Sendable {
    let numberOfGroupMembersThatAreContactsButNotOneToOne: Int
    let numberOfOneToOneInvitationsSent: Int
    let numberOfPendingMembersWithNoAssociatedContact: Int // Those cannot be invited yet
    let groupHasNoOtherMember: Bool
    public init(numberOfGroupMembersThatAreContactsButNotOneToOne: Int, numberOfOneToOneInvitationsSent: Int, numberOfPendingMembersWithNoAssociatedContact: Int, groupHasNoOtherMember: Bool) {
        self.numberOfGroupMembersThatAreContactsButNotOneToOne = numberOfGroupMembersThatAreContactsButNotOneToOne
        self.numberOfOneToOneInvitationsSent = numberOfOneToOneInvitationsSent
        self.numberOfPendingMembersWithNoAssociatedContact = numberOfPendingMembersWithNoAssociatedContact
        self.groupHasNoOtherMember = groupHasNoOtherMember
    }
}


@MainActor
protocol OneToOneInvitableViewDataSource {
    func getAsyncSequenceOfOneToOneInvitableViewModel(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OneToOneInvitableViewModel>)
    func finishAsyncSequenceOfOneToOneInvitableViewModel(streamUUID: UUID)
}


@MainActor
protocol OneToOneInvitableViewActionsProtocol: AnyObject {
    func userWantsToNavigateToViewAllowingToSelectGroupMembersToInviteToOneToOne(groupIdentifier: ObvGroupV2Identifier)
}


/// This view, at the bottom of the main view, shows how many group members are not yet part of the one2one contact of the owned identity, how many can be invited in one click, etc.
private struct OneToOneInvitableView: View {
    
    let groupIdentifier: ObvGroupV2Identifier
    let dataSource: OneToOneInvitableViewDataSource
    let actions: OneToOneInvitableViewActionsProtocol
    
    @State private var model: OneToOneInvitableViewModel?
    @State private var streamUUID: UUID?
    
    private func onAppear() {
        Task {
            do {
                let (streamUUID, stream) = try dataSource.getAsyncSequenceOfOneToOneInvitableViewModel(groupIdentifier: groupIdentifier)
                if let previousStreamUUID = self.streamUUID {
                    dataSource.finishAsyncSequenceOfOneToOneInvitableViewModel(streamUUID: previousStreamUUID)
                }
                self.streamUUID = streamUUID
                for await model in stream {
                    if self.model == nil {
                        self.model = model
                    } else {
                        withAnimation {
                            self.model = model
                        }
                    }
                }
            } catch {
                assertionFailure()
            }
        }
    }
    
    private func onDisappear() {
        if let previousStreamUUID = self.streamUUID {
            dataSource.finishAsyncSequenceOfOneToOneInvitableViewModel(streamUUID: previousStreamUUID)
            self.streamUUID = nil
        }
    }
    
    var body: some View {
        InternalView(groupIdentifier: groupIdentifier,
                     actions: actions,
                     model: model)
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
    }
    
    private struct InternalView: View {
        
        let groupIdentifier: ObvGroupV2Identifier
        let actions: OneToOneInvitableViewActionsProtocol
        let model: OneToOneInvitableViewModel?

        private func userTappedButtonToShowAllInvitableContacts() {
            actions.userWantsToNavigateToViewAllowingToSelectGroupMembersToInviteToOneToOne(groupIdentifier: groupIdentifier)
        }
        
        private func explanationText(model: OneToOneInvitableViewModel) -> String {
            switch (model.numberOfGroupMembersThatAreContactsButNotOneToOne > 0, model.numberOfPendingMembersWithNoAssociatedContact > 0) {
            case (false, false):
                // Note that in that case, we do not show the button.
                return String(localizedInThisBundle: "ALL_THE_GROUP_MEMBERS_ARE_PART_OF_YOUR_CONTACTS")
            case (false, true):
                return String(localizedInThisBundle: "\(model.numberOfPendingMembersWithNoAssociatedContact)_OF_THE_GROUP_MEMBERS_ARE_NOT_PART_OF_YOUR_CONTACTS_BUT_YOU_CANNOT_INVITE_THEM_UNTIL_THEY_ACCEPT_THE_GROUP_INVITATION")
            case (true, false):
                return String(localizedInThisBundle: "\(model.numberOfGroupMembersThatAreContactsButNotOneToOne)_OF_THE_GROUP_MEMBERS_ARE_NOT_PART_OF_YOUR_CONTACTS_BUT_YOU_CAN_INVITE_THEM")
            case (true, true):
                let total = model.numberOfGroupMembersThatAreContactsButNotOneToOne + model.numberOfPendingMembersWithNoAssociatedContact
                let s1 = String(localizedInThisBundle: "\(total)_OF_THE_GROUP_MEMBERS_ARE_NOT_PART_OF_YOUR_CONTACTS")
                let s2 = String(localizedInThisBundle: "YOU_CAN_INVITE_\(model.numberOfGroupMembersThatAreContactsButNotOneToOne)_OF_THEM_NOW")
                let s3 = String(localizedInThisBundle: "THE_REMAINING_\(model.numberOfPendingMembersWithNoAssociatedContact)_MUST_ACCEPT_THE_GROUP_INVITATION_BEFORE_YOU_CAN_ADD_THEM")
                let s = [s1, s2, s3].joined(separator: " ")
                return s
            }
        }
        
        private func subExplanationText(model: OneToOneInvitableViewModel) -> String? {
            guard model.numberOfOneToOneInvitationsSent > 0 else { return nil }
            if model.numberOfOneToOneInvitationsSent < model.numberOfGroupMembersThatAreContactsButNotOneToOne {
                return String(localizedInThisBundle: "YOU_ALREADY_INVITED_\(model.numberOfOneToOneInvitationsSent)_OF_THESE_MEMBERS")
            } else {
                if model.numberOfOneToOneInvitationsSent == 1 {
                    return String(localizedInThisBundle: "YOU_ALREADY_INVITED_THIS_MEMBER")
                } else {
                    return String(localizedInThisBundle: "YOU_ALREADY_INVITED_ALL_THESE_MEMBERS")
                }
            }
        }
        
        private func showButton(model: OneToOneInvitableViewModel) -> Bool {
            // We always show the button, except when all the group members are already part of the one2one contacts.
            return model.numberOfGroupMembersThatAreContactsButNotOneToOne > 0 || model.numberOfPendingMembersWithNoAssociatedContact > 0
        }
        
        var body: some View {
            if let model {
                
                if model.groupHasNoOtherMember {
                    
                    EmptyView()
                    
                } else {
                    
                    VStack {
                        
                        HStack {
                            Text("ADD_GROUP_MEMBERS_TO_YOUR_CONTACTS")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.bold)
                            Spacer()
                        }
                        
                        ObvCardView(padding: 0) {
                            
                            HStack {
                                VStack {
                                    VStack(alignment: .leading) {
                                        HStack {
                                            Text(explanationText(model: model))
                                            Spacer(minLength: 0)
                                        }
                                        if let subExplanationText = subExplanationText(model: model) {
                                            HStack {
                                                Text(subExplanationText)
                                                Spacer(minLength: 0)
                                            }
                                            .padding(.top, 4)
                                        }
                                    }
                                    .foregroundStyle(.secondary)
                                    .padding(.top)
                                    .padding(.horizontal)
                                    .padding(.bottom, showButton(model: model) ? 0 : 16)
                                    if showButton(model: model) {
                                        Divider()
                                            .padding(.vertical, 4)
                                            .padding(.leading)
                                        Button(action: userTappedButtonToShowAllInvitableContacts) {
                                            HStack {
                                                Text("SHOW_ME")
                                                    .tint(.primary)
                                                Spacer()
                                                ObvChevronRight()
                                            }
                                            .padding(.bottom)
                                            .padding(.horizontal)
                                        }
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            
                        }
                    }
                    
                }
                
            } else {
                
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }.padding()
                
            }
        }
        
    }
    
    
}


// MARK: - Subview: Leave group button and confirmations

private struct LeaveGroupButtonAndConfirmationsView: View {
    
    let ownedIdentityCanLeaveGroup: SingleGroupV2MainViewModel.CanLeaveGroup
    let userWantsToLeaveGroup: () -> Void

    @State private var showLeaveGroupDialog: Bool = false
    @State private var showCannotLeaveGroupAsWeAreTheOnlyAdminAlert: Bool = false
    @State private var showCannotLeaveGroupAsThisIsKeycloakGroupAlert: Bool = false

    var body: some View {
        OlvidButton(style: .red, title: Text("LEAVE_GROUP"), systemIcon: .xmarkOctagon) {
            switch ownedIdentityCanLeaveGroup {
            case .canLeaveGroup:
                showLeaveGroupDialog = true
            case .cannotLeaveGroupAsWeAreTheOnlyAdmin:
                showCannotLeaveGroupAsWeAreTheOnlyAdminAlert = true
            case .cannotLeaveGroupAsThisIsKeycloakGroup:
                showCannotLeaveGroupAsThisIsKeycloakGroupAlert = true
            }
        }
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
protocol GroupAdministrationViewActionsProtocol {
    func userWantsToNavigateToViewAllowingToModifyMembers() async
    func userWantsToNavigateToViewAllowingToSelectGroupTypes() async
    func userWantsToNavigateToViewAllowingToManageAdmins() async
    func userWantsToNavigateToViewAllowingToEditGroupName() async
}

private struct GroupAdministrationView: View {
    
    let actions: GroupAdministrationViewActionsProtocol
    let adminsCanBeChanged: Bool
    
    private func modifyMemberButtonTapped() {
        Task { await actions.userWantsToNavigateToViewAllowingToModifyMembers() }
    }
    
    private func modifyGroupNameButtonTapped() {
        Task { await actions.userWantsToNavigateToViewAllowingToEditGroupName() }
    }
    
    private func groupTypesButtonTapped() {
        Task { await actions.userWantsToNavigateToViewAllowingToSelectGroupTypes() }
    }
    
    private func manageAdminsButtonTapped() {
        Task { await actions.userWantsToNavigateToViewAllowingToManageAdmins() }
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
        
    }
}


// MARK: - Subview: ListOfGroupMembersView


protocol ListOfGroupMembersViewActionsProtocol: SingleGroupMemberViewActionsProtocol {
    func userWantsToNavigateToFullListOfOtherGroupMembers(groupIdentifier: ObvGroupV2Identifier) async
    func userWantsToNavigateToViewAllowingToAddGroupMembers(groupIdentifier: ObvGroupV2Identifier)
}


protocol ListOfGroupMembersViewDataSource: ListOfOtherGroupMembersViewDataSource, OwnedIdentityAsGroupMemberViewDataSource {
}

protocol ListOfOtherGroupMembersViewDataSource: SingleGroupMemberViewDataSource {
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>)
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: UUID, searchText: String?)
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: UUID)
}


private struct ListOfGroupMembersView: View {

    @Binding var hudCategory: HUDView.Category? // Must be a binding
    let groupIdentifier: ObvGroupV2Identifier
    let dataSource: ListOfGroupMembersViewDataSource
    let actions: ListOfGroupMembersViewActionsProtocol

    @State private var model: ListOfSingleGroupMemberViewModel?
    @State private var streamUUID: UUID?
    
    private func onAppear() {
        Task {
            let (streamUUID, stream) = try dataSource.getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(groupIdentifier: groupIdentifier)
            if let previousStreamUUID = self.streamUUID {
                dataSource.finishAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: previousStreamUUID)
            }
            self.streamUUID = streamUUID
            for await model in stream {
                if self.model == nil {
                    self.model = model
                } else {
                    withAnimation {
                        self.model = model
                    }
                }
            }
        }
    }
    
    
    private func onDisappear() {
        if let previousStreamUUID = self.streamUUID {
            dataSource.finishAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: previousStreamUUID)
            self.streamUUID = nil
        }
    }
    
    
    var body: some View {
        InternalView(groupIdentifier: groupIdentifier,
                     model: model,
                     hudCategory: $hudCategory,
                     dataSource: dataSource,
                     actions: actions)
            .onDisappear(perform: onDisappear)
            .onAppear(perform: onAppear)
    }
    
    
    private struct InternalView: View {
        
        let groupIdentifier: ObvGroupV2Identifier
        let model: ListOfSingleGroupMemberViewModel?
        @Binding var hudCategory: HUDView.Category? // Must be a binding
        let dataSource: ListOfGroupMembersViewDataSource
        let actions: ListOfGroupMembersViewActionsProtocol

        private let maximumNumberOfGroupMembersShown = 5

        private func userWantsToNavigateToFullListOfOtherGroupMembers(model: ListOfSingleGroupMemberViewModel) {
            Task {
                await actions.userWantsToNavigateToFullListOfOtherGroupMembers(groupIdentifier: groupIdentifier)
            }
        }
        
        private func userTappedButtonToAddMembersToGroup() {
            actions.userWantsToNavigateToViewAllowingToAddGroupMembers(groupIdentifier: groupIdentifier)
        }

        private let leadingPaddingForDivider: CGFloat = 70.0

        var body: some View {
            if let model {
                if model.otherGroupMembers.isEmpty {
                    
                    VStack {
                        
                        HStack {
                            Text("GROUP_MEMBERS_TITLE_WHEN_NO_OTHER_MEMBER")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.bold)
                            Spacer()
                        }

                        ObvCardView(padding: 0) {
                            VStack {
                                OwnedIdentityAsGroupMemberView(groupIdentifier: groupIdentifier, dataSource: dataSource)
                                    .padding(.horizontal)
                                    .padding(.vertical, 4)
                                Divider()
                                    .padding(.leading, leadingPaddingForDivider)
                                Button(action: userTappedButtonToAddMembersToGroup) {
                                    HStack {
                                        Spacer(minLength: 0)
                                        Text("ADD_MEMBERS_TO_THIS_GROUP_BUTTON_TITLE")
                                        Spacer(minLength: 0)
                                    }.padding(.vertical, 4)
                                }
                                .buttonStyle(.borderedProminent)
                                .padding()
                            }
                            .padding(.vertical, 8)
                        }
                        
                    }
                    
                } else {
                    VStack {
                        
                        HStack {
                            Text("GROUP_MEMBERS_TITLE_\(model.otherGroupMembers.count + 1)")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.bold)
                            Spacer()
                        }
                        
                        ObvCardView(padding: 0) {
                            LazyVStack {
                                VStack {
                                    OwnedIdentityAsGroupMemberView(groupIdentifier: groupIdentifier, dataSource: dataSource)
                                        .padding(.horizontal)
                                        .padding(.vertical, 4)
                                    Divider()
                                        .padding(.leading, leadingPaddingForDivider)
                                }
                                ForEach(model.otherGroupMembers.prefix(maximumNumberOfGroupMembersShown)) { otherGroupMember in
                                    VStack {
                                        SingleGroupMemberView(mode: .listMembers(groupIdentifier: groupIdentifier),
                                                              modelIdentifier: otherGroupMember,
                                                              dataSource: dataSource,
                                                              actions: actions,
                                                              selectedMembers: .constant([]),
                                                              hudCategory: $hudCategory,
                                                              membersWithUpdatedAdminPermission: .constant([]))
                                        .padding(.horizontal)
                                        .padding(.vertical, 4)
                                        if otherGroupMember != model.otherGroupMembers.last {
                                            Divider()
                                                .padding(.leading, leadingPaddingForDivider)
                                        }
                                    }
                                }
                                if model.otherGroupMembers.count > maximumNumberOfGroupMembersShown {
                                    Button(action: { userWantsToNavigateToFullListOfOtherGroupMembers(model: model) }) {
                                        HStack {
                                            Spacer()
                                            Text("SHOW_ALL_GROUP_MEMBERS")
                                            Spacer()
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    
                                }
                            }.padding(.vertical, 8)
                        }
                        
                    }
                }
            } else {
                ProgressView()
            }
        }
        
    }
    
}


// MARK: - Subview: ChatAndCallButtons

private struct ChatAndCallButtons: View {
    
    let userTappedTheChatButton: () -> Void
    let userTappedTheCallButton: () -> Void
    
    var body: some View {
        HStack {
            OlvidButton(style: .standardWithBlueText,
                        title: Text("BUTTON_CHAT"),
                        systemIcon: .textBubbleFill,
                        action: userTappedTheChatButton)
            OlvidButton(style: .standardWithBlueText,
                        title: Text("BUTTON_CALL"),
                        systemIcon: .phoneFill,
                        action: userTappedTheCallButton)
        }
    }
}


















// MARK: - Previews

#if DEBUG

@MainActor
private class ActionsForPreviews: SingleGroupV2MainViewActionsProtocol {
    
    // SingleGroupV2MainViewActionsProtocol
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails(publishedDetails: PublishedDetailsValidationViewModel) async throws {
        // Nothing to simulate
    }
    
    func userWantsToLeaveGroupFlow() {
        // Nothing to simulate
    }
    
    // ListOfGroupMembersViewActionsProtocol
    
    func userWantsToInviteOtherUserToOneToOne(contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        // Nothing to simulate
    }
    
    
    func userWantsToNavigateToFullListOfOtherGroupMembers(groupIdentifier: ObvTypes.ObvGroupV2Identifier) async {
        // Nothing to simulate
    }
    
    // GroupAdministrationViewActionsProtocol

    func userWantsToNavigateToViewAllowingToModifyMembers() async {
        // Nothing to simulate
    }
    
    func userWantsToNavigateToViewAllowingToSelectGroupTypes() async {
        // Nothing to simulate
    }
    
    func userWantsToNavigateToViewAllowingToManageAdmins() async {
        // Nothing to simulate
    }
    
    func userWantsToNavigateToViewAllowingToEditGroupName() async {
        // Nothing to simulate
    }

    func userWantsToShowOtherUserProfile(contactIdentifier: ObvTypes.ObvContactIdentifier) async {
        // Nothing to simulate
    }
    
    func userWantsToRemoveOtherUserFromGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        // Nothing to simulate
    }

    func userWantsToLeaveGroup(groupIdentifier: ObvGroupV2Identifier) async throws {
        try await Task.sleep(seconds: 2)
    }
    
    func userWantsToDisbandGroup(groupIdentifier: ObvGroupV2Identifier) async throws {
        try await Task.sleep(seconds: 2)
    }
    
    func userWantsToChat(groupIdentifier: ObvGroupV2Identifier) async {
        // Nothing to simulate
    }
    
    func userWantsToCall(groupIdentifier: ObvGroupV2Identifier) async {
        // Nothing to simulate
    }
    
    func userTappedOnTheEditPersonalNoteButton(groupIdentifier: ObvGroupV2Identifier, currentPersonalNote: String?) {
        // Nothing to simulate
    }
    
    func userTappedOnTheEditCustomNameAndPhotoButton() {
        // Nothing to simulate
    }
    
    func userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(creationSessionUUID: UUID, memberIdentifier: SingleGroupMemberViewModelIdentifier, newIsAnAdmin: Bool) {
        // Nothing to simulate
    }

    func userWantsToNavigateToViewAllowingToSelectGroupMembersToInviteToOneToOne(groupIdentifier: ObvGroupV2Identifier) {
        // Nothing to simulate
    }
    
    func userTappedOnCloneGroupButton(groupIdentifier: ObvGroupV2Identifier) {
        // Nothing to simulate
    }
    
    func userTappedOnManualResyncOfGroupV2Button(groupIdentifier: ObvGroupV2Identifier) async throws {
        // Nothing to simulate
    }
    
    func userWantsToNavigateToViewAllowingToAddGroupMembers(groupIdentifier: ObvGroupV2Identifier) {
        // Nothing to simulate
    }
    
}

private final class DataSourceForPreviews: SingleGroupV2MainViewDataSource {

    func getAsyncSequenceOfSingleGroupV2MainViewModel(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV2MainViewModelOrNotFound>) {
        let stream = AsyncStream(SingleGroupV2MainViewModelOrNotFound.self) { (continuation: AsyncStream<SingleGroupV2MainViewModelOrNotFound>.Continuation) in
            let model = PreviewsHelper.singleGroupV2MainViewModels[0]
            continuation.yield(.model(model: model))
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(streamUUID: UUID) {
        // Nothing to terminate in these previews
    }
    

    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: UUID, searchText: String?) {
        // We don't simulate search
    }

    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>) {
        let otherGroupMembers: [SingleGroupMemberViewModelIdentifier] = PreviewsHelper.groupMembers.map({ .contactIdentifierForExistingGroup(groupIdentifier: groupIdentifier, contactIdentifier: $0.contactIdentifier) })
        let stream = AsyncStream(ListOfSingleGroupMemberViewModel.self) { (continuation: AsyncStream<ListOfSingleGroupMemberViewModel>.Continuation) in
            let model = ListOfSingleGroupMemberViewModel(otherGroupMembers: otherGroupMembers)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: UUID) {
        // Nothing to finish in these previews
    }
    
    func getAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupMemberViewModel>) {
        switch identifier {
        case .contactIdentifierForExistingGroup(_, let contactIdentifier), .contactIdentifierForCreatingGroup(contactIdentifier: let contactIdentifier):
            let stream = AsyncStream(SingleGroupMemberViewModel.self) { (continuation: AsyncStream<SingleGroupMemberViewModel>.Continuation) in
                if let groupMember = PreviewsHelper.groupMembers.first(where: { $0.contactIdentifier == contactIdentifier }) {
                    continuation.yield(groupMember)
                }
            }
            return (UUID(), stream)
        case .objectIDOfPersistedGroupV2Member, .objectIDOfPersistedContact:
            throw ObvError.error
        }
    }
    
    
    func finishAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier, streamUUID: UUID) {
        // Nothing to finish in these previews
    }

    
    func getTrustedPhotoForGroup(groupIdentifier: ObvGroupV2Identifier, trustedPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        return PreviewsHelper.groupPictureForURL[trustedPhotoURL]
    }
    
    func getPublishedPhotoForGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, publishedPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.groupPictureForURL[publishedPhotoURL]
    }

    func getCustomPhotoForGroup(groupIdentifier: ObvGroupV2Identifier, customPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }

    func fetchAvatarImageForGroupMember(contactIdentifier: ObvContactIdentifier, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        return PreviewsHelper.profilePictureForURL[photoURL]
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

    
    enum ObvError: Error {
        case error
    }
    
    func getAsyncSequenceOfOneToOneInvitableViewModel(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OneToOneInvitableViewModel>) {
        let stream = AsyncStream(OneToOneInvitableViewModel.self) { (continuation: AsyncStream<OneToOneInvitableViewModel>.Continuation) in
            Task {
                do {
                    let model = OneToOneInvitableViewModel(numberOfGroupMembersThatAreContactsButNotOneToOne: 0, numberOfOneToOneInvitationsSent: 0, numberOfPendingMembersWithNoAssociatedContact: 1, groupHasNoOtherMember: false)
                    continuation.yield(model)
                }
                try! await Task.sleep(seconds: 2)
                do {
                    let model = OneToOneInvitableViewModel(numberOfGroupMembersThatAreContactsButNotOneToOne: 3, numberOfOneToOneInvitationsSent: 3, numberOfPendingMembersWithNoAssociatedContact: 0, groupHasNoOtherMember: false)
                    continuation.yield(model)
                }
            }
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncSequenceOfOneToOneInvitableViewModel(streamUUID: UUID) {
        // Nothing to finish in these previews
    }
    
    // OwnedIdentityAsGroupMemberViewDataSource
    
    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityAsGroupMemberViewModel>) {
        let stream = AsyncStream(OwnedIdentityAsGroupMemberViewModel.self) { (continuation: AsyncStream<OwnedIdentityAsGroupMemberViewModel>.Continuation) in
            let model = OwnedIdentityAsGroupMemberViewModel.sampleData
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(groupIdentifier: ObvGroupV2Identifier, streamUUID: UUID) {
        // Nothing to finish in these previews
    }
    
    func fetchAvatarImageForOwnedIdentityAsGroupMember(ownedCryptoId: ObvTypes.ObvCryptoId, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.profilePictureForURL[photoURL]
    }

}


@MainActor
private let actionsForPreviews = ActionsForPreviews()

@MainActor
private let dataSource = DataSourceForPreviews()

#Preview {
    SingleGroupV2MainView(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0],
                         dataSource: dataSource,
                         actions: actionsForPreviews)
}


private final class DataSourceWithMemberUpdatesForPreviews: SingleGroupV2MainViewDataSource {
        
    func getAsyncSequenceOfSingleGroupV2MainViewModel(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV2MainViewModelOrNotFound>) {
        let stream = AsyncStream(SingleGroupV2MainViewModelOrNotFound.self) { (continuation: AsyncStream<SingleGroupV2MainViewModelOrNotFound>.Continuation) in
            let model = PreviewsHelper.singleGroupV2MainViewModels[0]
            continuation.yield(.model(model: model))
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(streamUUID: UUID) {
        // Nothing to terminate in these previews
    }

    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: UUID, searchText: String?) {
        // We don't simulate search
    }

    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>) {
        let stream = AsyncStream(ListOfSingleGroupMemberViewModel.self) { (continuation: AsyncStream<ListOfSingleGroupMemberViewModel>.Continuation) in
            Task {
                let oneGroupMember: [SingleGroupMemberViewModelIdentifier] = [.contactIdentifierForExistingGroup(groupIdentifier: groupIdentifier, contactIdentifier: PreviewsHelper.groupMembers.first!.contactIdentifier)]
                let modelWithOneGroupMember = ListOfSingleGroupMemberViewModel(otherGroupMembers: oneGroupMember)
                continuation.yield(modelWithOneGroupMember)
                try! await Task.sleep(seconds: 5)
                let twoGroupMembers = oneGroupMember + [.contactIdentifierForExistingGroup(groupIdentifier: groupIdentifier, contactIdentifier: PreviewsHelper.groupMembers[1].contactIdentifier)]
                let modelWithTwoGroupMembers = ListOfSingleGroupMemberViewModel(otherGroupMembers: twoGroupMembers)
                continuation.yield(modelWithTwoGroupMembers)
                try! await Task.sleep(seconds: 5)
                let threeGroupMembers = twoGroupMembers + [.contactIdentifierForExistingGroup(groupIdentifier: groupIdentifier, contactIdentifier: PreviewsHelper.groupMembers[2].contactIdentifier)]
                let modelWithThreeGroupMembers = ListOfSingleGroupMemberViewModel(otherGroupMembers: threeGroupMembers)
                continuation.yield(modelWithThreeGroupMembers)
            }
        }
        return (UUID(), stream)
    }

    
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: UUID) {
        // Nothing to finish in these previews
    }
    
    
    func getAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupMemberViewModel>) {
        switch identifier {
        case .contactIdentifierForExistingGroup(_, let contactIdentifier), .contactIdentifierForCreatingGroup(contactIdentifier: let contactIdentifier):
            let stream = AsyncStream(SingleGroupMemberViewModel.self) { (continuation: AsyncStream<SingleGroupMemberViewModel>.Continuation) in
                if let groupMember = PreviewsHelper.groupMembers.first(where: { $0.contactIdentifier == contactIdentifier }) {
                    continuation.yield(groupMember)
                }
            }
            return (UUID(), stream)
        case .objectIDOfPersistedGroupV2Member, .objectIDOfPersistedContact:
            throw ObvError.error
        }
    }

    func finishAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier, streamUUID: UUID) {
        // Nothing to finish in these previews
    }

    func getTrustedPhotoForGroup(groupIdentifier: ObvGroupV2Identifier, trustedPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        return PreviewsHelper.groupPictureForURL[trustedPhotoURL]
    }
    
    
    func getPublishedPhotoForGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, publishedPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.groupPictureForURL[publishedPhotoURL]
    }

    func getCustomPhotoForGroup(groupIdentifier: ObvGroupV2Identifier, customPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }

    func fetchAvatarImageForGroupMember(contactIdentifier: ObvContactIdentifier, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        return PreviewsHelper.profilePictureForURL[photoURL]
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

    
    enum ObvError: Error {
        case error
    }
    
    
    func getAsyncSequenceOfOneToOneInvitableViewModel(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OneToOneInvitableViewModel>) {
        let stream = AsyncStream(OneToOneInvitableViewModel.self) { (continuation: AsyncStream<OneToOneInvitableViewModel>.Continuation) in
            let model = OneToOneInvitableViewModel(numberOfGroupMembersThatAreContactsButNotOneToOne: 2, numberOfOneToOneInvitationsSent: 2, numberOfPendingMembersWithNoAssociatedContact: 0, groupHasNoOtherMember: false)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncSequenceOfOneToOneInvitableViewModel(streamUUID: UUID) {
        // Nothing to finish in these previews
    }

    // OwnedIdentityAsGroupMemberViewDataSource
    
    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityAsGroupMemberViewModel>) {
        let stream = AsyncStream(OwnedIdentityAsGroupMemberViewModel.self) { (continuation: AsyncStream<OwnedIdentityAsGroupMemberViewModel>.Continuation) in
            let model = OwnedIdentityAsGroupMemberViewModel.sampleData
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(groupIdentifier: ObvGroupV2Identifier, streamUUID: UUID) {
        // Nothing to finish in these previews
    }
    
    func fetchAvatarImageForOwnedIdentityAsGroupMember(ownedCryptoId: ObvTypes.ObvCryptoId, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.profilePictureForURL[photoURL]
    }

}


@MainActor
private let dataSourceWithUpdates = DataSourceWithMemberUpdatesForPreviews()


#Preview("Update members") {
    SingleGroupV2MainView(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0],
                         dataSource: dataSourceWithUpdates,
                         actions: actionsForPreviews)
}



private final class DataSourceAllowingToAcceptPublishedDetails: SingleGroupV2MainViewDataSource {
    
    var model = PreviewsHelper.singleGroupV2MainViewModels[0]
    var continuations = [UUID: AsyncStream<SingleGroupV2MainViewModelOrNotFound>.Continuation]()
    
    func updateModel(model: SingleGroupV2MainViewModel) {
        self.model = model
        continuations.values.forEach { continuation in
            continuation.yield(.model(model: model))
        }
    }
     
    
    func getAsyncSequenceOfSingleGroupV2MainViewModel(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV2MainViewModelOrNotFound>) {
        let streamUUID = UUID()
        let stream = AsyncStream(SingleGroupV2MainViewModelOrNotFound.self) { (continuation: AsyncStream<SingleGroupV2MainViewModelOrNotFound>.Continuation) in
            continuations[streamUUID] = continuation
            continuation.yield(.model(model: model))
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(streamUUID: UUID) {
        if let continuation = continuations.removeValue(forKey: streamUUID) {
            continuation.finish()
        }
    }

    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>) {
        let stream = AsyncStream(ListOfSingleGroupMemberViewModel.self) { (continuation: AsyncStream<ListOfSingleGroupMemberViewModel>.Continuation) in
            Task {
                let oneGroupMember: [SingleGroupMemberViewModelIdentifier] = [.contactIdentifierForExistingGroup(groupIdentifier: groupIdentifier, contactIdentifier: PreviewsHelper.groupMembers.first!.contactIdentifier)]
                let modelWithOneGroupMember = ListOfSingleGroupMemberViewModel(otherGroupMembers: oneGroupMember)
                continuation.yield(modelWithOneGroupMember)
                try! await Task.sleep(seconds: 5)
                let twoGroupMembers = oneGroupMember + [.contactIdentifierForExistingGroup(groupIdentifier: groupIdentifier, contactIdentifier: PreviewsHelper.groupMembers[1].contactIdentifier)]
                let modelWithTwoGroupMembers = ListOfSingleGroupMemberViewModel(otherGroupMembers: twoGroupMembers)
                continuation.yield(modelWithTwoGroupMembers)
                try! await Task.sleep(seconds: 5)
                let threeGroupMembers = twoGroupMembers + [.contactIdentifierForExistingGroup(groupIdentifier: groupIdentifier, contactIdentifier: PreviewsHelper.groupMembers[2].contactIdentifier)]
                let modelWithThreeGroupMembers = ListOfSingleGroupMemberViewModel(otherGroupMembers: threeGroupMembers)
                continuation.yield(modelWithThreeGroupMembers)
            }
        }
        return (UUID(), stream)
    }

    func finishAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier, streamUUID: UUID) {
        // Nothing to finish in these previews
    }

    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: UUID) {
        // Nothing to finish in these previews
    }

    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: UUID, searchText: String?) {
        // We don't simulate search
    }
    
    func getAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupMemberViewModel>) {
        switch identifier {
        case .contactIdentifierForExistingGroup(_, let contactIdentifier), .contactIdentifierForCreatingGroup(contactIdentifier: let contactIdentifier):
            let stream = AsyncStream(SingleGroupMemberViewModel.self) { (continuation: AsyncStream<SingleGroupMemberViewModel>.Continuation) in
                if let groupMember = PreviewsHelper.groupMembers.first(where: { $0.contactIdentifier == contactIdentifier }) {
                    continuation.yield(groupMember)
                }
            }
            return (UUID(), stream)
        case .objectIDOfPersistedGroupV2Member, .objectIDOfPersistedContact:
            throw ObvError.error
        }
    }

    
    func getTrustedPhotoForGroup(groupIdentifier: ObvGroupV2Identifier, trustedPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        return PreviewsHelper.groupPictureForURL[trustedPhotoURL]
    }
    
    
    func getPublishedPhotoForGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, publishedPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.groupPictureForURL[publishedPhotoURL]
    }

    func getCustomPhotoForGroup(groupIdentifier: ObvGroupV2Identifier, customPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }

    func fetchAvatarImageForGroupMember(contactIdentifier: ObvContactIdentifier, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        return PreviewsHelper.profilePictureForURL[photoURL]
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

    
    enum ObvError: Error {
        case error
    }
    
    
    func getAsyncSequenceOfOneToOneInvitableViewModel(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OneToOneInvitableViewModel>) {
        let stream = AsyncStream(OneToOneInvitableViewModel.self) { (continuation: AsyncStream<OneToOneInvitableViewModel>.Continuation) in
            let model = OneToOneInvitableViewModel(numberOfGroupMembersThatAreContactsButNotOneToOne: 2, numberOfOneToOneInvitationsSent: 2, numberOfPendingMembersWithNoAssociatedContact: 0, groupHasNoOtherMember: false)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncSequenceOfOneToOneInvitableViewModel(streamUUID: UUID) {
        // Nothing to finish in these previews
    }

    // OwnedIdentityAsGroupMemberViewDataSource
    
    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityAsGroupMemberViewModel>) {
        let stream = AsyncStream(OwnedIdentityAsGroupMemberViewModel.self) { (continuation: AsyncStream<OwnedIdentityAsGroupMemberViewModel>.Continuation) in
            let model = OwnedIdentityAsGroupMemberViewModel.sampleData
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(groupIdentifier: ObvGroupV2Identifier, streamUUID: UUID) {
        // Nothing to finish in these previews
    }
    
    func fetchAvatarImageForOwnedIdentityAsGroupMember(ownedCryptoId: ObvTypes.ObvCryptoId, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.profilePictureForURL[photoURL]
    }

}


@MainActor
private class ActionsAllowingToAcceptPublishedDetailsForPreviews: ActionsForPreviews {
    
    let dataSource = DataSourceAllowingToAcceptPublishedDetails()
    
    override func userWantsToReplaceTrustedDetailsByPublishedDetails(publishedDetails: PublishedDetailsValidationViewModel) async throws {
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


@MainActor
private let actionsAllowingToAcceptPublishedDetailsForPreviews = ActionsAllowingToAcceptPublishedDetailsForPreviews()


#Preview("Accept Published") {
    SingleGroupV2MainView(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0],
                         dataSource: actionsAllowingToAcceptPublishedDetailsForPreviews.dataSource,
                         actions: actionsAllowingToAcceptPublishedDetailsForPreviews)
}

#endif
