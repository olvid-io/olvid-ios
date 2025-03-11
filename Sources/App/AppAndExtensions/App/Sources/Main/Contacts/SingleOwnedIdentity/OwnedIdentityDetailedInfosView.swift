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


protocol OwnedIdentityDetailedInfosViewDelegate: AnyObject {
    func userWantsToDismissOwnedIdentityDetailedInfosView() async
    func getKeycloakAPIKey(ownedCryptoId: ObvCryptoId) async throws -> UUID?
    func getIsTransferRestricted(ownedCryptoId: ObvCryptoId) async throws -> Bool
}


struct OwnedIdentityDetailedInfosView: View {

    @ObservedObject var ownedIdentity: PersistedObvOwnedIdentity
    weak var delegate: OwnedIdentityDetailedInfosViewDelegate?
    @State private var signedContactDetails: SignedObvKeycloakUserDetails? = nil
    @State private var ownedIdentityKeycloakApiKey: UUID?
    @State private var isTransferRestricted: Bool?
    
    private var titlePart1: String? {
        ownedIdentity.identityCoreDetails.firstName?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var titlePart2: String? {
        ownedIdentity.identityCoreDetails.lastName?.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard let url = ownedIdentity.photoURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    
    private var textViewModel: TextView.Model {
        .init(titlePart1: titlePart1,
              titlePart2: titlePart2,
              subtitle: ownedIdentity.identityCoreDetails.position,
              subsubtitle: ownedIdentity.identityCoreDetails.company)
    }
    
    private var profilePictureViewModelContent: ProfilePictureView.Model.Content {
        .init(text: circledText,
              icon: .person,
              profilePicture: profilePicture,
              showGreenShield: ownedIdentity.isKeycloakManaged,
              showRedShield: false)
    }
    
    private var circleAndTitlesViewModelContent: CircleAndTitlesView.Model.Content {
        .init(textViewModel: textViewModel,
              profilePictureViewModelContent: profilePictureViewModelContent)
    }
    
    private var initialCircleViewModelColors: InitialCircleView.Model.Colors {
        .init(background: ownedIdentity.cryptoId.colors.background,
              foreground: ownedIdentity.cryptoId.colors.text)
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
                            Task { await delegate?.userWantsToDismissOwnedIdentityDetailedInfosView() }
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
                    
                    if !ownedIdentity.devices.isEmpty {
                        Section {
                            ForEach(ownedIdentity.sortedDevices) { ownedDevice in
                                OwnedDeviceInfosView(ownedDevice: ownedDevice)
                            }
                        } header: {
                            Text("Devices")
                        }
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
                                    ProgressView()
                                    Spacer()
                                }
                            }
                            ObvSimpleListItemView(
                                title: Text("API Key"),
                                value: ownedIdentityKeycloakApiKey?.uuidString ?? CommonString.Word.None)
                        } header: {
                            Text("DETAILS_SIGNED_BY_IDENTITY_PROVIDER")
                        }
                        
                        
                        Section("OTHER_INFORMATIONS_ABOUT_MANAGED_PROFILE") {
                            if let isTransferRestricted {
                                ObvSimpleListItemView(
                                    title: Text("IS_TRANSFER_RESTRICTED"),
                                    value: isTransferRestricted ? CommonString.Word.Yes : CommonString.Word.No)
                            } else {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Spacer()
                                }
                            }

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
            let ownedCryptoId = ownedIdentity.ownedCryptoId
            Task {
                self.ownedIdentityKeycloakApiKey = try? await self.delegate?.getKeycloakAPIKey(ownedCryptoId: ownedCryptoId)
                self.isTransferRestricted = try? await self.delegate?.getIsTransferRestricted(ownedCryptoId: ownedCryptoId)
            }
        }
    }


}


private struct OwnedDeviceInfosView: View {
    
    let ownedDevice: PersistedObvOwnedDevice
    
    private var title: String {
        return ownedDevice.name
    }
    
    var body: some View {
        ObvSimpleListItemView(
            title: Text(title),
            value: ownedDevice.identifier.hexString())
    
    }
    
}
