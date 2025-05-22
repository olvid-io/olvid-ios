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
import CoreData
import ObvUI
import ObvUICoreData
import ObvDesignSystem
import ObvCircleAndTitlesView


final class APIKeyStatusAndExpiry: ObservableObject {
    
    let id = UUID()
    private let ownedIdentity: PersistedObvOwnedIdentity!
    @Published var apiKeyStatus: APIKeyStatus
    @Published var apiPermissions: APIPermissions
    @Published var apiKeyExpirationDate: Date?
    private var observationTokens = [NSObjectProtocol]()
    
    // For SwiftUI previews
    fileprivate init(ownedCryptoId: ObvCryptoId, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?) {
        self.ownedIdentity = nil
        self.apiKeyStatus = apiKeyStatus
        self.apiPermissions = apiPermissions
        self.apiKeyExpirationDate = apiKeyExpirationDate
    }
    
    init(ownedIdentity: PersistedObvOwnedIdentity) {
        assert(Thread.isMainThread)
        assert(ownedIdentity.managedObjectContext == ObvStack.shared.viewContext)
        self.ownedIdentity = ownedIdentity
        self.apiKeyStatus = ownedIdentity.apiKeyStatus
        self.apiPermissions = ownedIdentity.effectiveAPIPermissions
        self.apiKeyExpirationDate = ownedIdentity.apiKeyExpirationDate
        observeViewContextDidChange()
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func observeViewContextDidChange() {
        let NotificationName = Notification.Name.NSManagedObjectContextObjectsDidChange
        observationTokens.append(NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { [weak self] (notification) in
            guard Thread.isMainThread else { return }
            guard let context = notification.object as? NSManagedObjectContext else { assertionFailure(); return }
            guard context == ObvStack.shared.viewContext else { return }
            guard let ownedIdentity = self?.ownedIdentity else { assertionFailure(); return }
            self?.apiKeyStatus = ownedIdentity.apiKeyStatus
            self?.apiPermissions = ownedIdentity.effectiveAPIPermissions
            self?.apiKeyExpirationDate = ownedIdentity.apiKeyExpirationDate
        })
    }
    
}


// MARK: - SingleOwnedIdentityViewActionsDelegate

protocol SingleOwnedIdentityViewActionsDelegate: AnyObject, OwnedDevicesCardViewActionsDelegate, OwnedIdentityCardViewActionsDelegate, InactiveOwnedIdentityViewActionsDelegate {
    func userWantsToEditOwnedIdentity(ownedCryptoId: ObvCryptoId) async
    func userWantsToSeeSubscriptionPlans() async
    func userWantsToRefreshSubscriptionStatus() async
}


// MARK: - SingleOwnedIdentityView

struct SingleOwnedIdentityView: View {
    
    @ObservedObject var ownedIdentity: PersistedObvOwnedIdentity
    @ObservedObject var apiKeyStatusAndExpiry: APIKeyStatusAndExpiry
    let actions: SingleOwnedIdentityViewActionsDelegate?

    private var apiKeyStatus: APIKeyStatus { apiKeyStatusAndExpiry.apiKeyStatus }
    private var apiKeyExpirationDate: Date? { apiKeyStatusAndExpiry.apiKeyExpirationDate }
    private var apiPermissions: APIPermissions { apiKeyStatusAndExpiry.apiPermissions }

    private var showSubscriptionPlansButton: Bool {
        !ownedIdentity.isKeycloakManaged
    }
        
    private var circleAndTitlesViewModel: CircleAndTitlesView.Model {
        .init(content: ownedIdentity.circleAndTitlesViewModelContent,
              colors: ownedIdentity.initialCircleViewModelColors,
              displayMode: .header,
              editionMode: .none)
    }
    
    private func userWantsToEditOwnedIdentity() {
        Task { await actions?.userWantsToEditOwnedIdentity(ownedCryptoId: ownedIdentity.cryptoId) }
    }
    
    private func userWantsToSeeSubscriptionPlans() {
        Task { await actions?.userWantsToSeeSubscriptionPlans() }
    }
    
    private func userWantsToRefreshSubscriptionStatus() {
        Task { await actions?.userWantsToRefreshSubscriptionStatus() }
    }
    
    
    
