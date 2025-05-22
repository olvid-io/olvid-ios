/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
}


struct ManagedDetailsViewerView: View, ManagedDetailsViewerInnerViewActionsProtocol {

    let actions: ManagedDetailsViewerViewActionsProtocol
    let model: Model
    
    struct Model {
        let keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff
        let keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff
    }

    private var coreDetails: ObvIdentityCoreDetails? {
        try? model.keycloakUserDetailsAndStuff.signedUserDetails.userDetails.getCoreDetails()
    }

    fileprivate func createProfileAction() async {
        await actions.userWantsToCreateProfileWithDetailsFromIdentityProvider(keycloakDetails: (model.keycloakUserDetailsAndStuff, model.keycloakServerRevocationsAndStuff))
    }
    
    private var anOldIdentityAlreadyExistsOnTheIdentityProvider: Bool {
        model.keycloakUserDetailsAndStuff.signedUserDetails.identity != nil
    }
    
    private var identityProviderAllowsRevocation: Bool {
        model.keycloakServerRevocationsAndStuff.revocationAllowed
    }
    
    var body: some View {
        ManagedDetailsViewerInnerView(
            actions: self,
            model: .init(coreDetails: coreDetails, 
                         anOldIdentityAlreadyExistsOnTheIdentityProvider: anOldIdentityAlreadyExistsOnTheIdentityProvider, 
                         identityProviderAllowsRevocation: identityProviderAllowsRevocation))
    }
    
}



// MARK: - ManagedDetailsViewerInnerView


private protocol ManagedDetailsViewerInnerViewActionsProtocol {
    func createProfileAction() async
}


private struct ManagedDetailsViewerInnerView: View {
    
    let actions: ManagedDetailsViewerInnerViewActionsProtocol
    let model: Model
    @State private var isProfileCreationInProgress = false
    
    struct Model {
        let coreDetails: ObvIdentityCoreDetails? // Expected to be non nil, unless the identity provider did a bad job
        let anOldIdentityAlreadyExistsOnTheIdentityProvider: Bool
        let identityProviderAllowsRevocation: Bool
    }
    
    @MainActor
    private func createProfile() async {
        isProfileCreationInProgress = true
        await actions.createProfileAction()
        isProfileCreationInProgress = false
    }
    
    
    private var warningPanelConfig: (icon: SystemIcon, iconColor: Color, body: LocalizedStringKey)? {
        guard model.anOldIdentityAlreadyExistsOnTheIdentityProvider else { return nil }
        if model.identityProviderAllowsRevocation {
            return (SystemIcon.exclamationmarkCircle, Color(UIColor.systemYellow), "TEXT_EXPLANATION_WARNING_IDENTITY_CREATION_KEYCLOAK_REVOCATION_NEEDED")
        } else {
            return (SystemIcon.xmarkCircle, Color(UIColor.systemRed), "TEXT_EXPLANATION_WARNING_IDENTITY_CREATION_KEYCLOAK_REVOCATION_IMPOSSIBLE")
        }
    }
    
    
    private var indentityProviderWouldRejectProfileCreation: Bool {
        model.anOldIdentityAlreadyExistsOnTheIdentityProvider && !model.identityProviderAllowsRevocation
    }
    
    
    private var createProfileButtonIsDisabled: Bool {
        isProfileCreationInProgress || indentityProviderWouldRejectProfileCreation
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
                        
                        if isProfileCreationInProgress {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .controlSize(.large)
                                Spacer()
                            }.padding(.top)
                        }
                        
                    }
                    
                }
                
                InternalButton("ONBOARDING_NAME_CHOOSER_BUTTON_TITLE", action: { Task { await createProfile() } })
                    .disabled(createProfileButtonIsDisabled)
                    .padding(.bottom)
                
            } else {

                BadInformationsReturnedByIdentityProviderView()
                
            }
            
        }
        .padding(.horizontal)
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


private struct InternalButton: View {
    
    private let key: LocalizedStringKey
    private let action: () -> Void
    @Environment(\.isEnabled) var isEnabled
    
    init(_ key: LocalizedStringKey, action: @escaping () -> Void) {
        self.key = key
        self.action = action
    }
        
    var body: some View {
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



// MARK: - Previews

struct ManagedDetailsViewerInnerView_Previews: PreviewProvider {
    
    private static let model = ManagedDetailsViewerInnerView.Model(
        coreDetails: try? .init(
            firstName: "Alice",
            lastName: nil,
            company: nil,
            position: nil,
            signedUserDetails: nil),
        anOldIdentityAlreadyExistsOnTheIdentityProvider: false,
        identityProviderAllowsRevocation: false)
    
    private struct ActionsForPreviews: ManagedDetailsViewerInnerViewActionsProtocol {
        func createProfileAction() async {}
    }
    
    private static let actions = ActionsForPreviews()
    
    static var previews: some View {
        ManagedDetailsViewerInnerView(actions: actions, model: model)
    }
    
}
