/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvEngine
import ObvUI
import ObvUICoreData
import OlvidUtils
import ObvSettings
import ObvDesignSystem


protocol LicenseActivationViewModelProtocol: ObservableObject {
    associatedtype OwnedIdentityModel: LicenseActivationViewModelOwnedIdentityModelProtocol
    var ownedIdentity: OwnedIdentityModel { get }
    var serverAndAPIKey: ServerAndAPIKey { get }
}


protocol LicenseActivationViewModelOwnedIdentityModelProtocol: ObservableObject {
    var ownedCryptoId: ObvCryptoId { get }
    var isKeycloakManaged: Bool { get }
    var currentAPIKeyElements: ObvTypes.APIKeyElements { get }
    var isActive: Bool { get }
}


protocol LicenseActivationViewActionsDelegate {
    func userWantsToDismissLicenseActivationView()
    func userWantsToRegisterAPIKey(ownedCryptoId: ObvCryptoId, apiKey: UUID) async throws
    func userWantsToQueryServerForAPIKeyElements(ownedCryptoId: ObvCryptoId, apiKey: UUID) async throws -> ObvTypes.APIKeyElements
}


struct LicenseActivationView<Model: LicenseActivationViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    let actions: LicenseActivationViewActionsDelegate
    
    
    @State private var apiKeyElementsFetchedFromServer: ObvTypes.APIKeyElements?
    @State private var isAPIKeyActivationInProgress = false
    @State private var shownHUDViewCategory: HUDView.Category?
    @State private var isQueryingAPIKeyElementsFromServer = false
    @State private var queryingAPIKeyElementsFromServerDidFail = false
    @State private var isAPIKeyActivated = false


    private var apiKeyServerIsCompatibleWithOwnedIdentityServer: Bool {
        model.ownedIdentity.ownedCryptoId.belongsTo(serverURL: model.serverAndAPIKey.server)
    }
    
    
    @MainActor
    private func userWantsToActivateNewLicense() async {
        
        guard !isAPIKeyActivationInProgress else { return }
        withAnimation { isAPIKeyActivationInProgress = true }
        defer { withAnimation { isAPIKeyActivationInProgress = false } }
        
        let ownedCryptoId = model.ownedIdentity.ownedCryptoId
        let apiKey = model.serverAndAPIKey.apiKey
        
        withAnimation { shownHUDViewCategory = .progress }
        
        var success: Bool
        do {
            try await actions.userWantsToRegisterAPIKey(ownedCryptoId: ownedCryptoId, apiKey: apiKey)
            withAnimation { shownHUDViewCategory = .checkmark }
            success = true
        } catch {
            withAnimation { shownHUDViewCategory = .xmark }
            success = false
        }
        await suspendDuringTimeInterval(2)
        withAnimation {
            shownHUDViewCategory = nil
            isAPIKeyActivated = success
        }
    }
    
    
    private func activateNewLicenseNow() {
        Task { await userWantsToActivateNewLicense() }
    }
    
    @MainActor
    private func userWantsToQueryAPIKeyElementsFromServer() async {
        do {
            let apiKeyElements = try await actions.userWantsToQueryServerForAPIKeyElements(ownedCryptoId: model.ownedIdentity.ownedCryptoId, apiKey: model.serverAndAPIKey.apiKey)
            withAnimation {
                apiKeyElementsFetchedFromServer = apiKeyElements
            }
        } catch {
            withAnimation {
                queryingAPIKeyElementsFromServerDidFail = true
            }
        }
    }
    

    private func queryAPIKeyElementsFromServer() {
        guard !isQueryingAPIKeyElementsFromServer else { return }
        isQueryingAPIKeyElementsFromServer = true
        Task { await userWantsToQueryAPIKeyElementsFromServer() }
    }

    
    private var showCancelButton: Bool {
        if apiKeyElementsFetchedFromServer == nil {
            return !queryingAPIKeyElementsFromServerDidFail
        } else {
            return !model.ownedIdentity.isKeycloakManaged && model.ownedIdentity.isActive && apiKeyServerIsCompatibleWithOwnedIdentityServer
        }
    }
    
    
    var body: some View {
        ZStack {
            
            Color(AppTheme.shared.colorScheme.systemBackground)
                .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                
                VStack {
                    
                    if !isAPIKeyActivated {
                        
                        if let apiKeyElementsFetchedFromServer {
                            
                            SubscriptionStatusView(title: Text("NEW_LICENSE_TO_ACTIVATE"),
                                                   apiKeyStatus: apiKeyElementsFetchedFromServer.status,
                                                   apiKeyExpirationDate: apiKeyElementsFetchedFromServer.expirationDate,
                                                   showSubscriptionPlansButton: false,
                                                   userWantsToSeeSubscriptionPlans: {},
                                                   showRefreshStatusButton: false,
                                                   refreshStatusAction: {},
                                                   apiPermissions: apiKeyElementsFetchedFromServer.permissions)
                            
                            if !model.ownedIdentity.isActive {
                                
                                UnableToActivateLicenseView(category: .ownedIdentityIsInactive, dismissAction: actions.userWantsToDismissLicenseActivationView)

                            } else if model.ownedIdentity.isKeycloakManaged {
                                
                                UnableToActivateLicenseView(category: .ownedIdentityIsKeycloakManaged, dismissAction: actions.userWantsToDismissLicenseActivationView)
                                
                            } else if !apiKeyServerIsCompatibleWithOwnedIdentityServer {
                                
                                UnableToActivateLicenseView(category: .serverAndAPIKeyIncompatibleWithOwnServer, dismissAction: actions.userWantsToDismissLicenseActivationView)
                                
                            } else if apiKeyElementsFetchedFromServer.status.canBeActivated || ObvMessengerSettings.Subscription.allowAPIKeyActivationWithBadKeyStatus || ObvMessengerConstants.developmentMode {
                                
                                OlvidButton(style: .blue, title: Text("ACTIVATE_NEW_LICENSE"), systemIcon: .checkmarkSealFill, action: activateNewLicenseNow)
                                    .disabled(isAPIKeyActivationInProgress)
                                
                            }
                            
                        } else if queryingAPIKeyElementsFromServerDidFail {
                            
                            UnableToActivateLicenseView(category: .queryingAPIKeyElementsFromServerDidFail, dismissAction: actions.userWantsToDismissLicenseActivationView)
                            
                        } else {
                            
                            HStack {
                                Spacer()
                                ProgressView("Looking for the new license")
                                Spacer()
                            }
                            .padding(.vertical, 32)
                            .onAppear(perform: queryAPIKeyElementsFromServer)
                            
                        }

                        if showCancelButton {
                            
                            OlvidButton(style: .standard, title: Text("Cancel"), systemIcon: .xmarkCircleFill, action: actions.userWantsToDismissLicenseActivationView)
                            
                        }

                    }
                                        
                    SubscriptionStatusView(title: Text("CURRENT_LICENSE_STATUS"),
                                           apiKeyStatus: model.ownedIdentity.currentAPIKeyElements.status,
                                           apiKeyExpirationDate: model.ownedIdentity.currentAPIKeyElements.expirationDate,
                                           showSubscriptionPlansButton: false,
                                           userWantsToSeeSubscriptionPlans: {},
                                           showRefreshStatusButton: false,
                                           refreshStatusAction: {},
                                           apiPermissions: model.ownedIdentity.currentAPIKeyElements.permissions)
                    .padding(.top, 32)
                    
                    if isAPIKeyActivated {
                        OlvidButton(style: .blue, title: Text("Ok"), systemIcon: .checkmarkCircle, action: actions.userWantsToDismissLicenseActivationView)
                    }
                        
                }.padding(.horizontal)
                
            } // End of ScrollView
            
            if let shownHUDViewCategory {
                HUDView(category: shownHUDViewCategory)
            }
            
        }.onAppear(perform: queryAPIKeyElementsFromServer)

    }
    
}



