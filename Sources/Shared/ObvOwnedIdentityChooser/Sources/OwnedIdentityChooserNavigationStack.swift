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
import CoreHaptics
import ObvTypes
import ObvDesignSystem
import ObvSystemIcon



@MainActor
public protocol OwnedIdentityChooserNavigationStackActions {
    func userChoseProfile(_ view: OwnedIdentityChooserNavigationStack, chosenOwnedCryptoId: ObvCryptoId) async throws
    func userWantsToEditCurrentOwnedIdentity(_ view: OwnedIdentityChooserNavigationStack, currentOwnedCryptoId: ObvCryptoId) async
    func userWantsToAddNewProfile(_ view: OwnedIdentityChooserNavigationStack, ) async
}


public struct OwnedIdentityChooserNavigationStack: View {
    
    let currentOwnedCryptoId: ObvCryptoId
    let actions: OwnedIdentityChooserNavigationStackActions
    let dataSource: OwnedIdentityChooserViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let configuration: OwnedIdentityChooserInnerViewConfiguration
    @Binding var toggleToDismiss: Bool
    
    public init(currentOwnedCryptoId: ObvCryptoId, actions: OwnedIdentityChooserNavigationStackActions, dataSource: OwnedIdentityChooserViewDataSource, avatarViewDataSource: ObvAvatarViewDataSource, configuration: OwnedIdentityChooserInnerViewConfiguration, toggleToDismiss: Binding<Bool>) {
        self.currentOwnedCryptoId = currentOwnedCryptoId
        self.actions = actions
        self.dataSource = dataSource
        self.avatarViewDataSource = avatarViewDataSource
        self.configuration = configuration
        self._toggleToDismiss = toggleToDismiss
    }
    
    @State var ownedCryptoIdTappedByUser: ObvCryptoId? = nil
    @State private var toggleToPerformSensoryFeedback: Bool = false

    private func ownedIdentityTapped(_ ownedCryptoId: ObvCryptoId) {
        switch configuration.mode {
        case .changeCurrentProfile:
            Task {
                if ownedCryptoId == self.currentOwnedCryptoId {
                    // The user wants to edit the current profile.
                    // We immediately inform our actions delegate.
                    try await actions.userChoseProfile(self, chosenOwnedCryptoId: ownedCryptoId)
                    toggleToPerformSensoryFeedback.toggle()
                    toggleToDismiss.toggle()
                } else {
                    // The user wants to change profile. We give some time to
                    // the checkmark animation to finish
                    try? await Task.sleep(seconds: 0.4)
                    try await actions.userChoseProfile(self, chosenOwnedCryptoId: ownedCryptoId)
                    toggleToPerformSensoryFeedback.toggle()
                    // No need to dismiss this view, this is ensured by the delegate method...
                }
            }
        case .selectProfile:
            // We wait until the user confirms her choice by tapping the confirmation button
            break
        }
    }
    
        
    /// Set when switching owned identity. We use the state to perform nice animations for the checkmark and for hiding the items corresponding to a hidden profile.
    /// This is thus only set when the user taps on an owned identity that is different from the current one.
    @State private var ownedCryptoIdSwitchedTo: ObvCryptoId?

    /// What the chooser paints behind its content: the app theme's page colour, which is the partner of the card
    /// colour ``ObvCardView`` fills each row with.
    ///
    /// **Read, never composed.** This used to branch on `@Environment(\.colorScheme)` and return
    /// `UIColor.secondarySystemBackground` in light and `.black` in dark — which are *exactly* the two values this one
    /// property resolves to, so it was a hand-copy of the theme with the usual consequence: nothing keeps a copy in
    /// step, and the copy cannot carry what it never read.
    ///
    /// What it could not carry is **elevation**. Apple's dark mode has two levels, base and elevated, and the system
    /// raises modally presented content to the elevated level so that it reads as floating; a *dynamic* colour resolves
    /// that on its own, where a branch on `colorScheme` — which reports light against dark and nothing about elevation
    /// — can only ever produce the base value. Because both this and the card's colour are dynamic, elevation lifts
    /// **both** together, black and `#1C1C1E` becoming `#1C1C1E` and `#2C2C2E`: the sheet separates from what is behind
    /// it *and* the cards stay visible against it.
    ///
    /// **Do not read these names as UIKit's — `AppThemeColorScheme` inverts them** (`AppThemeColorScheme.swift:165`).
    /// The theme's `systemBackground` is UIKit's `secondarySystemBackground` in light and UIKit's `systemBackground` in
    /// dark, and its `secondarySystemBackground` is the other way about. So the theme's *secondary* is the lighter,
    /// card-coloured one and the theme's *primary* is the page. Reaching for `UIColor.secondarySystemBackground` here
    /// on the strength of the name gives the page the card's own colour and the rows vanish in dark mode, which is
    /// precisely what it did.
    ///
    /// The background does have to be painted rather than left to the presentation: the content is a `ScrollView`
    /// rather than a `List`, and the hosting controller presents this as a bare `UIHostingController`, so nothing else
    /// would fill it. Hence the name.
    private var backgroundColorInUIKitMode: UIColor {
        AppTheme.shared.colorScheme.systemBackground
    }
    
