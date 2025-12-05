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
import ObvTypes
import ObvDesignSystem
import ObvAppTypes
import ObvUIGroupSharedBetweenV1AndV2


@MainActor
public protocol FullListOfGroupMembersViewDataSource {
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(_ view: FullListOfGroupMembersView, creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, userIdentifiersOfAddedUsers: [SelectUsersToAddViewModel.User.Identifier]) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel>)
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(_ view: FullListOfGroupMembersView.InternalView, streamUUID: UUID, userIdentifiersOfAddedUsers: [SelectUsersToAddViewModel.User.Identifier], searchText: String?)
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(_ view: FullListOfGroupMembersView, streamUUID: UUID)
    
    func getAsyncSequenceOfListOfSingleGroupAdminsMemberViewModelForExistingGroup(_ view: FullListOfGroupMembersView, groupIdentifier: ObvGroupV2Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>)
    func finishAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(_ view: FullListOfGroupMembersView, streamUUID: UUID)

    func getAsyncSequenceOfGroupLightweightModelForExistingGroup(_ view: FullListOfGroupMembersView, groupIdentifier: ObvGroupV2Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvGroupLightweightModel>)
    func finishAsyncSequenceOfGroupLightweightModelForExistingGroup(_ view: FullListOfGroupMembersView, groupIdentifier: ObvGroupV2Identifier, streamUUID: UUID)
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(_ view: FullListOfGroupMembersView, groupIdentifier: ObvGroupV2Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>)
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: FullListOfGroupMembersView.InternalView, streamUUID: UUID, searchText: String?)
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: FullListOfGroupMembersView, streamUUID: UUID)

}

@MainActor
public protocol FullListOfGroupMembersViewNavigationDuringEdition {
    func hudWasDismissedAfterSuccessfulGroupEdition(_ view: FullListOfGroupMembersView.InternalView, groupIdentifier: ObvGroupV2Identifier)
}

@MainActor
public protocol FullListOfGroupMembersViewNavigationDuringCreation {
    func userConfirmedTheAdminsChoiceDuringGroupCreationAndWantsToNavigateToNextScreen(_ view: FullListOfGroupMembersView.InternalView, creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId)
}

public protocol FullListOfGroupMembersViewActionsInEditAdminsMode {
    func userWantsToUpdateGroupV2(_ view: FullListOfGroupMembersView.InternalView, groupIdentifier: ObvGroupV2Identifier, changeset: ObvGroupV2.Changeset) async throws
}

public protocol FullListOfGroupMembersViewActionsForCreation: SingleGroupMemberViewActionsDuringCreation {
    func getGroupLightweightModelDuringGroupCreation(_ view: FullListOfGroupMembersView, creationSessionUUID: UUID) throws -> ObvGroupLightweightModel
}

public struct FullListOfGroupMembersView: View {
    
    let mode: Mode
    let dataSource: any FullListOfGroupMembersViewDataSource
    let subDataSources: SubDataSources
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet

    public init(mode: Mode,
                dataSource: any FullListOfGroupMembersViewDataSource,
                subDataSources: SubDataSources,
                uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet) {
        self.mode = mode
        self.dataSource = dataSource
        self.subDataSources = subDataSources
        self.uiKitDelegateForSwiftUISheet = uiKitDelegateForSwiftUISheet
    }
        
    public struct SubDataSources {
        let singleGroupMemberViewDataSource: any SingleGroupMemberViewDataSource
        let selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource
        let listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource
        let ownedIdentityAsGroupMemberViewDataSource: any OwnedIdentityAsGroupMemberViewDataSource
        let avatarViewDataSource: ObvAvatarViewDataSource
        let listOfGroupMembersViewDataSource: any ListOfGroupMembersViewDataSource
        let selectUsersToRemoveViewDataSource: any SelectUsersToRemoveViewDataSource
        
        let selectUsersToRemoveViewDataSources: SelectUsersToRemoveView.DataSources
        
        public init(singleGroupMemberViewDataSource: any SingleGroupMemberViewDataSource,
                    selectUsersToAddViewDataSource: any SelectUsersToAddViewDataSource,
                    listOfUsersViewCellDataSource: any ListOfUsersViewCellDataSource,
                    ownedIdentityAsGroupMemberViewDataSource: any OwnedIdentityAsGroupMemberViewDataSource,
                    avatarViewDataSource: ObvAvatarViewDataSource,
                    listOfGroupMembersViewDataSource: any ListOfGroupMembersViewDataSource,
                    selectUsersToRemoveViewDataSource: any SelectUsersToRemoveViewDataSource) {
            self.singleGroupMemberViewDataSource = singleGroupMemberViewDataSource
            self.selectUsersToAddViewDataSource = selectUsersToAddViewDataSource
            self.listOfUsersViewCellDataSource = listOfUsersViewCellDataSource
            self.ownedIdentityAsGroupMemberViewDataSource = ownedIdentityAsGroupMemberViewDataSource
            self.avatarViewDataSource = avatarViewDataSource
            self.listOfGroupMembersViewDataSource = listOfGroupMembersViewDataSource
            self.selectUsersToRemoveViewDataSource = selectUsersToRemoveViewDataSource
            self.selectUsersToRemoveViewDataSources = .init(
                dataSource: selectUsersToRemoveViewDataSource,
                ownedIdentityAsGroupMemberViewDataSource: ownedIdentityAsGroupMemberViewDataSource,
                avatarViewDataSource: avatarViewDataSource,
                singleGroupMemberViewDataSource: singleGroupMemberViewDataSource)
        }
    }

    public enum Mode {
        /// Use this mode when an administrator wants to navigate to the (non-editable) list of admins.
        case administrateAdmins(groupIdentifier: ObvGroupV2Identifier, actions: any SingleGroupMemberViewActionsProtocol & FullListOfGroupMembersViewActionsInEditAdminsMode, navigation: SingleGroupMemberViewNavigation)
        case editAdmins(groupIdentifier: ObvGroupV2Identifier,
                        selectedGroupType: ObvGroupType?, // selectedGroupType is non nil when the user just edited the group type
                        navigation: FullListOfGroupMembersViewNavigationDuringEdition,
                        actions: FullListOfGroupMembersViewActionsInEditAdminsMode)
        case selectAdminsDuringGroupCreation(creationSessionUUID: UUID,
                                             ownedCryptoId: ObvCryptoId,
                                             preSelectedAdmins: Set<SingleGroupMemberView.Model.Identifier>,
                                             userIdentifiersOfAddedUsers: [SelectUsersToAddViewModel.User.Identifier],
                                             actionsForCreation: any FullListOfGroupMembersViewActionsForCreation,
                                             navigation: FullListOfGroupMembersViewNavigationDuringCreation)
    }

