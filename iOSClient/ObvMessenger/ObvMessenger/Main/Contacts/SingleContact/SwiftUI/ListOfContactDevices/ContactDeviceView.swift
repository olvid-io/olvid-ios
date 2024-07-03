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
import ObvUI
import UI_SystemIcon
import ObvTypes
import ObvEngine
import ObvDesignSystem


// MARK: - ContactDeviceViewModelProtocol

protocol ContactDeviceViewModelProtocol: ObservableObject {
    
    var contactIdentifier: ObvContactIdentifier { get throws }
    var secureChannelStatus: PersistedObvContactDevice.SecureChannelStatus? { get }
    var deviceIdentifier: Data { get }
    var name: String { get }

}


// MARK: - ContactDeviceViewActionDelegate

protocol ContactDeviceViewActionsDelegate {
    
    func userWantsToRestartChannelCreationWithContactDevice(contactIdentifier: ObvContactIdentifier, deviceIdentifier: Data) async
    
}

// MARK: - ContactDeviceView

struct ContactDeviceView<Model: ContactDeviceViewModelProtocol>: View {

    @ObservedObject var model: Model
    let actions: ContactDeviceViewActionsDelegate

    
    private var textForSecureChannelStatus: LocalizedStringKey {
        switch model.secureChannelStatus {
        case .creationInProgress, .none:
            return "SECURE_CHANNEL_CREATION_IN_PROGRESS"
        case .created:
            return "SECURE_CHANNEL_CREATED"
        }
    }
    

    private var systemIconForSecureChannelStatus: SystemIcon {
        switch model.secureChannelStatus {
        case .creationInProgress, .none:
            return .arrowTriangle2CirclepathCircle
        case .created:
            return .checkmarkShield
        }
    }
    
    
    private var textForPreKeyStatus: LocalizedStringKey {
        if model.secureChannelStatus?.isPreKeyAvailable == true {
            return "PRE_KEY_IS_AVAILABLE_FOR_CONTACT_DEVICE"
        } else {
            return "PRE_KEY_IS_NOT_AVAILABLE_FOR_CONTACT_DEVICE"
        }
    }
    

    private var systemIconForPreKeyStatus: SystemIcon {
        if model.secureChannelStatus?.isPreKeyAvailable == true {
            return .key
        } else {
            return .keySlash
        }
    }
    
    private var systemIconColorForPreKeyStatus: Color {
        if model.secureChannelStatus?.isPreKeyAvailable == true {
            return Color(UIColor.systemGreen)
        } else {
            return .primary
        }
    }
    
    private var colorForSecureChannelStatus: Color {
        switch model.secureChannelStatus {
        case .creationInProgress, .none:
            return .primary
        case .created:
            return .green
        }
    }
    
    
    private func userWantsToRestartChannelCreationWithThisDevice() {
        guard let contactIdentifier = try? model.contactIdentifier else { assertionFailure(); return }
        let deviceIdentifier = model.deviceIdentifier
        Task {
            await actions.userWantsToRestartChannelCreationWithContactDevice(contactIdentifier: contactIdentifier, deviceIdentifier: deviceIdentifier)
        }
    }
    
        
    var body: some View {
        VStack(alignment: .leading) {
            
            HStack {
                Text("DEVICE \(model.name)")
                    .font(.headline)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                Spacer()
            }
            .padding(.bottom, 4.0)
            
            HStack {
                Label {
                    Text(textForSecureChannelStatus)
                        .font(.body)
                        .foregroundColor(.primary)
                } icon: {
                    Image(systemIcon: systemIconForSecureChannelStatus)
                        .foregroundColor(colorForSecureChannelStatus)
                }
            }
            .padding(.bottom, 2.0)
            
            HStack {
                Label {
                    Text(textForPreKeyStatus)
                        .font(.body)
                        .foregroundColor(.primary)
                } icon: {
                    Image(systemIcon: systemIconForPreKeyStatus)
                        .foregroundColor(systemIconColorForPreKeyStatus)
                }
            }
            .padding(.bottom, 2.0)

            
            Button(action: userWantsToRestartChannelCreationWithThisDevice) {
                Label(LocalizedStringKey("RECREATE_SECURE_CHANNEL_WITH_THIS_DEVICE"), systemIcon: .restartCircle)
            }
            .padding(.bottom, 4.0)
        }
    }

}







// MARK: - Previews


struct ContactDeviceView_Previews: PreviewProvider {

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

    
    private struct ContactDeviceViewActionsForPreviews: ContactDeviceViewActionsDelegate {
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

    
    private static let models: [ContactDeviceViewModelForPreviews] = {
    [
        ContactDeviceViewModelForPreviews(
            contactIdentifier: contactIdentifier,
            secureChannelStatus: .creationInProgress(preKeyAvailable: false),
            deviceIdentifier: Data(repeating: 0, count: 16),
            name: String("1234")),
        ContactDeviceViewModelForPreviews(
            contactIdentifier: contactIdentifier,
            secureChannelStatus: .created(preKeyAvailable: true),
            deviceIdentifier: Data(repeating: 0, count: 16),
            name: String("5678")),
        ContactDeviceViewModelForPreviews(
            contactIdentifier: contactIdentifier,
            secureChannelStatus: nil,
            deviceIdentifier: Data(repeating: 0, count: 16),
            name: String("5678")),
    ]
    }()
    
    static var previews: some View {
        Group {
            ContactDeviceView(
                model: models[0],
                actions: ContactDeviceViewActionsForPreviews())
            .previewLayout(PreviewLayout.sizeThatFits)
            .previewDisplayName("Creation in progress")
            .environment(\.locale, .init(identifier: "fr"))
            
            ContactDeviceView(
                model: models[1],
                actions: ContactDeviceViewActionsForPreviews())
            .previewLayout(PreviewLayout.sizeThatFits)
            .previewDisplayName("Channel created")

            ContactDeviceView(
                model: models[2],
                actions: ContactDeviceViewActionsForPreviews())
            .previewLayout(PreviewLayout.sizeThatFits)
            .previewDisplayName("Channel status not specified")
        }
    }

}
