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
import ObvAppTypes
import ObvDesignSystem


@MainActor
public protocol SelectUsersToRemoveViewDataSource {
    func getAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: SelectUsersToRemoveView, groupIdentifier: ObvGroupIdentifier, searchText: String?) async throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToRemoveView.Model>)
    func filterAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: SelectUsersToRemoveView, streamUUID: UUID, searchText: String?)
    func finishAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: SelectUsersToRemoveView, streamUUID: UUID)
}


@MainActor
public protocol SelectUsersToRemoveViewActions {
    func userWantsToRemoveMembersFromGroup(_ view: SelectUsersToRemoveView, groupIdentifier: ObvGroupIdentifier, membersToRemove: Set<SingleGroupMemberView.Model.Identifier>) async throws
}

@MainActor
public protocol SelectUsersToRemoveViewNavigation {
    func selectUsersToRemoveViewShouldBeDismissed(_ view: SelectUsersToRemoveView)
}

public struct SelectUsersToRemoveView: View {
    
    let groupIdentifier: ObvGroupIdentifier
    let dataSources: DataSources
    let actions: SelectUsersToRemoveViewActions
    let navigation: any SelectUsersToRemoveViewNavigation
    
    public init(groupIdentifier: ObvGroupIdentifier, dataSources: DataSources, actions: SelectUsersToRemoveViewActions, navigation: any SelectUsersToRemoveViewNavigation) {
        self.groupIdentifier = groupIdentifier
        self.dataSources = dataSources
        self.actions = actions
        self.navigation = navigation
    }
    
    public struct DataSources {
        let dataSource: any SelectUsersToRemoveViewDataSource
        let ownedIdentityAsGroupMemberViewDataSource: any OwnedIdentityAsGroupMemberViewDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        let singleGroupMemberViewDataSource: any SingleGroupMemberViewDataSource
        let singleGroupMembersListViewDataSources: SingleGroupMembersListView.DataSources
        
        public init(dataSource: any SelectUsersToRemoveViewDataSource,
                    ownedIdentityAsGroupMemberViewDataSource: any OwnedIdentityAsGroupMemberViewDataSource,
                    avatarViewDataSource: any ObvAvatarViewDataSource,
                    singleGroupMemberViewDataSource: any SingleGroupMemberViewDataSource) {
            self.dataSource = dataSource
            self.ownedIdentityAsGroupMemberViewDataSource = ownedIdentityAsGroupMemberViewDataSource
            self.avatarViewDataSource = avatarViewDataSource
            self.singleGroupMemberViewDataSource = singleGroupMemberViewDataSource
            self.singleGroupMembersListViewDataSources = .init(
                ownedIdentityAsGroupMemberViewDataSource: ownedIdentityAsGroupMemberViewDataSource,
                avatarViewDataSource: avatarViewDataSource,
                singleGroupMemberViewDataSource: singleGroupMemberViewDataSource)
        }
    }
    
    public struct Model: Sendable, Equatable {
        let groupIdentifier: ObvGroupIdentifier
        let allOtherGroupMembers: [SingleGroupMemberView.Model.Identifier]
        let filteredOtherGroupMembers: [SingleGroupMemberView.Model.Identifier] // Filtered by searchText
        
        public init(groupIdentifier: ObvGroupIdentifier, allOtherGroupMembers: [SingleGroupMemberView.Model.Identifier], filteredOtherGroupMembers: [SingleGroupMemberView.Model.Identifier]) {
            self.groupIdentifier = groupIdentifier
            self.allOtherGroupMembers = allOtherGroupMembers
            self.filteredOtherGroupMembers = filteredOtherGroupMembers
        }
    }
    
    @State private var streamedModel: Model?
    @State private var currentStreamUUID: UUID? // Required to perform search
    @State private var searchText: String = ""
    @State private var isSearchInProgress: Bool = false

    @State private var selectedMembers: Set<SingleGroupMemberView.Model.Identifier> = []

