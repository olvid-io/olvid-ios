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
import ObvDesignSystem
import ObvSystemIcon

@MainActor
public protocol ObvContactDetailedInfosViewDataSource {
    func getAsyncSequenceOfContactDetailedInfosViewModel(_ view: ObvContactDetailedInfosView, contactIdentifier: ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvContactDetailedInfosView.Model>)
    func finishAsyncSequenceOfContactDetailedInfosViewModel(_ view: ObvContactDetailedInfosView, streamUUID: UUID)
}


@MainActor
protocol ObvContactDetailedInfosViewActions {
    func userTappedBackButton(_ view: ObvContactDetailedInfosView)
    func userWantsToSyncOneToOneStatusOfContact(_ view: ObvContactDetailedInfosView, contactIdentifier: ObvContactIdentifier)
}


public struct ObvContactDetailedInfosView: View {

    let contactIdentifier: ObvContactIdentifier
    let dataSource: ObvContactDetailedInfosViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let actions: ObvContactDetailedInfosViewActions

    @State private var streamedModel: Model?
    @State private var streamUUIDForViewModel: UUID?
    
    public struct Model: Sendable, Equatable {
        let avatarModel: ObvAvatarViewModel
        let identityCoreDetails: ObvIdentityCoreDetails
        let customDisplayName: String?
        let isActive: Bool
        let isCertifiedByOwnKeycloak: Bool
        let wasRecentlyOnline: Bool
        let capabilitites: Set<ObvCapability>
        let devices: [Device]
        
        public init(avatarModel: ObvAvatarViewModel, identityCoreDetails: ObvIdentityCoreDetails, customDisplayName: String?, isActive: Bool, isCertifiedByOwnKeycloak: Bool, wasRecentlyOnline: Bool, capabilitites: Set<ObvCapability>, devices: [Device]) {
            self.avatarModel = avatarModel
            self.identityCoreDetails = identityCoreDetails
            self.customDisplayName = customDisplayName
            self.isActive = isActive
            self.isCertifiedByOwnKeycloak = isCertifiedByOwnKeycloak
            self.wasRecentlyOnline = wasRecentlyOnline
            self.capabilitites = capabilitites
            self.devices = devices
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
                case creationInProgress(preKeyAvailable: Bool)
                case created(preKeyAvailable: Bool)
                case unavailable
            }
        }
        
    }
    
    private func userTappedBackButton() {
        actions.userTappedBackButton(self)
    }
    
    private func userWantsToSyncOneToOneStatusOfContact() {
        actions.userWantsToSyncOneToOneStatusOfContact(self, contactIdentifier: contactIdentifier)
    }


    private func onTask() async {
        do {
            let (newStreamUUID, stream) = try await dataSource.getAsyncSequenceOfContactDetailedInfosViewModel(self, contactIdentifier: contactIdentifier)
            if let previousStreamUUID = self.streamUUIDForViewModel {
                dataSource.finishAsyncSequenceOfContactDetailedInfosViewModel(self, streamUUID: previousStreamUUID)
            }
            self.streamUUIDForViewModel = newStreamUUID
            for await receivedModel in stream {
                withAnimation { self.streamedModel = receivedModel }
            }
        } catch {
            assertionFailure()
        }
        if let previousStreamUUID = self.streamUUIDForViewModel {
            dataSource.finishAsyncSequenceOfContactDetailedInfosViewModel(self, streamUUID: previousStreamUUID)
        }
        self.streamUUIDForViewModel = nil
    }
    
    public var body: some View {
        
        ZStack {
            
            Color(UIColor.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)
            
            if let streamedModel {
                ObvContactDetailedInfosViewInternalView(
                    contactIdentifier: contactIdentifier,
                    model: streamedModel,
                    avatarViewDataSource: avatarViewDataSource,
                    userTappedBackButton: userTappedBackButton,
                    userWantsToSyncOneToOneStatusOfContact: userWantsToSyncOneToOneStatusOfContact)
            } else {
                ObvCenteredProgressView()
            }
            

        }
        .task(onTask)
    }
    
}


// MARK: - Internal view

private struct ObvContactDetailedInfosViewInternalView: View {
    
    let contactIdentifier: ObvContactIdentifier
    let model: ObvContactDetailedInfosView.Model
    let avatarViewDataSource: ObvAvatarViewDataSource
    let userTappedBackButton: () -> Void
    let userWantsToSyncOneToOneStatusOfContact: () -> Void
    
    private var cornerRadius: CGFloat {
        if #available(iOS 26.0, *) {
            return 26
        } else {
            return 12
        }
    }
    
    var body: some View {
        
        VStack {
            
            ObvCardView(cornerRadius: cornerRadius) {
                HeaderView(model: model,
                           avatarViewDataSource: avatarViewDataSource,
                           userTappedBackButton: userTappedBackButton)
            }
            .padding(.horizontal)
            
            ListOfAllDetails(contactIdentifier: contactIdentifier,
                             model: model,
                             userWantsToSyncOneToOneStatusOfContact: userWantsToSyncOneToOneStatusOfContact)

        }
        .padding(.top)

    }
}


// MARK: - Internal view

private struct HeaderView: View {

    let model: ObvContactDetailedInfosView.Model
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


// MARK: - Internal view

private struct ListOfAllDetails: View {

    let contactIdentifier: ObvContactIdentifier
    let model: ObvContactDetailedInfosView.Model
    let userWantsToSyncOneToOneStatusOfContact: () -> Void
    
