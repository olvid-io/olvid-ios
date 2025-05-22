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


protocol FullListOfGroupMembersViewActionsProtocol: AnyObject, AddAndRemoveMembersButtonsViewActionsProtocol, SingleGroupMemberViewActionsProtocol {
    func userWantsToRemoveMembersFromGroup(groupIdentifier: ObvGroupV2Identifier, membersToRemove: Set<SingleGroupMemberViewModelIdentifier>) async throws
    func groupMembersWereSuccessfullyRemovedFromGroup(groupIdentifier: ObvGroupV2Identifier)
    func userWantsToUpdateGroupV2(groupIdentifier: ObvGroupV2Identifier, changeset: ObvGroupV2.Changeset) async throws
    func hudWasDismissedAfterSuccessfulGroupEdition(groupIdentifier: ObvGroupV2Identifier)
    func userConfirmedTheAdminsChoiceDuringGroupCreationAndWantsToNavigateToNextScreen(creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId)
}


@MainActor
protocol FullListOfGroupMembersViewDataSource: ListOfOtherGroupMembersViewDataSource, GroupMembersListViewDataSource {
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(creationSessionUUID: UUID) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>)
    func getAsyncSequenceOfListOfSingleGroupAdminsMemberViewModelForExistingGroup(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>)
    func finishAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(streamUUID: UUID)
}

enum GroupMembersListMode {
    case listMembers(groupIdentifier: ObvGroupV2Identifier)
    case removeMembers(groupIdentifier: ObvGroupV2Identifier)
    case editAdmins(groupIdentifier: ObvGroupV2Identifier, selectedGroupType: ObvGroupType?) // selectedGroupType is non nil when the user just edited the group type
    case selectAdminsDuringGroupCreation(creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, preSelectedAdmins: Set<SingleGroupMemberViewModelIdentifier>)
}

struct FullListOfGroupMembersView: View {
    
    let mode: GroupMembersListMode
    let dataSource: FullListOfGroupMembersViewDataSource
    let actions: FullListOfGroupMembersViewActionsProtocol

    @State private var modelForAll: ListOfSingleGroupMemberViewModel?
    @State private var modelForAllFilteredBySearchText: ListOfSingleGroupMemberViewModel?
    @State private var modelForAdminsOnly: ListOfSingleGroupMemberViewModel?
    @State private var modelForAdminsOnlyFilteredBySearchText: ListOfSingleGroupMemberViewModel?
    @State private var groupLightweightModel: GroupLightweightModel? // Not used during group creation
    
    @State private var streamUUIDForAll: UUID?
    @State private var streamUUIDForAllFilteredBySearchText: UUID?
    @State private var streamUUIDForAdminsOnly: UUID?
    @State private var streamUUIDForAdminsOnlyFilteredBySearchText: UUID?
    @State private var streamUUIDForGroupLightweightModel: UUID? // Not used during group creation
    
    @State private var searchText: String = ""

    // The following States are used when in `removeMembers` mode
    
    @State private var selectedMembers: Set<SingleGroupMemberViewModelIdentifier> = []
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
            
            switch mode {
            case .listMembers(groupIdentifier: let groupIdentifier),
                    .removeMembers(groupIdentifier: let groupIdentifier),
                    .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _):
                
