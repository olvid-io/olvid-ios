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
import ObvUI
import ObvUICoreData
import ObvSystemIcon
import ObvTypes
import ObvEngine


// MARK: - OwnedDevicesListViewModelProtocol

protocol OwnedDevicesListViewModelProtocol: ObservableObject {

    associatedtype OwnedDeviceViewModel: OwnedDeviceViewModelProtocol

    var ownedCryptoId: ObvCryptoId { get }
    var ownedDevices: [OwnedDeviceViewModel] { get }
    
}


// MARK: - OwnedDevicesListViewActionsDelegate

protocol OwnedDevicesListViewActionsDelegate: OwnedDeviceViewActionsDelegate {
    
    func userWantsToSearchForNewOwnedDevices(ownedCryptoId: ObvCryptoId) async
    func userWantsToClearAllOtherOwnedDevices(ownedCryptoId: ObvCryptoId) async
    
}


// MARK: - OwnedDevicesListView

struct OwnedDevicesListView<Model: OwnedDevicesListViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    let actions: OwnedDevicesListViewActionsDelegate
    
    @State private var alertKind = AlertKind.clearAllDevices
    @State private var isAlertPresented = false
    
    private enum AlertKind {
        case clearAllDevices
    }
    
    private func userWantsToSearchForNewOwnedDevices() {
        Task { await actions.userWantsToSearchForNewOwnedDevices(ownedCryptoId: model.ownedCryptoId) }
    }
    
    private func userWantsToClearAllOtherOwnedDevicesAndHasConfirmed() {
        Task { await actions.userWantsToClearAllOtherOwnedDevices(ownedCryptoId: model.ownedCryptoId) }
    }
    
    private func userWantsToClearAllOtherOwnedDevicesAndMustConfirm() {
        alertKind = .clearAllDevices
        withAnimation {
            isAlertPresented = true
        }
    }
    
    var body: some View {
        ScrollView {
            VStack {
                ForEach(model.ownedDevices, id: \.deviceIdentifier) { ownedDevice in
                    ObvCardView {
                        OwnedDeviceView(
                            ownedDevice: ownedDevice,
                            actions: actions)
                    }.padding(.bottom)
                }
                OlvidButton(
                    style: .standard,
                    title: Text("SEARCH_FOR_NEW_DEVICES"),
                    systemIcon: .magnifyingglass,
                    action: userWantsToSearchForNewOwnedDevices)
                OlvidButton(
                    style: .red,
                    title: Text("CLEAR_ALL_DEVICES"),
                    systemIcon: .trash,
                    action: userWantsToClearAllOtherOwnedDevicesAndMustConfirm)
                Spacer()
            }.padding()
        }
        .alert(isPresented: $isAlertPresented) {
            switch self.alertKind {
            case .clearAllDevices:
                return Alert(title: Text("CLEAR_ALL_OTHER_OWNED_DEVICES_ALERT_TITLE"),
                             message: Text("CLEAR_ALL_OTHER_OWNED_DEVICES_ALERT_MESSAGE"),
                             primaryButton: Alert.Button.destructive(Text("Yes"), action: userWantsToClearAllOtherOwnedDevicesAndHasConfirmed),
                             secondaryButton: Alert.Button.cancel())
            }
        }
    }
    
}


// MARK: - Previews


struct OwnedDevicesListView_Previews: PreviewProvider {

    private class OwnedDeviceViewModelForPreviews: OwnedDeviceViewModelProtocol {
        
        let ownedCryptoId: ObvCryptoId
        let deviceIdentifier: Data
        let name: String
        let secureChannelStatus: PersistedObvOwnedDevice.SecureChannelStatus?
        let expirationDate: Date?
        let latestRegistrationDate: Date?
        let ownedIdentityIsActive: Bool

        init(ownedCryptoId: ObvCryptoId, deviceIdentifier: Data, name: String, secureChannelStatus: PersistedObvOwnedDevice.SecureChannelStatus?, expirationDate: Date?, latestRegistrationDate: Date?, ownedIdentityIsActive: Bool) {
            self.ownedCryptoId = ownedCryptoId
            self.deviceIdentifier = deviceIdentifier
            self.name = name
            self.secureChannelStatus = secureChannelStatus
            self.expirationDate = expirationDate
            self.latestRegistrationDate = latestRegistrationDate
            self.ownedIdentityIsActive = ownedIdentityIsActive
        }
        
    }

    private class OwnedDevicesListViewModelForPreviews: OwnedDevicesListViewModelProtocol {
        let ownedCryptoId: ObvCryptoId
        let ownedDevices: [OwnedDeviceViewModelForPreviews]
        
        init(ownedCryptoId: ObvCryptoId, ownedDevices: [OwnedDeviceViewModelForPreviews]) {
            self.ownedCryptoId = ownedCryptoId
            self.ownedDevices = ownedDevices
        }
    }
    
    
    private struct OwnedDevicesListViewActions: OwnedDevicesListViewActionsDelegate {
        func userWantsToKeepThisDeviceActive(ownedCryptoId: ObvTypes.ObvCryptoId, deviceIdentifier: Data) async {}
        func userWantsToSearchForNewOwnedDevices(ownedCryptoId: ObvTypes.ObvCryptoId) async {}
        func userWantsToClearAllOtherOwnedDevices(ownedCryptoId: ObvTypes.ObvCryptoId) async {}
        func userWantsToRestartChannelCreationWithOtherOwnedDevice(ownedCryptoId: ObvTypes.ObvCryptoId, deviceIdentifier: Data) async {}
        func userWantsToRenameOwnedDevice(ownedCryptoId: ObvTypes.ObvCryptoId, deviceIdentifier: Data) async {}
        func userWantsToDeactivateOtherOwnedDevice(ownedCryptoId: ObvCryptoId, deviceIdentifier: Data) async {}
    }

    
    private static let identitiesAsURLs: [URL] = [
        URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!,
        URL(string: "https://invitation.olvid.io/#AwAAAHAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAVZx8aqikpCe4h3ayCwgKBf-2nDwz-a6vxUo3-ep5azkBUjimUf3J--GXI8WTc2NIysQbw5fxmsY9TpjnDsZMW-AAAAAACEJvYiBXb3Jr")!,
    ]
        
    private static let ownedCryptoIds = identitiesAsURLs.map({ ObvURLIdentity(urlRepresentation: $0)!.cryptoId })

    private static let ownedDevices: [OwnedDeviceViewModelForPreviews] = {
        let ownedCryptoId = ownedCryptoIds[0]
        return [
            OwnedDeviceViewModelForPreviews(
                ownedCryptoId: ownedCryptoId,
                deviceIdentifier: Data(repeating: 0, count: 16),
                name: "iPhone 14",
                secureChannelStatus: .currentDevice,
                expirationDate: nil,
                latestRegistrationDate: nil,
                ownedIdentityIsActive: true),
            OwnedDeviceViewModelForPreviews(
                ownedCryptoId: ownedCryptoId,
                deviceIdentifier: Data(repeating: 1, count: 16),
                name: "iPad pro",
                secureChannelStatus: .created(preKeyAvailable: true),
                expirationDate: Date(timeIntervalSinceNow: 1_000),
                latestRegistrationDate: Date(timeIntervalSinceNow: -500),
                ownedIdentityIsActive: true),
        ]
    }()
    
    static var previews: some View {
        Group {
            OwnedDevicesListView(
                model: OwnedDevicesListViewModelForPreviews(
                    ownedCryptoId: ownedCryptoIds[0],
                    ownedDevices: ownedDevices),
                actions: OwnedDevicesListViewActions())
        }
    }
}
