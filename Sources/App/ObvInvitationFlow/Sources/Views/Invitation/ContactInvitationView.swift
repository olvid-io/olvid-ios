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
import ObvTypes
import CoreData
import ObvAppTypes
import ObvDesignSystem
import ConfettiSwiftUI
import ObvCells

public struct ContactInvitationViewModel: Sendable, Equatable {
    let avatarModel: ObvAvatarViewModel
    let isKeycloakManaged: Bool
    let title: String
    let subtitle: String
    let inviteHasBeenSent: Bool
    let groupsAvatarModel: [ObvAvatarViewModel]
    let groupTitle: String?
    let isOneToOne: Bool
    
    public init(avatarModel: ObvAvatarViewModel, isKeycloakManaged: Bool, title: String, subtitle: String, inviteHasBeenSent: Bool, groupsAvatarModel: [ObvAvatarViewModel], groupTitle: String?, isOneToOne: Bool) {
        self.avatarModel = avatarModel
        self.isKeycloakManaged = isKeycloakManaged
        self.title = title
        self.subtitle = subtitle
        self.inviteHasBeenSent = inviteHasBeenSent
        self.groupsAvatarModel = groupsAvatarModel
        self.groupTitle = groupTitle
        self.isOneToOne = isOneToOne
    }
    
    public enum ContactIdentifier: Sendable, Equatable, Hashable {
        case obvContactIdentifier(ObvContactIdentifier, ObvKeycloakUserDetails?)
        
        public var contactIdentifier: ObvContactIdentifier {
            switch self {
            case .obvContactIdentifier(let identifier, _):
                return identifier
            }
        }
        
        public var keycloakUserDetails: ObvKeycloakUserDetails? {
            switch self {
            case .obvContactIdentifier(_, let details):
                return details
            }
        }
    }
}


@MainActor
public protocol ObvContactInvitationViewAction {
    func userWantsToDiscussWith(_ view: ContactInvitationView, obvContactIdentifier: ObvContactIdentifier)
    func userWantsToInviteContactsToOneToOne(_ view: ContactInvitationView, ownedCryptoId: ObvCryptoId, users: [(cryptoId: ObvCryptoId, keycloakDetails: ObvKeycloakUserDetails?)]) async throws
    func userWantsToRemoveOneToOneInvitationSent(_ view: ContactInvitationView, contactIdentifier: ObvContactIdentifier) async throws
}


@MainActor
public protocol ObvContactInvitationViewDataSource {
    func getAsyncStreamOfContactInvitationViewModel(_ view: ContactInvitationView, contactIdentifier: ContactInvitationViewModel.ContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ContactInvitationViewModel>)
    func finishAsyncStreamOfContactInvitationViewModel(_ view: ContactInvitationView, streamUUID: UUID)
    
}


public struct ContactInvitationView: View {
    
    let contactIdentifier: ContactInvitationViewModel.ContactIdentifier
    let currentOwnedCryptoId: ObvCryptoId
    let router: InvitationFlowRouter
    
    @State private var streamedViewModel: ContactInvitationViewModel?
    
    @Environment(\.dismiss) private var dismiss
    
    private var viewModel: ContactInvitationViewModel? {
        self.streamedViewModel
    }
    
    @State private var triggerConfettiCanon = 0
    @State private var triggerConfettiCanonFull = 0
    
    init(contactIdentifier: ContactInvitationViewModel.ContactIdentifier, currentOwnedCryptoId: ObvCryptoId, router: InvitationFlowRouter) {
        self.contactIdentifier = contactIdentifier
        self.currentOwnedCryptoId = currentOwnedCryptoId
        self.router = router
    }
    
