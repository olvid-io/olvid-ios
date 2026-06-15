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
import OSLog
import CoreData
import ObvTypes
import ObvAppTypes
import ObvCircleAndTitlesView
import ObvDesignSystem
import ObvAppCoreConstants



// MARK: - SelectUsersToAddViewModel

public struct SelectUsersToAddViewModel: Sendable, Equatable {

    let textOnEmptySetOfUsers: String
    let allUserIdentifiers: [User.Identifier]
    
    public init(textOnEmptySetOfUsers: String, allUserIdentifiers: [User.Identifier]) {
        self.textOnEmptySetOfUsers = textOnEmptySetOfUsers
        self.allUserIdentifiers = allUserIdentifiers
    }

    public struct User: Sendable, Equatable {
        
        public let identifier: Identifier
        let isKeycloakManaged: Bool
        let profilePictureInitial: String?
        let circleColors: InitialCircleView.Model.Colors
        let identityDetails: ObvIdentityDetails
        let isRevokedAsCompromised: Bool
        let customDisplayName: String?
        let customPhotoURL: URL?
        
        public init(identifier: Identifier, isKeycloakManaged: Bool, profilePictureInitial: String?, circleColors: InitialCircleView.Model.Colors, identityDetails: ObvIdentityDetails, isRevokedAsCompromised: Bool, customDisplayName: String?, customPhotoURL: URL?) {
            self.identifier = identifier
            self.isKeycloakManaged = isKeycloakManaged
            self.profilePictureInitial = profilePictureInitial
            self.circleColors = circleColors
            self.identityDetails = identityDetails
            self.isRevokedAsCompromised = isRevokedAsCompromised
            self.customDisplayName = customDisplayName
            self.customPhotoURL = customPhotoURL
        }

        public enum Identifier: Identifiable, Sendable, CustomDebugStringConvertible, Hashable {
            
            case contactIdentifier(contactIdentifier: ObvContactIdentifier)
            case objectIDOfPersistedObvContactIdentity(objectID: NSManagedObjectID)
            
            public var id: Data {
                switch self {
                case .contactIdentifier(let contactIdentifier):
                    return contactIdentifier.ownedCryptoId.getIdentity() + contactIdentifier.contactCryptoId.getIdentity()
                case .objectIDOfPersistedObvContactIdentity(let objectID):
                    return objectID.uriRepresentation().dataRepresentation
                }
            }
            
            public var debugDescription: String {
                switch self {
                case .contactIdentifier(contactIdentifier: let contactIdentifier):
                    return contactIdentifier.description
                case .objectIDOfPersistedObvContactIdentity(let objectID):
                    return objectID.debugDescription
                }
            }
            
        }

    }

}


extension SelectUsersToAddViewModel.User.Identifier: Equatable {
    // Synthesized implemention
}


// MARK: - Data source

@MainActor
public protocol SelectUsersToAddViewDataSource {
    func getAsyncSequenceOfUsersToAddToCreatingGroup(_ view: SelectUsersToAddView, ownedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>)
    func getAsyncSequenceOfUsersToAddToExistingGroup(_ view: SelectUsersToAddView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>)
    func filterAsyncSequenceOfUsersToAdd(_ view: SelectUsersToAddView.InternalView, streamUUID: UUID, searchText: String?)
    func finishAsyncSequenceOfSelectUsersToAddViewModel(_ view: SelectUsersToAddView, streamUUID: UUID)
}


// MARK: - Actions

@MainActor
public protocol SelectUsersToAddViewActionsForEdition {
    func userWantsToAddSelectedUsersToExistingGroup(_ view: SelectUsersToAddView.InternalView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) async throws
}

@MainActor
public protocol SelectUsersToAddViewActionsForCreation {
    func userWantsToAddSelectedUsersToCreatingGroup(_ view: SelectUsersToAddView.InternalView, creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier])
}

@MainActor
public protocol SelectUsersToAddViewNavigationForEdition {
    func viewShouldBeDismissed(_ view: SelectUsersToAddView.InternalView)
}

@MainActor
public protocol SelectUsersToAddViewNavigationForCreation {
    func userDidFinishSelectingUsersToAddAndWantsToNavigateToNextScreen(_ view: SelectUsersToAddView.InternalView)
}

