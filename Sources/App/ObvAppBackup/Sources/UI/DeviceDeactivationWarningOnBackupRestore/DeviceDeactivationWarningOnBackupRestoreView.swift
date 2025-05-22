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
import ObvSystemIcon
import ObvCrypto
import ObvAppTypes


@MainActor
final class DeviceDeactivationWarningOnBackupRestoreViewModel: ObservableObject {
    
    let profileBackupFromServerToRestore: ObvProfileBackupFromServer
    @Published fileprivate(set) var deviceDeactivationConsequence: ObvDeviceDeactivationConsequence
    
    init(profileBackupFromServerToRestore: ObvProfileBackupFromServer, deviceDeactivationConsequence: ObvDeviceDeactivationConsequence) {
        self.profileBackupFromServerToRestore = profileBackupFromServerToRestore
        self.deviceDeactivationConsequence = deviceDeactivationConsequence
    }
    
}


protocol DeviceDeactivationWarningOnBackupRestoreViewActionsProtocol: AnyObject {
    
    /// This method will present a flow allowing the user to subscribe to Olvid+. It will return only when the user is done with the flow. It returns the new value
    /// of `ObvDeviceDeactivationConsequence`.
    @MainActor func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(ownedCryptoIdentity: ObvOwnedCryptoIdentity) async throws -> ObvDeviceDeactivationConsequence
    
    @MainActor func userConfirmedSheWantsToRestoreProfileBackupNow(profileBackupFromServer: ObvProfileBackupFromServer) async throws
    @MainActor func userWantsToCancelProfileRestoration()
    
}


struct DeviceDeactivationWarningOnBackupRestoreView: View {
    
    @ObservedObject var model: DeviceDeactivationWarningOnBackupRestoreViewModel
    let actions: DeviceDeactivationWarningOnBackupRestoreViewActionsProtocol
        
    @State private var disabled = false
    @State private var showWaitingIndicator: Bool = false

    @State private var errorOnRestore: Error?
    @State private var presentErrorOnRestoreAlert: Bool = false


    private var displayName: String {
        let coreDetails = model.profileBackupFromServerToRestore.parsedData.coreDetails
        return coreDetails.getFullDisplayName()
    }
    
    
    private struct TopIconView: View {
        let deviceDeactivationConsequence: ObvDeviceDeactivationConsequence
        private var systemIcon: SystemIcon {
            switch deviceDeactivationConsequence {
            case .noDeviceDeactivation:
                return .checkmark
            case .deviceDeactivations:
                return .exclamationmarkTriangleFill
            }
        }
        var body: some View {
            HStack {
                Spacer(minLength: 0)
                ZStack(alignment: .center) {
                    RoundedRectangle(cornerSize: CGSize(width: 45, height: 45), style: .continuous)
                        .frame(width: 109, height: 109)
                        .foregroundStyle(Color(UIColor.systemFill))
                    Image(systemIcon: systemIcon)
                        .font(.system(size: 50, weight: .bold))
                        .foregroundStyle(Color(UIColor.tertiaryLabel))
                }
                Spacer(minLength: 0)
            }
        }
    }
    
    
    private func userTappedRestoreProfileButton() {
        disabled = true
        withAnimation {
            showWaitingIndicator = true
        }
        Task {
            defer {
                disabled = false
                withAnimation {
                    showWaitingIndicator = false
                }
            }
            do {
                try await actions.userConfirmedSheWantsToRestoreProfileBackupNow(profileBackupFromServer: model.profileBackupFromServerToRestore)
            } catch {
                errorOnRestore = error
                presentErrorOnRestoreAlert = true
            }
        }
    }
    
    private func userTappedKeepThemAllWithOlvidPlusButton() {
        disabled = true
        Task {
            do {
                let newDeviceDeactivationConsequence = try await actions.userWantsToKeepAllDevicesActiveThanksToOlvidPlus(ownedCryptoIdentity: model.profileBackupFromServerToRestore.parsedData.ownedCryptoIdentity)
                withAnimation {
                    model.deviceDeactivationConsequence = newDeviceDeactivationConsequence
                }
                disabled = false
            } catch {
                disabled = false
            }
        }
    }
    
    private func userTappedCancelButton() {
        disabled = true
        actions.userWantsToCancelProfileRestoration()
    }

