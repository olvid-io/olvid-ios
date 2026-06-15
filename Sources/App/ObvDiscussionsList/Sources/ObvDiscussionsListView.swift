/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvAppTypes
import ObvDesignSystem
import ObvSystemIcon
import ObvAppCoreConstants
import ObvTypes
import ObvProfilePictureBarButtonItem
import ObvOwnedIdentityChooser


@MainActor
public protocol ObvDiscussionsListViewDataSource: AnyObject, DiscussionCellViewDataSource {
    func getAsyncStreamOfObvDiscussionsListViewModel(_ view: ObvDiscussionsListView, ownedCryptoId: ObvCryptoId, initialSearchText: String?) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvDiscussionsListViewModel>)
    func finishAsyncStreamOfObvDiscussionsListViewModel(_ view: ObvDiscussionsListView, streamUUID: UUID)
    func filterAsyncStreamOfObvDiscussionsListViewModel(_ view: ObvDiscussionsListView, streamUUID: UUID, searchStatus: ObvDiscussionsListViewModel.SearchStatus)
    func getIdentifiersOfCurrentlyPinnedDiscussions(ownedCryptoId: ObvCryptoId) async throws -> [ObvDiscussionsListViewModel.DiscussionIdentifier]
}


@MainActor
protocol ObvDiscussionsListViewActionsProtocol: AnyObject, SectionForListOfDiscussionsViewActionsProtocol, ArchivedDiscussionsCellActionsProtocol, LocationsCellViewActions, TipCellViewActionsProtocol, MainMenuActionsProtocol, ObvProfilePictureBarButtonItemViewActionsProtocol, ObvPlusButtonActionsDelegate {
    func userWantsToArchiveDiscussions(discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws
    func userWantsToUnarchiveDiscussions(discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws
    func userWantsToDeleteDiscussionFromThisDeviceAndHasConfirmed(discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws
    func userDidSwitchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async // Allows the rest of the app to be notified when the user switches to another profile in from this view or one of its decendents.
    func userWantsToGetNewMessages() async throws // Called during a pull down to refresh
}


public struct ObvDiscussionsListViewModel: Sendable, Equatable {

    let ownedCryptoId: ObvCryptoId
    let identifiersOfPinnedDiscussions: [DiscussionIdentifier]
    let identifiersOfUnpinnedDiscussions: [DiscussionIdentifier]
    let contentUnavailableViewModel: ObvContentUnavailableView.Model
    
    public init(ownedCryptoId: ObvCryptoId, identifiersOfPinnedDiscussions: [DiscussionIdentifier], identifiersOfUnpinnedDiscussions: [DiscussionIdentifier], contentUnavailableViewModel: ObvContentUnavailableView.Model) {
        self.ownedCryptoId = ownedCryptoId
        self.identifiersOfPinnedDiscussions = identifiersOfPinnedDiscussions
        self.identifiersOfUnpinnedDiscussions = identifiersOfUnpinnedDiscussions
        self.contentUnavailableViewModel = contentUnavailableViewModel
    }
    
    public enum DiscussionIdentifier: Sendable, Equatable, Hashable {
        case obvDiscussionIdentifier(ObvDiscussionIdentifier)
        case persistedDiscussionObjectID(NSManagedObjectID)
        public var objectID: NSManagedObjectID? {
            switch self {
            case .obvDiscussionIdentifier: return nil
            case .persistedDiscussionObjectID(let nSManagedObjectID): return nSManagedObjectID
            }
        }
    }
    
    var isEmpty: Bool {
        identifiersOfPinnedDiscussions.isEmpty && identifiersOfUnpinnedDiscussions.isEmpty
    }
    
    public enum SearchStatus {
        case notPerformingSearch
        case performingSearch(searchText: String?)
    }
    
}


extension ObvDiscussionsListViewModel.DiscussionIdentifier: Identifiable {
    
    public var id: Data {
        switch self {
        case .obvDiscussionIdentifier(let discussionIdentifier):
            let ownedIdentity = discussionIdentifier.ownedCryptoId.cryptoIdentity.getIdentity()
            switch discussionIdentifier {
            case .oneToOne(let id):
                let contactIdentity = id.contactCryptoId.cryptoIdentity.getIdentity()
                return ownedIdentity + contactIdentity
            case .groupV1(let id):
                let groupOwner = id.groupV1Identifier.groupOwner.cryptoIdentity.getIdentity()
                let groupUid = id.groupV1Identifier.groupUid.raw
                return ownedIdentity + groupOwner + groupUid
            case .groupV2(let id):
                let groupUID = id.identifier.groupUID.raw
                let serverURL = id.identifier.serverURL.dataRepresentation
                let category: Data
                switch id.identifier.category {
                case .server:
                    category = Data(repeating: 0x00, count: 1)
                case .keycloak:
                    category = Data(repeating: 0x01, count: 1)
                }
                return ownedIdentity + groupUID + serverURL + category
            }
        case .persistedDiscussionObjectID(let objectID):
            return objectID.uriRepresentation().dataRepresentation
        }
    }

}


// MARK: - View's configuration

public struct ObvDiscussionsListViewConfiguration: Sendable {
    
    let showArchivedDiscussionsCell: ShowArchivedDiscussionsCell
    let showLocationsCell: ShowLocationsCell
    let showProgressCell: ShowProgressCell
    let showTipCell: ShowTipCell
    let showProfilePictureBarButtonItem: ShowProfilePictureBarButtonItem
    let showArchiveActionButtonInMenu: Bool
    let showUnarchiveActionButtonInMenu: Bool
    let showPlusButton: Bool
    
    public init(showArchivedDiscussionsCell: ShowArchivedDiscussionsCell, showLocationsCell: ShowLocationsCell, showProgressCell: ShowProgressCell, showTipCell: ShowTipCell, showProfilePictureBarButtonItem: ShowProfilePictureBarButtonItem, showArchiveActionButtonInMenu: Bool, showUnarchiveActionButtonInMenu: Bool, showPlusButton: Bool) {
        self.showArchivedDiscussionsCell = showArchivedDiscussionsCell
        self.showLocationsCell = showLocationsCell
        self.showProgressCell = showProgressCell
        self.showTipCell = showTipCell
        self.showProfilePictureBarButtonItem = showProfilePictureBarButtonItem
        self.showArchiveActionButtonInMenu = showArchiveActionButtonInMenu
        self.showUnarchiveActionButtonInMenu = showUnarchiveActionButtonInMenu
        self.showPlusButton = showPlusButton
    }
    
    public enum ShowArchivedDiscussionsCell: Sendable {
        case no
        case yes(dataSource: ArchivedDiscussionsCellDataSource)
    }
    
    public enum ShowLocationsCell: Sendable {
        case no
        case yes(dataSource: ObvLocationsCellViewDataSource)
    }
    
    public enum ShowProgressCell: Sendable {
        case no
        case yes(dataSource: ProgressCellViewDataSource)
    }
    
    public enum ShowTipCell: Sendable {
        case no
        case yes(dataSource: any TipCellViewDataSource)
    }
    
    public enum ShowProfilePictureBarButtonItem: Sendable {
        case no
        case yes(profilePictureBarButtonItemViewDataSource: ObvProfilePictureBarButtonItemViewDataSource, ownedIdentityChooserViewDataSource: OwnedIdentityChooserViewDataSource)
    }
    
}


// MARK: - Main view: ObvDiscussionsListView


public struct ObvDiscussionsListView: View {
    
    @State var currentOwnedCryptoId: ObvCryptoId
    let dataSource: ObvDiscussionsListViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let actions: ObvDiscussionsListViewActionsProtocol
    let configuration: ObvDiscussionsListViewConfiguration
    
    @State private var viewModel: ObvDiscussionsListViewModel?
    @State private var streamUUIDForViewModel: UUID?
    
    /// Used iff this view is configured to show the "bavigate to archived discussions" cell.
    @State private var archivedDiscussionsCellModel: ObvArchivedDiscussionsCellModel?
    @State private var streamUUIDForArchivedDiscussionsCellModel: UUID?
    
    /// Used iff this view is configured to show the "location" cell.
    @State private var locationsCellViewModel: ObvLocationsCellViewModel?
    @State private var streamUUIDForLocationsCellViewModel: UUID?

    /// Used iff this view is configured to show the "progress" cell
    @State private var progressCellViewModel: Double?
    @State private var streamUUIDForProgressCell: UUID?
    
    /// Used iff this view is configured to show the "tip" cell
    @State private var tipCellViewModelAndDataSourceActions: (model: TipCellViewModel, dataSourceActions: TipCellViewDataSourceActions)?
    @State private var streamUUIDForTipCell: UUID?

    // Implementing search
    @State private var searchText: String = ""

    // Edit mode (selecting multiple discussions)
    @State var editMode: EditMode = .inactive
    @State private var selection = Set<ObvDiscussionsListViewModel.DiscussionIdentifier>()

    @State private var presentConfirmationDialogForDeletingDiscussions: Bool = false

    @State private var isCurrentlyGettingNewMessages = false

    @State var isSearchInProgress = false

    private func onChangeOfCurrentOwnedCryptoId(newOwnedCryptoId: ObvCryptoId) {
        finishAllStreams()
        requestAllStreams()
        Task { await actions.userDidSwitchCurrentOwnedCryptoId(to: newOwnedCryptoId) }
    }

    
    private func onAppear() {
        requestAllStreams()
    }
    
    private func onDisappear() {
        finishAllStreams()
    }
    
    private func requestAllStreams() {
        requestViewModelStream()
        requestStreamForArchiveCell()
        requestStreamForLocationCell()
        requestStreamForProgressCell()
        requestStreamForTipCell()
    }
    
    private func finishAllStreams() {
        finishViewModelStream()
        finishStreamForArchiveCell()
        finishStreamForLocationCell()
        finishStreamForProgressCell()
        finishStreamForTipCell()
    }
    
    private func requestViewModelStream() {
        if self.viewModel?.ownedCryptoId != currentOwnedCryptoId {
            self.viewModel = nil
        }
        Task {
            do {
                let (newStreamUUID, stream) = try await dataSource.getAsyncStreamOfObvDiscussionsListViewModel(self, ownedCryptoId: self.currentOwnedCryptoId, initialSearchText: searchText)
                if let previousStreamUUID = self.streamUUIDForViewModel {
                    dataSource.finishAsyncStreamOfObvDiscussionsListViewModel(self, streamUUID: previousStreamUUID)
                }
                self.streamUUIDForViewModel = newStreamUUID
                for await receivedModel in stream {
                    withAnimation { self.viewModel = receivedModel }
                }
            } catch {
                assertionFailure()
            }
        }
    }
    
    private func finishViewModelStream() {
        if let streamUUIDForViewModel {
            dataSource.finishAsyncStreamOfObvDiscussionsListViewModel(self, streamUUID: streamUUIDForViewModel)
            self.streamUUIDForViewModel = nil
        }
    }
    
    
    private func requestStreamForArchiveCell() {
        switch configuration.showArchivedDiscussionsCell {
        case .no:
            return
        case .yes(dataSource: let cellDataSource):
            Task {
                do {
                    let (newStreamUUID, stream) = try await cellDataSource.getAsyncStreamOfObvArchivedDiscussionsCellModel(self, ownedCryptoId: currentOwnedCryptoId)
                    if let previousStreamUUID = self.streamUUIDForArchivedDiscussionsCellModel {
                        cellDataSource.finishAsyncStreamOfObvArchivedDiscussionsCellModel(self, streamUUID: previousStreamUUID)
                    }
                    self.streamUUIDForArchivedDiscussionsCellModel = newStreamUUID
                    for await receivedModel in stream {
                        withAnimation {
                            self.archivedDiscussionsCellModel = receivedModel
                        }
                    }
                } catch {
                    assertionFailure()
                }
            }
        }
    }
    
    
    private func finishStreamForArchiveCell() {
        switch configuration.showArchivedDiscussionsCell {
        case .no:
            return
        case .yes(dataSource: let cellDataSource):
            if let previousStreamUUID = self.streamUUIDForArchivedDiscussionsCellModel {
                cellDataSource.finishAsyncStreamOfObvArchivedDiscussionsCellModel(self, streamUUID: previousStreamUUID)
                self.streamUUIDForArchivedDiscussionsCellModel = nil
            }
        }
    }

    
    private func requestStreamForLocationCell() {
        switch configuration.showLocationsCell {
        case .no:
            return
        case .yes(dataSource: let cellDataSource):
            Task {
                do {
                    let (newStreamUUID, stream) = try await cellDataSource.getAsyncStreamOfLocationsCellViewModel(self, ownedCryptoId: currentOwnedCryptoId)
                    if let previousStreamUUID = self.streamUUIDForLocationsCellViewModel {
                        cellDataSource.finishAsyncStreamOfLocationsCellViewModel(self, streamUUID: previousStreamUUID)
                    }
                    self.streamUUIDForLocationsCellViewModel = newStreamUUID
                    for await receivedModel in stream {
                        withAnimation {
                            self.locationsCellViewModel = receivedModel
                        }
                    }
                } catch {
                    assertionFailure()
                }
            }
        }
    }
    
    
    private func finishStreamForLocationCell() {
        switch configuration.showLocationsCell {
        case .no:
            return
        case .yes(dataSource: let cellDataSource):
            if let previousStreamUUID = self.streamUUIDForLocationsCellViewModel {
                cellDataSource.finishAsyncStreamOfLocationsCellViewModel(self, streamUUID: previousStreamUUID)
                self.streamUUIDForLocationsCellViewModel = nil
            }
        }
    }
    
    
    private func requestStreamForProgressCell() {
        switch configuration.showProgressCell {
        case .no:
            return
        case .yes(dataSource: let cellDataSource):
            // We experienced a crash for a few users under iOS 17.6.1 (when this feature was implemented with a UIKit version of this list), so we restrict to iOS 18+
            if #available(iOS 18, *) {
                Task {
                    do {
                        let (newStreamUUID, stream) = try cellDataSource.getAsyncStreamOfCoordinatorsProgress(self)
                        if let previousStreamUUID = self.streamUUIDForProgressCell {
                            cellDataSource.finishAsyncStreamOfCoordinatorsProgress(self, streamUUID: previousStreamUUID)
                        }
                        self.streamUUIDForProgressCell = newStreamUUID
                        for await receivedModel in stream {
                            withAnimation {
                                self.progressCellViewModel = receivedModel
                            }
                        }
                    } catch {
                        assertionFailure()
                    }
                }
            }
        }
    }

    
    private func finishStreamForProgressCell() {
        switch configuration.showProgressCell {
        case .no:
            return
        case .yes(dataSource: let cellDataSource):
            if let previousStreamUUID = self.streamUUIDForProgressCell {
                cellDataSource.finishAsyncStreamOfCoordinatorsProgress(self, streamUUID: previousStreamUUID)
                self.streamUUIDForProgressCell = nil
            }
        }
    }
    
    
    private func requestStreamForTipCell() {
        switch configuration.showTipCell {
        case .no:
            return
        case .yes(dataSource: let cellDataSource):
            Task {
                do {
                    let (newStreamUUID, stream) = try cellDataSource.getAsyncStreamOfTipCellViewModel(self)
                    if let previousStreamUUID = self.streamUUIDForTipCell {
                        cellDataSource.finishAsyncStreamOfTipCellViewModel(self, streamUUID: previousStreamUUID)
                    }
                    self.streamUUIDForTipCell = newStreamUUID
                    for await receivedModel in stream {
                        withAnimation {
                            if let receivedModel {
                                self.tipCellViewModelAndDataSourceActions = (model: receivedModel, dataSourceActions: cellDataSource)
                            } else {
                                self.tipCellViewModelAndDataSourceActions = nil
                            }
                        }
                    }
                } catch {
                    assertionFailure()
                }
            }
        }
    }

    
    private func finishStreamForTipCell() {
        switch configuration.showTipCell {
        case .no:
            return
        case .yes(dataSource: let cellDataSource):
            if let previousStreamUUID = self.streamUUIDForTipCell {
                cellDataSource.finishAsyncStreamOfTipCellViewModel(self, streamUUID: previousStreamUUID)
                self.streamUUIDForTipCell = nil
            }
        }
    }

    
    private func toggleSelectMode() {
        if editMode == .inactive {
            withAnimation { editMode = .active }
        } else {
            withAnimation { editMode = .inactive }
        }
    }
    
    
    private func userConfirmedDeletingSelectedDiscussions() {
        guard !self.selection.isEmpty else { return }
        let discussionIdentifiers = self.selection
        toggleSelectMode()
        Task {
            do {
                try await actions.userWantsToDeleteDiscussionFromThisDeviceAndHasConfirmed(discussionIdentifiers: discussionIdentifiers)
            } catch {
                assertionFailure()
            }
        }
    }
    
    
    private var profilePictureBarButtonItemViewDataSource: ObvProfilePictureBarButtonItemViewDataSource? {
        switch configuration.showProfilePictureBarButtonItem {
        case .no:
            return nil
        case .yes(profilePictureBarButtonItemViewDataSource: let profilePictureBarButtonItemViewDataSource, ownedIdentityChooserViewDataSource: _):
            return profilePictureBarButtonItemViewDataSource
        }
    }
    
    private var ownedIdentityChooserViewDataSource: OwnedIdentityChooserViewDataSource? {
        switch configuration.showProfilePictureBarButtonItem {
        case .no:
            return nil
        case .yes(profilePictureBarButtonItemViewDataSource: _, ownedIdentityChooserViewDataSource: let ownedIdentityChooserViewDataSource):
            return ownedIdentityChooserViewDataSource
        }
    }
    
    /// Allows to determine which actions should be shown in the menu accessible during a multiple discussions selection.
    struct SelectionDescription {
        let containsPinnedDiscussion: Bool
        let containsUnpinnedDiscussion: Bool
        let showArchiveActionButtonInMenu: Bool
        let showUnarchiveActionButtonInMenu: Bool
    }
    
    
    /// Allows to determine which actions should be shown in the menu accessible during a multiple discussions selection.
    private var selectionDescription: SelectionDescription {
        guard let viewModel else {
            return .init(containsPinnedDiscussion: false, containsUnpinnedDiscussion: false, showArchiveActionButtonInMenu: false, showUnarchiveActionButtonInMenu: false)
        }
        let containsPinnedDiscussion = !Set(viewModel.identifiersOfPinnedDiscussions).intersection(selection).isEmpty
        let containsUnpinnedDiscussion = !Set(viewModel.identifiersOfUnpinnedDiscussions).intersection(selection).isEmpty
        return .init(containsPinnedDiscussion: containsPinnedDiscussion,
                     containsUnpinnedDiscussion: containsUnpinnedDiscussion,
                     showArchiveActionButtonInMenu: configuration.showArchiveActionButtonInMenu,
                     showUnarchiveActionButtonInMenu: configuration.showUnarchiveActionButtonInMenu)
    }
    
    
    private func userWantsToGetNewMessagesFromMainMenu() {
        Task {
            await userWantsToGetNewMessages()
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            MainInternalView(currentOwnedCryptoId: currentOwnedCryptoId,
                             viewModel: viewModel,
                             streamUUIDForViewModel: streamUUIDForViewModel,
                             archivedDiscussionsCellModel: archivedDiscussionsCellModel,
                             locationsCellViewModel: locationsCellViewModel,
                             progressCellViewModel: progressCellViewModel,
                             tipCellViewModelAndDataSourceActions: tipCellViewModelAndDataSourceActions,
                             dataSource: dataSource,
                             avatarViewDataSource: avatarViewDataSource,
                             internalDataSource: self,
                             actions: actions,
                             internalActions: self,
                             configuration: configuration,
                             searchText: searchText,
                             selection: $selection,
                             isSearchInProgress: $isSearchInProgress)
            if configuration.showPlusButton && !isSearchInProgress {
                ObvPlusButton(actions: actions)
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("SEARCH"))
        .onChange(of: currentOwnedCryptoId, perform: { newOwnedCryptoId in onChangeOfCurrentOwnedCryptoId(newOwnedCryptoId: newOwnedCryptoId) })
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
        .environment(\.editMode, $editMode)
        .confirmationDialog(String(localizedInThisBundle: "ARE_YOU_SURE_YOU_WANT_TO_DELETE_THESE_\(selection.count)_DISCUSSIONS_FROM_THIS_DEVICE"),
                            isPresented: $presentConfirmationDialogForDeletingDiscussions,
                            titleVisibility: .visible) {
            Button(role: .destructive, action: userConfirmedDeletingSelectedDiscussions) {
                Label(title: { Text("DELETE_\(selection.count)_DISCUSSIONS") }, icon: { Image(systemIcon: .trash) })
            }
        }
    }
    
    public var body: some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let profilePictureBarButtonItemViewDataSource, let ownedIdentityChooserViewDataSource {
                        ObvProfilePictureBarButtonItemView(currentOwnedCryptoId: $currentOwnedCryptoId,
                                                           dataSource: profilePictureBarButtonItemViewDataSource,
                                                           avatarViewDataSource: avatarViewDataSource,
                                                           ownedIdentityChooserViewDataSource: ownedIdentityChooserViewDataSource,
                                                           actions: actions)
                    }
                }
                .sharedBackgroundVisibilityOniOS26(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    if isCurrentlyGettingNewMessages && ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
                        ProgressView()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if editMode == .active {
                        HStack {
                            ActionsMenuDuringSelection(actions: self, selectionDescription: selectionDescription)
                                .disabled(selection.isEmpty)
                            Button(action: toggleSelectMode, label: { Text("DONE") })
                        }
                    } else {
                        MainMenu(editMode: $editMode, actions: actions, userWantsToGetNewMessagesFromMainMenu: userWantsToGetNewMessagesFromMainMenu)
                    }
                }
            }
    }
}