    private var topPadding: CGFloat {
        if #available(iOS 26.0, *) {
            return 0.0
        } else if #available(iOS 18.0, *) {
            return 0.0
        } else if #available(iOS 17.0, *) {
            return 0.0
        } else {
            return 8.0
        }
    }

    @ViewBuilder
    var content: some View {
        ZStack {
            Color(backgroundColorInUIKitMode).ignoresSafeArea(.all)
            OwnedIdentityChooserInnerView(currentOwnedCryptoId: self.currentOwnedCryptoId,
                                          actions: self,
                                          configuration: configuration,
                                          dataSource: dataSource,
                                          avatarViewDataSource: avatarViewDataSource,
                                          ownedCryptoIdTappedByUser: $ownedCryptoIdTappedByUser)
        }
    }

    public var body: some View {
        Group {
            
            if #available(iOS 26, *) {
                
                NavigationStack {
                    content
                        .navigationTitle(configuration.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem {
                                Button {
                                    toggleToDismiss.toggle()
                                } label: {
                                    Image(systemIcon: .xmark)
                                }
                                .keyboardShortcut(configuration.isEmbeddedInHostingController ? .cancelAction : nil)
                            }
                            .sharedBackgroundVisibility(.automatic)
                        }
                }

            } else if #available(iOS 17, *) {
                
                NavigationStack {
                    content
                        .navigationTitle(configuration.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem {
                                Button {
                                    toggleToDismiss.toggle()
                                } label: {
                                    Text("Cancel")
                                }
                                .keyboardShortcut(configuration.isEmbeddedInHostingController ? .cancelAction : nil)
                            }
                        }
                }
                
            } else {
                
                VStack {
                    HeaderView(configuration: configuration, actions: actions, toggleToDismiss: $toggleToDismiss)
                        .padding(.horizontal)
                        .padding(.top, 4)
                    OwnedIdentityChooserInnerView(currentOwnedCryptoId: self.currentOwnedCryptoId,
                                                  actions: self,
                                                  configuration: configuration,
                                                  dataSource: dataSource,
                                                  avatarViewDataSource: avatarViewDataSource,
                                                  ownedCryptoIdTappedByUser: $ownedCryptoIdTappedByUser)
                }

            }
            
            
        }
        .padding(.top, topPadding)
        // Esc is carried by the close button only when this stack is presented from UIKit, where nothing else answers the key; a SwiftUI sheet closes on
        // Esc by itself on Catalyst, and the binding toggled by the button would present it again if both ran. Nothing in the stack is focusable, and a
        // shortcut is found from the first responder.
        .takesKeyboardFocusOnAppear()
        .sensoryFeedbackOniOS17(.success, trigger: toggleToPerformSensoryFeedback)
        .onChange(of: ownedCryptoIdTappedByUser) { newValue in
            guard let newValue else { return }
            ownedIdentityTapped(newValue)
        }
    }
    
}


extension OwnedIdentityChooserNavigationStack: OwnedIdentityChooserInnerViewActionsProtocol {
        
    func userWantsToEditCurrentOwnedIdentity(_ view: OwnedIdentityChooserInnerView, currentOwnedCryptoId: ObvTypes.ObvCryptoId) async {
        toggleToDismiss.toggle()
        await actions.userWantsToEditCurrentOwnedIdentity(self, currentOwnedCryptoId: currentOwnedCryptoId)
    }
    
    func userWantsToAddNewProfile(_ view: OwnedIdentityChooserInnerView) async {
        toggleToDismiss.toggle()
        await actions.userWantsToAddNewProfile(self)
    }

