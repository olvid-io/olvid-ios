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
import ObvDesignSystem
import ConfettiSwiftUI
import ObvAppTypes
import ObvCells


/// Manages the state and logic for validating a scanned `ObvMutualScanUrl` in the invitation flow during a double-scan.
///
/// When the current user scans a remote user’s `ObvMutualScanUrl`, the `ScannerView` passes the URL to its delegate.
/// The delegate processes the URL and provides an initial `ScanValidationViewModel` to drive this view.
///
/// - **Initial State:**
///   The view starts in a pending state, waiting for the data source to stream an updated model.
///
/// - **Success State:**
///   On successful contact addition (with good network conditions), the data source streams a new version of the model.
///   The view updates to reflect the new contact and enables immediate conversation.
public struct ScanValidationViewModel: Sendable, Equatable, Hashable {
    
    let contactIdentifier: ObvContactIdentifier
    let contactFullDisplayName: String
    let contactAvatarModel: ObvAvatarViewModel
    let contactStatus: Status
    
    public enum Status: Equatable, Sendable, Hashable {
        case contactNotAddedYet
        case contactAdded(activeOneToOneDiscussionAvailable: Bool, contactFirstName: String)
    }
    
    public init(contactStatus: Status, contactAvatarModel: ObvAvatarViewModel, contactFullDisplayName: String, contactIdentifier: ObvContactIdentifier) {
        self.contactStatus = contactStatus
        self.contactAvatarModel = contactAvatarModel
        self.contactFullDisplayName = contactFullDisplayName
        self.contactIdentifier = contactIdentifier
    }
    
    var activeOneToOneDiscussionAvailable: Bool {
        switch contactStatus {
        case .contactAdded(activeOneToOneDiscussionAvailable: let available, contactFirstName: _):
            return available
        case .contactNotAddedYet:
            return false
        }
    }
    
}


@MainActor
public protocol ObvScanValidationViewDataSource {
    func getAsyncStreamOfScanValidationViewModel(_ view: ScanValidationView, contactIdentifier: ObvContactIdentifier, contactFullDisplayName: String) async throws -> (streamUUID: UUID, stream: AsyncStream<ScanValidationViewModel>)
    func finishAsyncStreamOfScanValidationViewModel(_ view: ScanValidationView, streamUUID: UUID)
}


@MainActor
public protocol ObvScanValidationViewActions {
    func userWantsToNavigateToOneToOneDiscussion(_ view: ScanValidationView, obvContactIdentifier: ObvContactIdentifier)
}


/// A full-screen view displayed at the completion of a double-scan flow between two Olvid users.
///
/// - For the user **displaying** the `ObvMutualScanUrl`:
///   The scanner detects when a one-to-one discussion becomes available and automatically presents this view.
///
/// - For the user **scanning** the other user’s `ObvMutualScanUrl`:
///   This view is presented full-screen once the app resumes the invitation flow.
public struct ScanValidationView: View {
    
    @Environment(\.dismiss) private var dismiss
    
    let currentOwnedCryptoId: ObvCryptoId
    let router: InvitationFlowRouter
    
    @State private var streamedViewModel: ScanValidationViewModel?
    let initialViewModel: ScanValidationViewModel
    
    private var viewModel: ScanValidationViewModel {
        self.streamedViewModel ?? initialViewModel
    }
    
    @State private var triggerConfettiCanon = 0
    
    /// Call this method to trigger the confetti canon. This method ensures the canon is triggered only once.
    private func doTriggerConfettiCanon(afterDelay delay: TimeInterval) {
        Task {
            try? await Task.sleep(seconds: delay)
            guard triggerConfettiCanon == 0 else { return }
            triggerConfettiCanon += 1
        }
    }
    
    init(currentOwnedCryptoId: ObvCryptoId, initialViewModel: ScanValidationViewModel, router: InvitationFlowRouter) {
        self.currentOwnedCryptoId = currentOwnedCryptoId
        self.initialViewModel = initialViewModel
        self.router = router
        if initialViewModel.activeOneToOneDiscussionAvailable {
            doTriggerConfettiCanon(afterDelay: 1)
        }
    }
    
    @State private var addingContactTooksTooLong: Bool = false
    

    private var subtitle: String {
        switch viewModel.contactStatus {
        case .contactNotAddedYet:
            if addingContactTooksTooLong {
                return String(localizedInThisBundle: "SCAN_VALIDATION_SUBTITLE_CONTACT_WILL_BE_ADDED_WHEN_NETWORK_AVAILABLE")
            } else {
                return String(localizedInThisBundle: "SCAN_VALIDATION_SUBTITLE_ADDING_CONTACT")
            }
        case .contactAdded(activeOneToOneDiscussionAvailable: let activeOneToOneDiscussionAvailable, contactFirstName: let contactFirstName):
            if activeOneToOneDiscussionAvailable {
                return String(localizedInThisBundle: "SCAN_VALIDATION_SUBTITLE_DISCUSSION_AVAILABLE_\(contactFirstName)")
            } else {
                return String(localizedInThisBundle: "SCAN_VALIDATION_SUBTITLE_CONTACT_WILL_BE_ADDED_WHEN_NETWORK_AVAILABLE")
            }
        }
    }
    
    
    private func onTask() async {
        try? await Task.sleep(seconds: 3)
        switch viewModel.contactStatus {
        case .contactNotAddedYet:
            withAnimation { addingContactTooksTooLong = true }
        case .contactAdded:
            withAnimation { addingContactTooksTooLong = false }
        }
    }
    
