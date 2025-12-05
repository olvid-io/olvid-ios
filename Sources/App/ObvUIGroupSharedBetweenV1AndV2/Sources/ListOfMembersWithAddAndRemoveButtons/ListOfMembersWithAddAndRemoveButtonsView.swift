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
public protocol ListOfMembersWithAddAndRemoveButtonsViewDataSource {
    func getAsyncSequenceOfListOfMembersWithAddAndRemoveButtonsViewModel(_ view: ListOfMembersWithAddAndRemoveButtonsView, groupIdentifier: ObvGroupIdentifier, searchText: String?) async throws -> (streamUUID: UUID, stream: AsyncStream<ListOfMembersWithAddAndRemoveButtonsView.Model>)
    func filterAsyncSequenceOfListOfMembersWithAddAndRemoveButtonsViewModel(_ view: ListOfMembersWithAddAndRemoveButtonsView, streamUUID: UUID, searchText: String?)
    func finishAsyncSequenceOfListOfMembersWithAddAndRemoveButtonsViewModel(_ view: ListOfMembersWithAddAndRemoveButtonsView, streamUUID: UUID)
}

@MainActor
public protocol ListOfMembersWithAddAndRemoveButtonsViewActions: AddAndRemoveMembersButtonsViewActions, SingleGroupMemberViewActionsProtocol {
    
}

@MainActor
public protocol ListOfMembersWithAddAndRemoveButtonsViewNavigation: SingleGroupMemberViewNavigation {}

/// A view that displays the members of a group, typically pushed on the navigation stack when a group admin taps the **"Members"** button in the administration panel.
///
/// The view consists of:
/// - Two action buttons at the top:
///   - One to present a view for adding new members.
///   - One to present a view for removing members from the group.
/// - A list of all group members, with the current user displayed as the first item.
public struct ListOfMembersWithAddAndRemoveButtonsView: View {
    
    let groupIdentifier: ObvGroupIdentifier
    let dataSources: DataSources
    let actions: any ListOfMembersWithAddAndRemoveButtonsViewActions
    let navigation: any ListOfMembersWithAddAndRemoveButtonsViewNavigation
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet

    public init(groupIdentifier: ObvGroupIdentifier,
                dataSources: DataSources,
                actions: any ListOfMembersWithAddAndRemoveButtonsViewActions,
                navigation: any ListOfMembersWithAddAndRemoveButtonsViewNavigation,
                uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet) {
        self.groupIdentifier = groupIdentifier
        self.dataSources = dataSources
        self.actions = actions
        self.navigation = navigation
        self.uiKitDelegateForSwiftUISheet = uiKitDelegateForSwiftUISheet
    }

    public struct Model: Sendable, Equatable {
        let groupIdentifier: ObvGroupIdentifier
        let allOtherGroupMembers: [SingleGroupMemberView.Model.Identifier]
        let isGroupV2UpdateInProgress: Bool // Always false for a group v1
        
        public init(groupIdentifier: ObvGroupIdentifier, allOtherGroupMembers: [SingleGroupMemberView.Model.Identifier], isGroupV2UpdateInProgress: Bool) {
            self.groupIdentifier = groupIdentifier
            self.allOtherGroupMembers = allOtherGroupMembers
            self.isGroupV2UpdateInProgress = isGroupV2UpdateInProgress
        }
    }
    
    public struct DataSources {
        let dataSource: any ListOfMembersWithAddAndRemoveButtonsViewDataSource
        let addAndRemoveMembersButtonsViewDataSources: AddAndRemoveMembersButtonsView.DataSources
        let singleGroupMembersListViewDataSources: SingleGroupMembersListView.DataSources
        
        public init(dataSource: any ListOfMembersWithAddAndRemoveButtonsViewDataSource,
                    addAndRemoveMembersButtonsViewDataSources: AddAndRemoveMembersButtonsView.DataSources,
                    singleGroupMembersListViewDataSources: SingleGroupMembersListView.DataSources) {
            self.dataSource = dataSource
            self.addAndRemoveMembersButtonsViewDataSources = addAndRemoveMembersButtonsViewDataSources
            self.singleGroupMembersListViewDataSources = singleGroupMembersListViewDataSources
        }
    }

