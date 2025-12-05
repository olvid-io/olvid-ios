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
import CoreHaptics
import ObvTypes
import ObvDesignSystem
import ObvSystemIcon


public struct OwnedIdentityChooserViewModel: Sendable, Equatable {

    let ownedIdentities: [OwnedIdentity]

    public init(ownedIdentities: [OwnedIdentity]) {
        self.ownedIdentities = ownedIdentities
    }
    
    public struct OwnedIdentity: Sendable, Identifiable, Equatable {
        let ownedCryptoId: ObvCryptoId
        let avatarViewModel: ObvAvatarViewModel
        let title: String
        let subtitle: String
        let totalBadgeCount: Int
        let showGreenShield: Bool
        let showRedShield: Bool
        let showHiddenProfileIcon: Bool
        public var id: Data { ownedCryptoId.getIdentity() }
        
        public init(ownedCryptoId: ObvCryptoId, avatarViewModel: ObvAvatarViewModel, title: String, subtitle: String, totalBadgeCount: Int, showGreenShield: Bool, showRedShield: Bool, showHiddenProfileIcon: Bool) {
            self.ownedCryptoId = ownedCryptoId
            self.avatarViewModel = avatarViewModel
            self.title = title
            self.subtitle = subtitle
            self.totalBadgeCount = totalBadgeCount
            self.showGreenShield = showGreenShield
            self.showRedShield = showRedShield
            self.showHiddenProfileIcon = showHiddenProfileIcon
        }
        
    }
    
}


@MainActor
public protocol OwnedIdentityChooserViewActionsProtocol {
    func userChoseProfile(_ view: OwnedIdentityChooserView, chosenOwnedCryptoId: ObvCryptoId) async throws
    func userWantsToEditCurrentOwnedIdentity(_ view: OwnedIdentityChooserView, currentOwnedCryptoId: ObvCryptoId) async
    func userWantsToAddNewProfile(_ view: OwnedIdentityChooserView, ) async
}


@MainActor
public protocol OwnedIdentityChooserViewDataSource: Sendable {
    func getAsyncStreamOfOwnedIdentityChooserViewModel(_ view: OwnedIdentityChooserView, currentOwnedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityChooserViewModel>)
    func finishAsyncStreamOfOwnedIdentityChooserViewModel(_ view: OwnedIdentityChooserView, streamUUID: UUID)
}


public struct OwnedIdentityChooserViewConfiguration {
    let mode: Mode
    let explanation: String?
    let title: String
    let isEmbeddedInHostingController: Bool // Required to tweak colors

    /// `OwnedIdentityChooserView` supports two distinct modes:
    ///
    /// - `changeCurrentProfile`:
    ///   Used when the user wants to switch their active profile.
    ///   Typically triggered by tapping the profile picture in the top-left corner of the screen.
    ///
    /// - `selectProfile`:
    ///   Used when an action requires selecting a specific profile from all available profiles.
    ///   Commonly occurs when interacting with `OlvidURL` links that need a target profile,
    ///   such as scanning a Keycloak configuration to bind an existing profile,
    ///   or applying a license to enable calls and multi-device support for a specific profile.
    public enum Mode {
        case changeCurrentProfile
        case selectProfile
    }

    public init(mode: Mode, explanation: String?, title: String, isEmbeddedInHostingController: Bool = false) {
        self.mode = mode
        self.explanation = explanation
        self.title = title
        self.isEmbeddedInHostingController = isEmbeddedInHostingController
    }
    
}


public struct OwnedIdentityChooserView: View {
    
    let currentOwnedCryptoId: ObvCryptoId
    let actions: OwnedIdentityChooserViewActionsProtocol
    let dataSource: OwnedIdentityChooserViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let configuration: OwnedIdentityChooserViewConfiguration
    @Binding var toggleToDismiss: Bool
    
    public init(currentOwnedCryptoId: ObvCryptoId, actions: OwnedIdentityChooserViewActionsProtocol, dataSource: OwnedIdentityChooserViewDataSource, avatarViewDataSource: ObvAvatarViewDataSource, configuration: OwnedIdentityChooserViewConfiguration, toggleToDismiss: Binding<Bool>) {
        self.currentOwnedCryptoId = currentOwnedCryptoId
        self.actions = actions
        self.dataSource = dataSource
        self.avatarViewDataSource = avatarViewDataSource
        self.configuration = configuration
        self._toggleToDismiss = toggleToDismiss
    }
    