    private func userWantsToCancelOneToOneInvitationSent() {
        Task {
            do {
                let contactIdentifier = ObvContactIdentifier(contactCryptoId: contactIdentifier.contactIdentifier.contactCryptoId, ownedCryptoId: currentOwnedCryptoId)
                try await router.contactInvitationViewAction.userWantsToRemoveOneToOneInvitationSent(self, contactIdentifier: contactIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
    @ViewBuilder
    public var content: some View {
        VStack() {
            Spacer()
            ZStack(alignment: .center) {
                VStack(alignment: .center) {
                    if let viewModel {
                        HStack(alignment: .center) {
                            Spacer()
                            DismissButton(action: { dismiss() })
                        }
                        .onChange(of: viewModel.inviteHasBeenSent) { newValue in
                            if !viewModel.inviteHasBeenSent && newValue {
                                self.triggerConfettiCanon += 1
                            }
                        }
                        .onChange(of: viewModel.isOneToOne) { newValue in
                            if !viewModel.isOneToOne && newValue {
                                self.triggerConfettiCanonFull += 1
                            }
                        }
                        
                        ZStack(alignment: .center) {
                            ObvAvatarView(model: viewModel.avatarModel,
                                          style: .circle,
                                          size: .custom(frameSize: CGSize(width: 144.0, height: 144.0)),
                                          dataSource: router.avatarViewDataSource)
                            Circle()
                                .stroke(.white.opacity(0.4), lineWidth: 4.0)
                                .frame(width: 140.0)
                                .overlay(Image(systemIcon: .checkmarkShieldFill)
                                    .font(.system(size: (144.0) / 4))
                                    .foregroundColor(viewModel.isKeycloakManaged ? Color(AppTheme.shared.colorScheme.green) : .clear)
                                    .accessibilityHidden(!viewModel.isKeycloakManaged),
                                         alignment: .topTrailing
                                )
                        }
                        .padding(.bottom, 20.0)
                        
                        Text(viewModel.title)
                            .lineLimit(nil)
                            .multilineTextAlignment(.center)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(viewModel.subtitle)
                            .lineLimit(nil)
                            .multilineTextAlignment(.center)
                            .font(.headline)
                            .fontWeight(.regular)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 24.0)
                        
                        if !viewModel.groupsAvatarModel.isEmpty {
                            HStack(alignment: .center, spacing: -12) {
                                ForEach(viewModel.groupsAvatarModel, id: \.self) { groupAvatarModel in
                                    ObvAvatarView(model: groupAvatarModel,
                                                  style: .circle,
                                                  size: .small,
                                                  dataSource: router.avatarViewDataSource)
                                }
                            }
                        }
                        
                        if let groupTitle = viewModel.groupTitle {
                            Text(groupTitle)
                                .lineLimit(nil)
                                .multilineTextAlignment(.center)
                                .font(.subheadline)
                                .fontWeight(.light)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 24.0)
                        }
                        
                        if viewModel.isOneToOne {
                            GoToOneToOneDiscussionButton {
                                router.contactInvitationViewAction.userWantsToDiscussWith(self, obvContactIdentifier: self.contactIdentifier.contactIdentifier)
                            }
                        } else if !viewModel.inviteHasBeenSent {
                            InviteUserButton(action: processInvitation)
                        } else {
                            RemoveInvitationButton(action: userWantsToCancelOneToOneInvitationSent)
                        }
                    } else {
                        HStack() {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 40.0)
                            Spacer()
                        }
                    }
                }
                .padding(24.0)
                .padding(.bottom, 8.0)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(48.0)
            }
            Spacer()
        }
        .padding(.horizontal, 24.0)
    }
    
    public var contentBody: some View {
        content
            .confettiCannon(trigger: $triggerConfettiCanon,
                            num: 10,
                            openingAngle: Angle(degrees: 0),
                            closingAngle: Angle(degrees: 360),
                            radius: 200)
            .edgesIgnoringSafeArea(.all)
            .confettiCannon(trigger: $triggerConfettiCanonFull,
                            num: 100,
                            openingAngle: Angle(degrees: 0),
                            closingAngle: Angle(degrees: 360),
                            radius: 200)
            .edgesIgnoringSafeArea(.all)
            .task(onTaskForAsyncStreamOfContactInvitationViewModel)
    }
    
    public var body: some View {
        if #available(iOS 16.4, *) {
            contentBody
                .presentationBackground(.black.opacity(0.5))
        } else {
            contentBody
        }
    }
    