// MARK: ObvDiscussionsListView implements MainInternalViewActionsProtocol

extension ObvDiscussionsListView: MainInternalViewActionsProtocol {
    
    func userWantsToGetNewMessages() async {
        let startDate = Date.now
        isCurrentlyGettingNewMessages = true
        
        do {
            try await actions.userWantsToGetNewMessages()
        } catch {
            assertionFailure()
        }

        let minDisplayDelay: TimeInterval = 1.5
        let endDate = Date.now
        let elapsedTime = endDate.timeIntervalSince(startDate)
        assert(elapsedTime > 0)
        if elapsedTime < minDisplayDelay {
            print("Will wait for \(minDisplayDelay-elapsedTime) seconds")
            try? await Task.sleep(seconds: minDisplayDelay-elapsedTime)
        }
        isCurrentlyGettingNewMessages = false
        
    }

}


// MARK: ObvDiscussionsListView implements MainInternalViewDataSource

extension ObvDiscussionsListView: MainInternalViewDataSource {
    
    fileprivate func filterAsyncStreamOfObvDiscussionsListViewModel(_ view: MainInternalView, streamUUID: UUID, searchStatus: ObvDiscussionsListViewModel.SearchStatus) {
        dataSource.filterAsyncStreamOfObvDiscussionsListViewModel(self, streamUUID: streamUUID, searchStatus: searchStatus)
    }
    
}


