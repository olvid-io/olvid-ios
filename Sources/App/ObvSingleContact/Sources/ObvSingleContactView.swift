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
import ObvCircleAndTitlesView
import ObvSystemIcon
import ObvDesignSystem
import ObvTypes


@MainActor
public protocol ObvSingleContactViewActions: PersonalNoteEditorViewActions {
    func userWantsToReblockContact(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier) async throws
    func userWantsToRestartChannelCreationWithContact(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier) async throws
    func userWantsToReplaceTrustedContactDetailsByPublishedContactDetails(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier, publishedDetails: ObvTypes.ObvIdentityDetails) async throws
    func userWantsToUnblockContact(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier) async throws
    func userWantsToCancelTheOneToOneInvitationSentToContact(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier) async throws
    func userWantsToSendOneToOneInvitationToContact(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier) throws
    func userWantsToRemoveContactFromTheirContacts(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier, contactDeletionType: ObvSingleContactView.Model.ContactDeletionType) async throws
    func userWantsToSyncOneToOneStatusOfContact(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws
    func userDidSeeNewDetailsOfContact(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier)
}


@MainActor
public protocol ObvSingleContactViewDataSource {
    func getAsyncSequenceOfSingleContactViewModel(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleContactView.ModelOrDeleted>)
    func finishAsyncSequenceOfSingleContactViewModel(_ view: ObvSingleContactView, streamUUID: UUID)
}

@MainActor
public protocol ObvSingleContactViewNavigation {
    func userWantsToNavigateToListOfContactDevices(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier) throws
    func userWantsToNavigateToListOfTrustOrigins(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier) throws
    func userWantsToNavigateToOneToOneDiscussionWithContact(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier) throws
    func userWantsToIntroduceOneContactToAnother(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier) throws
    func userWantsToCallContact(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier)
    func userWantsToNavigateToListOfCommonGroupsWithContact(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier) throws
    func userWantsToCreateNewGroupWithContact(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier) async throws
    func userWantsToEditContactNicknameAndCustomPicture(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier)
}

public struct ObvSingleContactView: View {
    
    let contactIdentifier: ObvContactIdentifier
    let dataSources: DataSources
    let actions: any ObvSingleContactViewActions
    let navigation: any ObvSingleContactViewNavigation
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
    
    public init(contactIdentifier: ObvContactIdentifier,
                dataSources: DataSources,
                actions: ObvSingleContactViewActions,
                navigation: any ObvSingleContactViewNavigation,
                uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet) {
        self.contactIdentifier = contactIdentifier
        self.dataSources = dataSources
        self.actions = actions
        self.navigation = navigation
        self.uiKitDelegateForSwiftUISheet = uiKitDelegateForSwiftUISheet
    }
    
    public struct DataSources {
        let dataSource: any ObvSingleContactViewDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        let contactDetailedInfosViewDataSource: any ObvContactDetailedInfosViewDataSource
        
        public init(dataSource: any ObvSingleContactViewDataSource, avatarViewDataSource: any ObvAvatarViewDataSource, contactDetailedInfosViewDataSource: any ObvContactDetailedInfosViewDataSource) {
            self.dataSource = dataSource
            self.avatarViewDataSource = avatarViewDataSource
            self.contactDetailedInfosViewDataSource = contactDetailedInfosViewDataSource
        }
    }

    @State private var streamedModel: ModelOrDeleted?
    @State private var streamUUIDForViewModel: UUID?
    
    @State private var isRestartChannelCreationFailedAlertShown: Bool = false
    @State private var isRestartChannelCreationAlertShown: Bool = false
    
    @State private var isPersonalNoteEditorViewPresented: Bool = false
    @State private var isContactDetailedInfosViewPresented: Bool = false
    
    private func onTask() async {
        do {
            let (newStreamUUID, stream) = try await dataSources.dataSource.getAsyncSequenceOfSingleContactViewModel(self, contactIdentifier: contactIdentifier)
            if let previousStreamUUID = self.streamUUIDForViewModel {
                dataSources.dataSource.finishAsyncSequenceOfSingleContactViewModel(self, streamUUID: previousStreamUUID)
            }
            self.streamUUIDForViewModel = newStreamUUID
            for await receivedModel in stream {
                withAnimation { self.streamedModel = receivedModel }
            }
        } catch {
            assertionFailure()
        }
        if let previousStreamUUID = self.streamUUIDForViewModel {
            dataSources.dataSource.finishAsyncSequenceOfSingleContactViewModel(self, streamUUID: previousStreamUUID)
        }
        self.streamUUIDForViewModel = nil
    }
    
    private func userTappedOnTheEditCustomNameAndPhotoButton() {
        navigation.userWantsToEditContactNicknameAndCustomPicture(self, contactIdentifier: contactIdentifier)
    }
    
    
    private func callUserDidSeeNewDetailsOfContactIfRequired(_ newStreamedModel: ModelOrDeleted?) {
        switch newStreamedModel {
        case .deleted, nil:
            return
        case .model(let model):
            guard model.publishedIdentityDetails != nil else { return }
            actions.userDidSeeNewDetailsOfContact(self, contactIdentifier: contactIdentifier)
        }
    }
    
    private var navigationTitle: String {
        switch streamedModel {
        case nil:
            return ""
        case .deleted:
            return String(localizedInThisBundle: "DELETED_CONTACT_TITLE")
        case .model(let model):
            return model.nicknameOrShortName
        }
    }
    
