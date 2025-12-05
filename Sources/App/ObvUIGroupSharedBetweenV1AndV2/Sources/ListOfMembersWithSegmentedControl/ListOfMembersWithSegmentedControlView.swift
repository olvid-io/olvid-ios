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
import ObvAppTypes
import ObvDesignSystem
import ObvCircleAndTitlesView

@MainActor
public protocol ListOfMembersWithSegmentedControlViewDataSource {
    func getAsyncSequenceOfListOfMembersWithSegmentedControlViewModel(_ view: ListOfMembersWithSegmentedControlView, groupIdentifier: ObvGroupIdentifier, searchText: String?) async throws -> (streamUUID: UUID, stream: AsyncStream<ListOfMembersWithSegmentedControlView.Model>)
    func filterAsyncSequenceOfListOfMembersWithSegmentedControlViewModel(_ view: ListOfMembersWithSegmentedControlView, streamUUID: UUID, searchText: String?)
    func finishAsyncSequenceOfListOfMembersWithSegmentedControlViewModel(_ view: ListOfMembersWithSegmentedControlView, streamUUID: UUID)
}

@MainActor
public protocol ListOfMembersWithSegmentedControlViewActions: SingleGroupMemberViewActionsProtocol {
}

@MainActor
public protocol ListOfMembersWithSegmentedControlViewNavigation: SingleGroupMemberViewNavigation {}

public struct ListOfMembersWithSegmentedControlView: View {

    let groupIdentifier: ObvGroupIdentifier
    let dataSources: DataSources
    let actions: any ListOfMembersWithSegmentedControlViewActions
    let navigation: any ListOfMembersWithSegmentedControlViewNavigation
    
    public init(groupIdentifier: ObvGroupIdentifier,
                dataSources: DataSources,
                actions: any ListOfMembersWithSegmentedControlViewActions,
                navigation: any ListOfMembersWithSegmentedControlViewNavigation) {
        self.groupIdentifier = groupIdentifier
        self.dataSources = dataSources
        self.actions = actions
        self.navigation = navigation
    }

    public struct Model: Sendable, Equatable {
        let groupIdentifier: ObvGroupIdentifier
        let allOtherGroupMembers: [SingleGroupMemberView.Model.Identifier] // Includes admins
        let allOtherGroupAdmins: [SingleGroupMemberView.Model.Identifier]
        let isGroupV2UpdateInProgress: Bool // Always false for a group v1
        let isOwnedIdentityAnAdmin: Bool
        
        public init(groupIdentifier: ObvGroupIdentifier, allOtherGroupMembers: [SingleGroupMemberView.Model.Identifier], allOtherGroupAdmins: [SingleGroupMemberView.Model.Identifier], isGroupV2UpdateInProgress: Bool, isOwnedIdentityAnAdmin: Bool) {
            self.groupIdentifier = groupIdentifier
            self.allOtherGroupMembers = allOtherGroupMembers
            self.allOtherGroupAdmins = allOtherGroupAdmins
            self.isGroupV2UpdateInProgress = isGroupV2UpdateInProgress
            self.isOwnedIdentityAnAdmin = isOwnedIdentityAnAdmin
        }
    }
    
    public struct DataSources {
        let dataSource: any ListOfMembersWithSegmentedControlViewDataSource
        let singleGroupMembersListViewDataSources: SingleGroupMembersListView.DataSources
        
        public init(dataSource: any ListOfMembersWithSegmentedControlViewDataSource, singleGroupMembersListViewDataSources: SingleGroupMembersListView.DataSources) {
            self.dataSource = dataSource
            self.singleGroupMembersListViewDataSources = singleGroupMembersListViewDataSources
        }
    }

    @State private var streamedModel: Model?
    @State private var currentStreamUUID: UUID? // Required to perform search
    @State private var searchText: String = ""
    @State private var isSearchInProgress: Bool = false

    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSources.dataSource.getAsyncSequenceOfListOfMembersWithSegmentedControlViewModel(self, groupIdentifier: groupIdentifier, searchText: searchText.mapToNilIfZeroLength())
            if let currentStreamUUID {
                dataSources.dataSource.finishAsyncSequenceOfListOfMembersWithSegmentedControlViewModel(self, streamUUID: currentStreamUUID)
            }
            currentStreamUUID = streamUUID
            for await model in stream {
                if self.streamedModel == nil {
                    self.streamedModel = model
                } else {
                    withAnimation {
                        self.streamedModel = model
                    }
                }
            }
            dataSources.dataSource.finishAsyncSequenceOfListOfMembersWithSegmentedControlViewModel(self, streamUUID: streamUUID)
            currentStreamUUID = nil
        } catch {
            assertionFailure()
        }
    }

    private func performSearchWith(newSearchText: String?) {
        guard let currentStreamUUID else { return }
        dataSources.dataSource.filterAsyncSequenceOfListOfMembersWithSegmentedControlViewModel(self, streamUUID: currentStreamUUID, searchText: newSearchText)
    }

    public var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .edgesIgnoringSafeArea(.all)
            VStack { Spacer() }
            if let streamedModel {
                InternalView(groupIdentifier: groupIdentifier,
                             isSearchInProgress: $isSearchInProgress,
                             model: streamedModel,
                             dataSources: dataSources,
                             actions: self,
                             navigation: navigation)
                .onChange(of: searchText) { newSearchText in performSearchWith(newSearchText: newSearchText) }
                if isSearchInProgress && streamedModel.allOtherGroupMembers.isEmpty {
                    ObvContentUnavailableView.search
                }
            } else {
                ObvCenteredProgressView()
            }
        }
        .task(onTask)
        .navigationTitle(String(localizedInThisBundle: "TITLE_GROUP_MEMBERS"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search"))
    }
        
}