// MARK: ObvDiscussionsListView implements ActionsMenuDuringSelectionActionsProtocol

extension ObvDiscussionsListView: ActionsMenuDuringSelectionActionsProtocol {
    
    func userTappedMenuButtonDuringSelection(buttonType: MenuDuringSelectionButtonType) {
        guard let viewModel else { return }
        guard !self.selection.isEmpty else { return }
        switch buttonType {
        case .markAsRead:
            for discussionIdentifier in self.selection {
                Task {
                    try await actions.userWantsToMarkAllMessagesAsReadInDiscussion(withIdentifier: discussionIdentifier)
                    self.toggleSelectMode()
                }
            }
        case .archive:
            Task {
                try await actions.userWantsToArchiveDiscussions(discussionIdentifiers: self.selection)
                self.toggleSelectMode()
            }
        case .unarchive:
            Task {
                try await actions.userWantsToUnarchiveDiscussions(discussionIdentifiers: self.selection)
                self.toggleSelectMode()
            }
        case .pin:
            let identifiersToAdd = viewModel.identifiersOfUnpinnedDiscussions.filter({ selection.contains($0) })
            let newIdentifiersOfPinnedDiscussions = viewModel.identifiersOfPinnedDiscussions + identifiersToAdd
            Task {
                try await actions.userWantsToReorderPinnedDiscussions(identifiersOfPinnedDiscussions: newIdentifiersOfPinnedDiscussions)
                self.toggleSelectMode()
            }
        case .unpin:
            let newIdentifiersOfPinnedDiscussions = viewModel.identifiersOfPinnedDiscussions.filter({ !selection.contains($0) })
            Task {
                try await actions.userWantsToReorderPinnedDiscussions(identifiersOfPinnedDiscussions: newIdentifiersOfPinnedDiscussions)
                self.toggleSelectMode()
            }
        case .delete:
            presentConfirmationDialogForDeletingDiscussions = true
        }
    }

}


