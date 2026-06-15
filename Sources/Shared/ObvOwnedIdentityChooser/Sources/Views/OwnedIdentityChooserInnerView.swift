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


/// View allowing SwiftUI previews for the `OwnedIdentityChooserView`.
public struct OwnedIdentityChooserInnerView: View {
    
    let currentOwnedCryptoId: ObvCryptoId
    let actions: OwnedIdentityChooserInnerViewActionsProtocol
    let configuration: OwnedIdentityChooserInnerViewConfiguration
    let dataSource: OwnedIdentityChooserViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    
    @Binding var ownedCryptoIdTappedByUser: ObvCryptoId?
    
    @State private var continueWithThisProfileButtonWasTapped: Bool = false

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
                                        .multilineTextAlignment(.center)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal)
                                .padding(.bottom)
                            }
                            ForEach(viewModel.ownedIdentities) { ownedIdentity in
                                ObvCardView(padding: 0) {
                                    OwnedIdentityItemView(currentOwnedCryptoId: currentOwnedCryptoId,
                                                          viewModel: ownedIdentity,
                                                          dataSource: dataSource,
                                                          avatarViewDataSource: avatarViewDataSource,
                                                          configuration: configuration,
                                                          ownedCryptoIdTappedByUser: $ownedCryptoIdTappedByUser)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                }
                                .rainbowBorder(
                                    cornerRadius: ObvCardViewParameters.defaultCornerRadius,
                                    isActive: configuration.mode == .selectProfile && ownedCryptoIdTappedByUser == ownedIdentity.ownedCryptoId)
                            }
                            .disabled(continueWithThisProfileButtonWasTapped)
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
