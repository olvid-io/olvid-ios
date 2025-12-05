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
import ObvSystemIcon
import OlvidUtils
import ObvTypes
import ObvCrypto

@MainActor
public protocol OwnedDeviceViewDataSource {
    func getAsyncSequenceOfOwnedDeviceViewModel(_ view: OwnedDeviceView, ownedDeviceIdentifier: ObvOwnedDeviceIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<OwnedDeviceView.Model>)
    func finishAsyncSequenceOfOwnedDeviceViewModel(_ view: OwnedDeviceView, streamUUID: UUID)
}

@MainActor
public protocol OwnedDeviceViewActions {
    func userWantsToUpdateOwnedDeviceName(_ view: OwnedDeviceView, ownedDeviceIdentifier: ObvOwnedDeviceIdentifier, newName: String) async throws
    func userWantsToDeactivateOtherOwnedDevice(_ view: OwnedDeviceView, otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier) async throws
    func userWantsToRestartChannelCreationWithOtherOwnedDevice(_ view: OwnedDeviceView, otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier) async throws
    func userRequestedSettingUnexpiringDevice(_ view: OwnedDeviceView, identifierOfOwnedDeviceToKeepActive: ObvOwnedDeviceIdentifier) async throws
}

@MainActor
public protocol OwnedDeviceViewNavigation {
    func userWantsToSeeSubscriptionPlans(_ view: OwnedDeviceView)
}


public struct OwnedDeviceView: View {
    
    let ownedDeviceIdentifier: ObvOwnedDeviceIdentifier
    let dataSource: any OwnedDeviceViewDataSource
    let actions: any OwnedDeviceViewActions
    let navigation: any OwnedDeviceViewNavigation
    
    @State private var loadingState: ModelLoadingState = .loading
    
    private var ownedCryptoId: ObvCryptoId {
        ownedDeviceIdentifier.ownedCryptoId
    }
    
    public struct Model: Sendable, Equatable {
        let ownedDeviceName: String
        let secureChannelStatus: SecureChannelStatus
        let latestRegistrationDate: Date?
        let ownedIdentityIsActive: Bool
        let expiration: Expiration? // Set iff the device expires
        let ownedIdentityEffectiveAPIPermissionsContainsMultidevice: Bool
        
        public struct Expiration: Sendable, Equatable {
            let date: Date
            let deviceWithoutExpiration: DeviceWithoutExpiration? // Expected to be non-nil: if this device expires, there must be one that does not
            public init(date: Date, deviceWithoutExpiration: DeviceWithoutExpiration?) {
                self.date = date
                self.deviceWithoutExpiration = deviceWithoutExpiration
            }
            
            public struct DeviceWithoutExpiration: Sendable, Equatable {
                let deviceUID: UID
                let deviceName: String
                public init(deviceUID: UID, deviceName: String) {
                    self.deviceUID = deviceUID
                    self.deviceName = deviceName
                }
            }
        }
        
        public init(ownedDeviceName: String,
                    secureChannelStatus: SecureChannelStatus,
                    latestRegistrationDate: Date?,
                    ownedIdentityIsActive: Bool,
                    expiration: Expiration?,
                    ownedIdentityEffectiveAPIPermissionsContainsMultidevice: Bool) {
            self.ownedDeviceName = ownedDeviceName
            self.secureChannelStatus = secureChannelStatus
            self.latestRegistrationDate = latestRegistrationDate
            self.ownedIdentityIsActive = ownedIdentityIsActive
            self.expiration = expiration
            self.ownedIdentityEffectiveAPIPermissionsContainsMultidevice = ownedIdentityEffectiveAPIPermissionsContainsMultidevice
        }
        
        var expirationDate: Date? {
            self.expiration?.date
        }
        
        var isCurrentDevice: Bool {
            secureChannelStatus == .currentDevice
        }
        
