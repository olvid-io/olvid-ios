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

@available(iOS 13, *)
struct OwnedIdentityDetailedInfosView: View {

    @ObservedObject var ownedIdentity: PersistedObvOwnedIdentity
    @State private var signedContactDetails: SignedUserDetails? = nil
    
    @Environment(\.presentationMode) var presentationMode

    private var titlePart1: String? {
        ownedIdentity.identityCoreDetails.firstName?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var titlePart2: String? {
        ownedIdentity.identityCoreDetails.lastName?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var circledTextView: Text? {
        let component = [titlePart1, titlePart2]
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
            .first
        if let char = component?.first {
            return Text(String(char))
        } else {
            return nil
        }
    }
    
    private var profilePicture: UIImage? {
        guard let url = ownedIdentity.photoURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    
    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
                
            VStack {
                                
                ObvCardView(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        
                        CircleAndTitlesView(
                            titlePart1: titlePart1,
                            titlePart2: titlePart2,
                            subtitle: ownedIdentity.identityCoreDetails.position,
                            subsubtitle: ownedIdentity.identityCoreDetails.company,
                            circleBackgroundColor: ownedIdentity.cryptoId.colors.background,
                            circleTextColor: ownedIdentity.cryptoId.colors.text,
                            circledTextView: circledTextView,
                            systemImage: .person,
                            profilePicture: .constant(profilePicture),
                            changed: .constant(false),
                            showGreenShield: ownedIdentity.isKeycloakManaged,
                            showRedShield: false,
                            editionMode: .none,
                            displayMode: .normal)
                            .padding()

                        OlvidButton(style: .blue, title: Text(CommonString.Word.Back), systemIcon: .arrowshapeTurnUpBackwardFill) {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .padding(.horizontal)
                        .padding(.bottom)

                        HStack { Spacer() }

                    }
                    
                }
                .padding(16)

                List {
                    Section {
                        ObvSimpleListItemView(
                            title: Text("FORM_FIRST_NAME"),
                            value: ownedIdentity.identityCoreDetails.firstName)
                        ObvSimpleListItemView(
                            title: Text("FORM_LAST_NAME"),
                            value: ownedIdentity.identityCoreDetails.lastName)
                        ObvSimpleListItemView(
                            title: Text("FORM_POSITION"),
                            value: ownedIdentity.identityCoreDetails.position)
                        ObvSimpleListItemView(
                            title: Text("FORM_COMPANY"),
                            value: ownedIdentity.identityCoreDetails.company)
                        ObvSimpleListItemView(
                            title: Text("Identity"),
                            value: ownedIdentity.cryptoId.getIdentity().hexString())
                        ObvSimpleListItemView(
                            title: Text("Active"),
                            value: ownedIdentity.isActive ? CommonString.Word.Yes : CommonString.Word.No)
                        ObvSimpleListItemView(
                            title: Text("CERTIFIED_BY_IDENTITY_PROVIDER"),
                            value: ownedIdentity.isKeycloakManaged ? CommonString.Word.Yes : CommonString.Word.No)
                    } header: {
                        Text("Details")
                    }
                    
                    Section {
                        ForEach(ObvCapability.allCases) { capability in
                            switch capability {
                            case .webrtcContinuousICE:
                                ObvSimpleListItemView(
                                    title: Text("CAPABILITY_WEBRTC_CONTINUOUS_ICE"),
                                    value: ownedIdentity.supportsCapability(capability) ? CommonString.Word.Yes : CommonString.Word.No)
                            case .oneToOneContacts:
                                ObvSimpleListItemView(
                                    title: Text("CAPABILITY_ONE_TO_ONE_CONTACTS"),
                                    value: ownedIdentity.supportsCapability(capability) ? CommonString.Word.Yes : CommonString.Word.No)
                            case .groupsV2:
                                ObvSimpleListItemView(
                                    title: Text("CAPABILITY_GROUPS_V2"),
                                    value: ownedIdentity.supportsCapability(capability) ? CommonString.Word.Yes : CommonString.Word.No)
                            }
                        }
                    } header: {
                        Text("CAPABILITIES")
                    }
                    
                    if ownedIdentity.isKeycloakManaged {
                        Section {
                            if let signedContactDetails = signedContactDetails {
                                ObvSimpleListItemView(
                                    title: Text("KEYCLOAK_ID"),
                                    value: signedContactDetails.id)
                                ObvSimpleListItemView(
                                    title: Text("SIGNED_DETAILS_DATE"),
                                    date: signedContactDetails.timestamp)
                            } else {
                                HStack {
                                    Spacer()
                                    ObvProgressView()
                                    Spacer()
                                }
                            }
                        } header: {
                            Text("DETAILS_SIGNED_BY_IDENTITY_PROVIDER")
                        }
                    }

                }
                
            }
            .padding(.top, 32)

        }

        .onAppear {
            guard ownedIdentity.isKeycloakManaged else { return }
            ObvMessengerInternalNotification.uiRequiresSignedOwnedDetails(
                ownedIdentityCryptoId: ownedIdentity.cryptoId, completion: { signedContactDetails in
                    DispatchQueue.main.async {
                        self.signedContactDetails = signedContactDetails
                    }
                })
                .postOnDispatchQueue()
        }
    }


}