    var body: some View {
        List {
            SectionAboutIdentityDetails(contactIdentifier: contactIdentifier, model: model)
            SectionCapabilities(model: model, userWantsToSyncOneToOneStatusOfContact: userWantsToSyncOneToOneStatusOfContact)
            SectionDevices(model: model)
        }
    }
    
}


// MARK: - Internal view

private struct SectionAboutIdentityDetails: View {

    let contactIdentifier: ObvContactIdentifier
    let model: ObvContactDetailedInfosView.Model

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
                title: Text("FORM_NICKNAME"),
                value: model.customDisplayName)
            ObvSimpleListItemView(
                title: Text("FORM_IDENTITY"),
                value: contactIdentifier.contactCryptoId.getIdentity().hexString())
            ObvSimpleListItemView(
                title: Text("FORM_ACTIVE"),
                value: model.isActive ? String(localizedInThisBundle: "YES") : String(localizedInThisBundle: "NO"))
            ObvSimpleListItemView(
                title: Text("CERTIFIED_BY_IDENTITY_PROVIDER"),
                value: model.isCertifiedByOwnKeycloak ? String(localizedInThisBundle: "YES") : String(localizedInThisBundle: "NO"))
            ObvSimpleListItemView(
                title: Text("WAS_RECENTLY_ONLINE"),
                value: model.wasRecentlyOnline ? String(localizedInThisBundle: "YES") : String(localizedInThisBundle: "NO"))
        } header: {
            Text("SECTION_TITLE_DETAILS")
        }
    }
    
}


// MARK: - Internal view

private struct SectionCapabilities: View {

    let model: ObvContactDetailedInfosView.Model
    let userWantsToSyncOneToOneStatusOfContact: () -> Void

    var body: some View {
    
        Section {
            ForEach(ObvCapability.allCases) { capability in
                switch capability {
                case .webrtcContinuousICE:
                    ObvSimpleListItemView(
                        title: Text("CAPABILITY_WEBRTC_CONTINUOUS_ICE"),
                        value: model.capabilitites.contains(capability) ?  String(localizedInThisBundle: "YES") : String(localizedInThisBundle: "NO"))
                case .oneToOneContacts:
                    ObvSimpleListItemView(
                        title: Text("CAPABILITY_ONE_TO_ONE_CONTACTS"),
                        value: model.capabilitites.contains(capability) ?  String(localizedInThisBundle: "YES") : String(localizedInThisBundle: "NO"),
                        buttonConfig: ("SYNC", "SYNC_REQUEST_SENT", userWantsToSyncOneToOneStatusOfContact))
                case .groupsV2:
                    ObvSimpleListItemView(
                        title: Text("CAPABILITY_GROUPS_V2"),
                        value: model.capabilitites.contains(capability) ?  String(localizedInThisBundle: "YES") : String(localizedInThisBundle: "NO"))
                }
            }
        } header: {
            Text("CAPABILITIES")
        }

    }
    
}


// MARK: - Internal view

private struct SectionDevices: View {

    let model: ObvContactDetailedInfosView.Model

    var body: some View {
        Section {
            if model.devices.isEmpty {
                Text("NONE")
            } else {
                ForEach(Array(model.devices.enumerated()), id: \.offset) { index, device in
                    SingleContactDeviceView(index: index, device: device)
                }
            }
        } header: {
            Text("DEVICES")
        }
    }
    
}


// MARK: - Internal view

private struct SingleContactDeviceView: View {
    
    let index: Int
    let device: ObvContactDetailedInfosView.Model.Device
    
    private var secureChannelStatus: String {
        switch device.secureChannelStatus {
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


#if DEBUG

// MARK: - Previews

@MainActor
private final class DataSourceAndActionsForPreviews {}

extension DataSourceAndActionsForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }

}

extension DataSourceAndActionsForPreviews: ObvContactDetailedInfosViewDataSource {
    
    func getAsyncSequenceOfContactDetailedInfosViewModel(_ view: ObvContactDetailedInfosView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvContactDetailedInfosView.Model>) {
        let stream = AsyncStream<ObvContactDetailedInfosView.Model> { (continuation: AsyncStream<ObvContactDetailedInfosView.Model>.Continuation) in
            let model = ObvContactDetailedInfosView.Model(
                avatarModel: .sampleDataForTrustedDetails,
                identityCoreDetails: .sampleDataForTrustedDetails,
                customDisplayName: "Custom name",
                isActive: true,
                isCertifiedByOwnKeycloak: false,
                wasRecentlyOnline: true,
                capabilitites: [.groupsV2, .oneToOneContacts],
                devices: [
                    .init(identifier: Data(repeating: 0x00, count: 32),
                          secureChannelStatus: .created(preKeyAvailable: true))
                ])
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfContactDetailedInfosViewModel(_ view: ObvContactDetailedInfosView, streamUUID: UUID) {}
    
}


extension DataSourceAndActionsForPreviews: ObvContactDetailedInfosViewActions {
    
    func userTappedBackButton(_ view: ObvContactDetailedInfosView) {}
    func userWantsToSyncOneToOneStatusOfContact(_ view: ObvContactDetailedInfosView, contactIdentifier: ObvContactIdentifier) {}
    
}


@MainActor
private let dataSourceAndActionsForPreviews = DataSourceAndActionsForPreviews()

#Preview {
    ObvContactDetailedInfosView(contactIdentifier: .sampleData,
                                dataSource: dataSourceAndActionsForPreviews,
                                avatarViewDataSource: dataSourceAndActionsForPreviews,
                                actions: dataSourceAndActionsForPreviews)
}



#endif
