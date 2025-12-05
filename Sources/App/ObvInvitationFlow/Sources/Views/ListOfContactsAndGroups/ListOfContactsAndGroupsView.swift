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
import ObvAppCoreConstants
import OSLog
import ObvDesignSystem
import ObvTypes
import ObvAppTypes
import ObvCells

// MARK: - InvitationContactsListView


public enum InvitationContactsListNavigationType {
    case none
    case showInvitation(obvContactIdentifier: ObvContactIdentifier, keycloakUserDetails: ObvKeycloakUserDetails?)
}


public struct InvitationFlowGroupListViewModel: Sendable, Equatable {
    let groupIdentifiers: [ObvCells.ObvGroupCellViewModel.GroupIdentifier]
    
    public init(groupIdentifiers: [ObvCells.ObvGroupCellViewModel.GroupIdentifier]) {
        self.groupIdentifiers = groupIdentifiers
    }
    
    var isEmpty: Bool {
        groupIdentifiers.isEmpty
    }

    public enum SearchStatus {
        case notPerformingSearch
        case performingSearch(searchText: String?)
    }

}


/// Model used for both the contacts tab and the keycloak tab
public struct InvitationContactsListViewModel: Sendable, Equatable {
    let contactIdentifiers: [String: [ContactIdentifier]]
    let numberOfMissingResults: Int // Always 0 for the contacts tab
    
    public init(contactIdentifiers: [String: [ContactIdentifier]], numberOfMissingResults: Int) {
        self.contactIdentifiers = contactIdentifiers
        self.numberOfMissingResults = numberOfMissingResults
    }
    
    public enum ContactIdentifier: Sendable, Equatable, Hashable {
        case obvContactIdentifier(ObvContactIdentifier)
        case keycloakContactIdentifier(ObvKeycloakUserDetails, contactsSortOrder: ContactsSortOrder)
        case persistedObvContactIdentity(NSManagedObjectID)
        
        public var objectID: NSManagedObjectID? {
            switch self {
            case .obvContactIdentifier, .keycloakContactIdentifier: return nil
            case .persistedObvContactIdentity(let nSManagedObjectID): return nSManagedObjectID
            }
        }
    }
    
    var isEmpty: Bool {
        contactIdentifiers.isEmpty
    }
    
    public enum SearchStatus: Equatable {
        case notPerformingSearch
        case performingSearch(searchText: String?)
    }
}


public enum InvitationKeycloakContactsListViewModel: Sendable {
    case success(InvitationContactsListViewModel)
    case searchError(ObvKeycloakSearchError)
    
    public enum ObvError: Error, Equatable {
        case permissionDenied // Requires authentication
        case otherError(localizedDescription: String)
    }
}


@MainActor
public protocol ListOfContactsAndGroupsViewActions {
    
    func userWantsToCreateGroup(_ view: ListOfContactsAndGroupsView.InvitationsContactsListContentView, ownedCryptoId: ObvCryptoId)
    func persistedObvContactIdentityTapped(_ view: ListOfContactsAndGroupsView.ListOfContactsCellForKeyView, currentCryptoId: ObvCryptoId, with objectID: NSManagedObjectID) async -> InvitationContactsListNavigationType
    func keycloakContactIdentifierTapped(_ view: ListOfContactsAndGroupsView.ListOfContactsCellForKeyView, currentCryptoId: ObvCryptoId, with keycloakUserDetails: ObvKeycloakUserDetails) async -> InvitationContactsListNavigationType
    func userPastedAnOlvidURL(_ view: ListOfContactsAndGroupsView, scannedOlvidURL: OlvidURL) -> (remoteURLIdentity: ObvURLIdentity, mutualScanURLToShow: ObvMutualScanUrl)?
    func userWantsToPerformKeycloakAuthentication(_ view: ListOfContactsAndGroupsView.ListOfDirectoryContactsView, ownedCryptoId: ObvCryptoId) async throws(ListOfContactsAndGroupsView.ListOfDirectoryContactsView.KeycloakError)
    func userWantsToDismissInvitationFlow(_ view: ListOfContactsAndGroupsView)
    
}


@MainActor
public protocol ListOfContactsAndGroupsViewDataSource: InvitationContactsListCellViewDataSource {
    
    func getAsyncStreamOfInvitationContactsListViewModel(_ view: ListOfContactsAndGroupsView.ListOfLocalContactsView, ownedCryptoId: ObvCryptoId, initialSearchStatus: InvitationContactsListViewModel.SearchStatus) async throws -> (streamUUID: UUID, stream: AsyncStream<InvitationContactsListViewModel>)
    func filterAsyncSequenceOfInvitationContactsListViewModel(_ view: ListOfContactsAndGroupsView.ListOfLocalContactsView, streamUUID: UUID, searchStatus: InvitationContactsListViewModel.SearchStatus)
    func finishAsyncStreamOfInvitationContactsListViewModel(_ view: ListOfContactsAndGroupsView.ListOfLocalContactsView, streamUUID: UUID)
    
    func getAsyncStreamOfInvitationKeycloakContactsListViewModel(_ view: ListOfContactsAndGroupsView.ListOfDirectoryContactsView, ownedCryptoId: ObvCryptoId, initialSearchStatus: InvitationContactsListViewModel.SearchStatus) throws -> (streamUUID: UUID, stream: AsyncStream<InvitationKeycloakContactsListViewModel>)
    func filterAsyncStreamOfInvitationKeycloakContactsListViewModel(_ view: ListOfContactsAndGroupsView.ListOfDirectoryContactsView, streamUUID: UUID, searchStatus: InvitationContactsListViewModel.SearchStatus)
    func finishAsyncStreamOfInvitationKeycloakContactsListViewModel(_ view: ListOfContactsAndGroupsView.ListOfDirectoryContactsView, streamUUID: UUID)

