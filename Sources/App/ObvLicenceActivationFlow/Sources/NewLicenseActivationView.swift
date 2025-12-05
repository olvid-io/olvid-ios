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
import ObvDesignSystem
import ObvSystemIcon
import ObvTypes
import ConfettiSwiftUI



public struct NewLicenseActivationViewModel: Sendable, Equatable {
    let isKeycloakManaged: Bool
    let currentAPIKeyElements: ObvTypes.APIKeyElements
    let isActive: Bool
    
    public init(isKeycloakManaged: Bool, currentAPIKeyElements: ObvTypes.APIKeyElements, isActive: Bool) {
        self.isKeycloakManaged = isKeycloakManaged
        self.currentAPIKeyElements = currentAPIKeyElements
        self.isActive = isActive
    }
    
}


@MainActor
public protocol NewLicenseActivationViewDataSource: AnyObject {
    // Streaming the user's current license (updates if she accepts the new license)
//    func getInitialNewLicenseActivationViewModel(ownedCryptoId: ObvCryptoId) -> NewLicenseActivationViewModel?
    func getAsyncStreamOfNewLicenseActivationViewModel(_ view: NewLicenseActivationView, ownedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<NewLicenseActivationViewModel>)
    func finishAsyncStreamOfNewLicenseActivationViewModel(_ view: NewLicenseActivationView, streamUUID: UUID)
    // Requesting the new license to activate
    func getApiKeyElementsFromServer(_ view: NewLicenseActivationView, ownedCryptoId: ObvCryptoId, apiKey: UUID) async throws -> ObvTypes.APIKeyElements
}

@MainActor
public protocol NewLicenseActivationViewActions {
    func userWantsToActivateNewLicense(_ view: NewLicenseActivationView, ownedCryptoId: ObvCryptoId, serverAndAPIKey: ServerAndAPIKey) async throws
    func userWantsToDismissNewLicenseActivationView(_ view: NewLicenseActivationView)
}


// MARK: - NewLicenseActivationView

public struct NewLicenseActivationView: View {
    
    let ownedCryptoId: ObvCryptoId
    let serverAndAPIKey: ServerAndAPIKey
    let dataSource: NewLicenseActivationViewDataSource
    let actions: NewLicenseActivationViewActions
    let initialViewModel: NewLicenseActivationViewModel?

    init(ownedCryptoId: ObvCryptoId, serverAndAPIKey: ServerAndAPIKey, dataSource: NewLicenseActivationViewDataSource, actions: NewLicenseActivationViewActions) {
        self.ownedCryptoId = ownedCryptoId
        self.serverAndAPIKey = serverAndAPIKey
        self.dataSource = dataSource
        self.actions = actions
//        if let receivedModel = dataSource.getInitialNewLicenseActivationViewModel(ownedCryptoId: ownedCryptoId) {
//            initialViewModel = receivedModel
//        } else {
//            initialViewModel = nil
//        }
        initialViewModel = nil
    }
    
    @State private var isAPIKeyActivated = false
    @State private var isAPIKeyActivating = false
    @State private var activationRequestError: Error?
    @State private var apiKeyElementsFromServerStatus: APIKeyElementsFromServerStatus = .none
    @State private var streamedViewModel: NewLicenseActivationViewModel?
    @State private var triggerConfettiCanon: Int = 0

    private var viewModel: NewLicenseActivationViewModel? {
        self.streamedViewModel ?? self.initialViewModel
    }
    