extension ListOfMembersWithSegmentedControlView: ListOfMembersWithSegmentedControlViewInternalActions {
    
    public func userWantsToAddSelectedUsersToExistingGroup(_ view: SelectUsersToAddView.InternalView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) async throws {
        try await actions.userWantsToAddSelectedUsersToExistingGroup(view, groupIdentifier: groupIdentifier, withIdentifiers: userIdentifiers)
    }
    
}


// MARK: - Internal view

@MainActor
protocol ListOfMembersWithSegmentedControlViewInternalActions: SingleGroupMemberViewActionsProtocol {}

extension ListOfMembersWithSegmentedControlView {
    struct InternalView: View {
        
        let groupIdentifier: ObvGroupIdentifier
        @Binding var isSearchInProgress: Bool
        let model: Model
        let dataSources: DataSources
        let actions: ListOfMembersWithSegmentedControlViewInternalActions
        let navigation: any ListOfMembersWithSegmentedControlViewNavigation

        @Environment(\.isSearching) var isSearching

        private enum AllOrAdminsOnly {
            case all
            case adminsOnly
        }
        
        @State private var allOrAdminsOnly: AllOrAdminsOnly = .all

        private let leadingPaddingForDivider: CGFloat = 70.0

        private var opacity: CGFloat {
            switch allOrAdminsOnly {
            case .all:
                return isSearchInProgress && model.allOtherGroupMembers.isEmpty ? 0.0 : 1.0
            case .adminsOnly:
                return isSearchInProgress && model.allOtherGroupAdmins.isEmpty ? 0.0 : 1.0
            }
        }
        
        var body: some View {
            ScrollView {
                VStack {
                    
                    Picker(String(localizedInThisBundle: "SHOW_ALL_GROUP_MEMBERS_OR_RESTRICT_TO_ADMINS"), selection: $allOrAdminsOnly) {
                        Text("ALL").tag(AllOrAdminsOnly.all)
                        Text("ADMINS").tag(AllOrAdminsOnly.adminsOnly)
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    if model.isGroupV2UpdateInProgress {
                        UpdateInProgressView()
                            .padding([.horizontal, .bottom])
                    }

                    ObvCardView(padding: 0) {
                        
                        VStack {
                            
                            switch allOrAdminsOnly {
                                
                            case .all:
                                
                                SingleGroupMembersListView(
                                    model: .init(groupIdentifier: model.groupIdentifier,
                                                 mode: .listMembers(groupIdentifier: groupIdentifier,
                                                                    commonActions: actions,
                                                                    navigation: navigation),
                                                 singleGroupMemberViewModelIdentifiers: model.allOtherGroupMembers,
                                                 showOwnedIdentity: !isSearchInProgress),
                                    dataSources: dataSources.singleGroupMembersListViewDataSources)
                                
                            case .adminsOnly:
                                
                                SingleGroupMembersListView(
                                    model: .init(groupIdentifier: model.groupIdentifier,
                                                 mode: .listMembers(groupIdentifier: groupIdentifier,
                                                                    commonActions: actions,
                                                                    navigation: navigation),
                                                 singleGroupMemberViewModelIdentifiers: model.allOtherGroupAdmins,
                                                 showOwnedIdentity: !isSearchInProgress && model.isOwnedIdentityAnAdmin),
                                    dataSources: dataSources.singleGroupMembersListViewDataSources)
                                
                            }
                            
                        }
                        .padding(.vertical)
                        
                    }
                    .padding(.horizontal)
                    .opacity(opacity)

                }
                .padding(.bottom)
            }
            .onChange(of: isSearching) { newValue in withAnimation { isSearchInProgress = newValue } }
        }
        
    }
}


// MARK: - Previews

#if DEBUG

@MainActor
private let genericDataSourceForPreviews = GenericDataSourceAndActionsForPreviews()

#Preview {
    NavigationStack {
        ListOfMembersWithSegmentedControlView(
            groupIdentifier: .sampleData,
            dataSources: .init(
                dataSource: genericDataSourceForPreviews,
                singleGroupMembersListViewDataSources: .init(
                    ownedIdentityAsGroupMemberViewDataSource: genericDataSourceForPreviews,
                    avatarViewDataSource: genericDataSourceForPreviews,
                    singleGroupMemberViewDataSource: genericDataSourceForPreviews)),
            actions: genericDataSourceForPreviews,
            navigation: genericDataSourceForPreviews)
    }
}

#endif