    func getAsyncStreamOfInvitationFlowGroupListViewModel(_ view: ListOfContactsAndGroupsView.ListOfGroupsView, ownedCryptoId: ObvCryptoId, initialSearchStatus: InvitationFlowGroupListViewModel.SearchStatus) async throws -> (streamUUID: UUID, stream: AsyncStream<InvitationFlowGroupListViewModel>)
    func filterAsyncStreamOfInvitationFlowGroupListViewModel(_ view: ListOfContactsAndGroupsView.ListOfGroupsView, streamUUID: UUID, searchStatus: InvitationFlowGroupListViewModel.SearchStatus)
    func finishAsyncStreamOfInvitationFlowGroupListViewModel(_ view: ListOfContactsAndGroupsView.ListOfGroupsView, streamUUID: UUID)
    
}

@MainActor
public protocol ListOfContactsAndGroupsViewNavigation: ObvGroupCellViewNavigation {
    
}

public struct ListOfContactsAndGroupsView: View {
    
    let ownedURLIdentity: ObvURLIdentity
    let ownedIdentityIsManagedByKeycloak: Bool
    let router: InvitationFlowRouter
    let navigation: ListOfContactsAndGroupsViewNavigation
        
    @State private var searchText: String = ""
    
    @State private var pastedOlvidURL: OlvidURL?
    
    @State private var showAlertPastedInvitationLinkIsOwnInvitationLink: Bool = false
    
    private func onChangeOfScannedOlvidURL(_ newScannedOlvidURL: OlvidURL?) {
        pastedOlvidURL = nil // Reset, so that a new paste of the same URL works
        guard let newScannedOlvidURL else { return }
        guard let (remoteURLIdentity, mutualScanURLToShow) = router.listOfContactsAndGroupsViewActions.userPastedAnOlvidURL(self, scannedOlvidURL: newScannedOlvidURL) else {
            // The scanned OlvidURL is not an invitation (e.g., it could be a Keycloak configuration).
            // Since this scanner is part of the invitation flow, it will be dismissed and replaced
            // by the appropriate flow for the scanned OlvidURL type.
            return
        }
        // Make sure the "remote" identity is distinct from the owned identity
        guard remoteURLIdentity.cryptoId != mutualScanURLToShow.cryptoId else {
            showAlertPastedInvitationLinkIsOwnInvitationLink = true
            return
        }
        // The scanned OlvidURL was an invitation. We received a mutual scan URL in response.
        // We navigate to the ExternalInvitationHandlerView (as we would have done if the invitation
        // was scanned from outside of the app)
        self.router.pushRoute(.externalInvitation(mutualScanURLToShow: mutualScanURLToShow, remoteURLIdentity: remoteURLIdentity))
    }

    private var closeButtonPlacement: ToolbarItemPlacement {
        if #available(iOS 26.0, *) {
            return .topBarTrailing
        } else {
            return .topBarLeading
        }
    }
    
    private func userWantsToDismissInvitationFlow() {
        router.listOfContactsAndGroupsViewActions.userWantsToDismissInvitationFlow(self)
    }
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ListOfContactsAndGroupsView")

    @State private var searchIsPresented: Bool = false
    
    private func onEscapeKeyPressed() {
        Self.logger.debug("Escape key pressed")
        if searchIsPresented {
            searchIsPresented = false
            searchText = ""
        } else {
            userWantsToDismissInvitationFlow()
        }
    }
    
    private func onCommandPlusFKeyPressed() {
        Self.logger.debug("Cmd+F key pressed")
        searchIsPresented = true
    }
    
    public var body: some View {
        InvitationsContactsListContentView(ownedURLIdentity: ownedURLIdentity,
                                           ownedIdentityIsManagedByKeycloak: ownedIdentityIsManagedByKeycloak,
                                           router: router,
                                           dataSource: router.invitationContactsListViewDataSource,
                                           avatarDataSource: router.avatarViewDataSource,
                                           groupCellViewDataSource: router.groupCellViewDataSource,
                                           actions: router.listOfContactsAndGroupsViewActions,
                                           navigation: navigation,
                                           searchText: $searchText)
        .searchableOniOS17(text: $searchText, isPresented: $searchIsPresented, placement: .automatic, prompt: Text("SEARCH_CONTACT_OR_GROUP"))
        .background(Button(action: onCommandPlusFKeyPressed, label: { Text(verbatim: " ").opacity(0) }).keyboardShortcut("F", modifiers: .command).hidden()) // Trick to activate the search field With Cmd+F
        .background(Button(action: onEscapeKeyPressed, label: { Text(verbatim: " ").opacity(0) }).keyboardShortcut(.cancelAction).hidden()) // Trick to deactivate the search field with escape, or to quit the flow
        .navigationTitle(Text("CONTACT_VIEW_TITLE"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ScanButtonView(ownedURLIdentity: self.ownedURLIdentity, router: self.router)
                CopyPasteMenu(ownedCryptoId: ownedURLIdentity.cryptoId,
                              actions: router.copyPasteMenuActions,
                              pastedOlvidURL: $pastedOlvidURL)
            }
            ToolbarItem(placement: closeButtonPlacement) {
                DismissButton(action: userWantsToDismissInvitationFlow)
            }
        }
        .onChange(of: pastedOlvidURL, perform: onChangeOfScannedOlvidURL)
        .alert(String(localizedInThisBundle: "CANNOT_INVITE_YOURSELF_TITLE"), isPresented: $showAlertPastedInvitationLinkIsOwnInvitationLink, actions: {}) {
            Text("CANNOT_INVITE_YOURSELF_MESSAGE")
        }
    }
}


// MARK: - Internal view

private struct DismissButton: View {
    
    let action: () -> Void
    
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: .close, action: action)
        } else {
            Button(action: action) {
                Image(systemIcon: .xmarkCircle)
            }
        }
    }
    
}



// MARK: - Internal view

private struct ScanButtonView: View {
    
    let ownedURLIdentity: ObvURLIdentity
    let router: InvitationFlowRouter
    
    var currentOwnedCryptoId: ObvCryptoId {
        ownedURLIdentity.cryptoId
    }
    
    var body: some View {
        Button {
            router.presentFullScreen(.scanner(currentOwnedCryptoId: self.currentOwnedCryptoId, scannerMode: .singleScan(ownedURLIdentity: ownedURLIdentity)))
        } label: {
            Image(systemIcon: .qrcodeViewfinder)
        }
    }
}