// MARK: - Internal view: MainMenu

@MainActor
protocol MainMenuActionsProtocol {
    func userWantsToNavigateToSettings()
    func userWantsToNavigateToStorageManagement()
}


private struct MainMenu: View {
 
    @Binding var editMode: EditMode
    let actions: MainMenuActionsProtocol
    let userWantsToGetNewMessagesFromMainMenu: () -> Void
    
    private func toggleSelectMode() {
        if editMode == .inactive {
            withAnimation { editMode = .active }
        } else {
            withAnimation { editMode = .inactive }
        }
    }
    
    private func userTappedSettings() {
        actions.userWantsToNavigateToSettings()
    }
    
    private func userTappedStorageManagement() {
        actions.userWantsToNavigateToStorageManagement()
    }
    
    private var systemIconForMenuLabel: SystemIcon {
        if #available(iOS 26, *) {
            return .ellipsis
        } else {
            return .ellipsisCircle
        }
    }

    var body: some View {
        Menu {
            Section {
                Button(action: userTappedSettings) {
                    Label(title: { Text("MENU_BUTTON_SETTINGS") }, icon: { Image(systemIcon: .gear) })
                }
                if #available(iOS 17.0, *) {
                    Button(action: userTappedStorageManagement) {
                        Label(title: { Text("MENU_BUTTON_STORAGE_MANAGEMENT") }, icon: { Image(systemIcon: .externaldriveFill) })
                    }
                }
            }
            Section {
                Button(action: toggleSelectMode) {
                    Label(title: { Text("SELECT_DISCUSSIONS") }, icon: { Image(systemIcon: .checkmarkCircle) })
                }
            }
            if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
                Section {
                    Button(action: userWantsToGetNewMessagesFromMainMenu) {
                        Label(title: { Text("GET_NEW_MESSAGES") }, icon: { Image(systemIcon: .cloud) })
                    }
                }
            }
        } label: {
            Image(systemIcon: systemIconForMenuLabel)
        }
    }
    
}

// MARK: - Internal view: ActionsMenuDuringSelection

@MainActor
protocol ActionsMenuDuringSelectionActionsProtocol {
    func userTappedMenuButtonDuringSelection(buttonType: MenuDuringSelectionButtonType)
}

enum MenuDuringSelectionButtonType {
    case markAsRead
    case archive
    case unarchive
    case pin
    case unpin
    case delete
}

private struct ActionsMenuDuringSelection: View {
        
    let actions: ActionsMenuDuringSelectionActionsProtocol
    let selectionDescription: ObvDiscussionsListView.SelectionDescription
    
    var body: some View {
        Menu {
            Section {
                Button(action: { actions.userTappedMenuButtonDuringSelection(buttonType: .markAsRead) }) {
                    Label(title: { Text("MENU_BUTTON_MARK_ALL_AS_READ") }, icon: { Image(systemIcon: .envelopeOpen) })
                }
            }
            if selectionDescription.showArchiveActionButtonInMenu || selectionDescription.showUnarchiveActionButtonInMenu {
                Section {
                    if selectionDescription.showArchiveActionButtonInMenu {
                        Button(action: { actions.userTappedMenuButtonDuringSelection(buttonType: .archive) }) {
                            Label(title: { Text("MENU_BUTTON_ARCHIVE") }, icon: { Image(systemIcon: .archivebox) })
                        }
                    }
                    if selectionDescription.showUnarchiveActionButtonInMenu {
                        Button(action: { actions.userTappedMenuButtonDuringSelection(buttonType: .unarchive) }) {
                            Label(title: { Text("MENU_BUTTON_UNARCHIVE") }, icon: { Image(systemIcon: .trayAndArrowUp) })
                        }
                    }
                }
            }
            Section {
                Button(action: { actions.userTappedMenuButtonDuringSelection(buttonType: .pin) }) {
                    Label(title: { Text("MENU_BUTTON_PIN") }, icon: { Image(systemIcon: .pin) })
                }.disabled(!selectionDescription.containsUnpinnedDiscussion)
                Button(action: { actions.userTappedMenuButtonDuringSelection(buttonType: .unpin) }) {
                    Label(title: { Text("MENU_BUTTON_UNPIN") }, icon: { Image(systemIcon: .pinSlash) })
                }.disabled(!selectionDescription.containsPinnedDiscussion)
            }
            Section {
                Button(role: .destructive, action: { actions.userTappedMenuButtonDuringSelection(buttonType: .delete) }) {
                    Label(title: { Text("MENU_BUTTON_DELETE") }, icon: { Image(systemIcon: .trash) })
                }
            }
        } label: {
            Text("ACTIONS")
        }
    }
    
}



