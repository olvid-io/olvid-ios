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
import ObvTypes
import ObvDesignSystem


@MainActor
protocol OwnedIdentityChooserInnerViewActionsProtocol {
    func userWantsToEditCurrentOwnedIdentity(_ view: OwnedIdentityChooserInnerView, currentOwnedCryptoId: ObvCryptoId) async
    func userWantsToAddNewProfile(_ view: OwnedIdentityChooserInnerView) async
    func userDidConfirmOwnedCryptoIdSelection(_ view: OwnedIdentityChooserInnerView, selectedOwnedCryptoId: ObvCryptoId)
}


@MainActor
public protocol OwnedIdentityChooserViewDataSource: Sendable {
    func getAsyncStreamOfOwnedIdentityChooserViewModel(_ view: OwnedIdentityChooserInnerView, currentOwnedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityChooserViewModel>)
    func finishAsyncStreamOfOwnedIdentityChooserViewModel(_ view: OwnedIdentityChooserInnerView, streamUUID: UUID)
}


public struct OwnedIdentityChooserInnerViewConfiguration {
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
    ///   The optional `serverRestriction` is only meaningful in this mode (see `ServerRestriction`).
    public enum Mode {
        case changeCurrentProfile
        case selectProfile(serverRestriction: ServerRestriction?)
    }

    /// Set when the action that requires choosing a profile is tied to a specific server, e.g. applying a license (`ServerAndAPIKey`)
    /// which only grants capabilities on the server that issued it.
    ///
    /// When set, the profiles are split in two groups: those on `serverURL` (selectable, shown first, followed by a row offering to
    /// create a new profile on `serverURL`) and those on a different server (shown below, greyed out, non-selectable, with an
    /// explanation displayed when tapped).
    public struct ServerRestriction {
        public let serverURL: URL

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }
    }

    public init(mode: Mode, explanation: String?, title: String, isEmbeddedInHostingController: Bool = false) {
        self.mode = mode
        self.explanation = explanation
        self.title = title
        self.isEmbeddedInHostingController = isEmbeddedInHostingController
    }

}


/// View allowing SwiftUI previews for the `OwnedIdentityChooserView`.
public struct OwnedIdentityChooserInnerView: View {
    
    let currentOwnedCryptoId: ObvCryptoId
    let actions: OwnedIdentityChooserInnerViewActionsProtocol
    let configuration: OwnedIdentityChooserInnerViewConfiguration
    let dataSource: OwnedIdentityChooserViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    
    @Binding var ownedCryptoIdTappedByUser: ObvCryptoId?

    @State private var continueWithThisProfileButtonWasTapped: Bool = false

    /// Set to `true` to explain why a profile on a different server cannot be selected (see `ServerRestriction`).
    @State private var showIncompatibleProfileExplanation: Bool = false

    /// The server restriction associated with the `.selectProfile` mode, if any.
    private var serverRestriction: OwnedIdentityChooserInnerViewConfiguration.ServerRestriction? {
        if case .selectProfile(let serverRestriction) = configuration.mode { return serverRestriction }
        return nil
    }

    private var isInSelectProfileMode: Bool {
        if case .selectProfile = configuration.mode { return true }
        return false
    }

    private func editCurrentIdentityButtonTapped() {
        Task { await actions.userWantsToEditCurrentOwnedIdentity(self, currentOwnedCryptoId: self.currentOwnedCryptoId) }
    }
    
    private func addProfileButtonTapped() {
        Task { await actions.userWantsToAddNewProfile(self) }
    }
    
    private func userTappedContinueWithThisProfileButton() {
        guard let ownedCryptoIdTappedByUser else { assertionFailure("The button should be inactive"); return }
        withAnimation { continueWithThisProfileButtonWasTapped = true }
        actions.userDidConfirmOwnedCryptoIdSelection(self, selectedOwnedCryptoId: ownedCryptoIdTappedByUser)
    }
    