// MARK: - Internal view

extension ListOfContactsAndGroupsView {
    
    public struct InvitationsContactsListContentView: View {
        
        let ownedURLIdentity: ObvURLIdentity
        let ownedIdentityIsManagedByKeycloak: Bool
        let router: InvitationFlowRouter
        let dataSource: ListOfContactsAndGroupsViewDataSource
        let avatarDataSource: ObvAvatarViewDataSource
        let groupCellViewDataSource: ObvGroupCellViewDataSource
        let actions: ListOfContactsAndGroupsViewActions
        let navigation: any ObvGroupCellViewNavigation
        @Binding var searchText: String
        
        @State private var isSearchInProgress = false
        @State private var filterType: ContactFilterType = .contacts
        @State private var streamUUIDForAllFilteredBySearchText: UUID?
        
        @Environment(\.isSearching) var isSearching
        
        private var currentOwnedCryptoId: ObvCryptoId {
            ownedURLIdentity.cryptoId
        }
        
        fileprivate enum ContactFilterType: Int, Identifiable, CaseIterable {
            case contacts
            case groups
            case directory
            
            var id: Int { self.rawValue }
            
            var title: Text {
                switch self {
                case .contacts:
                    Text("CONTACT_VIEW_PICKER_CONTACTS")
                case .groups:
                    Text("CONTACT_VIEW_PICKER_GROUPS")
                case .directory:
                    Text("CONTACT_VIEW_PICKER_DIRECTORY")
                }
            }
        }
        
        private func addContactRemotelyAction() {
            router.presentFullScreen(.sharingProfile(currentOwnedCryptoId: self.currentOwnedCryptoId))
        }
        
        private func addContactInPersonAction() {
            router.presentFullScreen(.scanner(currentOwnedCryptoId: self.currentOwnedCryptoId, scannerMode: .mutualScan(ownedURLIdentityToShow: ownedURLIdentity)))
        }
        
        private func addNewGroupAction() {
            self.actions.userWantsToCreateGroup(self, ownedCryptoId: self.currentOwnedCryptoId)
        }
        
        private var availableFilterTypes: [ContactFilterType] {
            if ownedIdentityIsManagedByKeycloak {
                return ContactFilterType.allCases
            } else {
                return ContactFilterType.allCases.filter { $0 != .directory }
            }
        }
        
        public var body: some View {
            List {
                
                Section {
                    
                    VStack {
                        
                        // Add contact / Add group buttons
                        
                        if !isSearching {
                            NewContactButton(addContactInPersonAction: addContactInPersonAction, addContactRemotelyAction: addContactRemotelyAction)
                                .padding([.horizontal])
                                .padding(.top, 4)
                            NewGroupButton(addNewGroupAction: addNewGroupAction)
                                .padding([.horizontal])
                                .padding(.top, 4)
                        }
                        
                        // Picker
                        
                        Picker("", selection: $filterType) {
                            ForEach(availableFilterTypes) { filter in
                                filter.title.tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding([.top, .horizontal])
                        .background(Button(action: { if availableFilterTypes.contains(.contacts) { filterType = .contacts } }, label: { EmptyView() }).keyboardShortcut("1", modifiers: .command).hidden()) // Trick to activate the contacts tab With Cmd+1
                        .background(Button(action: { if availableFilterTypes.contains(.groups) { filterType = .groups } }, label: { EmptyView() }).keyboardShortcut("2", modifiers: .command).hidden()) // Trick to activate the contacts tab With Cmd+1
                        .background(Button(action: { if availableFilterTypes.contains(.directory) { filterType = .directory } }, label: { EmptyView() }).keyboardShortcut("3", modifiers: .command).hidden()) // Trick to activate the contacts tab With Cmd+1

                    }
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .padding(.bottom)
                    
                }
                
                switch filterType {
                    
                case .contacts:
                    
                    ListOfLocalContactsView(
                        currentOwnedCryptoId: currentOwnedCryptoId,
                        dataSource: dataSource,
                        avatarDataSource: avatarDataSource,
                        actions: actions,
                        router: router,
                        searchText: $searchText,
                        isSearchInProgress: $isSearchInProgress,
                        addContactInPersonAction: addContactInPersonAction,
                        addContactRemotelyAction: addContactRemotelyAction)
                    
                case .directory:
                    
                    ListOfDirectoryContactsView(
                        currentOwnedCryptoId: currentOwnedCryptoId,
                        dataSource: dataSource,
                        avatarDataSource: avatarDataSource,
                        actions: actions,
                        router: router,
                        searchText: $searchText,
                        isSearchInProgress: $isSearchInProgress)
                    
                case .groups:
                    
                    ListOfGroupsView(
                        currentOwnedCryptoId: currentOwnedCryptoId,
                        dataSource: dataSource,
                        groupCellViewDataSource: groupCellViewDataSource,
                        avatarDataSource: avatarDataSource,
                        navigation: navigation,
                        searchText: $searchText,
                        isSearchInProgress: $isSearchInProgress)
                    
                }
                
            }
            .listStyle(.plain)
            .listRowSpacing(0)
            .listSectionSpacingOniOS17(.custom(0))
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
        }
        
    }
    
}


// MARK: - Internal view

extension ListOfContactsAndGroupsView {
    
    /// One of the 3 tab views. This view shows the list of groups.
    public struct ListOfGroupsView: View {
        
        let currentOwnedCryptoId: ObvCryptoId
        let dataSource: ListOfContactsAndGroupsViewDataSource
        let groupCellViewDataSource: ObvGroupCellViewDataSource
        let avatarDataSource: ObvAvatarViewDataSource
        let navigation: any ObvGroupCellViewNavigation
        @Binding var searchText: String
        @Binding var isSearchInProgress: Bool
        
        @Environment(\.isSearching) var environmentIsSearching
        
        @State private var streamedViewModel: InvitationFlowGroupListViewModel?
        @State private var streamUUIDForViewModel: UUID? // Required as a state to implement search
        
