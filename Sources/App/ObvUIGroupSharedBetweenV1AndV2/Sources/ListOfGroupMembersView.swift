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


// MARK: - Subview: ListOfGroupMembersView

@MainActor
public protocol ListOfGroupMembersViewDataSource {
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(_ view: ListOfGroupMembersView, groupIdentifier: ObvGroupIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>)
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: ListOfGroupMembersView, streamUUID: UUID, searchText: String?)
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: ListOfGroupMembersView, streamUUID: UUID)
}


@MainActor
public protocol ListOfGroupMembersViewNavigation: SingleGroupMemberViewNavigation {
    func userWantsToNavigateToFullListOfOtherGroupMembers(_ view: ListOfGroupMembersView, groupIdentifier: ObvGroupIdentifier) async
}


public struct ListOfSingleGroupMemberViewModel: Sendable, Equatable {
    
    public let otherGroupMembers: [SingleGroupMemberView.Model.Identifier]
    
    public init(otherGroupMembers: [SingleGroupMemberView.Model.Identifier]) {
        self.otherGroupMembers = otherGroupMembers
    }
    
}

public struct ListOfGroupMembersView: View {

    let groupIdentifier: ObvGroupIdentifier
    let maximumNumberOfGroupMembersShown: Int?
    let dataSource: ListOfGroupMembersViewDataSource
    let subDataSources: SubDataSources
    let actions: SingleGroupMemberViewActionsProtocol
    let navigation: ListOfGroupMembersViewNavigation
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
    
    public struct SubDataSources {
        let ownedIdentityAsGroupMemberViewDataSource: OwnedIdentityAsGroupMemberViewDataSource
        let singleGroupMemberViewDataSource: SingleGroupMemberViewDataSource
        let avatarViewDataSource: ObvAvatarViewDataSource
        let selectUsersToAddViewDataSource: SelectUsersToAddViewDataSource
        let listOfUsersViewCellDataSource: ListOfUsersViewCellDataSource
        let singleGroupMembersListViewDataSources: SingleGroupMembersListView.DataSources
        public init(ownedIdentityAsGroupMemberViewDataSource: OwnedIdentityAsGroupMemberViewDataSource,
                    singleGroupMemberViewDataSource: SingleGroupMemberViewDataSource,
                    avatarViewDataSource: ObvAvatarViewDataSource,
                    selectUsersToAddViewDataSource: SelectUsersToAddViewDataSource,
                    listOfUsersViewCellDataSource: ListOfUsersViewCellDataSource) {
            self.ownedIdentityAsGroupMemberViewDataSource = ownedIdentityAsGroupMemberViewDataSource
            self.singleGroupMemberViewDataSource = singleGroupMemberViewDataSource
            self.avatarViewDataSource = avatarViewDataSource
            self.selectUsersToAddViewDataSource = selectUsersToAddViewDataSource
            self.listOfUsersViewCellDataSource = listOfUsersViewCellDataSource
            self.singleGroupMembersListViewDataSources = .init(
                ownedIdentityAsGroupMemberViewDataSource: ownedIdentityAsGroupMemberViewDataSource,
                avatarViewDataSource: avatarViewDataSource,
                singleGroupMemberViewDataSource: singleGroupMemberViewDataSource)
        }
    }
    
  
    public init(groupIdentifier: ObvGroupIdentifier,
                maximumNumberOfGroupMembersShown: Int?,
                dataSource: ListOfGroupMembersViewDataSource,
                subDataSources: SubDataSources,
                actions: SingleGroupMemberViewActionsProtocol,
                navigation: ListOfGroupMembersViewNavigation,
                uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet) {
        self.groupIdentifier = groupIdentifier
        self.dataSource = dataSource
        self.subDataSources = subDataSources
        self.actions = actions
        self.navigation = navigation
        self.maximumNumberOfGroupMembersShown = maximumNumberOfGroupMembersShown
        self.uiKitDelegateForSwiftUISheet = uiKitDelegateForSwiftUISheet
    }
    

    @State private var model: ListOfSingleGroupMemberViewModel?
    @State private var streamUUID: UUID?
    