    @State private var viewModel: OwnedIdentityChooserViewModel?
    @State private var streamUUIDForViewModel: UUID?
    
    @State var ownedCryptoIdTappedByUser: ObvCryptoId? = nil
    @State private var toggleToPerformSensoryFeedback: Bool = false

    private func onAppear() {
        Task {
            do {
                let (newStreamUUID, stream) = try await dataSource.getAsyncStreamOfOwnedIdentityChooserViewModel(self, currentOwnedCryptoId: currentOwnedCryptoId)
                if let previousStreamUUID = self.streamUUIDForViewModel {
                    dataSource.finishAsyncStreamOfOwnedIdentityChooserViewModel(self, streamUUID: previousStreamUUID)
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
    
    private func onDisappear() {
        if let streamUUIDForViewModel {
            dataSource.finishAsyncStreamOfOwnedIdentityChooserViewModel(self, streamUUID: streamUUIDForViewModel)
            self.streamUUIDForViewModel = nil
        }
    }
    
    
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
            //if configuration.isEmbeddedInHostingController {
                Color(backgroundColorInUIKitMode).ignoresSafeArea(.all)
            //}
            if let viewModel {
                OwnedIdentityChooserInnerView(currentOwnedCryptoId: self.currentOwnedCryptoId,
                                              viewModel: viewModel,
                                              actions: self,
                                              configuration: configuration,
                                              dataSource: dataSource,
                                              avatarViewDataSource: avatarViewDataSource,
                                              ownedCryptoIdTappedByUser: $ownedCryptoIdTappedByUser,
                                              toggleToDismiss: $toggleToDismiss)
            } else {
                ObvCenteredProgressView()
            }
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
                
                if let viewModel {
                    VStack {
                        HeaderView(configuration: configuration, actions: actions, toggleToDismiss: $toggleToDismiss)
                            .padding(.horizontal)
                            .padding(.top, 4)
                        OwnedIdentityChooserInnerView(currentOwnedCryptoId: self.currentOwnedCryptoId,
                                                      viewModel: viewModel,
                                                      actions: self,
                                                      configuration: configuration,
                                                      dataSource: dataSource,
                                                      avatarViewDataSource: avatarViewDataSource,
                                                      ownedCryptoIdTappedByUser: $ownedCryptoIdTappedByUser,
                                                      toggleToDismiss: $toggleToDismiss)
                    }
                } else {
                    ObvCenteredProgressView()
                }

            }
            
            
        }
        .padding(.top, topPadding)
        .sensoryFeedbackOniOS17(.success, trigger: toggleToPerformSensoryFeedback)
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
        .onChange(of: ownedCryptoIdTappedByUser) { newValue in
            guard let newValue else { return }
            ownedIdentityTapped(newValue)
        }
    }
    
}


extension OwnedIdentityChooserView: OwnedIdentityChooserInnerViewActionsProtocol {
        
    fileprivate func userWantsToEditCurrentOwnedIdentity(_ view: OwnedIdentityChooserInnerView, currentOwnedCryptoId: ObvTypes.ObvCryptoId) async {
        await actions.userWantsToEditCurrentOwnedIdentity(self, currentOwnedCryptoId: currentOwnedCryptoId)
    }
    
    fileprivate func userWantsToAddNewProfile(_ view: OwnedIdentityChooserInnerView) async {
        await actions.userWantsToAddNewProfile(self)
    }

