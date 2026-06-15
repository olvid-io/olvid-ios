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
import ObvDesignSystem
import ObvTypes

@MainActor
public protocol ObvOwnedDetailedInfosViewDataSource {
    func getAsyncSequenceOfObvOwnedDetailedInfosViewModel(_ view: ObvOwnedDetailedInfosView, ownedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvOwnedDetailedInfosView.Model>)
    func finishAsyncSequenceOfObvOwnedDetailedInfosViewModel(_ view: ObvOwnedDetailedInfosView, streamUUID: UUID)
}

@MainActor
protocol ObvOwnedDetailedInfosViewNavigation {
    func ownedDetailedInfosViewShouldBeDismissed(_ view: ObvOwnedDetailedInfosView)
}


public struct ObvOwnedDetailedInfosView: View {
    
    let ownedCryptoId: ObvCryptoId
    let dataSources: DataSources
    let navigation: any ObvOwnedDetailedInfosViewNavigation
    
    public struct Model: Sendable, Equatable {
        let avatarModel: ObvAvatarViewModel
        let identityCoreDetails: ObvIdentityCoreDetails
        let isActive: Bool
        let isKeycloakManaged: IsKeycloakManaged
        let capabilitites: Set<ObvCapability>
        let devices: [Device]
        
        public init(avatarModel: ObvAvatarViewModel,
                    identityCoreDetails: ObvIdentityCoreDetails,
                    isActive: Bool,
                    isKeycloakManaged: IsKeycloakManaged,
                    capabilitites: Set<ObvCapability>,
                    devices: [Device]) {
            self.avatarModel = avatarModel
            self.identityCoreDetails = identityCoreDetails
            self.isActive = isActive
            self.isKeycloakManaged = isKeycloakManaged
            self.capabilitites = capabilitites
            self.devices = devices
        }
        
        public enum IsKeycloakManaged: Sendable, Equatable {
            case no
            case yes(signedDetails: SignedObvKeycloakUserDetails?, ownedIdentityKeycloakApiKey: UUID?, isTransferRestricted: Bool?, supportsIdBasedAuth: Bool)
        }
        
        public struct Device: Identifiable, Sendable, Equatable {
            let identifier: Data
            let secureChannelStatus: SecureChannelStatus
            
            public init(identifier: Data, secureChannelStatus: SecureChannelStatus) {
                self.identifier = identifier
                self.secureChannelStatus = secureChannelStatus
            }

            public var id: Data { identifier }
            
            public enum SecureChannelStatus: Equatable, Sendable {
                case currentDevice
                case creationInProgress(preKeyAvailable: Bool)
                case created(preKeyAvailable: Bool)
                case unavailable
            }
        }

    }
    
    public struct DataSources {
        let dataSource: any ObvOwnedDetailedInfosViewDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        public init(dataSource: any ObvOwnedDetailedInfosViewDataSource, avatarViewDataSource: any ObvAvatarViewDataSource) {
            self.dataSource = dataSource
            self.avatarViewDataSource = avatarViewDataSource
        }
    }
    
    private enum ModelLoadingState {
        case loading
        case loaded(Model)
    }
    
    @State private var modelLoadingState: ModelLoadingState = .loading
    
    @State private var streamedModel: Model?
    
    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSources.dataSource.getAsyncSequenceOfObvOwnedDetailedInfosViewModel(self, ownedCryptoId: ownedCryptoId)
            defer { dataSources.dataSource.finishAsyncSequenceOfObvOwnedDetailedInfosViewModel(self, streamUUID: streamUUID) }
            for await receivedModel in stream {
                switch modelLoadingState {
                case .loading:
                    modelLoadingState = .loaded(receivedModel)
                case .loaded:
                    withAnimation { modelLoadingState = .loaded(receivedModel) }
                }
            }
        } catch {
            assertionFailure()
        }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {

                Color(UIColor.systemGroupedBackground)
                    .edgesIgnoringSafeArea(.all)

                switch modelLoadingState {
                case .loading:
                    ObvCenteredProgressView()
                case .loaded(let model):
                    OnLoadedModel(model: model,
                                  ownedCryptoId: ownedCryptoId,
                                  dataSources: dataSources,
                                  internalActions: self)
                }
                
            }
        }
        .task(onTask)
    }
    
}