        private func onTask() async {
            do {
                let searchStatus: InvitationFlowGroupListViewModel.SearchStatus
                if isSearchInProgress {
                    searchStatus = .performingSearch(searchText: searchText)
                } else {
                    searchStatus = .notPerformingSearch
                }
                let (streamUUID, stream) = try await dataSource.getAsyncStreamOfInvitationFlowGroupListViewModel(self, ownedCryptoId: currentOwnedCryptoId, initialSearchStatus: searchStatus)
                self.streamUUIDForViewModel = streamUUID
                for await model in stream {
                    withAnimation { self.streamedViewModel = model }
                }
                dataSource.finishAsyncStreamOfInvitationFlowGroupListViewModel(self, streamUUID: streamUUID)
                self.streamUUIDForViewModel = nil
            } catch {
                assertionFailure()
            }
        }
        
        private func performSearchWith(newSearchText: String?) {
            guard let streamUUIDForViewModel else { return }
            dataSource.filterAsyncStreamOfInvitationFlowGroupListViewModel(self, streamUUID: streamUUIDForViewModel, searchStatus: .performingSearch(searchText: newSearchText))
        }
        
        private func stopSearch() {
            guard let streamUUIDForViewModel else { return }
            dataSource.filterAsyncStreamOfInvitationFlowGroupListViewModel(self, streamUUID: streamUUIDForViewModel, searchStatus: .notPerformingSearch)
        }
        
        private func setIsSearchInProgress(newValue: Bool) {
            withAnimation { isSearchInProgress = newValue }
            if newValue {
                performSearchWith(newSearchText: searchText)
            } else {
                stopSearch()
            }
        }
        
        public var body: some View {
            Group {
                if let streamedViewModel {
                    if streamedViewModel.isEmpty {
                        Group {
                            if isSearchInProgress {
                                ObvContentUnavailableView.search
                            } else {
                                ObvContentUnavailableView(title: String(localizedInThisBundle: "YOU_DO_NOT_HAVE_ANY_GROUPS_YET_TITLE"),
                                                          systemIcon: .person3,
                                                          description: String(localizedInThisBundle: "YOU_DO_NOT_HAVE_ANY_GROUPS_YET_DESCRIPTION"))
                            }
                        }
                        .padding(.top)
                    } else {
                        ForEach(streamedViewModel.groupIdentifiers) { groupIdentifier in
                            ObvGroupCellView(
                                groupIdentifier: groupIdentifier,
                                expectedNavigationOnTap: .groupDiscussion,
                                dataSource: groupCellViewDataSource,
                                avatarViewDataSource: avatarDataSource,
                                navigation: navigation,
                                highlightedGroupIdentifier: .constant(nil))
                        }
                    }
                } else {
                    ProgressViewForList()
                        .padding(.top)
                        .listRowSeparator(.hidden)
                }
            }
            .listRowInsets(EdgeInsets(top: 12.0, leading: 16.0, bottom: 12.0, trailing: 16.0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .task(onTask)
            .onChange(of: searchText) { newSearchText in performSearchWith(newSearchText: newSearchText) }
            .onChange(of: environmentIsSearching) { newValue in setIsSearchInProgress(newValue: newValue) }
        }
        
    }
    
}

// MARK: - Internal view

extension ListOfContactsAndGroupsView {
    
    /// One of the 3 tab views. This view shows the list of contacts from a Keycloak directory.
    public struct ListOfDirectoryContactsView: View {
        
        let currentOwnedCryptoId: ObvCryptoId
        let dataSource: ListOfContactsAndGroupsViewDataSource
        let avatarDataSource: ObvAvatarViewDataSource
        let actions: ListOfContactsAndGroupsViewActions
        let router: InvitationFlowRouter
        @Binding var searchText: String
        @Binding var isSearchInProgress: Bool
        
        @Environment(\.isSearching) var environmentIsSearching
        
        @State private var streamedViewModel: InvitationKeycloakContactsListViewModel?
        @State private var streamUUIDForViewModel: UUID? // Required as a state to implement search
        
        private let listOfFirstLetters: [String] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ#").map(String.init)
        
        private func onTask() async {
            do {
                let searchStatus: InvitationContactsListViewModel.SearchStatus
                if isSearchInProgress {
                    searchStatus = .performingSearch(searchText: searchText)
                } else {
                    searchStatus = .notPerformingSearch
                }
                let (streamUUID, stream) = try dataSource.getAsyncStreamOfInvitationKeycloakContactsListViewModel(self, ownedCryptoId: currentOwnedCryptoId, initialSearchStatus: searchStatus)
                self.streamUUIDForViewModel = streamUUID
                for await model in stream {
                    withAnimation { self.streamedViewModel = model }
                }
                dataSource.finishAsyncStreamOfInvitationKeycloakContactsListViewModel(self, streamUUID: streamUUID)
                self.streamUUIDForViewModel = nil
            } catch {
                assertionFailure()
            }
        }
        
        private func performSearchWith(newSearchText: String?) {
            guard let streamUUIDForViewModel else { return }
            dataSource.filterAsyncStreamOfInvitationKeycloakContactsListViewModel(self, streamUUID: streamUUIDForViewModel, searchStatus: .performingSearch(searchText: newSearchText))
        }
        
        private func stopSearch() {
            guard let streamUUIDForViewModel else { return }
            dataSource.filterAsyncStreamOfInvitationKeycloakContactsListViewModel(self, streamUUID: streamUUIDForViewModel, searchStatus: .notPerformingSearch)
        }
        