    var body: some View {
        ZStack {

            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack {
                    
                    CircleAndTitlesView(model: circleAndTitlesViewModel)
                        .padding(.top, 16)
                    
                    OwnedIdentityCardView(ownedIdentity: ownedIdentity, actions: actions)
                        .padding(.top, 40)
                    
                    if !ownedIdentity.isActive {
                        InactiveOwnedIdentityView(ownedCryptoId: ownedIdentity.cryptoId, actions: actions)
                            .padding(.top, 20)
                    } else {
                        OwnedDevicesCardView(model: .init(ownedCryptoId: ownedIdentity.cryptoId, numberOfOwnedDevices: ownedIdentity.sortedDevices.count), actions: actions)
                            .padding(.top, 40)
                    }
                                        
                    SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                           apiKeyStatus: apiKeyStatus,
                                           apiKeyExpirationDate: apiKeyExpirationDate,
                                           showSubscriptionPlansButton: showSubscriptionPlansButton,
                                           userWantsToSeeSubscriptionPlans: userWantsToSeeSubscriptionPlans,
                                           showRefreshStatusButton: true,
                                           refreshStatusAction: userWantsToRefreshSubscriptionStatus,
                                           apiPermissions: apiPermissions)
                    .padding(.top, 40)
                    
                    Spacer()
                    
                }.padding(.horizontal, 16)
            }
            
        }
    }
}
    


// MARK: - InactiveOwnedIdentityView

protocol InactiveOwnedIdentityViewActionsDelegate {
    func userWantsToReactivateThisDevice(ownedCryptoId: ObvCryptoId) async
}

fileprivate struct InactiveOwnedIdentityView: View {
    
    let ownedCryptoId: ObvCryptoId
    let actions: InactiveOwnedIdentityViewActionsDelegate?
    
    @State private var reactivationRequested = false

    private func userWantsToReactivateThisDevice() {
        guard !reactivationRequested else { return }
        reactivationRequested = true
        Task {
            await actions?.userWantsToReactivateThisDevice(ownedCryptoId: ownedCryptoId)
            reactivationRequested = false
        }
    }
        
    var body: some View {
        ObvCardView {
            VStack(alignment: .leading) {
                Text("INACTIVE_PROFILE_EXPLANATION_ON_MY_PROFILE_VIEW")
                    .font(.body)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                OlvidButton(style: .blue,
                            title: Text("REACTIVATE_PROFILE_BUTTON_TITLE"),
                            systemIcon: .checkmarkCircleFill,
                            action: userWantsToReactivateThisDevice)
                .disabled(reactivationRequested)
                .padding(.top, 8)
            }
        }
    }
    
}



// MARK: - OwnedIdentityCardViewActionsDelegate

protocol OwnedIdentityCardViewActionsDelegate {
    func userWantsToEditOwnedIdentity(ownedCryptoId: ObvCryptoId) async
}


// MARK: - OwnedIdentityCardView

fileprivate struct OwnedIdentityCardView: View {

    @ObservedObject var ownedIdentity: PersistedObvOwnedIdentity
    let actions: OwnedIdentityCardViewActionsDelegate?

    private func editOwnedIdentityAction() {
        let ownedCryptoId = ownedIdentity.cryptoId
        Task { await actions?.userWantsToEditOwnedIdentity(ownedCryptoId: ownedCryptoId) }
    }
    
    private var circleAndTitlesViewModel: CircleAndTitlesView.Model {
        .init(content: ownedIdentity.circleAndTitlesViewModelContent,
              colors: ownedIdentity.initialCircleViewModelColors,
              displayMode: .normal,
              editionMode: .none)
    }
    
    var body: some View {
        ObvCardView {
            VStack(alignment: .leading) {
                CircleAndTitlesView(model: circleAndTitlesViewModel)
                OlvidButton(style: .blue,
                            title: Text("EDIT_MY_ID"),
                            systemIcon: .squareAndPencil,
                            action: editOwnedIdentityAction)
                    .padding(.top, 16)
            }
        }
    }
}




