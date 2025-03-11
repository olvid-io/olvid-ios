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
import StoreKit
import ObvTypes
import ObvCrypto
import Contacts
import ObvSubscription


protocol ChooseDeviceToKeepActiveViewActionsProtocol: AnyObject, SubscriptionPlansViewActionsProtocol {
    
    func userChoseDeviceToKeepActive(ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, enteredSAS: ObvOwnedIdentityTransferSas, ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult, currentDeviceIdentifier: Data, targetDeviceName: String, deviceToKeepActive: ObvOwnedDeviceDiscoveryResult.Device?, protocolInstanceUID: UID) async
    func refreshDeviceDiscovery(for ownedCryptoId: ObvCryptoId) async throws -> ObvOwnedDeviceDiscoveryResult
    
}


final class ChooseDeviceToKeepActiveViewModel: ChooseDeviceToKeepActiveViewModelProtocol {
    
    let ownedCryptoId: ObvCryptoId
    let ownedDetails: CNContact
    let enteredSAS: ObvOwnedIdentityTransferSas
    @Published var ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult
    let currentDeviceIdentifier: Data
    let targetDeviceName: String
    let protocolInstanceUID: UID

    init(ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, enteredSAS: ObvOwnedIdentityTransferSas, ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult, currentDeviceIdentifier: Data, targetDeviceName: String, protocolInstanceUID: UID) {
        self.ownedCryptoId = ownedCryptoId
        self.ownedDetails = ownedDetails
        self.enteredSAS = enteredSAS
        self.ownedDeviceDiscoveryResult = ownedDeviceDiscoveryResult
        self.currentDeviceIdentifier = currentDeviceIdentifier
        self.targetDeviceName = targetDeviceName
        self.protocolInstanceUID = protocolInstanceUID
    }
    
    
    @MainActor
    func resetOwnedDeviceDiscoveryResult(with newObvOwnedDeviceDiscoveryResult: ObvTypes.ObvOwnedDeviceDiscoveryResult) async {
        withAnimation {
            self.ownedDeviceDiscoveryResult = newObvOwnedDeviceDiscoveryResult
        }
    }

}


protocol ChooseDeviceToKeepActiveViewModelProtocol: AnyObject, ObservableObject {
    var ownedCryptoId: ObvCryptoId { get }
    var ownedDetails: CNContact { get }
    var enteredSAS: ObvOwnedIdentityTransferSas { get }
    var ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult { get } // Published
    var currentDeviceIdentifier: Data { get }
    var targetDeviceName: String { get }
    var protocolInstanceUID: UID { get }
    
    func resetOwnedDeviceDiscoveryResult(with newObvOwnedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult) async
}


struct ChooseDeviceToKeepActiveView<Model: ChooseDeviceToKeepActiveViewModelProtocol>: View, SubscriptionPlansViewDismissActionsProtocol {
    
    let actions: ChooseDeviceToKeepActiveViewActionsProtocol
    @ObservedObject var model: Model
    @State private var selectedDevice: ObvOwnedDeviceDiscoveryResult.Device?
    @State private var isInterfaceDisabled = false
    @State private var isSubscriptionPlansViewPresented = false
    @State private var userJustSubscribedToMultidevice = false
    
