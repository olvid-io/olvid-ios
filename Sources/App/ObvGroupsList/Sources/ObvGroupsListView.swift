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
import ObvDesignSystem
import ObvSystemIcon
import ObvAppTypes
import ObvTypes
import ObvProfilePictureBarButtonItem
import ObvOwnedIdentityChooser
import ObvCells


@MainActor
public protocol ObvGroupsListViewDataSource: AnyObject {
    func getObvGroupsListViewModel(_ view: ObvGroupsListView, searchStatus: ObvGroupsListViewModel.SearchStatus) throws -> ObvGroupsListViewModel?
    func getAsyncStreamOfObvGroupsListViewModel(_ view: ObvGroupsListView, initialSearchStatus: ObvGroupsListViewModel.SearchStatus) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvGroupsListViewModel>)
    func finishAsyncStreamOfObvGroupsListViewModel(_ view: ObvGroupsListView, streamUUID: UUID)
    func filterAsyncStreamOfObvGroupsListViewModel(_ view: ObvGroupsListView, streamUUID: UUID, searchStatus: ObvGroupsListViewModel.SearchStatus)
}


@MainActor
public protocol ObvGroupsListViewActions: AnyObject, ObvProfilePictureBarButtonItemViewActionsProtocol, MainMenuActionsProtocol, ObvPlusButtonActionsDelegate {
    func userWantsToCreateNewGroup(_ view: ObvGroupsListView, ownedCryptoId: ObvCryptoId)
    func userDidSwitchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async // Allows the rest of the app to be notified when the user switches to another profile in from this view or one of its decendents.
}




public struct ObvGroupsListViewModel: Sendable, Equatable {
    
    let currentOwnedCryptoId: ObvCryptoId
    let identifiersOfGroupsAdministrated: [ObvGroupCellViewModel.GroupIdentifier]
    let identifiersOfGroupsJoined: [ObvGroupCellViewModel.GroupIdentifier]
    