    @ViewBuilder
    public var content: some View {
        VStack() {
            Spacer()
            ZStack(alignment: .center) {
                VStack(alignment: .center) {
                    HStack(alignment: .center) {
                        Spacer()
                        DismissButton(action: { dismiss() })
                    }
                    
                    ZStack(alignment: .center) {
                        ObvAvatarView(model: viewModel.contactAvatarModel,
                                      style: .circle,
                                      size: .custom(frameSize: CGSize(width: 144.0, height: 144.0)),
                                      dataSource: router.avatarViewDataSource)
                        Circle()
                            .stroke(.white.opacity(0.4), lineWidth: 4.0)
                            .frame(width: 140.0)
                    }
                    .padding(.bottom, 20.0)
                    
                    Text(viewModel.contactFullDisplayName)
                        .lineLimit(nil)
                        .multilineTextAlignment(.center)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(subtitle)
                        .lineLimit(nil)
                        .multilineTextAlignment(.center)
                        .font(.headline)
                        .fontWeight(.regular)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 24.0)
                    
                    if viewModel.activeOneToOneDiscussionAvailable {
                        GoToDiscussionButton {
                            router.scanValidationViewActions.userWantsToNavigateToOneToOneDiscussion(self, obvContactIdentifier: viewModel.contactIdentifier)
                        }
                    } else if addingContactTooksTooLong {
                        LargeOkButton {
                            router.dismiss()
                        }
                    } else {
                        ProgressView()
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
        .task(onTask)
        .onChange(of: viewModel) { newValue in
            if viewModel.activeOneToOneDiscussionAvailable || newValue.activeOneToOneDiscussionAvailable {
                doTriggerConfettiCanon(afterDelay: 1)
            }
        }
        .onAppear {
            if viewModel.activeOneToOneDiscussionAvailable {
                doTriggerConfettiCanon(afterDelay: 1)
            }
        }
    }
    
    var contentBody: some View {
        content
            .confettiCannon(trigger: $triggerConfettiCanon,
                            num: 100,
                            openingAngle: Angle(degrees: 0),
                            closingAngle: Angle(degrees: 360),
                            radius: 200)
            .edgesIgnoringSafeArea(.all)
            .task(onTaskForAsyncStreamOfScanValidationViewModel)
    }
    
    public var body: some View {
        if #available(iOS 16.4, *) {
            contentBody
                .presentationBackground(.black.opacity(0.5))
        } else {
            contentBody
        }
    }
}


extension ScanValidationView {
    private func onTaskForAsyncStreamOfScanValidationViewModel() async {
        do {
            let (streamUUID, stream) = try await router.scanValidationViewDataSource.getAsyncStreamOfScanValidationViewModel(
                self,
                contactIdentifier: viewModel.contactIdentifier,
                contactFullDisplayName: viewModel.contactFullDisplayName)
            for await receivedModel in stream {
                withAnimation {
                    self.streamedViewModel = receivedModel
                }
            }
            router.scanValidationViewDataSource.finishAsyncStreamOfScanValidationViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
}


// MARK: - Internal view

private struct LargeOkButton: View {
    
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Text("OK")
                    .padding(.vertical, 8.0)
            }
            .buttonStyle(.glassProminent)
            .buttonSizing(.flexible)
        } else {
            Button(action: action) {
                HStack {
                    Spacer()
                    Text("OK")
                        .padding(.vertical, 8.0)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
}



// MARK: - Internal view

private struct GoToDiscussionButton: View {
    
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Text("BUTTON_ACTION_INVITE_GO_TO_DISCUSSION")
                    .padding(.vertical, 8.0)
            }
            .buttonStyle(.glassProminent)
            .buttonSizing(.flexible)
        } else {
            Button(action: action) {
                HStack {
                    Spacer()
                    Text("BUTTON_ACTION_INVITE_GO_TO_DISCUSSION")
                        .padding(.vertical, 8.0)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
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

#if DEBUG

@MainActor
private let minimalDataSourceForPreviews = MinimalDataSourceAndActionsForPreviews()

#Preview() {
    ZStack {
        ScanValidationView(currentOwnedCryptoId: ObvCryptoId.sampleOwnedCryptoId,
                           initialViewModel: ScanValidationViewModel.sampleDatas[0],
                           router: InvitationFlowRouter.initForPreviews())
    }
    .background(.red)
}

#endif