// MARK: - Main internal view

@MainActor
private protocol MainInternalViewDataSource {
    func filterAsyncStreamOfObvDiscussionsListViewModel(_ view: MainInternalView, streamUUID: UUID, searchStatus: ObvDiscussionsListViewModel.SearchStatus)
}

@MainActor
private protocol MainInternalViewActionsProtocol {
    func userWantsToGetNewMessages() async
}

private struct MainInternalView: View {

    let currentOwnedCryptoId: ObvCryptoId
    let viewModel: ObvDiscussionsListViewModel?
    let streamUUIDForViewModel: UUID?
    let archivedDiscussionsCellModel: ObvArchivedDiscussionsCellModel?
    let locationsCellViewModel: ObvLocationsCellViewModel?
    let progressCellViewModel: Double?
    let tipCellViewModelAndDataSourceActions: (model: TipCellViewModel, dataSourceActions: TipCellViewDataSourceActions)?
    let dataSource: ObvDiscussionsListViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let internalDataSource: MainInternalViewDataSource
    let actions: ObvDiscussionsListViewActionsProtocol
    let internalActions: MainInternalViewActionsProtocol
    let configuration: ObvDiscussionsListViewConfiguration
    let searchText: String
    @Binding var selection: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>
    @Binding var isSearchInProgress: Bool

    @Environment(\.isSearching) var isSearching

    @Environment(\.editMode) var editMode

    private func performSearchWith(newSearchText: String?) {
        guard let streamUUIDForViewModel else { return }
        internalDataSource.filterAsyncStreamOfObvDiscussionsListViewModel(self, streamUUID: streamUUIDForViewModel, searchStatus: .performingSearch(searchText: newSearchText))
    }
    
    private func stopSearch() {
        guard let streamUUIDForViewModel else { return }
        internalDataSource.filterAsyncStreamOfObvDiscussionsListViewModel(self, streamUUID: streamUUIDForViewModel, searchStatus: .notPerformingSearch)
    }
    
    private var archivedDiscussionsCellModelAvailbleOrNotRequired: Bool {
        switch configuration.showArchivedDiscussionsCell {
        case .no:
            return true
        case .yes:
            return self.archivedDiscussionsCellModel != nil
        }
    }
    
    private var locationsCellViewModelAvailableOrNotRequired: Bool {
        switch configuration.showLocationsCell {
        case .no:
            return true
        case .yes:
            return self.locationsCellViewModel != nil
        }
    }
    
    private var progressCellViewModelAvailableOrNotRequired: Bool {
        switch configuration.showProgressCell {
        case .no:
            return true
        case .yes:
            return self.progressCellViewModel != nil
        }
    }
    
    private func setIsSearchInProgress(newValue: Bool) {
        withAnimation { isSearchInProgress = newValue }
        if newValue {
            performSearchWith(newSearchText: searchText)
        } else {
            stopSearch()
        }
    }
    
    private var showContentUnavailableView: Bool {
        if let viewModel, !viewModel.isEmpty { return false }
        if let archivedDiscussionsCellModel, archivedDiscussionsCellModel.atLeastOneDiscussionIsArchived, !isSearchInProgress { return false }
        return true
    }

    
    var body: some View {
        VStack {
            if let viewModel, archivedDiscussionsCellModelAvailbleOrNotRequired, locationsCellViewModelAvailableOrNotRequired {
                Group {
                    if showContentUnavailableView {
                        if self.isSearching {
                            ObvContentUnavailableView.search
                        } else {
                            ObvContentUnavailableView(viewModel.contentUnavailableViewModel)
                        }
                    } else {
                        List(selection: $selection) {
                            // Section: Progress cell
                            if let progressCellViewModel, progressCellViewModel > 0, progressCellViewModel < 1.0, !isSearchInProgress {
                                ProgressCellView(fractionCompleted: progressCellViewModel)
                            }
                            // Section: Tip cell
                            if let tipCellViewModelAndDataSourceActions, !isSearchInProgress {
                                TipCellView(viewModel: tipCellViewModelAndDataSourceActions.model,
                                            actions: actions,
                                            dataSourceActions: tipCellViewModelAndDataSourceActions.dataSourceActions)
                                    .listRowSeparator(.hidden, edges: .top)
                            }
                            // Section: Location cell
                            if let locationsCellViewModel, locationsCellViewModel.isRelevantToDisplay, !isSearchInProgress {
                                LocationsCellView(viewModel: locationsCellViewModel, actions: actions)
                                    .listRowSeparator(.hidden, edges: .top)
                            }
                            // Section: Archive cell
                            if let archivedDiscussionsCellModel, archivedDiscussionsCellModel.atLeastOneDiscussionIsArchived, !isSearchInProgress {
                                SectionForArchivedDiscussionsCellView(viewModel: archivedDiscussionsCellModel, actions: actions)
                            }
                            // Section: List of recent discussions
                            SectionForListOfDiscussionsView(ownedCryptoId: self.currentOwnedCryptoId,
                                                            identifiersOfPinnedDiscussions: viewModel.identifiersOfPinnedDiscussions,
                                                            identifiersOfUnpinnedDiscussions: viewModel.identifiersOfUnpinnedDiscussions,
                                                            dataSource: dataSource,
                                                            avatarViewDataSource: avatarViewDataSource,
                                                            actions: actions,
                                                            isSearchInProgress: self.isSearchInProgress)
                            // Since .safeAreaPadding is only available on iOS17+, we artifically add padding at the bottom.
                            // This allows to make sure the "Add a contact" button does not overlap the last discussion
                            Spacer()
                                .listRowSeparator(.hidden)
                                .padding(.bottom, 50)
                        }
                        .listStyle(.plain)
                        .refreshable {
                            await internalActions.userWantsToGetNewMessages()
                        }
                    }
                }
                .onChange(of: searchText) { newSearchText in performSearchWith(newSearchText: newSearchText) }
                .onChange(of: isSearching) { newValue in setIsSearchInProgress(newValue: newValue) }
            } else {
                ProgressView()
            }
        }
    }
    
}



// MARK: - Internal view: SectionForArchivedDiscussions

private struct SectionForArchivedDiscussionsCellView: View {
    
    let viewModel: ObvArchivedDiscussionsCellModel
    let actions: ArchivedDiscussionsCellActionsProtocol
    
    var body: some View {
        Section {
            ArchivedDiscussionsCellView(viewModel: viewModel, actions: actions)
        }
    }
    
}



// MARK: - Internal view: SectionForListOfDiscussionsView

protocol SectionForListOfDiscussionsViewActionsProtocol: AnyObject, DiscussionCellViewActionsProtocol {
    func userWantsToReorderPinnedDiscussions(identifiersOfPinnedDiscussions: [ObvDiscussionsListViewModel.DiscussionIdentifier]) async throws
}


private struct SectionForListOfDiscussionsView: View {
    
