/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

@available(iOS 13, *)
struct LicenseActivationView: View {
    
    let ownedCryptoId: ObvCryptoId
    let serverAndAPIKey: ServerAndAPIKey
    let currentApiKeyStatus: APIKeyStatus
    let currentApiKeyExpirationDate: Date?
    let ownedIdentityIsKeycloakManaged: Bool
    
    let requestNewAvailableApiKeyElements: (UUID) -> Void
    let userRequestedNewAPIKeyActivation: (UUID) -> Void
    @ObservedObject var newAvailableApiKeyElements: APIKeyElements
    
    @State private var serverAndAPIKeyIncompatibleWithOwnServer = false
    
    let dismissAction: () -> Void
    
    @State private var isNewAPIActivationInProgress = false
    
    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .edgesIgnoringSafeArea(.all)
            ScrollView {
                if ownedIdentityIsKeycloakManaged {
                    UnableToActivateLicenseView(category: .ownedIdentityIsKeycloakManaged, dismissAction: dismissAction)
                } else if serverAndAPIKeyIncompatibleWithOwnServer {
                    UnableToActivateLicenseView(category: .serverAndAPIKeyIncompatibleWithOwnServer, dismissAction: dismissAction)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        if let newAvailableApiKeyStatus = self.newAvailableApiKeyElements.apiKeyStatus {
                            SubscriptionStatusView(title: Text("NEW_LICENSE_TO_ACTIVATE"),
                                                   apiKeyStatus: newAvailableApiKeyStatus,
                                                   apiKeyExpirationDate: newAvailableApiKeyElements.apiKeyExpirationDate,
                                                   showSubscriptionPlansButton: false,
                                                   subscriptionPlanAction: {},
                                                   showRefreshStatusButton: false,
                                                   refreshStatusAction: {})
                            if newAvailableApiKeyStatus.canBeActivated || ObvMessengerSettings.Subscription.allowAPIKeyActivationWithBadKeyStatus {
                                OlvidButton(style: .blue, title: Text("ACTIVATE_NEW_LICENSE"), systemIcon: .checkmarkSealFill) {
                                    isNewAPIActivationInProgress = true
                                    userRequestedNewAPIKeyActivation(serverAndAPIKey.apiKey)
                                    
                                }.disabled(isNewAPIActivationInProgress)
                            }
                            OlvidButton(style: .standard, title: Text("Cancel"), systemIcon: .xmarkCircleFill, action: dismissAction)
                        } else {
                            HStack {
                                Spacer()
                                if #available(iOS 14.0, *) {
                                    ProgressView("Looking for the new license")
                                } else {
                                    ObvActivityIndicator(isAnimating: .constant(true), style: .large)
                                }
                                Spacer()
                            }.padding(.top)
                        }
                        SubscriptionStatusView(title: Text("CURRENT_LICENSE_STATUS"),
                                               apiKeyStatus: currentApiKeyStatus,
                                               apiKeyExpirationDate: currentApiKeyExpirationDate,
                                               showSubscriptionPlansButton: false,
                                               subscriptionPlanAction: {},
                                               showRefreshStatusButton: false,
                                               refreshStatusAction: {})
                            .padding(.top, 40)
                        Spacer()
                    }
                    .padding()
                }
            }.disabled(isNewAPIActivationInProgress)
            if isNewAPIActivationInProgress {
                if !newAvailableApiKeyElements.activated {
                    HUDView(category: .progress)
                } else {
                    HUDView(category: .checkmark)
                        .onAppear(perform: {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                                        dismissAction()
                                    }})
                }
            }
        }
        .navigationBarTitle(Text("License activation"), displayMode: .inline)
        .onAppear(perform: {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(600)) {
                if ownedCryptoId.belongsTo(serverURL: serverAndAPIKey.server) {
                    requestNewAvailableApiKeyElements(serverAndAPIKey.apiKey)
                } else {
                    // The distribution server of the user (indicated in her identity) is incompatible with the server indicated in the licence
                    withAnimation { serverAndAPIKeyIncompatibleWithOwnServer = true }
                }
            }
        })
    }
}


@available(iOS 13, *)
fileprivate struct UnableToActivateLicenseView: View {
    
    enum Category {
        case ownedIdentityIsKeycloakManaged
        case serverAndAPIKeyIncompatibleWithOwnServer
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
                    }
                    Spacer()
                }
                HStack {
                    Text("PLEASE_CONTACT_ADMIN_FOR_MORE_DETAILS")
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .font(.body)
                    Spacer()
                }
                OlvidButton(style: .standard, title: Text("Cancel"), systemIcon: .xmarkCircleFill, action: dismissAction)
            }
        }
        .padding()
    }
    
}