    private func onTaskForAsyncStreamOfNewLicenseActivationViewModel() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfNewLicenseActivationViewModel(self, ownedCryptoId: ownedCryptoId)
            for await receivedModel in stream {
                withAnimation {
                    self.streamedViewModel = receivedModel
                }
            }
            dataSource.finishAsyncStreamOfNewLicenseActivationViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }

    private enum APIKeyElementsFromServerStatus {
        case none
        case fetching
        case fetchingFailed(Error)
        case success(ObvTypes.APIKeyElements)
    }
    
    private func userTappedCancelButton() {
        actions.userWantsToDismissNewLicenseActivationView(self)
    }
    
    private func activateNewLicenseButtonTapped() {
        withAnimation { isAPIKeyActivating = true }
        Task {
            do {
                try await actions.userWantsToActivateNewLicense(self, ownedCryptoId: ownedCryptoId, serverAndAPIKey: serverAndAPIKey)
                withAnimation {
                    isAPIKeyActivated = true
                    isAPIKeyActivating = false
                    activationRequestError = nil
                }
                // Sleep before the confettis
                Task {
                    try? await Task.sleep(milliseconds: 500)
                    triggerConfettiCanon += 1
                }
            } catch {
                withAnimation {
                    isAPIKeyActivated = false
                    isAPIKeyActivating = false
                    activationRequestError = error
                }
            }
        }
    }
    
    private enum ActivationError: Error {
        case failed
        case invalidAPIKey
    }
    
    /// Button shown once the user accepted the new license (i.e., after tapping the "accept" button)
    private func okButtonTapped() {
        actions.userWantsToDismissNewLicenseActivationView(self)
    }
    
    private func onTask() async {
        await userWantsToQueryAPIKeyElementsFromServer()
    }
    
    private var apiKeyServerIsCompatibleWithOwnedIdentityServer: Bool {
        self.ownedCryptoId.belongsTo(serverURL: serverAndAPIKey.server)
    }

    private func userWantsToQueryAPIKeyElementsFromServer() async {
        withAnimation { apiKeyElementsFromServerStatus = .fetching }
        assert(ownedCryptoId.belongsTo(serverURL: serverAndAPIKey.server), "This should have been checked by this view earlier")
        do {
            let APIKeyElementsFromServer = try await dataSource.getApiKeyElementsFromServer(self, ownedCryptoId: ownedCryptoId, apiKey: serverAndAPIKey.apiKey)
            withAnimation { apiKeyElementsFromServerStatus = .success(APIKeyElementsFromServer) }
        } catch {
            withAnimation { apiKeyElementsFromServerStatus = .fetchingFailed(error) }
        }
    }
    
    private func cannotActivateLicense(viewModel: NewLicenseActivationViewModel) -> Bool {
        !viewModel.isActive || viewModel.isKeycloakManaged || !apiKeyServerIsCompatibleWithOwnedIdentityServer
    }
    
    private func activateLicenseButtonAction(viewModel: NewLicenseActivationViewModel) -> (() -> Void)? {
        if cannotActivateLicense(viewModel: viewModel) {
            return nil
        } else {
            return activateNewLicenseButtonTapped
        }
    }
    
    public var body: some View {
        NavigationView {
            
            ZStack {
                
                Color(AppTheme.shared.colorScheme.systemBackground)
                    .edgesIgnoringSafeArea(.all)
                
                if let viewModel {
                    
                    VStack {
                        
                        // ----------
                        // ScrollView
                        // ----------
                        
                        ScrollView {
                            
                            VStack {
                                
                                // API Key elements fetched from server
                                
                                if !isAPIKeyActivated {
                                    
                                    switch apiKeyElementsFromServerStatus {
                                        
                                    case .none:
                                        
                                        EmptyView()
                                        
                                    case .fetching:
                                        
                                        HStack {
                                            Spacer()
                                            ProgressView(String(localizedInThisBundle: "LOOKING_FOR_YOUR_LICENSE"))
                                            Spacer()
                                        }
                                        .padding(.vertical, 32)
                                        
                                    case .fetchingFailed(let error):
                                        
                                        UnableToActivateLicenseView(category: .queryingAPIKeyElementsFromServerDidFail(error))
                                        
                                    case .success(let apiKeyElementsFetchedFromServer):
                                        
                                        if cannotActivateLicense(viewModel: viewModel) {
                                            VStack {
                                                if !viewModel.isActive {
                                                    UnableToActivateLicenseView(category: .ownedIdentityIsInactive)
                                                } else if viewModel.isKeycloakManaged {
                                                    UnableToActivateLicenseView(category: .ownedIdentityIsKeycloakManaged)
                                                } else if !apiKeyServerIsCompatibleWithOwnedIdentityServer {
                                                    UnableToActivateLicenseView(category: .serverAndAPIKeyIncompatibleWithOwnServer)
                                                }
                                            }
                                            .padding(.bottom)
                                        } else if let activationRequestError {
                                            UnableToActivateLicenseView(category: .activationRequestFailed(activationRequestError))
                                                .padding(.bottom)
                                        }
                                        
                                        NewSubscriptionStatusView(title: Text("NEW_LICENSE_TO_ACTIVATE"),
                                                                  apiKeyStatus: apiKeyElementsFetchedFromServer.status,
                                                                  apiKeyExpirationDate: apiKeyElementsFetchedFromServer.expirationDate,
                                                                  apiPermissions: apiKeyElementsFetchedFromServer.permissions,
                                                                  activateLicenseButtonAction: activateLicenseButtonAction(viewModel: viewModel),
                                                                  isAPIKeyActivating: $isAPIKeyActivating)
                                        .padding(.bottom, 32)
                                        
                                    }
                                    
                                }
                                
                                // Current licence
                                
                                NewSubscriptionStatusView(title: Text("CURRENT_LICENSE_STATUS"),
                                                          apiKeyStatus: viewModel.currentAPIKeyElements.status,
                                                          apiKeyExpirationDate: viewModel.currentAPIKeyElements.expirationDate,
                                                          apiPermissions: viewModel.currentAPIKeyElements.permissions)
                                .confettiCannon(trigger: $triggerConfettiCanon,
                                                num: 50,
                                                openingAngle: Angle(degrees: 0),
                                                closingAngle: Angle(degrees: 360),
                                                radius: 200)
                                
                            }.padding()
                            
                        } // ScrollView
                        
                        // -------
                        // Buttons
                        // -------
                        
                        VStack {
                            if !isAPIKeyActivated {                                                                
                                CancelButton(action: userTappedCancelButton)
                            } else {
                                OkButton(action: okButtonTapped)
                            }
                        }
                        .disabled(isAPIKeyActivating)
                        .padding()
                    }

                    
                } else {
                    
                    ObvCenteredProgressView()
                    
                }
                
            }
            .navigationTitle(String(localizedInThisBundle: "MANAGE_YOUR_LICENSE"))
            .task { await onTask() }
            .task { await onTaskForAsyncStreamOfNewLicenseActivationViewModel() }

            
        }
    }
}


