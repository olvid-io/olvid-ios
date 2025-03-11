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
import ObvUI
import ObvUICoreData
import ObvDesignSystem


struct ContactDetailedInfosView: View {

    @ObservedObject var contact: PersistedObvContactIdentity
    let userWantsToSyncOneToOneStatusOfContact: () -> Void
    @State private var signedContactDetails: SignedObvKeycloakUserDetails? = nil
    
    @Environment(\.presentationMode) var presentationMode

    private var titlePart1: String? {
        guard contact.customDisplayName == nil else { return nil }
        return contact.identityCoreDetails?.firstName?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var titlePart2: String? {
        return (contact.customDisplayName ?? contact.identityCoreDetails?.lastName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var circledText: String? {
        let component = [titlePart1, titlePart2]
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
            .first
        if let char = component?.first {
            return String(char)
        } else {
            return nil
        }
    }
    
    private var profilePicture: UIImage? {
        guard let url = contact.customPhotoURL ?? contact.photoURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    
    private var textViewModel: TextView.Model {
        .init(titlePart1: titlePart1,
              titlePart2: titlePart2,
              subtitle: contact.identityCoreDetails?.position,
              subsubtitle: contact.identityCoreDetails?.company)
    }
    
    private var profilePictureViewModelContent: ProfilePictureView.Model.Content {
        .init(text: circledText,
              icon: .person,
              profilePicture: profilePicture,
              showGreenShield: contact.isCertifiedByOwnKeycloak,
              showRedShield: !contact.isActive)
    }
    
    private var circleAndTitlesViewModelContent: CircleAndTitlesView.Model.Content {
        .init(textViewModel: textViewModel,
              profilePictureViewModelContent: profilePictureViewModelContent)
    }
    
    private var initialCircleViewModelColors: InitialCircleView.Model.Colors {
        .init(background: contact.cryptoId.colors.background,
              foreground: contact.cryptoId.colors.text)
    }
    
    private var circleAndTitlesViewModel: CircleAndTitlesView.Model {
        .init(content: circleAndTitlesViewModelContent,
              colors: initialCircleViewModelColors,
              displayMode: .normal,
              editionMode: .none)
    }
    
    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
                
            VStack {
                                
                ObvCardView(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {

                        CircleAndTitlesView(model: circleAndTitlesViewModel)
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
                            value: contact.identityCoreDetails?.firstName)
                        ObvSimpleListItemView(
                            title: Text("FORM_LAST_NAME"),
                            value: contact.identityCoreDetails?.lastName)
                        ObvSimpleListItemView(
                            title: Text("FORM_POSITION"),
                            value: contact.identityCoreDetails?.position)
                        ObvSimpleListItemView(
                            title: Text("FORM_COMPANY"),
                            value: contact.identityCoreDetails?.company)
                        ObvSimpleListItemView(
                            title: Text("FORM_NICKNAME"),
                            value: contact.customDisplayName)
                        ObvSimpleListItemView(
                            title: Text("Identity"),
                            value: contact.cryptoId.getIdentity().hexString())
                        ObvSimpleListItemView(
                            title: Text("Active"),
                            value: contact.isActive ? CommonString.Word.Yes : CommonString.Word.No)
                        ObvSimpleListItemView(
                            title: Text("CERTIFIED_BY_IDENTITY_PROVIDER"),
                            value: contact.isCertifiedByOwnKeycloak ? CommonString.Word.Yes : CommonString.Word.No)
                        ObvSimpleListItemView(
                            title: Text("WAS_RECENTLY_ONLINE"),
                            value: contact.wasRecentlyOnline ? CommonString.Word.Yes : CommonString.Word.No)
                    } header: {
                        Text("Details")
                    }
                    
                    Section {
                        ForEach(ObvCapability.allCases) { capability in
                            switch capability {
                            case .webrtcContinuousICE:
                                ObvSimpleListItemView(
                                    title: Text("CAPABILITY_WEBRTC_CONTINUOUS_ICE"),
                                    value: contact.supportsCapability(capability) ? CommonString.Word.Yes : CommonString.Word.No)
                            case .oneToOneContacts:
                                ObvSimpleListItemView(
                                    title: Text("CAPABILITY_ONE_TO_ONE_CONTACTS"),
                                    value: contact.supportsCapability(capability) ? CommonString.Word.Yes : CommonString.Word.No,
                                    buttonConfig: ("SYNC", "SYNC_REQUEST_SENT", userWantsToSyncOneToOneStatusOfContact))
                            case .groupsV2:
                                ObvSimpleListItemView(
                                    title: Text("CAPABILITY_GROUPS_V2"),
                                    value: contact.supportsCapability(capability) ? CommonString.Word.Yes : CommonString.Word.No)
                            }
                        }
                    } header: {
                        Text("CAPABILITIES")
                    }
                    
                    Section {
                        if contact.devices.isEmpty {
                            Text("None")
                        } else {
                            ForEach(contact.sortedDevices.indices, id: \.self) { index in
                                SingleContactDeviceView(index: index, device: contact.sortedDevices[index])
                            }
                        }
                    } header: {
                        Text("Devices")
                    }

                    if contact.isCertifiedByOwnKeycloak {
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
                                    ProgressView()
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
            guard let ownedIdentityCryptoId = contact.ownedIdentity?.cryptoId else { return }
            if contact.isCertifiedByOwnKeycloak {
                ObvMessengerInternalNotification.uiRequiresSignedContactDetails(
                    ownedIdentityCryptoId: ownedIdentityCryptoId,
                    contactCryptoId: contact.cryptoId,
                    completion: { signedContactDetails in
                        DispatchQueue.main.async {
                            self.signedContactDetails = signedContactDetails
                        }
                    })
                    .postOnDispatchQueue()
            }
        }
    }


}



fileprivate struct SingleContactDeviceView: View {
    
    let index: Int
    @ObservedObject var device: PersistedObvContactDevice
    
    private var secureChannelStatus: LocalizedStringKey {
        switch device.secureChannelStatus {
        case .creationInProgress, .none:
            return "SECURE_CHANNEL_CREATION_IN_PROGRESS"
        case .created:
            return "SECURE_CHANNEL_CREATED"
        }
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("DEVICE \(index+1)")
                    .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                    .font(.headline)
                    .padding(.bottom, 4.0)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    .font(.body)
                Text(secureChannelStatus)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    .font(.body)
                    .padding(.bottom, 4.0)
                Text(device.identifier.hexString())
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    .font(.body)
                HStack { Spacer() }
            }
        }
    }
    
}