    /// Called exclusively when in `.selectProfile` mode, when the user confirms the selected profile.
    fileprivate func userDidConfirmOwnedCryptoIdSelection(_ view: OwnedIdentityChooserInnerView, selectedOwnedCryptoId: ObvTypes.ObvCryptoId) {
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
    
    let configuration: OwnedIdentityChooserViewConfiguration
    let actions: OwnedIdentityChooserViewActionsProtocol
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


@MainActor
fileprivate protocol OwnedIdentityChooserInnerViewActionsProtocol {
    func userWantsToEditCurrentOwnedIdentity(_ view: OwnedIdentityChooserInnerView, currentOwnedCryptoId: ObvCryptoId) async
    func userWantsToAddNewProfile(_ view: OwnedIdentityChooserInnerView) async
    func userDidConfirmOwnedCryptoIdSelection(_ view: OwnedIdentityChooserInnerView, selectedOwnedCryptoId: ObvCryptoId)
}


/// View allowing SwiftUI previews for the `OwnedIdentityChooserView`.
fileprivate struct OwnedIdentityChooserInnerView: View {
    
    let currentOwnedCryptoId: ObvCryptoId
    let viewModel: OwnedIdentityChooserViewModel
    let actions: OwnedIdentityChooserInnerViewActionsProtocol
    let configuration: OwnedIdentityChooserViewConfiguration
    let dataSource: OwnedIdentityChooserViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    
    @Binding var ownedCryptoIdTappedByUser: ObvCryptoId?
    @Binding var toggleToDismiss: Bool
    
    @State private var continueWithThisProfileButtonWasTapped: Bool = false

    private func editCurrentIdentityButtonTapped() {
        toggleToDismiss.toggle()
        Task { await actions.userWantsToEditCurrentOwnedIdentity(self, currentOwnedCryptoId: self.currentOwnedCryptoId) }
    }
    
    private func addProfileButtonTapped() {
        toggleToDismiss.toggle()
        Task { await actions.userWantsToAddNewProfile(self) }
    }
    
    private func userTappedContinueWithThisProfileButton() {
        guard let ownedCryptoIdTappedByUser else { assertionFailure("The button should be inactive"); return }
        withAnimation { continueWithThisProfileButtonWasTapped = true }
        actions.userDidConfirmOwnedCryptoIdSelection(self, selectedOwnedCryptoId: ownedCryptoIdTappedByUser)
    }
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing: 6) {
                    if let explanationString = configuration.explanation {
                        HStack {
                            Text(explanationString)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    ForEach(viewModel.ownedIdentities) { ownedIdentity in
                        OwnedIdentityItemView(currentOwnedCryptoId: currentOwnedCryptoId,
                                              viewModel: ownedIdentity,
                                              dataSource: dataSource,
                                              avatarViewDataSource: avatarViewDataSource,
                                              configuration: configuration,
                                              ownedCryptoIdTappedByUser: $ownedCryptoIdTappedByUser)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 20.0)
                                .foregroundStyle(.background)
                        }
                    }
                }
            }
            Spacer()
            
            // Buttons at the bottom
            
            switch configuration.mode {

            case .changeCurrentProfile:
                
                VStack {
                    OlvidButtonNew(action: editCurrentIdentityButtonTapped, style: .glassOrBordered) {
                        Label { Text("EDIT_CURRENT_IDENTITY") } icon: { Image(systemIcon: .pencil(.circle)) }
                    }
                    OlvidButtonNew(action: addProfileButtonTapped) {
                        Label { Text("ADD_OWNED_IDENTITY") } icon: { Image(systemIcon: .personCropCircleBadgePlus) }
                    }                    
                }
                
            case .selectProfile:
                
                ContinueWithThisProfileButton(action: userTappedContinueWithThisProfileButton)
                    .disabled(ownedCryptoIdTappedByUser == nil || continueWithThisProfileButtonWasTapped)

            } // switch configuration.mode
            
        }
        .padding()
        .navigationBarTitle(String(localizedInThisBundle: "MY_OWN_IDS"), displayMode: .inline)
    }
}


// MARK: - Internal view: ContinueWithThisProfileButton

private struct ContinueWithThisProfileButton: View {
    
    let action: () -> Void
    