    public init(currentOwnedCryptoId: ObvCryptoId, identifiersOfGroupsAdministrated: [ObvGroupCellViewModel.GroupIdentifier], identifiersOfGroupsJoined: [ObvGroupCellViewModel.GroupIdentifier]) {
        self.currentOwnedCryptoId = currentOwnedCryptoId
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


/// A tiny observable wrapper used to request programmatic scrolling inside `ObvGroupsListView`.
///
/// `ItemToScrollToWrapper` is owned outside the SwiftUI view hierarchy (e.g., by a hosting
/// controller or coordinator) and injected into `ObvGroupsListView`. To trigger a scroll, set
/// `itemToScrollTo` to a specific `ObvGroupCellViewModel.GroupIdentifier`. The view observes this
/// change and scrolls to the corresponding row using a `ScrollViewReader`.
///
/// Flow
/// 1. External owner sets `itemToScrollTo` to a target group identifier.
/// 2. `ObvGroupsListView` detects the change and calls its internal
///    `performProgrammaticScroll(scrollViewProxy:)`.
/// 3. The view performs an animated scroll and then resets `itemToScrollTo` back to `nil` so that
///    the same target can be used again in the future without additional bookkeeping by the caller.
///
/// Why not `scrollPosition(id:anchor:)`?
/// Because `ObvGroupsListView` uses a SwiftUI `List` (not a plain `ScrollView`), the `scrollPosition`
/// APIs are not applicable for this layout. Using a `ScrollViewReader` with stable `id`s is the
/// recommended approach for Lists.
///
/// Ownership and lifecycle
/// - Keep this wrapper outside the view to survive view reloads and identity changes, ensuring that
///   scroll requests are not lost.
///
/// Threading and animation
/// - Updates to `itemToScrollTo` must occur on the main actor.
/// - The view performs the scroll with animation on the main thread.
///
/// Re-triggering a scroll
/// - Since the view resets `itemToScrollTo` to `nil` after each scroll, you can re-trigger the same
///   destination later by simply assigning it again.
///
/// Example
/// ```swift
/// // In your hosting controller or coordinator
/// let scroller = ItemToScrollToWrapper()
/// let view = ObvGroupsListView(
///     currentOwnedCryptoId: currentId,
///     dataSource: dataSource,
///     profilePictureBarButtonItemViewDataSource: profileSource,
///     avatarViewDataSource: avatarSource,
///     actions: actions,
///     itemToScrollToWrapper: scroller
/// )
///
/// // Later, when you want to scroll to a specific group
/// scroller.itemToScrollTo = .obvGroupIdentifier(targetGroupId)
/// // The view will scroll and then automatically reset the value to `nil`.
/// ```
final class ItemToScrollToWrapper: ObservableObject {
    @Published var itemToScrollTo: ObvGroupCellViewModel.GroupIdentifier?
    @Published var scrollToTop: Bool = false
}


@MainActor
public protocol ObvGroupsListViewNavigation: ObvGroupCellViewNavigation {
    
}

/// A SwiftUI view that displays the list of groups for the current owned identity.
///
/// `ObvGroupsListView` renders two sections:
/// - Groups you administer (with a prominent “Create group” action)
/// - Groups you’ve joined
///
/// Data flows in via an async stream provided by `ObvGroupsListViewDataSource`. The view
/// updates reactively as new `ObvGroupsListViewModel` values arrive. It also supports:
/// - Profile switching via the profile picture bar button item (notifies `actions`)
/// - Search, with server-side filtering delegated to the data source
/// - Programmatic scrolling to a specific group using `ItemToScrollToWrapper`
///
/// Dependencies:
/// - `dataSource`: Supplies the view model and handles search filtering
/// - `actions`: Handles navigation and user intents (create group, menus, etc.)
/// - `avatarViewDataSource`: Provides avatars for group cells
/// - `profilePictureBarButtonItemViewDataSource`: Streams profile info for the leading item
///
/// Notes:
/// - Uses `ScrollViewReader` with stable `id`s to support programmatic scrolling within a `List`.
/// - Resets content immediately on `onAppear()` to reflect current profile without animations.
/// - Hides the “+” floating action button while search is active.
public struct ObvGroupsListView: View {
    
    @State var currentOwnedCryptoId: ObvCryptoId
    let dataSource: ObvGroupsListViewDataSource
    let groupCellViewDataSource: any ObvGroupCellViewDataSource
    let profilePictureBarButtonItemViewDataSource: any ObvProfilePictureBarButtonItemViewDataSource
    let avatarViewDataSource: any ObvAvatarViewDataSource
    let ownedIdentityChooserViewDataSource: any OwnedIdentityChooserViewDataSource
    let actions: ObvGroupsListViewActions
    let navigation: any ObvGroupsListViewNavigation
    @ObservedObject var itemToScrollToWrapper: ItemToScrollToWrapper
    
    @State private var streamedViewModel: ObvGroupsListViewModel?
    @State private var streamUUIDForViewModel: UUID? // Required as a state to implement search
    
    // Implementing search
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var isSearchInProgress: Bool = false
    @State private var highlightedGroupIdentifier: ObvGroupCellViewModel.GroupIdentifier? = nil
    
    // Smart hiding/showing of the create group button in the navigation bar
    @State private var shouldShowCreateGroupButtonInToolbar: Bool = false
    
    private func onTaskForAsyncStreamOfObvGroupsListViewModel() async {
        do {
            let searchStatus: ObvGroupsListViewModel.SearchStatus
            if isSearchInProgress {
                searchStatus = .performingSearch(searchText: searchText)
            } else {
                searchStatus = .notPerformingSearch
            }
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfObvGroupsListViewModel(self, initialSearchStatus: searchStatus)
            self.streamUUIDForViewModel = streamUUID
            for await receivedModel in stream {
                guard self.streamedViewModel != receivedModel || self.currentOwnedCryptoId != receivedModel.currentOwnedCryptoId else { continue }
                if self.streamedViewModel == nil {
                    self.streamedViewModel = receivedModel
                    self.currentOwnedCryptoId = receivedModel.currentOwnedCryptoId
                } else {
                    withAnimation {
                        self.streamedViewModel = receivedModel
                        self.currentOwnedCryptoId = receivedModel.currentOwnedCryptoId
                    }
                }
            }
            if self.streamUUIDForViewModel == streamUUID {
                self.streamUUIDForViewModel = nil
            }
            dataSource.finishAsyncStreamOfObvGroupsListViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    

    /// Updates the view's content immediately when it appears. Required when the current was changed while this
    /// view was not on screen.
    ///
    /// This method ensures the view reflects the latest profile data **before** it appears on screen
    /// by skipping animations.
    private func onAppear() {
        highlightedGroupIdentifier = nil
        let searchStatus: ObvGroupsListViewModel.SearchStatus
        if isSearchInProgress {
            searchStatus = .performingSearch(searchText: searchText)
        } else {
            searchStatus = .notPerformingSearch
        }
        do {
            guard let receivedModel = try dataSource.getObvGroupsListViewModel(self, searchStatus: searchStatus) else { return }
            self.streamedViewModel = receivedModel
            self.currentOwnedCryptoId = receivedModel.currentOwnedCryptoId
        } catch {
            assertionFailure()
        }
    }
    
        
    private func userTappedCreateGroupButton() {
        actions.userWantsToCreateNewGroup(self, ownedCryptoId: currentOwnedCryptoId)
    }
    
    private func performSearchWith(newSearchText: String?) {
        guard let streamUUIDForViewModel else { return }
        dataSource.filterAsyncStreamOfObvGroupsListViewModel(self, streamUUID: streamUUIDForViewModel, searchStatus: .performingSearch(searchText: newSearchText))
    }

    private func stopSearch() {
        guard let streamUUIDForViewModel else { return }
        dataSource.filterAsyncStreamOfObvGroupsListViewModel(self, streamUUID: streamUUIDForViewModel, searchStatus: .notPerformingSearch)
    }

    private func setIsSearchInProgress(newValue: Bool) {
        withAnimation { isSearchInProgress = newValue }
        if newValue {
            performSearchWith(newSearchText: searchText)
        } else {
            stopSearch()
        }
    }
    
    
    /// Most notably called when the user changes her current profile using the `ObvProfilePictureBarButtonItemView`.
    /// In that case, we notify using the `userDidSwitchCurrentOwnedCryptoId`. Eventually, the datasource should stream
    /// a model for that new current profile.
    private func onChangeOfCurrentOwnedCryptoId(newOwnedCryptoId: ObvCryptoId) {
        guard self.streamedViewModel?.currentOwnedCryptoId != newOwnedCryptoId else { return }
        withAnimation {
            self.streamedViewModel = nil
        }
        Task {
            await actions.userDidSwitchCurrentOwnedCryptoId(to: newOwnedCryptoId)
        }
    }
    
    
    private func performProgrammaticScroll(scrollViewProxy: ScrollViewProxy) {
        if let itemToScrollTo = itemToScrollToWrapper.itemToScrollTo {
            // Reset the wrapper so the same target can be used again later
            itemToScrollToWrapper.itemToScrollTo = nil // Scroll only once
            withAnimation {
                scrollViewProxy.scrollTo(itemToScrollTo, anchor: .center)
            }
            Task {
                try? await Task.sleep(milliseconds: 300) // Approximate duration of the scroll
                withAnimation {
                    highlightedGroupIdentifier = itemToScrollTo
                }
            }
        } else if itemToScrollToWrapper.scrollToTop {
            itemToScrollToWrapper.scrollToTop = false
            withAnimation {
                print("DO SCROLL TO TOP")
                scrollViewProxy.scrollTo(Self.topItem, anchor: .center)
            }
        }
        
    }

    private func userTappedCreateGroupButtonInMenu() {
        self.userTappedCreateGroupButton()
    }

    fileprivate static let topItem = "topItem" // id of the top item, to perfom programmatic scroll to top
    
    public var body: some View {
        ZStack {
            if let streamedViewModel {
                ScrollViewReader { scrollViewProxy in
                    ObvGroupsListInternalView(dataSource: dataSource,
                                              groupCellViewDataSource: groupCellViewDataSource,
                                              avatarViewDataSource: avatarViewDataSource,
                                              actions: actions,
                                              navigation: navigation,
                                              streamedViewModel: streamedViewModel,
                                              userTappedCreateGroupButton: userTappedCreateGroupButton,
                                              isSearching: $isSearching,
                                              highlightedGroupIdentifier: $highlightedGroupIdentifier,
                                              shouldShowCreateGroupButtonInToolbar: $shouldShowCreateGroupButtonInToolbar,
                                              isSearchInProgress: $isSearchInProgress)
                    .onChange(of: itemToScrollToWrapper.itemToScrollTo) { _ in performProgrammaticScroll(scrollViewProxy: scrollViewProxy) }
                    .onChange(of: itemToScrollToWrapper.scrollToTop) { _ in performProgrammaticScroll(scrollViewProxy: scrollViewProxy) }
                }
            } else {
                ProgressView()
            }
            if !isSearchInProgress {
                ObvPlusButton(actions: actions)
            }
        }
        .task(onTaskForAsyncStreamOfObvGroupsListViewModel)
        .onAppear(perform: onAppear)
        .onChange(of: isSearching) { newValue in setIsSearchInProgress(newValue: newValue) }
        .onChange(of: searchText) { newSearchText in performSearchWith(newSearchText: newSearchText) }
        .onChange(of: currentOwnedCryptoId, perform: { newOwnedCryptoId in onChangeOfCurrentOwnedCryptoId(newOwnedCryptoId: newOwnedCryptoId) })
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .automatic, prompt: Text("SEARCH"))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Groups").font(.system(size: 20.0, weight: .heavy, design: .default))
            }
            ToolbarItem(placement: .navigationBarLeading) {
                ObvProfilePictureBarButtonItemView(currentOwnedCryptoId: $currentOwnedCryptoId,
                                                   dataSource: profilePictureBarButtonItemViewDataSource,
                                                   avatarViewDataSource: avatarViewDataSource,
                                                   ownedIdentityChooserViewDataSource: ownedIdentityChooserViewDataSource,
                                                   actions: actions)
            }
            .sharedBackgroundVisibilityOniOS26(.hidden)
            ToolbarItemGroup(placement: .topBarTrailing) {
                if shouldShowCreateGroupButtonInToolbar {
                    if #available(iOS 26, *) {
                        Button(action: userTappedCreateGroupButton) {
                            Text("CREATE_GROUP_WITH_OWN_PERMISSION_ADMIN")
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
                MainMenu(actions: actions,
                         userTappedCreateGroupButtonInMenu: userTappedCreateGroupButtonInMenu)
            }
        }
    }
    
}


@MainActor
public protocol MainMenuActionsProtocol {
    func userWantsToNavigateToSettings(_ view: ObvGroupsListView.MainMenu)
    func userWantsToNavigateToStorageManagement(_ view: ObvGroupsListView.MainMenu)
}


extension ObvGroupsListView {
    
    public struct MainMenu: View {
        
        let actions: MainMenuActionsProtocol
        let userTappedCreateGroupButtonInMenu: () -> Void
        
        private func userTappedSettings() {
            actions.userWantsToNavigateToSettings(self)
        }
        
        private func userTappedStorageManagement() {
            actions.userWantsToNavigateToStorageManagement(self)
        }
        
        private var systemIconForMenuLabel: SystemIcon {
            if #available(iOS 26, *) {
                return .ellipsis
            } else {
                return .ellipsisCircle
            }
        }
        
        public var body: some View {
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
                    Button(action: userTappedCreateGroupButtonInMenu) {
                        Label(title: { Text("CREATE_GROUP_WITH_OWN_PERMISSION_ADMIN") }, icon: { Image(systemIcon: .person3Fill) })
                    }
                }
            } label: {
                Image(systemIcon: systemIconForMenuLabel)
            }
        }
        
    }
    
}


