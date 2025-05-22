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
import ObvEngine
import ObvUI
import ObvUICoreData
import ObvDesignSystem
import ObvKeycloakManager
import ObvCircleAndTitlesView


struct BindingShowIdentityView: View {
    
    let ownedCryptoId: ObvCryptoId
    let keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff
    let revocationAllowed: Bool
    let obvKeycloakState: ObvKeycloakState
    let dismissAction: () -> Void

    private var profilePicture: UIImage? {
        assert(Thread.isMainThread)
        guard let persistedOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else { return nil }
        guard let photoURL = persistedOwnedIdentity.photoURL else { return nil }
        return UIImage(contentsOfFile: photoURL.path)
    }
    
    private var ownedCryptoIdBelongsToServerAdvertizedByKeycloak: Bool {
        ownedCryptoId.belongsTo(serverURL: keycloakUserDetailsAndStuff.server)
    }
    
    private func userWantsToBindOwnedIdentityToKeycloak(completionHandler: @escaping (Error?) -> Void) {
        ObvMessengerInternalNotification.userWantsToBindOwnedIdentityToKeycloak(ownedCryptoId: ownedCryptoId,
                                                                                obvKeycloakState: obvKeycloakState,
                                                                                keycloakUserId: keycloakUserDetailsAndStuff.id,
                                                                                completionHandler: completionHandler)
            .postOnDispatchQueue()
    }
    
    var body: some View {
        BindingShowIdentityInnerView(firstName: keycloakUserDetailsAndStuff.firstName,
                                     lastName: keycloakUserDetailsAndStuff.lastName,
                                     position: keycloakUserDetailsAndStuff.position,
                                     company: keycloakUserDetailsAndStuff.company,
                                     circleBackgroundColor: ownedCryptoId.colors.background,
                                     circleTextColor: ownedCryptoId.colors.text,
                                     descriptiveCharacter: keycloakUserDetailsAndStuff.descriptiveCharacter,
                                     profilePicture: profilePicture,
                                     previousIdentityExistsOnKeycloak: keycloakUserDetailsAndStuff.identity != nil && keycloakUserDetailsAndStuff.identity! != ownedCryptoId.getIdentity(),
                                     revocationAllowed: revocationAllowed,
                                     ownedCryptoIdBelongsToServerAdvertizedByKeycloak: ownedCryptoIdBelongsToServerAdvertizedByKeycloak,
                                     userWantsToBindOwnedIdentityToKeycloak: userWantsToBindOwnedIdentityToKeycloak,
                                     dismissAction: dismissAction)
    }
}



struct BindingShowIdentityInnerView: View {
    
    let firstName: String?
    let lastName: String?
    let position: String?
    let company: String?
    let circleBackgroundColor: UIColor?
    let circleTextColor: UIColor?
    let descriptiveCharacter: String?
    let profilePicture: UIImage?
    let previousIdentityExistsOnKeycloak: Bool
    let revocationAllowed: Bool
    let ownedCryptoIdBelongsToServerAdvertizedByKeycloak: Bool
    let userWantsToBindOwnedIdentityToKeycloak: (@escaping (Error?) -> Void) -> Void
    let dismissAction: () -> Void
    
    private enum BindError {
        case defaultError
        case revokedIdentity
    }

    @State private var hudCategory: HUDView.Category?
    @State private var isErrorAlertPresented = false
    @State private var isButtonDisabled = true
    @State private var bindError: BindError = .defaultError

    private var circledText: String? {
        if let descriptiveCharacter = self.descriptiveCharacter {
            return descriptiveCharacter
        } else {
            return nil
        }
    }

    private func enableButtonIfAppropriate() {
        let canEnabledButton = ownedCryptoIdBelongsToServerAdvertizedByKeycloak && (!previousIdentityExistsOnKeycloak || revocationAllowed)
        isButtonDisabled = !canEnabledButton
    }
    
    private func userTappedOnSwitchToManagedIdButton() {
        isButtonDisabled = true
        withAnimation {
            hudCategory = .progress
        }
        userWantsToBindOwnedIdentityToKeycloak { error in
            Task { await bindingPerformed(error: error) }
        }
    }
    
