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
import ObvCrypto


@MainActor
protocol PermuteDeviceExpirationViewActions {
    func userRequestedSettingUnexpiringDevice(_ view: PermuteDeviceExpirationView, identifierOfOwnedDeviceToKeepActive: ObvOwnedDeviceIdentifier) async throws
}


@MainActor
protocol PermuteDeviceExpirationViewNavigation {
    func userWantsToSeeSubscriptionPlans(_ view: PermuteDeviceExpirationView)
    func permuteDeviceExpirationViewShouldBeDismissed(_ view: PermuteDeviceExpirationView)
}


public struct PermuteDeviceExpirationView: View {

    let model: Model
    let actions: any PermuteDeviceExpirationViewActions
    let navigation: any PermuteDeviceExpirationViewNavigation
    
    public struct Model: Sendable, Equatable, Identifiable {
        let ownedCryptoId: ObvCryptoId
        let deviceToKeepActive: Device
        let deviceWithoutExpiration: Device
                
        public struct Device: Sendable, Equatable, Identifiable {
            let deviceUID: UID
            let name: String
            public var id: Data {
                deviceUID.raw
            }
        }
        
        public var id: Data {
            ownedCryptoId.getIdentity()  + deviceToKeepActive.id + deviceWithoutExpiration.id
        }
        
    }
    
    @State private var isSettingUnexpiringDevice: Bool = false
    
    private var isInterfaceDisabled: Bool {
        isSettingUnexpiringDevice
    }
    
    private var identifierOfOwnedDeviceToKeepActive: ObvOwnedDeviceIdentifier {
        return .init(ownedCryptoId: model.ownedCryptoId, deviceUID: model.deviceToKeepActive.deviceUID)
    }
    
    private func userConfirmed() {
        isSettingUnexpiringDevice = true
        Task {
            defer { isSettingUnexpiringDevice = false }
            try await actions.userRequestedSettingUnexpiringDevice(self, identifierOfOwnedDeviceToKeepActive: identifierOfOwnedDeviceToKeepActive)
            navigation.permuteDeviceExpirationViewShouldBeDismissed(self)
        }
    }
    
    private func userWantsToSeeSubscriptionPlans() {
        navigation.userWantsToSeeSubscriptionPlans(self)
    }
    
    private func userWantsToCancel() {
        navigation.permuteDeviceExpirationViewShouldBeDismissed(self)
    }
    
    private var navigationTitle: String {
        String(localizedInThisBundle: "PERMUTE_DEVICE_EXPIRATION_CONFIRMATION_ALERT_TITLE")
    }
    
    public var body: some View {
        ScrollView {
            VStack {
                
                // Title
                
                Text("PERMUTE_DEVICE_EXPIRATION_CONFIRMATION_ALERT_TITLE")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                .padding(.top, 32)
                
                // Explanation
                
                ObvCardView {
                    HStack {
                        Text("KEEP_DEVICE_\(model.deviceToKeepActive.name)_ACTIVE_AND_ACCEPT_TO_DEACTIVATE_DEVICE_\(model.deviceWithoutExpiration.name)")
                            .font(.body)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                        Spacer()
                    }.padding()
                }
                .padding(.vertical)
                
                // Buttons
                
                OlvidButtonNew(action: userConfirmed) {
                    HStack {
                        if isSettingUnexpiringDevice {
                            ProgressView().progressViewStyle(.circular).foregroundStyle(.white)
                        }
                        Label {
                            Text("DEACTIVATE_\(model.deviceWithoutExpiration.name)_AND_ACTIVATE_\(model.deviceToKeepActive.name)")
                        } icon: {
                            Image(systemIcon: .arrow2Squarepath)
                        }
                    }
                }
                
                OlvidButtonNew(action: userWantsToSeeSubscriptionPlans) {
                    Label {
                        Text("See subscription plans")
                    } icon: {
                        Image(systemIcon: .storefront)
                    }
                }
                
                OlvidButtonNew(action: userWantsToCancel, style: .glassOrBordered) {
                    Text("CANCEL")
                }
                

            }.padding()
        }
        .disabled(isInterfaceDisabled)
        .background(Color(UIColor.systemGroupedBackground))
    }
    
}



// MARK: - Previews

#if DEBUG

@MainActor
private final class ActionsForPreviews {}

extension ActionsForPreviews: PermuteDeviceExpirationViewActions {
    
    func userRequestedSettingUnexpiringDevice(_ view: PermuteDeviceExpirationView, identifierOfOwnedDeviceToKeepActive: ObvOwnedDeviceIdentifier) async throws {
        try await Task.sleep(seconds: 3)
    }

}

extension ActionsForPreviews: PermuteDeviceExpirationViewNavigation {
    
    func userWantsToSeeSubscriptionPlans(_ view: PermuteDeviceExpirationView) {
        print("User wants to see subscription plans")
    }
    
    func permuteDeviceExpirationViewShouldBeDismissed(_ view: PermuteDeviceExpirationView) {
        print("PermuteDeviceExpirationView should be dismissed")
    }
    
}

@MainActor
private let modelForPreviews: PermuteDeviceExpirationView.Model = .init(
    ownedCryptoId: .sampleOwnedCryptoId,
    deviceToKeepActive: .init(deviceUID: UID.zero,
                              name: "Name of device to keep active"),
    deviceWithoutExpiration: .init(deviceUID: UID(uid: .init(repeating: 0x01, count: UID.length))!,
                                   name: "Name of device without expiration"))

@MainActor
private let actionsForPreviews = ActionsForPreviews()

#Preview {
    PermuteDeviceExpirationView(model: modelForPreviews,
                                actions: actionsForPreviews,
                                navigation: actionsForPreviews)
}

#endif
