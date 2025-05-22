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
import ObvUICoreData
import CoreData
import ObvTypes
import ObvEngine
import ObvUI
import ObvDesignSystem



// MARK: - ContactDevicesListViewModelProtocol

protocol ContactDevicesListViewModelProtocol: ObservableObject {
    
    associatedtype ContactDeviceViewModel: ContactDeviceViewModelProtocol

    var contactIdentifier: ObvContactIdentifier { get throws }
    var contactDevices: [ContactDeviceViewModel] { get }

}


protocol ContactDevicesListViewActionsDelegate: AnyObject, ContactDeviceViewActionsDelegate {
    
    func userWantsToClearAllContactDevices(contactIdentifier: ObvContactIdentifier) async
    func userWantsToSearchForNewContactDevices(contactIdentifier: ObvContactIdentifier) async

}


// MARK: - ContactDevicesListView

struct ContactDevicesListView<Model: ContactDevicesListViewModelProtocol>: View {

    @ObservedObject var model: Model
    let actions: ContactDevicesListViewActionsDelegate

    
    private func userWantsToSearchForNewDevicesOfThisContact() {
        guard let contactIdentifier = try? model.contactIdentifier else { assertionFailure(); return }
        Task {
            await actions.userWantsToSearchForNewContactDevices(contactIdentifier: contactIdentifier)
        }
    }
    
    
    private func userWantsToClearAllDevicesOfThisContact() {
        guard let contactIdentifier = try? model.contactIdentifier else { assertionFailure(); return }
        Task {
            await actions.userWantsToClearAllContactDevices(contactIdentifier: contactIdentifier)
        }
    }
    

    var body: some View {
        ScrollView {
            VStack {
                ObvCardView {
                    ForEach(model.contactDevices, id: \.deviceIdentifier) { device in
                        ContactDeviceView(model: device, actions: actions)
                    }
                }
                OlvidButton(
                    style: .standard,
                    title: Text("SEARCH_FOR_NEW_DEVICES"),
                    systemIcon: .magnifyingglass,
                    action: userWantsToSearchForNewDevicesOfThisContact)
                OlvidButton(
                    style: .red,
                    title: Text("CLEAR_ALL_DEVICES"),
                    systemIcon: .trash,
                    action: userWantsToClearAllDevicesOfThisContact)
                Spacer()
            }.padding()
        }
    }
    
}


// MARK: - Previews


struct ContactDevicesListView_Previews: PreviewProvider {

    private class ContactDeviceViewModelForPreviews: ContactDeviceViewModelProtocol {
        
        let contactIdentifier: ObvContactIdentifier
        let secureChannelStatus: ObvUICoreData.PersistedObvContactDevice.SecureChannelStatus?
        let deviceIdentifier: Data
        let name: String
        
        init(contactIdentifier: ObvContactIdentifier, secureChannelStatus: ObvUICoreData.PersistedObvContactDevice.SecureChannelStatus?, deviceIdentifier: Data, name: String) {
            self.contactIdentifier = contactIdentifier
            self.secureChannelStatus = secureChannelStatus
            self.deviceIdentifier = deviceIdentifier
            self.name = name
        }
        
    }

    
    private class ContactDevicesListViewForPreviews: ContactDevicesListViewModelProtocol {
        
        let contactIdentifier: ObvContactIdentifier
        let contactDevices: [ContactDeviceViewModelForPreviews]
        
        init(contactIdentifier: ObvContactIdentifier, contactDevices: [ContactDeviceViewModelForPreviews]) {
            self.contactIdentifier = contactIdentifier
            self.contactDevices = contactDevices
        }
        
    }
    
    
    private final class ContactDevicesListViewActionsForPreviews: ContactDevicesListViewActionsDelegate {
        func userWantsToClearAllContactDevices(contactIdentifier: ObvContactIdentifier) {}
        func userWantsToSearchForNewContactDevices(contactIdentifier: ObvContactIdentifier) {}
        func userWantsToRestartChannelCreationWithContactDevice(contactIdentifier: ObvContactIdentifier, deviceIdentifier: Data) async {}
    }
    
    
    private static let identitiesAsURLs: [URL] = [
        URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!,
        URL(string: "https://invitation.olvid.io/#AwAAAHAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAVZx8aqikpCe4h3ayCwgKBf-2nDwz-a6vxUo3-ep5azkBUjimUf3J--GXI8WTc2NIysQbw5fxmsY9TpjnDsZMW-AAAAAACEJvYiBXb3Jr")!,
    ]

    private static let contactIdentifier: ObvContactIdentifier = {
        let ownedCryptoId = ObvURLIdentity(urlRepresentation: identitiesAsURLs[0])!.cryptoId
        let contactCryptoId = ObvURLIdentity(urlRepresentation: identitiesAsURLs[1])!.cryptoId
        return ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
    }()

    
    private static let contactDevices: [ContactDeviceViewModelForPreviews] = {
    [
        ContactDeviceViewModelForPreviews(
            contactIdentifier: contactIdentifier,
            secureChannelStatus: .creationInProgress(preKeyAvailable: true),
            deviceIdentifier: Data(repeating: 0, count: 16),
            name: String("1234")),
        ContactDeviceViewModelForPreviews(
            contactIdentifier: contactIdentifier,
            secureChannelStatus: .created(preKeyAvailable: false),
            deviceIdentifier: Data(repeating: 1, count: 16),
            name: String("5678")),
        ContactDeviceViewModelForPreviews(
            contactIdentifier: contactIdentifier,
            secureChannelStatus: nil,
            deviceIdentifier: Data(repeating: 2, count: 16),
            name: String("5678")),
    ]
    }()

    
    private static let model: ContactDevicesListViewForPreviews = {
        ContactDevicesListViewForPreviews(
            contactIdentifier: contactIdentifier,
            contactDevices: contactDevices)
    }()
    
    
    static var previews: some View {
        Group {
            ContactDevicesListView(
                model: model,
                actions: ContactDevicesListViewActionsForPreviews())
            .previewLayout(PreviewLayout.sizeThatFits)
            .previewDisplayName("Three devices")
        }
    }

}
