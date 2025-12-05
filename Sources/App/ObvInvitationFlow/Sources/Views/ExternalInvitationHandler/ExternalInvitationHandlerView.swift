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
import ObvDesignSystem

@MainActor
public protocol ObvExternalInvitationHandlerViewActions {
    func userWantsToStartTrustEstablishmentProtocolOfRemoteIdentity(_ view: ExternalInvitationHandlerView, ownedCryptoId: ObvCryptoId, remoteURLIdentity: ObvURLIdentity)
}


/// When the `ExternalInvitationHandlerView` appears on screen, it displays the current user’s `ObvMutualScanUrl`
/// and requests a stream of `ExternalInvitationHandlerViewModel` updates from its data source.
/// This stream notifies the view when a one-to-one discussion with the contact is available,
/// enabling automatic presentation of the confirmation screen.
///
/// This behavious is the same than the one in `NewScannerView` when it displays a `ObvMutualScanUrl`.
public struct ObvExternalInvitationHandlerViewModel: Sendable, Equatable {
    let scanValidationViewModel: ScanValidationViewModel
    
    public init(scanValidationViewModel: ScanValidationViewModel) {
        self.scanValidationViewModel = scanValidationViewModel
    }
    
}


@MainActor
public protocol ObvExternalInvitationHandlerViewDataSource {
    func getAsyncStreamOfObvExternalInvitationHandlerViewModel(_ view: ExternalInvitationHandlerView, contactIdentifier: ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvExternalInvitationHandlerViewModel>)
    func finishAsyncStreamOfObvExternalInvitationHandlerViewModel(_ view: ExternalInvitationHandlerView, streamUUID: UUID)
}

/// A view presented when the current user scans or taps an Olvid invitation link from outside the app.
///
/// This view is shown in scenarios where the user:
/// - Receives the link via SMS, email, or another external source, or
/// - Scans the link using the device’s native camera (outside the `ScannerView`).
///
/// Since the local user has no further scanning to perform, this view provides two options:
/// 1. **Face-to-face interaction:** This view display an `ObvMutualScanUrl` for the remote user to scan.
///    *(Note: This is less common, as face-to-face users typically perform a double-scan directly in the `ScannerView`.)*
/// 2. **Remote interaction:** The local user can send a remote invitation to the other user using the button shown by this view.
///    If accepted, both users will exchange SAS codes to complete the connection.
public struct ExternalInvitationHandlerView: View {
    
    let router: InvitationFlowRouter
    let mutualScanURLToShow: ObvMutualScanUrl
    let remoteURLIdentity: ObvURLIdentity
    let actions: ObvExternalInvitationHandlerViewActions
    
    private var ownedCryptoId: ObvCryptoId {
        mutualScanURLToShow.cryptoId
    }
    
    @State private var showAlertPastedInvitationLinkIsOwnInvitationLink: Bool = false

    private func userWantsToSendInvitationToRemoteUser() {
        // Make sure the "remote" identity is distinct from the owned identity
        guard remoteURLIdentity.cryptoId != mutualScanURLToShow.cryptoId else {
            showAlertPastedInvitationLinkIsOwnInvitationLink = true
            return
        }
        actions.userWantsToStartTrustEstablishmentProtocolOfRemoteIdentity(self, ownedCryptoId: mutualScanURLToShow.cryptoId, remoteURLIdentity: remoteURLIdentity)
    }
    
    private func showAlertAppearIfInvitationLinkIsOwnInvitationLink() {
        // Make sure the "remote" identity is distinct from the owned identity
        guard remoteURLIdentity.cryptoId != mutualScanURLToShow.cryptoId else {
            showAlertPastedInvitationLinkIsOwnInvitationLink = true
            return
        }
    }
    
