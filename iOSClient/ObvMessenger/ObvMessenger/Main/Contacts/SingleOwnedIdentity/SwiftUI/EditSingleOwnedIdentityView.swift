/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

@available(iOS 13, *)
struct EditSingleOwnedIdentityView: View {

    enum EditionType {
        case edition, creation
    }

    let editionType: EditionType
    @ObservedObject var singleIdentity: SingleIdentity
    @State private var isPublishActionSheetShown = false
    let userConfirmedPublishAction: () -> Void
    /// Used to prevent small screen settings when the keyboard appears on a large screen
    @State private var largeScreenUsedOnce = false
    @State private var newIdentityPublishingInProgress = false
    @State private var disableAllButtons = false
    @State private var hudViewCategory: HUDView.Category? = nil
    
    private func useSmallScreenMode(for geometry: GeometryProxy) -> Bool {
        if largeScreenUsedOnce { return false }
        let res = max(geometry.size.height, geometry.size.width) < 510
        if !res {
            DispatchQueue.main.async {
                largeScreenUsedOnce = true
            }
        }
        return res
    }
    
    private func typicalPadding(for geometry: GeometryProxy) -> CGFloat {
        useSmallScreenMode(for: geometry) ? 8 : 16
    }

    private var canPublish: Bool {
        switch editionType {
        case .creation:
            if singleIdentity.isKeycloakManaged {
                guard let keycloakDetails = singleIdentity.keycloakDetails else { assertionFailure(); return false }
                return keycloakDetails.keycloakUserDetailsAndStuff.identity == nil || keycloakDetails.keycloakServerRevocationsAndStuff.revocationAllowed
            } else {
                return (singleIdentity.hasChanged && (!singleIdentity.firstName.isEmpty || !singleIdentity.lastName.isEmpty))
            }
        case .edition:
            return (singleIdentity.isKeycloakManaged && singleIdentity.hasChanged) ||
                (singleIdentity.hasChanged && (!singleIdentity.firstName.isEmpty || !singleIdentity.lastName.isEmpty))
        }
        
    }
    
    private var disablePublishMyIdButton: Bool {
        !canPublish || isPublishActionSheetShown || newIdentityPublishingInProgress
    }

    private func olvidButtonText() -> Text {
        switch editionType {
        case .edition: return Text("PUBLISH_MY_ID")
        case .creation: return Text("CREATE_MY_ID")
        }
    }
    
    private func userWantsToUnbindFromKeycloak() {
        guard let ownCryptoId = singleIdentity.ownCryptoId else { assertionFailure(); return }
        withAnimation {
            hudViewCategory = .progress
            disableAllButtons = true
        }
        ObvMessengerInternalNotification.userWantsToUnbindOwnedIdentityFromKeycloak(ownedCryptoId: ownCryptoId) { success in
            withAnimation {
                disableAllButtons = false
                hudViewCategory = success ? .checkmark : nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                withAnimation { hudViewCategory = nil }
            }
        }.postOnDispatchQueue()
    }

    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 0) {
                    ObvCardView(padding: 0) {
                        VStack(spacing: 0) {
                            HStack {
                                IdentityCardContentView(model: singleIdentity)
                                    .padding(.horizontal, typicalPadding(for: geometry))
                                    .padding(.top, typicalPadding(for: geometry))
                                    .padding(.bottom, typicalPadding(for: geometry))
                                Spacer()
                            }
                            OlvidButton(style: .blue,
                                        title: olvidButtonText(),
                                        systemIcon: .paperplaneFill,
                                        action: {
                                            switch editionType {
                                            case .edition:
                                                isPublishActionSheetShown = true
                                            case .creation:
                                                newIdentityPublishingInProgress = true
                                                userConfirmedPublishAction()
                                            }
                                        })
                                .actionSheet(isPresented: $isPublishActionSheetShown) {
                                    ActionSheet(title: Text("PUBLISH_NEW_ID"),
                                                message: Text("ARE_YOU_SURE_PUBLISH_NEW_OWNED_ID"),
                                                buttons: [
                                                    ActionSheet.Button.default(Text("PUBLISH_MY_ID"), action: { newIdentityPublishingInProgress = true; userConfirmedPublishAction() }),
                                                    ActionSheet.Button.cancel(),
                                                ])
                                }
                                .padding(.all, 10)
                                .disabled(disableAllButtons || disablePublishMyIdButton)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.all, typicalPadding(for: geometry))
                    if singleIdentity.isKeycloakManaged {
                        Text("EXPLANATION_MANAGED_IDENTITY")
                            .font(.caption)
                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                            .padding(.horizontal)
                        if editionType == .creation && singleIdentity.keycloakDetails?.keycloakUserDetailsAndStuff.signedUserDetails.identity != nil {
                            ObvCardView {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("WARNING")
                                        Spacer()
                                    }
                                    Text(singleIdentity.keycloakDetails?.keycloakServerRevocationsAndStuff.revocationAllowed == true ? "TEXT_EXPLANATION_WARNING_IDENTITY_CREATION_KEYCLOAK_REVOCATION_NEEDED" : "TEXT_EXPLANATION_WARNING_IDENTITY_CREATION_KEYCLOAK_REVOCATION_IMPOSSIBLE")
                                        .font(.footnote)
                                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                                }
                            }
                            .padding()
                        } else if editionType == .edition {
                            RemoveIdentityProviderView(userWantsToUnbindFromKeycloak: userWantsToUnbindFromKeycloak,
                                                       disableButton: disableAllButtons)
                        }
                    } else {
                        Form {
                            Section(header: Text("Enter your personal details")) {
                                TextField(LocalizedStringKey("FORM_FIRST_NAME"), text: $singleIdentity.firstName.map({ $0.trimmingWhitespacesAndNewlines() }))
                                    .disableAutocorrection(true)
                                TextField(LocalizedStringKey("FORM_LAST_NAME"), text: $singleIdentity.lastName.map({ $0.trimmingWhitespacesAndNewlines() }))
                                    .disableAutocorrection(true)
                                TextField(LocalizedStringKey("FORM_POSITION"), text: $singleIdentity.position.map({ $0.trimmingWhitespacesAndNewlines() }))
                                TextField(LocalizedStringKey("FORM_COMPANY"), text: $singleIdentity.company.map({ $0.trimmingWhitespacesAndNewlines() }))
                            }.disabled(isPublishActionSheetShown)
                            if let serverAndAPIKeyToShow = singleIdentity.serverAndAPIKeyToShow {
                                Section(header: Text("IDENTITY_SETTINGS")) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("SERVER_URL")
                                        Text(serverAndAPIKeyToShow.server.absoluteString)
                                            .font(.footnote)
                                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("LICENSE_ACTIVATION_CODE")
                                        Text(serverAndAPIKeyToShow.apiKey.uuidString)
                                            .font(.footnote)
                                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                                    }
                                }
                            }
                        }
                    }
                    Spacer()
                }
            }
            if let hudViewCategory = self.hudViewCategory {
                HUDView(category: hudViewCategory)
            }
        }
    }

}


