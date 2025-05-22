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
import ObvCircleAndTitlesView
import ObvDesignSystem


// MARK: - SelectUsersToAddViewModel

public struct SelectUsersToAddViewModel: Sendable {

    let textOnEmptySetOfUsers: String
    let allUserIdentifiers: [User.Identifier]
    
    public init(textOnEmptySetOfUsers: String, allUserIdentifiers: [User.Identifier]) {
        self.textOnEmptySetOfUsers = textOnEmptySetOfUsers
        self.allUserIdentifiers = allUserIdentifiers
    }

    public struct User: Sendable {
        
        let identifier: Identifier
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

        public enum Identifier: Identifiable, Sendable, CustomDebugStringConvertible {
            
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

protocol SelectUsersToAddViewDataSource: AnyObject, ListOfUsersViewDataSource {
    func getAsyncSequenceOfUsersToAddToCreatingGroup(ownedCryptoId: ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>)
    func getAsyncSequenceOfUsersToAddToExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>)
    func filterAsyncSequenceOfUsersToAdd(streamUUID: UUID, searchText: String?)
    func finishAsyncSequenceOfSelectUsersToAddViewModel(streamUUID: UUID)
}


// MARK: - Actions

@MainActor
protocol SelectUsersToAddViewActionsProtocol: AnyObject {
    func userWantsToAddSelectedUsersToCreatingGroup(creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier])
    func userWantsToAddSelectedUsersToExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) async throws
    func viewShouldBeDismissed() // Only called during a group edition
}

// MARK: - Main view: SelectUsersToAddView

struct SelectUsersToAddView: View {
    
    let mode: Mode
    let dataSource: SelectUsersToAddViewDataSource
    let actions: SelectUsersToAddViewActionsProtocol
    
    enum Mode {
        case edition(groupIdentifier: ObvTypes.ObvGroupV2Identifier)
        case creation(ownedCryptoId: ObvCryptoId, creationSessionUUID: UUID, preselectedUserIdentifiers: [SelectUsersToAddViewModel.User.Identifier])
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
        case .creation(ownedCryptoId: _, creationSessionUUID: _, preselectedUserIdentifiers: let preselectedUserIdentifiers):
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
                case .edition(groupIdentifier: let groupIdentifier):
                    (streamUUID, stream) = try dataSource.getAsyncSequenceOfUsersToAddToExistingGroup(groupIdentifier: groupIdentifier)
                case .creation(ownedCryptoId: let ownedCryptoId, creationSessionUUID: _, preselectedUserIdentifiers: _):
                    (streamUUID, stream) = try dataSource.getAsyncSequenceOfUsersToAddToCreatingGroup(ownedCryptoId: ownedCryptoId)
                }
                self.streamUUIDForModel = streamUUID
                for await model in stream {
                    withAnimation {
                        self.model = model
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
                case .edition(groupIdentifier: let groupIdentifier):
                    (streamUUID, stream) = try dataSource.getAsyncSequenceOfUsersToAddToExistingGroup(groupIdentifier: groupIdentifier)
                case .creation(ownedCryptoId: let ownedCryptoId, creationSessionUUID: _, preselectedUserIdentifiers: _):
                    (streamUUID, stream) = try dataSource.getAsyncSequenceOfUsersToAddToCreatingGroup(ownedCryptoId: ownedCryptoId)
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
            dataSource.finishAsyncSequenceOfSelectUsersToAddViewModel(streamUUID: streamUUID)
            self.streamUUIDForModel = nil
        }
        if let streamUUID = self.streamUUIDForModelFilteredBySearch {
            dataSource.finishAsyncSequenceOfSelectUsersToAddViewModel(streamUUID: streamUUID)
            self.streamUUIDForModelFilteredBySearch = nil
        }
    }
    
    private var searchFieldPlacement: SearchFieldPlacement {
        // This is required under macOS. If we need to change this in the future for, e.g., iOS,
        // we should differentiate between the two platforms
        .navigationBarDrawer(displayMode: .always)
    }