fileprivate struct UnableToActivateLicenseView: View {
    
    enum Category {
        case ownedIdentityIsKeycloakManaged
        case serverAndAPIKeyIncompatibleWithOwnServer
        case queryingAPIKeyElementsFromServerDidFail
        case ownedIdentityIsInactive
    }
    
    let category: Category
    let dismissAction: () -> Void

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
                        .ownedIdentityIsInactive:
                    EmptyView()
                }
                OlvidButton(style: .standard, title: Text("Cancel"), systemIcon: .xmarkCircleFill, action: dismissAction)
            }
        }
    }
    
}



struct LicenseActivationView_Previews: PreviewProvider {
    
        
    fileprivate final class ModelForPreviews: LicenseActivationViewModelProtocol {
        
        final class OwnedIdentityModelForPreviews: LicenseActivationViewModelOwnedIdentityModelProtocol {
            let ownedCryptoId: ObvCryptoId
            let isKeycloakManaged: Bool
            let currentAPIKeyElements: ObvTypes.APIKeyElements
            let isActive: Bool
            init(ownedCryptoId: ObvCryptoId, isActive: Bool, isKeycloakManaged: Bool, currentAPIKeyElements: ObvTypes.APIKeyElements) {
                self.ownedCryptoId = ownedCryptoId
                self.isActive = isActive
                self.isKeycloakManaged = isKeycloakManaged
                self.currentAPIKeyElements = currentAPIKeyElements
            }
        }

        let ownedIdentity: OwnedIdentityModelForPreviews
        let serverAndAPIKey: ServerAndAPIKey
        init(ownedIdentity: OwnedIdentityModelForPreviews, serverAndAPIKey: ServerAndAPIKey) {
            self.ownedIdentity = ownedIdentity
            self.serverAndAPIKey = serverAndAPIKey
        }
    }
    