//struct SingleOwnedIdentityView_Previews: PreviewProvider {
//
//    private static let singleIdentities = [
//        SingleIdentity(firstName: "Steve",
//                       lastName: "Jobs",
//                       position: "CEO",
//                       company: "Apple",
//                       isKeycloakManaged: false,
//                       showGreenShield: false,
//                       showRedShield: false,
//                       identityColors: nil,
//                       photoURL: nil),
//    ]
//
//    private static let identityAsURL = URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!
//    private static let testOwnedCryptoId = ObvURLIdentity(urlRepresentation: identityAsURL)!.cryptoId
//
//    private static let testApiKeyStatusAndExpiry = APIKeyStatusAndExpiry(ownedCryptoId: testOwnedCryptoId,
//                                                          apiKeyStatus: .free,
//                                                          apiKeyExpirationDate: Date())
//
//    static var previews: some View {
//        Group {
//            ForEach(singleIdentities) {
//                SingleOwnedIdentityView(singleIdentity: $0,
//                                        apiKeyStatusAndExpiry: testApiKeyStatusAndExpiry,
//                                        dismissAction: {},
//                                        editOwnedIdentityAction: {},
//                                        subscriptionPlanAction: {},
//                                        refreshStatusAction: {})
//                    .environment(\.colorScheme, .dark)
//            }
//            ForEach(singleIdentities) {
//                SingleOwnedIdentityView(singleIdentity: $0,
//                                        apiKeyStatusAndExpiry: testApiKeyStatusAndExpiry,
//                                        dismissAction: {},
//                                        editOwnedIdentityAction: {},
//                                        subscriptionPlanAction: {},
//                                        refreshStatusAction: {})
//                    .environment(\.colorScheme, .light)
//            }
//        }
//    }
//}


// MARK: - OwnedDevicesCardViewActionsDelegate

protocol OwnedDevicesCardViewActionsDelegate {
    
    func userWantsToNavigateToListOfContactDevicesView(ownedCryptoId: ObvCryptoId) async
    func userWantsToAddNewDevice(ownedCryptoId: ObvCryptoId) async
    
}


// MARK: - OwnedDevicesCardView

struct OwnedDevicesCardView: View {

    struct Model {
        let ownedCryptoId: ObvCryptoId
        let numberOfOwnedDevices: Int
    }
    
    let model: Model
    let actions: OwnedDevicesCardViewActionsDelegate?
    @State private var selected = false

    private func userWantsToNavigateToListOfContactDevicesView() {
        Task { await actions?.userWantsToNavigateToListOfContactDevicesView(ownedCryptoId: model.ownedCryptoId) }
    }
    
    private func userWantsToAddNewDevice() {
        Task { await actions?.userWantsToAddNewDevice(ownedCryptoId: model.ownedCryptoId) }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("MY_DEVICES")
                .font(.headline)
                .foregroundColor(Color(AppTheme.shared.colorScheme.label))
            ObvCardView {
                VStack {
                    
                    HStack(alignment: .firstTextBaseline) {
                        
                        Label {
                            Text(String.localizedStringWithFormat(NSLocalizedString("YOU_HAVE_N_DEVICES", comment: ""), model.numberOfOwnedDevices))
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.system(.headline, design: .rounded))
                                .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                        } icon: {
                            Image(systemIcon: .laptopcomputerAndIphone)
                                .foregroundColor(Color(.systemBlue))
                                .font(.system(size: 22))
                                .frame(width: 40)

                        }
                        
                        Spacer()
                        
                        ObvChevron(selected: selected)
                        
                    }
                    .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
                    .onTapGesture {
                        withAnimation {
                            selected = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                                userWantsToNavigateToListOfContactDevicesView()
                            }
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                            withAnimation {
                                selected = false
                            }
                        }
                    }
                    
                    Divider()
                        .padding(.leading, 48)
                        .padding(.bottom, 4)
                    
                    HStack(alignment: .firstTextBaseline) {
                        Label {
                            Text("ADD_A_NEW_DEVICE")
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.system(.headline, design: .rounded))
                                .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                        } icon: {
                            Image(systemIcon: .plusCircle)
                                .foregroundColor(Color(.systemBlue))
                                .font(.system(size: 22))
                                .frame(width: 40)
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
                    .onTapGesture {
                        userWantsToAddNewDevice()
                    }

                }
                
            }
            
        }
    }
    
}






// MARK: - Previews

struct OwnedDevicesCardView_Previews: PreviewProvider {
    
    private static let ownedCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)

    static private let model = OwnedDevicesCardView.Model(
        ownedCryptoId: ownedCryptoId,
        numberOfOwnedDevices: 1)
    
    static var previews: some View {
        OwnedDevicesCardView(model: model, actions: nil)
    }
    
}