private struct OkButton: View {
    
    let action: () -> Void
    
    private let systemIcon: SystemIcon = .checkmarkCircle

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Label(title: { Text("OK") }, icon: { Image(systemIcon: systemIcon) })
                .padding(.vertical, 8)
            }
            .buttonSizing(.flexible)
            .buttonStyle(.glassProminent)
        } else {
            Button(action: action) {
                HStack {
                    Spacer(minLength: 0)
                    Label(title: { Text("OK") }, icon: { Image(systemIcon: systemIcon) })
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
}


// MARK: - Internal view

private struct UnableToActivateLicenseView: View {
    
    enum Category {
        case ownedIdentityIsKeycloakManaged
        case serverAndAPIKeyIncompatibleWithOwnServer
        case queryingAPIKeyElementsFromServerDidFail(Error)
        case ownedIdentityIsInactive
        case activationRequestFailed(Error)
    }
    
    let category: Category

    var body: some View {
        ObvCardView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemIcon: .exclamationmarkCircle)
                        .foregroundColor(.red)
                        .font(.system(size: 32, weight: .medium))
                    Text("UNABLE_TO_ACTIVATE_LICENSE_TITLE")
                        .font(.headline)
                    Spacer()
                }
                HStack {
                    switch category {
                    case .ownedIdentityIsKeycloakManaged:
                        Text("UNABLE_TO_ACTIVATE_LICENSE_EXPLANATION")
                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                            .font(.body)
                    case .serverAndAPIKeyIncompatibleWithOwnServer:
                        Text("UNABLE_TO_ACTIVATE_LICENSE_EXPLANATION_ALT")
                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                            .font(.body)
                    case .queryingAPIKeyElementsFromServerDidFail:
                        Text("COULD_NOT_QUERY_SERVER_FOR_API_KEY_ELEMENTS")
                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                            .font(.body)
                    case .ownedIdentityIsInactive:
                        Text("UNABLE_TO_ACTIVATE_LICENSE_EXPLANATION_OWNED_IDENTITY_INACTIVE")
                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                            .font(.body)
                    case .activationRequestFailed:
                        Text("ACTIVATION_REQUEST_FAILED")
                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                            .font(.body)
                    }
                    Spacer()
                }
                switch category {
                case .ownedIdentityIsKeycloakManaged:
                    HStack {
                        Text("PLEASE_CONTACT_ADMIN_FOR_MORE_DETAILS")
                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                            .font(.body)
                        Spacer()
                    }
                case .serverAndAPIKeyIncompatibleWithOwnServer,
                        .queryingAPIKeyElementsFromServerDidFail,
                        .ownedIdentityIsInactive,
                        .activationRequestFailed:
                    EmptyView()
                }
            }
        }
    }
    
}