    @MainActor
    private func bindingPerformed(error: Error?) async {
        if let error {
            if let error = error as? KeycloakManager.UploadOwnedIdentityError {
                switch error {
                case .ownedIdentityWasRevoked:
                    bindError = .revokedIdentity
                default:
                    bindError = .defaultError
                }
            } else {
                bindError = .defaultError
            }
            withAnimation {
                hudCategory = nil
                isErrorAlertPresented = true
                isButtonDisabled = false
            }
        } else {
            withAnimation {
                hudCategory = .checkmark
            }
            try? await Task.sleep(seconds: 1)
            dismissAction()
        }
    }
    
    private var textViewModel: TextView.Model {
        .init(titlePart1: firstName,
              titlePart2: lastName,
              subtitle: position,
              subsubtitle: company)
    }
    
    private var profilePictureViewModelContent: ProfilePictureView.Model.Content {
        .init(text: descriptiveCharacter,
              icon: .person,
              profilePicture: profilePicture,
              showGreenShield: true,
              showRedShield: false)
    }
    
    private var circleAndTitlesViewModelContent: CircleAndTitlesView.Model.Content {
        .init(textViewModel: textViewModel,
              profilePictureViewModelContent: profilePictureViewModelContent)
    }
    
    private var initialCircleViewModelColors: InitialCircleView.Model.Colors {
        .init(background: circleBackgroundColor,
              foreground: circleTextColor)
    }
    
    private var circleAndTitlesViewModel: CircleAndTitlesView.Model {
        .init(content: circleAndTitlesViewModelContent,
              colors: initialCircleViewModelColors,
              displayMode: .normal,
              editionMode: .none)
    }
    
    private var alertTitle: LocalizedStringKey {
        switch bindError {
        case .defaultError:
            return "COULD_NOT_SWITCH_TO_MANAGED_ID"
        case .revokedIdentity:
            return "DIALOG_OWNED_IDENTITY_WAS_REVOKED_BY_KEYCLOAK_TITLE"
        }
    }

    private var alertMessage: LocalizedStringKey {
        switch bindError {
        case .defaultError:
            return "PLEASE_TRY_AGAIN_LATER"
        case .revokedIdentity:
            return "DIALOG_OWNED_IDENTITY_WAS_REVOKED_BY_KEYCLOAK_MESSAGE"
        }
    }

    
    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .edgesIgnoringSafeArea(.all)
            ScrollView {
                VStack(spacing: 16) {
                    ObvCardView {
                        VStack(spacing: 16) {
                            HStack {
                                CircleAndTitlesView(model: circleAndTitlesViewModel)
                                Spacer()
                            }
                            OlvidButton(
                                style: .blue,
                                title: Text("BUTTON_LABEL_MANAGE_KEYCLOAK"),
                                systemIcon: .serverRack,
                                action: userTappedOnSwitchToManagedIdButton)
                            .disabled(isButtonDisabled)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("EXPLANATION_KEYCLOAK_BIND")
                        .font(.caption)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    if !ownedCryptoIdBelongsToServerAdvertizedByKeycloak {
                        OwnedCryptoIdBelongsToAnotherServerExplanationView()
                    } else if previousIdentityExistsOnKeycloak {
                        PreviousIdentityExistsOnKeycloakExplanationView(revocationAllowed: revocationAllowed)
                    }
                }
                .padding()
                Spacer()
            }
            if let hudCategory = self.hudCategory {
                HUDView(category: hudCategory)
            }
        }
        .onAppear(perform: enableButtonIfAppropriate)
        .alert(
            alertTitle,
            isPresented: $isErrorAlertPresented,
            actions: {
                Button(role: .none, action: {}) {
                    Text("Ok")
                }
            },
            message: {
                Text(alertMessage)
            })
    }
    
}



struct PreviousIdentityExistsOnKeycloakExplanationView: View {
    
    let revocationAllowed: Bool
    
    var body: some View {
        ObvCardView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("WARNING")
                    Spacer()
                }
                Text(revocationAllowed ? "TEXT_EXPLANATION_WARNING_IDENTITY_CREATION_KEYCLOAK_REVOCATION_NEEDED" : "TEXT_EXPLANATION_WARNING_IDENTITY_CREATION_KEYCLOAK_REVOCATION_IMPOSSIBLE")
                    .font(.footnote)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
            }
        }
    }
}