    public var body: some View {
        ZStack {
            switch streamedModel {
            case .deleted:
                DeletedContactView()
            case .model(let model):
                ObvSingleContactInternalView(contactIdentifier: contactIdentifier,
                                             viewModel: model,
                                             avatarViewDataSource: dataSources.avatarViewDataSource,
                                             internalActions: self,
                                             isRestartChannelCreationFailedAlertShown: $isRestartChannelCreationFailedAlertShown,
                                             isRestartChannelCreationAlertShown: $isRestartChannelCreationAlertShown)
            case nil:
                ObvCenteredProgressView()
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(onTask)
        .toolbar {
            InternalMenu(isPersonalNoteEditorViewPresented: $isPersonalNoteEditorViewPresented,
                         isContactDetailedInfosViewPresented: $isContactDetailedInfosViewPresented,
                         userTappedOnTheEditCustomNameAndPhotoButton: userTappedOnTheEditCustomNameAndPhotoButton)
        }
        .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isPersonalNoteEditorViewPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
            switch streamedModel {
            case .deleted, nil:
                EmptyView()
            case .model(let model):
                PersonalNoteEditorView(model: .init(initialText: model.personalNote, about: .contact(contactIdentifier)), actions: actions, navigation: self)
            }
        }
        .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isContactDetailedInfosViewPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
            ObvContactDetailedInfosView(contactIdentifier: contactIdentifier,
                                        dataSource: dataSources.contactDetailedInfosViewDataSource,
                                        avatarViewDataSource: dataSources.avatarViewDataSource,
                                        actions: self)
        }
        .onChange(of: streamedModel, perform: callUserDidSeeNewDetailsOfContactIfRequired)
    }
    
}


private struct DeletedContactView: View {
    var body: some View {
        ObvContentUnavailableView(
            title: String(localizedInThisBundle: "DELETED_CONTACT_TITLE"),
            systemIcon: .personSlash,
            description: String(localizedInThisBundle: "DELETED_CONTACT_DESCRIPTION"))
    }
}


extension ObvSingleContactView: ObvContactDetailedInfosViewActions {
    
    func userTappedBackButton(_ view: ObvContactDetailedInfosView) {
        isContactDetailedInfosViewPresented = false
    }
    