// MARK: - Main view: SelectUsersToAddView

public struct SelectUsersToAddView: View {
    
    let mode: Mode
    let dataSource: SelectUsersToAddViewDataSource
    let listOfUsersViewCellDataSource: ListOfUsersViewCellDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    
    public init(mode: Mode, dataSource: SelectUsersToAddViewDataSource, listOfUsersViewCellDataSource: ListOfUsersViewCellDataSource, avatarViewDataSource: ObvAvatarViewDataSource) {
        self.mode = mode
        self.dataSource = dataSource
        self.listOfUsersViewCellDataSource = listOfUsersViewCellDataSource
        self.avatarViewDataSource = avatarViewDataSource
    }
    
    public enum Mode {
        case edition(groupIdentifier: ObvAppTypes.ObvGroupIdentifier, actions: SelectUsersToAddViewActionsForEdition, navigation: SelectUsersToAddViewNavigationForEdition)
        case creation(ownedCryptoId: ObvCryptoId, creationSessionUUID: UUID, preselectedUserIdentifiers: [SelectUsersToAddViewModel.User.Identifier], actionsForCreation: SelectUsersToAddViewActionsForCreation, navigation: SelectUsersToAddViewNavigationForCreation)
    }
    
    @State private var model: SelectUsersToAddViewModel?
    @State private var modelFilteredBySearch: SelectUsersToAddViewModel?
    @State private var streamUUIDForModel: UUID?
    @State private var streamUUIDForModelFilteredBySearch: UUID?

    @State private var searchText: String = ""

    @State private var identifiersOfSelectedUsers = [SelectUsersToAddViewModel.User.Identifier]()
    @State private var preselectedUserIdentifiersWereSet = false // Only used on creation, when cloning a group

    private func onAppear() {
        
        // When cloning a group, use the pre-selected identifiers of members
        switch mode {
        case .edition:
            break
        case .creation(ownedCryptoId: _, creationSessionUUID: _, preselectedUserIdentifiers: let preselectedUserIdentifiers, actionsForCreation: _, navigation: _):
            if !preselectedUserIdentifiersWereSet {
                preselectedUserIdentifiersWereSet = true
                self.identifiersOfSelectedUsers = preselectedUserIdentifiers
            }
        }
        
        Task {
            do {
                guard self.streamUUIDForModel == nil else { return }
                let streamUUID: UUID
                let stream: AsyncStream<SelectUsersToAddViewModel>
                switch mode {
                case .edition(groupIdentifier: let groupIdentifier, actions: _, navigation: _):
                    (streamUUID, stream) = try await dataSource.getAsyncSequenceOfUsersToAddToExistingGroup(self, groupIdentifier: groupIdentifier)
                case .creation(ownedCryptoId: let ownedCryptoId, creationSessionUUID: _, preselectedUserIdentifiers: _, actionsForCreation: _, navigation: _):
                    (streamUUID, stream) = try await dataSource.getAsyncSequenceOfUsersToAddToCreatingGroup(self, ownedCryptoId: ownedCryptoId)
                }
                self.streamUUIDForModel = streamUUID
                for await model in stream {
                    withAnimation {
                        self.model = model
                        // Make sure the identifiersOfSelectedUsers only contains identifiers of members that are part of the model.
                        // This, in particular, allows to filter out certain members when cloning a group containing members that can no longer be reached.
                        self.identifiersOfSelectedUsers = self.identifiersOfSelectedUsers.filter { model.allUserIdentifiers.contains($0) }
                    }
                }
            } catch {
                assertionFailure()
            }
        }
        Task {
            do {
                guard self.streamUUIDForModelFilteredBySearch == nil else { return }
                let streamUUID: UUID
                let stream: AsyncStream<SelectUsersToAddViewModel>
                switch mode {
                case .edition(groupIdentifier: let groupIdentifier, actions: _, navigation: _):
                    (streamUUID, stream) = try await dataSource.getAsyncSequenceOfUsersToAddToExistingGroup(self, groupIdentifier: groupIdentifier)
                case .creation(ownedCryptoId: let ownedCryptoId, creationSessionUUID: _, preselectedUserIdentifiers: _, actionsForCreation: _, navigation: _):
                    (streamUUID, stream) = try await dataSource.getAsyncSequenceOfUsersToAddToCreatingGroup(self, ownedCryptoId: ownedCryptoId)
                }
                self.streamUUIDForModelFilteredBySearch = streamUUID
                for await model in stream {
                    withAnimation {
                        self.modelFilteredBySearch = model
                    }
                }
            } catch {
                assertionFailure()
            }
        }
    }
    