        public enum SecureChannelStatus: Sendable, Equatable {
            case currentDevice
            case creationInProgress(preKeyAvailable: Bool)
            case created(preKeyAvailable: Bool)
            
            public var isPreKeyAvailable: Bool? {
                switch self {
                case .currentDevice:
                    return nil
                case .creationInProgress(preKeyAvailable: let preKeyAvailable),
                        .created(preKeyAvailable: let preKeyAvailable):
                    return preKeyAvailable
                }
            }

        }
    }
    
    @State private var isAlertForChangingOwnedDeviceNamePresented: Bool = false
    
    @State private var deviceNameForRenaming: String = ""
    
    enum ModelLoadingState {
        case loading
        case loaded(Model)
        var model: Model? {
            switch self {
            case .loading: return nil
            case .loaded(let model): return model
            }
        }
    }
    
    private func userWantsToRenameThisDevice() {
        guard let model = loadingState.model else { return }
        deviceNameForRenaming = model.ownedDeviceName
        isAlertForChangingOwnedDeviceNamePresented = true
    }
    
    private func userConfirmedNewDeviceName() {
        guard let newName = self.deviceNameForRenaming.trimmingWhitespacesAndNewlines().mapToNilIfZeroLength() else { return }
        Task {
            try await actions.userWantsToUpdateOwnedDeviceName(self, ownedDeviceIdentifier: ownedDeviceIdentifier, newName: newName)
        }
    }
    
    @State private var isDeactivatingThisOtherOwnedDevice: Bool = false
    @State private var isKeepingDeviceActive: Bool = false
    @State private var isRecreatingSecureChannel: Bool = false
    
    private var isInterfaceDisabled: Bool {
        isDeactivatingThisOtherOwnedDevice || isKeepingDeviceActive || isRecreatingSecureChannel
    }
    
    private func userWantsToKeepDeviceActive() {
        guard let model = loadingState.model else { return }
        
        // If the device is not active, this request makes no sense.
        
        guard model.ownedIdentityIsActive else { assertionFailure(); return }
        
        // If the device requested has no expiry, this request makes no sense.

        guard let expiration = model.expiration else { assertionFailure(); return }

        // We have two cases to consider: either the owned identity is allowed to have multiple devices, or not.

        if model.ownedIdentityEffectiveAPIPermissionsContainsMultidevice {
            
            // Since the owned identity is allowed to have multiple devices, keeping this device active will have no impact on other devices.
            // Therefore, no need to alert the user, we can process the request immediately.

            return doKeepDeviceActiveNow()
            
        } else {
            
            // Since the owned identity is not allowed to have multiple device, keeping this device active will necessarily transfer the expiration to the device that currently has no expiration.
            
            guard let deviceWithoutExpiration = expiration.deviceWithoutExpiration else {
                // We did not find a device with no expiration, which is unexpected. In production, we process the user request immediately.
                return doKeepDeviceActiveNow()
            }

            // If we reach this point, we alert the user, allowing her to decide whether she wants to indeed keep the device active (and add an expiration to the other device) or not.

            let model: PermuteDeviceExpirationView.Model = .init(
                ownedCryptoId: ownedCryptoId,
                deviceToKeepActive: .init(
                    deviceUID: ownedDeviceIdentifier.deviceUID,
                    name: model.ownedDeviceName),
                deviceWithoutExpiration: .init(
                    deviceUID: deviceWithoutExpiration.deviceUID,
                    name: deviceWithoutExpiration.deviceName))
            
            isPermuteDeviceExpirationViewPresented = model
            
        }

    }
    
    @State private var isPermuteDeviceExpirationViewPresented: PermuteDeviceExpirationView.Model? = nil

    /// Helper method for `userWantsToKeepDeviceActive()`. Also called when the user confirms from the `PermuteDeviceExpirationView` that this device should remain active.
    private func doKeepDeviceActiveNow() {
        withAnimation { isKeepingDeviceActive = true }
        Task {
            defer { withAnimation { isKeepingDeviceActive = false } }
            try await actions.userRequestedSettingUnexpiringDevice(self, identifierOfOwnedDeviceToKeepActive: ownedDeviceIdentifier)
        }
    }
    