    /// Called exclusively when in `.selectProfile` mode, when the user confirms the selected profile.
    func userDidConfirmOwnedCryptoIdSelection(_ view: OwnedIdentityChooserInnerView, selectedOwnedCryptoId: ObvTypes.ObvCryptoId) {
        toggleToDismiss.toggle()
        Task {
            do {
                try await actions.userChoseProfile(self, chosenOwnedCryptoId: selectedOwnedCryptoId)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
}


// MARK: - Internal view: OwnedIdentityChooserInnerView

/// Not used in iOS17+
@available(iOS, deprecated: 17.0)
private struct HeaderView: View {
    
    let configuration: OwnedIdentityChooserInnerViewConfiguration
    let actions: OwnedIdentityChooserNavigationStackActions
    @Binding var toggleToDismiss: Bool
    
    var body: some View {
        HStack {
            Text("Cancel")
                .opacity(0)
            Spacer()
            Text(configuration.title)
                .font(.headline)
                .lineLimit(nil)
                .multilineTextAlignment(.center)
            Spacer()
            Button(action: { toggleToDismiss.toggle() }) {
                Text("Cancel")
            }
            .keyboardShortcut(configuration.isEmbeddedInHostingController ? .cancelAction : nil)
        }
    }
    
}



// MARK: - Previews

#if DEBUG

private final class ActionsForPreviews: OwnedIdentityChooserNavigationStackActions {
    
    func userChoseProfile(_ view: OwnedIdentityChooserNavigationStack, chosenOwnedCryptoId: ObvTypes.ObvCryptoId) async throws {
        
    }
    
    func userWantsToEditCurrentOwnedIdentity(_ view: OwnedIdentityChooserNavigationStack, currentOwnedCryptoId: ObvTypes.ObvCryptoId) async {
        print("Edit button tapped")
    }
    
    func userWantsToAddNewProfile(_ view: OwnedIdentityChooserNavigationStack) async {
        print("Add new profile")
    }
    
}


private final class DataSourceForPreviews: OwnedIdentityChooserViewDataSource, ObvAvatarViewDataSource {

    private let model: OwnedIdentityChooserViewModel

    init(model: OwnedIdentityChooserViewModel = .sampleData) {
        self.model = model
    }

    // ObvAvatarViewDataSource

    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }

    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }

    // OwnedIdentityChooserViewDataSource

    func getAsyncStreamOfOwnedIdentityChooserViewModel(_ view: OwnedIdentityChooserInnerView, currentOwnedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityChooserViewModel>) {
        let model = self.model
        let stream = AsyncStream(OwnedIdentityChooserViewModel.self) { (continuation: AsyncStream<OwnedIdentityChooserViewModel>.Continuation) in
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfOwnedIdentityChooserViewModel(_ view: OwnedIdentityChooserInnerView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
    
}

@MainActor
private let actionsForPreviews = ActionsForPreviews()

@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

/// Yields profiles spread over two different servers, to preview the server-restricted `.selectProfile` mode.
@MainActor
private let dataSourceForPreviewsTwoServers = DataSourceForPreviews(model: .sampleDataWithProfilesOnTwoServers)

#Preview("Change current profile") {
    OwnedIdentityChooserNavigationStack(currentOwnedCryptoId: ObvCryptoId.sampleDatas[0],
                             actions: actionsForPreviews,
                             dataSource: dataSourceForPreviews,
                             avatarViewDataSource: dataSourceForPreviews,
                             configuration: .init(mode: .changeCurrentProfile, explanation: nil, title: "Title"),
                             toggleToDismiss: .constant(false))
}

#Preview("Sheet") {
    Text(verbatim: "Test")
        .sheet(isPresented: .constant(true)) {
            OwnedIdentityChooserNavigationStack(currentOwnedCryptoId: ObvCryptoId.sampleDatas[0],
                                     actions: actionsForPreviews,
                                     dataSource: dataSourceForPreviews,
                                     avatarViewDataSource: dataSourceForPreviews,
                                     configuration: .init(mode: .changeCurrentProfile, explanation: nil, title: "Title"),
                                     toggleToDismiss: .constant(false))
            .presentationDetents([.medium, .large])
            .interactiveDismissDisabled()
        }
}


#Preview("Select profile") {
    OwnedIdentityChooserNavigationStack(currentOwnedCryptoId: ObvCryptoId.sampleDatas[0],
                             actions: actionsForPreviews,
                             dataSource: dataSourceForPreviews,
                             avatarViewDataSource: dataSourceForPreviews,
                             configuration: .init(mode: .selectProfile(serverRestriction: nil),
                                                  explanation: "Please select the profile you want to bind to the identity provider.",
                                                  title: "Title"),
                             toggleToDismiss: .constant(false))
}


#Preview("Select profile (server-restricted)") {
    OwnedIdentityChooserNavigationStack(currentOwnedCryptoId: ObvCryptoId.sampleDatas[0],
                             actions: actionsForPreviews,
                             dataSource: dataSourceForPreviewsTwoServers,
                             avatarViewDataSource: dataSourceForPreviewsTwoServers,
                             configuration: .init(mode: .selectProfile(serverRestriction: .init(serverURL: ObvCryptoId.sampleDatas[0].serverURL)),
                                                  explanation: "Choose the profile to which this license should be applied.",
                                                  title: "Title"),
                             toggleToDismiss: .constant(false))
}

#endif