    func userWantsToSyncOneToOneStatusOfContact(_ view: ObvContactDetailedInfosView, contactIdentifier: ObvTypes.ObvContactIdentifier) {
        Task {
            do {
                try await actions.userWantsToSyncOneToOneStatusOfContact(self, contactIdentifier: contactIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
}

extension ObvSingleContactView: PersonalNoteEditorViewNavigation {
    
    public func userWantsToDismissPersonalNoteEditorView(_ view: ObvDesignSystem.PersonalNoteEditorView) {
        isPersonalNoteEditorViewPresented = false
    }
    
}


extension ObvSingleContactView {
    
    public enum ModelOrDeleted: Sendable, Equatable {
        case deleted
        case model(Model)
    }
    
    public struct Model: Sendable, Equatable {
        
        let contactIdentifier: ObvContactIdentifier
        let trustedIdentityDetails: ObvIdentityDetails
        let publishedIdentityDetails: ObvIdentityDetails? // Comming from the engine
        let customDetails: CustomDetails?
        let personalNote: String?
        let avatarModelFromTrustedDetails: ObvAvatarViewModel
        let avatarModelFromPublishedDetails: ObvAvatarViewModel? // Non-nil iff contactIdentity.publishedIdentityDetails is non-nil.
        let countOfContactDevices: Int
        let contactDeletionType: ContactDeletionType
        let atLeastOneDeviceAllowsThisContactToReceiveMessages: Bool
        let showReblockView: Bool
        let oneToOneInvitationSent: Bool
        let numberOfGroupsInCommon: Int
        let isActive: Bool
        let wasRecentlyOnline: Bool
        let isOneToOne: Bool

        public init(contactIdentifier: ObvContactIdentifier, trustedIdentityDetails: ObvIdentityDetails, publishedIdentityDetails: ObvIdentityDetails?, customDetails: CustomDetails?, personalNote: String?, avatarModelFromTrustedDetails: ObvAvatarViewModel, avatarModelFromPublishedDetails: ObvAvatarViewModel?, countOfContactDevices: Int, contactDeletionType: ContactDeletionType, atLeastOneDeviceAllowsThisContactToReceiveMessages: Bool, showReblockView: Bool, oneToOneInvitationSent: Bool, numberOfGroupsInCommon: Int, isActive: Bool, wasRecentlyOnline: Bool, isOneToOne: Bool) {
            self.contactIdentifier = contactIdentifier
            self.trustedIdentityDetails = trustedIdentityDetails
            self.publishedIdentityDetails = publishedIdentityDetails
            self.customDetails = customDetails
            self.personalNote = personalNote
            self.avatarModelFromTrustedDetails = avatarModelFromTrustedDetails
            self.avatarModelFromPublishedDetails = avatarModelFromPublishedDetails
            self.countOfContactDevices = countOfContactDevices
            self.contactDeletionType = contactDeletionType
            self.atLeastOneDeviceAllowsThisContactToReceiveMessages = atLeastOneDeviceAllowsThisContactToReceiveMessages
            self.showReblockView = showReblockView
            self.oneToOneInvitationSent = oneToOneInvitationSent
            self.numberOfGroupsInCommon = numberOfGroupsInCommon
            self.isActive = isActive
            self.wasRecentlyOnline = wasRecentlyOnline
            self.isOneToOne = isOneToOne
        }
        
        
        public struct CustomDetails: Sendable, Equatable {
            let nickname: String?
            let avatarModel: ObvAvatarViewModel?
            
            public init(nickname: String?, avatarModel: ObvAvatarViewModel?) {
                self.nickname = nickname
                self.avatarModel = avatarModel
            }
            
        }
         
        public enum ContactDeletionType: Sendable, Equatable {
            case downgradeToNonOneToOne
            case fullDeletion
            case legacyFullDeletion
            case fullDeletionImpossibleAsContactInCommonGroup
        }

        var contactPublishedDetailsValidationViewModel: ContactPublishedDetailsValidationViewModel? {
            guard let publishedDetails = publishedIdentityDetails, let avatarModelFromPublishedDetails else { return nil }
            return .init(contactIdentifier: contactIdentifier,
                         trustedDetails: trustedIdentityDetails,
                         publishedDetails: publishedDetails,
                         avatarModelFromPublishedDetails: avatarModelFromPublishedDetails)
        }
        
        var nicknameOrShortName: String {
            customDetails?.nickname ?? trustedIdentityDetails.getDisplayNameWithStyle(.short)
        }

    }
    
}



extension ObvSingleContactView: ContactPublishedDetailsValidationViewActions {
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ view: ContactPublishedDetailsValidationView, contactIdentifier: ObvContactIdentifier, publishedDetails: ObvIdentityDetails) async throws {
        Task {
            do {
                try await actions.userWantsToReplaceTrustedContactDetailsByPublishedContactDetails(self, contactIdentifier: contactIdentifier, publishedDetails: publishedDetails)
            } catch {
                assertionFailure()
            }
        }
    }
    
}

extension ObvSingleContactView: ObvSingleContactInternalViewActions {
    
    func userWantsToNavigateToListOfTrustOrigins() {
        do {
            try navigation.userWantsToNavigateToListOfTrustOrigins(self, contactIdentifier: self.contactIdentifier)
        } catch {
            assertionFailure()
        }
    }
    
    func userWantsToRemoveContactFromTheirContacts(contactDeletionType: ObvSingleContactView.Model.ContactDeletionType) {
        Task {
            do {
                try await actions.userWantsToRemoveContactFromTheirContacts(self, contactIdentifier: self.contactIdentifier, contactDeletionType: contactDeletionType)
                switch contactDeletionType {
                case .downgradeToNonOneToOne, .fullDeletionImpossibleAsContactInCommonGroup:
                    break
                case .fullDeletion, .legacyFullDeletion:
                    break
                }
            } catch {
                assertionFailure()
            }
        }
    }
    
    func userWantsToUnblockContact() {
        Task {
            do {
                try await actions.userWantsToUnblockContact(self, contactIdentifier: self.contactIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
    func userWantsToCancelTheOneToOneInvitationSentToContact() {
        Task {
            do {
                try await actions.userWantsToCancelTheOneToOneInvitationSentToContact(self, contactIdentifier: self.contactIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
    func userWantsToSendOneToOneInvitationToContact() {
        do {
            try actions.userWantsToSendOneToOneInvitationToContact(self, contactIdentifier: self.contactIdentifier)
        } catch {
            assertionFailure()
        }
    }
    
    func userWantsToNavigateToListOfCommonGroupsWithContact() {
        do {
            try navigation.userWantsToNavigateToListOfCommonGroupsWithContact(self, contactIdentifier: self.contactIdentifier)
        } catch {
            assertionFailure()
        }
    }
    
    func userWantsToCreateNewGroupWithContact() {
        Task {
            do {
                try await navigation.userWantsToCreateNewGroupWithContact(self, contactIdentifier: self.contactIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
    func userWantsToReblockContact() {
        Task {
            do {
                try await actions.userWantsToReblockContact(self, contactIdentifier: contactIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
    func userTappedTheCallButton() {
        navigation.userWantsToCallContact(self, contactIdentifier: contactIdentifier)
    }
    
    func userTappedTheChatButton() {
        do {
            try navigation.userWantsToNavigateToOneToOneDiscussionWithContact(self, contactIdentifier: contactIdentifier)
        } catch {
            assertionFailure()
        }
    }
    
    func userWantsToRestartChannelCreationWithContact() {
        Task {
            do {
                try await actions.userWantsToRestartChannelCreationWithContact(self, contactIdentifier: contactIdentifier)
                isRestartChannelCreationAlertShown = true
            } catch {
                isRestartChannelCreationFailedAlertShown = true
            }
        }
    }
    
    
    func userWantsToIntroduceOneContactToAnother() {
        do {
            try navigation.userWantsToIntroduceOneContactToAnother(self, contactIdentifier: contactIdentifier)
        } catch {
            assertionFailure()
        }
    }
    
    func userWantsToNavigateToListOfContactDevices() {
        do {
            try navigation.userWantsToNavigateToListOfContactDevices(self, contactIdentifier: self.contactIdentifier)
        } catch {
            assertionFailure()
        }
    }
    
}


@MainActor
protocol ObvSingleContactInternalViewActions: ContactPublishedDetailsValidationViewActions {
    func userWantsToIntroduceOneContactToAnother()
    func userWantsToNavigateToListOfContactDevices()
    func userWantsToReblockContact()
    func userTappedTheCallButton()
    func userTappedTheChatButton()
    func userWantsToRestartChannelCreationWithContact()
    func userWantsToNavigateToListOfCommonGroupsWithContact()
    func userWantsToCreateNewGroupWithContact()
    func userWantsToCancelTheOneToOneInvitationSentToContact()
    func userWantsToSendOneToOneInvitationToContact()
    func userWantsToUnblockContact()
    func userWantsToRemoveContactFromTheirContacts(contactDeletionType: ObvSingleContactView.Model.ContactDeletionType)
    func userWantsToNavigateToListOfTrustOrigins()
}


struct ObvSingleContactInternalView: View {

    let contactIdentifier: ObvContactIdentifier
    let viewModel: ObvSingleContactView.Model
    let avatarViewDataSource: ObvAvatarViewDataSource
    let internalActions: ObvSingleContactInternalViewActions
    @Binding var isRestartChannelCreationFailedAlertShown: Bool
    @Binding var isRestartChannelCreationAlertShown: Bool
            
    var body: some View {
        ScrollView(.vertical) {
            VStack {
                
                // Header
                
                HeaderView(viewModel: viewModel, avatarViewDataSource: avatarViewDataSource)
                
                // If active (i.e., not blocked): chat and call buttons or channel in creation message
                // If inactive (i.e., blocked): explanation view

                if viewModel.isActive {

                    UpperPartWhenNotBlocked(viewModel: viewModel, internalActions: internalActions)
                        .padding([.horizontal, .top])

                } else {
                    
                    // Unblock view
                    
                    UpperPartWhenBlocked(internalActions: internalActions)
                        .padding([.horizontal, .top])

                }
                
                // Was recently online
                
                if !viewModel.wasRecentlyOnline {
                    ContactWasNotRecentlyOnlineExplanationView()
                        .padding([.horizontal, .top])
                }

                // Personal note viewer
                
                if let personalNote = viewModel.personalNote?.trimmingWhitespacesAndNewlines(), !personalNote.isEmpty {
                    PersonalNoteStaticView(personalNote: personalNote)
                        .padding([.horizontal, .top])
                }

                // Card shown when there are published details that the user needs to accept
                
                if let contactPublishedDetailsValidationViewModel = viewModel.contactPublishedDetailsValidationViewModel {
                    ContactPublishedDetailsValidationView(
                        viewModel: contactPublishedDetailsValidationViewModel,
                        avatarViewDataSource: avatarViewDataSource,
                        internalActions: internalActions)
                    .padding([.horizontal, .top])
                }
                
                // Card allowing to introduce the contact to other contacts
                // Not shown for a revoked contact.
                
                if viewModel.isActive {
                    IntroduceContactView(name: viewModel.nicknameOrShortName, internalActions: internalActions)
                        .padding([.horizontal, .top])
                }
                
                // Common groups
                
                GroupsWithContactView(viewModel: viewModel, internalActions: internalActions)
                    .padding([.horizontal, .top])

                // Number of contact devices
                
                DevicesView(name: viewModel.nicknameOrShortName,
                            countOfContactDevices: viewModel.countOfContactDevices,
                            internalActions: internalActions)
                .padding([.horizontal, .top])
                
                // Trust origins
                
                TrustOriginsView(internalActions: internalActions)
                    .padding([.horizontal, .top])
                
                // Remove from contacts button
                
                RemoveFromContactsButton(
                    name: viewModel.nicknameOrShortName,
                    contactDeletionType: viewModel.contactDeletionType,
                    internalActions: internalActions)
                .padding([.horizontal, .top])


            }
            .padding(.bottom)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .alert(String(localizedInThisBundle: "AT_LEAST_ONE_CHANNEL_FAILED_TO_RESTART"), isPresented: $isRestartChannelCreationFailedAlertShown, actions: {})
        .alert(String(localizedInThisBundle: "CHANNEL_ESTABLISHMENT_WAS_RESTARTED"), isPresented: $isRestartChannelCreationAlertShown, actions: {})
    }
    
    
}


// MARK: - Internal view (Menu)

extension ObvSingleContactView {
    
    struct InternalMenu: View {
        
        @Binding var isPersonalNoteEditorViewPresented: Bool
        @Binding var isContactDetailedInfosViewPresented: Bool
        let userTappedOnTheEditCustomNameAndPhotoButton: () -> Void
        
        private var systemIconForMenuLabel: SystemIcon {
            if #available(iOS 26, *) {
                return .ellipsis
            } else {
                return .ellipsisCircle
            }
        }
        
        private func userTappedOnTheEditPersonalNoteButton() {
            isPersonalNoteEditorViewPresented = true
        }
        
        private func userTappedOnShowContactDetailsButton() {
            isContactDetailedInfosViewPresented = true
        }

        var body: some View {
            Menu {
                Section {
                 
                    Button(action: userTappedOnTheEditPersonalNoteButton) {
                        Label(title: { Text("EDIT_PERSONAL_NOTE") }, icon: { Image(systemIcon: .noteText) })
                    }

                    Button(action: userTappedOnTheEditCustomNameAndPhotoButton) {
                        Label { Text("EDIT_NICKNAME_AND_CUSTOM_PHOTO") } icon: { Image(systemIcon: .camera(.none)) }
                    }

                }
                
                Section {
                    
                    Button(action: userTappedOnShowContactDetailsButton) {
                        Label(title: { Text("SHOW_CONTACT_DETAILS") }, icon: { Image(systemIcon: .personCropCircleBadgeQuestionmark) })
                    }

                }
                
            } label: {
                Image(systemIcon: systemIconForMenuLabel)
            }
        }
        
    }
    
}


// MARK: - Internal view

private struct GroupsWithContactView: View {
    
    let viewModel: ObvSingleContactView.Model
    let internalActions: ObvSingleContactInternalViewActions
    
    var body: some View {

        VStack {
            
            HStack(alignment: .firstTextBaseline) {
                Text("COMMON_GROUPS")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.bold)
                Spacer()
            }
            
            ObvCardView(padding: 0) {
                
                VStack(alignment: .leading, spacing: 0) {
                    
                    if viewModel.numberOfGroupsInCommon > 0 {
                        
                        Text("YOU_AND_\(viewModel.nicknameOrShortName)_HAVE_\(viewModel.numberOfGroupsInCommon)_GROUPS_IN_COMMON")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding()
                        Divider()
                        Button(action: internalActions.userWantsToNavigateToListOfCommonGroupsWithContact) {
                            HStack {
                                
                                Image(systemIcon: .person3)
                                    .foregroundStyle(Color(.tintColor))
                                    .frame(width: 40)

                                Text("SEE_\(viewModel.numberOfGroupsInCommon)_GROUPS_IN_COMMON")
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(.primary)

                                Spacer()
                                ObvChevronRight()
                            }
                            .padding()
                            .contentShape(Rectangle()) // Trick making the button interactive everywhere
                        }
                        .buttonStyle(.plain)
                        
                    } else {
                        
                        HStack {
                            Text("YOU_HAVE_NO_GROUP_IN_COMMON_WITH_\(viewModel.nicknameOrShortName)")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding()
                            Spacer()
                        }
                        
                    }
                    
                    // Button allowing to start a group creation with the contact.
                    // Not shown if the contact was revoked.
                    
                    if viewModel.isActive {
                        
                        Divider()
                        
                        Button(action: internalActions.userWantsToCreateNewGroupWithContact) {
                            Spacer(minLength: 0)
                            Label {
                                Text("CREATE_GROUP_WITH_\(viewModel.nicknameOrShortName)")
                            } icon: {
                                Image(systemIcon: .plusCircle)
                            }
                            .padding(.vertical, 4)
                            Spacer(minLength: 0)
                        }
                        .buttonStyle(.bordered)
                        .padding()
                        
                    }
                    
                }
                
            }
        }
        
    }
    
}


// MARK: - Internal view

private struct UpperPartWhenNotBlocked: View {
    
    let viewModel: ObvSingleContactView.Model
    let internalActions: ObvSingleContactInternalViewActions

    @State private var showAlertOneToOneInvitationRequired: Bool = false
        
    private func userTappedTheChatButton() {
        if viewModel.isOneToOne {
            internalActions.userTappedTheChatButton()
        } else {
            showAlertOneToOneInvitationRequired = true
        }
    }

    private func userTappedInviteOrCancelToOneToOneButton() {
        if viewModel.oneToOneInvitationSent {
            internalActions.userWantsToCancelTheOneToOneInvitationSentToContact()
        } else {
            internalActions.userWantsToSendOneToOneInvitationToContact()
        }
    }
    
    private var callButtonIsDisabled: Bool {
        !(viewModel.isActive && viewModel.atLeastOneDeviceAllowsThisContactToReceiveMessages)
    }

    var body: some View {
        
        VStack {
            
            if viewModel.atLeastOneDeviceAllowsThisContactToReceiveMessages {
                
                ObvChatAndCallButtonsView(
                    chatButtonLooksInactive: !viewModel.isOneToOne,
                    callButtonIsDisabled: callButtonIsDisabled,
                    userTappedTheChatButton: userTappedTheChatButton,
                    userTappedTheCallButton: internalActions.userTappedTheCallButton)
                .padding(.vertical)
                .alert(String(localizedInThisBundle: "INVITE_REQUIRED_ALERT_TITLE"), isPresented: $showAlertOneToOneInvitationRequired, actions: {
                    if #available(iOS 26.0, *) {
                        Button(role: .cancel, action: {})
                    } else {
                        Button(action: {}, label: { Text("CANCEL") })
                    }
                    Button(action: userTappedInviteOrCancelToOneToOneButton) {
                        Label(title: { Text("INVITE") }, icon: { Image(systemIcon: .personBadgePlus) })
                    }
                }, message: {
                    Text("YOU_NEED_TO_INVITE_\(viewModel.nicknameOrShortName)_BEFORE_HAVING_DISCUSSION_ALERT_MESSAGE")
                })
                
                if !viewModel.isOneToOne {
                    InviteContactToOneToOneView(
                        name: viewModel.nicknameOrShortName,
                        oneToOneInvitationSent: viewModel.oneToOneInvitationSent,
                        userTappedInviteOrCancelToOneToOneButton: userTappedInviteOrCancelToOneToOneButton)
                    .padding([.vertical, .top])
                }
                
            } else if viewModel.countOfContactDevices > 0 {
                
                CreatingChannelExplanationView(internalActions: internalActions)
                    .padding([.vertical, .top])

            }
            
            // Reblock view
            
            if viewModel.showReblockView {
                ContactCanBeReblockedExplanationView(internalActions: internalActions)
                    .padding([.vertical, .top])
            }
            
        }
        
    }
    
}


// MARK: - Internal view

private struct InviteContactToOneToOneView: View {
    
    let name: String
    let oneToOneInvitationSent: Bool
    let userTappedInviteOrCancelToOneToOneButton: () -> Void
    
    var body: some View {
        ObvCardView {
            VStack {
                HStack(alignment: .firstTextBaseline) {
                    Text(oneToOneInvitationSent ? "ONE_TO_ONE_INVITATION_SENT_TO_\(name)_EXPLANATION" : "ONE_TO_ONE_INVITATION_TO_\(name)_REQUIRED_EXPLANATION")
                    Spacer()
                }
                .font(.body)
                .foregroundStyle(.secondary)
                Button(action: userTappedInviteOrCancelToOneToOneButton) {
                    HStack {
                        Spacer(minLength: 0)
                        Label(title: {
                            Text(oneToOneInvitationSent ? "ABORT" : "INVITE")
                        }, icon: {
                            Image(systemIcon: oneToOneInvitationSent ? .xmarkCircle : .personBadgePlus)
                        })
                        .padding(.vertical, 4)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(oneToOneInvitationSent ? .red : .accentColor)
            }
        }
    }
    
}

// MARK: - Internal view

private struct ContactWasNotRecentlyOnlineExplanationView: View {

    var body: some View {
        ObvCardView {
            VStack {
                HStack(alignment: .firstTextBaseline) {
                    Text("CONTACT_WAS_NOT_RECENTLY_ONLINE_TITLE")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemIcon: .zzz)
                        .foregroundColor(.secondary)
                }
                .font(.headline)
                HStack {
                    Text("CONTACT_WAS_NOT_RECENTLY_ONLINE_BODY")
                        .lineLimit(nil)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: /*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
                    Spacer()
                }
            }
        }
    }
    
}


// MARK: - Internal view

fileprivate struct ContactCanBeReblockedExplanationView: View {
    
    let internalActions: ObvSingleContactInternalViewActions
    
    @State private var showAlertConfirm = false

    var body: some View {
        ObvCardView {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("CONTACT_IS_NOT_ACTIVE_EXPLANATION_TITLE")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemIcon: .shieldFill)
                        .foregroundStyle(.red)
                }
                .font(.headline)
                HStack {
                    Text("EXPLANATION_CONTACT_REVOKED_AND_UNBLOCKED")
                        .lineLimit(nil)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: /*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
                    Spacer()
                }
                OlvidButton(style: .standard, title: Text("REBLOCK_CONTACT"), systemIcon: .exclamationmarkShieldFill, action: { showAlertConfirm.toggle() })
                    .actionSheet(isPresented: $showAlertConfirm) {
                        ActionSheet(title: Text("REBLOCK_CONTACT"), message: Text("REBLOCK_CONTACT_CONFIRMATION"), buttons: [
                            .default(Text("Yes"), action: internalActions.userWantsToReblockContact),
                            .cancel(),
                        ])
                    }
            }
        }
    }

}


// MARK: - Internal view

private struct UpperPartWhenBlocked: View {
    
    let internalActions: ObvSingleContactInternalViewActions
    
    @State private var showAlertConfirm = false

    var body: some View {
        ObvCardView {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("CONTACT_IS_NOT_ACTIVE_EXPLANATION_TITLE")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemIcon: .exclamationmarkShieldFill)
                        .foregroundColor(.red)
                }
                .font(.headline)
                HStack {
                    Text("CONTACT_IS_NOT_ACTIVE_EXPLANATION_BODY")
                        .lineLimit(nil)
                        .font(.body)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: /*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
                    Spacer()
                }
                Button(action: { showAlertConfirm = true }) {
                    HStack {
                        Spacer(minLength: 0)
                        Label(title: { Text("UNBLOCK_CONTACT") }, icon: { Image(systemIcon: .shieldFill) })
                            .padding(.vertical, 4)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.bordered)
                .confirmationDialog(String(localizedInThisBundle: "UNBLOCK_CONTACT"), isPresented: $showAlertConfirm, titleVisibility: .visible, actions: {
                    Button(action: internalActions.userWantsToUnblockContact) {
                        Text("YES")
                    }
                })
            }
        }
    }

}



// MARK: - Internal view

private struct RemoveFromContactsButton: View {
    
    let name: String
    let contactDeletionType: ObvSingleContactView.Model.ContactDeletionType
    let internalActions: ObvSingleContactInternalViewActions
    
    @State private var showAlertConfirm = false
    @State private var showAlertContactCannotBeDeletedAsPartOfCommonGroup = false
    
    private func userTappedRemoveFromContactsButton() {
        internalActions.userWantsToRemoveContactFromTheirContacts(contactDeletionType: contactDeletionType)
    }

    private var deleteContactButtonTitle: String {
        switch contactDeletionType {
        case .legacyFullDeletion: return String(localizedInThisBundle: "DELETE_CONTACT")
        case .downgradeToNonOneToOne: return String(localizedInThisBundle: "DOWNGRADE_CONTACT_TO_NON_ONE_TO_ONE_BUTTON_TITLE")
        case .fullDeletion: return String(localizedInThisBundle: "DELETE_OLVID_USER")
        case .fullDeletionImpossibleAsContactInCommonGroup: return String(localizedInThisBundle: "DELETE_OLVID_USER") // An alert will explain why the deletion is impossible
        }
    }
    
    private func userTappedButton() {
        switch contactDeletionType {
        case .downgradeToNonOneToOne:
            showAlertConfirm = true
        case .fullDeletion, .legacyFullDeletion:
            showAlertConfirm = true
        case .fullDeletionImpossibleAsContactInCommonGroup:
            showAlertContactCannotBeDeletedAsPartOfCommonGroup = true
        }
    }
    
    private var confirmationOrAlertTitle: String {
        switch contactDeletionType {
        case .downgradeToNonOneToOne:
            return String(localizedInThisBundle: "ARE_YOU_SURE_YOU_WANT_TO_DELETE_\(name)_FROM_YOUR_CONTACTS")
        case .fullDeletion, .legacyFullDeletion:
            return String(localizedInThisBundle: "ARE_YOU_SURE_YOU_WANT_TO_FULLY_DELETE_\(name)")
        case .fullDeletionImpossibleAsContactInCommonGroup:
            return String(localizedInThisBundle: "CANNOT_DELETE_USER_FOR_NOW")
        }
    }
    
    var body: some View {
        
        Button(action: userTappedButton) {
            HStack {
                Spacer(minLength: 0)
                Label(title: { Text(deleteContactButtonTitle) }, icon: { Image(systemIcon: .minusCircle) })
                    .padding(.vertical, 4)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .confirmationDialog(confirmationOrAlertTitle, isPresented: $showAlertConfirm, titleVisibility: .visible) {
            Button(role: .destructive, action: userTappedRemoveFromContactsButton) {
                Text("YES")
            }
        }
        .alert(confirmationOrAlertTitle,
               isPresented: $showAlertContactCannotBeDeletedAsPartOfCommonGroup,
               actions: {},
               message: { Text("CANNOT_DELETE_USER_\(name)_AS_PART_OF_COMMON_GROUPS") })
        
    }
    
}


// MARK: - Internal view

fileprivate struct CreatingChannelExplanationView: View {
    
    let internalActions: ObvSingleContactInternalViewActions
    @State private var showAlertConfirmRestart = false
        
    var body: some View {
        ObvCardView {
            VStack(spacing: 8) {
                HStack(alignment: .top) {
                    Text("ESTABLISHING_SECURE_CHANNEL")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    ProgressView()
                }
                HStack {
                    Text("ESTABLISHING_SECURE_CHANNEL_EXPLANATION")
                        .lineLimit(nil)
                        .font(.body)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: /*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
                    Spacer()
                }
                Button(action: { showAlertConfirmRestart = true }) {
                    HStack {
                        Spacer(minLength: 0)
                        Label(title: { Text("Restart") }, icon: { Image(systemIcon: .restartCircle) })
                        
                            .padding(.vertical, 4)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.bordered)
                .confirmationDialog(String(localizedInThisBundle: "RESTART_CHANNEL_CREATION"), isPresented: $showAlertConfirmRestart, titleVisibility: .visible) {
                    Button(action: internalActions.userWantsToRestartChannelCreationWithContact) {
                        Text("YES")
                    }
                }
            }
        }
    }
    
}


// MARK: - Internal view

private struct TrustOriginsView: View {
    
    let internalActions: ObvSingleContactInternalViewActions
    
    var body: some View {
        
        VStack(alignment: .leading) {
            
            HStack {
                Text("TRUST_ORIGINS")
                    .font(.system(.headline, design: .rounded))
                Spacer()
            }
            
            ObvCardView {
                Button(action: internalActions.userWantsToNavigateToListOfTrustOrigins) {

                    HStack(alignment: .center) {
                        Image(systemIcon: .checkmarkShield)
                            .foregroundStyle(.green)
                            .font(.system(size: 22))
                            .frame(width: 40)

                        Text("TRUST_ORIGINS")
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Spacer()

                        ObvChevronRight()
                        
                    }
                    .contentShape(Rectangle()) // Trcik that makes it possible to have an "on tap" gesture that also works when the Spacer is tapped

                }
                .buttonStyle(.plain)
            }
            
        }

    }
    
}


// MARK: - Internal view

private struct DevicesView: View {
    
    let name: String
    let countOfContactDevices: Int
    let internalActions: ObvSingleContactInternalViewActions

    var body: some View {
        
        VStack(alignment: .leading) {
            
            HStack {
                Text("DEVICES")
                    .font(.system(.headline, design: .rounded))
                Spacer()
            }
            
            ObvCardView {
                Button(action: internalActions.userWantsToNavigateToListOfContactDevices) {

                    HStack(alignment: .firstTextBaseline) {
                        Image(systemIcon: .laptopcomputerAndIphone)
                            .foregroundStyle(Color(.tintColor))
                            .font(.system(size: 22))
                            .frame(width: 40)

                        Text("CONTACT_\(name)_HAS_\(countOfContactDevices)_DEVICES")
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Spacer()

                        ObvChevronRight()
                        
                    }
                    .contentShape(Rectangle()) // Trcik that makes it possible to have an "on tap" gesture that also works when the Spacer is tapped

                }
                .buttonStyle(.plain)
            }
            
        }
        
    }
    
}


// MARK: - Internal view

private struct IntroduceContactView: View {

    let name: String
    let internalActions: ObvSingleContactInternalViewActions
    
    var body: some View {
        
        VStack {
            
            HStack(alignment: .firstTextBaseline) {
                Text("CONTACT_INTRODUCTION_TITLE_\(name)")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.bold)
                Spacer()
            }
            
            ObvCardView(padding: 0) {
                
                VStack {
                    HStack {
                        Text("CONTACT_INTRODUCTION_EXPLANATION_\(name)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 4)
                    Button(action: internalActions.userWantsToIntroduceOneContactToAnother) {
                        HStack {
                            Spacer(minLength: 0)
                            Label(title: { Text("INTRODUCE_\(name)_TO_DOTS") }, icon: { Image(systemIcon: .arrowshapeTurnUpForward) })
                                .padding(.vertical, 4)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.bordered)
                }.padding()
                
            }
            
        }
        
    }
    
}




// MARK: - Internal view

private struct HeaderView: View {
    
    let viewModel: ObvSingleContactView.Model
    let avatarViewDataSource: ObvAvatarViewDataSource

    private var avatarModel: ObvAvatarViewModel {
        viewModel.customDetails?.avatarModel ?? viewModel.avatarModelFromTrustedDetails
    }

    private var headerTitle: String {
        viewModel.customDetails?.nickname ?? viewModel.trustedIdentityDetails.getDisplayNameWithStyle(.firstNameThenLastName)
    }
    
    private var headerSubtitle: String? {
        if viewModel.customDetails == nil {
            return viewModel.trustedIdentityDetails.coreDetails.positionAtCompany()
        } else {
            return viewModel.trustedIdentityDetails.getDisplayNameWithStyle(.firstNameThenLastName)
        }
    }

    private var headerSubSubtitle: String? {
        if viewModel.customDetails == nil {
            return nil
        } else {
            return viewModel.trustedIdentityDetails.coreDetails.positionAtCompany()
        }
    }
    
    var body: some View {
        VStack {
            ObvAvatarView(model: avatarModel,
                          style: .circle,
                          size: .xLarge,
                          dataSource: avatarViewDataSource,
                          showGreenShieldIfAppropriate: true)
            Text(headerTitle)
                .font(.system(.title, design: .rounded))
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            if let headerSubtitle {
                Text(headerSubtitle)
                    .font(.system(.title2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let headerSubSubtitle {
                Text(headerSubSubtitle)
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
}



// MARK: - Previews

#if DEBUG

private final class DataSourceAndActionsForPreviews {}


extension DataSourceAndActionsForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
}

extension DataSourceAndActionsForPreviews: PersonalNoteEditorViewActions {
    
    func userWantsToUpdatePersonalNote(_ view: ObvDesignSystem.PersonalNoteEditorView, with newText: String?, about: ObvDesignSystem.PersonalNoteEditorView.Model.About) async throws {
        print("User wants to update personal note")
    }
    
}

extension DataSourceAndActionsForPreviews: ObvSingleContactViewActions {
    
    func userDidSeeNewDetailsOfContact(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier) {
        print("User did see new details of contact")
    }
    
    func userWantsToSyncOneToOneStatusOfContact(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        print("User wants to sync one-to-one status of contact")
    }
    
    func userWantsToRemoveContactFromTheirContacts(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier, contactDeletionType: ObvSingleContactView.Model.ContactDeletionType) throws {
        print("User wants to remove contact from their contacts.")
    }
    
    func userWantsToUnblockContact(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        print("User wants to unblock contact.")
    }
    
    func userWantsToCancelTheOneToOneInvitationSentToContact(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        print("User wants to cancel the one to one invitation sent to contact.")
    }
    
    func userWantsToSendOneToOneInvitationToContact(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        print("User wants to send one to one invitation to contact.")
    }
    
    func userWantsToReblockContact(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        print("User wants to reblock contact.")
    }
    
    func userWantsToRestartChannelCreationWithContact(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        print("User wants to restart channel creation with contact.")
    }
    
    func userWantsToReplaceTrustedContactDetailsByPublishedContactDetails(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier, publishedDetails: ObvTypes.ObvIdentityDetails) throws {
        print("User wants to replace trusted contact details by published contact details.")
    }
        
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ view: ContactPublishedDetailsValidationView, contactIdentifier: ObvContactIdentifier, publishedDetails: ObvIdentityDetails) async throws {
        print("User wants to replace trusted details by published details")
    }

}

extension DataSourceAndActionsForPreviews: ObvSingleContactViewDataSource {
    
    func getAsyncSequenceOfSingleContactViewModel(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleContactView.ModelOrDeleted>) {
        let stream = AsyncStream<ObvSingleContactView.ModelOrDeleted> { (continuation: AsyncStream<ObvSingleContactView.ModelOrDeleted>.Continuation) in
            Task {
                while true {
//                    try? await Task.sleep(seconds: 0)
//                    let viewModel: ObvSingleContactView.Model = .sampleData
//                    continuation.yield(viewModel)
//                    do {
//                        try? await Task.sleep(seconds: 2)
//                        let viewModel = ObvSingleContactView.Model(
//                            contactIdentity: ObvContactIdentity.sampleData,
//                            customDetails: ObvSingleContactView.Model.CustomDetails.sampleData,
//                            personalNote: "Some personal note",
//                            avatarModelFromTrustedDetails: .sampleDataForTrustedDetails,
//                            avatarModelFromPublishedDetails: .sampleDataForPublishedDetails,
//                            countOfContactDevices: 2,
//                            contactDeletionType: .downgradeToNonOneToOne,
//                            atLeastOneDeviceAllowsThisContactToReceiveMessages: true,
//                            showReblockView: false,
//                            oneToOneInvitationSent: true,
//                            numberOfGroupsInCommon: 2)
//                        continuation.yield(viewModel)
//                    }
                    do {
                        try? await Task.sleep(seconds: 0)
                        let viewModel = ObvSingleContactView.Model(
                            contactIdentifier: .sampleData,
                            trustedIdentityDetails: .sampleDataForTrustedDetails,
                            publishedIdentityDetails: .sampleDataForPublishedDetails,
                            customDetails: ObvSingleContactView.Model.CustomDetails.sampleData,
                            personalNote: "Some personal note",
                            avatarModelFromTrustedDetails: .sampleDataForTrustedDetails,
                            avatarModelFromPublishedDetails: .sampleDataForPublishedDetails,
                            countOfContactDevices: 2,
                            contactDeletionType: .downgradeToNonOneToOne,
                            atLeastOneDeviceAllowsThisContactToReceiveMessages: true,
                            showReblockView: false,
                            oneToOneInvitationSent: false,
                            numberOfGroupsInCommon: 2,
                            isActive: true,
                            wasRecentlyOnline: true,
                            isOneToOne: true)
                        continuation.yield(.model(viewModel))
                    }
                    try? await Task.sleep(seconds: 2)
                }

            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfSingleContactViewModel(_ view: ObvSingleContactView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
}


extension DataSourceAndActionsForPreviews: ObvContactDetailedInfosViewDataSource {
    
    func getAsyncSequenceOfContactDetailedInfosViewModel(_ view: ObvContactDetailedInfosView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvContactDetailedInfosView.Model>) {
        let stream = AsyncStream<ObvContactDetailedInfosView.Model> { (continuation: AsyncStream<ObvContactDetailedInfosView.Model>.Continuation) in
            let model = ObvContactDetailedInfosView.Model(
                avatarModel: .sampleDataForTrustedDetails,
                identityCoreDetails: .sampleDataForTrustedDetails,
                customDisplayName: "Custom name",
                isActive: true,
                isCertifiedByOwnKeycloak: false,
                wasRecentlyOnline: true,
                capabilitites: [.groupsV2, .oneToOneContacts],
                devices: [
                    .init(identifier: Data(repeating: 0x00, count: 32),
                          secureChannelStatus: .created(preKeyAvailable: true))
                ])
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfContactDetailedInfosViewModel(_ view: ObvContactDetailedInfosView, streamUUID: UUID) {}
    
}

extension DataSourceAndActionsForPreviews: PersonalNoteEditorViewNavigation {
    
    func userWantsToDismissPersonalNoteEditorView(_ view: ObvDesignSystem.PersonalNoteEditorView) {
        print("User wants to dismiss personal note editor view.")
    }
    
}

extension DataSourceAndActionsForPreviews: ObvSingleContactViewNavigation {
 
    func userWantsToNavigateToListOfContactDevices(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        print("User wants to navigate to list of contact devices.")
    }

    func userWantsToNavigateToListOfTrustOrigins(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        print("User wants to navigate to list of trust origins.")
    }

    func userWantsToNavigateToOneToOneDiscussionWithContact(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        print("User wants to navigate to one to one discussion with contact.")
    }

    func userWantsToIntroduceOneContactToAnother(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        print("User wants to introduce one contact to another.")
    }

    func userWantsToCallContact(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) {
        print("User wants to call contact.")
    }
        
    func userWantsToNavigateToListOfCommonGroupsWithContact(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        print("User wants to navigate to list of common groups with contact.")
    }
    
    func userWantsToCreateNewGroupWithContact(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        print("User wants to create new group with contact.")
    }
                
    func userWantsToEditContactNicknameAndCustomPicture(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier) {
        print("User wants to edit contact nickname and custom picture.")
    }
    
}

extension DataSourceAndActionsForPreviews: UIKitDelegateForSwiftUISheet {
    func userWantsToPresentView<Content>(_ view: some View, content: @escaping () -> Content) where Content : View {
        // We don't implement this method. Consequently certain views cannot be presented when showing previews on catalyst.
    }
    func userWantsToDismissPresentedView(_ view: some View) {}
}

@MainActor
private let dataSourceAndActionsForPreviews = DataSourceAndActionsForPreviews()

#Preview {
    NavigationView {
        ObvSingleContactView(contactIdentifier: .sampleData,
                             dataSources: .init(
                                dataSource: dataSourceAndActionsForPreviews,
                                avatarViewDataSource: dataSourceAndActionsForPreviews,
                                contactDetailedInfosViewDataSource: dataSourceAndActionsForPreviews),
                             actions: dataSourceAndActionsForPreviews,
                             navigation: dataSourceAndActionsForPreviews,
                             uiKitDelegateForSwiftUISheet: dataSourceAndActionsForPreviews)
    }
    //.environment(\.locale, .init(identifier: "fr"))
}


#endif
