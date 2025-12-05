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
import ObvCells
import ObvDesignSystem


@MainActor
public protocol ObvListOfCommonGroupsWithContactViewDataSource {
    func getAsyncStreamOfObvGroupsListViewModel(_ view: ObvListOfCommonGroupsWithContactView, contactIdentifier: ObvContactIdentifier, initialSearchStatus: ObvListOfCommonGroupsWithContactView.Model.SearchStatus) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvListOfCommonGroupsWithContactView.Model>)
    func finishAsyncStreamOfObvGroupsListViewModel(_ view: ObvListOfCommonGroupsWithContactView, streamUUID: UUID)
    func filterAsyncStreamOfObvGroupsListViewModel(_ view: ObvListOfCommonGroupsWithContactView, streamUUID: UUID, searchStatus: ObvListOfCommonGroupsWithContactView.Model.SearchStatus)
}

@MainActor
public protocol ObvListOfCommonGroupsWithContactViewNavigation: ObvGroupCellViewNavigation {
    
}

/// View that shows the list of common groups with a particular contact.
/// It's a simplified version of `ObvGroupsList.ObvGroupsListView`
public struct ObvListOfCommonGroupsWithContactView: View {

    let contactIdentifier: ObvContactIdentifier
    let dataSources: DataSources
    let navigation: any ObvListOfCommonGroupsWithContactViewNavigation
    
    public init(contactIdentifier: ObvContactIdentifier, dataSources: DataSources, navigation: any ObvListOfCommonGroupsWithContactViewNavigation) {
        self.contactIdentifier = contactIdentifier
        self.dataSources = dataSources
        self.navigation = navigation
    }
    
    public struct DataSources {
        let dataSource: any ObvListOfCommonGroupsWithContactViewDataSource
        let groupCellViewDataSource: any ObvGroupCellViewDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        
        public init(dataSource: any ObvListOfCommonGroupsWithContactViewDataSource, groupCellViewDataSource: any ObvGroupCellViewDataSource, avatarViewDataSource: any ObvAvatarViewDataSource) {
            self.dataSource = dataSource
            self.groupCellViewDataSource = groupCellViewDataSource
            self.avatarViewDataSource = avatarViewDataSource
        }
    }

    @State private var streamedViewModel: Model?
    @State private var streamUUIDForViewModel: UUID? // Required as a state to implement search
    
    // Implementing search
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var isSearchInProgress: Bool = false
    @State private var highlightedGroupIdentifier: ObvGroupCellViewModel.GroupIdentifier? = nil

    public struct Model: Sendable, Equatable {
        let contactDisplayName: String
        let identifiersOfGroupsAdministrated: [ObvGroupCellViewModel.GroupIdentifier]
        let identifiersOfGroupsJoined: [ObvGroupCellViewModel.GroupIdentifier]
        
        public init(contactDisplayName: String, identifiersOfGroupsAdministrated: [ObvGroupCellViewModel.GroupIdentifier], identifiersOfGroupsJoined: [ObvGroupCellViewModel.GroupIdentifier]) {
            self.contactDisplayName = contactDisplayName
            self.identifiersOfGroupsAdministrated = identifiersOfGroupsAdministrated
            self.identifiersOfGroupsJoined = identifiersOfGroupsJoined
        }
        
        public enum SearchStatus: Sendable {
            case notPerformingSearch
            case performingSearch(searchText: String?)
            public var searchText: String? {
                switch self {
                case .notPerformingSearch:
                    return nil
                case .performingSearch(let searchText):
                    return searchText
                }
            }
        }

    }
    
    
    private func onTask() async {
        do {
            let searchStatus: Model.SearchStatus
            if isSearchInProgress {
                searchStatus = .performingSearch(searchText: searchText)
            } else {
                searchStatus = .notPerformingSearch
            }
            let (streamUUID, stream) = try await dataSources.dataSource.getAsyncStreamOfObvGroupsListViewModel(self, contactIdentifier: contactIdentifier, initialSearchStatus: searchStatus)
            self.streamUUIDForViewModel = streamUUID
            for await receivedModel in stream {
                withAnimation {
                    self.streamedViewModel = receivedModel
                }
            }
            dataSources.dataSource.finishAsyncStreamOfObvGroupsListViewModel(self, streamUUID: streamUUID)
            if self.streamUUIDForViewModel == streamUUID {
                self.streamUUIDForViewModel = nil
            }
        } catch {
            assertionFailure()
        }
    }

