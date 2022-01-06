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
import CoreData


@available(iOS 13, *)
final class APIKeyStatusAndExpiry: ObservableObject {
    
    let id = UUID()
    private let ownedIdentity: PersistedObvOwnedIdentity!
    @Published var apiKeyStatus: APIKeyStatus
    @Published var apiKeyExpirationDate: Date?
    private var observationTokens = [NSObjectProtocol]()
    
    // For SwiftUI previews
    fileprivate init(ownedCryptoId: ObvCryptoId, apiKeyStatus: APIKeyStatus, apiKeyExpirationDate: Date?) {
        self.ownedIdentity = nil
        self.apiKeyStatus = apiKeyStatus
        self.apiKeyExpirationDate = apiKeyExpirationDate
    }
    
    init(ownedIdentity: PersistedObvOwnedIdentity) {
        assert(Thread.isMainThread)
        assert(ownedIdentity.managedObjectContext == ObvStack.shared.viewContext)
        self.ownedIdentity = ownedIdentity
        self.apiKeyStatus = ownedIdentity.apiKeyStatus
        self.apiKeyExpirationDate = ownedIdentity.apiKeyExpirationDate
        observeViewContextDidChange()
    }
    
    deinit {
        for token in observationTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    private func observeViewContextDidChange() {
        let NotificationName = Notification.Name.NSManagedObjectContextObjectsDidChange
        observationTokens.append(NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { [weak self] (notification) in
            guard Thread.isMainThread else { return }
            guard let context = notification.object as? NSManagedObjectContext else { assertionFailure(); return }
            guard context == ObvStack.shared.viewContext else { return }
            guard let ownedIdentity = self?.ownedIdentity else { assertionFailure(); return }
            self?.apiKeyStatus = ownedIdentity.apiKeyStatus
            self?.apiKeyExpirationDate = ownedIdentity.apiKeyExpirationDate
        })
    }
    
}


@available(iOS 13, *)
struct SingleOwnedIdentityView: View {
    
    @ObservedObject var singleIdentity: SingleIdentity
    @ObservedObject var apiKeyStatusAndExpiry: APIKeyStatusAndExpiry
    let dismissAction: () -> Void
    let presentSettingsAction: () -> Void
    let editOwnedIdentityAction: () -> Void
    let subscriptionPlanAction: () -> Void
    let refreshStatusAction: () -> Void
    
    @State private var showSubscriptionPlans: Bool = false
    
    private var apiKeyStatus: APIKeyStatus { apiKeyStatusAndExpiry.apiKeyStatus }
    private var apiKeyExpirationDate: Date? { apiKeyStatusAndExpiry.apiKeyExpirationDate }

    private var showSubscriptionPlansButton: Bool {
        !singleIdentity.isKeycloakManaged
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                
                Color(AppTheme.shared.colorScheme.systemBackground)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack {
                        OwnedIdentityHeaderView(singleIdentity: singleIdentity)
                            .padding(.top, 16)
                        OwnedIdentityCardView(singleIdentity: singleIdentity,
                                              editOwnedIdentityAction: editOwnedIdentityAction)
                            .padding(.top, 40)
                        SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                               apiKeyStatus: apiKeyStatus,
                                               apiKeyExpirationDate: apiKeyExpirationDate,
                                               showSubscriptionPlansButton: showSubscriptionPlansButton,
                                               subscriptionPlanAction: subscriptionPlanAction,
                                               showRefreshStatusButton: true,
                                               refreshStatusAction: refreshStatusAction)
                            .padding(.top, 40)
                        Spacer()
                    }.padding(.horizontal, 16)
                }
            }
            .navigationBarTitle(Text("My Id"), displayMode: .inline)
            .navigationBarItems(leading: Button(action: dismissAction,
                                                label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(Font.system(size: 24, weight: .semibold, design: .default))
                                                        .foregroundColor(Color(AppTheme.shared.colorScheme.tertiaryLabel))
                                                }),
                                trailing: Button(action: presentSettingsAction,
                                                 label: {
                                                    Image(systemName: "gear")
                                                        .font(Font.system(size: 24, weight: .semibold, design: .default))
                                                        .foregroundColor(Color(AppTheme.shared.colorScheme.tertiaryLabel))
                                                 })
            )
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}
    



@available(iOS 13, *)
fileprivate struct OwnedIdentityCardView: View {

    @ObservedObject var singleIdentity: SingleIdentity
    let editOwnedIdentityAction: () -> Void
    
    var body: some View {
        ObvCardView {
            VStack(alignment: .leading) {
                IdentityCardContentView(model: singleIdentity)
                OlvidButton(style: .blue,
                            title: Text("EDIT_MY_ID"),
                            systemIcon: .squareAndPencil,
                            action: editOwnedIdentityAction)
                    .padding(.top, 16)
            }
        }
    }
}



@available(iOS 13, *)
struct SingleOwnedIdentityView_Previews: PreviewProvider {
    
    private static let singleIdentities = [
        SingleIdentity(firstName: "Steve",
                       lastName: "Jobs",
                       position: "CEO",
                       company: "Apple",
                       isKeycloakManaged: false,
                       showGreenShield: false,
                       showRedShield: false,
                       identityColors: nil,
                       photoURL: nil),
    ]
    
    private static let identityAsURL = URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!
    private static let testOwnedCryptoId = ObvURLIdentity(urlRepresentation: identityAsURL)!.cryptoId

    private static let testApiKeyStatusAndExpiry = APIKeyStatusAndExpiry(ownedCryptoId: testOwnedCryptoId,
                                                          apiKeyStatus: .free,
                                                          apiKeyExpirationDate: Date())
    
    static var previews: some View {
        Group {
            ForEach(singleIdentities) {
                SingleOwnedIdentityView(singleIdentity: $0,
                                        apiKeyStatusAndExpiry: testApiKeyStatusAndExpiry,
                                        dismissAction: {},
                                        presentSettingsAction: {},
                                        editOwnedIdentityAction: {},
                                        subscriptionPlanAction: {},
                                        refreshStatusAction: {})
                    .environment(\.colorScheme, .dark)
            }
            ForEach(singleIdentities) {
                SingleOwnedIdentityView(singleIdentity: $0,
                                        apiKeyStatusAndExpiry: testApiKeyStatusAndExpiry,
                                        dismissAction: {},
                                        presentSettingsAction: {},
                                        editOwnedIdentityAction: {},
                                        subscriptionPlanAction: {},
                                        refreshStatusAction: {})
                    .environment(\.colorScheme, .light)
            }
        }
    }
}