    @State private var isInterfaceDisabled: Bool = false
    @State private var hudCategory: HUDView.Category? = nil

    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSources.dataSource.getAsyncSequenceOfSelectUsersToRemoveViewModel(self, groupIdentifier: groupIdentifier, searchText: searchText)
            if let currentStreamUUID {
                dataSources.dataSource.finishAsyncSequenceOfSelectUsersToRemoveViewModel(self, streamUUID: currentStreamUUID)
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
                cleanupSelectedMembersOnModelUpdate()
            }
            dataSources.dataSource.finishAsyncSequenceOfSelectUsersToRemoveViewModel(self, streamUUID: streamUUID)
            currentStreamUUID = nil
        } catch {
            assertionFailure()
        }
    }
    
    /// Called on each model update.
    /// If we are currently selecting members for deletion, make sure we have not selected a member who no longer is part of the model.
    private func cleanupSelectedMembersOnModelUpdate() {
        guard let streamedModel else { return }
        for memberIdentifier in self.selectedMembers {
            withAnimation {
                if !streamedModel.allOtherGroupMembers.contains(memberIdentifier) {
                    self.selectedMembers.remove(memberIdentifier)
                }
            }
        }
    }
    
    
    private func performSearchWith(newSearchText: String?) {
        guard let currentStreamUUID else { return }
        dataSources.dataSource.filterAsyncSequenceOfSelectUsersToRemoveViewModel(self, streamUUID: currentStreamUUID, searchText: newSearchText)
    }
    

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(AppTheme.shared.colorScheme.systemBackground)
                    .edgesIgnoringSafeArea(.all)
                if let streamedModel {
                    InternalView(model: streamedModel,
                                 selectedMembers: $selectedMembers,
                                 isSearchInProgress: $isSearchInProgress,
                                 singleGroupMembersListViewDataSources: dataSources.singleGroupMembersListViewDataSources,
                                 internalActions: self)
                    .searchable(text: $searchText, placement: .automatic, prompt: Text("Search"))
                    .onChange(of: searchText) { newSearchText in performSearchWith(newSearchText: newSearchText) }
                    if isSearchInProgress && streamedModel.filteredOtherGroupMembers.isEmpty {
                        ObvContentUnavailableView.search
                    }
                } else {
                    ObvCenteredProgressView()
                }
                if let hudCategory = self.hudCategory {
                    HUDView(category: hudCategory)
                }
            }
            .task(onTask)
            .navigationTitle(String(localizedInThisBundle: "TITLE_REMOVE_GROUP_MEMBERS"))
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isInterfaceDisabled)
        }
    }
    
}


extension SelectUsersToRemoveView: SelectUsersToRemoveInternalViewActions {
    
    func userConfirmedSelectedMembersToRemoveFromGroup() {
        guard !selectedMembers.isEmpty else { assertionFailure(); return }
        isInterfaceDisabled = true
        withAnimation { hudCategory = .progress }
        Task {
            do {
                try await actions.userWantsToRemoveMembersFromGroup(self, groupIdentifier: groupIdentifier, membersToRemove: selectedMembers)
                withAnimation { hudCategory = .checkmark }
                try? await Task.sleep(seconds: 1)
                navigation.selectUsersToRemoveViewShouldBeDismissed(self)
            } catch {
                assertionFailure()
                isInterfaceDisabled = false
            }
        }
    }
    
}


@MainActor
protocol SelectUsersToRemoveInternalViewActions {
    func userConfirmedSelectedMembersToRemoveFromGroup()
}


extension SelectUsersToRemoveView{
    struct InternalView: View {

        let model: Model
        @Binding var selectedMembers: Set<SingleGroupMemberView.Model.Identifier>
        @Binding var isSearchInProgress: Bool
        let singleGroupMembersListViewDataSources: SingleGroupMembersListView.DataSources
        let internalActions: SelectUsersToRemoveInternalViewActions
        
        @Environment(\.isSearching) var isSearching

        @State private var showGroupMembersRemovalConfirmationAlert = false
        
        var body: some View {
            
            VStack {
                
                ScrollView {
                    ObvCardView(padding: 0) {
                        SingleGroupMembersListView(
                            model: .init(groupIdentifier: model.groupIdentifier,
                                         mode: .removeMembers(groupIdentifier: model.groupIdentifier),
                                         singleGroupMemberViewModelIdentifiers: model.filteredOtherGroupMembers,
                                         showOwnedIdentity: false,
                                         selectedMembers: $selectedMembers),
                            dataSources: singleGroupMembersListViewDataSources)
                        .padding(.vertical)
                    }
                    .padding(.horizontal)
                    .opacity(model.filteredOtherGroupMembers.isEmpty ? 0.0 : 1.0)
                }
                .onChange(of: isSearching) { newValue in withAnimation { isSearchInProgress = newValue } }
                
                if !selectedMembers.isEmpty {
                    Button(action: { showGroupMembersRemovalConfirmationAlert = true }) {
                        HStack {
                            Spacer(minLength: 0)
                            Text("REMOVE_\(selectedMembers.count)_MEMBERS")
                                .padding(.vertical, 8)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.red)
                    .padding(.horizontal)
                    .padding(.bottom)
                    .transition(.move(edge: .bottom))
                    .alert(String(localizedInThisBundle: "ARE_YOU_SURE_YOU_WANT_TO_REMOVE_THE_\(selectedMembers.count)_SELECTED_MEMBERS"),
                           isPresented: $showGroupMembersRemovalConfirmationAlert) {
                        Button(String(localizedInThisBundle: "REMOVE_GROUP_MEMBER_BUTTON_TITLE"), role: .destructive, action: internalActions.userConfirmedSelectedMembersToRemoveFromGroup)
                    }
                }
                
            }
        }
        
    }
}




// MARK: - Previews

#if DEBUG

private final class DataSourcesForPreviews {
    