    @State private var streamedModel: Model?
    @State private var currentStreamUUID: UUID? // Required to perform search
    @State private var searchText: String = ""
    @State private var isSearchInProgress: Bool = false

    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSources.dataSource.getAsyncSequenceOfListOfMembersWithAddAndRemoveButtonsViewModel(self, groupIdentifier: groupIdentifier, searchText: searchText.mapToNilIfZeroLength())
            if let currentStreamUUID {
                dataSources.dataSource.finishAsyncSequenceOfListOfMembersWithAddAndRemoveButtonsViewModel(self, streamUUID: currentStreamUUID)
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
            dataSources.dataSource.finishAsyncSequenceOfListOfMembersWithAddAndRemoveButtonsViewModel(self, streamUUID: streamUUID)
            currentStreamUUID = nil
        } catch {
            assertionFailure()
        }
    }

    
    private func performSearchWith(newSearchText: String?) {
        guard let currentStreamUUID else { return }
        dataSources.dataSource.filterAsyncSequenceOfListOfMembersWithAddAndRemoveButtonsViewModel(self, streamUUID: currentStreamUUID, searchText: newSearchText)
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
                             navigation: navigation,
                             uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                .onChange(of: searchText) { newSearchText in performSearchWith(newSearchText: newSearchText) }
                if isSearchInProgress && streamedModel.allOtherGroupMembers.isEmpty {
                    ObvContentUnavailableView.search
                }
            } else {
                ObvCenteredProgressView()
            }
        }
        .task(onTask)
        .navigationTitle(String(localizedInThisBundle: "TITLE_MANAGE_GROUP_MEMBERS"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search"))
    }
    
}

extension ListOfMembersWithAddAndRemoveButtonsView: ListOfMembersWithAddAndRemoveButtonsViewInternalActions {
    
    public func userWantsToAddSelectedUsersToExistingGroup(_ view: SelectUsersToAddView.InternalView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) async throws {
        try await actions.userWantsToAddSelectedUsersToExistingGroup(view, groupIdentifier: groupIdentifier, withIdentifiers: userIdentifiers)
    }
    
    public func userWantsToRemoveMembersFromGroup(_ view: SelectUsersToRemoveView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, membersToRemove: Set<SingleGroupMemberView.Model.Identifier>) async throws {
        try await actions.userWantsToRemoveMembersFromGroup(view, groupIdentifier: groupIdentifier, membersToRemove: membersToRemove)
    }
    
}

// MARK: - Internal view

@MainActor
protocol ListOfMembersWithAddAndRemoveButtonsViewInternalActions: AddAndRemoveMembersButtonsViewActions, SingleGroupMemberViewActionsProtocol {}

extension ListOfMembersWithAddAndRemoveButtonsView {
    struct InternalView: View {
        
        let groupIdentifier: ObvGroupIdentifier
        @Binding var isSearchInProgress: Bool
        let model: Model
        let dataSources: DataSources
        let actions: ListOfMembersWithAddAndRemoveButtonsViewInternalActions
        let navigation: any ListOfMembersWithAddAndRemoveButtonsViewNavigation
        let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet

        @Environment(\.isSearching) var isSearching

        private let leadingPaddingForDivider: CGFloat = 70.0

        var body: some View {
            ScrollView {
                VStack {
                    
                    if model.isGroupV2UpdateInProgress {
                        UpdateInProgressView()
                            .padding()
                    }
                    
                    ObvCardView(padding: 0) {
                        
                        VStack {
                            
                            if !isSearchInProgress {
                                
                                AddAndRemoveMembersButtonsView(
                                    groupIdentifier: groupIdentifier,
                                    dataSources: dataSources.addAndRemoveMembersButtonsViewDataSources,
                                    actions: actions,
                                    uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                                
                                Divider()
                                    .padding(.leading, leadingPaddingForDivider)
                                
                            }
                            
                            SingleGroupMembersListView(
                                model: .init(groupIdentifier: model.groupIdentifier,
                                             mode: .listMembers(groupIdentifier: groupIdentifier,
                                                                commonActions: actions,
                                                                navigation: navigation),
                                             singleGroupMemberViewModelIdentifiers: model.allOtherGroupMembers,
                                             showOwnedIdentity: !isSearchInProgress),
                                dataSources: dataSources.singleGroupMembersListViewDataSources)
                            
                        }
                        .padding(.vertical)
                        
                    }
                    .padding(.horizontal)
                    .opacity(isSearchInProgress && model.allOtherGroupMembers.isEmpty ? 0.0 : 1.0)
                    
                }
                    
            }
            .onChange(of: isSearching) { newValue in withAnimation { isSearchInProgress = newValue } }
        }
        
    }
}


// MARK: - Internal view: AddAndRemoveMembersButtonsView

@MainActor
public protocol AddAndRemoveMembersButtonsViewActions: SelectUsersToAddViewActionsForEdition, SelectUsersToRemoveViewActions {
    
}

public struct AddAndRemoveMembersButtonsView: View {
    
    let groupIdentifier: ObvGroupIdentifier
    let dataSources: DataSources
    let actions: any AddAndRemoveMembersButtonsViewActions
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet

    public struct DataSources {
        let selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource
        let listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        let selectUsersToRemoveViewDataSources: SelectUsersToRemoveView.DataSources
        