    private func userWantsToDeactivateOtherOwnedDevice() {
        withAnimation { isDeactivatingThisOtherOwnedDevice = true }
        Task {
            defer { withAnimation { isDeactivatingThisOtherOwnedDevice = false } }
            try await actions.userWantsToDeactivateOtherOwnedDevice(self, otherOwnedDeviceIdentifier: ownedDeviceIdentifier)
        }
    }
    
    private func userWantsToRestartChannelCreationWithThisOwnedDevice() {
        withAnimation { isRecreatingSecureChannel = true }
        Task {
            defer { withAnimation { isRecreatingSecureChannel = false } }
            try await actions.userWantsToRestartChannelCreationWithOtherOwnedDevice(self, otherOwnedDeviceIdentifier: ownedDeviceIdentifier)
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

    
    private var textForPreKeyStatus: String {
        guard let model = loadingState.model else { return "" }
        if model.secureChannelStatus.isPreKeyAvailable == true {
            return String(localizedInThisBundle: "PRE_KEY_IS_AVAILABLE_FOR_OWNED_DEVICE")
        } else {
            return String(localizedInThisBundle: "PRE_KEY_IS_NOT_AVAILABLE_FOR_OWNED_DEVICE")
        }
    }

    private var systemIconForPreKeyStatus: SystemIcon {
        if loadingState.model?.secureChannelStatus.isPreKeyAvailable == true {
            return .key
        } else {
            return .keySlash
        }
    }

    private var systemIconColorForPreKeyStatus: Color {
        if loadingState.model?.secureChannelStatus.isPreKeyAvailable == true {
            return Color(UIColor.systemGreen)
        } else {
            return .primary
        }
    }

    private var textForSecureChannelStatus: String {
        guard let model = loadingState.model else { return "" }
        switch model.secureChannelStatus {
        case .currentDevice:
            return String(localizedInThisBundle: "CURRENT_DEVICE")
        case .creationInProgress:
            return String(localizedInThisBundle: "SECURE_CHANNEL_CREATION_IN_PROGRESS")
        case .created:
            return String(localizedInThisBundle: "SECURE_CHANNEL_CREATED")
        }
    }

    private var systemIconForSecureChannelStatus: SystemIcon {
        switch loadingState.model?.secureChannelStatus {
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
        switch loadingState.model?.secureChannelStatus {
        case .creationInProgress, .none, .currentDevice:
            return .primary
        case .created:
            return .green
        }
    }
    
    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfOwnedDeviceViewModel(self, ownedDeviceIdentifier: ownedDeviceIdentifier)
            defer { dataSource.finishAsyncSequenceOfOwnedDeviceViewModel(self, streamUUID: streamUUID) }
            for await receivedModel in stream {
                switch loadingState {
                case .loading:
                    loadingState = .loaded(receivedModel)
                case .loaded:
                    withAnimation { loadingState = .loaded(receivedModel) }
                }
            }
        } catch {
            assertionFailure()
        }
    }

    public var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                
                switch loadingState {
                case .loading:
                    ObvCenteredProgressView()
                    
                case .loaded(let model):
                    
                    // Title
                    
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: model.ownedDeviceName)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(nil)
                        if model.isCurrentDevice {
                            Text("CURRENT_DEVICE_LOWERCAES_WITH_PARENTHESES")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(verbatim: String("(\(ownedDeviceIdentifier.deviceUID.hexString().prefix(4)))"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8.0)
                    .padding(.trailing)
                    
                    // Button for renaming this device
                    
                    Button(action: userWantsToRenameThisDevice) {
                        InternalLabel(String(localizedInThisBundle: "RENAME_DEVICE"),
                                      systemIcon: .rectangleAndPencilAndEllipsis,
                                      systemIconIconWidth: heuristicIconSize,
                                      systemIconColor: Color(UIColor.systemBlue),
                                      labelColor: Color(UIColor.systemBlue))
                    }
                    .padding(.bottom, 8.0)
                    .padding(.trailing)
                    
                    // Last online date
                    
                    if let latestRegistrationDate = model.latestRegistrationDate, model.secureChannelStatus != .currentDevice {
                        InternalLabel(String(localizedInThisBundle: "DEVICE_LAST_ONLINE_\(latestRegistrationDate.relativeFormatted)"),
                                      systemIcon: .eyes,
                                      systemIconIconWidth: heuristicIconSize,
                                      systemIconColor: Color(UIColor.systemGreen))
                        .padding(.bottom, 8.0)
                        .padding(.trailing)
                    }
                    
                    // Divider
                    
                    Divider()
                        .padding(.leading, heuristicIconSize + 8)
                        .padding(.bottom, 8.0)
                    
                    // Deactivation date
                    
                    Group {
                        if !model.ownedIdentityIsActive {
                            InternalLabel(String(localizedInThisBundle: "DEVICE_DEACTIVATED"),
                                          systemIcon: .poweroff,
                                          systemIconIconWidth: heuristicIconSize,
                                          systemIconColor: Color(UIColor.systemRed))
                        } else if let expirationDate = model.expirationDate {
                            InternalLabel(String(localizedInThisBundle: "DEVICE_DEACTIVATED_\(expirationDate.relativeFormatted)"),
                                          systemIcon: .poweroff,
                                          systemIconIconWidth: heuristicIconSize,
                                          systemIconColor: Color(UIColor.systemRed))
                        } else {
                            InternalLabel(String(localizedInThisBundle: "DEVICE_WONT_BE_DEACTIVATED"),
                                          systemIcon: .poweroff,
                                          systemIconIconWidth: heuristicIconSize,
                                          systemIconColor: Color(UIColor.systemGreen))
                        }
                    }
                    .padding(.bottom, 8.0)
                    .padding(.trailing)
                    
                    // Button for keeping the device active
                    
                    if model.expirationDate != nil && model.ownedIdentityIsActive {
                        Button(action: userWantsToKeepDeviceActive) {
                            InternalLabel(String(localizedInThisBundle: "KEEP_THIS_DEVICE_ACTIVE"),
                                          systemIcon: .poweroff,
                                          systemIconIconWidth: heuristicIconSize,
                                          systemIconColor: Color(UIColor.systemGreen),
                                          labelColor: Color(UIColor.systemBlue))
                            .padding(.bottom, 8.0)
                        }
                        .popover(item: $isPermuteDeviceExpirationViewPresented) { isPermuteDeviceExpirationViewPresented in
                            PermuteDeviceExpirationView(
                                model: isPermuteDeviceExpirationViewPresented,
                                actions: self,
                                navigation: self)
                        }
                    }
                    
                    // Button for deactivating this device
                    
                    switch model.secureChannelStatus {
                    case .currentDevice:
                        EmptyView()
                    case .created, .creationInProgress:
                        Button(action: userWantsToDeactivateOtherOwnedDevice) {
                            InternalLabel(String(localizedInThisBundle: "REMOVE_OWNED_DEVICE"),
                                          systemIcon: .poweroff,
                                          systemIconIconWidth: heuristicIconSize,
                                          systemIconColor: Color(UIColor.systemRed),
                                          labelColor: Color(UIColor.systemRed))
                        }
                        .padding(.bottom, 8.0)
                    }
                    
                    // Secure channel & PreKey informations and actions (for other owned devices)
                    
                    switch model.secureChannelStatus {
                    case .currentDevice:
                        EmptyView()
                    case .created, .creationInProgress:
                        
                        Group {
                            
                            Divider()
                                .padding(.leading, heuristicIconSize + 8)
                                .padding(.bottom, 8.0)
                            
                            InternalLabel(textForPreKeyStatus,
                                          systemIcon: systemIconForPreKeyStatus,
                                          systemIconIconWidth: heuristicIconSize,
                                          systemIconColor: systemIconColorForPreKeyStatus)
                            .padding(.bottom, 8.0)
                            
                            // Secure channel status (for other owned devices)
                            
                            InternalLabel(textForSecureChannelStatus,
                                          systemIcon: systemIconForSecureChannelStatus,
                                          systemIconIconWidth: heuristicIconSize,
                                          systemIconColor: colorForSecureChannelStatus)
                            .padding(.bottom, 8.0)
                            
                            // Button for reacreating channel
                            
                            switch loadingState.model?.secureChannelStatus {
                            case .currentDevice:
                                EmptyView()
                            case .created, .creationInProgress, .none:
                                Button(action: userWantsToRestartChannelCreationWithThisOwnedDevice) {
                                    InternalLabel(String(localizedInThisBundle: "RECREATE_SECURE_CHANNEL_WITH_THIS_DEVICE"),
                                                  systemIcon: .restartCircle,
                                                  systemIconIconWidth: heuristicIconSize,
                                                  systemIconColor: Color(UIColor.systemBlue),
                                                  labelColor: Color(UIColor.systemBlue))
                                }
                                .padding(.bottom, 8.0)
                            }
                            
                        }
                        
                    }
                    
                }
                
            }
            .padding([.leading, .vertical])
            .opacity(isInterfaceDisabled ? 0.5 : 1.0)
            
            if isDeactivatingThisOtherOwnedDevice {
                HStack {
                    ProgressView().progressViewStyle(.circular).tint(.white)
                    Text("DEACTIVATING...")
                }
                .foregroundStyle(.white)
                .padding()
                .background(Capsule().fill(Color.red))
            }
            
            if isKeepingDeviceActive {
                HStack {
                    ProgressView().progressViewStyle(.circular).tint(.white)
                    Text("KEEPING_THIS_DEVICE_ACTIVE...")
                }
                .foregroundStyle(.white)
                .padding()
                .background(Capsule().fill(Color.blue))
            }

            if isRecreatingSecureChannel {
                HStack {
                    ProgressView().progressViewStyle(.circular).tint(.white)
                    Text("RECREATING_SECURE_CHANNEL...")
                }
                .foregroundStyle(.white)
                .padding()
                .background(Capsule().fill(Color.blue))
            }

        }
        .disabled(isInterfaceDisabled)
        .task(onTask)
        .alert(String(localizedInThisBundle: "CHOOSE_DEVICE_NAME"), isPresented: $isAlertForChangingOwnedDeviceNamePresented) {
            TextField(String(localizedInThisBundle: "CHOOSE_DEVICE_NAME"), text: $deviceNameForRenaming)
            Button(String(localizedInThisBundle: "CANCEL"), action: {})
            Button(String(localizedInThisBundle: "OK"), action: userConfirmedNewDeviceName)
                .disabled(deviceNameForRenaming.trimmingWhitespacesAndNewlines().mapToNilIfZeroLength() == nil)
        }
    }
    
}


