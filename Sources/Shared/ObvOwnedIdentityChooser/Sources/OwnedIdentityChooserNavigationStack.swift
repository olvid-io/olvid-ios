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

    @Environment(\.colorScheme) var colorScheme: ColorScheme

    private var backgroundColorInUIKitMode: UIColor {
        if colorScheme == .light {
            return .secondarySystemBackground
        } else {
            return .black
        }
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
    
    // ObvAvatarViewDataSource
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
    // OwnedIdentityChooserViewDataSource
    
    func getAsyncStreamOfOwnedIdentityChooserViewModel(_ view: OwnedIdentityChooserInnerView, currentOwnedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityChooserViewModel>) {
        let stream = AsyncStream(OwnedIdentityChooserViewModel.self) { (continuation: AsyncStream<OwnedIdentityChooserViewModel>.Continuation) in
            let model = OwnedIdentityChooserViewModel.sampleData
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
                             configuration: .init(mode: .selectProfile,
                                                  explanation: "Please select the profile you want to bind to the identity provider.",
                                                  title: "Title"),
                             toggleToDismiss: .constant(false))
}

#endif
