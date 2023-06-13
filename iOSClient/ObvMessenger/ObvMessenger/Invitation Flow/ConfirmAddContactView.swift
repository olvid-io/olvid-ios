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
import ObvUI
import ObvUICoreData


struct ConfirmAddContactView: View {
    
    let ownedCryptoId: ObvCryptoId
    let mutualScanUrl: ObvMutualScanUrl
    let contactIdentity: PersistedObvContactIdentity? /// Only set if the contact is already known
    
    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .edgesIgnoringSafeArea(.all)
            VStack {
                ObvCardView {
                    VStack {
                        if let contact = self.contactIdentity {
                            HStack {
                                IdentityCardContentView(model: SingleContactIdentity(persistedContact: contact, observeChangesMadeToContact: false))
                                Spacer()
                            }
                            if contact.isOneToOne {
                                HStack {
                                    Text("\(contact.identityCoreDetails?.getDisplayNameWithStyle(.firstNameThenLastName) ?? contact.fullDisplayName) is already part of your trusted contacts 🙌. Do you still wish to proceed?")
                                        .allowsTightening(true)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .lineLimit(nil)
                                        .multilineTextAlignment(.leading)
                                        .font(.body)
                                        .padding(.bottom, 8)
                                    Spacer()
                                }
                            }
                        } else {
                            HStack {
                                IdentityCardContentView(model: SingleIdentity(mutualScanUrl: mutualScanUrl))
                                Spacer()
                            }
                            HStack {
                                Text("Do you wish to add \(mutualScanUrl.fullDisplayName) to your contacts?")
                                    .font(.body)
                                    .allowsTightening(true)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.leading)
                                    .font(.body)
                                    .padding(.bottom, 8)
                                Spacer()
                            }
                        }
                        OlvidButton(style: .blue, title: Text("ADD_TO_CONTACTS"), systemIcon: .personCropCircleBadgePlus, action: {
                            ObvMessengerInternalNotification.userWantsToStartTrustEstablishmentWithMutualScanProtocol(ownedCryptoId: ownedCryptoId, mutualScanUrl: mutualScanUrl)
                                .postOnDispatchQueue()
                            let deepLink = ObvDeepLink.latestDiscussions(ownedCryptoId: ownedCryptoId)
                            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                                .postOnDispatchQueue()
                        })
                    }
                }
                .padding()
                Spacer()
            }
        }
    }
    
}