        private func setIsSearchInProgress(newValue: Bool) {
            withAnimation { isSearchInProgress = newValue }
            if newValue {
                performSearchWith(newSearchText: searchText)
            } else {
                stopSearch()
            }
        }

        
        private let contentUnavailableViewModel: ObvContentUnavailableView.Model = .init(
            title: String(localizedInThisBundle: "CONTENT_UNAVAILABLE_VIEW_DESCRIPTION_CONTACTS_LIST"),
            systemIcon: .personCropBadgeMagnifyingglass,
            description: nil)
            
        
        private func userWantsToPerformKeycloakAuthentication() async {
            do {
                try await actions.userWantsToPerformKeycloakAuthentication(self, ownedCryptoId: currentOwnedCryptoId)
                // If reach this point, the authentication process was successful. We re-trigger a search to update the
                // model.
                performSearchWith(newSearchText: searchText)
            } catch {
                switch error {
                case .userHasCancelled:
                    return
                }
            }
        }
        
        
        public var body: some View {
            Group {
                if let streamedViewModel {
                    
                    switch streamedViewModel {
                        
                    case .success(let successViewModel):
                        
                        if successViewModel.isEmpty {
                            Group {
                                if isSearchInProgress {
                                    ObvContentUnavailableView.search
                                } else {
                                    ObvContentUnavailableView(contentUnavailableViewModel)
                                }
                            }
                            .padding(.top)
                        } else {
                            
                            ForEach(listOfFirstLetters, id: \.self) { key in
                                if let contactIdentifiers = successViewModel.contactIdentifiers[key], !contactIdentifiers.isEmpty {
                                    ListOfContactsCellForKeyView(currentOwnedCryptoId: self.currentOwnedCryptoId,
                                                                 key: key,
                                                                 contactIdentifiers: contactIdentifiers,
                                                                 dataSource: dataSource,
                                                                 avatarDataSource: avatarDataSource,
                                                                 actions: actions,
                                                                 router: router)
                                }
                            }
                            
                            if successViewModel.numberOfMissingResults > 0 {
                                Text("\(successViewModel.numberOfMissingResults)_KEYCLOAK_MISSING_RESULTS")
                                    .padding(.vertical)
                                    .foregroundColor(.secondary)
                                    .listRowInsets(EdgeInsets(top: 0.0, leading: 8.0, bottom: 0.0, trailing: 8.0))
                                    .listRowBackground(Color.clear)
                            }
                        }

                    case .searchError(let searchError):
                                   
                        switch searchError {
                            
                        case .authenticationRequired, .userHasCancelled:

                            ContentUnavailableOnKeycloakAuthenticationRequiredView(userWantsToPerformKeycloakAuthentication: userWantsToPerformKeycloakAuthentication)
                                .padding(.top)

                        default:
                            
                            ObvContentUnavailableView(title: String(localizedInThisBundle: "SOMETHING_WENT_WONT_DURING_KEYCLOAK_SEARCH"),
                                                      systemIcon: .serverRack,
                                                      description: nil)
                            .padding(.top)

                            EmptyView()
                        }
                        
                    }
                } else {
                    ProgressViewForList()
                        .padding(.top)
                        .listRowSeparator(.hidden)
                }
            }
            .listRowSeparator(.hidden)
            .task(onTask)
            .onChange(of: searchText) { newSearchText in performSearchWith(newSearchText: newSearchText) }
            .onChange(of: environmentIsSearching) { newValue in setIsSearchInProgress(newValue: newValue) }
        }
        
    }
    
}


extension ListOfContactsAndGroupsView.ListOfDirectoryContactsView {
    
    public enum KeycloakError: Error {
        case userHasCancelled
    }
    
}

// MARK: - Internal view

private struct ContentUnavailableOnKeycloakAuthenticationRequiredView: View {

    let userWantsToPerformKeycloakAuthentication: () async -> Void
    
    private func userWantsToAuthenticate() {
        withAnimation { isAuthenticating = true }
        Task {
            await userWantsToPerformKeycloakAuthentication()
            try? await Task.sleep(seconds: 1) // Allow the model to refresh
            withAnimation { isAuthenticating = false }
        }
    }
    
    @State private var showAlert: Bool = false
    @State private var isAuthenticating: Bool = false
    
    private let title = String(localizedInThisBundle: "KEYCLOAK_AUTHENTICATION_REQUIRED_TITLE")
    
    private let description = String(localizedInThisBundle: "KEYCLOAK_AUTHENTICATION_REQUIRED_DESCRIPTION")
    
    private let buttonTitle = String(localizedInThisBundle: "KEYCLOAK_AUTHENTICATION_BUTTON_TITLE")
    
    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                Label(title: { Text(title) }, icon: { Image(systemIcon: .serverRack) })
            } description: {
                Text(description)
            } actions: {
                Button(action: userWantsToAuthenticate) {
                    HStack {
                        if isAuthenticating {
                            ProgressView().progressViewStyle(.circular)
                        }
                        Text(buttonTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)
            }
        } else {
            ObvContentUnavailableView(
                title: title,
                systemIcon: .serverRack,
                description: description)
            .onAppear(perform: { showAlert = true })
            .alert(title, isPresented: $showAlert) {
                Button(String(localizedInThisBundle: "LATER"), action: {})
                Button(buttonTitle, action: userWantsToAuthenticate)
            }
        }
    }
    
}


// MARK: - Internal view

private struct ProgressViewForList: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
    }
}

// MARK: - Internal view

extension ListOfContactsAndGroupsView {
    
    /// One of the 3 tab views. This view shows the list of contacts.
    public struct ListOfLocalContactsView: View {
        
        let currentOwnedCryptoId: ObvCryptoId
        let dataSource: ListOfContactsAndGroupsViewDataSource
        let avatarDataSource: ObvAvatarViewDataSource
        let actions: ListOfContactsAndGroupsViewActions
        let router: InvitationFlowRouter
        @Binding var searchText: String
        @Binding var isSearchInProgress: Bool
        let addContactInPersonAction: () -> Void
        let addContactRemotelyAction: () -> Void

        @Environment(\.isSearching) var environmentIsSearching
        
        @State private var streamedViewModel: InvitationContactsListViewModel?
        @State private var streamUUIDForViewModel: UUID? // Required as a state to implement search
        
        private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ListOfContactsAndGroupsView")
        
        private let listOfFirstLetters: [String] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ#").map(String.init)
        