    private var title: LocalizedStringKey {
        if model.ownedDeviceDiscoveryResult.isMultidevice {
            return "CHOOSE_ACTIVE_DEVICE_TITLE_WHEN_MULTIDEVICE_TRUE"
        } else {
            return "CHOOSE_ACTIVE_DEVICE_TITLE_WHEN_MULTIDEVICE_FALSE"
        }
    }

    
    private var subtitle: LocalizedStringKey {
        if model.ownedDeviceDiscoveryResult.isMultidevice {
            return "CHOOSE_ACTIVE_DEVICE_SUBTITLE_WHEN_MULTIDEVICE_TRUE"
        } else {
            return "CHOOSE_ACTIVE_DEVICE_SUBTITLE_WHEN_MULTIDEVICE_FALSE"
        }
    }
    
    
    private var sortedDevices: [ObvOwnedDeviceDiscoveryResult.Device] {
        let existingDevices = model.ownedDeviceDiscoveryResult.devices.sorted { device1, device2 in
            if device1.identifier == model.currentDeviceIdentifier { return true }
            if device2.identifier == model.currentDeviceIdentifier { return false }
            return device1.hashValue < device2.hashValue
        }
        let newDevice = ObvOwnedDeviceDiscoveryResult.Device(
            identifier: OwnedIdentityTransferSummaryView.fakeDeviceIdForNewDevice,
            expirationDate: nil,
            latestRegistrationDate: nil,
            name: model.targetDeviceName)
        return existingDevices + [newDevice]
    }
    
    
    private func titleOfKeepDeviceActiveButton(device: ObvOwnedDeviceDiscoveryResult.Device) -> LocalizedStringKey {
        if let name = device.name {
            return "KEEP_\(name)_ACTIVE"
        } else {
            return "KEEP_SELECTED_DEVICE_ACTIVE"
        }
    }
    
    
    private func proceedButtonTapped(deviceToKeepActive: ObvOwnedDeviceDiscoveryResult.Device?) {
        isInterfaceDisabled = true
        Task {
            await userChoseDeviceToKeepActive(deviceToKeepActive: deviceToKeepActive)
        }
    }
    
    
    private func userWantsToSeeMultideviceSubscriptionsOptions() {
        isSubscriptionPlansViewPresented = true
    }
    
    
    @MainActor
    private func userChoseDeviceToKeepActive(deviceToKeepActive: ObvOwnedDeviceDiscoveryResult.Device?) async {
        isInterfaceDisabled = true
        await actions.userChoseDeviceToKeepActive(
            ownedCryptoId: model.ownedCryptoId,
            ownedDetails: model.ownedDetails,
            enteredSAS: model.enteredSAS,
            ownedDeviceDiscoveryResult: model.ownedDeviceDiscoveryResult,
            currentDeviceIdentifier: model.currentDeviceIdentifier,
            targetDeviceName: model.targetDeviceName,
            deviceToKeepActive: deviceToKeepActive,
            protocolInstanceUID: model.protocolInstanceUID)
        isInterfaceDisabled = false // In case the user comes back
    }
    
    // SubscriptionPlansViewDismissActionsProtocol
    
    @MainActor
    func userWantsToDismissSubscriptionPlansView() async {
        isSubscriptionPlansViewPresented = false
    }
    
    
    func dismissSubscriptionPlansViewAfterPurchaseWasMade() async {
        await refreshDeviceDiscovery()
    }
    
    
    /// Called when the subscription view is dismissed after a purchase is made (so as to reflect the acquisition of the multi-device feature)
    /// and when the subscription view is dismissed manually (since, in that case, was cannot know whether a purchase was made or not).
    @MainActor
    private func refreshDeviceDiscovery() async {
        isInterfaceDisabled = true
        do {
            let newObvOwnedDeviceDiscoveryResult = try await actions.refreshDeviceDiscovery(for: model.ownedCryptoId)
            await model.resetOwnedDeviceDiscoveryResult(with: newObvOwnedDeviceDiscoveryResult)
            if newObvOwnedDeviceDiscoveryResult.isMultidevice {
                userJustSubscribedToMultidevice = true
            }
        } catch {
            assertionFailure(error.localizedDescription)
        }
        isInterfaceDisabled = false
    }

    
    // Body