    @State private var viewModel: OwnedIdentityChooserViewModel?

    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfOwnedIdentityChooserViewModel(self, currentOwnedCryptoId: currentOwnedCryptoId)
            for await receivedModel in stream {
                if self.viewModel == nil {
                    self.viewModel = receivedModel
                } else {
                    withAnimation { self.viewModel = receivedModel }
                }
            }
            dataSource.finishAsyncStreamOfOwnedIdentityChooserViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
    public var body: some View {
        Group {
            if let viewModel {
                VStack {
                    ScrollView {
                        VStack(spacing: 6) {
                            if let explanationString = configuration.explanation {
                                HStack {
                                    Text(explanationString)
                                        .font(.headline)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal)
                                .padding(.bottom)
                            }
                            if let serverRestriction {
                                // Profiles on the restriction's server are selectable and shown first, followed by a row offering to
                                // create a new profile on that server. Profiles on a different server are shown below in a separate,
                                // non-selectable group with an explanatory header.
                                let compatibleOwnedIdentities = viewModel.ownedIdentities.filter { $0.ownedCryptoId.belongsTo(serverURL: serverRestriction.serverURL) }
                                let incompatibleOwnedIdentities = viewModel.ownedIdentities.filter { !$0.ownedCryptoId.belongsTo(serverURL: serverRestriction.serverURL) }
                                Group {
                                    ForEach(compatibleOwnedIdentities) { ownedIdentity in
                                        profileCard(for: ownedIdentity, isCompatible: true)
                                    }
                                    CreateNewProfileCard(action: addProfileButtonTapped)
                                }
                                .disabled(continueWithThisProfileButtonWasTapped)
                                if !incompatibleOwnedIdentities.isEmpty {
                                    HStack {
                                        Text("PROFILES_ON_A_DIFFERENT_SERVER_CANNOT_BE_USED")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal)
                                    .padding(.top)
                                    ForEach(incompatibleOwnedIdentities) { ownedIdentity in
                                        profileCard(for: ownedIdentity, isCompatible: false)
                                    }
                                }
                            } else {
                                ForEach(viewModel.ownedIdentities) { ownedIdentity in
                                    profileCard(for: ownedIdentity, isCompatible: true)
                                }
                                .disabled(continueWithThisProfileButtonWasTapped)
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
                .navigationBarTitle(configuration.title, displayMode: .inline)
            } else {
                ObvCenteredProgressView()
            }
        }
        .task(onTask)
        .onAppear(perform: { continueWithThisProfileButtonWasTapped = false })
        .alert(String(localizedInThisBundle: "PROFILE_ON_A_DIFFERENT_SERVER_TITLE"), isPresented: $showIncompatibleProfileExplanation) {
            // No button provided: SwiftUI shows a default, system-localized "OK" button.
        } message: {
            // Note: this `Text` resolves against the module bundle (see the custom `Text(_:comment:)` init), unlike the alert's
            // title which takes a raw `LocalizedStringKey` and would otherwise be looked up in `Bundle.main`.
            Text("PROFILE_ON_A_DIFFERENT_SERVER_MESSAGE")
        }
    }


    @ViewBuilder
    private func profileCard(for ownedIdentity: OwnedIdentityChooserViewModel.OwnedIdentity, isCompatible: Bool) -> some View {
        ObvCardView(padding: 0) {
            OwnedIdentityItemView(currentOwnedCryptoId: currentOwnedCryptoId,
                                  viewModel: ownedIdentity,
                                  dataSource: dataSource,
                                  avatarViewDataSource: avatarViewDataSource,
                                  configuration: configuration,
                                  ownedCryptoIdTappedByUser: $ownedCryptoIdTappedByUser,
                                  isCompatibleWithServerRestriction: isCompatible,
                                  onTapWhenIncompatible: { showIncompatibleProfileExplanation = true })
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .rainbowBorder(
            cornerRadius: ObvCardViewParameters.defaultCornerRadius,
            isActive: isInSelectProfileMode && isCompatible && ownedCryptoIdTappedByUser == ownedIdentity.ownedCryptoId)
    }
}


// MARK: - Internal view: CreateNewProfileCard

/// Row shown at the end of the selectable profiles when a `ServerRestriction` allows it. Tapping it lets the user create a new
/// profile on the restriction's server.
///
/// Its layout mirrors `OwnedIdentityItemView`: a leading element the size of an avatar (so the title is leading-aligned with the
/// titles of the profile rows above it) and the same paddings (so its height matches the other cards).
private struct CreateNewProfileCard: View {

    let action: () -> Void

    /// Same spacing as the one between the avatar and the text area in `OwnedIdentityItemView`.
    private static let kCircleToTextAreaPadding = CGFloat(8.0)

    private var avatarFrameSize: CGSize { ObvAvatarSize.normal.frameSize }

    var body: some View {
        ObvCardView(padding: 0) {
            HStack(alignment: .center, spacing: Self.kCircleToTextAreaPadding) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                    Image(systemIcon: .plus)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: avatarFrameSize.width, height: avatarFrameSize.height)
                Text("CREATE_A_NEW_PROFILE_ON_THIS_SERVER")
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .font(.system(.headline, design: .rounded))
                Spacer(minLength: 0)
                ObvChevronRight()
                    .padding(.trailing, 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .onTapGesture(perform: action)
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