    var body: some View {
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
                         actions: actions)
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
            .searchable(text: $searchText, placement: searchFieldPlacement, prompt: Text("Search"))
        }
    }
        
    private struct InternalView: View {
        
        let mode: Mode
        let model: SelectUsersToAddViewModel?
        let modelFilteredBySearch: SelectUsersToAddViewModel?
        let streamUUIDForModelFilteredBySearch: UUID?
        let searchText: String
        @Binding var identifiersOfSelectedUsers: [SelectUsersToAddViewModel.User.Identifier] // Must be a binding
        let dataSource: SelectUsersToAddViewDataSource
        let actions: SelectUsersToAddViewActionsProtocol

        @State private var isInterfaceDisabled: Bool = false
        @State private var hudCategory: HUDView.Category? = nil

        @Environment(\.dismissSearch) private var dismissSearch

        private func userTappedButtonToAddSelectedUsersToTheGroup() {
            switch mode {
            case .edition(groupIdentifier: let groupIdentifier):
                guard !identifiersOfSelectedUsers.isEmpty else { assertionFailure(); return }
                dismissSearch()
                isInterfaceDisabled = true
                hudCategory = .progress
                Task {
                    do {
                        try await actions.userWantsToAddSelectedUsersToExistingGroup(groupIdentifier: groupIdentifier, withIdentifiers: identifiersOfSelectedUsers)
                        hudCategory = .checkmark
                    } catch {
                        hudCategory = .xmark
                    }
                    try? await Task.sleep(seconds: 1) // Give some time to the hudCategory
                    actions.viewShouldBeDismissed()
                }
            case .creation(ownedCryptoId: let ownedCryptoId, creationSessionUUID: let creationSessionUUID, preselectedUserIdentifiers: _):
                actions.userWantsToAddSelectedUsersToCreatingGroup(creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId, withIdentifiers: identifiersOfSelectedUsers)
            }
        }
        
        
        private func performSearchWith(newSearchText: String?) {
            if let streamUUIDForModelFilteredBySearch {
                dataSource.filterAsyncSequenceOfUsersToAdd(streamUUID: streamUUIDForModelFilteredBySearch, searchText: newSearchText)
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
        
        var body: some View {
            if let model, let modelFilteredBySearch {
                
                ZStack {
                    
                    VStack(spacing: 0) {
                        if !isSearching {
                            HorizontalListOfUsersView(model: model,
                                                      dataSource: dataSource,
                                                      identifiersOfSelectedUsers: $identifiersOfSelectedUsers)
                            .padding(.bottom, verticalPadding)
                        }
                        VerticalListOfUsersView(model: model,
                                                modelFilteredBySearch: modelFilteredBySearch,
                                                dataSource: dataSource,
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


// MARK: - Data source share between the horizontal and vertical lists of users

protocol ListOfUsersViewDataSource: ListOfUsersViewCellDataSource {
    
}

private struct HorizontalListOfUsersView: View {
    
    let model: SelectUsersToAddViewModel
    let dataSource: ListOfUsersViewDataSource
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
    let dataSource: ListOfUsersViewDataSource
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

@MainActor
protocol ListOfUsersViewCellDataSource: AnyObject {
    func getAsyncSequenceOfSelectUsersToAddViewModelUser(withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel.User>)
    func finishAsyncSequenceOfSelectUsersToAddViewModelUser(withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier, streamUUID: UUID)
    func fetchAvatarImage(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
}


private struct HorizontalListOfUsersViewCell: View {
    
    let userIdentifier: SelectUsersToAddViewModel.User.Identifier
    let dataSource: ListOfUsersViewCellDataSource
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
                let (streamUUID, stream) = try dataSource.getAsyncSequenceOfSelectUsersToAddViewModelUser(withIdentifier: userIdentifier)
                if let previousStreamUUID = self.streamUUID {
                    dataSource.finishAsyncSequenceOfSelectUsersToAddViewModelUser(withIdentifier: userIdentifier, streamUUID: previousStreamUUID)
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
            dataSource.finishAsyncSequenceOfSelectUsersToAddViewModelUser(withIdentifier: self.userIdentifier, streamUUID: streamUUID)
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
            let image = try await dataSource.fetchAvatarImage(photoURL: photoURL, avatarSize: avatarSize)
            guard self.profilePicture?.url == photoURL else { return } // The fetched photo is outdated
            withAnimation {
                self.profilePicture = (photoURL, image)
            }
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    
    var body: some View {
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


private struct VerticalListOfUsersViewCell: View {
    
    let userIdentifier: SelectUsersToAddViewModel.User.Identifier
    let dataSource: ListOfUsersViewCellDataSource
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
                let (streamUUID, stream) = try dataSource.getAsyncSequenceOfSelectUsersToAddViewModelUser(withIdentifier: userIdentifier)
                if let previousStreamUUID = self.streamUUID {
                    dataSource.finishAsyncSequenceOfSelectUsersToAddViewModelUser(withIdentifier: userIdentifier, streamUUID: previousStreamUUID)
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
            dataSource.finishAsyncSequenceOfSelectUsersToAddViewModelUser(withIdentifier: self.userIdentifier, streamUUID: streamUUID)
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
            let image = try await dataSource.fetchAvatarImage(photoURL: photoURL, avatarSize: avatarSize)
            guard self.profilePicture?.url == photoURL else { return } // The fetched photo is outdated
            withAnimation {
                self.profilePicture = (photoURL, image)
            }
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    
    var body: some View {
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
                Button(action: buttonAction) {
                    HStack {
                        ProfilePictureView(model: profilePictureViewModel(user: user))
                        TextView(model: textViewModel(user: user))
                        Spacer()
                        Image(systemIcon: isSelected ? .personCropCircleFillBadgePlus : .circle)
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? .green : .secondary)
                            .animation(nil, value: isSelected)
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

private final class DataSourceForPreviews: SelectUsersToAddViewDataSource {

    func filterAsyncSequenceOfUsersToAdd(streamUUID: UUID, searchText: String?) {
        // We don't simulate search
    }
    
    func getAsyncSequenceOfUsersToAddToExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>) {
        let model = PreviewsHelper.selectUsersToAddViewModel
        let stream = AsyncStream(SelectUsersToAddViewModel.self) { (continuation: AsyncStream<SelectUsersToAddViewModel>.Continuation) in
            continuation.yield(model)
        }
        return (UUID(), stream)
    }

    func getAsyncSequenceOfUsersToAddToCreatingGroup(ownedCryptoId: ObvTypes.ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>) {
        let model = PreviewsHelper.selectUsersToAddViewModel
        let stream = AsyncStream(SelectUsersToAddViewModel.self) { (continuation: AsyncStream<SelectUsersToAddViewModel>.Continuation) in
            continuation.yield(model)
        }
        return (UUID(), stream)
    }

    func finishAsyncSequenceOfSelectUsersToAddViewModel(streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
    func getAsyncSequenceOfSelectUsersToAddViewModelUser(withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel.User>) {
        let model = PreviewsHelper.selectUsersToAddViewModelUser.first(where: { $0.identifier == identifier })!
        let stream = AsyncStream(SelectUsersToAddViewModel.User.self) { (continuation: AsyncStream<SelectUsersToAddViewModel.User>.Continuation) in
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfSelectUsersToAddViewModelUser(withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
    func fetchAvatarImage(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        return PreviewsHelper.profilePictureForURL[photoURL]
    }

}


private final class ActionsForPreviews: SelectUsersToAddViewActionsProtocol {
    
    func userWantsToAddSelectedUsersToCreatingGroup(creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) {
        // Nothing to simulate
    }
    
    func userWantsToAddSelectedUsersToExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) async throws {
        // Nothing to simulate
    }
    
    func viewShouldBeDismissed() {
        // Nothing to simulate
    }
}


private let dataSourceForPreviews = DataSourceForPreviews()

@MainActor
private let actionsForPreviews = ActionsForPreviews()

@available(iOS 16.0, *)
#Preview("Creation") {
    NavigationStack {
        SelectUsersToAddView(mode: .creation(ownedCryptoId: PreviewsHelper.cryptoIds[0], creationSessionUUID: UUID(), preselectedUserIdentifiers: []), dataSource: dataSourceForPreviews, actions: actionsForPreviews)
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Edition") {
    SelectUsersToAddView(mode: .edition(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0]), dataSource: dataSourceForPreviews, actions: actionsForPreviews)
}

#endif