    private func performSearchWith(newSearchText: String?) {
        guard let streamUUIDForViewModel else { return }
        dataSources.dataSource.filterAsyncStreamOfObvGroupsListViewModel(self, streamUUID: streamUUIDForViewModel, searchStatus: .performingSearch(searchText: newSearchText))
    }

    private func stopSearch() {
        guard let streamUUIDForViewModel else { return }
        dataSources.dataSource.filterAsyncStreamOfObvGroupsListViewModel(self, streamUUID: streamUUIDForViewModel, searchStatus: .notPerformingSearch)
    }

    private func setIsSearchInProgress(newValue: Bool) {
        withAnimation { isSearchInProgress = newValue }
        if newValue {
            performSearchWith(newSearchText: searchText)
        } else {
            stopSearch()
        }
    }
    
    private var navigationTitle: String {
        if let streamedViewModel {
            return String(localizedInThisBundle: "NAVIGATION_TITLE_COMMON_GROUPS_WITH_CONTACT_\(streamedViewModel.contactDisplayName)")
        } else {
            return String(localizedInThisBundle: "NAVIGATION_TITLE_COMMON_GROUPS_WITH_CONTACT")
        }
    }

    public var body: some View {
        Group {
            if let streamedViewModel {
                ObvListOfCommonGroupsWithContactInternalView(groupCellViewDataSource: dataSources.groupCellViewDataSource,
                                                             avatarViewDataSource: dataSources.avatarViewDataSource,
                                                             navigation: navigation,
                                                             streamedViewModel: streamedViewModel,
                                                             isSearching: $isSearching,
                                                             highlightedGroupIdentifier: $highlightedGroupIdentifier,
                                                             isSearchInProgress: $isSearchInProgress)
            } else {
                ProgressView()
            }
        }
        .task(onTask)
        .onChange(of: isSearching) { newValue in setIsSearchInProgress(newValue: newValue) }
        .onChange(of: searchText) { newSearchText in performSearchWith(newSearchText: newSearchText) }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(navigationTitle)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("SEARCH"))

    }
    
}



// MARK: - Internal view

private struct ObvListOfCommonGroupsWithContactInternalView: View {
    
    let groupCellViewDataSource: ObvGroupCellViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let navigation: ObvListOfCommonGroupsWithContactViewNavigation
    let streamedViewModel: ObvListOfCommonGroupsWithContactView.Model
    @Binding var isSearching: Bool
    @Binding var highlightedGroupIdentifier: ObvGroupCellViewModel.GroupIdentifier?
    @Binding var isSearchInProgress: Bool

    @Environment(\.isSearching) var environmentIsSearching

    private var isSearchInProgressWithNoResults: Bool {
        isSearchInProgress &&
        self.streamedViewModel.identifiersOfGroupsAdministrated.isEmpty &&
        self.streamedViewModel.identifiersOfGroupsJoined.isEmpty
    }

    @Environment(\.colorScheme) var colorScheme
    
    private var sectionBackgroundColor: Color {
        if colorScheme == .dark {
            Color(UIColor.secondarySystemBackground)
        } else {
            Color(UIColor.systemBackground)
        }
    }