    private func onDisappear() {
        if let streamUUID = self.streamUUIDForModel {
            dataSource.finishAsyncSequenceOfSelectUsersToAddViewModel(self, streamUUID: streamUUID)
            self.streamUUIDForModel = nil
        }
        if let streamUUID = self.streamUUIDForModelFilteredBySearch {
            dataSource.finishAsyncSequenceOfSelectUsersToAddViewModel(self, streamUUID: streamUUID)
            self.streamUUIDForModelFilteredBySearch = nil
        }
    }
    
    private var searchFieldPlacement: SearchFieldPlacement {
        // This is required under macOS. If we need to change this in the future for, e.g., iOS,
        // we should differentiate between the two platforms
        .navigationBarDrawer(displayMode: .always)
    }

    public var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .ignoresSafeArea(.all)
            InternalView(mode: mode,
                         model: model,
                         modelFilteredBySearch: modelFilteredBySearch,
                         streamUUIDForModelFilteredBySearch: streamUUIDForModelFilteredBySearch,
                         searchText: searchText,
                         identifiersOfSelectedUsers: $identifiersOfSelectedUsers,
                         dataSource: dataSource,
                         listOfUsersViewCellDataSource: listOfUsersViewCellDataSource,
                         avatarViewDataSource: avatarViewDataSource)
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
            .searchable(text: $searchText, placement: searchFieldPlacement, prompt: Text("Search"))
            .navigationTitle(String(localizedInThisBundle: "TITLE_ADD_GROUP_MEMBERS"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
        
    public struct InternalView: View {
        
        private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "SelectUsersToAddView.InternalView")

        let mode: Mode
        let model: SelectUsersToAddViewModel?
        let modelFilteredBySearch: SelectUsersToAddViewModel?
        let streamUUIDForModelFilteredBySearch: UUID?
        let searchText: String
        @Binding var identifiersOfSelectedUsers: [SelectUsersToAddViewModel.User.Identifier] // Must be a binding
        let dataSource: SelectUsersToAddViewDataSource
        let listOfUsersViewCellDataSource: ListOfUsersViewCellDataSource
        let avatarViewDataSource: ObvAvatarViewDataSource

        @State private var isInterfaceDisabled: Bool = false
        @State private var hudCategory: HUDView.Category? = nil

        @Environment(\.dismissSearch) private var dismissSearch

        private func userTappedButtonToAddSelectedUsersToTheGroup() {
            switch mode {
            case .edition(groupIdentifier: let groupIdentifier, actions: let actions, navigation: let navigation):
                guard !identifiersOfSelectedUsers.isEmpty else { assertionFailure(); return }
                dismissSearch()
                isInterfaceDisabled = true
                hudCategory = .progress
                Task {
                    do {
                        try await actions.userWantsToAddSelectedUsersToExistingGroup(self, groupIdentifier: groupIdentifier, withIdentifiers: identifiersOfSelectedUsers)
                        hudCategory = .checkmark
                    } catch {
                        Self.logger.fault("🧑‍🧑‍🧒‍🧒 Could not add users to existing group: \(error.localizedDescription, privacy: .public)")
                        hudCategory = .xmark
                    }
                    try? await Task.sleep(seconds: 1) // Give some time to the hudCategory
                    navigation.viewShouldBeDismissed(self)
                }
            case .creation(ownedCryptoId: let ownedCryptoId, creationSessionUUID: let creationSessionUUID, preselectedUserIdentifiers: _, actionsForCreation: let actionsForCreation, navigation: let navigation):
                actionsForCreation.userWantsToAddSelectedUsersToCreatingGroup(self, creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId, withIdentifiers: identifiersOfSelectedUsers)
                navigation.userDidFinishSelectingUsersToAddAndWantsToNavigateToNextScreen(self)
            }
        }
        
        
        private func performSearchWith(newSearchText: String?) {
            if let streamUUIDForModelFilteredBySearch {
                dataSource.filterAsyncSequenceOfUsersToAdd(self, streamUUID: streamUUIDForModelFilteredBySearch, searchText: newSearchText)
            }
        }
        
        
        private var disableButtonAllowingToAddUsers: Bool {
            switch mode {
            case .edition:
                return identifiersOfSelectedUsers.isEmpty
            case .creation:
                return false
            }
        }
        
        private let verticalPadding: CGFloat = 6
        
        @Environment(\.isSearching) private var isSearching
        
        private func titleOfAddButton(identifiersOfSelectedUsersCount: Int) -> String {
            switch mode {
            case .edition:
                String(localizedInThisBundle: "ADD_\(identifiersOfSelectedUsersCount)_USERS_TO_THE_GROUP_EDITION")
            case .creation:
                String(localizedInThisBundle: "ADD_\(identifiersOfSelectedUsersCount)_USERS_TO_THE_GROUP_CREATION")
            }
        }
        
        public var body: some View {
            if let model, let modelFilteredBySearch {
                
                ZStack {
                    
                    VStack(spacing: 0) {
                        if !isSearching {
                            HorizontalListOfUsersView(model: model,
                                                      dataSource: listOfUsersViewCellDataSource,
                                                      avatarViewDataSource: avatarViewDataSource,
                                                      identifiersOfSelectedUsers: $identifiersOfSelectedUsers)
                            .padding(.bottom, verticalPadding)
                        }
                        VerticalListOfUsersView(model: model,
                                                modelFilteredBySearch: modelFilteredBySearch,
                                                dataSource: listOfUsersViewCellDataSource,
                                                avatarViewDataSource: avatarViewDataSource,
                                                identifiersOfSelectedUsers: $identifiersOfSelectedUsers)
                        .padding(.bottom, verticalPadding)
                        Spacer(minLength: 0)
                        Button(action: userTappedButtonToAddSelectedUsersToTheGroup) {
                            HStack {
                                Spacer(minLength: 0)
                                Text(titleOfAddButton(identifiersOfSelectedUsersCount: identifiersOfSelectedUsers.count))
                                    .padding(.vertical, 8)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(disableButtonAllowingToAddUsers)
                        .padding(.horizontal)
                        .padding(.bottom, verticalPadding)
                    }
                    .disabled(isInterfaceDisabled)
                    
                    if let hudCategory = self.hudCategory {
                        HUDView(category: hudCategory)
                    }

                }
                .onChange(of: searchText) { newSearchText in performSearchWith(newSearchText: newSearchText) }

            } else {
                ProgressView()
            }
        }
    }
    
}


private struct HorizontalListOfUsersView: View {
    
    let model: SelectUsersToAddViewModel
    let dataSource: ListOfUsersViewCellDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    @Binding var identifiersOfSelectedUsers: [SelectUsersToAddViewModel.User.Identifier] // Must be a binding
    
    @Environment(\.sizeCategory) var sizeCategory

    /// Magic numbers that shall be replaced by a custom SwiftUI Layout (only available for iOS 16.0+).
    /// See https://developer.apple.com/documentation/swiftui/layout and
    /// https://developer.apple.com/wwdc22/10056?time=609
    private var height: CGFloat {
        switch sizeCategory {
        case .extraSmall:
            return 109
        case .small:
            return 113
        case .medium:
            return 115
        case .large:
            return 118
        case .extraLarge:
            return 123
        case .extraExtraLarge:
            return 128
        case .extraExtraExtraLarge:
            return 133
        case .accessibilityMedium:
            return 144
        case .accessibilityLarge:
            return 157
        case .accessibilityExtraLarge:
            return 174
        case .accessibilityExtraExtraLarge:
            return 190
        case .accessibilityExtraExtraExtraLarge:
            return 209
        @unknown default:
            return 118
        }
    }

    var body: some View {
        ObvCardView(padding: 0) {
            if identifiersOfSelectedUsers.isEmpty {
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        Text(model.textOnEmptySetOfUsers)
                            .padding(16)
                            .multilineTextAlignment(.center)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            //.opacity(model.selectedUsersOrdered.isEmpty ? 1.0 : 0.0)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack {
                        ForEach(identifiersOfSelectedUsers) { userIdentifier in
                            HorizontalListOfUsersViewCell(userIdentifier: userIdentifier,
                                                          dataSource: dataSource,
                                                          avatarViewDataSource: avatarViewDataSource,
                                                          identifiersOfSelectedUsers: $identifiersOfSelectedUsers)
                        }
                    }.padding(.horizontal)
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12.0))
        .padding(.horizontal)

    }
}


private struct VerticalListOfUsersView: View {
    
    let model: SelectUsersToAddViewModel
    let modelFilteredBySearch: SelectUsersToAddViewModel
    let dataSource: ListOfUsersViewCellDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    @Binding var identifiersOfSelectedUsers: [SelectUsersToAddViewModel.User.Identifier] // Must be a binding

    var body: some View {
        ObvCardView(padding: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                if model.allUserIdentifiers.isEmpty {
                    HStack {
                        Spacer(minLength: 0)
                        Text("ALL_YOUR_CONTACTS_ARE_ALREADY_PART_OF_THIS_GROUP")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding()
                        Spacer(minLength: 0)
                    }
                } else if modelFilteredBySearch.allUserIdentifiers.isEmpty {
                    HStack {
                        Spacer(minLength: 0)
                        Text("NO_CONTACT_FOUND_MATCHING_YOUR_SEARCH")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding()
                        Spacer(minLength: 0)
                    }
                } else {
                    LazyVStack {
                        ForEach(modelFilteredBySearch.allUserIdentifiers) { userIdentifier in
                            VStack {
                                VerticalListOfUsersViewCell(userIdentifier: userIdentifier,
                                                            dataSource: dataSource,
                                                            avatarViewDataSource: avatarViewDataSource,
                                                            identifiersOfSelectedUsers: $identifiersOfSelectedUsers)
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                                if userIdentifier != modelFilteredBySearch.allUserIdentifiers.last {
                                    Divider()
                                        .padding(.leading, 70)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }.padding(.horizontal)
    }
}



// MARK: - Data source for ListOfUsersViewCell (shared between the cells displayed in the horizontal and vertical lists of users)

public enum HorizontalOrVerticalListOfUsersViewCell {
    case horizontal(HorizontalListOfUsersViewCell)
    case vertical(VerticalListOfUsersViewCell)
}

@MainActor
public protocol ListOfUsersViewCellDataSource {
    func getAsyncSequenceOfSelectUsersToAddViewModelUser(_ view: HorizontalOrVerticalListOfUsersViewCell, withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel.User>)
    func finishAsyncSequenceOfSelectUsersToAddViewModelUser(_ view: HorizontalOrVerticalListOfUsersViewCell, withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier, streamUUID: UUID)
}


public struct HorizontalListOfUsersViewCell: View {
    
    let userIdentifier: SelectUsersToAddViewModel.User.Identifier
    let dataSource: ListOfUsersViewCellDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    @Binding var identifiersOfSelectedUsers: [SelectUsersToAddViewModel.User.Identifier] // Must be a binding

    @State private var user: SelectUsersToAddViewModel.User?
    @State private var streamUUID: UUID?

    @State private var profilePicture: (url: URL, image: UIImage?)?

    private var avatarSize: ObvDesignSystem.ObvAvatarSize {
        ObvDesignSystem.ObvAvatarSize.normal
    }

    private func onAppear() {
        Task {
            do {
                let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfSelectUsersToAddViewModelUser(.horizontal(self), withIdentifier: userIdentifier)
                if let previousStreamUUID = self.streamUUID {
                    dataSource.finishAsyncSequenceOfSelectUsersToAddViewModelUser(.horizontal(self), withIdentifier: userIdentifier, streamUUID: previousStreamUUID)
                }
                self.streamUUID = streamUUID
                for await model in stream {
                    
                    if self.user == nil {
                        self.user = model
                    } else {
                        withAnimation { self.user = model }
                    }

                    Task { await updateProfilePictureIfRequired(model: model, photoURL: model.customPhotoURL ?? model.identityDetails.photoURL) }
                    
                }
            } catch {
                assertionFailure()
            }
        }
    }
    
    private func onDisappear() {
        if let streamUUID = self.streamUUID {
            dataSource.finishAsyncSequenceOfSelectUsersToAddViewModelUser(.horizontal(self), withIdentifier: self.userIdentifier, streamUUID: streamUUID)
            self.streamUUID = nil
        }
    }

    
    private func updateProfilePictureIfRequired(model: SelectUsersToAddViewModel.User, photoURL: URL?) async {
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

    
    public var body: some View {
        InternalView(user: user,
                     identifiersOfSelectedUsers: $identifiersOfSelectedUsers,
                     profilePicture: profilePicture?.image,
                     avatarSize: avatarSize)
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
    }
    
    
    private struct InternalView: View {
        
        let user: SelectUsersToAddViewModel.User?
        @Binding var identifiersOfSelectedUsers: [SelectUsersToAddViewModel.User.Identifier] // Must be a binding
        let profilePicture: UIImage?
        let avatarSize: ObvDesignSystem.ObvAvatarSize

        /// When the user taps on a cell in the horizontal list, it means she wants to remove the user of this cell from the list of selected users.
        private func buttonAction() {
            guard let user else { assertionFailure(); return }
            withAnimation {
                identifiersOfSelectedUsers.removeAll(where: { $0 == user.identifier  })
            }
        }

        private func profilePictureViewModel(user: SelectUsersToAddViewModel.User) -> ProfilePictureView.Model {
            .init(content: profilePictureViewModelContent(user: user),
                  colors: user.circleColors,
                  circleDiameter: avatarSize.frameSize.width)
        }

        private func profilePictureViewModelContent(user: SelectUsersToAddViewModel.User) -> ProfilePictureView.Model.Content {
            .init(text: user.profilePictureInitial,
                  icon: .person,
                  profilePicture: profilePicture,
                  showGreenShield: user.isKeycloakManaged,
                  showRedShield: user.isRevokedAsCompromised)
        }

        var body: some View {
            if let user {
                VStack {
                    ProfilePictureView(model: profilePictureViewModel(user: user))
                        .overlay(alignment: .topTrailing) {
                            DeleteButton(buttonAction: buttonAction)
                                .offset(x: 16.0, y: -16.0)
                        }
                    VStack(alignment: .center) {
                        Text(user.identityDetails.coreDetails.firstName ?? " ")
                            .lineLimit(1)
                        Text(user.identityDetails.coreDetails.lastName ?? " ")
                            .lineLimit(1)
                    }
                    .font(.subheadline)
                }
            } else {
                VStack {
                    Spacer(minLength: 0)
                    ProgressView()
                    Spacer(minLength: 0)
                }.padding(.leading, 30)
            }
        }
    }
    
    
    private struct DeleteButton: View {

        let buttonAction: () -> Void

        var body: some View {
            Button(action: buttonAction) {
                ZStack {
                    Circle()
                        .foregroundStyle(Color(.secondarySystemGroupedBackground))
                        .frame(width: 20, height: 20)
                    Image(systemIcon: .xmarkCircleFill)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.white, Color(UIColor.systemGray))
                }
                .frame(width: 44, height: 44)
            }
        }
        
    }

}


public struct VerticalListOfUsersViewCell: View {
    
    let userIdentifier: SelectUsersToAddViewModel.User.Identifier
    let dataSource: ListOfUsersViewCellDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    @Binding var identifiersOfSelectedUsers: [SelectUsersToAddViewModel.User.Identifier] // Must be a binding

    @State private var user: SelectUsersToAddViewModel.User?
    @State private var streamUUID: UUID?

    @State private var profilePicture: (url: URL, image: UIImage?)?

    private var avatarSize: ObvDesignSystem.ObvAvatarSize {
        ObvDesignSystem.ObvAvatarSize.normal
    }

    private func onAppear() {
        Task {
            do {
                let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfSelectUsersToAddViewModelUser(.vertical(self), withIdentifier: userIdentifier)
                if let previousStreamUUID = self.streamUUID {
                    dataSource.finishAsyncSequenceOfSelectUsersToAddViewModelUser(.vertical(self), withIdentifier: userIdentifier, streamUUID: previousStreamUUID)
                }
                self.streamUUID = streamUUID
                for await model in stream {
                    
                    if self.user == nil {
                        self.user = model
                    } else {
                        withAnimation { self.user = model }
                    }
                    
                    Task { await updateProfilePictureIfRequired(model: model, photoURL: model.customPhotoURL ?? model.identityDetails.photoURL) }

                }
            } catch {
                assertionFailure()
            }
        }
    }
    
    private func onDisappear() {
        if let streamUUID = self.streamUUID {
            dataSource.finishAsyncSequenceOfSelectUsersToAddViewModelUser(.vertical(self), withIdentifier: self.userIdentifier, streamUUID: streamUUID)
            self.streamUUID = nil
        }
    }
    
    
    private func updateProfilePictureIfRequired(model: SelectUsersToAddViewModel.User, photoURL: URL?) async {
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

    
    public var body: some View {
        InternalView(userIdentifier: userIdentifier,
                     user: user,
                     identifiersOfSelectedUsers: $identifiersOfSelectedUsers,
                     profilePicture: profilePicture?.image,
                     avatarSize: avatarSize)
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
    }
    
    private struct InternalView: View {
        
        let userIdentifier: SelectUsersToAddViewModel.User.Identifier
        let user: SelectUsersToAddViewModel.User?
        @Binding var identifiersOfSelectedUsers: [SelectUsersToAddViewModel.User.Identifier] // Must be a binding
        let profilePicture: UIImage?
        let avatarSize: ObvDesignSystem.ObvAvatarSize

        /// When the user taps on an vertical cell, it means she wants to insert (or to remove) the user to (or from) the list of selected users.
        private func buttonAction() {
            guard let user else { assertionFailure(); return }
            let userIsSelected = identifiersOfSelectedUsers.contains(where: { $0 == user.identifier })
            if userIsSelected {
                withAnimation {
                    identifiersOfSelectedUsers.removeAll(where: { $0 == user.identifier  })
                }
            } else {
                withAnimation {
                    identifiersOfSelectedUsers.insert(user.identifier, at: 0)
                }
            }
        }

        private var isSelected: Bool {
            identifiersOfSelectedUsers.contains(self.userIdentifier)
        }

        private func profilePictureViewModel(user: SelectUsersToAddViewModel.User) -> ProfilePictureView.Model {
            .init(content: profilePictureViewModelContent(user: user),
                  colors: user.circleColors,
                  circleDiameter: avatarSize.frameSize.width)
        }

        private func profilePictureViewModelContent(user: SelectUsersToAddViewModel.User) -> ProfilePictureView.Model.Content {
            .init(text: user.profilePictureInitial,
                  icon: .person,
                  profilePicture: profilePicture,
                  showGreenShield: user.isKeycloakManaged,
                  showRedShield: user.isRevokedAsCompromised)
        }

        private func textViewModel(user: SelectUsersToAddViewModel.User) -> TextView.Model {
            let coreDetails = user.identityDetails.coreDetails
            if let customDisplayName = user.customDisplayName, !customDisplayName.isEmpty {
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

        var body: some View {
            if let user {
                HStack {
                    ProfilePictureView(model: profilePictureViewModel(user: user))
                    TextView(model: textViewModel(user: user))
                    Spacer()
                    Image(systemIcon: isSelected ? .personCropCircleFillBadgePlus : .circle)
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? .green : .secondary)
                        .animation(nil, value: isSelected)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    buttonAction()
                }
                .sensoryFeedbackOniOS17(.selection, trigger: isSelected)
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

extension DataSourceForPreviews: SelectUsersToAddViewDataSource {

    func filterAsyncSequenceOfUsersToAdd(_ view: SelectUsersToAddView.InternalView, streamUUID: UUID, searchText: String?) {
        // We don't simulate search
    }

    func getAsyncSequenceOfUsersToAddToExistingGroup(_ view: SelectUsersToAddView, groupIdentifier: ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>) {
        let model = PreviewsHelper.selectUsersToAddViewModel
        let stream = AsyncStream(SelectUsersToAddViewModel.self) { (continuation: AsyncStream<SelectUsersToAddViewModel>.Continuation) in
            continuation.yield(model)
        }
        return (UUID(), stream)
    }

    func getAsyncSequenceOfUsersToAddToCreatingGroup(_ view: SelectUsersToAddView, ownedCryptoId: ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>) {
        let model = PreviewsHelper.selectUsersToAddViewModel
        let stream = AsyncStream(SelectUsersToAddViewModel.self) { (continuation: AsyncStream<SelectUsersToAddViewModel>.Continuation) in
            continuation.yield(model)
        }
        return (UUID(), stream)
    }

    func finishAsyncSequenceOfSelectUsersToAddViewModel(_ view: SelectUsersToAddView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
        
}

extension DataSourceForPreviews: ListOfUsersViewCellDataSource {
    
    func getAsyncSequenceOfSelectUsersToAddViewModelUser(_ view: HorizontalOrVerticalListOfUsersViewCell, withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel.User>) {
        let model = PreviewsHelper.selectUsersToAddViewModelUser.first(where: { $0.identifier == identifier })!
        let stream = AsyncStream(SelectUsersToAddViewModel.User.self) { (continuation: AsyncStream<SelectUsersToAddViewModel.User>.Continuation) in
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfSelectUsersToAddViewModelUser(_ view: HorizontalOrVerticalListOfUsersViewCell, withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier, streamUUID: UUID) {
        // Nothing to finish in previews
    }

}

extension DataSourceForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        if let image = PreviewsHelper.profilePictureForURL[photoURL] {
            return image
        } else {
            return nil
        }
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
    func fetchAvatarForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        if let image = PreviewsHelper.profilePictureForURL[photoURL] {
            return image
        } else {
            return nil
        }
    }
    
    func fetchAvatarFromCacheForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
    
}

private final class ActionsForPreviews: SelectUsersToAddViewActionsForEdition {
        
    func userWantsToAddSelectedUsersToExistingGroup(_ view: SelectUsersToAddView.InternalView, groupIdentifier: ObvGroupIdentifier, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) async throws {
        // Nothing to simulate
    }
    
}

extension ActionsForPreviews: SelectUsersToAddViewActionsForCreation {
    
    func userWantsToAddSelectedUsersToCreatingGroup(_ view: SelectUsersToAddView.InternalView, creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) {
        // Nothing to simulate
    }

}

private final class NavigationForPreviews {}

extension NavigationForPreviews: SelectUsersToAddViewNavigationForEdition {
    func viewShouldBeDismissed(_ view: SelectUsersToAddView.InternalView) {}
}

extension NavigationForPreviews: SelectUsersToAddViewNavigationForCreation {
    func userDidFinishSelectingUsersToAddAndWantsToNavigateToNextScreen(_ view: SelectUsersToAddView.InternalView) {}
}


private let dataSourceForPreviews = DataSourceForPreviews()

@MainActor
private let actionsForPreviews = ActionsForPreviews()

@MainActor
private let navigationForPreviews = NavigationForPreviews()

#Preview("Creation") {
    NavigationStack {
        SelectUsersToAddView(mode: .creation(ownedCryptoId: PreviewsHelper.cryptoIds[0],
                                             creationSessionUUID: UUID(),
                                             preselectedUserIdentifiers: [],
                                             actionsForCreation: actionsForPreviews,
                                             navigation: navigationForPreviews),
                             dataSource: dataSourceForPreviews,
                             listOfUsersViewCellDataSource: dataSourceForPreviews,
                             avatarViewDataSource: dataSourceForPreviews)
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Edition") {
    SelectUsersToAddView(mode: .edition(groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
                                        actions: actionsForPreviews, navigation: navigationForPreviews),
                         dataSource: dataSourceForPreviews,
                         listOfUsersViewCellDataSource: dataSourceForPreviews,
                         avatarViewDataSource: dataSourceForPreviews)
}

#endif
