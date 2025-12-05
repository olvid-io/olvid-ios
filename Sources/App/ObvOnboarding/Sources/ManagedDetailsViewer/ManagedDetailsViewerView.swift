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
import ObvSystemIcon
import ObvKeycloakManager
import ObvDesignSystem


protocol ManagedDetailsViewerViewActionsProtocol: AnyObject {
    func userWantsToCreateProfileWithDetailsFromIdentityProvider(keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff)) async
    func userWantsToBindExistingProfileWithKeycloak(existingOwnedCryptoIdToBind: ObvCryptoId, keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff)) async
}


struct ManagedDetailsViewerView: View {

    let actions: ManagedDetailsViewerViewActionsProtocol
    let model: Model
    
    struct Model {
        let keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff
        let keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff
        let existingOwnedCryptoIdToBind: ObvCryptoId? // Non-nil iff we are binding a profile that already exists on this device.
    }

    private var coreDetails: ObvIdentityCoreDetails? {
        try? model.keycloakUserDetailsAndStuff.signedUserDetails.userDetails.getCoreDetails()
    }
    
    private var anOldIdentityAlreadyExistsOnTheIdentityProvider: Bool {
        model.keycloakUserDetailsAndStuff.signedUserDetails.identity != nil
    }
    
    private var identityProviderAllowsRevocation: Bool {
        model.keycloakServerRevocationsAndStuff.revocationAllowed
    }
    
    private var modelForInnerView: ManagedDetailsViewerInnerView.Model {
        .init(coreDetails: self.coreDetails,
              anOldIdentityAlreadyExistsOnTheIdentityProvider: self.anOldIdentityAlreadyExistsOnTheIdentityProvider,
              identityProviderAllowsRevocation: self.identityProviderAllowsRevocation,
              existingOwnedCryptoIdToBind: self.model.existingOwnedCryptoIdToBind)
    }
    
    var body: some View {
        ManagedDetailsViewerInnerView(
            model: modelForInnerView,
            actions: self)
    }
        
}


extension ManagedDetailsViewerView: ManagedDetailsViewerInnerViewActionsProtocol {
    
    func userWantsToCreateProfileWithDetailsFromIdentityProvider() async {
        await self.actions.userWantsToCreateProfileWithDetailsFromIdentityProvider(keycloakDetails: (keycloakUserDetailsAndStuff: model.keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: model.keycloakServerRevocationsAndStuff))
    }
    
    func userWantsToBindExistingProfileWithKeycloak(existingOwnedCryptoIdToBind: ObvTypes.ObvCryptoId) async {
        await actions.userWantsToBindExistingProfileWithKeycloak(existingOwnedCryptoIdToBind: existingOwnedCryptoIdToBind,
                                                                 keycloakDetails: (keycloakUserDetailsAndStuff: model.keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: model.keycloakServerRevocationsAndStuff))
    }

}


// MARK: - Internal view: struct ManagedDetailsViewerInnerView

protocol ManagedDetailsViewerInnerViewActionsProtocol {
    func userWantsToCreateProfileWithDetailsFromIdentityProvider() async
    func userWantsToBindExistingProfileWithKeycloak(existingOwnedCryptoIdToBind: ObvCryptoId) async
}

/// The sole purpose of this inner view is to make it possible to have previews (since the model of the `ManagedDetailsViewerInnerView` cannot be easily instantiated)
private struct ManagedDetailsViewerInnerView: View {
    
    let model: Model
    let actions: ManagedDetailsViewerInnerViewActionsProtocol
    
    struct Model {
        let coreDetails: ObvIdentityCoreDetails?
        let anOldIdentityAlreadyExistsOnTheIdentityProvider: Bool
        let identityProviderAllowsRevocation: Bool
        let existingOwnedCryptoIdToBind: ObvCryptoId?
    }
    
    @State private var isProfileCreationOrBindingInProgress = false

    private func userWantsToBindExistingProfileWithKeycloak(existingOwnedCryptoIdToBind: ObvCryptoId) {
        withAnimation { isProfileCreationOrBindingInProgress = true }
        Task {
            await actions.userWantsToBindExistingProfileWithKeycloak(existingOwnedCryptoIdToBind: existingOwnedCryptoIdToBind)
            withAnimation { isProfileCreationOrBindingInProgress = false }
        }
    }