    private static let identityAsURL = URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!
    private static let ownedCryptoId = ObvURLIdentity(urlRepresentation: identityAsURL)!.cryptoId

    private static let apiKeyGoodServer = URL(string: "https://server.dev.olvid.io")!
    private static let apiKeyWrongServer = URL(string: "https://wrong.olvid.io")!
    private static let apiKey = UUID()
    
    fileprivate static let currentAPIKeyElements = ObvTypes.APIKeyElements(status: .freeTrial, permissions: [.canCall], expirationDate: Date(timeIntervalSinceNow: .init(days: 5)))
    
    fileprivate static let ownedIdentityModels: [ModelForPreviews.OwnedIdentityModelForPreviews] = [
        ModelForPreviews.OwnedIdentityModelForPreviews(
            ownedCryptoId: ownedCryptoId,
            isActive: true,
            isKeycloakManaged: false,
            currentAPIKeyElements: currentAPIKeyElements),
        ModelForPreviews.OwnedIdentityModelForPreviews(
            ownedCryptoId: ownedCryptoId,
            isActive: true,
            isKeycloakManaged: true,
            currentAPIKeyElements: currentAPIKeyElements),
        ModelForPreviews.OwnedIdentityModelForPreviews(
            ownedCryptoId: ownedCryptoId,
            isActive: false,
            isKeycloakManaged: false,
            currentAPIKeyElements: currentAPIKeyElements),
    ]
    
    fileprivate static let models: [ModelForPreviews] = [
        ModelForPreviews(
            ownedIdentity: ownedIdentityModels[0],
            serverAndAPIKey: .init(server: apiKeyGoodServer, apiKey: apiKey)),
        ModelForPreviews(
            ownedIdentity: ownedIdentityModels[1],
            serverAndAPIKey: .init(server: apiKeyGoodServer, apiKey: apiKey)),
        ModelForPreviews(
            ownedIdentity: ownedIdentityModels[0],
            serverAndAPIKey: .init(server: apiKeyWrongServer, apiKey: apiKey)),
        ModelForPreviews(
            ownedIdentity: ownedIdentityModels[2],
            serverAndAPIKey: .init(server: apiKeyGoodServer, apiKey: apiKey)),
    ]
    
    private struct Actions: LicenseActivationViewActionsDelegate {
        
        let simulateFailToQueryServerForAPIKeyElements: Bool
        
        @MainActor
        func userWantsToQueryServerForAPIKeyElements(ownedCryptoId: ObvTypes.ObvCryptoId, apiKey: UUID) async throws -> ObvTypes.APIKeyElements {
            await TaskUtils.suspendDuringTimeInterval(2)
            if simulateFailToQueryServerForAPIKeyElements {
                throw NSError(domain: "LicenseActivationViewActionsDelegate", code: 0)
            } else {
                return .init(status: .valid, permissions: [.multidevice, .canCall], expirationDate: .init(timeIntervalSinceNow: .init(days: 10)))
            }
        }
        
        func userWantsToDismissLicenseActivationView() {}
        
        func userWantsToRegisterAPIKey(ownedCryptoId: ObvTypes.ObvCryptoId, apiKey: UUID) async throws {
            await TaskUtils.suspendDuringTimeInterval(2)
        }
        
    }
    
    private static let actions: [Actions] = [
        Actions(simulateFailToQueryServerForAPIKeyElements: false),
        Actions(simulateFailToQueryServerForAPIKeyElements: true),
    ]
    
    static var previews: some View {
        
        Group {
            NavigationView {
                LicenseActivationView(
                    model: models[0],
                    actions: actions[0])
            }
            .previewDisplayName("Simulate successful fetch of API key elements")
            NavigationView {
                LicenseActivationView(
                    model: models[0],
                    actions: actions[1])
            }
            .previewDisplayName("Simulate failed fetch of API key elements")
            NavigationView {
                LicenseActivationView(
                    model: models[1],
                    actions: actions[0])
            }
            .previewDisplayName("Failure (keycloak managed)")
            NavigationView {
                LicenseActivationView(
                    model: models[2],
                    actions: actions[0])
            }
            .previewDisplayName("Failure (bad server URL)")
            NavigationView {
                LicenseActivationView(
                    model: models[3],
                    actions: actions[0])
            }
            .previewDisplayName("Failure (inactive owned identity)")
        }
    }
    
}