    /// Requests a stream of `ExternalInvitationHandlerViewModel` from the data source.
    /// This stream allows to detect when a one-to-one discussion becomes available with the remote user—indicating they scanned our `ObvMutualScanUrl`—
    /// and to trigger navigation to the confirmation screen.
    private func requestAsyncStreamOfObvExternalInvitationHandlerViewModel() async {
        do {
            let contactIdentifier = ObvContactIdentifier(contactCryptoId: remoteURLIdentity.cryptoId, ownedCryptoId: mutualScanURLToShow.cryptoId)
            let (streamUUID, stream) = try await router.externalInvitationHandlerViewDataSource.getAsyncStreamOfObvExternalInvitationHandlerViewModel(self, contactIdentifier: contactIdentifier)
            for await receivedModel in stream {
                let scanValidationViewModel = receivedModel.scanValidationViewModel
                guard scanValidationViewModel.activeOneToOneDiscussionAvailable else { continue }
                router.popToRoot() // Go back to the list of contacts and groups
                router.presentFullScreen(.scanValidation(currentOwnedCryptoId: ownedCryptoId, initalScanViewModel: scanValidationViewModel))
                break // Stop receiving stream updates since the parent router will soon present the scan validation
            }
            router.externalInvitationHandlerViewDataSource.finishAsyncStreamOfObvExternalInvitationHandlerViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }

    public var body: some View {
        ZStack {
            
            Color(UIColor.secondarySystemBackground)
                .ignoresSafeArea()
            
            ScrollView {
                
                VStack {
                    
                    ObvCardView {
                        
                        VStack(alignment: .leading) {
                            
                            Text("OPTION_ONE_FACE_TO_FACE")
                                .font(.headline)
                            
                            Text("INVITE_\(remoteURLIdentity.fullDisplayName)_LOCALLY")
                                .foregroundStyle(.secondary)
                            
                            QRCodeView(ownedCryptoId: ownedCryptoId,
                                       dataSource: router.qrCodeViewDataSource,
                                       avatarViewDataSource: router.avatarViewDataSource,
                                       urlToShow: mutualScanURLToShow.urlRepresentation)
                            
                        }
                        .padding(.bottom)
                        
                    }
                    
                    ObvCardView {
                        
                        VStack(alignment: .leading) {
                            
                            HStack {
                                Text("OPTION_TWO_REMOTELY")
                                    .font(.headline)
                                Spacer(minLength: 0)
                            }
                            
                            
                            GetInContactRemotelyButton(action: userWantsToSendInvitationToRemoteUser)
                                .padding(.vertical)
                            
                        }
                        
                    }
                    
                }
                .padding()
                
            }
        }
        .navigationTitle(String(localizedInThisBundle: "GET_IN_CONTACT"))
        .task(requestAsyncStreamOfObvExternalInvitationHandlerViewModel)
        .onAppear(perform: showAlertAppearIfInvitationLinkIsOwnInvitationLink)
        .alert(String(localizedInThisBundle: "CANNOT_INVITE_YOURSELF_TITLE"), isPresented: $showAlertPastedInvitationLinkIsOwnInvitationLink, actions: {}) {
            Text("CANNOT_INVITE_YOURSELF_MESSAGE")
        }
    }
    
}


// MARK: - Private view

private struct GetInContactRemotelyButton: View {
    
    let action: () -> Void
    
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Text("GET_IN_CONTACT_REMOTELY")
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .buttonSizing(.flexible)
        } else {
            Button(action: action) {
                HStack {
                    Spacer(minLength: 0)
                    Text("GET_IN_CONTACT_REMOTELY")
                    Spacer(minLength: 0)
                }
            }
        }
    }
    
}

#if DEBUG

#Preview {
    ExternalInvitationHandlerView(router: InvitationFlowRouter.initForPreviews(),
                               mutualScanURLToShow: ObvMutualScanUrl.sampleData,
                               remoteURLIdentity: ObvURLIdentity.sampleDataRemoteIdentity,
                               actions: MinimalDataSourceAndActionsForPreviews())
}

#endif