    var body: some View {
     
        Group {
            
            if isSearchInProgressWithNoResults {
                
                ObvContentUnavailableView.search
                
            } else {
                ScrollView(.vertical) {
                    VStack {
                        
                        //-------------------------------
                        // Section - Administrated Groups
                        //-------------------------------

                        if !isSearchInProgress || !streamedViewModel.identifiersOfGroupsAdministrated.isEmpty {
                            
                            Section {
                                
                                VStack {
                                    
                                    HStack {
                                        Text("GROUPS_THAT_YOU_ADMINISTER")
                                            .font(.headline)
                                            .listRowSeparator(.hidden)
                                            .padding([.top, .horizontal])
                                        Spacer()
                                    }
                                    .padding(.bottom, 8)

                                    if !streamedViewModel.identifiersOfGroupsAdministrated.isEmpty {
                                        
                                        VStack { Divider() }
                                        
                                        ListOfGroups(identifiersOfGroups: streamedViewModel.identifiersOfGroupsAdministrated,
                                                     groupCellViewDataSource: groupCellViewDataSource,
                                                     avatarViewDataSource: avatarViewDataSource,
                                                     navigation: navigation,
                                                     highlightedGroupIdentifier: $highlightedGroupIdentifier)
                                        .padding(.vertical)
                                        
                                    }
                                    
                                } // End of VStack
                                .background(sectionBackgroundColor)
                                .cornerRadius(20)
                                
                            } // End of Section
                            .padding(.bottom)
                            
                        }

                        //------------------------
                        // Section - Joined Groups
                        //------------------------
                        
                        if !streamedViewModel.identifiersOfGroupsJoined.isEmpty {
                            
                            Section {
                                
                                VStack {
                                    
                                    HStack {
                                        Text("GROUPS_JOINED")
                                            .font(.headline)
                                            .listRowSeparator(.hidden)
                                            .padding([.top, .horizontal])
                                        Spacer()
                                    }
                                    .padding(.bottom, 8)
                                    
                                    VStack { Divider() }
                                        .padding(.bottom)
                                    
                                    ListOfGroups(identifiersOfGroups: streamedViewModel.identifiersOfGroupsJoined,
                                                 groupCellViewDataSource: groupCellViewDataSource,
                                                 avatarViewDataSource: avatarViewDataSource,
                                                 navigation: navigation,
                                                 highlightedGroupIdentifier: $highlightedGroupIdentifier)
                                    .padding([.bottom])
                                    
                                } // End of VStack
                                .background(sectionBackgroundColor)
                                .cornerRadius(20)
                                
                            } // End of Section
                            
                        }

                    } // VStack
                    .padding(.horizontal)

                } // ScrollView
            }
            
        } // Group
        .background(Color(UIColor.systemGroupedBackground))
        .onChange(of: environmentIsSearching) { newValue in isSearching = newValue }

    }
}


// MARK: - Internal view

private struct ListOfGroups: View {
    
    let identifiersOfGroups: [ObvGroupCellViewModel.GroupIdentifier]
    let groupCellViewDataSource: ObvGroupCellViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let navigation: any ObvGroupCellViewNavigation
    @Binding var highlightedGroupIdentifier: ObvGroupCellViewModel.GroupIdentifier?

    var body: some View {
        LazyVStack {
            ForEach(identifiersOfGroups) { groupIdentifier in
                ObvGroupCellView(
                    groupIdentifier: groupIdentifier,
                    expectedNavigationOnTap: .groupDetails,
                    dataSource: groupCellViewDataSource,
                    avatarViewDataSource: avatarViewDataSource,
                    navigation: navigation,
                    highlightedGroupIdentifier: $highlightedGroupIdentifier)
                .id(groupIdentifier) // Required for programatic scroll
                .padding(.horizontal)
                if !identifiersOfGroups.isEmpty && groupIdentifier != identifiersOfGroups.last {
                    Divider()
                        .padding(.leading)
                        .padding(.leading, ObvAvatarSize.normal.frameSize.width + ObvGroupCellView.Constant.horizontalSpacingBetweenAvatarAndText)
                }
            }
            .padding(.bottom, 8) // Add some space after the last item
        }
    }
}
