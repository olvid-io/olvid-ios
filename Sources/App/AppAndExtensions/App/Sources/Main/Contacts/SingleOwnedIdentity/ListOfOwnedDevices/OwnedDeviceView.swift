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


// MARK: - OwnedDeviceViewModel

protocol OwnedDeviceViewModelProtocol: ObservableObject {
    
    var ownedCryptoId: ObvCryptoId { get throws }
    var deviceIdentifier: Data { get }
    var name: String { get }
    var secureChannelStatus: PersistedObvOwnedDevice.SecureChannelStatus? { get }
    var expirationDate: Date? { get }
    var latestRegistrationDate: Date? { get }
    var ownedIdentityIsActive: Bool { get }
    
}


// MARK: - OwnedDeviceViewActionsDelegate

protocol OwnedDeviceViewActionsDelegate {
    
    func userWantsToRestartChannelCreationWithOtherOwnedDevice(ownedCryptoId: ObvCryptoId, deviceIdentifier: Data) async
    func userWantsToRenameOwnedDevice(ownedCryptoId: ObvCryptoId, deviceIdentifier: Data) async
    func userWantsToDeactivateOtherOwnedDevice(ownedCryptoId: ObvCryptoId, deviceIdentifier: Data) async
    func userWantsToKeepThisDeviceActive(ownedCryptoId: ObvCryptoId, deviceIdentifier: Data) async
    
}


// MARK: - OwnedDeviceView

struct OwnedDeviceView<Model: OwnedDeviceViewModelProtocol>: View {
    
    @ObservedObject var ownedDevice: Model
    let actions: OwnedDeviceViewActionsDelegate
    
    
    private var textForSecureChannelStatus: LocalizedStringKey {
        switch ownedDevice.secureChannelStatus {
        case .currentDevice:
            return "CURRENT_DEVICE"
        case .creationInProgress, .none:
            return "SECURE_CHANNEL_CREATION_IN_PROGRESS"
        case .created:
            return "SECURE_CHANNEL_CREATED"
        }
    }

    
    private var textForPreKeyStatus: LocalizedStringKey {
        if ownedDevice.secureChannelStatus?.isPreKeyAvailable == true {
            return "PRE_KEY_IS_AVAILABLE_FOR_OWNED_DEVICE"
        } else {
            return "PRE_KEY_IS_NOT_AVAILABLE_FOR_OWNED_DEVICE"
        }
    }

    
    private var systemIconForPreKeyStatus: SystemIcon {
        if ownedDevice.secureChannelStatus?.isPreKeyAvailable == true {
            return .key
        } else {
            return .keySlash
        }
    }
    
    private var systemIconColorForPreKeyStatus: Color {
        if ownedDevice.secureChannelStatus?.isPreKeyAvailable == true {
            return Color(UIColor.systemGreen)
        } else {
            return .primary
        }
    }

    
    private func userWantsToRestartChannelCreationWithThisOwnedDevice() {
        guard let ownedCryptoId = try? ownedDevice.ownedCryptoId else { assertionFailure(); return }
        guard ownedDevice.secureChannelStatus != .currentDevice else { assertionFailure(); return }
        let deviceIdentifier = ownedDevice.deviceIdentifier
        Task {
            await actions.userWantsToRestartChannelCreationWithOtherOwnedDevice(ownedCryptoId: ownedCryptoId, deviceIdentifier: deviceIdentifier)
        }
    }
    
    
    private func userWantsToRenameThisDevice() {
        guard let ownedCryptoId = try? ownedDevice.ownedCryptoId else { assertionFailure(); return }
        let deviceIdentifier = ownedDevice.deviceIdentifier
        Task {
            await actions.userWantsToRenameOwnedDevice(ownedCryptoId: ownedCryptoId, deviceIdentifier: deviceIdentifier)
        }
    }
    
    
    private func userWantsToDeactivateOtherOwnedDevice() {
        guard let ownedCryptoId = try? ownedDevice.ownedCryptoId else { assertionFailure(); return }
        let deviceIdentifier = ownedDevice.deviceIdentifier
        Task {
            await actions.userWantsToDeactivateOtherOwnedDevice(ownedCryptoId: ownedCryptoId, deviceIdentifier: deviceIdentifier)
        }
    }
    
    
    private func userWantsToKeepThisDeviceActive() {
        guard let ownedCryptoId = try? ownedDevice.ownedCryptoId else { assertionFailure(); return }
        let deviceIdentifier = ownedDevice.deviceIdentifier
        Task {
            await actions.userWantsToKeepThisDeviceActive(ownedCryptoId: ownedCryptoId, deviceIdentifier: deviceIdentifier)
        }
    }
    
    
    private var systemIconForSecureChannelStatus: SystemIcon {
        switch ownedDevice.secureChannelStatus {
        case .currentDevice:
            switch UIDevice.current.userInterfaceIdiom {
            case .pad:
                return .ipadLandscape
            case .mac:
                return .laptopcomputer
            default:
                return .iphone
            }
        case .creationInProgress, .none:
            return .arrowTriangle2CirclepathCircle
        case .created:
            return .checkmarkShield
        }
    }

    
    private var colorForSecureChannelStatus: Color {
        switch ownedDevice.secureChannelStatus {
        case .creationInProgress, .none, .currentDevice:
            return .primary
        case .created:
            return .green
        }
    }