    var body: some View {
        VStack {
            ScrollView {
                VStack {
                    
                    NewOnboardingHeaderView(title: title, subtitle: subtitle)
                        .padding(.bottom)
                    
                    if userJustSubscribedToMultidevice {
                        HStack {
                            Label {
                                Text("NO_DEVICE_WILL_EXPIRE_SINCE_YOUR_SUBSCRIPTION_INCLUDES_MULTIDEVICE")
                            } icon: {
                                Image(systemIcon: .checkmarkCircleFill)
                                    .foregroundStyle(Color(UIColor.systemGreen))
                            }
                            Spacer()
                        }
                    }
                    
                    ProgressView()
                        .opacity(isInterfaceDisabled ? 1 : 0)
                    
                    ForEach(sortedDevices) { device in
                        DeviceView(mode: model.ownedDeviceDiscoveryResult.isMultidevice ? .list : .select(selectedDevice: $selectedDevice),
                                   model: .init(device: device,
                                                currentDeviceIdentifier: model.currentDeviceIdentifier,
                                                fakeDeviceIdForNewDevice: OwnedIdentityTransferSummaryView.fakeDeviceIdForNewDevice))
                        .padding(.leading)
                        .padding(.top)
                    }
                    
                    
                }.padding(.horizontal)

                if model.ownedDeviceDiscoveryResult.isMultidevice {
                    InternalButton("VALIDATE", action: { proceedButtonTapped(deviceToKeepActive: nil) })
                        .padding()
                } else if let selectedDevice {
                    InternalButton(titleOfKeepDeviceActiveButton(device: selectedDevice), action: { proceedButtonTapped(deviceToKeepActive: selectedDevice) })
                        .padding()
                }
            }
            
            if !model.ownedDeviceDiscoveryResult.isMultidevice {
                HStack {
                    Spacer()
                    // We use a Markdown trick so as to show an in-line link instead of a button.
                    Text("DO_YOU_WANT_ALL_YOUR_DEVICE_TO_STAY_ACTIVE_[THIS_WAY](_)")
                        .environment(\.openURL, OpenURLAction { url in
                            userWantsToSeeMultideviceSubscriptionsOptions()
                            return .discarded
                        })
                    Spacer()
                }
            }
            
        }
        .disabled(isInterfaceDisabled)
        .sheet(isPresented: $isSubscriptionPlansViewPresented, onDismiss: {
            Task { await refreshDeviceDiscovery() }
        }, content: {
            let model = SubscriptionPlansViewModel(ownedCryptoId: model.ownedCryptoId, showFreePlanIfAvailable: false)
            SubscriptionPlansView(model: model, actions: actions, dismissActions: self)
        })
    }
}


// MARK: - DeviceView

private struct DeviceView: View {

    enum Mode {
        case list
        case select(selectedDevice: Binding<ObvOwnedDeviceDiscoveryResult.Device?>)
    }
    
    let mode: Mode
    let model: Model
    
    struct Model {
        let device: ObvOwnedDeviceDiscoveryResult.Device
        let currentDeviceIdentifier: Data
        let fakeDeviceIdForNewDevice: Data
    }
    
    
    private func cellTapped() {
        switch mode {
        case .list:
            return
        case .select(selectedDevice: let selectedDevice):
            selectedDevice.wrappedValue = model.device
        }
    }
    
    
    private var isSelected: Bool {
        switch mode {
        case .list:
            return false
        case .select(selectedDevice: let selectedDevice):
            return model.device == selectedDevice.wrappedValue
        }
    }
    
    
    var body: some View {
        HStack {
            Label(
                title: {
                    VStack(alignment: .leading) {
                        Text(verbatim: model.device.name ?? String(model.device.identifier.hexString().prefix(4)))
                            .font(.headline)
                        if model.device.identifier == model.currentDeviceIdentifier {
                            Text("CURRENT_DEVICE")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        } else if model.device.identifier == model.fakeDeviceIdForNewDevice {
                            Text("NEW_DEVICE")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }
                },
                icon: {
                    Image(systemIcon: .laptopcomputerAndIphone)
                }
            )
            Spacer()
            switch mode {
            case .list:
                EmptyView()
            case .select:
                Image(systemIcon: isSelected ? .checkmarkCircleFill : .circle)
                    .foregroundStyle(isSelected ? Color(UIColor.systemGreen) : .secondary)
            }
        }
        .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
        .onTapGesture(perform: cellTapped)
    }
}



// MARK: - Button used in this view only

private struct InternalButton: View {
    
    private let key: LocalizedStringKey
    private let action: () -> Void
    @Environment(\.isEnabled) var isEnabled
    
    init(_ key: LocalizedStringKey, action: @escaping () -> Void) {
        self.key = key
        self.action = action
    }
        
    var body: some View {
        Button(action: action) {
            Text(key)
                .foregroundStyle(.white)
                .padding(.horizontal, 26)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
        }
        .background(Color.blue01)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1.0 : 0.6)
    }
    
}



// MARK: - Previews

struct ChooseDeviceToKeepActiveView_Previews: PreviewProvider {
    