        public init(selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource,
             listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource,
             avatarViewDataSource: any ObvAvatarViewDataSource,
             selectUsersToRemoveViewDataSources: SelectUsersToRemoveView.DataSources) {
            self.selectUsersToAddViewDataSource = selectUsersToAddViewDataSource
            self.listOfUsersViewCellDataSource = listOfUsersViewCellDataSource
            self.avatarViewDataSource = avatarViewDataSource
            self.selectUsersToRemoveViewDataSources = selectUsersToRemoveViewDataSources
        }
    }
    
    private let circleDiameter: CGFloat = ObvDesignSystem.ObvAvatarSize.normal.frameSize.width
    
    @State private var isSelectUsersToAddViewPresented: Bool = false
    @State private var isRemoveMembersViewPresented: Bool = false
    
    private var selectUsersToAddViewMode: SelectUsersToAddView.Mode {
        .edition(groupIdentifier: groupIdentifier,
                 actions: actions,
                 navigation: self)
    }
    
    public var body: some View {
        VStack {
            Button(action: { isSelectUsersToAddViewPresented = true }) {
                HStack {
                    InitialCircleView(model: .init(content: .init(text: nil, icon: .personFillBadgePlus),
                                                   colors: .init(background: .systemFill,
                                                                 foreground: .secondaryLabel),
                                                   circleDiameter: circleDiameter))
                    Text("GROUP_MEMBERS_ADD")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            Divider()
                .padding(.leading, 70)
            
            Button(role: .destructive, action: { isRemoveMembersViewPresented = true }) {
                HStack {
                    InitialCircleView(model: .init(content: .init(text: nil, icon: .personFillBadgeMinus),
                                                   colors: .init(background: .systemFill,
                                                                 foreground: .secondaryLabel),
                                                   circleDiameter: circleDiameter))
                    Text("GROUP_MEMBERS_REMOVE")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
            }
                                
        }
        .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isSelectUsersToAddViewPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
            NavigationStack {
                SelectUsersToAddView(mode: selectUsersToAddViewMode,
                                     dataSource: dataSources.selectUsersToAddViewDataSource,
                                     listOfUsersViewCellDataSource: dataSources.listOfUsersViewCellDataSource,
                                     avatarViewDataSource: dataSources.avatarViewDataSource)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        ObvButtonWithCancelRole(action: { isSelectUsersToAddViewPresented = false })
                    }
                }
            }
        }
        .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isRemoveMembersViewPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
            NavigationStack {
                SelectUsersToRemoveView(groupIdentifier: groupIdentifier,
                                        dataSources: dataSources.selectUsersToRemoveViewDataSources,
                                        actions: actions,
                                        navigation: self)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        ObvButtonWithCancelRole(action: { isRemoveMembersViewPresented = false })
                    }
                }
            }
        }
    }
}


extension AddAndRemoveMembersButtonsView: SelectUsersToAddViewNavigationForEdition {
    
    public func viewShouldBeDismissed(_ view: SelectUsersToAddView.InternalView) {
        isSelectUsersToAddViewPresented = false
    }
    
}


extension AddAndRemoveMembersButtonsView: SelectUsersToRemoveViewNavigation {
    
    public func selectUsersToRemoveViewShouldBeDismissed(_ view: SelectUsersToRemoveView) {
        isRemoveMembersViewPresented = false
    }
    
}


// MARK: - Previews

#if DEBUG

@MainActor
private let genericDataSourceForPreviews = GenericDataSourceAndActionsForPreviews()


#Preview {
    NavigationStack {
        ListOfMembersWithAddAndRemoveButtonsView(
            groupIdentifier: .sampleData,
            dataSources: .init(dataSource: genericDataSourceForPreviews,
                               addAndRemoveMembersButtonsViewDataSources: .init(
                                selectUsersToAddViewDataSource: genericDataSourceForPreviews,
                                listOfUsersViewCellDataSource: genericDataSourceForPreviews,
                                avatarViewDataSource: genericDataSourceForPreviews,
                                selectUsersToRemoveViewDataSources: .init(
                                    dataSource: genericDataSourceForPreviews,
                                    ownedIdentityAsGroupMemberViewDataSource: genericDataSourceForPreviews,
                                    avatarViewDataSource: genericDataSourceForPreviews,
                                    singleGroupMemberViewDataSource: genericDataSourceForPreviews)),
                               singleGroupMembersListViewDataSources: .init(
                                ownedIdentityAsGroupMemberViewDataSource: genericDataSourceForPreviews,
                                avatarViewDataSource: genericDataSourceForPreviews,
                                singleGroupMemberViewDataSource: genericDataSourceForPreviews)),
            actions: genericDataSourceForPreviews,
            navigation: genericDataSourceForPreviews,
            uiKitDelegateForSwiftUISheet: genericDataSourceForPreviews)
    }
}

#endif