    private var indentityProviderWouldRejectProfileCreation: Bool {
        model.anOldIdentityAlreadyExistsOnTheIdentityProvider && !model.identityProviderAllowsRevocation
    }

    private var buttonIsDisabled: Bool {
        isProfileCreationOrBindingInProgress || indentityProviderWouldRejectProfileCreation
    }

    fileprivate func createProfile() {
        withAnimation { isProfileCreationOrBindingInProgress = true }
        Task {
            await actions.userWantsToCreateProfileWithDetailsFromIdentityProvider()
            withAnimation { isProfileCreationOrBindingInProgress = false }
        }
    }

    var body: some View {
        VStack {
            
            ObvHeaderView(title: "ONBOARDING_NAME_CHOOSER_TITLE".localizedInThisBundle,
                          subtitle: "ONBOARDING_MANAGED_IDENTITY_SUBTITLE".localizedInThisBundle)
                .padding(.bottom, 40)
            
            if let coreDetails = model.coreDetails {
                
                ScrollView {
                    
                    VStack {
                        
                        if let firstName = coreDetails.firstName, !firstName.isEmpty {
                            InternalCellView(title: "FORM_FIRST_NAME", verbatim: firstName)
                        }
                        
                        if let lastName = coreDetails.lastName, !lastName.isEmpty {
                            InternalCellView(title: "FORM_LAST_NAME", verbatim: lastName)
                        }
                        
                        if let position = coreDetails.position, !position.isEmpty {
                            InternalCellView(title: "FORM_POSITION", verbatim: position)
                        }
                        
                        if let company = coreDetails.company, !company.isEmpty {
                            InternalCellView(title: "FORM_COMPANY", verbatim: company)
                        }
                        
                        if model.anOldIdentityAlreadyExistsOnTheIdentityProvider {
                            WarningPreviousIDExistsOnIdentityProviderView(model: .init(identityProviderAllowsRevocation: model.identityProviderAllowsRevocation))
                            .padding(.top)
                        }
                        
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemIcon: .infoCircle)
                                .foregroundStyle(.yellow)
                            Text("EXPLANATION_KEYCLOAK_BIND")
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }.padding(.top)
                        
                    }
                    
                }
                
                // Display a button allowing to start the creation of the new profile, or to bind the existing profile.
                
                if let existingOwnedCryptoIdToBind = model.existingOwnedCryptoIdToBind {
                    
                    SwitchToManagedProfileButton(existingOwnedCryptoIdToBind: existingOwnedCryptoIdToBind) {
                        userWantsToBindExistingProfileWithKeycloak(existingOwnedCryptoIdToBind: existingOwnedCryptoIdToBind)
                    }
                    .disabled(buttonIsDisabled)
                    .padding(.bottom)

                } else {
                    
                    CreateProfileButton("ONBOARDING_NAME_CHOOSER_BUTTON_TITLE", action: createProfile)
                        .disabled(buttonIsDisabled)
                        .padding(.bottom)
                    
                }
                
                
            } else {

                BadInformationsReturnedByIdentityProviderView()
                
            }
            
        }
        .padding(.horizontal)
    }

}


// MARK: - Internal view: SwitchToManagedProfileButton

private struct SwitchToManagedProfileButton: View {
    
    let existingOwnedCryptoIdToBind: ObvCryptoId
    let action: () -> Void
    
    @Environment(\.isEnabled) var isEnabled

    @ViewBuilder
    private var buttonLabel: some View {
        Label {
            Text("SWITCH_TO_A_MANAGED_PROFILE")
        } icon: {
            Image(systemIcon: .serverRack)
        }
        .padding(.vertical, 8)
    }
        