extension ObvOwnedDetailedInfosView: InternalActions {
    
    func userTappedBackButton() {
        navigation.ownedDetailedInfosViewShouldBeDismissed(self)
    }

}


@MainActor
private protocol InternalActions {
    func userTappedBackButton()
}


extension ObvOwnedDetailedInfosView {
    private struct OnLoadedModel: View {

        let model: Model
        let ownedCryptoId: ObvCryptoId
        let dataSources: DataSources
        let internalActions: InternalActions
        
        var body: some View {
            
            VStack {
                
                ObvCardView {
                    HeaderView(model: model,
                               avatarViewDataSource: dataSources.avatarViewDataSource,
                               userTappedBackButton: internalActions.userTappedBackButton)
                }
                .padding(.horizontal)
                
                ListOfAllDetails(ownedCryptoId: ownedCryptoId,
                                 model: model)

            }
            .padding(.top)

        }
        
    }
}

// MARK: - Internal view

extension ObvOwnedDetailedInfosView {
    private struct HeaderView: View {
        
        let model: Model
        let avatarViewDataSource: ObvAvatarViewDataSource
        let userTappedBackButton: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {

                HStack {
                    
                    ObvAvatarView(model: model.avatarModel,
                                  style: .circle,
                                  size: .normal,
                                  dataSource: avatarViewDataSource)

                    Text(model.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName))
                        .font(.system(.body, design: .rounded))

                    Spacer(minLength: 0)
                    
                }
                .padding(.bottom)

                OlvidButtonNew(action: userTappedBackButton) {
                    Label(title: { Text("BACK") }, icon: { Image(systemIcon: .arrowshapeTurnUpBackwardFill) })
                }
                            
            }

        }
        
    }
}


// MARK: - Internal view

extension ObvOwnedDetailedInfosView {
    struct ListOfAllDetails: View {
        
        let ownedCryptoId: ObvCryptoId
        let model: Model

        var body: some View {
            List {
                SectionAboutIdentityDetails(ownedCryptoId: ownedCryptoId, model: model)
                SectionCapabilities(ownedCryptoId: ownedCryptoId, model: model)
                SectionDevices(model: model)
                switch model.isKeycloakManaged {
                case .no:
                    EmptyView()
                case .yes(signedDetails: let signedDetails,
                          ownedIdentityKeycloakApiKey: let ownedIdentityKeycloakApiKey,
                          isTransferRestricted: let isTransferRestricted,
                          supportsIdBasedAuth: let supportsIdBasedAuth):
                    KeycloakRelatedInfosSections(
                        signedDetails: signedDetails,
                        ownedIdentityKeycloakApiKey: ownedIdentityKeycloakApiKey,
                        isTransferRestricted: isTransferRestricted,
                        supportsIdBasedAuth: supportsIdBasedAuth)
                }
            }
        }
        
    }
}


extension ObvOwnedDetailedInfosView {
    private struct SectionAboutIdentityDetails: View {
        
        let ownedCryptoId: ObvCryptoId
        let model: Model

        private var isKeycloakManaged: Bool {
            switch model.isKeycloakManaged {
            case .no: return false
            case .yes: return true
            }
        }
        
        var body: some View {
            Section {
                ObvSimpleListItemView(
                    title: Text("FORM_FIRST_NAME"),
                    value: model.identityCoreDetails.firstName)
                ObvSimpleListItemView(
                    title: Text("FORM_LAST_NAME"),
                    value: model.identityCoreDetails.lastName)
                ObvSimpleListItemView(
                    title: Text("FORM_POSITION"),
                    value: model.identityCoreDetails.position)
                ObvSimpleListItemView(
                    title: Text("FORM_COMPANY"),
                    value: model.identityCoreDetails.company)
                ObvSimpleListItemView(
                    title: Text("Identity"),
                    value: ownedCryptoId.getIdentity().hexString())
                ObvSimpleListItemView(
                    title: Text("Active"),
                    value: model.isActive ? String(localizedInThisBundle: "YES") : String(localizedInThisBundle: "NO"))
                ObvSimpleListItemView(
                    title: Text("CERTIFIED_BY_IDENTITY_PROVIDER"),
                    value: isKeycloakManaged ? String(localizedInThisBundle: "YES") : String(localizedInThisBundle: "NO"))
            } header: {
                Text("Details")
            }
        }
        
    }
}


