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

struct ConfirmAddingKeycloakContactView: View {
    
    let contactUserDetails: UserDetails
    let contactIdentity: PersistedObvContactIdentity? /// Only set if the contact is already known
    @Binding var addingKeycloakContactFailedAlertIsPresented: Bool
    let confirmAddingKeycloakContactViewAction: () -> Void
    let cancelAddingKeycloakContactViewAction: () -> Void

    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .edgesIgnoringSafeArea(.all)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let contact = self.contactIdentity {
                        ObvCardView {
                            HStack {
                                IdentityCardContentView(model: SingleContactIdentity(persistedContact: contact, observeChangesMadeToContact: false))
                                Spacer()
                            }
                        }
                        if contact.isOneToOne {
                            HStack {
                                Text("\(contact.identityCoreDetails?.getDisplayNameWithStyle(.firstNameThenLastName) ?? contact.fullDisplayName) is already part of your trusted contacts 🙌. Do you still wish to proceed?")
                                    .allowsTightening(true)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.leading)
                                    .font(.body)
                                Spacer()
                            }
                        }
                    } else {
                        ObvCardView {
                            HStack {
                                IdentityCardContentView(model: SingleIdentity(userDetails: contactUserDetails))
                                Spacer()
                            }
                        }
                        Text("Do you wish to add \(contactUserDetails.firstNameAndLastName) to your contacts?")
                            .font(.body)
                    }
                    OlvidButton(style: .standard, title: Text("Cancel"), action: cancelAddingKeycloakContactViewAction)
                    OlvidButton(style: .blue, title: Text("ADD_TO_CONTACTS"), systemIcon: .paperplaneFill, action: confirmAddingKeycloakContactViewAction)
                    Spacer()
                }
                .padding()
            }
        }
        .alert(isPresented: $addingKeycloakContactFailedAlertIsPresented) {
            Alert(title: Text("ADDING_KEYCLOAK_CONTACT_FAILED"), message: Text("PLEASE_TRY_AGAIN_LATER"), dismissButton: Alert.Button.default(Text("Ok")))
        }
        .navigationBarTitle(Text(CommonString.Word.Confirmation), displayMode: .inline)
    }
}