// MARK: - Internal View

private struct ObvGroupsListInternalView: View {
    
    let dataSource: ObvGroupsListViewDataSource
    let groupCellViewDataSource: ObvGroupCellViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let actions: ObvGroupsListViewActions
    let navigation: ObvGroupsListViewNavigation
    let streamedViewModel: ObvGroupsListViewModel
    let userTappedCreateGroupButton: () -> Void
    @Binding var isSearching: Bool
    @Binding var highlightedGroupIdentifier: ObvGroupCellViewModel.GroupIdentifier?
    @Binding var shouldShowCreateGroupButtonInToolbar: Bool
    @Binding var isSearchInProgress: Bool

    @Environment(\.isSearching) var environmentIsSearching
    
    @State private var isCreateGroupButtonVisible: Bool = true
    

    /// Synchronizes the visibility of the toolbar “Create group” button with the inline
    /// button inside the list section.
    ///
    /// Called whenever `isCreateGroupButtonVisible` changes (see the inline button’s
    /// `.onScrollVisibilityChangeOniOS18` handler). The goal is to avoid showing two
    /// identical affordances at once:
    /// - If the inline button is visible on screen, the toolbar button is hidden.
    /// - If the inline button scrolls off screen, the toolbar button is shown.
    private func onChangeOfIsCreateGroupButtonVisible() {
        print("isCreateGroupButtonVisible: \(isCreateGroupButtonVisible)")
        if isCreateGroupButtonVisible {
            withAnimation {
                self.shouldShowCreateGroupButtonInToolbar = false
            }
        } else {
            withAnimation {
                self.shouldShowCreateGroupButtonInToolbar = true
            }
        }
    }
    
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
                                    