    @Environment(\.sizeCategory) var sizeCategory
    
    private var heuristicIconSize: CGFloat {
        switch sizeCategory {
        case .accessibilityExtraLarge, .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge:
            return 70
        case .accessibilityMedium, .accessibilityLarge:
            return 50
        default:
            return 35
        }
    }
    
    
    private var isCurrentDevice: Bool {
        switch ownedDevice.secureChannelStatus {
        case .currentDevice:
            return true
        case .creationInProgress, .created, .none:
            return false
        }
    }
    

    var body: some View {
        VStack(alignment: .leading) {
            
            // Title
            
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: ownedDevice.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(nil)
                if isCurrentDevice {
                    Text("CURRENT_DEVICE_LOWERCAES_WITH_PARENTHESES")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(verbatim: String("(\(ownedDevice.deviceIdentifier.hexString().prefix(4)))"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }.padding(.bottom, 4.0)
            
            Group {
                
                // Button for renaming this device
                
                Button(action: userWantsToRenameThisDevice) {
                    InternalLabel("RENAME_DEVICE", systemIcon: .rectangleAndPencilAndEllipsis, systemIconIconWidth: heuristicIconSize, systemIconColor: Color(UIColor.systemBlue), labelColor: Color(UIColor.systemBlue))
                }
                .padding(.bottom, 4.0)

                // Last online date
                
                if let latestRegistrationDate = ownedDevice.latestRegistrationDate, ownedDevice.secureChannelStatus != .currentDevice {
                    InternalLabel("DEVICE_LAST_ONLINE_\(latestRegistrationDate.relativeFormatted)", systemIcon: .eyes, systemIconIconWidth: heuristicIconSize, systemIconColor: Color(UIColor.systemGreen))
                        .padding(.bottom, 4.0)
                }
                
            }
            
            Divider()
                .padding(.leading, heuristicIconSize + 8)
                .padding(.vertical, 4.0)

            // Deactivation informations and actions
            
            Group {
                
                // Deactivation date
                
                Group {
                    if !ownedDevice.ownedIdentityIsActive {
                        InternalLabel("DEVICE_DEACTIVATED", systemIcon: .poweroff, systemIconIconWidth: heuristicIconSize, systemIconColor: Color(UIColor.systemRed))
                    } else if let expirationDate = ownedDevice.expirationDate {
                        InternalLabel("DEVICE_DEACTIVATED_\(expirationDate.relativeFormatted)", systemIcon: .poweroff, systemIconIconWidth: heuristicIconSize, systemIconColor: Color(UIColor.systemRed))
                    } else {
                        InternalLabel("DEVICE_WONT_BE_DEACTIVATED", systemIcon: .poweroff, systemIconIconWidth: heuristicIconSize, systemIconColor: Color(UIColor.systemGreen))
                    }
                }.padding(.bottom, 4.0)


                // Button for keeping the device active
                
                if ownedDevice.expirationDate != nil && ownedDevice.ownedIdentityIsActive {
                    Button(action: userWantsToKeepThisDeviceActive) {
                        InternalLabel("KEEP_THIS_DEVICE_ACTIVE", systemIcon: .poweroff, systemIconIconWidth: heuristicIconSize, systemIconColor: Color(UIColor.systemGreen), labelColor: Color(UIColor.systemBlue))
                            .padding(.bottom, 4.0)
                    }
                }

                // Button for deactivating this device
                
                switch ownedDevice.secureChannelStatus {
                case .currentDevice:
                    EmptyView()
                case .created, .creationInProgress, .none:
                    Button(action: userWantsToDeactivateOtherOwnedDevice) {
                        InternalLabel("REMOVE_OWNED_DEVICE", systemIcon: .poweroff, systemIconIconWidth: heuristicIconSize, systemIconColor: Color(UIColor.systemRed), labelColor: Color(UIColor.systemRed))
                    }
                    .padding(.bottom, 4.0)
                }

            }

            // Secure channel & PreKey informations and actions (for other owned devices)
            
            switch ownedDevice.secureChannelStatus {
            case .currentDevice:
                EmptyView()
            case .created, .creationInProgress, .none:

                Group {
                    
                    Divider()
                        .padding(.leading, heuristicIconSize + 8)
                        .padding(.vertical, 4.0)
                    
                    InternalLabel(textForPreKeyStatus, systemIcon: systemIconForPreKeyStatus, systemIconIconWidth: heuristicIconSize, systemIconColor: systemIconColorForPreKeyStatus)
                        .padding(.bottom, 4.0)

                    // Secure channel status (for other owned devices)
                    
                    InternalLabel(textForSecureChannelStatus, systemIcon: systemIconForSecureChannelStatus, systemIconIconWidth: heuristicIconSize, systemIconColor: colorForSecureChannelStatus)
                        .padding(.bottom, 4.0)
                    
                    // Button for reacreating channel
                    
                    switch ownedDevice.secureChannelStatus {
                    case .currentDevice:
                        EmptyView()
                    case .created, .creationInProgress, .none:
                        Button(action: userWantsToRestartChannelCreationWithThisOwnedDevice) {
                            InternalLabel("RECREATE_SECURE_CHANNEL_WITH_THIS_DEVICE", systemIcon: .restartCircle, systemIconIconWidth: heuristicIconSize, systemIconColor: Color(UIColor.systemBlue), labelColor: Color(UIColor.systemBlue))
                        }
                        .padding(.bottom, 4.0)
                    }
                                                                    
                }

            }
                                    
        }
    }
    
}


// MARK: - InternalLabel

fileprivate struct InternalLabel: View {
    
    let localizedStringKey: LocalizedStringKey
    let systemIcon: SystemIcon
    let systemIconIconWidth: CGFloat
    let systemIconColor: Color
    let labelColor: Color
    
    init(_ localizedStringKey: LocalizedStringKey, systemIcon: SystemIcon, systemIconIconWidth: CGFloat, systemIconColor: Color = .primary, labelColor: Color = .primary) {
        self.localizedStringKey = localizedStringKey
        self.systemIcon = systemIcon
        self.systemIconIconWidth = systemIconIconWidth
        self.systemIconColor = systemIconColor
        self.labelColor = labelColor
    }
    
    var body: some View {
        Label {
            Text(localizedStringKey)
                .foregroundColor(labelColor)
        } icon: {
            HStack(alignment: .firstTextBaseline) {
                Spacer()
                Image(systemIcon: systemIcon)
                    .foregroundColor(systemIconColor)
                Spacer()
            }
            .frame(width: systemIconIconWidth)
        }
    }
}










// MARK: - Previews

struct OwnedDeviceView_Previews: PreviewProvider {

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
    
    private struct OwnedDeviceViewActions: OwnedDeviceViewActionsDelegate {
        func userWantsToKeepThisDeviceActive(ownedCryptoId: ObvTypes.ObvCryptoId, deviceIdentifier: Data) async {}
        func userWantsToRestartChannelCreationWithOtherOwnedDevice(ownedCryptoId: ObvTypes.ObvCryptoId, deviceIdentifier: Data) async {}
        func userWantsToRenameOwnedDevice(ownedCryptoId: ObvTypes.ObvCryptoId, deviceIdentifier: Data) async {}
        func userWantsToDeactivateOtherOwnedDevice(ownedCryptoId: ObvCryptoId, deviceIdentifier: Data) async {}
    }
    
    private static let identitiesAsURLs: [URL] = [
        URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!,
        URL(string: "https://invitation.olvid.io/#AwAAAHAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAVZx8aqikpCe4h3ayCwgKBf-2nDwz-a6vxUo3-ep5azkBUjimUf3J--GXI8WTc2NIysQbw5fxmsY9TpjnDsZMW-AAAAAACEJvYiBXb3Jr")!,
    ]
        
    private static let ownedCryptoIds = identitiesAsURLs.map({ ObvURLIdentity(urlRepresentation: $0)!.cryptoId })

    static var previews: some View {
        Group {
            
            OwnedDeviceView(
                ownedDevice: OwnedDeviceViewModelForPreviews(
                    ownedCryptoId: ownedCryptoIds[0],
                    deviceIdentifier: Data(repeating: 0, count: 16),
                    name: "iPhone 14",
                    secureChannelStatus: .currentDevice,
                    expirationDate: nil,
                    latestRegistrationDate: nil,
                    ownedIdentityIsActive: true),
                actions: OwnedDeviceViewActions())
            .previewLayout(.sizeThatFits)
            .padding()
            
            OwnedDeviceView(
                ownedDevice: OwnedDeviceViewModelForPreviews(
                    ownedCryptoId: ownedCryptoIds[1],
                    deviceIdentifier: Data(repeating: 1, count: 16),
                    name: "iPad pro",
                    secureChannelStatus: .created(preKeyAvailable: true),
                    expirationDate: Date(timeIntervalSinceNow: 1_000),
                    latestRegistrationDate: Date(timeIntervalSinceNow: -500),
                    ownedIdentityIsActive: true),
                actions: OwnedDeviceViewActions())
            .previewLayout(.sizeThatFits)
            .padding()

            OwnedDeviceView(
                ownedDevice: OwnedDeviceViewModelForPreviews(
                    ownedCryptoId: ownedCryptoIds[0],
                    deviceIdentifier: Data(repeating: 0, count: 16),
                    name: "iPhone 14",
                    secureChannelStatus: .currentDevice,
                    expirationDate: nil,
                    latestRegistrationDate: nil,
                    ownedIdentityIsActive: false),
                actions: OwnedDeviceViewActions())
            .previewLayout(.sizeThatFits)
            .padding()

        }
    }
}