    var body: some View {
        if #available(iOS 26, *) {
            Button(action: action) {
                Text("CONTINUE_WITH_THIS_PROFILE")
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .buttonSizing(.flexible)
        } else {
            Button(action: action) {
                HStack {
                    Spacer(minLength: 0)
                    Text("CONTINUE_WITH_THIS_PROFILE")
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
}


/// View showing details about one owned identity.
///
/// We use a internal model to make it possible to have SwiftUI previews
private struct OwnedIdentityItemView: View {
    
    let currentOwnedCryptoId: ObvCryptoId
    let viewModel: OwnedIdentityChooserViewModel.OwnedIdentity
    let dataSource: OwnedIdentityChooserViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let configuration: OwnedIdentityChooserViewConfiguration
    @Binding var ownedCryptoIdTappedByUser: ObvCryptoId?

    private static let kCircleToTextAreaPadding = CGFloat(8.0)
    private static let animationDurationWhenSwitchingIdentity: Double = 0.3 // In secconds
    
    private var showCheckmark: Bool {
        if let ownedCryptoIdTappedByUser {
            return viewModel.ownedCryptoId == ownedCryptoIdTappedByUser
        } else {
            return viewModel.ownedCryptoId == self.currentOwnedCryptoId
        }
    }
    
    
    private func onTap() {
        switch configuration.mode {
        case .changeCurrentProfile:
            guard ownedCryptoIdTappedByUser == nil else { return } // Prevents double tapping
        case .selectProfile:
            break // Let the user change the selected profile
        }
        withAnimation {
            ownedCryptoIdTappedByUser = viewModel.ownedCryptoId
        }
    }
    
    var body: some View {
        Group {
            HStack(alignment: .center, spacing: Self.kCircleToTextAreaPadding) {
                ObvAvatarView(model: viewModel.avatarViewModel, style: .circle, size: .normal, dataSource: avatarViewDataSource)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(viewModel.title)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .font(.system(.headline, design: .rounded))
                        if viewModel.showGreenShield {
                            Image(systemIcon: .checkmarkShieldFill)
                                .foregroundColor(.green)
                        }
                        if viewModel.showRedShield {
                            Image(systemIcon: .exclamationmarkShieldFill)
                                .foregroundColor(.red)
                        }
                    }
                    if !viewModel.subtitle.isEmpty {
                        Text(viewModel.subtitle)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .font(.subheadline)
                    }
                }
                Spacer()
                if viewModel.showHiddenProfileIcon {
                    Image(systemIcon: .eyeSlash)
                        .imageScale(.small)
                        .foregroundColor(.secondary)
                }
                switch configuration.mode {
                case .changeCurrentProfile:
                    if showCheckmark {
                        Image(systemIcon: .checkmarkCircleFill)
                            .imageScale(.large)
                            .foregroundColor(.blue)
                    } else if viewModel.totalBadgeCount > 0 {
                        ObvBadgeNumberOfNewMessages(numberOfNewReceivedMessages: viewModel.totalBadgeCount)
                    }
                case .selectProfile:
                    ObvRadioButtonView(value: self.viewModel.ownedCryptoId, selectedValue: $ownedCryptoIdTappedByUser)
                }
            }
            .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
        }
        .onTapGesture(perform: onTap) // We used to have a button, but it suffered interferences with the drag gesture
    }
    
}



// MARK: - Previews

#if DEBUG

private final class ActionsForPreviews: OwnedIdentityChooserViewActionsProtocol {
    
    func userChoseProfile(_ view: OwnedIdentityChooserView, chosenOwnedCryptoId: ObvTypes.ObvCryptoId) async throws {
        
    }
    
    func userWantsToEditCurrentOwnedIdentity(_ view: OwnedIdentityChooserView, currentOwnedCryptoId: ObvTypes.ObvCryptoId) async {
        print("Edit button tapped")
    }
    
    func userWantsToAddNewProfile(_ view: OwnedIdentityChooserView) async {
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
    
    func getAsyncStreamOfOwnedIdentityChooserViewModel(_ view: OwnedIdentityChooserView, currentOwnedCryptoId: ObvTypes.ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityChooserViewModel>) {
        let stream = AsyncStream(OwnedIdentityChooserViewModel.self) { (continuation: AsyncStream<OwnedIdentityChooserViewModel>.Continuation) in
            let model = OwnedIdentityChooserViewModel.sampleData
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfOwnedIdentityChooserViewModel(_ view: OwnedIdentityChooserView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
    
}

@MainActor
private let actionsForPreviews = ActionsForPreviews()

@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

#Preview("Change current profile") {
    OwnedIdentityChooserView(currentOwnedCryptoId: ObvCryptoId.sampleDatas[0],
                             actions: actionsForPreviews,
                             dataSource: dataSourceForPreviews,
                             avatarViewDataSource: dataSourceForPreviews,
                             configuration: .init(mode: .changeCurrentProfile, explanation: nil, title: "Title"),
                             toggleToDismiss: .constant(false))
}

#Preview("Sheet") {
    Text(verbatim: "Test")
        .sheet(isPresented: .constant(true)) {
            OwnedIdentityChooserView(currentOwnedCryptoId: ObvCryptoId.sampleDatas[0],
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
    OwnedIdentityChooserView(currentOwnedCryptoId: ObvCryptoId.sampleDatas[0],
                             actions: actionsForPreviews,
                             dataSource: dataSourceForPreviews,
                             avatarViewDataSource: dataSourceForPreviews,
                             configuration: .init(mode: .selectProfile,
                                                  explanation: "Please select the profile you want to bind to the identity provider.",
                                                  title: "Title"),
                             toggleToDismiss: .constant(false))
}

#endif