        private func onTask() async {
            do {
                let searchStatus: InvitationContactsListViewModel.SearchStatus
                if isSearchInProgress {
                    searchStatus = .performingSearch(searchText: searchText)
                } else {
                    searchStatus = .notPerformingSearch
                }
                let (streamUUID, stream) = try await dataSource.getAsyncStreamOfInvitationContactsListViewModel(self, ownedCryptoId: self.currentOwnedCryptoId, initialSearchStatus: searchStatus)
                self.streamUUIDForViewModel = streamUUID
                for await model in stream {
                    withAnimation { self.streamedViewModel = model }
                }
                dataSource.finishAsyncStreamOfInvitationContactsListViewModel(self, streamUUID: streamUUID)
                self.streamUUIDForViewModel = nil
            } catch {
                Self.logger.fault("Failed to load model: \(error.localizedDescription, privacy: .public)")
                assertionFailure()
            }
        }
        
        private func performSearchWith(newSearchText: String?) {
            guard let streamUUIDForViewModel else { return }
            dataSource.filterAsyncSequenceOfInvitationContactsListViewModel(self, streamUUID: streamUUIDForViewModel, searchStatus: .performingSearch(searchText: searchText))
        }
        
        private func stopSearch() {
            guard let streamUUIDForViewModel else { return }
            dataSource.filterAsyncSequenceOfInvitationContactsListViewModel(self, streamUUID: streamUUIDForViewModel, searchStatus: .notPerformingSearch)
        }
        
        private func setIsSearchInProgress(newValue: Bool) {
            withAnimation { isSearchInProgress = newValue }
            if newValue {
                performSearchWith(newSearchText: searchText)
            } else {
                stopSearch()
            }
        }
        
        
        public var body: some View {
            Group {
                if let streamedViewModel {
                    if streamedViewModel.isEmpty {
                        Group {
                            if isSearchInProgress {
                                ObvContentUnavailableView.search
                            } else {
                                LocalContactContentUnavailableView(addContactInPersonAction: addContactInPersonAction,
                                                                   addContactRemotelyAction: addContactRemotelyAction)
                            }
                        }
                        .padding(.top)
                    } else {
                        ForEach(listOfFirstLetters, id: \.self) { key in
                            if let contactIdentifiers = streamedViewModel.contactIdentifiers[key], !contactIdentifiers.isEmpty {
                                ListOfContactsCellForKeyView(currentOwnedCryptoId: self.currentOwnedCryptoId,
                                                             key: key,
                                                             contactIdentifiers: contactIdentifiers,
                                                             dataSource: dataSource,
                                                             avatarDataSource: avatarDataSource,
                                                             actions: actions,
                                                             router: router)
                            }
                        }
                    }
                } else {
                    ProgressViewForList()
                        .padding(.top)
                        .listRowSeparator(.hidden)
                }
            }
            .listRowSeparator(.hidden)
            .task(onTask)
            .onChange(of: searchText) { newSearchText in performSearchWith(newSearchText: newSearchText) }
            .onChange(of: environmentIsSearching) { newValue in setIsSearchInProgress(newValue: newValue) }
        }
        
    }
    
}


// MARK: - Internal view

private struct LocalContactContentUnavailableView: View {
    
    let addContactInPersonAction: () -> Void
    let addContactRemotelyAction: () -> Void

    private let contentUnavailableViewModel: ObvContentUnavailableView.Model = .init(
        title: String(localizedInThisBundle: "CONTENT_UNAVAILABLE_YET_VIEW_DESCRIPTION_CONTACTS_LIST"),
        systemIcon: .personCropBadgeMagnifyingglass,
        description: nil)

    @State private var showAddContactSheet: Bool = false

    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                Label(title: { Text(contentUnavailableViewModel.title) }, icon: { Image(systemIcon: contentUnavailableViewModel.systemIcon) })
            } description: {
                Text("CONTENT_UNAVAILABLE_YET_VIEW_DESCRIPTION_CONTACTS_LIST_DESCRIPTION")
            } actions: {
                Button(action: { showAddContactSheet = true }) {
                    Text("CONTACT_VIEW_NEW_CONTACT")
                }
                .buttonStyle(.borderedProminent)
                .confirmationDialog(Text("HOW_DO_YOU_WANT_TO_ADD_A_CONTACT"), isPresented: $showAddContactSheet, titleVisibility: .visible) {
                    Button(action: addContactInPersonAction) {
                        Text("SHOW_ADD_CONTACT_SHEET_IN_PERSON")
                    }
                    Button(action: addContactRemotelyAction) {
                        Text("SHOW_ADD_CONTACT_SHEET_DISTANCE")
                    }
                }
            }
        } else {
            ObvContentUnavailableView(contentUnavailableViewModel)
        }
    }
    
}


// MARK: - Internal view

extension ListOfContactsAndGroupsView {
    
    public struct ListOfContactsCellForKeyView: View {
        
        let currentOwnedCryptoId: ObvCryptoId
        let key: String
        let contactIdentifiers: [InvitationContactsListViewModel.ContactIdentifier]
        let dataSource: ListOfContactsAndGroupsViewDataSource
        let avatarDataSource: ObvAvatarViewDataSource
        let actions: ListOfContactsAndGroupsViewActions
        let router: InvitationFlowRouter
        
        private func contactIdentifierTapped(with contactIdentifier: InvitationContactsListViewModel.ContactIdentifier) {
            switch contactIdentifier {
            case .obvContactIdentifier:
                #if DEBUG
                print("Contact identifier tapped in a preview")
                #else
                assertionFailure("Should not happen within previews")
                #endif
            case .keycloakContactIdentifier(let keycloakUserDetails, _):
                Task {
                    let navigationType = await actions.keycloakContactIdentifierTapped(self, currentCryptoId: currentOwnedCryptoId, with: keycloakUserDetails)
                    if case let .showInvitation(obvContactIdentifier, keycloakUserDetails) = navigationType {
                        router.presentFullScreen(.invitation(contactIdentifier: .obvContactIdentifier(obvContactIdentifier, keycloakUserDetails), currentOwnedCryptoId: currentOwnedCryptoId))
                    }
                }
            case .persistedObvContactIdentity(let objectID):
                Task {
                    let navigationType = await actions.persistedObvContactIdentityTapped(self, currentCryptoId: currentOwnedCryptoId, with: objectID)
                    if case let .showInvitation(obvContactIdentifier, keycloakUserDetails) = navigationType {
                        router.presentFullScreen(.invitation(contactIdentifier: .obvContactIdentifier(obvContactIdentifier, keycloakUserDetails), currentOwnedCryptoId: currentOwnedCryptoId))
                    }
                }
            }
        }

