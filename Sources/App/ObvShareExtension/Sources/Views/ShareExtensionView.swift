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
import ObvDesignSystem
import ObvOwnedIdentityChooser
import ObvDiscussionChooser
import ObvTypes
import ObvAppTypes

public struct ShareExtensionView: View {
    
    public struct DataSources {
        public let dataSource: any ShareExtensionViewDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        
        public init(dataSource: any ShareExtensionViewDataSource,
                    avatarViewDataSource: any ObvAvatarViewDataSource) {
            self.dataSource = dataSource
            self.avatarViewDataSource = avatarViewDataSource
        }
    }
    
    @ObservedObject var sharedState: SharedState
    
    let dataSources: DataSources
    let actions: any ShareExtensionViewActions

    /// "First paint" seed computed by the caller and injected, so this view's init stays cheap and free of
    /// Core Data I/O. Never mutated after init — the async stream drives updates via `streamedModel`.
    let initialModel: Model
    @State private var streamedModel: Model?
    @State private var streamUUIDForViewModel: UUID?
    
    @State private var showOwnedIdentityChooserView = false
    @State private var showDiscussionChooserView = false

    /// Ties each chooser sheet to the row that presents it, so on iOS 18+ it appears to grow out of that
    /// row rather than fading in from nowhere.
    @Namespace private var chooserNamespace
    
    private var model: Model { streamedModel ?? initialModel }
    
    // IdentityChooserChooserViewConfiguration
    private let ownedIdentityChooserViewConfiguration = OwnedIdentityChooserInnerViewConfiguration(mode: .selectProfile(serverRestriction: nil),
                                                                                                   explanation: nil,
                                                                                                   title: String(localizedInThisBundle: "MY_OWN_IDS"))
    
    public init(sharedState: SharedState,
                dataSources: DataSources,
                actions: any ShareExtensionViewActions,
                initialModel: Model) {
        self.sharedState = sharedState
        self.dataSources = dataSources
        self.actions = actions
        self.initialModel = initialModel
    }
    
    private func onTask() async {
        // Three probes, because this task runs inside the 173ms window that spends 22.9 MB with nothing of ours
        // reporting, and it is the only work of ours scheduled in it: a stream over the owned identities and every
        // active discussion. Bracketing it either accounts for the memory or rules this out and leaves the framework.
        PreviewMemory.mark("view.taskBegan")
        do {
            let (newStreamUUID, stream) = try await dataSources.dataSource.getAsyncSequenceOfShareExtensionViewModel(self, currentOwnedCryptoId: sharedState.selectedOwnedCryptoId)
            PreviewMemory.mark("view.streamOpened")
            if let previousStreamUUID = self.streamUUIDForViewModel {
                dataSources.dataSource.finishAsyncSequenceOfShareExtensionViewModel(self, streamUUID: previousStreamUUID)
            }
            self.streamUUIDForViewModel = newStreamUUID
            var theFirstModelHasArrived = false
            for await receivedModel in stream {
                if !theFirstModelHasArrived {
                    theFirstModelHasArrived = true
                    PreviewMemory.mark("view.firstModel")
                }
                if sharedState.selectedOwnedCryptoId != receivedModel.selectedOwnedIdentity?.ownedCryptoId {
                    sharedState.selectedOwnedCryptoId = receivedModel.selectedOwnedIdentity?.ownedCryptoId
                }
                withAnimation { self.streamedModel = receivedModel }
            }
        } catch {
            assertionFailure()
        }
        if let previousStreamUUID = self.streamUUIDForViewModel {
            dataSources.dataSource.finishAsyncSequenceOfShareExtensionViewModel(self, streamUUID: previousStreamUUID)
        }
        self.streamUUIDForViewModel = nil
    }
    
    private var closeButton: some View {
        Button(action: {
            actions.userWantsToCloseShare(from: self)
        }) {
            Image(systemIcon: .xmark)
                .imageScale(.large)
                .frame(width: 42, height: 42)
        }
        .glassButtonStyle()
    }
    