    var body: some View {
        List {
            
            TopIconView(deviceDeactivationConsequence: model.deviceDeactivationConsequence)
                .listRowSeparator(.hidden)
                .padding(.bottom)
            
            switch model.deviceDeactivationConsequence {
                
            case .noDeviceDeactivation:
                
                Text("SINCE_YOU_HAVE_A_MULTIDEVICE_SUBSRIPTION_ALL_YOUR_PREVIOUS_DEVICES_WILL_STAY_ACTIVE_YOU_CAN_RESTORE_YOUR_PROFILE_\(displayName)")
                    .font(.body)
                    .listRowSeparator(.hidden)
                
            case .deviceDeactivations(let deactivatedDevices):
                
                Text("BY_RESTORING_YOUR_PROFILE_\(displayName)_YOU_WILL_DEACTIVATE_OTHER_\(deactivatedDevices.count)_DEVICES")
                    .font(.body)
                    .listRowSeparator(.hidden)

                ForEach(deactivatedDevices, id: \.identifier) { device in
                    HStack {
                        DeviceImageView(platform: device.platform)
                        Text(device.deviceName)
                        Spacer()
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(UIColor.secondarySystemFill)))
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init(top: 0, leading: 16, bottom: 16, trailing: 16))
                }
                
                Label {
                    Text("YOU_CAN_CHOOSE_ACTIVE_DEVICE_AFTER_RESTORATION")
                } icon: {
                    Image(systemIcon: .infoCircle)
                }
                .listRowSeparator(.hidden)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom)

            }
            
            VStack {
                
                Button(action: userTappedRestoreProfileButton) {
                    HStack {
                        Spacer(minLength: 0)
                        Text("RESTORE_MY_PROFILE")
                        if showWaitingIndicator {
                            ProgressView()
                        }
                        Spacer(minLength: 0)
                    }.padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                
                switch model.deviceDeactivationConsequence {
                case .noDeviceDeactivation:
                    EmptyView()
                case .deviceDeactivations:
                    Button(action: userTappedKeepThemAllWithOlvidPlusButton) {
                        HStack {
                            Spacer(minLength: 0)
                            Text("KEEP_THEM_ALL_WITH_OLVID_PLUS")
                            Spacer(minLength: 0)
                        }.padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button(action: userTappedCancelButton) {
                    HStack {
                        Spacer(minLength: 0)
                        Text("CANCEL")
                        Spacer(minLength: 0)
                    }.padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                
            }
            .disabled(disabled)
            .listRowSeparator(.hidden)
            .alert(String(localizedInThisBundle: "WE_COULD_NOT_RESTORE_THIS_PROFILE"), isPresented: $presentErrorOnRestoreAlert) {
                Button.init(action: {}) {
                    Text("OK")
                }
            } message: {
                Text(errorOnRestore?.localizedDescription ?? String(localizedInThisBundle: "AN_ERROR_OCCURED"))
            }

        }
        .listStyle(.plain)
        .listRowSpacing(0)
    }
    
}



// MARK: - Previews

#if DEBUG

@MainActor
let modelForPreviews = DeviceDeactivationWarningOnBackupRestoreViewModel(
    profileBackupFromServerToRestore: ProfileBackupsForPreviews.profileBackups.first!,
    deviceDeactivationConsequence: .deviceDeactivations(deactivatedDevices: [
        OlvidPlatformAndDeviceName(identifier: Data(repeating: 0, count: 20), deviceName: "Alice's iPad", platform: .iPad),
        OlvidPlatformAndDeviceName(identifier: Data(repeating: 0, count: 20), deviceName: "Alice's iPad", platform: .iPad),
    ])
)


@MainActor
private final class ActionsForPreviews: DeviceDeactivationWarningOnBackupRestoreViewActionsProtocol {

    func userWantsToCancelProfileRestoration() {}
    
    func userConfirmedSheWantsToRestoreProfileBackupNow(profileBackupFromServer: ObvTypes.ObvProfileBackupFromServer) async throws {
        try? await Task.sleep(seconds: 2)
        throw ObvErrorForPreviews.someError
    }
    
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(ownedCryptoIdentity: ObvOwnedCryptoIdentity) async throws -> ObvDeviceDeactivationConsequence {
        try await Task.sleep(seconds: 2)
        // Simulate a purchase made by the user
        return .noDeviceDeactivation
        // Simulate the situation where the user comes back with no purchase
//        let deactivatedDevices: [OlvidPlatformAndDeviceName] = [
//            OlvidPlatformAndDeviceName(identifier: Data(repeating: 0, count: 20), deviceName: "Alice's iPad", platform: .iPad),
//            OlvidPlatformAndDeviceName(identifier: Data(repeating: 0, count: 20), deviceName: "Alice's iPad", platform: .iPad),
//        ]
//        return .deviceDeactivations(deactivatedDevices: deactivatedDevices)
    }
    
    enum ObvErrorForPreviews: Error {
        case someError
    }
    
}

#Preview {
    DeviceDeactivationWarningOnBackupRestoreView(model: modelForPreviews, actions: ActionsForPreviews())
}

#endif