    var body: some View {

        if #available(iOS 26, *) {
            Button(action: action) {
                HStack {
                    if !isEnabled { ProgressView().tint(.white) }
                    buttonLabel
                }
            }
                .buttonStyle(.glassProminent)
                .buttonSizing(.flexible)
        } else {
            Button(action: action) {
                HStack {
                    Spacer(minLength: 0)
                    if !isEnabled { ProgressView() }
                    buttonLabel
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        
    }
}


// MARK: Warning panel when an Olvid ID already exists on the identity provider

private struct WarningPreviousIDExistsOnIdentityProviderView: View {
    
    let model: Model
    
    struct Model {
        let identityProviderAllowsRevocation: Bool
    }
    
    private var warningPanelConfig: (icon: SystemIcon, iconColor: Color, body: LocalizedStringKey) {
        if model.identityProviderAllowsRevocation {
            return (SystemIcon.exclamationmarkCircle, Color(UIColor.systemYellow), "TEXT_EXPLANATION_WARNING_IDENTITY_CREATION_KEYCLOAK_REVOCATION_NEEDED")
        } else {
            return (SystemIcon.xmarkCircle, Color(UIColor.systemRed), "TEXT_EXPLANATION_WARNING_IDENTITY_CREATION_KEYCLOAK_REVOCATION_IMPOSSIBLE")
        }
    }

    var body: some View {
        Label(
            title: {
                Text(warningPanelConfig.body)
                    .foregroundStyle(.secondary)
            },
            icon: {
                Image(systemIcon: warningPanelConfig.icon)
                    .foregroundStyle(warningPanelConfig.iconColor)
            }
        )
    }
    
}


// MARK: InternalCellView

private struct InternalCellView: View {
    
    let title: LocalizedStringKey
    let verbatim: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            TextField(title, text: .constant(verbatim))
                .disabled(true)
                .padding()
                .background(Color.textFieldBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack { Spacer() }
        }
    }
    
}


// MARK: View used when bad informations were returned by the identity provider

private struct BadInformationsReturnedByIdentityProviderView: View {
    
    var body: some View {
        ScrollView {
            HStack {
                Label {
                    Text("ONBOARDING_BAD_INFORMATIONS_RETURNED_BY_IDENTITY_PROVIDER")
                        .font(.body)
                } icon: {
                    Image(systemIcon: .xmarkCircle)
                        .foregroundStyle(Color(UIColor.systemRed))
                }
                
                Spacer(minLength: 0)
            }
        }
    }
    
}


// MARK: - Internal view: CreateProfileButton

private struct CreateProfileButton: View {
    
    private let key: LocalizedStringKey
    private let action: () -> Void
    @Environment(\.isEnabled) var isEnabled
    
    init(_ key: LocalizedStringKey, action: @escaping () -> Void) {
        self.key = key
        self.action = action
    }
        
    var body: some View {
        if #available(iOS 26, *) {
            Button(action: action) {
                Text(key)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .buttonSizing(.flexible)
        } else {
            Button(action: action) {
                Text(key)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            }
            .background(Color.blue01)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? 1.0 : 0.6)
        }
    }
    
}



// MARK: - Previews

#if DEBUG

private final class ActionsForPreviews: ManagedDetailsViewerInnerViewActionsProtocol {
    
    
    func userWantsToCreateProfileWithDetailsFromIdentityProvider() async {
        print("User tapped the userWantsToCreateProfileWithDetailsFromIdentityProvider button")
        try? await Task.sleep(seconds: 2)
    }
    
    func userWantsToBindExistingProfileWithKeycloak(existingOwnedCryptoIdToBind: ObvTypes.ObvCryptoId) async {
        print("User tapped the userWantsToBindExistingProfileWithKeycloak button")
        try? await Task.sleep(seconds: 2)
    }

}

@MainActor
private let actionsForPreviews = ActionsForPreviews()

private let coreDetailsForPreviews = try? ObvIdentityCoreDetails(
    firstName: "Alice",
    lastName: "Cooper",
    company: nil,
    position: nil,
    signedUserDetails: nil)

let cryptoIdForPreviews = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)

private let modelForPreviews = ManagedDetailsViewerInnerView.Model(
    coreDetails: coreDetailsForPreviews,
    anOldIdentityAlreadyExistsOnTheIdentityProvider: false,
    identityProviderAllowsRevocation: false,
    existingOwnedCryptoIdToBind: cryptoIdForPreviews)

#Preview {
    
    ManagedDetailsViewerInnerView(model: modelForPreviews, actions: actionsForPreviews)
    
}

#endif // DEBUG