    public var body: some View {
        ZStack(alignment: .center) {
            
            // Show empty state if not loading and no shareable items
            if !sharedState.isLoading && sharedState.shareableItems.isEmpty {
                EmptyStateView()
            } else {
                VStack(spacing: 0) {
                    
                    Spacer()
                    
                    HorizontalShareableItemsView(sharedState: sharedState)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .animation(.easeInOut(duration: 0.2), value: sharedState.shareableItems.count)
                    
                    Spacer()
                    
                    if sharedState.shareableItems.count > 1 {
                        // The per-attachment thumbnail strip (switch/delete individual items) is intentionally
                        // gated to iOS 17+: HorizontalThumbnailsView relies on genuinely iOS 17-only APIs
                        // (containerRelativeFrame, contentMargins(for: .scrollContent), scrollPosition(id:)).
                        // On iOS 16, multiple shared items are still sent, but cannot be switched/removed
                        // individually. This is an accepted limitation, not an oversight — no iOS 16 fallback
                        // is provided on purpose. Revisit if iOS 16 usage warrants a ScrollViewReader-based port.
                        if #available(iOS 17.0, *) {
                            HorizontalThumbnailsView(sharedState: sharedState)
                                .frame(height: 60)
                        }
                    }
                }
            }
            
            VStack {
                HStack(alignment: .top) {
                    closeButton
                    
                    if sharedState.atLeastOneShareableItemIsAPhotoOrVideo {
                        MediaQualityPicker(sharedState: sharedState, actions: actions)
                            .glassButtonStyle()
                    }
                    
                    VStack(alignment: .trailing, spacing: 0.0) {
                        ProfileAndRecipientsView(model: model,
                                                 avatarDataSource: dataSources.avatarViewDataSource,
                                                 singleRecipientSummaryViewDataSource: dataSources.dataSource,
                                                 sharedState: sharedState,
                                                 showOwnedIdentityChooserView: $showOwnedIdentityChooserView,
                                                 showDiscussionChooserView: $showDiscussionChooserView,
                                                 chooserNamespace: chooserNamespace)
                        // Presented as sheets rather than popovers. A popover is anchored to its source and
                        // sized to fit around it, which inside the share extension's small container left
                        // the chooser too cramped to use on iPad — the discussion list had almost no room.
                        // This changes nothing on iPhone, where a popover already adapts to a sheet, nor on
                        // Catalyst, which was explicitly using a sheet; and it lets the presentation detents
                        // below actually take effect, which a popover ignored.
                        .sheet(isPresented: $showOwnedIdentityChooserView) {
                            if let currentOwnedCryptoId = model.selectedOwnedIdentity?.ownedCryptoId {
                                OwnedIdentityChooserNavigationStack(currentOwnedCryptoId: currentOwnedCryptoId,
                                                                    actions: actions,
                                                                    dataSource: dataSources.dataSource,
                                                                    avatarViewDataSource: dataSources.avatarViewDataSource,
                                                                    configuration: ownedIdentityChooserViewConfiguration,
                                                                    toggleToDismiss: $showOwnedIdentityChooserView)
                                .presentationDetents([.medium, .large])
                                .navigationZoomTransitionOnIOS18(id: ProfileAndRecipientsView.ChooserTransitionSource.card, in: chooserNamespace)
                            }
                        }
                        .sheet(isPresented: $showDiscussionChooserView) {
                            if let currentOwnedCryptoId = model.selectedOwnedIdentity?.ownedCryptoId {
                                let discussionDataSources = DiscussionChooserView.DataSources(discussionChooserViewDataSource: dataSources.dataSource,
                                                                                              discussionItemViewDataSource: dataSources.dataSource,
                                                                                              avatarViewDataSource: dataSources.avatarViewDataSource)

                                DiscussionChooserNavigationStack(currentOwnedCryptoId: currentOwnedCryptoId,
                                                                 initialSelectedDiscussionIdentifiers: sharedState.selectedDiscussionIdentifiers,
                                                                 dataSources: discussionDataSources,
                                                                 actions: actions,
                                                                 toggleToDismiss: $showDiscussionChooserView)
                                .presentationDetents([.large])
                                // Swipe-to-dismiss competes with the list: scrolling upward hands the
                                // gesture to the sheet once the list reaches its top, so the chooser is
                                // easily dismissed by accident mid-scroll — losing the current selection.
                                // Dismissal stays available through the explicit close and confirm buttons
                                // in the header, which is why removing the gesture costs nothing here.
                                .interactiveDismissDisabled()
                                .navigationZoomTransitionOnIOS18(id: ProfileAndRecipientsView.ChooserTransitionSource.card, in: chooserNamespace)
                            }
                        }

                    }
                    // Fill the width left of the close/media buttons and keep the card trailing-aligned,
                    // so a long profile name truncates within this space instead of pushing the buttons off.
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .glassEffectContainer(spacing: 0.0)
                Spacer()
            }
            .padding(16)
        }
        .onAppear { PreviewMemory.mark("view.onAppear") }
        .task(id: sharedState.selectedOwnedCryptoId, onTask)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .safeAreaInset(edge: .bottom) {
            // ShareComposeView pinned at the bottom, above keyboard
            ShareComposeView(sharedState: sharedState,
                             actions: actions)
                .padding(.horizontal)
                .padding(.bottom)
        }
    }
    
    /// Empty state view shown when there are no shareable items
    private struct EmptyStateView: View {
        var body: some View {
            VStack(spacing: 16) {
                Image(systemIcon: .docOnDoc)
                    .font(.system(size: 48))
                    .foregroundStyle(.primary)
                
                Text("NO_ATTACHMENTS")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(60.0)
        }
    }
    
}

// MARK: - Previews

#if DEBUG

@MainActor
private func makeSharedStateForPreviews() -> SharedState {
    let sharedState = SharedState(initialMediaQuality: .standard)
    
    let linkMetadata = [ObvLinkMetadata].sampleData[safe: 0]!
    sharedState.addLinkMetadata(linkMetadata: linkMetadata, for: linkMetadata.url!)
    
    sharedState.setHardlinks([SharedState.HardLink].sampleData)
    
    return sharedState
}

@MainActor
private let sharedStateForPreviews = makeSharedStateForPreviews()

@MainActor
private let dataSourceAndActionsForPreviews = ShareExtensionDataSourceAndActionsForPreviews(sharedState: sharedStateForPreviews)

@MainActor
private let dataSources = ShareExtensionView.DataSources(dataSource: dataSourceAndActionsForPreviews,
                                                         avatarViewDataSource: dataSourceAndActionsForPreviews)

#Preview {
    ShareExtensionView(sharedState: sharedStateForPreviews,
                       dataSources: dataSources,
                       actions: dataSourceAndActionsForPreviews,
                       initialModel: dataSourceAndActionsForPreviews.getInitialShareExtensionViewModel(currentOwnedCryptoId: sharedStateForPreviews.selectedOwnedCryptoId))
}

#endif