extension ObvOwnedDetailedInfosView {
    private struct SectionCapabilities: View {
        
        let ownedCryptoId: ObvCryptoId
        let model: Model

        var body: some View {
            Section {
                ForEach(ObvCapability.allCases) { capability in
                    switch capability {
                    case .webrtcContinuousICE:
                        ObvSimpleListItemView(
                            title: Text("CAPABILITY_WEBRTC_CONTINUOUS_ICE"),
                            value: model.capabilitites.contains(capability) ? String(localizedInThisBundle: "YES") : String(localizedInThisBundle: "NO"))
                    case .oneToOneContacts:
                        ObvSimpleListItemView(
                            title: Text("CAPABILITY_ONE_TO_ONE_CONTACTS"),
                            value: model.capabilitites.contains(capability) ? String(localizedInThisBundle: "YES") : String(localizedInThisBundle: "NO"))
                    case .groupsV2:
                        ObvSimpleListItemView(
                            title: Text("CAPABILITY_GROUPS_V2"),
                            value: model.capabilitites.contains(capability) ? String(localizedInThisBundle: "YES") : String(localizedInThisBundle: "NO"))
                    }
                }
            } header: {
                Text("CAPABILITIES")
            }
        }
    }
}


extension ObvOwnedDetailedInfosView {
    private struct SectionDevices: View {
        
        let model: Model

        var body: some View {
            Section {
                if model.devices.isEmpty {
                    Text("NONE")
                } else {
                    ForEach(Array(model.devices.enumerated()), id: \.offset) { index, device in
                        SingleOwnedDeviceView(index: index, device: device)
                    }
                }
            } header: {
                Text("Devices")
            }
        }
        
    }
}


extension ObvOwnedDetailedInfosView {
    private struct SingleOwnedDeviceView: View {
        
        let index: Int
        let device: ObvOwnedDetailedInfosView.Model.Device

        private var secureChannelStatus: String {
            switch device.secureChannelStatus {
            case .currentDevice:
                return String(localizedInThisBundle: "SECURE_CHANNEL_CURRENT_DEVICE")
            case .creationInProgress:
                return String(localizedInThisBundle: "SECURE_CHANNEL_CREATION_IN_PROGRESS")
            case .created:
                return String(localizedInThisBundle: "SECURE_CHANNEL_CREATED")
            case .unavailable:
                return String(localizedInThisBundle: "SECURE_CHANNEL_STATUS_UNAVAILABLE")
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
}


extension ObvOwnedDetailedInfosView {
    private struct KeycloakRelatedInfosSections: View {
        
        let signedDetails: SignedObvKeycloakUserDetails?
        let ownedIdentityKeycloakApiKey: UUID?
        let isTransferRestricted: Bool?
        let supportsIdBasedAuth: Bool
        
        var body: some View {
            Section {
                ObvSimpleListItemView(
                    title: Text("KEYCLOAK_ID"),
                    value: signedDetails?.id)
                ObvSimpleListItemView(
                    title: Text("SIGNED_DETAILS_DATE"),
                    date: signedDetails?.timestamp)
                ObvSimpleListItemView(
                    title: Text("API Key"),
                    value: ownedIdentityKeycloakApiKey?.uuidString ?? String(localizedInThisBundle: "NONE"))
            } header: {
                Text("DETAILS_SIGNED_BY_IDENTITY_PROVIDER")
            }
            
            
            Section(String(localizedInThisBundle: "OTHER_INFORMATIONS_ABOUT_MANAGED_PROFILE")) {
                if let isTransferRestricted {
                    ObvSimpleListItemView(
                        title: Text("IS_TRANSFER_RESTRICTED"),
                        value: isTransferRestricted ? String(localizedInThisBundle: "YES") : String(localizedInThisBundle: "NO"))
                } else {
                    ObvSimpleListItemView(
                        title: Text("IS_TRANSFER_RESTRICTED"),
                        value: nil)
                }
                ObvSimpleListItemView(
                    title: Text("SUPPORTS_ID_BASED_AUTH"),
                    value: supportsIdBasedAuth ? String(localizedInThisBundle: "YES") : String(localizedInThisBundle: "NO"))

            }
        }
        
    }
}