    @State private var modelForAll: ListOfSingleGroupMemberViewModel?
    @State private var modelForAllFilteredBySearchText: ListOfSingleGroupMemberViewModel?
    @State private var modelForAdminsOnly: ListOfSingleGroupMemberViewModel?
    @State private var modelForAdminsOnlyFilteredBySearchText: ListOfSingleGroupMemberViewModel?
    @State private var groupLightweightModel: ObvGroupLightweightModel? // Not used during group creation
    
    @State private var streamUUIDForAll: UUID?
    @State private var streamUUIDForAllFilteredBySearchText: UUID?
    @State private var streamUUIDForAdminsOnly: UUID?
    @State private var streamUUIDForAdminsOnlyFilteredBySearchText: UUID?
    @State private var streamUUIDForGroupLightweightModel: UUID? // Not used during group creation
    
    @State private var searchText: String = ""

    @State private var allOrAdminsOnly: AllOrAdminsOnly = .all

    // The following States are used when in `removeMembers` mode
    
    @State private var selectedMembers: Set<SingleGroupMemberView.Model.Identifier> = []
    @State private var hudCategory: HUDView.Category? = nil

    // The following States are used when in `editAdmins` mode
    
    @State private var membersWithUpdatedAdminPermission: Set<MemberIdentifierAndPermissions> = []
    
    fileprivate enum AllOrAdminsOnly {
        case all
        case adminsOnly
    }