    var continuation: AsyncStream<SelectUsersToRemoveView.Model>.Continuation?
    
    let allOtherGroupMembers: [SingleGroupMemberView.Model.Identifier] = SingleGroupMemberView.Model.Identifier.sampleIdentifiers

}

extension DataSourcesForPreviews: SelectUsersToRemoveViewDataSource {
    
    func getAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: SelectUsersToRemoveView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, searchText: String?) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToRemoveView.Model>) {
        let stream = AsyncStream<SelectUsersToRemoveView.Model> { (continuation: AsyncStream<SelectUsersToRemoveView.Model>.Continuation) in
            self.continuation = continuation
            Task {
                try? await Task.sleep(seconds: 2)
                do {
                    let model: SelectUsersToRemoveView.Model = .init(
                        groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
                        allOtherGroupMembers: allOtherGroupMembers,
                        filteredOtherGroupMembers: allOtherGroupMembers)
                    continuation.yield(model)
                }
            }
        }
        return (UUID(), stream)
    }
    
    func filterAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: SelectUsersToRemoveView, streamUUID: UUID, searchText: String?) {
        // Whatever the searchText, we remove members randomly (unless search text is nil)
        let filteredOtherGroupMembers: [SingleGroupMemberView.Model.Identifier]
        if let searchText, !searchText.isEmpty {
            filteredOtherGroupMembers = allOtherGroupMembers.compactMap { Bool.random() ? $0 : nil }
        } else {
            filteredOtherGroupMembers = allOtherGroupMembers
        }
        let model: SelectUsersToRemoveView.Model = .init(
            groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
            allOtherGroupMembers: allOtherGroupMembers,
            filteredOtherGroupMembers: filteredOtherGroupMembers)
        continuation?.yield(model)
    }
    
    func finishAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: SelectUsersToRemoveView, streamUUID: UUID) {}
    
    
}


extension DataSourcesForPreviews: OwnedIdentityAsGroupMemberViewDataSource {
    
    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: OwnedIdentityAsGroupMemberView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityAsGroupMemberViewModel>) {
        let stream = AsyncStream<OwnedIdentityAsGroupMemberViewModel> { (continuation: AsyncStream<OwnedIdentityAsGroupMemberViewModel>.Continuation) in
            Task {
                let model = OwnedIdentityAsGroupMemberViewModel.sampleData
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: OwnedIdentityAsGroupMemberView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, streamUUID: UUID) {}
    
}


extension DataSourcesForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try? await Task.sleep(seconds: 1)
        return PreviewsHelper.profilePictureForURL[photoURL]
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
    func fetchAvatarForLegacyViews(photoURL: URL, avatarSize: ObvAvatarSize) async throws -> UIImage? {
        try? await Task.sleep(seconds: 1)
        return PreviewsHelper.profilePictureForURL[photoURL]
    }
    
    func fetchAvatarFromCacheForLegacyViews(photoURL: URL, avatarSize: ObvAvatarSize) -> UIImage? {
        return nil
    }
    
}


extension DataSourcesForPreviews: SingleGroupMemberViewDataSource {
    
    func getAsyncSequenceOfSingleGroupMemberViewModels(_ view: SingleGroupMemberView, withIdentifier identifier: SingleGroupMemberView.Model.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupMemberView.Model>) {
        let stream = AsyncStream<SingleGroupMemberView.Model> { (continuation: AsyncStream<SingleGroupMemberView.Model>.Continuation) in
            Task {
                let model = SingleGroupMemberView.Model.sampleDataForIdentifier(identifier)
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfSingleGroupMemberViewModels(_ view: SingleGroupMemberView, withIdentifier identifier: SingleGroupMemberView.Model.Identifier, streamUUID: UUID) {}
    
}


extension DataSourcesForPreviews: SelectUsersToRemoveViewActions {
    
    func userWantsToRemoveMembersFromGroup(_ view: SelectUsersToRemoveView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, membersToRemove: Set<SingleGroupMemberView.Model.Identifier>) async throws {
        print("User wants to remove \(membersToRemove.count) members from the group")
    }
    
}

extension DataSourcesForPreviews: SelectUsersToRemoveViewNavigation {
    func selectUsersToRemoveViewShouldBeDismissed(_ view: SelectUsersToRemoveView) {}
}

@MainActor
private let dataSourcesForPreviews = DataSourcesForPreviews()

#Preview {
    SelectUsersToRemoveView(groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
                            dataSources: .init(
                                dataSource: dataSourcesForPreviews,
                                ownedIdentityAsGroupMemberViewDataSource: dataSourcesForPreviews,
                                avatarViewDataSource: dataSourcesForPreviews,
                                singleGroupMemberViewDataSource: dataSourcesForPreviews),
                            actions: dataSourcesForPreviews,
                            navigation: dataSourcesForPreviews)
}

#endif