fileprivate struct OwnedCryptoIdBelongsToAnotherServerExplanationView: View {
    var body: some View {
        ObvCardView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Oups")
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("EXPLANATION_KEYCLOAK_UPDATE_BAD_SERVER")
                    Text("PLEASE_CONTACT_ADMIN_FOR_MORE_DETAILS")
                }
                .font(.footnote)
                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
            }
        }
    }
}












struct BindingShowIdentityView_Previews: PreviewProvider {
    
    static var previews: some View {
        Group {
            BindingShowIdentityInnerView(
                firstName: "Alice",
                lastName: "Work",
                position: "Software Developer",
                company: "Apple",
                circleBackgroundColor: #colorLiteral(red: 1, green: 0.4932718873, blue: 0.4739984274, alpha: 1),
                circleTextColor: #colorLiteral(red: 0.1829138398, green: 0.3950355947, blue: 0.9591949582, alpha: 1),
                descriptiveCharacter: "A",
                profilePicture: nil,
                previousIdentityExistsOnKeycloak: false,
                revocationAllowed: false,
                ownedCryptoIdBelongsToServerAdvertizedByKeycloak: true,
                userWantsToBindOwnedIdentityToKeycloak: {_ in },
                dismissAction: {})
            BindingShowIdentityInnerView(
                firstName: "Alice",
                lastName: "Work",
                position: "Software Developer",
                company: "Apple",
                circleBackgroundColor: #colorLiteral(red: 1, green: 0.4932718873, blue: 0.4739984274, alpha: 1),
                circleTextColor: #colorLiteral(red: 0.1829138398, green: 0.3950355947, blue: 0.9591949582, alpha: 1),
                descriptiveCharacter: "A",
                profilePicture: nil,
                previousIdentityExistsOnKeycloak: false,
                revocationAllowed: false,
                ownedCryptoIdBelongsToServerAdvertizedByKeycloak: true,
                userWantsToBindOwnedIdentityToKeycloak: {_ in },
                dismissAction: {})
                .environment(\.colorScheme, .dark)
            BindingShowIdentityInnerView(
                firstName: "Alice",
                lastName: "Work",
                position: "Software Developer",
                company: "Apple",
                circleBackgroundColor: #colorLiteral(red: 1, green: 0.4932718873, blue: 0.4739984274, alpha: 1),
                circleTextColor: #colorLiteral(red: 0.1829138398, green: 0.3950355947, blue: 0.9591949582, alpha: 1),
                descriptiveCharacter: "A",
                profilePicture: nil,
                previousIdentityExistsOnKeycloak: true,
                revocationAllowed: true,
                ownedCryptoIdBelongsToServerAdvertizedByKeycloak: true,
                userWantsToBindOwnedIdentityToKeycloak: {_ in },
                dismissAction: {})
                .environment(\.colorScheme, .dark)
            BindingShowIdentityInnerView(
                firstName: "Alice",
                lastName: "Work",
                position: "Software Developer",
                company: "Apple",
                circleBackgroundColor: #colorLiteral(red: 1, green: 0.4932718873, blue: 0.4739984274, alpha: 1),
                circleTextColor: #colorLiteral(red: 0.1829138398, green: 0.3950355947, blue: 0.9591949582, alpha: 1),
                descriptiveCharacter: "A",
                profilePicture: nil,
                previousIdentityExistsOnKeycloak: true,
                revocationAllowed: false,
                ownedCryptoIdBelongsToServerAdvertizedByKeycloak: true,
                userWantsToBindOwnedIdentityToKeycloak: {_ in },
                dismissAction: {})
                .environment(\.colorScheme, .dark)
            BindingShowIdentityInnerView(
                firstName: "Alice",
                lastName: "Work",
                position: "Software Developer",
                company: "Apple",
                circleBackgroundColor: #colorLiteral(red: 1, green: 0.4932718873, blue: 0.4739984274, alpha: 1),
                circleTextColor: #colorLiteral(red: 0.1829138398, green: 0.3950355947, blue: 0.9591949582, alpha: 1),
                descriptiveCharacter: "A",
                profilePicture: nil,
                previousIdentityExistsOnKeycloak: false,
                revocationAllowed: false,
                ownedCryptoIdBelongsToServerAdvertizedByKeycloak: false,
                userWantsToBindOwnedIdentityToKeycloak: {_ in },
                dismissAction: {})
        }
    }
}