    let ownedCryptoId: ObvCryptoId
    let identifiersOfPinnedDiscussions: [ObvDiscussionsListViewModel.DiscussionIdentifier]
    let identifiersOfUnpinnedDiscussions: [ObvDiscussionsListViewModel.DiscussionIdentifier]
    let dataSource: ObvDiscussionsListViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let actions: SectionForListOfDiscussionsViewActionsProtocol
    let isSearchInProgress: Bool

    @State var preventMoveAsPrecedentMoveIsOngoing: Bool = false

    /// Returns nil when move is not allowed.
    private func onMoveOfPinnedDiscussion(_ fromOffsets: IndexSet, _ toOffset: Int) {
        guard !preventMoveAsPrecedentMoveIsOngoing else { return }
        preventMoveAsPrecedentMoveIsOngoing = true
        var newOrderOfIdentifiersOfPinnedDiscussions = identifiersOfPinnedDiscussions
        newOrderOfIdentifiersOfPinnedDiscussions.move(fromOffsets: fromOffsets, toOffset: toOffset)
        Task {
            do {
                try await actions.userWantsToReorderPinnedDiscussions(identifiersOfPinnedDiscussions: newOrderOfIdentifiersOfPinnedDiscussions)
                preventMoveAsPrecedentMoveIsOngoing = false
            } catch {
                assertionFailure()
            }
        }
    }
    
    
    private var allDiscussionIdentifiers: [ObvDiscussionsListViewModel.DiscussionIdentifier] {
        identifiersOfPinnedDiscussions + identifiersOfUnpinnedDiscussions
    }

    
    private var verticalPadding: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return 0
        } else {
            return 0
        }
    }
    
    var body: some View {
        Section {
            if #available(iOS 16, *) { // Do not put this test inside the ForEach
                ForEach(allDiscussionIdentifiers, id: \.self) { discussionIdentifier in
                    DiscussionCellView(discussionIdentifier: discussionIdentifier, dataSource: dataSource, avatarViewDataSource: avatarViewDataSource, actions: actions, internalActions: self)
                        .moveDisabled(!identifiersOfPinnedDiscussions.contains(discussionIdentifier) || isSearchInProgress) // pinned discussions are the only ones that can be moved (and no move during a search)
                        .padding(.vertical, verticalPadding)
                }
                .onMove(perform: onMoveOfPinnedDiscussion) // This is called for pinned discussions only (see .moveDisabled())
            } else {
                ForEach(allDiscussionIdentifiers) { discussionIdentifier in
                    DiscussionCellView(discussionIdentifier: discussionIdentifier, dataSource: dataSource, avatarViewDataSource: avatarViewDataSource, actions: actions, internalActions: self)
                        .moveDisabled(!identifiersOfPinnedDiscussions.contains(discussionIdentifier) || isSearchInProgress) // pinned discussions are the only ones that can be moved (and no move during a search)
                        .padding(.vertical, verticalPadding)
                        .listRowSeparator(.hidden)
                }
                .onMove(perform: onMoveOfPinnedDiscussion) // This is called for pinned discussions only (see .moveDisabled())
            }
        }
    }
}


// MARK: - Implementing certain actions of the child views

extension SectionForListOfDiscussionsView: DiscussionCellViewInternalActionsProtocol {
    
    /// When the user swipe a cells and pin/unpins a discussion, the cell eventually calls this method. We leverage this view's actions to pin/unpin the discussion.
    func userTappedPinDiscussionButton(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) {
        guard !preventMoveAsPrecedentMoveIsOngoing else { return }
        preventMoveAsPrecedentMoveIsOngoing = true
        Task {
            do {
                var newOrderOfIdentifiersOfPinnedDiscussions = try await dataSource.getIdentifiersOfCurrentlyPinnedDiscussions(ownedCryptoId: self.ownedCryptoId)
                if newOrderOfIdentifiersOfPinnedDiscussions.contains(discussionIdentifier) {
                    newOrderOfIdentifiersOfPinnedDiscussions.removeAll(where: { $0 == discussionIdentifier })
                } else {
                    newOrderOfIdentifiersOfPinnedDiscussions.append(discussionIdentifier)
                }
                try await actions.userWantsToReorderPinnedDiscussions(identifiersOfPinnedDiscussions: newOrderOfIdentifiersOfPinnedDiscussions)
                preventMoveAsPrecedentMoveIsOngoing = false
            } catch {
                assertionFailure()
            }
        }
    }
    
}


















// MARK: - Previews


#if DEBUG

@MainActor
private final class DataSourceForPreviews {
    
    private var cachedPhotoURLs = Set<URL>()
    
    private var streamUUIDForObvDiscussionsListViewModel: UUID?
    private var continuationForObvDiscussionsListViewModel: AsyncStream<ObvDiscussionsListViewModel>.Continuation?
    
}


extension DataSourceForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvAvatarView, photoURL: URL, avatarSize: ObvAvatarSize) async throws -> UIImage? {
        if !cachedPhotoURLs.contains(photoURL) {
            cachedPhotoURLs.insert(photoURL)
            try await Task.sleep(seconds: Double.random(in: 2...4))
        }
        return UIImage.avatarImageForURL(photoURL)
    }
    
    func fetchAvatarFromCache(_ view: ObvAvatarView, photoURL: URL, avatarSize: ObvAvatarSize) -> UIImage? {
        return nil
    }
    
}

extension DataSourceForPreviews: DiscussionCellViewDataSource {
    