@available(iOS 13, *)
struct LicenseActivationView_Previews: PreviewProvider {
    
    private static let identityAsURL = URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!
    private static let identity = ObvURLIdentity(urlRepresentation: identityAsURL)!
    
    private static let serverAndAPIKey = ServerAndAPIKey(server: URL(string: "https://olvid.io")!, apiKey: UUID())
    
    private static func returnNewAPIKeyStatusAndExpirationDate(completion: (APIKeyStatus, Date) -> Void) {
        completion(APIKeyStatus.valid, Date())
    }
    
    static var previews: some View {
        Group {
            NavigationView {
                LicenseActivationView(ownedCryptoId: identity.cryptoId,
                                      serverAndAPIKey: serverAndAPIKey,
                                      currentApiKeyStatus: APIKeyStatus.free,
                                      currentApiKeyExpirationDate: nil,
                                      ownedIdentityIsKeycloakManaged: false,
                                      requestNewAvailableApiKeyElements: {_ in },
                                      userRequestedNewAPIKeyActivation: {_ in },
                                      newAvailableApiKeyElements: APIKeyElements(),
                                      dismissAction: {})
            }
            NavigationView {
                LicenseActivationView(ownedCryptoId: identity.cryptoId,
                                      serverAndAPIKey: serverAndAPIKey,
                                      currentApiKeyStatus: APIKeyStatus.unknown,
                                      currentApiKeyExpirationDate: nil,
                                      ownedIdentityIsKeycloakManaged: false,
                                      requestNewAvailableApiKeyElements: {_ in },
                                      userRequestedNewAPIKeyActivation: {_ in },
                                      newAvailableApiKeyElements: APIKeyElements(apiKey: UUID(), apiKeyStatus: APIKeyStatus.valid, apiKeyExpirationDate: Date()),
                                      dismissAction: {})
            }
            NavigationView {
                LicenseActivationView(ownedCryptoId: identity.cryptoId,
                                      serverAndAPIKey: serverAndAPIKey,
                                      currentApiKeyStatus: APIKeyStatus.free,
                                      currentApiKeyExpirationDate: nil,
                                      ownedIdentityIsKeycloakManaged: false,
                                      requestNewAvailableApiKeyElements: {_ in },
                                      userRequestedNewAPIKeyActivation: {_ in },
                                      newAvailableApiKeyElements: APIKeyElements(),
                                      dismissAction: {})
            }
            .environment(\.colorScheme, .dark)
            NavigationView {
                LicenseActivationView(ownedCryptoId: identity.cryptoId,
                                      serverAndAPIKey: serverAndAPIKey,
                                      currentApiKeyStatus: APIKeyStatus.unknown,
                                      currentApiKeyExpirationDate: nil,
                                      ownedIdentityIsKeycloakManaged: false,
                                      requestNewAvailableApiKeyElements: {_ in },
                                      userRequestedNewAPIKeyActivation: {_ in },
                                      newAvailableApiKeyElements: APIKeyElements(apiKey: UUID(), apiKeyStatus: APIKeyStatus.valid, apiKeyExpirationDate: Date()),
                                      dismissAction: {})
            }
            .environment(\.colorScheme, .dark)
            NavigationView {
                LicenseActivationView(ownedCryptoId: identity.cryptoId,
                                      serverAndAPIKey: serverAndAPIKey,
                                      currentApiKeyStatus: APIKeyStatus.freeTrial,
                                      currentApiKeyExpirationDate: nil,
                                      ownedIdentityIsKeycloakManaged: false,
                                      requestNewAvailableApiKeyElements: {_ in },
                                      userRequestedNewAPIKeyActivation: {_ in },
                                      newAvailableApiKeyElements: APIKeyElements(apiKey: UUID(), apiKeyStatus: APIKeyStatus.valid, apiKeyExpirationDate: Date()),
                                      dismissAction: {})
            }
            .environment(\.colorScheme, .dark)
            NavigationView {
                LicenseActivationView(ownedCryptoId: identity.cryptoId,
                                      serverAndAPIKey: serverAndAPIKey,
                                      currentApiKeyStatus: APIKeyStatus.freeTrial,
                                      currentApiKeyExpirationDate: nil,
                                      ownedIdentityIsKeycloakManaged: true,
                                      requestNewAvailableApiKeyElements: {_ in },
                                      userRequestedNewAPIKeyActivation: {_ in },
                                      newAvailableApiKeyElements: APIKeyElements(apiKey: UUID(), apiKeyStatus: APIKeyStatus.valid, apiKeyExpirationDate: Date()),
                                      dismissAction: {})
            }
        }
    }
}