                                    GroupThatYouAdministerSectionHeader(userTappedCreateGroupButton: userTappedCreateGroupButton,
                                                                        isSearchInProgress: $isSearchInProgress)
                                    .id(ObvGroupsListView.topItem) // Allows scrolling to top
                                    .padding([.horizontal, .top])
                                    .padding(streamedViewModel.identifiersOfGroupsAdministrated.isEmpty ? [.bottom] : [])
                                    .padding(.bottom, streamedViewModel.identifiersOfGroupsAdministrated.isEmpty ? 0 : 8)
                                    .onScrollVisibilityChangeOniOS18(threshold: 0.01) { isCreateGroupButtonVisible = $0 }
                                    
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
                .contentMarginsOniOS17(.bottom, EdgeInsets(top: 0, leading: 0, bottom: 100, trailing: 0 )) // Adds space for the "Add a contact" button
                
            }
            
        } // Group
        .background(Color(UIColor.systemGroupedBackground))
        .onChange(of: environmentIsSearching) { newValue in isSearching = newValue }
        .onChange(of: isCreateGroupButtonVisible) { _ in onChangeOfIsCreateGroupButtonVisible() }

    }
    
}


// MARK: - Internal view

private struct ListOfGroups: View {
    
    let identifiersOfGroups: [ObvGroupCellViewModel.GroupIdentifier]
    let groupCellViewDataSource: ObvGroupCellViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let navigation: ObvGroupCellViewNavigation
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


// MARK: - Internal view

private struct GroupThatYouAdministerSectionHeader: View {
    