    func getAsyncStreamOfUserActivityDiscussionIdentifier(_ view: DiscussionCellView) throws -> (streamUUID: UUID, stream: AsyncStream<ObvDiscussionsListViewModel.DiscussionIdentifier?>) {
        let stream = AsyncStream(ObvDiscussionsListViewModel.DiscussionIdentifier?.self) { (continuation: AsyncStream<ObvDiscussionsListViewModel.DiscussionIdentifier?>.Continuation) in
            let model = ObvDiscussionsListViewModel.DiscussionIdentifier.obvDiscussionIdentifier(ObvDiscussionIdentifier.sampleDatas[0])
            continuation.yield(model)
        }
        return (UUID(), stream)
    }

    
    func finishAsyncStreamOfUserActivityDiscussionIdentifier(_ view: DiscussionCellView, streamUUID: UUID) {
        // Not implemented in previews
    }
    
    
    func getAsyncStreamOfObvDiscussionCellViewModel(_ view: DiscussionCellView, discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvDiscussionCellViewModel>) {
        let stream = AsyncStream(ObvDiscussionCellViewModel.self) { (continuation: AsyncStream<ObvDiscussionCellViewModel>.Continuation) in
            let model = ObvDiscussionCellViewModel.sampleData(for: discussionIdentifier)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfObvDiscussionCellViewModel(_ view: DiscussionCellView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
    func getInitialObvDiscussionCellViewModel(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) -> ObvDiscussionCellViewModel? {
        let model = ObvDiscussionCellViewModel.sampleData(for: discussionIdentifier)
        return model
    }

}

extension DataSourceForPreviews: OwnedIdentityChooserViewDataSource {

    func getAsyncStreamOfOwnedIdentityChooserViewModel(_ view: OwnedIdentityChooserInnerView, currentOwnedCryptoId: ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityChooserViewModel>) {
        let stream = AsyncStream(OwnedIdentityChooserViewModel.self) { (continuation: AsyncStream<OwnedIdentityChooserViewModel>.Continuation) in
            let model = OwnedIdentityChooserViewModel.sampleDatas[0]
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfOwnedIdentityChooserViewModel(_ view: OwnedIdentityChooserInnerView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
}

extension DataSourceForPreviews: ObvProfilePictureBarButtonItemViewDataSource {
    
    func getAsyncStreamOfObvProfilePictureBarButtonItemViewModel(_ view: ObvProfilePictureBarButtonItemView, ownedCryptoId: ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<ObvProfilePictureBarButtonItemViewModel>) {
        let stream = AsyncStream(ObvProfilePictureBarButtonItemViewModel.self) { (continuation: AsyncStream<ObvProfilePictureBarButtonItemViewModel>.Continuation) in
            let model = ObvProfilePictureBarButtonItemViewModel.sampleDataForOwnedCryptoId(ObvCryptoId.sampleDatasForOwnedCryptoId[0])
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    

    func finishAsyncStreamOfObvProfilePictureBarButtonItemViewModel(_ view: ObvProfilePictureBarButtonItemView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    

    func getNextOwnedCryptoId(_ view: ObvProfilePictureBarButtonItemView, currentOwnedCryptoId: ObvCryptoId) async throws -> ObvCryptoId {
        guard let currentIndex = ObvCryptoId.sampleDatasForOwnedCryptoId.firstIndex(where: { $0 == currentOwnedCryptoId }) else {
            return currentOwnedCryptoId
        }
        let newIndex = (currentIndex + 1) % ObvCryptoId.sampleDatasForOwnedCryptoId.count
        let newCurrentOwnedCryptoId = ObvCryptoId.sampleDatasForOwnedCryptoId[newIndex]
        return newCurrentOwnedCryptoId
    }
    
}

extension DataSourceForPreviews: ObvDiscussionsListViewDataSource {
    
    func getAsyncStreamOfObvDiscussionsListViewModel(_ view: ObvDiscussionsListView, ownedCryptoId: ObvCryptoId, initialSearchText: String?) throws -> (streamUUID: UUID, stream: AsyncStream<ObvDiscussionsListViewModel>) {
        self.continuationForObvDiscussionsListViewModel?.finish()
        self.continuationForObvDiscussionsListViewModel = nil
        let streamUUID = UUID()
        self.streamUUIDForObvDiscussionsListViewModel = streamUUID
        let stream = AsyncStream(ObvDiscussionsListViewModel.self) { (continuation: AsyncStream<ObvDiscussionsListViewModel>.Continuation) in
            self.continuationForObvDiscussionsListViewModel = continuation
            continuation.yield(ObvDiscussionsListViewModel.sampleDatas[0])
        }
        return (streamUUID, stream)
    }
    
    func finishAsyncStreamOfObvDiscussionsListViewModel(_ view: ObvDiscussionsListView, streamUUID: UUID) {
        if self.streamUUIDForObvDiscussionsListViewModel == streamUUID {
            self.continuationForObvDiscussionsListViewModel?.finish()
            self.continuationForObvDiscussionsListViewModel = nil
            self.streamUUIDForObvDiscussionsListViewModel = nil
        } else {
            //assert(continuationForObvDiscussionsListViewModel == nil)
        }
    }
    
    func filterAsyncStreamOfObvDiscussionsListViewModel(_ view: ObvDiscussionsListView, streamUUID: UUID, searchStatus: ObvDiscussionsListViewModel.SearchStatus) {
        switch searchStatus {
        case .notPerformingSearch:
            print("Not performing search")
        case .performingSearch(let searchText):
            print("Performing search: \(String(describing: searchText))")
        }
        // We don't filter in previews
    }

    func getIdentifiersOfCurrentlyPinnedDiscussions(ownedCryptoId: ObvCryptoId) async throws -> [ObvDiscussionsListViewModel.DiscussionIdentifier] {
        // Not implemented in previews
        return []
    }
    
}


@MainActor
private final class ActionsForPreviews {
    
}


extension ActionsForPreviews: ObvProfilePictureBarButtonItemViewActionsProtocol {
    
    func userDidLongPressOnProfilePicture(_ view: ObvProfilePictureBarButtonItem.ObvProfilePictureBarButtonItemView) {
        print("User did long press on profile picture")
    }
    
    func userWantsToEditOwnedIdentity(_ view: ObvProfilePictureBarButtonItem.ObvProfilePictureBarButtonItemView, ownedCryptoId: ObvTypes.ObvCryptoId) async {
        print("User wants to edit owned identity")
    }
    
    func userWantsToAddNewProfile(_ view: ObvProfilePictureBarButtonItem.ObvProfilePictureBarButtonItemView) async {
        print("User wants to add new profile")
    }
    
}

extension ActionsForPreviews: MainMenuActionsProtocol {
    
    func userWantsToNavigateToSettings() {
        print("User wants to navigate to settings")
    }
    
    func userWantsToNavigateToStorageManagement() {
        print("User wants to navigate to storage management")
    }
    
    func userWantsToGetNewMessages() {
        print("Userwants to get new messages")
    }

}

extension ActionsForPreviews: TipCellViewActionsProtocol {
    
    func userWantsToSetupNewBackups() {
        print("User wants to setup new backups")
    }
    
    func userWantsToDisplayBackupKey() {
        print("User wants to display backup key")
    }
    
    func userWantsToSetDoSendReadReceipt(doSendReadReceipt: Bool) {
        print("User wants to set do send read receipt")
    }
    
    func userWantsToDismissTip() {
        print("User wants to dismiss tip")
    }
    
    func userWantsToNavigateToSettingsToChangeDiscussionsUnarchivingBehavior(_ view: ArchivedDiscussionsHelpMessageView) async {
        print("User wants to navigate to settings to change discussions unarchiving behavior")
    }
    
    func userWantsToDiscoverOlvidPlus(_ view: OlvidPlusTipView) {
        print("User wants to discover Olvid+")
    }

    func userWantsToDismissOlvidPlusSuccessfulSubscriptionView(_ view: OlvidPlusSuccessfulSubscriptionView) {
        print("User wants to dismiss Olvid+ successful subscription view")
    }
    
    func userWantsToDismissOSUpgradeCell(_ view: OSUpgradeCell) {
        print("User wants to dismiss OS upgrade cell")
    }
    
}

extension ActionsForPreviews: ProfileIsDeactivatedOnThisDeviceTipViewActions {
    
    func userWantsToShowThisDeviceReactivationOptions(_ view: ProfileIsDeactivatedOnThisDeviceTipView, ownedCryptoId: ObvCryptoId) {
        print("User wants to show this device reactivation options")
    }
    
}

extension ActionsForPreviews: RequestUserNotificationsAuthorizationTipViewActions {
    
    func userWantsToRequestNotificationsAuthorization(_ view: RequestUserNotificationsAuthorizationTipView) {
        print("User wants to request notifications authorization")
    }
    
}

extension ActionsForPreviews: OwnedDeviceExpriginSoonTipViewActions {
    
    func userWantsToDiscoverOlvidPlus(_ view: OwnedDeviceExpiringSoonTipView) {
        print("User wants to discover Olvid+")
    }
    
    func userWantsToManageTheirDevices(_ view: OwnedDeviceExpiringSoonTipView, ownedCryptoId: ObvCryptoId) {
        print("User wants to manage their devices")
    }
    
}

extension ActionsForPreviews: LocationsCellViewActions {
    
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice() async throws {
        print("User wants to stop all continuous sharing from current physical device")
    }
    
    func userWantsToShowMapToConsultLocationSharedContinously(ownedCryptoId: ObvTypes.ObvCryptoId) async throws {
        print("User wants to show map to consult location shared continously: \(ownedCryptoId)")
    }
    
}

extension ActionsForPreviews: ArchivedDiscussionsCellActionsProtocol {
    
    func userWantsToNavigateToListOfArchivedDiscussions() {
        print("User wants to navigate to list of archived discussions")
    }
    
}

extension ActionsForPreviews: SectionForListOfDiscussionsViewActionsProtocol {
    
    func userWantsToReorderPinnedDiscussions(identifiersOfPinnedDiscussions: [ObvDiscussionsListViewModel.DiscussionIdentifier]) async throws {
        print("User wants to reorder pinned discussions")
    }
    
    func userWantsToNavigateToDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) throws {
        print("User wants to navigate to discussion: \(discussionIdentifier)")
    }
    
    func userWantsToMarkAllMessagesAsReadInDiscussion(withIdentifier discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        print("User wants to marks all messages as read in discussion: \(discussionIdentifier)")
    }
    
    func userWantsToDeleteDiscussionButAsYetToConfirm(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        print("User wants to delete discussion but as yet to confirm: \(discussionIdentifier)")
    }
    
    func userWantsToArchiveDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        print("User wants to archive discussion: \(discussionIdentifier)")
    }
    
    func userWantsToUnarchiveDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        print("User wants to unarchive discussion: \(discussionIdentifier)")
    }
    
    func userWantsToMuteDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier, duration: ObvAppTypes.ObvMuteDurationOption) async throws {
        print("User wants to mute discussion")
    }
    
    func userWantsToUnmuteDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        print("User wants to unmute discussion")
    }
    
}

extension ActionsForPreviews: ObvDiscussionsListViewActionsProtocol {
    
    func userWantsToArchiveDiscussions(discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws {
        print("User wants to archive discussion: \(discussionIdentifiers.count)")
    }
    
    func userWantsToUnarchiveDiscussions(discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws {
        print("User wants to unarchive discussion: \(discussionIdentifiers.count)")
    }
    
    func userWantsToDeleteDiscussionFromThisDeviceAndHasConfirmed(discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws {
        print("User wants to delete discussion: \(discussionIdentifiers.count)")
    }
    
    func userDidSwitchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        print("User did switch current owned crypto id: \(newOwnedCryptoId.getIdentity().hexString().suffix(8))")
    }
    
    func userWantsToGetNewMessages() async throws {
        try await Task.sleep(seconds: 3)
    }
    
    func userTappedObvPlusButton() {
        print("Plus button tapped")
    }
    
}


private final class ArchivedDiscussionsCellDataSourceForPreviews: ArchivedDiscussionsCellDataSource {
    
    func getAsyncStreamOfObvArchivedDiscussionsCellModel(_ view: ObvDiscussionsListView, ownedCryptoId: ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<ObvArchivedDiscussionsCellModel>) {
        let stream = AsyncStream(ObvArchivedDiscussionsCellModel.self) { (continuation: AsyncStream<ObvArchivedDiscussionsCellModel>.Continuation) in
            Task {
                do {
                    let model = ObvArchivedDiscussionsCellModel(
                        atLeastOneDiscussionIsArchived: false,
                        numberOfArchivedPersistedDiscussionsWithNewMessages: 0)
                    continuation.yield(model)
                }
                try? await Task.sleep(seconds: 2)
                do {
                    let model = ObvArchivedDiscussionsCellModel(
                        atLeastOneDiscussionIsArchived: true,
                        numberOfArchivedPersistedDiscussionsWithNewMessages: 0)
                    continuation.yield(model)
                }
                try? await Task.sleep(seconds: 2)
                do {
                    let model = ObvArchivedDiscussionsCellModel(
                        atLeastOneDiscussionIsArchived: true,
                        numberOfArchivedPersistedDiscussionsWithNewMessages: 1)
                    continuation.yield(model)
                }
                try? await Task.sleep(seconds: 2)
                do {
                    let model = ObvArchivedDiscussionsCellModel(
                        atLeastOneDiscussionIsArchived: true,
                        numberOfArchivedPersistedDiscussionsWithNewMessages: 2)
                    continuation.yield(model)
                }
            }
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncStreamOfObvArchivedDiscussionsCellModel(_ view: ObvDiscussionsListView, streamUUID: UUID) {
        // Not implemented in previews
    }
    
}


private final class ObvLocationsCellViewDataSourceForPreviews: ObvLocationsCellViewDataSource {
    
    func getAsyncStreamOfLocationsCellViewModel(_ view: ObvDiscussionsListView, ownedCryptoId: ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<ObvLocationsCellViewModel>) {
        let stream = AsyncStream(ObvLocationsCellViewModel.self) { (continuation: AsyncStream<ObvLocationsCellViewModel>.Continuation) in
            Task {
//                continuation.yield(ObvLocationsCellViewModel.sampleData[0])
//                try? await Task.sleep(seconds: 2)
                continuation.yield(ObvLocationsCellViewModel.sampleData[1])
//                try? await Task.sleep(seconds: 2)
//                continuation.yield(ObvLocationsCellViewModel.sampleData[2])
//                try? await Task.sleep(seconds: 2)
//                continuation.yield(ObvLocationsCellViewModel.sampleData[3])
//                try? await Task.sleep(seconds: 2)
//                continuation.yield(ObvLocationsCellViewModel.sampleData[4])
//                try? await Task.sleep(seconds: 2)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfLocationsCellViewModel(_ view: ObvDiscussionsListView, streamUUID: UUID) {
        // Not implemented in previews
    }
    
    
}

@MainActor
private let locationsCellViewDataSourceForPreviews = ObvLocationsCellViewDataSourceForPreviews()

@MainActor
private let archiveCellDataSourceForPreviews = ArchivedDiscussionsCellDataSourceForPreviews()

@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

@MainActor
private let actionsForPreviews = ActionsForPreviews()

@MainActor
private let configurationForPreviews = ObvDiscussionsListViewConfiguration(
    showArchivedDiscussionsCell: .yes(dataSource: archiveCellDataSourceForPreviews),
    showLocationsCell: .yes(dataSource: locationsCellViewDataSourceForPreviews),
    showProgressCell: .no,
    showTipCell: .no,
    showProfilePictureBarButtonItem: .yes(profilePictureBarButtonItemViewDataSource: dataSourceForPreviews, ownedIdentityChooserViewDataSource: dataSourceForPreviews),
    showArchiveActionButtonInMenu: true,
    showUnarchiveActionButtonInMenu: true,
    showPlusButton: true)



private struct PreviewView: View {
    
    @State private var currentOwnedCryptoId = ObvCryptoId.sampleDatasForOwnedCryptoId[0]
    
    var body: some View {
        NavigationView {
            ObvDiscussionsListView(currentOwnedCryptoId: currentOwnedCryptoId,
                                   dataSource: dataSourceForPreviews,
                                   avatarViewDataSource: dataSourceForPreviews,
                                   actions: actionsForPreviews,
                                   configuration: configurationForPreviews)
        }
    }
}

#Preview {
    PreviewView()
}


#endif // DEBUG