    private func onAppear() {
        Task {
            let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(self, groupIdentifier: groupIdentifier)
            if let previousStreamUUID = self.streamUUID {
                dataSource.finishAsyncSequenceOfListOfSingleGroupMemberViewModel(self, streamUUID: previousStreamUUID)
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
            dataSource.finishAsyncSequenceOfListOfSingleGroupMemberViewModel(self, streamUUID: previousStreamUUID)
            self.streamUUID = nil
        }
    }
    
    
    public var body: some View {
        InternalView(groupIdentifier: groupIdentifier,
                     maximumNumberOfGroupMembersShown: maximumNumberOfGroupMembersShown,
                     model: model,
                     dataSource: dataSource,
                     subDataSources: subDataSources,
                     actions: self,
                     selectUsersToAddViewActionsForEdition: actions,
                     singleGroupMemberViewActionsProtocol: actions,
                     navigation: navigation,
                     uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
            .onDisappear(perform: onDisappear)
            .onAppear(perform: onAppear)
    }
    
    
    private struct InternalView: View {
        
        let groupIdentifier: ObvGroupIdentifier
        let maximumNumberOfGroupMembersShown: Int?
        let model: ListOfSingleGroupMemberViewModel?
        let dataSource: ListOfGroupMembersViewDataSource
        let subDataSources: ListOfGroupMembersView.SubDataSources
        let actions: InternalViewActions
        let selectUsersToAddViewActionsForEdition: any SelectUsersToAddViewActionsForEdition
        let singleGroupMemberViewActionsProtocol: SingleGroupMemberViewActionsProtocol
        let navigation: ListOfGroupMembersViewNavigation
        let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
        
        private let leadingPaddingForDivider: CGFloat = 70.0

        private func applyLimitOnMaxNumberOfGroupMembersShown(otherGroupMembers: [SingleGroupMemberView.Model.Identifier]) -> [SingleGroupMemberView.Model.Identifier] {
            if let maximumNumberOfGroupMembersShown {
                return [SingleGroupMemberView.Model.Identifier](otherGroupMembers.prefix(maximumNumberOfGroupMembersShown))
            } else {
                return otherGroupMembers
            }
        }
        
        private func userTappedShowAllGroupMembersButton() {
            actions.userWantsToNavigateToFullListOfOtherGroupMembers(groupIdentifier: groupIdentifier)
        }
        
        var body: some View {
            if let model {
                if model.otherGroupMembers.isEmpty {
                    
                    VStack {
                        
                        HStack {
                            Text("GROUP_MEMBERS_TITLE_WHEN_NO_OTHER_MEMBER")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.bold)
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                        }

                        ObvCardView(padding: 0) {
                            VStack {
                                OwnedIdentityAsGroupMemberView(groupIdentifier: groupIdentifier,
                                                               dataSource: subDataSources.ownedIdentityAsGroupMemberViewDataSource,
                                                               avatarViewDataSource: subDataSources.avatarViewDataSource)
                                    .padding(.horizontal)
                                    .padding(.vertical, 4)
                                Divider()
                                    .padding(.leading, leadingPaddingForDivider)
                                ButtonToAddMembersToThisGroup(
                                    groupIdentifier: groupIdentifier,
                                    actions: selectUsersToAddViewActionsForEdition,
                                    selectUsersToAddViewDataSource: subDataSources.selectUsersToAddViewDataSource,
                                    listOfUsersViewCellDataSource: subDataSources.listOfUsersViewCellDataSource,
                                    avatarViewDataSource: subDataSources.avatarViewDataSource,
                                    uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
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
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                        }
                        
                        ObvCardView(padding: 0) {
                            VStack {
                                SingleGroupMembersListView(
                                    model: .init(groupIdentifier: groupIdentifier,
                                                 mode: .listMembers(groupIdentifier: groupIdentifier,
                                                                    commonActions: singleGroupMemberViewActionsProtocol,
                                                                    navigation: navigation),
                                                 singleGroupMemberViewModelIdentifiers: applyLimitOnMaxNumberOfGroupMembersShown(otherGroupMembers: model.otherGroupMembers),
                                                 showOwnedIdentity: true),
                                    dataSources: subDataSources.singleGroupMembersListViewDataSources)
                                if let maximumNumberOfGroupMembersShown, model.otherGroupMembers.count > maximumNumberOfGroupMembersShown {
                                    Divider()
                                        .padding(.leading, leadingPaddingForDivider)
                                    ShowAllGroupMembersButton(action: userTappedShowAllGroupMembersButton)
                                }
                            }
                            .padding(.vertical)
                        }
                        
                    }
                }
            } else {
                ProgressView()
            }
        }
        
    }
    
}


private struct ShowAllGroupMembersButton: View {
    
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                Text("SHOW_ALL_GROUP_MEMBERS")
                Spacer()
            }
            .padding(.top, 4)
            .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped (trick)
        }
    }
}


extension ListOfGroupMembersView: InternalViewActions {
    
    func userWantsToNavigateToFullListOfOtherGroupMembers(groupIdentifier: ObvGroupIdentifier) {
        Task {
            await navigation.userWantsToNavigateToFullListOfOtherGroupMembers(self, groupIdentifier: groupIdentifier)
        }
    }
    
}


struct ButtonToAddMembersToThisGroup: View {
    
    let groupIdentifier: ObvGroupIdentifier
    let actions: any SelectUsersToAddViewActionsForEdition
    let selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource
    let listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource
    let avatarViewDataSource: any ObvAvatarViewDataSource
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
    
    @State private var isSelectUsersToAddViewPresented: Bool = false
    
    private func buttonTapped() {
        isSelectUsersToAddViewPresented = true
    }
    
    var body: some View {
        Button(action: buttonTapped) {
            HStack {
                Spacer(minLength: 0)
                Text("ADD_MEMBERS_TO_THIS_GROUP_BUTTON_TITLE")
                Spacer(minLength: 0)
            }.padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isSelectUsersToAddViewPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
            NavigationStack {
                SelectUsersToAddView(mode: .edition(groupIdentifier: groupIdentifier,
                                                    actions: actions,
                                                    navigation: self),
                                     dataSource: selectUsersToAddViewDataSource,
                                     listOfUsersViewCellDataSource: listOfUsersViewCellDataSource,
                                     avatarViewDataSource: avatarViewDataSource)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        ObvButtonWithCancelRole(action: { isSelectUsersToAddViewPresented = false })
                    }
                }
            }
        }
    }
}


extension ButtonToAddMembersToThisGroup: SelectUsersToAddViewNavigationForEdition {
    
    func viewShouldBeDismissed(_ view: SelectUsersToAddView.InternalView) {
        isSelectUsersToAddViewPresented = false
    }
        
}


@MainActor
private protocol InternalViewActions {
    func userWantsToNavigateToFullListOfOtherGroupMembers(groupIdentifier: ObvGroupIdentifier)
}