    let userTappedCreateGroupButton: () -> Void
    @Binding var isSearchInProgress: Bool
    
    var body: some View {
        VStack(alignment: .leading) {
            
            HStack {
                Text("GROUPS_THAT_YOU_ADMINISTER")
                    .font(.headline)
                    .padding(.bottom, isSearchInProgress ? 0 : 4)
                Spacer(minLength: 0)
            }
            
            if !isSearchInProgress {
                Button(action: userTappedCreateGroupButton) {
                    HStack {
                        Spacer(minLength: 0)
                        Label(title: {
                            Text("CREATE_GROUP_WITH_OWN_PERMISSION_ADMIN")
                        }, icon: {
                            Image(systemIcon: .person3)
                                .foregroundStyle(.white)
                        })
                        .padding(.vertical, 8)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            
        }
    }
}



#if DEBUG

@MainActor
private final class DataSourceAndActionsForPreviews {
    
    private var currentUnfilteredViewModel: ObvGroupsListViewModel?
    private var continuation: AsyncStream<ObvGroupsListViewModel>.Continuation?
    
}

extension DataSourceAndActionsForPreviews: ObvGroupCellViewNavigation {
    
    func userDidPressOnObvGroupCellView(_ view: ObvGroupCellView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, expectedNavigation: ObvGroupCellView.ExpectedNavigation) throws {
        print("User did press on ObvGroupCellView")
    }

}

extension DataSourceAndActionsForPreviews: ObvGroupsListViewDataSource {
    
    func getObvGroupsListViewModel(_ view: ObvGroupsListView, searchStatus: ObvGroupsListViewModel.SearchStatus) throws -> ObvGroupsListViewModel? {
        return nil
    }
    
    
    func getAsyncStreamOfObvGroupsListViewModel(_ view: ObvGroupsListView, initialSearchStatus: ObvGroupsListViewModel.SearchStatus) throws -> (streamUUID: UUID, stream: AsyncStream<ObvGroupsListViewModel>) {
        let stream = AsyncStream<ObvGroupsListViewModel> { (continuation: AsyncStream<ObvGroupsListViewModel>.Continuation) in
            self.continuation = continuation
            Task {
                
//                do {
//                    let viewModel = ObvGroupsListViewModel(
//                        currentOwnedCryptoId: ObvCryptoId.sampleData,
//                        identifiersOfGroupsAdministrated: [], //Array(ObvGroupCellViewModel.GroupIdentifier.sampleDatas[0..<1]),
//                        identifiersOfGroupsJoined: []) // Array(ObvGroupCellViewModel.GroupIdentifier.sampleDatas[50..<100]))
//                    currentUnfilteredViewModel = viewModel
//                    continuation.yield(viewModel)
//                }
                                
                //view.scrollToItem(ObvGroupCellViewModel.GroupIdentifier.sampleDatas[70])
                
               while true {
////                    do {
////                        let viewModel = ObvGroupsListViewModel(
////                            currentOwnedCryptoId: ObvCryptoId.sampleData,
////                            identifiersOfGroupsAdministrated: [],
////                            identifiersOfGroupsJoined: [])
////                        currentUnfilteredViewModel = viewModel
////                        continuation.yield(viewModel)
////                        try? await Task.sleep(seconds: 2)
////                    }
                    do {
                        let viewModel = ObvGroupsListViewModel(
                            currentOwnedCryptoId: ObvCryptoId.sampleData,
                            identifiersOfGroupsAdministrated: [], // Array(ObvGroupCellViewModel.GroupIdentifier.sampleDatas[0..<2]),
                            identifiersOfGroupsJoined: Array(ObvGroupCellViewModel.GroupIdentifier.sampleDatas[10..<10]))
                        currentUnfilteredViewModel = viewModel
                        continuation.yield(viewModel)
                        try? await Task.sleep(seconds: 2)
                    }
//                    do {
//                        let viewModel = ObvGroupsListViewModel(
//                            currentOwnedCryptoId: ObvCryptoId.sampleData,
//                            identifiersOfGroupsAdministrated: Array(ObvGroupCellViewModel.GroupIdentifier.sampleDatas[0..<1]),
//                            identifiersOfGroupsJoined: []) // Array(ObvGroupCellViewModel.GroupIdentifier.sampleDatas[10..<11]))
//                        currentUnfilteredViewModel = viewModel
//                        continuation.yield(viewModel)
//                        try? await Task.sleep(seconds: 2)
//                    }
//                    do {
//                        let viewModel = ObvGroupsListViewModel(
//                            currentOwnedCryptoId: ObvCryptoId.sampleData,
//                            identifiersOfGroupsAdministrated: Array(ObvGroupCellViewModel.GroupIdentifier.sampleDatas[0..<2]),
//                            identifiersOfGroupsJoined: Array(ObvGroupCellViewModel.GroupIdentifier.sampleDatas[10..<12]))
//                        currentUnfilteredViewModel = viewModel
//                        continuation.yield(viewModel)
//                        try? await Task.sleep(seconds: 2)
//                    }
//                    do {
//                        let viewModel = ObvGroupsListViewModel(
//                            currentOwnedCryptoId: ObvCryptoId.sampleData,
//                            identifiersOfGroupsAdministrated: Array(ObvGroupCellViewModel.GroupIdentifier.sampleDatas[0..<2]),
//                            identifiersOfGroupsJoined: Array(ObvGroupCellViewModel.GroupIdentifier.sampleDatas[11..<12]))
//                        currentUnfilteredViewModel = viewModel
//                        continuation.yield(viewModel)
//                        try? await Task.sleep(seconds: 2)
//                    }
//                    do {
//                        let viewModel = ObvGroupsListViewModel(
//                            currentOwnedCryptoId: ObvCryptoId.sampleData,
//                            identifiersOfGroupsAdministrated: Array(ObvGroupCellViewModel.GroupIdentifier.sampleDatas[0..<2]),
//                            identifiersOfGroupsJoined: Array(ObvGroupCellViewModel.GroupIdentifier.sampleDatas[10..<12]))
//                        currentUnfilteredViewModel = viewModel
//                        continuation.yield(viewModel)
//                        try? await Task.sleep(seconds: 2)
//                    }
                }
                
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfObvGroupsListViewModel(_ view: ObvGroupsListView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
    func filterAsyncStreamOfObvGroupsListViewModel(_ view: ObvGroupsListView, streamUUID: UUID, searchStatus: ObvGroupsListViewModel.SearchStatus) {
        switch searchStatus {
        case .notPerformingSearch:
            print("Not performing search")
        case .performingSearch(let searchText):
            print("Performing search with text: \(String(describing: searchText))")
        }
        guard let currentUnfilteredViewModel, let continuation else { return }
        switch searchStatus {
        case .notPerformingSearch:
            continuation.yield(currentUnfilteredViewModel)
        case .performingSearch(let searchText):
            if let searchText, searchText.count > 3 {
                let identifiersOfGroupsAdministrated = currentUnfilteredViewModel.identifiersOfGroupsAdministrated.prefix(5)
                let identifiersOfGroupsJoined = currentUnfilteredViewModel.identifiersOfGroupsJoined.prefix(5)
                let viewModel = ObvGroupsListViewModel(
                    currentOwnedCryptoId: currentUnfilteredViewModel.currentOwnedCryptoId,
                    identifiersOfGroupsAdministrated: Array(identifiersOfGroupsAdministrated),
                    identifiersOfGroupsJoined: Array(identifiersOfGroupsJoined))
                continuation.yield(viewModel)
            } else {
                continuation.yield(currentUnfilteredViewModel)
            }
        }
    }

}

extension DataSourceAndActionsForPreviews: ObvGroupCellViewDataSource {
    
    func getAsyncStreamOfObvGroupCellViewModel(_ view: ObvGroupCellView, groupIdentifier: ObvGroupCellViewModel.GroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvGroupCellViewModel>) {
        let stream = AsyncStream<ObvGroupCellViewModel> { (continuation: AsyncStream<ObvGroupCellViewModel>.Continuation) in
            let cellViewModel = ObvGroupCellViewModel.sampleData(groupIdentifier: groupIdentifier)
            continuation.yield(cellViewModel)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfObvGroupCellViewModel(_ view: ObvGroupCellView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
}


extension DataSourceAndActionsForPreviews: ObvGroupsListViewNavigation {
    
    // Other protocol conformances are enough
    
}

extension DataSourceAndActionsForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
}


extension DataSourceAndActionsForPreviews: ObvGroupsListViewActions {
    
    func userDidSwitchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvTypes.ObvCryptoId) async {
        print("User switched to a new owned crypto ID")
    }
    
    func userWantsToCreateNewGroup(_ view: ObvGroupsListView, ownedCryptoId: ObvTypes.ObvCryptoId) {
        print("User wants to create new group")
    }
        
}


extension DataSourceAndActionsForPreviews: ObvPlusButtonActionsDelegate {
    
    func userTappedObvPlusButton() {
        print("User tapped ObvPlusButton")
    }
    
}


extension DataSourceAndActionsForPreviews: MainMenuActionsProtocol {
    
    func userWantsToNavigateToSettings(_ view: ObvGroupsListView.MainMenu) {
        print("User wants to navigate to settings")
    }
    
    func userWantsToNavigateToStorageManagement(_ view: ObvGroupsListView.MainMenu) {
        print("User wants to navigate to storage management")
    }
    
}

extension DataSourceAndActionsForPreviews: ObvProfilePictureBarButtonItemViewActionsProtocol {
    
    func userDidLongPressOnProfilePicture(_ view: ObvProfilePictureBarButtonItem.ObvProfilePictureBarButtonItemView) {
        print("User did long press on profile picture")
    }
    
    func userWantsToEditOwnedIdentity(_ view: ObvProfilePictureBarButtonItem.ObvProfilePictureBarButtonItemView, ownedCryptoId: ObvTypes.ObvCryptoId) async {
        print("User wants to edit own identity")
    }
    
    func userWantsToAddNewProfile(_ view: ObvProfilePictureBarButtonItem.ObvProfilePictureBarButtonItemView) async {
        print("User wants to add new profile")
    }
    
}

extension DataSourceAndActionsForPreviews: ObvProfilePictureBarButtonItemViewDataSource {
    
    func getAsyncStreamOfObvProfilePictureBarButtonItemViewModel(_ view: ObvProfilePictureBarButtonItemView, ownedCryptoId: ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<ObvProfilePictureBarButtonItemViewModel>) {
        let stream = AsyncStream(ObvProfilePictureBarButtonItemViewModel.self) { (continuation: AsyncStream<ObvProfilePictureBarButtonItemViewModel>.Continuation) in
            let model = ObvProfilePictureBarButtonItemViewModel.sampleDataForOwnedCryptoId(ownedCryptoId)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }

    func finishAsyncStreamOfObvProfilePictureBarButtonItemViewModel(_ view: ObvProfilePictureBarButtonItem.ObvProfilePictureBarButtonItemView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
    func getNextOwnedCryptoId(_ view: ObvProfilePictureBarButtonItem.ObvProfilePictureBarButtonItemView, currentOwnedCryptoId: ObvTypes.ObvCryptoId) async throws -> ObvTypes.ObvCryptoId {
        // We don't switch
        return currentOwnedCryptoId
    }
    
}

extension DataSourceAndActionsForPreviews: OwnedIdentityChooserViewDataSource {
    
    func getAsyncStreamOfOwnedIdentityChooserViewModel(_ view: ObvOwnedIdentityChooser.OwnedIdentityChooserView, currentOwnedCryptoId: ObvTypes.ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<ObvOwnedIdentityChooser.OwnedIdentityChooserViewModel>) {
        let stream = AsyncStream(OwnedIdentityChooserViewModel.self) { (continuation: AsyncStream<OwnedIdentityChooserViewModel>.Continuation) in
            let model = OwnedIdentityChooserViewModel.sampleData
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfOwnedIdentityChooserViewModel(_ view: ObvOwnedIdentityChooser.OwnedIdentityChooserView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
}

@MainActor
private let dataSourceAndActionsForPreviews = DataSourceAndActionsForPreviews()

#Preview {
    NavigationView {
        ObvGroupsListView(currentOwnedCryptoId: ObvCryptoId.sampleData,
                          dataSource: dataSourceAndActionsForPreviews,
                          groupCellViewDataSource: dataSourceAndActionsForPreviews,
                          profilePictureBarButtonItemViewDataSource: dataSourceAndActionsForPreviews,
                          avatarViewDataSource: dataSourceAndActionsForPreviews,
                          ownedIdentityChooserViewDataSource: dataSourceAndActionsForPreviews,
                          actions: dataSourceAndActionsForPreviews,
                          navigation: dataSourceAndActionsForPreviews,
                          itemToScrollToWrapper: .init())
    }
}

#endif