        public var body: some View {
            Section(key) {
                ForEach(contactIdentifiers, id: \.self) { contactIdentifier in
                    InvitationContactsListCellView(currentOwnedCryptoId: currentOwnedCryptoId,
                                                   contactIdentifier: contactIdentifier,
                                                   dataSource: dataSource,
                                                   avatarViewDataSource: avatarDataSource)
                    .padding(.bottom)
                    .listRowInsets(EdgeInsets(top: 0.0, leading: 16.0, bottom: 0.0, trailing: 16.0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
                    .onTapGesture {
                        contactIdentifierTapped(with: contactIdentifier)
                    }
                }
            }
            .sectionIndexLabelOniOS26(key)
            .listSectionIndexVisibilityOniOS26(.visible)
        }
    }


}

// MARK: - Internal view

private struct NewGroupButton: View {

    let addNewGroupAction: () -> Void
    
    var body: some View {
        Button(action: addNewGroupAction) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemIcon: .person3Fill)
                    .imageScale(.medium)
                    .frame(width: ObvAvatarSize.normal.frameSize.width, height: ObvAvatarSize.normal.frameSize.height)
                    .tint(Color.primary)
                    .background(
                        Circle().stroke(Color.primary.opacity(0.3), lineWidth: 0.5)
                    )
                Text("CONTACT_VIEW_NEW_GROUP")
                Spacer()
            }
            .contentShape(Rectangle()) // Trick making the button interactive everywhere
        }
        .buttonStyle(.plain)
    }
    
}


// MARK: - Internal view

private struct NewContactButton: View {
    
    let addContactInPersonAction: () -> Void
    let addContactRemotelyAction: () -> Void
    
    @State private var showAddContactSheet: Bool = false
    
    var body: some View {
        Button(action: { showAddContactSheet = true }) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemIcon: .personFillBadgePlus)
                    .imageScale(.large)
                    .frame(width: ObvAvatarSize.normal.frameSize.width, height: ObvAvatarSize.normal.frameSize.height)
                    .tint(Color.primary)
                    .background(
                        Circle().stroke(Color.primary.opacity(0.3), lineWidth: 0.5)
                    )
                
                Text("CONTACT_VIEW_NEW_CONTACT")
                    .confirmationDialog(Text("HOW_DO_YOU_WANT_TO_ADD_A_CONTACT"), isPresented: $showAddContactSheet, titleVisibility: .visible) {
                        Button(action: addContactInPersonAction) {
                            Text("SHOW_ADD_CONTACT_SHEET_IN_PERSON")
                        }
                        Button(action: addContactRemotelyAction) {
                            Text("SHOW_ADD_CONTACT_SHEET_DISTANCE")
                        }
                    }
                Spacer()
            }
            .contentShape(Rectangle()) // Trick making the button interactive everywhere
        }
        .buttonStyle(.plain)
    }
    
}


// MARK: - Contact cell view

@MainActor
public protocol InvitationContactsListCellViewDataSource: AnyObject {

    func getInitialObvContactCellViewModel(contactIdentifier: InvitationContactsListViewModel.ContactIdentifier) -> InvitationContactsListCellView.Model?
    func getAsyncStreamOfObvContactCellViewModel(_ view: InvitationContactsListCellView, contactIdentifier: InvitationContactsListViewModel.ContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<InvitationContactsListCellView.Model>)
    func finishAsyncStreamOfObvContactCellViewModel(_ view: InvitationContactsListCellView, streamUUID: UUID)
    
    // The following datasource method returns an `InvitationContactsListCellViewModel` if the keycloak user is already a contact.
    func getInvitationContactsListCellViewModelForKeycloakUser(_ view: InvitationContactsListCellView, ownedCryptoId: ObvCryptoId, keycloakUserDetails: ObvKeycloakUserDetails) async -> InvitationContactsListCellView.Model?
    
}


public struct InvitationContactsListCellView: View {
    
    let currentOwnedCryptoId: ObvCryptoId
    let contactIdentifier: InvitationContactsListViewModel.ContactIdentifier
    let dataSource: InvitationContactsListCellViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let initialViewModel: Model?
    
    public struct Model: Sendable, Equatable {
        let avatarModel: ObvAvatarViewModel
        let coreDetails: ObvIdentityCoreDetails
        let customDisplayName: String?
        let isKeycloakManaged: Bool
        let wasRecentlyOnline: Bool
        let contactsSortOrder: ContactsSortOrder

        public init(avatarModel: ObvAvatarViewModel, coreDetails: ObvIdentityCoreDetails, customDisplayName: String?, isKeycloakManaged: Bool, wasRecentlyOnline: Bool, contactsSortOrder: ContactsSortOrder) {
            self.avatarModel = avatarModel
            self.coreDetails = coreDetails
            self.customDisplayName = customDisplayName
            self.isKeycloakManaged = isKeycloakManaged
            self.wasRecentlyOnline = wasRecentlyOnline
            self.contactsSortOrder = contactsSortOrder
        }
    }

    @State private var streamedViewModel: Model?
    
    private var viewModel: Model? {
        self.streamedViewModel ?? self.initialViewModel
    }
    