extension OwnedDeviceView: PermuteDeviceExpirationViewActions {
    
    func userRequestedSettingUnexpiringDevice(_ view: PermuteDeviceExpirationView, identifierOfOwnedDeviceToKeepActive: ObvTypes.ObvOwnedDeviceIdentifier) async throws {
        try await actions.userRequestedSettingUnexpiringDevice(self, identifierOfOwnedDeviceToKeepActive: identifierOfOwnedDeviceToKeepActive)
    }
    
}


extension OwnedDeviceView: PermuteDeviceExpirationViewNavigation {
    
    func userWantsToSeeSubscriptionPlans(_ view: PermuteDeviceExpirationView) {
        navigation.userWantsToSeeSubscriptionPlans(self)
    }
    
    func permuteDeviceExpirationViewShouldBeDismissed(_ view: PermuteDeviceExpirationView) {
        isPermuteDeviceExpirationViewPresented = nil
    }
        
}

// MARK: - InternalLabel

fileprivate struct InternalLabel: View {
    
    let label: String
    let systemIcon: SystemIcon
    let systemIconIconWidth: CGFloat
    let systemIconColor: Color
    let labelColor: Color
    
    init(_ label: String, systemIcon: SystemIcon, systemIconIconWidth: CGFloat, systemIconColor: Color = .primary, labelColor: Color = .primary) {
        self.label = label
        self.systemIcon = systemIcon
        self.systemIconIconWidth = systemIconIconWidth
        self.systemIconColor = systemIconColor
        self.labelColor = labelColor
    }
    
    var body: some View {
        Label {
            Text(label)
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

#if DEBUG

private final class DataSourceAndActionsForPreviews {}

extension DataSourceAndActionsForPreviews: OwnedDeviceViewDataSource {
    
    func getAsyncSequenceOfOwnedDeviceViewModel(_ view: OwnedDeviceView, ownedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<OwnedDeviceView.Model>) {
        let stream = AsyncStream<OwnedDeviceView.Model> { (continuation: AsyncStream<OwnedDeviceView.Model>.Continuation) in
            Task {
                let model: OwnedDeviceView.Model = .init(
                    ownedDeviceName: "Device name",
                    secureChannelStatus: .created(preKeyAvailable: true),
                    latestRegistrationDate: Date.now.addingTimeInterval(-.init(hours: 2)),
                    ownedIdentityIsActive: true,
                    expiration: .init(date: Date.now.addingTimeInterval(.init(days: 2)),
                                      deviceWithoutExpiration: .init(deviceUID: UID(uid: .init(repeating: 0x77, count: UID.length))!,
                                                                     deviceName: "Other device name")),
                    ownedIdentityEffectiveAPIPermissionsContainsMultidevice: false)
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOwnedDeviceViewModel(_ view: OwnedDeviceView, streamUUID: UUID) {}
    
}

extension DataSourceAndActionsForPreviews: OwnedDeviceViewActions {
    
    func userRequestedSettingUnexpiringDevice(_ view: OwnedDeviceView, identifierOfOwnedDeviceToKeepActive: ObvTypes.ObvOwnedDeviceIdentifier) async throws {
        try await Task.sleep(seconds: 2)
    }
    
    func userWantsToDeactivateOtherOwnedDevice(_ view: OwnedDeviceView, otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier) async throws {
        try await Task.sleep(seconds: 2)
    }
    
    func userWantsToUpdateOwnedDeviceName(_ view: OwnedDeviceView, ownedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier, newName: String) async throws {
        print("User wants to update the name of the device to '\(newName)'")
    }
    
    func userWantsToRestartChannelCreationWithOtherOwnedDevice(_ view: OwnedDeviceView, otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier) async throws {
        try await Task.sleep(seconds: 2)
    }
    
}

extension DataSourceAndActionsForPreviews: OwnedDeviceViewNavigation {
    
    func userWantsToSeeSubscriptionPlans(_ view: OwnedDeviceView) {
        print("User wants to see the subscription plans")
    }
    
}

@MainActor
private let dataSourceAndActionsForPreviews = DataSourceAndActionsForPreviews()

#Preview {
    VStack {
        Spacer()
        ObvCardView(padding: 0) {
            OwnedDeviceView(ownedDeviceIdentifier: .init(ownedCryptoId: .sampleOwnedCryptoId, deviceUID: UID.zero),
                            dataSource: dataSourceAndActionsForPreviews,
                            actions: dataSourceAndActionsForPreviews,
                            navigation: dataSourceAndActionsForPreviews)
        }
        Spacer()
    }
    .background(Color(.red))
}

#endif