    private func processInvitation() {
        Task {
            do {
                try await self.router.contactInvitationViewAction.userWantsToInviteContactsToOneToOne(
                    self,
                    ownedCryptoId: contactIdentifier.contactIdentifier.ownedCryptoId,
                    users: [(contactIdentifier.contactIdentifier.contactCryptoId, contactIdentifier.keycloakUserDetails)])
            } catch {
                assertionFailure()
            }
        }
    }
}


// MARK: - Internal view

private struct GoToOneToOneDiscussionButton: View {

    let action: () -> Void
    
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Text("BUTTON_ACTION_INVITE_GO_TO_DISCUSSION")
                    .fontWeight(.bold)
                    .padding(.vertical, 8.0)
            }
            .buttonStyle(.glassProminent)
            .buttonSizing(.flexible)
        } else {
            Button(action: action) {
                HStack {
                    Spacer()
                    Text("BUTTON_ACTION_INVITE_GO_TO_DISCUSSION")
                        .fontWeight(.bold)
                        .padding(.vertical, 8.0)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
}


// MARK: - Internal view

private struct InviteUserButton: View {
    
    let action: () -> Void
    
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Text("BUTTON_ACTION_INVITE")
                    .fontWeight(.bold)
                    .padding(.vertical, 8.0)
            }
            .buttonStyle(.glassProminent)
            .buttonSizing(.flexible)
        } else {
            Button(action: action) {
                HStack {
                    Spacer()
                    Text("BUTTON_ACTION_INVITE")
                        .fontWeight(.bold)
                        .padding(.vertical, 8.0)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
}


// MARK: - Internal view

private struct RemoveInvitationButton: View {
    
    let action: () -> Void
    
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Text("BUTTON_ACTION_INVITE_REMOVE")
                    .padding(.vertical, 8.0)
            }
            .buttonStyle(.glass)
            .buttonSizing(.flexible)
        } else {
            Button(action: action) {
                HStack {
                    Spacer()
                    Text("BUTTON_ACTION_INVITE_REMOVE")
                        .padding(.vertical, 8.0)
                    Spacer()
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
}


// MARK: - Internal view

private struct DismissButton: View {
    
    let action: () -> Void
    
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: .close, action: action)
                .buttonStyle(.glass)
        } else {
            Button(action: action) {
                Image(systemIcon: .xmark)
                    .imageScale(.large)
                    .frame(width: ObvAvatarSize.normal.frameSize.width, height: ObvAvatarSize.normal.frameSize.height)
                    .tint(Color.primary)
                    .background(
                        Circle().stroke(Color.primary.opacity(0.3), lineWidth: 0.5)
                    )
            }
        }
    }
    
}


extension ContactInvitationView {
    private func onTaskForAsyncStreamOfContactInvitationViewModel() async {
        do {
            let (streamUUID, stream) = try await router.contactInvitationViewDataSource.getAsyncStreamOfContactInvitationViewModel(self, contactIdentifier: contactIdentifier)
            for await receivedModel in stream {
                withAnimation {
                    self.streamedViewModel = receivedModel
                }
            }
            router.contactInvitationViewDataSource.finishAsyncStreamOfContactInvitationViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
}

extension ObvKeycloakUserDetails {

    public var firstNameAndLastName: String {
        guard let coreDetails = try? ObvIdentityCoreDetails(firstName: firstName, lastName: lastName, company: company, position: position, signedUserDetails: nil) else { return "" }
        return coreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
    }
    
}





// MARK: - Previews

#if DEBUG

@MainActor
private let minimalDataSourceForPreviews = MinimalDataSourceAndActionsForPreviews()

#Preview {
    ZStack {
        ContactInvitationView(contactIdentifier: .obvContactIdentifier(ObvContactIdentifier.sampleDatas[0], nil),
                              currentOwnedCryptoId: ObvCryptoId.sampleOwnedCryptoId,
                              router: InvitationFlowRouter.initForPreviews())
    }.background(.red)
}

#endif