    private func onAppear() {
        Task {
            
            guard self.streamUUIDForGroupLightweightModel == nil else { return }
            
            let groupV2Identifier: ObvGroupV2Identifier
            
            switch mode {
            case .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _, navigation: _, actions: _),
                    .administrateAdmins(groupIdentifier: let groupIdentifier, actions: _, navigation: _):
                
                groupV2Identifier = groupIdentifier
                
            case .selectAdminsDuringGroupCreation(creationSessionUUID: let creationSessionUUID, ownedCryptoId: _, preSelectedAdmins: _, userIdentifiersOfAddedUsers: _, actionsForCreation: let actionsForCreation, navigation: _):
                let model = try actionsForCreation.getGroupLightweightModelDuringGroupCreation(self, creationSessionUUID: creationSessionUUID)
                self.groupLightweightModel = model
                return
            }
            
            let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfGroupLightweightModelForExistingGroup(self, groupIdentifier: groupV2Identifier)
            self.streamUUIDForGroupLightweightModel = streamUUID
            for await model in stream {
                withAnimation {
                    self.groupLightweightModel = model
                }
            }

        }
    }

    
    // Also called when displaying a view that does not show the selector between all / admins only
    private func onAppearForAllGroupMembers() {
        Task {
            
            guard self.streamUUIDForAll == nil else { return }

            let groupV2Identifier: ObvGroupV2Identifier // Not the modes selectAdminsDuringGroupCreation, administrateAdmins
            
            switch mode {
                
            case .selectAdminsDuringGroupCreation(creationSessionUUID: let creationSessionUUID, ownedCryptoId: let ownedCryptoId, preSelectedAdmins: _, userIdentifiersOfAddedUsers: let userIdentifiersOfAddedUsers, actionsForCreation: _, navigation: _):
                                
                let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(
                    self,
                    creationSessionUUID: creationSessionUUID,
                    ownedCryptoId: ownedCryptoId,
                    userIdentifiersOfAddedUsers: userIdentifiersOfAddedUsers)
                
                self.streamUUIDForAll = streamUUID
                for await model in stream {
                    withAnimation {
                        self.modelForAll = model
                    }
                }
                
                return
                
            case .administrateAdmins(groupIdentifier: _):
                
                // Since we only show admins in this mode, there is no stream to fetch here. But we force the display of the admin stream
                allOrAdminsOnly = .adminsOnly
                
                return
                
            case .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _, navigation: _, actions: _):
                
                groupV2Identifier = groupIdentifier
                
            }
            
            // We are in the listMembers, administrateMembers, removeMembers, or editAdmins mode
            
            let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(self, groupIdentifier: groupV2Identifier)
            self.streamUUIDForAll = streamUUID
            
            for await model in stream {
                withAnimation {
                    self.modelForAll = model
                }
                cleanupSelectedMembersOnModelUpdate()
            }

        }
        Task {
            
            guard self.streamUUIDForAllFilteredBySearchText == nil else { return }
            
            let streamUUID: UUID
            let stream: AsyncStream<ListOfSingleGroupMemberViewModel>
            
            switch mode {
                
            case .administrateAdmins(groupIdentifier: _):
                
                // Since we only show admins in this mode, there is no stream to fetch here
                return

            case .selectAdminsDuringGroupCreation(creationSessionUUID: let creationSessionUUID, ownedCryptoId: let ownedCryptoId, preSelectedAdmins: _, userIdentifiersOfAddedUsers: let userIdentifiersOfAddedUsers, actionsForCreation: _, navigation: _):
                
                (streamUUID, stream) = try await dataSource.getAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(self, creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId, userIdentifiersOfAddedUsers: userIdentifiersOfAddedUsers)

            case .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _, navigation: _, actions: _):
                
                (streamUUID, stream) = try await dataSource.getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(self, groupIdentifier: groupIdentifier)

            }

            self.streamUUIDForAllFilteredBySearchText = streamUUID
            
            for await model in stream {
                withAnimation {
                    self.modelForAllFilteredBySearchText = model
                }
            }

        }
    }
    
    
    private func onAppearForAdminsOnly() {
        Task {
            guard self.streamUUIDForAdminsOnly == nil else { return }
            
            let groupV2Identifier: ObvGroupV2Identifier
            
            switch mode {

            case .selectAdminsDuringGroupCreation:
                
                // There is no "admin" tab when selecting group admins, so there is nothing to do here
                return
                
            case .administrateAdmins(groupIdentifier: let groupIdentifier, actions: _, navigation: _),
                    .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _, navigation: _, actions: _):
                
                groupV2Identifier = groupIdentifier

            }
            
            let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfListOfSingleGroupAdminsMemberViewModelForExistingGroup(self, groupIdentifier: groupV2Identifier)
            
            self.streamUUIDForAdminsOnly = streamUUID
            
            for await model in stream {
                withAnimation {
                    self.modelForAdminsOnly = model
                }
                cleanupSelectedMembersOnModelUpdate()
            }

        }
        Task {
            guard self.streamUUIDForAdminsOnlyFilteredBySearchText == nil else { return }
            
            let groupV2Identifier: ObvGroupV2Identifier

            switch mode {
                
            case .selectAdminsDuringGroupCreation:
                
                // There is no "admin" tab when selecting group admins, so there is nothing to do here
                return

            case .administrateAdmins(groupIdentifier: let groupIdentifier, actions: _, navigation: _),
                    .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _, navigation: _, actions: _):
                
                groupV2Identifier = groupIdentifier

            }

            let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfListOfSingleGroupAdminsMemberViewModelForExistingGroup(self, groupIdentifier: groupV2Identifier)
            
            self.streamUUIDForAdminsOnlyFilteredBySearchText = streamUUID
            
            for await model in stream {
                withAnimation {
                    self.modelForAdminsOnlyFilteredBySearchText = model
                }
                cleanupSelectedMembersOnModelUpdate()
            }

        }
    }
    
    
    /// Called on each model update.
    /// If we are currently selecting members for deletion, make sure we have not selected a member who no longer is part of the model.
    private func cleanupSelectedMembersOnModelUpdate() {
        guard let modelForAll else { return }
        for memberIdentifier in self.selectedMembers {
            withAnimation {
                if !modelForAll.otherGroupMembers.contains(memberIdentifier) {
                    self.selectedMembers.remove(memberIdentifier)
                }
            }
        }
    }
    
    
    private func onDisappear() {
        if let streamUUID = self.streamUUIDForAll {
            dataSource.finishAsyncSequenceOfListOfSingleGroupMemberViewModel(self, streamUUID: streamUUID)
            self.streamUUIDForAll = nil
        }
        if let streamUUID = self.streamUUIDForAllFilteredBySearchText {
            dataSource.finishAsyncSequenceOfListOfSingleGroupMemberViewModel(self, streamUUID: streamUUID)
            self.streamUUIDForAllFilteredBySearchText = nil
        }
        if let streamUUID = self.streamUUIDForAdminsOnly {
            dataSource.finishAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(self, streamUUID: streamUUID)
            self.streamUUIDForAdminsOnly = nil
        }
        if let streamUUID = self.streamUUIDForAdminsOnlyFilteredBySearchText {
            dataSource.finishAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(self, streamUUID: streamUUID)
            self.streamUUIDForAdminsOnlyFilteredBySearchText = nil
        }
        
        let groupV2Identifier: ObvGroupV2Identifier
        
        switch mode {
            
        case .selectAdminsDuringGroupCreation:
            return
            
        case .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _, navigation: _, actions: _),
                .administrateAdmins(groupIdentifier: let groupIdentifier, actions: _, navigation: _):
            
            groupV2Identifier = groupIdentifier
            
        }
        
        if let streamUUID = self.streamUUIDForGroupLightweightModel {
            dataSource.finishAsyncSequenceOfGroupLightweightModelForExistingGroup(self, groupIdentifier: groupV2Identifier, streamUUID: streamUUID)
            self.streamUUIDForGroupLightweightModel = nil
        }
        
    }


    private var searchablePlacement: SearchFieldPlacement {
        switch mode {
        case .administrateAdmins:
            return .automatic
        case .editAdmins:
            return .automatic
        case .selectAdminsDuringGroupCreation:
            return .automatic
        }
    }
    
    private var navigationTitle: String {
        switch self.mode {
        case .administrateAdmins:
            return String(localizedInThisBundle: "TITLE_EDIT_GROUP_ADMINS")
        case .editAdmins:
            return String(localizedInThisBundle: "TITLE_ADD_REMOVE_GROUP_ADMINS")
        case .selectAdminsDuringGroupCreation:
            return String(localizedInThisBundle: "TITLE_CHOOSE_GROUP_ADMINS")
        }
    }
    
    public var body: some View {
        ZStack {
             
            Color(AppTheme.shared.colorScheme.systemBackground)
                .edgesIgnoringSafeArea(.all)
            InternalView(
                mode: mode,
                dataSource: dataSource,
                subDataSources: subDataSources,
                uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet,
                modelForAll: modelForAll,
                modelForAllFilteredBySearchText: modelForAllFilteredBySearchText,
                modelForAdminsOnly: modelForAdminsOnly,
                modelForAdminsOnlyFilteredBySearchText: modelForAdminsOnlyFilteredBySearchText,
                groupLightweightModel: groupLightweightModel,
                membersWithUpdatedAdminPermission: $membersWithUpdatedAdminPermission,
                selectedMembers: $selectedMembers,
                hudCategory: $hudCategory,
                allOrAdminsOnly: $allOrAdminsOnly,
                streamUUIDForAllFilteredBySearchText: streamUUIDForAllFilteredBySearchText,
                streamUUIDForAdminsOnlyFilteredBySearchText: streamUUIDForAdminsOnlyFilteredBySearchText,
                searchText: searchText,
                onAppearForAllGroupMembers: onAppearForAllGroupMembers,
                onAppearForAdminsOnly: onAppearForAdminsOnly)
                .onAppear(perform: onAppear)
                .onDisappear(perform: onDisappear)
                .searchable(text: $searchText, placement: searchablePlacement, prompt: Text("Search"))

            if groupLightweightModel == nil {
                ProgressView()
            }

            if let hudCategory = self.hudCategory {
                HUDView(category: hudCategory)
            }
            
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    
    public struct InternalView: View {
        
        let mode: FullListOfGroupMembersView.Mode
        let dataSource: FullListOfGroupMembersViewDataSource
        let subDataSources: FullListOfGroupMembersView.SubDataSources
        let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
        let modelForAll: ListOfSingleGroupMemberViewModel?
        let modelForAllFilteredBySearchText: ListOfSingleGroupMemberViewModel?
        let modelForAdminsOnly: ListOfSingleGroupMemberViewModel?
        let modelForAdminsOnlyFilteredBySearchText: ListOfSingleGroupMemberViewModel?
        let groupLightweightModel: ObvGroupLightweightModel?
        @Binding var membersWithUpdatedAdminPermission: Set<MemberIdentifierAndPermissions> // Must be a binding
        @Binding var selectedMembers: Set<SingleGroupMemberView.Model.Identifier> // Must be a binding
        @Binding var hudCategory: HUDView.Category? // Must be a binding
        @Binding fileprivate var allOrAdminsOnly: AllOrAdminsOnly
        let streamUUIDForAllFilteredBySearchText: UUID?
        let streamUUIDForAdminsOnlyFilteredBySearchText: UUID?
        let searchText: String
        let onAppearForAllGroupMembers: () -> Void
        let onAppearForAdminsOnly: () -> Void
        
        @State private var isAdminsPermissionUpdateInProgress: Bool = false
        @State private var isSearchInProgress = false

        // Implementing search
        
        @Environment(\.dismissSearch) private var dismissSearch
        @Environment(\.isSearching) var isSearching

        private func resetAdminsButtonTapped() {
            self.membersWithUpdatedAdminPermission.removeAll()
        }

        private func validateNewAdminsSelectionButtonTapped(groupLightweightModel: ObvGroupLightweightModel) {
            
            dismissSearch()
            
            switch mode {
            case .administrateAdmins:
                
                assertionFailure()
                return
                
            case .selectAdminsDuringGroupCreation(creationSessionUUID: let creationSessionUUID, ownedCryptoId: let ownedCryptoId, preSelectedAdmins: _, userIdentifiersOfAddedUsers: _, actionsForCreation: _, navigation: let navigation):
                
                // During a group creation, each time the user toggles on/off an admin, the choice is immediately saved to the model's router.
                // This is done thanks to the
                //    `func userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(memberIdentifier: SingleGroupMemberViewModelIdentifier, newIsAnAdmin: Bool)`
                // method. For this reason, we don't need to pass the final list of admins here, as it is already known to the router.
                navigation.userConfirmedTheAdminsChoiceDuringGroupCreationAndWantsToNavigateToNextScreen(self, creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId)
                
            case .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: let selectedGroupType, navigation: let navigation, actions: let actions):
                
                let groupTypeToConsider = selectedGroupType ?? groupLightweightModel.groupType ?? .managed
                
                guard let modelForAll else { assertionFailure(); return }
                  
                var changes = Set<ObvGroupV2.Change>()
                
                // Compute the changes due to the member's with updated admin permissions
                
                for memberWithUpdatedAdminPermission in membersWithUpdatedAdminPermission {
                    guard modelForAll.otherGroupMembers.contains(memberWithUpdatedAdminPermission.memberIdentifier) else { continue }
                    let newPermissions: Set<ObvGroupV2.Permission>
                    if memberWithUpdatedAdminPermission.isAdmin {
                        newPermissions = ObvGroupType.exactPermissions(of: .admin, forGroupType: groupTypeToConsider)
                    } else {
                        newPermissions = ObvGroupType.exactPermissions(of: .regularMember, forGroupType: groupTypeToConsider)
                    }
                    changes.insert(.memberChanged(contactCryptoId: memberWithUpdatedAdminPermission.cryptoId, permissions: newPermissions))
                }
                
                // Compute the changes due to a choice of the group type (made in another view)
                
                if let selectedGroupType {
                    guard let serializedGroupType = try? selectedGroupType.toSerializedGroupType() else { assertionFailure(); return }
                    changes.insert(.groupType(serializedGroupType: serializedGroupType))
                }
          
                isAdminsPermissionUpdateInProgress = true
                self.hudCategory = .progress

                Task {
                    defer {
                        isAdminsPermissionUpdateInProgress = false
                        self.hudCategory = nil
                    }
                    do {
                        let changeset = try ObvGroupV2.Changeset(changes: changes)
                        try await actions.userWantsToUpdateGroupV2(self, groupIdentifier: groupIdentifier, changeset: changeset)
                        self.hudCategory = .checkmark
                    } catch {
                        self.hudCategory = .xmark
                    }
                    try? await Task.sleep(seconds: 1) // Give some time to the HUD
                    navigation.hudWasDismissedAfterSuccessfulGroupEdition(self, groupIdentifier: groupIdentifier)
                }

            }
                        
        }

        
        private func performSearchWith(newSearchText: String?) {
            switch mode {
            case .selectAdminsDuringGroupCreation(_, _, _, userIdentifiersOfAddedUsers: let userIdentifiersOfAddedUsers, _, _):
                if let streamUUIDForAllFilteredBySearchText {
                    dataSource.filterAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(self, streamUUID: streamUUIDForAllFilteredBySearchText, userIdentifiersOfAddedUsers: userIdentifiersOfAddedUsers, searchText: newSearchText)
                }
                if let streamUUIDForAdminsOnlyFilteredBySearchText {
                    dataSource.filterAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(self, streamUUID: streamUUIDForAdminsOnlyFilteredBySearchText, userIdentifiersOfAddedUsers: userIdentifiersOfAddedUsers, searchText: newSearchText)
                }
            case .administrateAdmins,
                    .editAdmins:
                if let streamUUIDForAllFilteredBySearchText {
                    dataSource.filterAsyncSequenceOfListOfSingleGroupMemberViewModel(self, streamUUID: streamUUIDForAllFilteredBySearchText, searchText: newSearchText)
                }
                if let streamUUIDForAdminsOnlyFilteredBySearchText {
                    dataSource.filterAsyncSequenceOfListOfSingleGroupMemberViewModel(self, streamUUID: streamUUIDForAdminsOnlyFilteredBySearchText, searchText: newSearchText)
                }
            }
        }
        
        
        private var disabledValidateNewAdminsSelectionButton: Bool {
            switch mode {
            case .administrateAdmins:
                assertionFailure("The button is only displayed when choosing admins during a group creation or edition. This is not expected to be called in this mode.")
                return true
            case .editAdmins(groupIdentifier: _, selectedGroupType: let selectedGroupType, navigation: _, actions: _):
                return membersWithUpdatedAdminPermission.isEmpty && selectedGroupType == nil
            case .selectAdminsDuringGroupCreation:
                return false
            }
        }
        

        private var showEditAdminsButtonView: Bool {
            guard let groupLightweightModel = self.groupLightweightModel else { return false }
            if groupLightweightModel.ownedIdentityIsAdmin && !groupLightweightModel.isKeycloakManaged {
                switch mode {
                case .administrateAdmins:
                    if isSearchInProgress {
                        return false
                    } else {
                        return true
                    }
                case .editAdmins, .selectAdminsDuringGroupCreation:
                    return false
                }
            } else {
                return false
            }
        }
        

        /// We show a divider above the cell showing the owned identity iff we are showing the add/remove buttons.
        private var showDividerAboveOwnedIdentityAsGroupMemberView: Bool {
            showEditAdminsButtonView
        }
        
        
        public var body: some View {
            
            VStack {
                
                ScrollView {
                    
                    if let groupLightweightModel = self.groupLightweightModel {
                        
                        LazyVStack {
                            
                            switch mode {
                                
                            case .administrateAdmins:
                                
                                if groupLightweightModel.updateInProgressDuringGroupEdition {
                                    UpdateInProgressView()
                                }

                            case .editAdmins(groupIdentifier: _, selectedGroupType: _, navigation: _, actions: _),
                                    .selectAdminsDuringGroupCreation:
                                
                                HStack {
                                    Spacer()
                                    Button(action: resetAdminsButtonTapped) {
                                        Text("RESET_ADMINS")
                                    }
                                    .disabled(membersWithUpdatedAdminPermission.isEmpty)
                                }
                                
                            }
                            
                            ObvCardView(padding: 0) {
                                
                                LazyVStack {
                                    
                                    if groupLightweightModel.ownedIdentityIsAdmin && !groupLightweightModel.isKeycloakManaged {
                                        
                                        switch mode {
                                            
                                        case .administrateAdmins(groupIdentifier: let groupIdentifier, actions: let actions, navigation: _):
                                            
                                            if showEditAdminsButtonView {
                                                EditAdminsButtonView(groupIdentifier: groupIdentifier,
                                                                     dataSource: dataSource,
                                                                     subDataSources: subDataSources,
                                                                     actions: actions,
                                                                     uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                                                    .padding(.top)
                                            }
                                            
                                        case .editAdmins, .selectAdminsDuringGroupCreation:
                                            
                                            EmptyView()
                                            
                                        }
                                        
                                    }
                                    
                                    switch allOrAdminsOnly {
                                        
                                    case .all:
                                        
                                        if let modelForAllFilteredBySearchText, let modelForAll {
                                            GroupMembersListView(
                                                mode: mode,
                                                modelNotFiltered: modelForAll,
                                                modelFilteredBySearchText: modelForAllFilteredBySearchText,
                                                singleGroupMemberViewDataSource: subDataSources.singleGroupMemberViewDataSource,
                                                ownedIdentityAsGroupMemberViewDataSource: subDataSources.ownedIdentityAsGroupMemberViewDataSource,
                                                avatarViewDataSource: subDataSources.avatarViewDataSource,
                                                doShowOwnedIdentityInListMode: true,
                                                isSearchInProgress: isSearchInProgress,
                                                showNoAdminInKeycloakGroupMessage: false,
                                                showDividerAboveOwnedIdentityAsGroupMemberView: showDividerAboveOwnedIdentityAsGroupMemberView,
                                                hudCategory: $hudCategory,
                                                selectedMembers: $selectedMembers,
                                                membersWithUpdatedAdminPermission: $membersWithUpdatedAdminPermission)
                                        } else {
                                            ProgressView()
                                                .padding(.vertical)
                                        }
                                        
                                    case .adminsOnly:
                                        
                                        if let modelForAdminsOnlyFilteredBySearchText, let modelForAdminsOnly {
                                            GroupMembersListView(
                                                mode: mode,
                                                modelNotFiltered: modelForAdminsOnly,
                                                modelFilteredBySearchText: modelForAdminsOnlyFilteredBySearchText,
                                                singleGroupMemberViewDataSource: subDataSources.singleGroupMemberViewDataSource,
                                                ownedIdentityAsGroupMemberViewDataSource: subDataSources.ownedIdentityAsGroupMemberViewDataSource,
                                                avatarViewDataSource: subDataSources.avatarViewDataSource,
                                                doShowOwnedIdentityInListMode: groupLightweightModel.ownedIdentityIsAdmin,
                                                isSearchInProgress: isSearchInProgress,
                                                showNoAdminInKeycloakGroupMessage: groupLightweightModel.isKeycloakManaged,
                                                showDividerAboveOwnedIdentityAsGroupMemberView: showDividerAboveOwnedIdentityAsGroupMemberView,
                                                hudCategory: $hudCategory,
                                                selectedMembers: $selectedMembers,
                                                membersWithUpdatedAdminPermission: $membersWithUpdatedAdminPermission)
                                        } else {
                                            ProgressView()
                                                .padding(.vertical)
                                        }
                                        
                                        
                                    }
                                    
                                }
                                
                            }
                        }
                        .padding()
                        .onAppear(perform: onAppearForAllGroupMembers)
                        .onAppear(perform: onAppearForAdminsOnly)
                        
                    } else {
                        
                        // Prevents an animation glitch on the tabbar
                        // This rectangle must be inside the ScrollView
                        Rectangle()
                            .opacity(0)
                            .frame(height: UIScreen.main.bounds.size.height)
                        
                    }
                    
                }
                
                Spacer()
                
                if let groupLightweightModel = self.groupLightweightModel {
                    
                    switch mode {
                        
                    case .administrateAdmins:
                        
                        EmptyView()
                        
                    case .editAdmins, .selectAdminsDuringGroupCreation:
                        
                        Button(action: { validateNewAdminsSelectionButtonTapped(groupLightweightModel: groupLightweightModel) }) {
                            HStack {
                                Spacer(minLength: 0)
                                Text("VALIDATE")
                                    .padding(.vertical, 8)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                        .padding(.bottom)
                        .disabled(disabledValidateNewAdminsSelectionButton)
                        
                    }
                    
                }
                
            }
            .disabled(isAdminsPermissionUpdateInProgress)
            .onChange(of: searchText) { newSearchText in performSearchWith(newSearchText: newSearchText) }
            .onChange(of: isSearching) { newValue in withAnimation { isSearchInProgress = newValue } }
            
        }
        
    }
    
}


// MARK: Subview: List of group members

private struct GroupMembersListView: View {
    
    let mode: FullListOfGroupMembersView.Mode
    let modelNotFiltered: ListOfSingleGroupMemberViewModel
    let modelFilteredBySearchText: ListOfSingleGroupMemberViewModel
    let singleGroupMemberViewDataSource: SingleGroupMemberViewDataSource
    let ownedIdentityAsGroupMemberViewDataSource: OwnedIdentityAsGroupMemberViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let doShowOwnedIdentityInListMode: Bool
    let isSearchInProgress: Bool
    let showNoAdminInKeycloakGroupMessage: Bool
    let showDividerAboveOwnedIdentityAsGroupMemberView: Bool
    
    @Binding var hudCategory: HUDView.Category? // Must be a binding
    
    // Used in removeMembers mode
    @Binding var selectedMembers: Set<SingleGroupMemberView.Model.Identifier> // Must be a binding
    
    // Used in editAdmins mode
    @Binding var membersWithUpdatedAdminPermission: Set<MemberIdentifierAndPermissions> // Must be a binding
    
    private let leadingPaddingForDivider: CGFloat = 70
    
    private var singleGroupMemberViewMode: SingleGroupMemberView.Mode {
        switch mode {
        case .administrateAdmins(groupIdentifier: let groupIdentifier, actions: let actions, navigation: let navigation):
            return .listMembers(groupIdentifier: .groupV2(groupIdentifier), commonActions: actions, navigation: navigation)
        case .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _, navigation: _, actions: _):
            return .editAdmins(groupIdentifier: groupIdentifier)
        case .selectAdminsDuringGroupCreation(let creationSessionUUID, let ownedCryptoId, let preSelectedAdmins, _, let actionsForCreation, navigation: _):
            return .selectAdminsDuringGroupCreation(creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId, preSelectedAdmins: preSelectedAdmins, actionsForCreation: actionsForCreation)
        }
    }
    
    var body: some View {
        
        VStack {
            
            // Show owned identity cell if appropriate
            
            if doShowOwnedIdentityInListMode && !isSearchInProgress && !showNoAdminInKeycloakGroupMessage {
                
                switch mode {
                case .administrateAdmins(groupIdentifier: let groupIdentifier, actions: _, navigation: _):
                    if showDividerAboveOwnedIdentityAsGroupMemberView {
                        Divider()
                            .padding(.leading, leadingPaddingForDivider)
                    }
                    OwnedIdentityAsGroupMemberView(groupIdentifier: .groupV2(groupIdentifier),
                                                   dataSource: ownedIdentityAsGroupMemberViewDataSource,
                                                   avatarViewDataSource: avatarViewDataSource)
                        .padding(.horizontal)
                        .padding(.top, showDividerAboveOwnedIdentityAsGroupMemberView ? 4 : 16)
                        .padding(.bottom, 4)
                case .editAdmins, .selectAdminsDuringGroupCreation:
                    EmptyView()
                    
                }
                
            }
            
            if showNoAdminInKeycloakGroupMessage {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemIcon: .checkmarkShieldFill)
                        .imageScale(.large)
                        .foregroundStyle(.green)
                    Text("NO_ADMIN_IN_KEYCLOAK_GROUP")
                    Spacer(minLength: 0)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding()
            } else if modelNotFiltered.otherGroupMembers.isEmpty && !isSearchInProgress {
                switch mode {
                case .administrateAdmins:
                    Spacer()
                        .padding(.bottom, 8)
                case .editAdmins, .selectAdminsDuringGroupCreation:
                    Text("NO_GROUP_MEMBER_FOR_NOW")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            } else if modelFilteredBySearchText.otherGroupMembers.isEmpty {
                Text("NO_CONTACT_FOUND_MATCHING_YOUR_SEARCH")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                LazyVStack {
                    
                    // Show the other members
                    
                    ForEach(modelFilteredBySearchText.otherGroupMembers) { otherGroupMember in
                        VStack {
                            switch mode {
                            case .administrateAdmins:
                                if otherGroupMember != modelFilteredBySearchText.otherGroupMembers.first || !isSearchInProgress {
                                    Divider()
                                        .padding(.leading, leadingPaddingForDivider)
                                } else {
                                    Spacer()
                                        .padding(.top, 4)
                                }
                            case .editAdmins, .selectAdminsDuringGroupCreation:
                                if otherGroupMember != modelFilteredBySearchText.otherGroupMembers.first {
                                    Divider()
                                        .padding(.leading, leadingPaddingForDivider)
                                } else {
                                    Spacer()
                                        .padding(.top, 4)
                                }
                            }
                            SingleGroupMemberView(mode: singleGroupMemberViewMode,
                                                  modelIdentifier: otherGroupMember,
                                                  dataSource: singleGroupMemberViewDataSource,
                                                  avatarViewDataSource: avatarViewDataSource,
                                                  selectedMembers: $selectedMembers,
                                                  membersWithUpdatedAdminPermission: $membersWithUpdatedAdminPermission)
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            
        }.padding(.bottom)
        
    }
    
}


// MARK: Subview: Edit admins button

private struct EditAdminsButtonView: View {

    let groupIdentifier: ObvGroupV2Identifier
    
    let dataSource: any FullListOfGroupMembersViewDataSource
    let subDataSources: FullListOfGroupMembersView.SubDataSources
    
    let actions: any FullListOfGroupMembersViewActionsInEditAdminsMode
    
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet

    private let circleDiameter: CGFloat = ObvDesignSystem.ObvAvatarSize.normal.frameSize.width

    @State private var isEditAdminsViewPresented: Bool = false
    
    var body: some View {
        Button(action: { isEditAdminsViewPresented = true }) {
            HStack {
                InitialCircleView(model: .init(content: .init(text: nil, icon: .personBustFill),
                                               colors: .init(background: .systemFill,
                                                             foreground: .secondaryLabel),
                                               circleDiameter: circleDiameter))
                Text("GROUP_ADMINS_EDIT")
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal)
        }
        .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isEditAdminsViewPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
            FullListOfGroupMembersInEditAdminsModeNavigationStack(
                groupIdentifier: groupIdentifier,
                subDataSources: .init(fullListOfGroupMembersViewDataSource: dataSource,
                                      fullListOfGroupMembersViewSubDataSources: subDataSources),
                actions: actions,
                navigation: self,
                uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)            
        }
    }
    
}


extension EditAdminsButtonView: FullListOfGroupMembersInEditAdminsModeNavigationStackNavigation {
    
    func fullListOfGroupMembersInEditAdminsModeNavigationStackShouldBeDismissed(_ view: FullListOfGroupMembersInEditAdminsModeNavigationStack) {
        isEditAdminsViewPresented = false
    }
    
}



// MARK: - Previews

#if DEBUG

@MainActor
private final class ActionsForPreviews {}

extension ActionsForPreviews: FullListOfGroupMembersViewActionsInEditAdminsMode {

    func userWantsToUpdateGroupV2(_ view: FullListOfGroupMembersView.InternalView, groupIdentifier: ObvTypes.ObvGroupV2Identifier, changeset: ObvTypes.ObvGroupV2.Changeset) async throws {
        try await Task.sleep(seconds: 2)
    }
    
}


extension ActionsForPreviews: SelectUsersToAddViewActionsForEdition {
    func userWantsToAddSelectedUsersToExistingGroup(_ view: SelectUsersToAddView.InternalView, groupIdentifier: ObvGroupIdentifier, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) async throws {}
}
    

extension ActionsForPreviews: SingleGroupMemberViewActionsProtocol {
    func userWantsToShowOtherUserProfile(_ view: SingleGroupMemberView.InternalView, contactIdentifier: ObvContactIdentifier) async {}
}


@MainActor
private final class DataSourceForPreviews {}

extension DataSourceForPreviews: FullListOfGroupMembersViewDataSource {
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(_ view: FullListOfGroupMembersView, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, userIdentifiersOfAddedUsers: [ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier]) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel>) {
        let otherGroupMembers: [SingleGroupMemberView.Model.Identifier] = PreviewsHelper.groupMembers.map({ .contactIdentifierForCreatingGroupForPreviews(contactIdentifier: $0.contactIdentifier) })
        let stream = AsyncStream(ListOfSingleGroupMemberViewModel.self) { (continuation: AsyncStream<ListOfSingleGroupMemberViewModel>.Continuation) in
            let model = ListOfSingleGroupMemberViewModel(otherGroupMembers: otherGroupMembers)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(_ view: FullListOfGroupMembersView.InternalView, streamUUID: UUID, userIdentifiersOfAddedUsers: [ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier], searchText: String?) {}
    
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(_ view: FullListOfGroupMembersView, streamUUID: UUID) {}
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(_ view: FullListOfGroupMembersView, groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>) {
        let otherGroupMembers: [SingleGroupMemberView.Model.Identifier] = PreviewsHelper.groupMembers.map({ .contactIdentifierForExistingGroupForPreviews(groupIdentifier: .groupV2(groupIdentifier), contactIdentifier: $0.contactIdentifier) })
        let stream = AsyncStream(ListOfSingleGroupMemberViewModel.self) { (continuation: AsyncStream<ListOfSingleGroupMemberViewModel>.Continuation) in
            let model = ListOfSingleGroupMemberViewModel(otherGroupMembers: otherGroupMembers)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: FullListOfGroupMembersView.InternalView, streamUUID: UUID, searchText: String?) {}
    
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: FullListOfGroupMembersView, streamUUID: UUID) {}
    
    func getAsyncSequenceOfListOfSingleGroupAdminsMemberViewModelForExistingGroup(_ view: FullListOfGroupMembersView, groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>) {
        let otherGroupMembers: [SingleGroupMemberView.Model.Identifier] = PreviewsHelper.groupMembers.compactMap {
            guard $0.isGroupAdmin else { return nil }
            return .contactIdentifierForExistingGroupForPreviews(groupIdentifier: .groupV2(groupIdentifier), contactIdentifier: $0.contactIdentifier)
        }
        let stream = AsyncStream(ListOfSingleGroupMemberViewModel.self) { (continuation: AsyncStream<ListOfSingleGroupMemberViewModel>.Continuation) in
            let model = ListOfSingleGroupMemberViewModel(otherGroupMembers: otherGroupMembers)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(_ view: FullListOfGroupMembersView, streamUUID: UUID) {}
    
    
    func getGroupLightweightModelDuringGroupCreation(_ view: FullListOfGroupMembersView, creationSessionUUID: UUID) throws -> ObvGroupLightweightModel {
        return .init(ownedIdentityIsAdmin: true, groupType: .standard, updateInProgressDuringGroupEdition: false, isKeycloakManaged: false)
    }

    func getAsyncSequenceOfGroupLightweightModelForExistingGroup(_ view: FullListOfGroupMembersView, groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvGroupLightweightModel>) {
        let stream = AsyncStream(ObvGroupLightweightModel.self) { (continuation: AsyncStream<ObvGroupLightweightModel>.Continuation) in
            continuation.yield(.init(ownedIdentityIsAdmin: true, groupType: .standard, updateInProgressDuringGroupEdition: false, isKeycloakManaged: false))
//            Task {
//                try! await Task.sleep(seconds: 2)
//                continuation.yield(.init(ownedIdentityIsAdmin: true, groupType: .standard, updateInProgressDuringGroupEdition: true))
//                try! await Task.sleep(seconds: 2)
//                continuation.yield(.init(ownedIdentityIsAdmin: true, groupType: .standard, updateInProgressDuringGroupEdition: false))
//                try! await Task.sleep(seconds: 2)
//            }
        }
        return (UUID(), stream)
    }
        
    func finishAsyncSequenceOfGroupLightweightModelForExistingGroup(_ view: FullListOfGroupMembersView, groupIdentifier: ObvGroupV2Identifier, streamUUID: UUID) {}
    
    
    enum ObvError: Error {
        case error
    }
    
    
    
}


extension DataSourceForPreviews: SingleGroupMemberViewDataSource {
    
    func getAsyncSequenceOfSingleGroupMemberViewModels(_ view: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView, withIdentifier identifier: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model>) {
        switch identifier {
            
        case .contactIdentifierForExistingGroupForPreviews(groupIdentifier: _, contactIdentifier: let contactIdentifier),
                .contactIdentifierForCreatingGroupForPreviews(contactIdentifier: let contactIdentifier):
            
            let stream = AsyncStream(SingleGroupMemberView.Model.self) { (continuation: AsyncStream<SingleGroupMemberView.Model>.Continuation) in
                if let groupMember = PreviewsHelper.groupMembers.first(where: { $0.contactIdentifier == contactIdentifier }) {
                    continuation.yield(groupMember)
                }
            }
            
            return (UUID(), stream)
            
        case .objectIDOfPersistedGroupV2Member, .objectIDOfPersistedContact, .objectIDOfPersistedPendingGroupMember:
            throw ObvError.error
        }
    }
    
    func finishAsyncSequenceOfSingleGroupMemberViewModels(_ view: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView, withIdentifier identifier: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model.Identifier, streamUUID: UUID) {}
    
//    func fetchAvatarImageForGroupMember(_ view: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView, contactIdentifier: ObvTypes.ObvContactIdentifier, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
//        try await Task.sleep(seconds: 1)
//        return PreviewsHelper.profilePictureForURL[photoURL]
//    }
    
}

extension DataSourceForPreviews: OwnedIdentityAsGroupMemberViewDataSource {
    
    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberViewModel>) {
        let stream = AsyncStream(OwnedIdentityAsGroupMemberViewModel.self) { (continuation: AsyncStream<OwnedIdentityAsGroupMemberViewModel>.Continuation) in
            let model = OwnedIdentityAsGroupMemberViewModel.sampleData
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, streamUUID: UUID) {}
    
//    func fetchAvatarImageForOwnedIdentityAsGroupMember(_ view: ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberView, ownedCryptoId: ObvTypes.ObvCryptoId, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
//        try await Task.sleep(seconds: 2)
//        return PreviewsHelper.profilePictureForURL[photoURL]
//    }
    
}


extension DataSourceForPreviews: ListOfGroupMembersViewDataSource {
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel>) {
        let otherGroupMembers: [SingleGroupMemberView.Model.Identifier] = PreviewsHelper.groupMembers.map({ .contactIdentifierForExistingGroupForPreviews(groupIdentifier: groupIdentifier, contactIdentifier: $0.contactIdentifier) })
        let stream = AsyncStream(ListOfSingleGroupMemberViewModel.self) { (continuation: AsyncStream<ListOfSingleGroupMemberViewModel>.Continuation) in
            let model = ListOfSingleGroupMemberViewModel(otherGroupMembers: otherGroupMembers)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, streamUUID: UUID, searchText: String?) {}
    
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, streamUUID: UUID) {}
    
}


extension DataSourceForPreviews: SelectUsersToRemoveViewDataSource {
    
    func getAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToRemoveView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, searchText: String?) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.SelectUsersToRemoveView.Model>) {
        let stream = AsyncStream<ObvUIGroupSharedBetweenV1AndV2.SelectUsersToRemoveView.Model> { (continuation: AsyncStream<SelectUsersToRemoveView.Model>.Continuation) in
            Task {
                let model: SelectUsersToRemoveView.Model = .init(
                    groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers[0]),
                    allOtherGroupMembers: [],
                    filteredOtherGroupMembers: [])
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func filterAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToRemoveView, streamUUID: UUID, searchText: String?) {}
    
    func finishAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToRemoveView, streamUUID: UUID) {}
    
}


extension DataSourceForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
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
        try await Task.sleep(seconds: 2)
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

extension DataSourceForPreviews: SelectUsersToAddViewDataSource {
    
    func getAsyncSequenceOfUsersToAddToCreatingGroup(_ view: SelectUsersToAddView, ownedCryptoId: ObvTypes.ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>) {
        let model = PreviewsHelper.selectUsersToAddViewModel
        let stream = AsyncStream(SelectUsersToAddViewModel.self) { (continuation: AsyncStream<SelectUsersToAddViewModel>.Continuation) in
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func getAsyncSequenceOfUsersToAddToExistingGroup(_ view: SelectUsersToAddView, groupIdentifier: ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>) {
        let model = PreviewsHelper.selectUsersToAddViewModel
        let stream = AsyncStream(SelectUsersToAddViewModel.self) { (continuation: AsyncStream<SelectUsersToAddViewModel>.Continuation) in
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func filterAsyncSequenceOfUsersToAdd(_ view: SelectUsersToAddView.InternalView, streamUUID: UUID, searchText: String?) {}
    func finishAsyncSequenceOfSelectUsersToAddViewModel(_ view: SelectUsersToAddView, streamUUID: UUID) {}
    
}

extension DataSourceForPreviews: ListOfUsersViewCellDataSource {
    
    func getAsyncSequenceOfSelectUsersToAddViewModelUser(_ view: HorizontalOrVerticalListOfUsersViewCell, withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel.User>) {
        let model = PreviewsHelper.selectUsersToAddViewModelUser.first(where: { $0.identifier == identifier })!
        let stream = AsyncStream(SelectUsersToAddViewModel.User.self) { (continuation: AsyncStream<SelectUsersToAddViewModel.User>.Continuation) in
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfSelectUsersToAddViewModelUser(_ view: HorizontalOrVerticalListOfUsersViewCell, withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier, streamUUID: UUID) {}
    
}

private final class NavigationForPreviews: FullListOfGroupMembersViewNavigationDuringEdition, FullListOfGroupMembersViewNavigationDuringCreation {
    func hudWasDismissedAfterSuccessfulGroupEdition(_ view: FullListOfGroupMembersView.InternalView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) {}
    func userConfirmedTheAdminsChoiceDuringGroupCreationAndWantsToNavigateToNextScreen(_ view: FullListOfGroupMembersView.InternalView, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId) {}
}

extension NavigationForPreviews: UIKitDelegateForSwiftUISheet {
    func userWantsToPresentView<Content>(_ view: some View, content: @escaping () -> Content) async where Content : View {
        // We don't implement this method. Consequently certain views cannot be presented when showing previews on catalyst.
    }
    func userWantsToDismissPresentedView(_ view: some View) async {}
}

private let actionsForPreviews = ActionsForPreviews()
private let dataSourceForPreviews = DataSourceForPreviews()
private let navigationForPreviews = NavigationForPreviews()

@MainActor
private let subDataSourcesForPreviews = FullListOfGroupMembersView.SubDataSources(
    singleGroupMemberViewDataSource: dataSourceForPreviews,
    selectUsersToAddViewDataSource: dataSourceForPreviews,
    listOfUsersViewCellDataSource: dataSourceForPreviews,
    ownedIdentityAsGroupMemberViewDataSource: dataSourceForPreviews,
    avatarViewDataSource: dataSourceForPreviews,
    listOfGroupMembersViewDataSource: dataSourceForPreviews,
    selectUsersToRemoveViewDataSource: dataSourceForPreviews)

#Preview("Edit admins") {
    FullListOfGroupMembersView(mode: .editAdmins(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0],
                                                 selectedGroupType: nil,
                                                 navigation: navigationForPreviews,
                                                 actions: actionsForPreviews),
                               dataSource: dataSourceForPreviews,
                               subDataSources: subDataSourcesForPreviews,
                               uiKitDelegateForSwiftUISheet: navigationForPreviews)
}

#endif