                let (streamUUID, stream) = try dataSource.getAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: groupIdentifier)
                self.streamUUIDForGroupLightweightModel = streamUUID
                for await model in stream {
                    withAnimation {
                        self.groupLightweightModel = model
                    }
                }
                
                
            case .selectAdminsDuringGroupCreation(creationSessionUUID: let creationSessionUUID, ownedCryptoId: _, preSelectedAdmins: _):
                let model = try dataSource.getGroupLightweightModelDuringGroupCreation(creationSessionUUID: creationSessionUUID)
                self.groupLightweightModel = model
            }
            
        }
    }

    
    // Also called when displaying a view that does not show the selector between all / admins only
    private func onAppearForAllGroupMembers() {
        Task {
            
            guard self.streamUUIDForAll == nil else { return }

            switch mode {
            case .listMembers(groupIdentifier: let groupIdentifier),
                    .removeMembers(groupIdentifier: let groupIdentifier),
                    .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _):
                
                let (streamUUID, stream) = try dataSource.getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(groupIdentifier: groupIdentifier)
                self.streamUUIDForAll = streamUUID
                
                for await model in stream {
                    withAnimation {
                        self.modelForAll = model
                    }
                    cleanupSelectedMembersOnModelUpdate()
                }
                
            case .selectAdminsDuringGroupCreation(creationSessionUUID: let creationSessionUUID, ownedCryptoId: _, preSelectedAdmins: _):
                                
                let (streamUUID, stream) = try dataSource.getAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(creationSessionUUID: creationSessionUUID)
                
                self.streamUUIDForAll = streamUUID
                for await model in stream {
                    withAnimation {
                        self.modelForAll = model
                    }
                }
                
            }
            
        }
        Task {
            
            guard self.streamUUIDForAllFilteredBySearchText == nil else { return }
            
            let streamUUID: UUID
            let stream: AsyncStream<ListOfSingleGroupMemberViewModel>
            
            switch mode {
            case .listMembers(groupIdentifier: let groupIdentifier),
                    .removeMembers(groupIdentifier: let groupIdentifier),
                    .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _):
                
                (streamUUID, stream) = try dataSource.getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(groupIdentifier: groupIdentifier)

            case .selectAdminsDuringGroupCreation(creationSessionUUID: let creationSessionUUID, ownedCryptoId: _, preSelectedAdmins: _):
                
                (streamUUID, stream) = try dataSource.getAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(creationSessionUUID: creationSessionUUID)

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
            
            switch mode {

            case .listMembers(groupIdentifier: let groupIdentifier),
                    .removeMembers(groupIdentifier: let groupIdentifier),
                    .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _):

                let (streamUUID, stream) = try dataSource.getAsyncSequenceOfListOfSingleGroupAdminsMemberViewModelForExistingGroup(groupIdentifier: groupIdentifier)
                
                self.streamUUIDForAdminsOnly = streamUUID
                
                for await model in stream {
                    withAnimation {
                        self.modelForAdminsOnly = model
                    }
                    cleanupSelectedMembersOnModelUpdate()
                }

                
            case .selectAdminsDuringGroupCreation:
                
                // There is no "admin" tab when selecting group admins, so there is nothing to do here
                return
                
            }
            
        }
        Task {
            guard self.streamUUIDForAdminsOnlyFilteredBySearchText == nil else { return }
            
            switch mode {
                
            case .listMembers(groupIdentifier: let groupIdentifier),
                    .removeMembers(groupIdentifier: let groupIdentifier),
                    .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _):
                
                let (streamUUID, stream) = try dataSource.getAsyncSequenceOfListOfSingleGroupAdminsMemberViewModelForExistingGroup(groupIdentifier: groupIdentifier)
                
                self.streamUUIDForAdminsOnlyFilteredBySearchText = streamUUID
                
                for await model in stream {
                    withAnimation {
                        self.modelForAdminsOnlyFilteredBySearchText = model
                    }
                    cleanupSelectedMembersOnModelUpdate()
                }

            case .selectAdminsDuringGroupCreation:
                
                // There is no "admin" tab when selecting group admins, so there is nothing to do here
                return

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
            dataSource.finishAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: streamUUID)
            self.streamUUIDForAll = nil
        }
        if let streamUUID = self.streamUUIDForAllFilteredBySearchText {
            dataSource.finishAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: streamUUID)
            self.streamUUIDForAllFilteredBySearchText = nil
        }
        if let streamUUID = self.streamUUIDForAdminsOnly {
            dataSource.finishAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(streamUUID: streamUUID)
            self.streamUUIDForAdminsOnly = nil
        }
        if let streamUUID = self.streamUUIDForAdminsOnlyFilteredBySearchText {
            dataSource.finishAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(streamUUID: streamUUID)
            self.streamUUIDForAdminsOnlyFilteredBySearchText = nil
        }
        switch mode {
        case .listMembers(groupIdentifier: let groupIdentifier),
                .removeMembers(groupIdentifier: let groupIdentifier),
                .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: _):
            if let streamUUID = self.streamUUIDForGroupLightweightModel {
                dataSource.finishAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: groupIdentifier, streamUUID: streamUUID)
                self.streamUUIDForGroupLightweightModel = nil
            }
        case .selectAdminsDuringGroupCreation:
            break
        }
    }


    private var searchablePlacement: SearchFieldPlacement {
        switch mode {
        case .listMembers:
            return .automatic
        case .removeMembers:
            return .navigationBarDrawer(displayMode: .always)
        case .editAdmins:
            return .automatic
        case .selectAdminsDuringGroupCreation:
            return .automatic
        }
    }
    
    
    var body: some View {
        ZStack {
             
            Color(AppTheme.shared.colorScheme.systemBackground)
                .edgesIgnoringSafeArea(.all)
            
            InternalView(mode: mode,
                         dataSource: dataSource,
                         actions: actions,
                         modelForAll: modelForAll,
                         modelForAllFilteredBySearchText: modelForAllFilteredBySearchText,
                         modelForAdminsOnly: modelForAdminsOnly,
                         modelForAdminsOnlyFilteredBySearchText: modelForAdminsOnlyFilteredBySearchText,
                         groupLightweightModel: groupLightweightModel,
                         membersWithUpdatedAdminPermission: $membersWithUpdatedAdminPermission,
                         selectedMembers: $selectedMembers,
                         hudCategory: $hudCategory,
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
    }
    
    
    private struct InternalView: View {
        
        let mode: GroupMembersListMode
        let dataSource: FullListOfGroupMembersViewDataSource
        let actions: FullListOfGroupMembersViewActionsProtocol
        let modelForAll: ListOfSingleGroupMemberViewModel?
        let modelForAllFilteredBySearchText: ListOfSingleGroupMemberViewModel?
        let modelForAdminsOnly: ListOfSingleGroupMemberViewModel?
        let modelForAdminsOnlyFilteredBySearchText: ListOfSingleGroupMemberViewModel?
        let groupLightweightModel: GroupLightweightModel?
        @Binding var membersWithUpdatedAdminPermission: Set<MemberIdentifierAndPermissions> // Must be a binding
        @Binding var selectedMembers: Set<SingleGroupMemberViewModelIdentifier> // Must be a binding
        @Binding var hudCategory: HUDView.Category? // Must be a binding
        let streamUUIDForAllFilteredBySearchText: UUID?
        let streamUUIDForAdminsOnlyFilteredBySearchText: UUID?
        let searchText: String
        let onAppearForAllGroupMembers: () -> Void
        let onAppearForAdminsOnly: () -> Void
        
        @State private var isMembersDeletionInProgress: Bool = false
        @State private var membersToFilterOutAfterDeletion: Set<SingleGroupMemberViewModelIdentifier> = []
        @State private var showGroupMembersRemovalConfirmationAlert: Bool = false
        @State private var isAdminsPermissionUpdateInProgress: Bool = false
        @State private var allOrAdminsOnly: AllOrAdminsOnly = .all
        @State private var isSearchInProgress = false

        // Implementing search
        
        @Environment(\.dismissSearch) private var dismissSearch
        @Environment(\.isSearching) var isSearching

        private func resetAdminsButtonTapped() {
            self.membersWithUpdatedAdminPermission.removeAll()
        }

        private func validateNewAdminsSelectionButtonTapped(groupLightweightModel: GroupLightweightModel) {
            
            dismissSearch()
            
            switch mode {
            case .listMembers, .removeMembers:
                
                assertionFailure()
                return
                
            case .selectAdminsDuringGroupCreation(creationSessionUUID: let creationSessionUUID, ownedCryptoId: let ownedCryptoId, preSelectedAdmins: _):
                
                // During a group creation, each time the user toggles on/off an admin, the choice is immediately saved to the model's router.
                // This is done thanks to the
                //    `func userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(memberIdentifier: SingleGroupMemberViewModelIdentifier, newIsAnAdmin: Bool)`
                // method. For this reason, we don't need to pass the final list of admins here, as it is already known to the router.
                actions.userConfirmedTheAdminsChoiceDuringGroupCreationAndWantsToNavigateToNextScreen(creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId)
                
            case .editAdmins(groupIdentifier: let groupIdentifier, selectedGroupType: let selectedGroupType):
                
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
                        try await actions.userWantsToUpdateGroupV2(groupIdentifier: groupIdentifier, changeset: changeset)
                        self.hudCategory = .checkmark
                    } catch {
                        self.hudCategory = .xmark
                    }
                    try? await Task.sleep(seconds: 1) // Give some time to the HUD
                    actions.hudWasDismissedAfterSuccessfulGroupEdition(groupIdentifier: groupIdentifier)
                }

            }
                        
        }

        
        private func removeMembersButtonTapped(confirmed: Bool) {
            
            switch mode {
                
            case .listMembers, .editAdmins, .selectAdminsDuringGroupCreation:
                assertionFailure("This method is not expected to be called in this mode")
                return
                
            case .removeMembers(groupIdentifier: let groupIdentifier):
                
                guard !selectedMembers.isEmpty else { return }
                
                if !confirmed {
                    
                    showGroupMembersRemovalConfirmationAlert = true
                    
                } else {
                    
                    isMembersDeletionInProgress = true
                    hudCategory = .progress
                    Task {
                        defer {
                            isMembersDeletionInProgress = false
                            hudCategory = nil
                        }
                        do {
                            try await actions.userWantsToRemoveMembersFromGroup(groupIdentifier: groupIdentifier, membersToRemove: selectedMembers)
                            hudCategory = .checkmark
                            withAnimation {
                                membersToFilterOutAfterDeletion = selectedMembers
                            }
                            selectedMembers.removeAll()
                            try? await Task.sleep(seconds: 2)
                            actions.groupMembersWereSuccessfullyRemovedFromGroup(groupIdentifier: groupIdentifier)
                        } catch {
                            hudCategory = .xmark
                            try? await Task.sleep(seconds: 2)
                        }
                    }
                    
                }
            }

        }
        
        
        private func performSearchWith(newSearchText: String?) {
            if let streamUUIDForAllFilteredBySearchText {
                dataSource.filterAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: streamUUIDForAllFilteredBySearchText, searchText: newSearchText)
            }
            if let streamUUIDForAdminsOnlyFilteredBySearchText {
                dataSource.filterAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: streamUUIDForAdminsOnlyFilteredBySearchText, searchText: newSearchText)
            }
        }
        
        
        private var disabledValidateNewAdminsSelectionButton: Bool {
            switch mode {
            case .listMembers, .removeMembers:
                assertionFailure("The button is only displayed when choosing admins during a group creation or edition. This is not expected to be called in this mode.")
                return true
            case .editAdmins(groupIdentifier: _, selectedGroupType: let selectedGroupType):
                return membersWithUpdatedAdminPermission.isEmpty && selectedGroupType == nil
            case .selectAdminsDuringGroupCreation:
                return false
            }
        }
        
        private var showAddAndRemoveMembersButtonsView: Bool {
            guard let groupLightweightModel = self.groupLightweightModel else { return false }
            if groupLightweightModel.ownedIdentityIsAdmin && !groupLightweightModel.isKeycloakManaged {
                switch mode {
                case .listMembers(groupIdentifier: _):
                    if isSearchInProgress {
                        return false
                    } else {
                        return true
                    }
                case .removeMembers, .editAdmins, .selectAdminsDuringGroupCreation:
                    return false
                }
            } else {
                return false
            }
        }

        /// We show a divider above the cell showing the owned identity iff we are showing the add/remove buttons.
        private var showDividerAboveOwnedIdentityAsGroupMemberView: Bool {
            showAddAndRemoveMembersButtonsView
        }
        
        
        var body: some View {
            
            VStack {
                
                ScrollView {
                    
                    if let groupLightweightModel = self.groupLightweightModel {
                        
                        LazyVStack {
                            
                            switch mode {
                                
                            case .removeMembers:
                                
                                EmptyView()
                                
                            case .listMembers:
                                
                                Picker(String(localizedInThisBundle: "SHOW_ALL_GROUP_MEMBERS_OR_RESTRICT_TO_ADMINS"), selection: $allOrAdminsOnly) {
                                    Text("ALL").tag(AllOrAdminsOnly.all)
                                    Text("ADMINS").tag(AllOrAdminsOnly.adminsOnly)
                                }
                                .pickerStyle(.segmented)
                                .padding(.bottom)
                                
                                if groupLightweightModel.updateInProgressDuringGroupEdition {
                                    UpdateInProgressView()
                                }
                                
                            case .editAdmins, .selectAdminsDuringGroupCreation:
                                
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
                                        case .listMembers(groupIdentifier: let groupIdentifier):
                                            
                                            if showAddAndRemoveMembersButtonsView {
                                                AddAndRemoveMembersButtonsView(groupIdentifier: groupIdentifier, actions: actions)
                                                    .padding(.top)
                                            }

                                        case .removeMembers, .editAdmins, .selectAdminsDuringGroupCreation:
                                            
                                            EmptyView()
                                            
                                        }
                                        
                                    }
                                    
                                    switch allOrAdminsOnly {
                                        
                                    case .all:
                                        
                                        if let modelForAllFilteredBySearchText, let modelForAll {
                                            GroupMembersListView(mode: mode,
                                                                 modelNotFiltered: modelForAll,
                                                                 modelFilteredBySearchText: modelForAllFilteredBySearchText,
                                                                 dataSource: dataSource,
                                                                 actions: actions,
                                                                 doShowOwnedIdentityInListMode: true,
                                                                 isSearchInProgress: isSearchInProgress,
                                                                 showNoAdminInKeycloakGroupMessage: false,
                                                                 showDividerAboveOwnedIdentityAsGroupMemberView: showDividerAboveOwnedIdentityAsGroupMemberView,
                                                                 hudCategory: $hudCategory,
                                                                 selectedMembers: $selectedMembers,
                                                                 membersToFilterOutAfterDeletion: $membersToFilterOutAfterDeletion,
                                                                 membersWithUpdatedAdminPermission: $membersWithUpdatedAdminPermission)
                                        } else {
                                            ProgressView()
                                                .padding(.vertical)
                                        }
                                        
                                    case .adminsOnly:
                                        
                                        if let modelForAdminsOnlyFilteredBySearchText, let modelForAdminsOnly {
                                            GroupMembersListView(mode: mode,
                                                                 modelNotFiltered: modelForAdminsOnly,
                                                                 modelFilteredBySearchText: modelForAdminsOnlyFilteredBySearchText,
                                                                 dataSource: dataSource,
                                                                 actions: actions,
                                                                 doShowOwnedIdentityInListMode: groupLightweightModel.ownedIdentityIsAdmin,
                                                                 isSearchInProgress: isSearchInProgress,
                                                                 showNoAdminInKeycloakGroupMessage: groupLightweightModel.isKeycloakManaged,
                                                                 showDividerAboveOwnedIdentityAsGroupMemberView: showDividerAboveOwnedIdentityAsGroupMemberView,
                                                                 hudCategory: $hudCategory,
                                                                 selectedMembers: $selectedMembers,
                                                                 membersToFilterOutAfterDeletion: $membersToFilterOutAfterDeletion,
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
                        
                    case .listMembers:
                        
                        EmptyView()
                        
                    case .removeMembers:
                        
                        if !selectedMembers.isEmpty {
                            Button(action: { removeMembersButtonTapped(confirmed: false) }) {
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
                                Button(String(localizedInThisBundle: "REMOVE_GROUP_MEMBER_BUTTON_TITLE"), role: .destructive) {
                                    removeMembersButtonTapped(confirmed: true)
                                }
                            }
                        }
                        
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
            .disabled(isMembersDeletionInProgress || isAdminsPermissionUpdateInProgress)
            .onChange(of: searchText) { newSearchText in performSearchWith(newSearchText: newSearchText) }
            .onChange(of: isSearching) { newValue in withAnimation { isSearchInProgress = newValue } }
            
        }
        
    }
    
}


// MARK: Subview: List of group members

protocol GroupMembersListViewDataSource: SingleGroupMemberViewDataSource, OwnedIdentityAsGroupMemberViewDataSource {}

private struct GroupMembersListView: View {
    
    let mode: GroupMembersListMode
    let modelNotFiltered: ListOfSingleGroupMemberViewModel
    let modelFilteredBySearchText: ListOfSingleGroupMemberViewModel
    let dataSource: GroupMembersListViewDataSource
    let actions: SingleGroupMemberViewActionsProtocol
    let doShowOwnedIdentityInListMode: Bool
    let isSearchInProgress: Bool
    let showNoAdminInKeycloakGroupMessage: Bool
    let showDividerAboveOwnedIdentityAsGroupMemberView: Bool
    
    @Binding var hudCategory: HUDView.Category? // Must be a binding
    
    // Used in removeMembers mode
    @Binding var selectedMembers: Set<SingleGroupMemberViewModelIdentifier> // Must be a binding
    @Binding var membersToFilterOutAfterDeletion: Set<SingleGroupMemberViewModelIdentifier> // Must be a binding
    
    // Used in editAdmins mode
    @Binding var membersWithUpdatedAdminPermission: Set<MemberIdentifierAndPermissions> // Must be a binding
    
    private let leadingPaddingForDivider: CGFloat = 70
    
    var body: some View {
        
        VStack {
            
            // Show owned identity cell if appropriate
            
            if doShowOwnedIdentityInListMode && !isSearchInProgress && !showNoAdminInKeycloakGroupMessage {
                
                switch mode {
                case .listMembers(groupIdentifier: let groupIdentifier):
                    if showDividerAboveOwnedIdentityAsGroupMemberView {
                        Divider()
                            .padding(.leading, leadingPaddingForDivider)
                    }
                    OwnedIdentityAsGroupMemberView(groupIdentifier: groupIdentifier, dataSource: dataSource)
                        .padding(.horizontal)
                        .padding(.top, showDividerAboveOwnedIdentityAsGroupMemberView ? 4 : 16)
                        .padding(.bottom, 4)
                case .removeMembers, .editAdmins, .selectAdminsDuringGroupCreation:
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
                case .listMembers:
                    Spacer()
                        .padding(.bottom, 8)
                case .removeMembers, .editAdmins, .selectAdminsDuringGroupCreation:
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
                        if !membersToFilterOutAfterDeletion.contains(otherGroupMember) {
                            VStack {
                                switch mode {
                                case .listMembers:
                                    if otherGroupMember != modelFilteredBySearchText.otherGroupMembers.first || !isSearchInProgress {
                                        Divider()
                                            .padding(.leading, leadingPaddingForDivider)
                                    } else {
                                        Spacer()
                                            .padding(.top, 4)
                                    }
                                case .removeMembers, .editAdmins, .selectAdminsDuringGroupCreation:
                                    if otherGroupMember != modelFilteredBySearchText.otherGroupMembers.first {
                                        Divider()
                                            .padding(.leading, leadingPaddingForDivider)
                                    } else {
                                        Spacer()
                                            .padding(.top, 4)
                                    }
                                }
                                SingleGroupMemberView(mode: mode,
                                                      modelIdentifier: otherGroupMember,
                                                      dataSource: dataSource,
                                                      actions: actions,
                                                      selectedMembers: $selectedMembers,
                                                      hudCategory: $hudCategory,
                                                      membersWithUpdatedAdminPermission: $membersWithUpdatedAdminPermission)
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            
        }.padding(.bottom)
        
    }
    
}


// MARK: Subview: Add/Remove members buttons

@MainActor
protocol AddAndRemoveMembersButtonsViewActionsProtocol: AnyObject {
    func userWantsToAddGroupMembers(groupIdentifier: ObvGroupV2Identifier) async
    func userWantsToRemoveGroupMembers(groupIdentifier: ObvGroupV2Identifier) async
}


private struct AddAndRemoveMembersButtonsView: View {
    
    let groupIdentifier: ObvGroupV2Identifier
    let actions: any AddAndRemoveMembersButtonsViewActionsProtocol
    
    private let circleDiameter: CGFloat = ObvDesignSystem.ObvAvatarSize.normal.frameSize.width
    
    private func userWantsToAddGroupMembers() {
        Task {
            await actions.userWantsToAddGroupMembers(groupIdentifier: groupIdentifier)
        }
    }
    
    private func userWantsToRemoveGroupMembers() {
        Task {
            await actions.userWantsToRemoveGroupMembers(groupIdentifier: groupIdentifier)
        }
    }
    
    var body: some View {
        VStack {
            Button(action: userWantsToAddGroupMembers) {
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
            
            Button(role: .destructive, action: userWantsToRemoveGroupMembers) {
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
    }
}




// MARK: - Previews

#if DEBUG

private final class ActionsForPreviews: FullListOfGroupMembersViewActionsProtocol {

    func userConfirmedTheAdminsChoiceDuringGroupCreationAndWantsToNavigateToNextScreen(creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId) {
        // We do nothing in this preview
    }
    
    func hudWasDismissedAfterSuccessfulGroupEdition(groupIdentifier: ObvGroupV2Identifier) {
        // We do nothing in this preview
    }
    
    func userWantsToAddGroupMembers(groupIdentifier: ObvGroupV2Identifier) async {
        // We do nothing in this preview
    }
    
    func userWantsToRemoveGroupMembers(groupIdentifier: ObvGroupV2Identifier) async {
        // We do nothing in this preview
    }
    
    // SingleGroupMemberViewActionsProtocol
    
    func userWantsToInviteOtherUserToOneToOne(contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        // We do nothing in this preview
    }
    
    func userWantsToShowOtherUserProfile(contactIdentifier: ObvTypes.ObvContactIdentifier) async {
        // We do nothing in this preview
    }
    
    func userWantsToRemoveOtherUserFromGroup(groupIdentifier: ObvGroupV2Identifier, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        // We do nothing in this preview
    }

    func userWantsToRemoveMembersFromGroup(groupIdentifier: ObvGroupV2Identifier, membersToRemove: Set<SingleGroupMemberViewModelIdentifier>) async throws {
        try await Task.sleep(seconds: 2)
    }
 
    func groupMembersWereSuccessfullyRemovedFromGroup(groupIdentifier: ObvGroupV2Identifier) {
        // We do nothing in this preview
    }
    
    func userWantsToUpdateGroupV2(groupIdentifier: ObvGroupV2Identifier, changeset: ObvGroupV2.Changeset) async throws {
        try await Task.sleep(seconds: 2)
    }
    
    func userChangedTheAdminStatusOfGroupMemberDuringGroupCreation(creationSessionUUID: UUID, memberIdentifier: SingleGroupMemberViewModelIdentifier, newIsAnAdmin: Bool) {
        // We do nothing in this preview
    }
}


private final class DataSourceForPreviews: FullListOfGroupMembersViewDataSource {

    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(creationSessionUUID: UUID) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>) {
        let otherGroupMembers: [SingleGroupMemberViewModelIdentifier] = PreviewsHelper.groupMembers.map({ .contactIdentifierForCreatingGroup(contactIdentifier: $0.contactIdentifier) })
        let stream = AsyncStream(ListOfSingleGroupMemberViewModel.self) { (continuation: AsyncStream<ListOfSingleGroupMemberViewModel>.Continuation) in
            let model = ListOfSingleGroupMemberViewModel(otherGroupMembers: otherGroupMembers)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>) {
        let otherGroupMembers: [SingleGroupMemberViewModelIdentifier] = PreviewsHelper.groupMembers.map({ .contactIdentifierForExistingGroup(groupIdentifier: groupIdentifier, contactIdentifier: $0.contactIdentifier) })
        let stream = AsyncStream(ListOfSingleGroupMemberViewModel.self) { (continuation: AsyncStream<ListOfSingleGroupMemberViewModel>.Continuation) in
            let model = ListOfSingleGroupMemberViewModel(otherGroupMembers: otherGroupMembers)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: UUID, searchText: String?) {
        // We don't simulate search
    }
    
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: UUID) {
        // Nothing to finish in these previews
    }
    
    func getAsyncSequenceOfListOfSingleGroupAdminsMemberViewModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>) {
        let otherGroupMembers: [SingleGroupMemberViewModelIdentifier] = PreviewsHelper.groupMembers.compactMap {
            guard $0.isAdmin else { return nil }
            return .contactIdentifierForExistingGroup(groupIdentifier: groupIdentifier, contactIdentifier: $0.contactIdentifier)
        }
        let stream = AsyncStream(ListOfSingleGroupMemberViewModel.self) { (continuation: AsyncStream<ListOfSingleGroupMemberViewModel>.Continuation) in
            let model = ListOfSingleGroupMemberViewModel(otherGroupMembers: otherGroupMembers)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(streamUUID: UUID) {
        // Nothing to finish in these previews
    }
    
    
    func getGroupLightweightModelDuringGroupCreation(creationSessionUUID: UUID) throws -> GroupLightweightModel {
        return .init(ownedIdentityIsAdmin: true, groupType: .standard, updateInProgressDuringGroupEdition: false, isKeycloakManaged: false)
    }

    func getAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<GroupLightweightModel>) {
        let stream = AsyncStream(GroupLightweightModel.self) { (continuation: AsyncStream<GroupLightweightModel>.Continuation) in
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
    
    
    func finishAsyncSequenceOfGroupLightweightModelForExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, streamUUID: UUID) {
        // Nothing to finish in these previews
    }

    
    func getAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupMemberViewModel>) {
        
        switch identifier {
            
        case .contactIdentifierForExistingGroup(groupIdentifier: _, contactIdentifier: let contactIdentifier),
                .contactIdentifierForCreatingGroup(contactIdentifier: let contactIdentifier):
            
            let stream = AsyncStream(SingleGroupMemberViewModel.self) { (continuation: AsyncStream<SingleGroupMemberViewModel>.Continuation) in
                if let groupMember = PreviewsHelper.groupMembers.first(where: { $0.contactIdentifier == contactIdentifier }) {
                    continuation.yield(groupMember)
                }
            }
            
            return (UUID(), stream)
            
        case .objectIDOfPersistedGroupV2Member, .objectIDOfPersistedContact:
            throw ObvError.error
        }
        
    }
    
    func finishAsyncSequenceOfSingleGroupMemberViewModels(withIdentifier identifier: SingleGroupMemberViewModelIdentifier, streamUUID: UUID) {
        // Nothing to finish in these previews
    }

    func fetchAvatarImageForGroupMember(contactIdentifier: ObvTypes.ObvContactIdentifier, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        return PreviewsHelper.profilePictureForURL[photoURL]
    }
    
    enum ObvError: Error {
        case error
    }
    
    // OwnedIdentityAsGroupMemberViewDataSource
    
    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityAsGroupMemberViewModel>) {
        let stream = AsyncStream(OwnedIdentityAsGroupMemberViewModel.self) { (continuation: AsyncStream<OwnedIdentityAsGroupMemberViewModel>.Continuation) in
            let model = OwnedIdentityAsGroupMemberViewModel.sampleData
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(groupIdentifier: ObvGroupV2Identifier, streamUUID: UUID) {
        // Nothing to finish in these previews
    }
    
    func fetchAvatarImageForOwnedIdentityAsGroupMember(ownedCryptoId: ObvTypes.ObvCryptoId, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 2)
        return PreviewsHelper.profilePictureForURL[photoURL]
    }

}


private let actionsForPreviews = ActionsForPreviews()
private let dataSourceForPreviews = DataSourceForPreviews()


#Preview("List") {
    NavigationView {
        FullListOfGroupMembersView(mode: .listMembers(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0]),
                                   dataSource: dataSourceForPreviews,
                                   actions: actionsForPreviews)
    }
}

#Preview("Remove") {
    FullListOfGroupMembersView(mode: .removeMembers(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0]),
                               dataSource: dataSourceForPreviews,
                               actions: actionsForPreviews)
}


#Preview("Edit admins") {
    FullListOfGroupMembersView(mode: .editAdmins(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0], selectedGroupType: nil),
                               dataSource: dataSourceForPreviews,
                               actions: actionsForPreviews)
}

#endif