    init(currentOwnedCryptoId: ObvCryptoId,
         contactIdentifier: InvitationContactsListViewModel.ContactIdentifier,
         dataSource: InvitationContactsListCellViewDataSource,
         avatarViewDataSource: ObvAvatarViewDataSource) {
        self.currentOwnedCryptoId = currentOwnedCryptoId
        self.contactIdentifier = contactIdentifier
        self.dataSource = dataSource
        self.avatarViewDataSource = avatarViewDataSource
        
        if case .keycloakContactIdentifier(let obvKeycloakUserDetails, let contactsSortOrder) = contactIdentifier { // Contact from keycloak
            self.initialViewModel = obvKeycloakUserDetails.toInvitationContactsListCellViewModel(contactsSortOrder: contactsSortOrder)
        } else {
            if let receivedModel = dataSource.getInitialObvContactCellViewModel(contactIdentifier: contactIdentifier) {
                self.initialViewModel = receivedModel
            } else {
                self.initialViewModel = nil
            }
        }
    }
    
    @ViewBuilder
    private var emptyAvatarView: some View {
        ObvAvatarView(model: .init(characterOrIcon: .icon(.person),
                                   colors: .init(foreground: .clear, background: .clear),
                                   photoURL: nil),
                      style: .circle,
                      size: .normal,
                      dataSource: nil)
    }
    
    private var nameParts: (part1: String, part2: String?) {
        guard let viewModel else { return (" ", nil) }
        if let customName = viewModel.customDisplayName?.trimmingWhitespacesAndNewlines(), !customName.isEmpty {
            return (customName, nil)
        } else if let firstName = viewModel.coreDetails.firstName {
            return (firstName, viewModel.coreDetails.lastName)
        } else if let lastName = viewModel.coreDetails.lastName {
            return (lastName, nil)
        } else {
            return (viewModel.coreDetails.getDisplayNameWithStyle(.short), nil)
        }
    }
    
    private var subtitle: String? {
        guard let viewModel else { return nil }
        if viewModel.customDisplayName != nil {
            return viewModel.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
        } else {
            return viewModel.coreDetails.getDisplayNameWithStyle(.positionAtCompany)
        }
    }
    
    private var subSubtitle: String? {
        guard let viewModel else { return nil }
        if viewModel.customDisplayName != nil {
            return viewModel.coreDetails.getDisplayNameWithStyle(.positionAtCompany)
        } else {
            return nil
        }
    }
    
    private var part1Font: Font {
        guard let viewModel else { return .system(.body, design: .rounded) }
        if nameParts.part2 == nil {
            return .system(.body, design: .rounded, weight: .bold)
        } else {
            switch viewModel.contactsSortOrder {
            case .byFirstName:
                return .system(.body, design: .rounded, weight: .bold)
            case .byLastName:
                return .system(.body, design: .rounded)
            }
        }
    }
    
    private var part2Font: Font {
        guard let viewModel else { return .system(.body, design: .rounded) }
        switch viewModel.contactsSortOrder {
        case .byFirstName:
            return .system(.body, design: .rounded)
        case .byLastName:
            return .system(.body, design: .rounded, weight: .bold)
        }
    }
    
    @ViewBuilder
    var content: some View {
        HStack(alignment: .center) {
            
            if let viewModel {
                ObvAvatarView(model: viewModel.avatarModel, style: .circle, size: .normal, dataSource: avatarViewDataSource, showGreenShieldIfAppropriate: true)
            } else {
                emptyAvatarView
            }
            
            VStack(alignment: .leading, spacing: 2.0) {
                
                HStack(alignment: .firstTextBaseline, spacing: 4.0) {
                    // firstName or nickname
                    Text(nameParts.part1)
                        .lineLimit(1)
                        .font(part1Font)
                        .foregroundStyle(.primary)
                    
                    // lastName
                    if let part2 = nameParts.part2 {
                        Text(part2)
                            .lineLimit(1)
                            .font(part2Font)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    
                }
                
                if let subtitle, !subtitle.isEmpty {
                    HStack {
                        Text(subtitle)
                            .lineLimit(subSubtitle == nil ? 2 : 1)
                            .foregroundStyle(.secondary)
                            .font(.body)
                        Spacer()
                    }
                }

                if let subSubtitle, !subSubtitle.isEmpty {
                    HStack {
                        Text(subSubtitle)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                            .font(.body)
                        Spacer()
                    }
                }

            }

            if let viewModel, !viewModel.wasRecentlyOnline {
                Image(systemIcon: .zzz)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
    
    public var body: some View {
        content
            .task(onTaskForAsyncStreamOfInvitationContactsListCellViewModel)
    }
}


extension InvitationContactsListCellView {
    
    private func onTaskForAsyncStreamOfInvitationContactsListCellViewModel() async {
        switch contactIdentifier {
        case .keycloakContactIdentifier(let keycloakUserDetails, _):
            // We only fetch data for user in database. But in case the keycloak user is already a contact, we get their details
            // We only fetch data for user in database. But in case the keycloak user is already a contact, we get their details
            if let receivedModel = await dataSource.getInvitationContactsListCellViewModelForKeycloakUser(self, ownedCryptoId: currentOwnedCryptoId, keycloakUserDetails: keycloakUserDetails) {
                withAnimation {
                    self.streamedViewModel = receivedModel
                }
            }
        case .obvContactIdentifier, .persistedObvContactIdentity:
            do {
                let (streamUUID, stream) = try await dataSource.getAsyncStreamOfObvContactCellViewModel(self, contactIdentifier: contactIdentifier)
                for await receivedModel in stream {
                    withAnimation {
                        self.streamedViewModel = receivedModel
                    }
                }
                dataSource.finishAsyncStreamOfObvContactCellViewModel(self, streamUUID: streamUUID)
            } catch {
                assertionFailure()
            }
        }
    }
    
}





// MARK: - Previews

#if DEBUG

@MainActor
private let minimalDataSourceForPreviews = MinimalDataSourceAndActionsForPreviews()


#Preview("InvitationContactsListView") {
    NavigationStack {
        ListOfContactsAndGroupsView(ownedURLIdentity: ObvURLIdentity.sampleDataOwnedIdentity,
                                    ownedIdentityIsManagedByKeycloak: true,
                                    router: InvitationFlowRouter.initForPreviews(),
                                    navigation: minimalDataSourceForPreviews)
        .environment(\.locale, .init(identifier: "fr"))
    }
}

#endif