@available(iOS 13, *)
struct RemoveIdentityProviderView: View {
    
    let userWantsToUnbindFromKeycloak: () -> Void
    let disableButton: Bool
    
    @State private var showAlertConfirmationKeycloakUnbind = false
    
    var body: some View {
        OlvidButton(style: .standard,
                    title: Text("REMOVE_IDENTITY_PROVIDER"),
                    systemIcon: .personCropCircleBadgeCheckmark,
                    action: { showAlertConfirmationKeycloakUnbind = true })
            .disabled(disableButton)
            .padding()
            .alert(isPresented: $showAlertConfirmationKeycloakUnbind) {
                Alert(title: Text("REMOVE_IDENTITY_PROVIDER"),
                      message: Text("DIALOG_MESSAGE_UNBIND_FROM_KEYCLOAK"),
                      primaryButton: Alert.Button.default(Text("Ok"), action: userWantsToUnbindFromKeycloak),
                      secondaryButton: Alert.Button.cancel())
            }
    }
}



@available(iOS 13, *)
struct OptionalView<Content: View>: View {

    let predicate: () -> Bool
    let content: () -> Content

    var body: some View {
        if predicate() {
            content()
        } else {
            EmptyView()
        }
    }
}


@available(iOS 13, *)
struct EditSingleOwnedIdentityView_Previews: PreviewProvider {
    
    static let testData = [
        SingleIdentity(firstName: nil,
                       lastName: nil,
                       position: nil,
                       company: nil,
                       isKeycloakManaged: false,
                       showGreenShield: false,
                       showRedShield: false,
                       identityColors: nil,
                       photoURL: nil),
        SingleIdentity(firstName: "Steve",
                       lastName: "Jobs",
                       position: nil,
                       company: nil,
                       isKeycloakManaged: false,
                       showGreenShield: false,
                       showRedShield: false,
                       identityColors: nil,
                       photoURL: nil),
        SingleIdentity(serverAndAPIKeyToShow: ServerAndAPIKey(server: URL(string: "https://mock.server.olvid.io")!,
                                                              apiKey: UUID("123e4567-e89b-12d3-a456-426614174000")!),
                       identityDetails: nil),
    ]
    
    static var previews: some View {
        Group {
            ForEach(testData) {
                EditSingleOwnedIdentityView(editionType: .edition,
                                            singleIdentity: $0,
                                            userConfirmedPublishAction: {})
                EditSingleOwnedIdentityView(editionType: .creation,
                                            singleIdentity: $0,
                                            userConfirmedPublishAction: {})
            }
            ForEach(testData) {
                EditSingleOwnedIdentityView(editionType: .edition,
                                            singleIdentity: $0,
                                            userConfirmedPublishAction: {})
                    .environment(\.colorScheme, .dark)
                EditSingleOwnedIdentityView(editionType: .creation,
                                            singleIdentity: $0,
                                            userConfirmedPublishAction: {})
                    .environment(\.colorScheme, .dark)
            }
            EditSingleOwnedIdentityView(editionType: .edition,
                                        singleIdentity: testData[1],
                                        userConfirmedPublishAction: {})
                .environment(\.colorScheme, .dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone XS"))
            EditSingleOwnedIdentityView(editionType: .creation,
                                        singleIdentity: testData[1],
                                        userConfirmedPublishAction: {})
                .environment(\.colorScheme, .dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone XS"))
        }
    }
}