// MARK: - Internal view: Cancel button

private struct CancelButton: View {
    
    let action: () -> Void
    
    private let systemIcon: SystemIcon = .xmarkCircle
    
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Label(title: { Text("CANCEL") }, icon: { Image(systemIcon: systemIcon) })
                    .padding(.vertical, 8)
            }
            .buttonSizing(.flexible)
            .buttonStyle(.glass)
        } else {
            Button(action: action) {
                HStack {
                    Spacer(minLength: 0)
                    Label(title: { Text("CANCEL") }, icon: { Image(systemIcon: systemIcon) })
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        }
    }
}




// MARK: - Previews

#if DEBUG

@MainActor
private let initialLicense = NewLicenseActivationViewModel(
    isKeycloakManaged: false,
    currentAPIKeyElements: .init(
        status: .valid,
        permissions: [],
        expirationDate: nil),
    isActive: true)

@MainActor
private let licenseFromServer = NewLicenseActivationViewModel(
    isKeycloakManaged: false,
    currentAPIKeyElements: .init(
        status: .valid,
        permissions: [.canCall, .multidevice],
        expirationDate: Date.now.addingTimeInterval(.init(months: 6))),
    isActive: true)

private final class DataSourceForPreviews: NewLicenseActivationViewDataSource {
    
    private var continuation: AsyncStream<NewLicenseActivationViewModel>.Continuation?
    
//    func getInitialNewLicenseActivationViewModel(ownedCryptoId: ObvTypes.ObvCryptoId) -> NewLicenseActivationViewModel? {
//        
//        return initialLicense
//        
//    }
    
    func getAsyncStreamOfNewLicenseActivationViewModel(_ view: NewLicenseActivationView, ownedCryptoId: ObvTypes.ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<NewLicenseActivationViewModel>) {
        let stream = AsyncStream(NewLicenseActivationViewModel.self) { (continuation: AsyncStream<NewLicenseActivationViewModel>.Continuation) in
            self.continuation = continuation
            Task {
                try? await Task.sleep(seconds: 1)
                continuation.yield(initialLicense)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfNewLicenseActivationViewModel(_ view: NewLicenseActivationView, streamUUID: UUID) {
        // Nothing to finish in previews
    }

    func getApiKeyElementsFromServer(_ view: NewLicenseActivationView, ownedCryptoId: ObvCryptoId, apiKey: UUID) async throws -> APIKeyElements {
        try? await Task.sleep(seconds: 2)
        return .init(status: .valid,
                     permissions: [.canCall, .multidevice],
                     expirationDate: Date.now.addingTimeInterval(.init(months: 6)))
    }
    
}


extension DataSourceForPreviews: NewLicenseActivationViewActions {
    
    func userWantsToActivateNewLicense(_ view: NewLicenseActivationView, ownedCryptoId: ObvTypes.ObvCryptoId, serverAndAPIKey: ObvTypes.ServerAndAPIKey) async throws {
        try await Task.sleep(seconds: 2)
        continuation?.yield(licenseFromServer)
    }
    
    func userWantsToDismissNewLicenseActivationView(_ view: NewLicenseActivationView) {
        print("Dismiss view")
    }
    
}

@MainActor
private let ownedCryptoIdForPreviews = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)


@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

@MainActor
private let serverAndAPIKeyForPreviews = ServerAndAPIKey(server: ownedCryptoIdForPreviews.cryptoIdentity.serverURL, apiKey: UUID())

#Preview {
    NewLicenseActivationView(ownedCryptoId: ownedCryptoIdForPreviews,
                             serverAndAPIKey: serverAndAPIKeyForPreviews,
                             dataSource: dataSourceForPreviews,
                             actions: dataSourceForPreviews)
}

#endif // DEBUG