    private static let ownedCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)
    
    private static let enteredSAS = try! ObvOwnedIdentityTransferSas(fullSas: "12345678".data(using: .utf8)!)
    
    private static let devices: Set<ObvOwnedDeviceDiscoveryResult.Device> = Set([
        .init(identifier: UID(uid: Data(repeating: 0x01, count: UID.length))!.raw,
              expirationDate: Date(timeIntervalSinceNow: 400),
              latestRegistrationDate: Date(timeIntervalSinceNow: -200),
              name: "iPad Pro"),
        .init(identifier: UID.zero.raw,
              expirationDate: Date(timeIntervalSinceNow: 500),
              latestRegistrationDate: Date(timeIntervalSinceNow: -100),
              name: "iPhone 15"),
    ])

    private static let ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult = .init(
        devices: devices,
        isMultidevice: false)

    private static let ownedDeviceDiscoveryResultWithMultidevice: ObvOwnedDeviceDiscoveryResult = .init(
        devices: devices,
        isMultidevice: true)

    final class ActionsForPreviews: ChooseDeviceToKeepActiveViewActionsProtocol {
        func userChoseDeviceToKeepActive(ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, enteredSAS: ObvOwnedIdentityTransferSas, ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult, currentDeviceIdentifier: Data, targetDeviceName: String, deviceToKeepActive: ObvOwnedDeviceDiscoveryResult.Device?, protocolInstanceUID: UID) async {}
        func userWantsToSeeMultideviceSubscriptionsOptions() async {}
        
        func fetchSubscriptionPlans(for ownedCryptoId: ObvCryptoId, alsoFetchFreePlan: Bool) async throws -> (freePlanIsAvailable: Bool, products: [Product]) {
            try! await Task.sleep(seconds: 1)
            return (alsoFetchFreePlan, [])
        }
        
        func userWantsToStartFreeTrialNow(ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> APIKeyElements {
            try! await Task.sleep(seconds: 2)
            return .init(status: .freeTrial, permissions: [.canCall], expirationDate: Date().addingTimeInterval(.init(days: 30)))
        }
        
        func userWantsToBuy(_: Product) async -> StoreKitDelegatePurchaseResult {
            try! await Task.sleep(seconds: 2)
            return .userCancelled
        }
        
        func userWantsToRestorePurchases() async {
            try! await Task.sleep(seconds: 2)
        }

        func refreshDeviceDiscovery(for ownedCryptoId: ObvCryptoId) async throws -> ObvOwnedDeviceDiscoveryResult {
            try? await Task.sleep(seconds: 2)
            return await ownedDeviceDiscoveryResultWithMultidevice
        }
     
    }
    
    private static let actions = ActionsForPreviews()
    
    private static let ownedDetails: CNContact = {
        let details = CNMutableContact()
        details.givenName = "Steve"
        return details
    }()
    
    
    private final class ModelForPreviews: ChooseDeviceToKeepActiveViewModelProtocol {
                
        let ownedCryptoId: ObvCryptoId
        let ownedDetails: CNContact
        let enteredSAS: ObvOwnedIdentityTransferSas
        @Published var ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult
        let currentDeviceIdentifier: Data
        let targetDeviceName: String
        let protocolInstanceUID: UID

        init(ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, enteredSAS: ObvOwnedIdentityTransferSas, ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult, currentDeviceIdentifier: Data, targetDeviceName: String, protocolInstanceUID: UID) {
            self.ownedCryptoId = ownedCryptoId
            self.ownedDetails = ownedDetails
            self.enteredSAS = enteredSAS
            self.ownedDeviceDiscoveryResult = ownedDeviceDiscoveryResult
            self.currentDeviceIdentifier = currentDeviceIdentifier
            self.targetDeviceName = targetDeviceName
            self.protocolInstanceUID = protocolInstanceUID
        }
        
        func resetOwnedDeviceDiscoveryResult(with newObvOwnedDeviceDiscoveryResult: ObvTypes.ObvOwnedDeviceDiscoveryResult) async {
            withAnimation {
                self.ownedDeviceDiscoveryResult = newObvOwnedDeviceDiscoveryResult
            }
        }

    }
    
    private static let model = ModelForPreviews(
        ownedCryptoId: ownedCryptoId,
        ownedDetails: ownedDetails,
        enteredSAS: enteredSAS,
        ownedDeviceDiscoveryResult: ownedDeviceDiscoveryResult,
        currentDeviceIdentifier: UID.zero.raw,
        targetDeviceName: "New Device Name",
        protocolInstanceUID: UID.zero)

    static var previews: some View {
        ChooseDeviceToKeepActiveView(
            actions: actions,
            model: model)
    }
    
}
