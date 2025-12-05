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
public protocol ObvChooseDeviceToReactivateViewDataSource {
    func getObvChooseDeviceToReactivateViewModel(_ view: ObvChooseDeviceToReactivateView, ownedCryptoId: ObvCryptoId) async throws -> ObvChooseDeviceToReactivateView.Model
    func performOwnedDeviceDiscoveryNow(_ view: ObvChooseDeviceToReactivateView, ownedCryptoId: ObvCryptoId) async throws -> ObvOwnedDeviceDiscoveryResult
}

@MainActor
public protocol ObvChooseDeviceToReactivateViewActions {
    func userWantsToActivateCurrentDevice(_ view: ObvChooseDeviceToReactivateView, ownedCryptoId: ObvCryptoId, currentDeviceIdentifier: Data, deviceIdentifierOfOtherDeviceToDeactivate: Data?) async throws
}

@MainActor
public protocol ObvChooseDeviceToReactivateViewNavigation {
    func userWantsToDismissObvChooseDeviceToReactivateView(_ view: ObvChooseDeviceToReactivateView)
}

/// When an owned identity is inactive on the current device, the `ObvSingleOwnedIdentityView` shows a button allowing to reactivate the owned identity
/// on the current device. When tapped, this view is shown.
public struct ObvChooseDeviceToReactivateView: View {
    
    let ownedCryptoId: ObvCryptoId
    let dataSource: any ObvChooseDeviceToReactivateViewDataSource
    let actions: any ObvChooseDeviceToReactivateViewActions
    let navigation: any ObvChooseDeviceToReactivateViewNavigation
    
    public struct Model {
        let currentDeviceName: String
        let currentDeviceIdentifier: Data
        public init(currentDeviceName: String, currentDeviceIdentifier: Data) {
            self.currentDeviceName = currentDeviceName
            self.currentDeviceIdentifier = currentDeviceIdentifier
        }
    }
    
    @State private var status: Status = .initial
    
    @State private var shouldDisableButtons = false

    enum Status {
        case initial
        case queryingServer(model: Model)
        case serverAnswerReceived(model: Model, status: ServerAnswerReceivedStatus)
        case serverQueryFailed(model: Model?)
        
        enum ServerAnswerReceivedStatus {
            case noActiveDeviceFoundOnServer
            case multideviceFeatureAvailable(devicesFromServer: [DeviceCardView.Model])
            case multideviceFeatureUnavailableAndAtLeastOneNonExpiringActiveDeviceFound(devicesFromServer: [DeviceCardView.Model])
            case multideviceFeatureUnavailableAndAllActiveDevicesExpire(devicesFromServer: [DeviceCardView.Model])
        }

    }
    
    
    private func onTask() async {
        
        status = .initial

        let model: ObvChooseDeviceToReactivateView.Model
        
        do {
            model = try await dataSource.getObvChooseDeviceToReactivateViewModel(self, ownedCryptoId: ownedCryptoId)
            withAnimation { status = .queryingServer(model: model) }
        } catch {
            withAnimation { status = .serverQueryFailed(model: nil) }
            return
        }
        
        do {
            
            let discoveryResult = try await dataSource.performOwnedDeviceDiscoveryNow(self, ownedCryptoId: ownedCryptoId)
            
            let devicesFromServer: [DeviceCardView.Model] = discoveryResult.devices.map {
                .init(deviceIdentifier: $0.identifier,
                      deviceName: $0.name ?? String($0.identifier.hexString().prefix(4)),
                      expirationDate: $0.expirationDate,
                      latestRegistrationDate: $0.latestRegistrationDate)
            }
            
            let serverAnswerReceivedStatus: Status.ServerAnswerReceivedStatus
            if discoveryResult.devices.isEmpty {
                serverAnswerReceivedStatus = .noActiveDeviceFoundOnServer
            } else if discoveryResult.isMultidevice {
                serverAnswerReceivedStatus = .multideviceFeatureAvailable(devicesFromServer: devicesFromServer)
            } else if discoveryResult.devices.allSatisfy({ $0.expirationDate != nil }) {
                serverAnswerReceivedStatus = .multideviceFeatureUnavailableAndAllActiveDevicesExpire(devicesFromServer: devicesFromServer)
            } else {
                serverAnswerReceivedStatus = .multideviceFeatureUnavailableAndAtLeastOneNonExpiringActiveDeviceFound(devicesFromServer: devicesFromServer)
            }
            
            withAnimation { status = .serverAnswerReceived(model: model, status: serverAnswerReceivedStatus) }
            
        } catch {
            withAnimation { status = .serverQueryFailed(model: model) }
        }
    }
    
    @Environment(\.colorScheme) var colorScheme

    private var navigationTitle: String {
        String(localizedInThisBundle: "NAVIGATION_TITLE_DEVICE_REACTIVATION")
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    
                    switch status {
                        
                    case .initial:
                        ObvCenteredProgressView()
                        
                    case .queryingServer(model: let model):
                        QueryingServerView(model: model, actions: self)
                            .padding(.horizontal)
                        
                    case .serverAnswerReceived(model: let model, status: let serverAnswerReceivedStatus):
                        ServerAnswerReceivedView(
                            model: model,
                            serverAnswerReceivedStatus: serverAnswerReceivedStatus,
                            actions: self,
                            shouldDisableButtons: $shouldDisableButtons)
                        
                    case .serverQueryFailed(model: let model):
                        ServerQueryFailedView(
                            model: model,
                            actions: self,
                            shouldDisableButtons: $shouldDisableButtons)
                        
                    }
                                        
                }
                .padding(.vertical)
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
            }
            .background(colorScheme == .dark ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground))
        }
        .task(onTask)
    }
    
}


extension ObvChooseDeviceToReactivateView: ObvChooseDeviceToReactivateViewInternalActions {
    
    func userWantsToDismissObvChooseDeviceToReactivateView() {
        navigation.userWantsToDismissObvChooseDeviceToReactivateView(self)
    }
    
    func userWantsToActivateThisDevice(currentDeviceIdentifier: Data, deviceIdentifierOfOtherDeviceToDeactivate: Data?) {
        shouldDisableButtons = true
        Task {
            defer { shouldDisableButtons = false }
            do {
                try await actions.userWantsToActivateCurrentDevice(self,
                                                                   ownedCryptoId: ownedCryptoId,
                                                                   currentDeviceIdentifier: currentDeviceIdentifier,
                                                                   deviceIdentifierOfOtherDeviceToDeactivate: deviceIdentifierOfOtherDeviceToDeactivate)
            } catch {
                assertionFailure()
            }
        }
    }
    
}


@MainActor
private protocol ObvChooseDeviceToReactivateViewInternalActions {
    func userWantsToDismissObvChooseDeviceToReactivateView()
    func userWantsToActivateThisDevice(currentDeviceIdentifier: Data, deviceIdentifierOfOtherDeviceToDeactivate: Data?)
}

// MARK: - Internal view

extension ObvChooseDeviceToReactivateView {
    private struct ServerQueryFailedView: View {
        
        let model: ObvChooseDeviceToReactivateView.Model?
        let actions: ObvChooseDeviceToReactivateViewInternalActions
        @Binding var shouldDisableButtons: Bool

        private func userWantsToActivateThisDevice() {
            guard let model else { return }
            actions.userWantsToActivateThisDevice(currentDeviceIdentifier: model.currentDeviceIdentifier, deviceIdentifierOfOtherDeviceToDeactivate: nil)
        }
        
        var body: some View {
            ScrollView {
                VStack {
                    
                    TitleView(title: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_FAILED_TITLE")
                        .padding(.bottom)

                    ExplanationView(text: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_FAILED_BODY")
                        .padding(.bottom)
                    
                    VStack {
                        if model != nil {
                            OlvidButtonNew(action: userWantsToActivateThisDevice) {
                                Text("ACTIVATE_THIS_DEVICE")
                            }
                        }
                        OlvidButtonNew(action: actions.userWantsToDismissObvChooseDeviceToReactivateView, style: .glassOrBordered) {
                            Text("MAYBE_LATER")
                        }
                    }
                    .disabled(shouldDisableButtons)

                }.padding()
            }
        }
        
    }
    
    
}


// MARK: - Internal view

extension ObvChooseDeviceToReactivateView {
    private struct ServerAnswerReceivedView: View {

        let model: ObvChooseDeviceToReactivateView.Model
        let serverAnswerReceivedStatus: Status.ServerAnswerReceivedStatus
        let actions: ObvChooseDeviceToReactivateViewInternalActions
        @Binding var shouldDisableButtons: Bool
        @State var deviceIdentifierOfSelectedDeviceToDeactivate: Data?
        
        private var aDeviceIsCurrentlySelected: Bool {
            deviceIdentifierOfSelectedDeviceToDeactivate != nil
        }

        private func userWantsToActivateThisDevice() {
            actions.userWantsToActivateThisDevice(currentDeviceIdentifier: model.currentDeviceIdentifier,
                                                  deviceIdentifierOfOtherDeviceToDeactivate: deviceIdentifierOfSelectedDeviceToDeactivate)
        }

        var body: some View {
            VStack {
                
                switch serverAnswerReceivedStatus {
                    
                case .noActiveDeviceFoundOnServer:
                    
                    TitleView(title: String(localizedInThisBundle: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_NO_ACTIVE_DEVICE_FOUND_TITLE"))
                        .padding(.bottom)
                    
                    ExplanationView(text: String(localizedInThisBundle: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_NO_ACTIVE_DEVICE_FOUND_BODY"))
                        .padding(.bottom)
                    
                    VStack {
                        OlvidButtonNew(action: userWantsToActivateThisDevice) {
                            Text("ACTIVATE_THIS_DEVICE")
                        }
                        OlvidButtonNew(action: actions.userWantsToDismissObvChooseDeviceToReactivateView, style: .glassOrBordered) {
                            Text("MAYBE_LATER")
                        }
                    }
                    .disabled(shouldDisableButtons)
                    
                case .multideviceFeatureAvailable(let devicesFromServer):
                    
                    TitleView(title: String(localizedInThisBundle: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_MULTIDEVICE_AVAILABLE_TITLE"))
                        .padding(.bottom)
                    
                    ExplanationView(text: String(localizedInThisBundle: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_MULTIDEVICE_AVAILABLE_BODY"))
                        .padding(.bottom)
                    
                    VStack {
                        OlvidButtonNew(action: userWantsToActivateThisDevice) {
                            Text("ACTIVATE_THIS_DEVICE")
                        }
                        OlvidButtonNew(action: actions.userWantsToDismissObvChooseDeviceToReactivateView, style: .glassOrBordered) {
                            Text("MAYBE_LATER")
                        }
                    }
                    .disabled(shouldDisableButtons)
                    
                    if !devicesFromServer.isEmpty {
                        
                        HStack {
                            Text("YOUR_\(devicesFromServer.count)_OTHER_DEVICES")
                                .font(.headline)
                            Spacer()
                        }.padding(.top, 32)
                        
                        ForEach(devicesFromServer, id: \.deviceIdentifier) { deviceFromServer in
                            DeviceCardView(model: deviceFromServer)
                        }
                        
                    }
                    
                case .multideviceFeatureUnavailableAndAllActiveDevicesExpire(let devicesFromServer):
                    
                    TitleView(title: String(localizedInThisBundle: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_NO_MULTIDEVICE_ALL_DEVICES_EXPIRE_TITLE"))
                        .padding(.bottom)
                    
                    ExplanationView(text: String(localizedInThisBundle: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_NO_MULTIDEVICE_\(devicesFromServer.count)_DEVICES_EXPIRE_BODY"))
                        .padding(.bottom)
                    
                    VStack {
                        OlvidButtonNew(action: userWantsToActivateThisDevice) {
                            Text("ACTIVATE_THIS_DEVICE")
                        }
                        OlvidButtonNew(action: actions.userWantsToDismissObvChooseDeviceToReactivateView, style: .glassOrBordered) {
                            Text("MAYBE_LATER")
                        }
                    }
                    .disabled(shouldDisableButtons)
                    
                    HStack {
                        Text("YOUR_\(devicesFromServer.count)_OTHER_DEVICES")
                            .font(.headline)
                        Spacer()
                    }.padding(.top, 32)
                    
                    ForEach(devicesFromServer, id: \.deviceIdentifier) { deviceFromServer in
                        DeviceCardView(model: deviceFromServer)
                    }
                    
                case .multideviceFeatureUnavailableAndAtLeastOneNonExpiringActiveDeviceFound(let devicesFromServer):
                    
                    TitleView(title: String(localizedInThisBundle: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_NO_MULTIDEVICE_AT_LEAST_ONE_NON_EXPIRING_DEVICE_TITLE"))
                        .padding(.bottom)
                    
                    ExplanationView(text: String(localizedInThisBundle: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_NO_MULTIDEVICE_AT_LEAST_ONE_NON_EXPIRING_DEVICE_BODY"))
                        .padding(.bottom)
                    
                    ForEach(devicesFromServer, id: \.deviceIdentifier) { deviceFromServer in
                        SelectableDeviceCardView(model: deviceFromServer,
                                                 deviceIdentifierOfSelectedDevice: $deviceIdentifierOfSelectedDeviceToDeactivate)
                    }
                    
                    VStack {
                        OlvidButtonNew(action: userWantsToActivateThisDevice) {
                            Text("DEACTIVATE_SELECTED_DEVICE_AND_ACTIVATE_THIS_ONE")
                        }
                        .disabled(!aDeviceIsCurrentlySelected)
                        OlvidButtonNew(action: actions.userWantsToDismissObvChooseDeviceToReactivateView, style: .glassOrBordered) {
                            Text("MAYBE_LATER")
                        }
                    }.disabled(shouldDisableButtons)
                    
                }
                
            }
            .padding(.horizontal)
        }
        
    }
}


extension ObvChooseDeviceToReactivateView {
    private  struct SelectableDeviceCardView: View {
        
        let model: DeviceCardView.Model
        @Binding var deviceIdentifierOfSelectedDevice: Data?

        private var thisDeviceIsSelected: Bool {
            model.deviceIdentifier == deviceIdentifierOfSelectedDevice
        }

        var body: some View {
            ObvCardView {
                HStack(alignment: .center, spacing: 16) {
                    Image(systemIcon: thisDeviceIsSelected ? .checkmarkCircleFill : .circle)
                        .foregroundColor(thisDeviceIsSelected ? Color(.systemRed) : .secondary)
                    VStack(alignment: .leading) {
                        HStack {
                            Text(verbatim: model.deviceName)
                                .font(.headline)
                            Spacer()
                        }
                        if let latestRegistrationDate = model.latestRegistrationDate {
                            Text("DEVICE_LAST_ONLINE_\(latestRegistrationDate.relativeFormatted)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                
            }
            .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
            .onTapGesture {
                withAnimation {
                    if deviceIdentifierOfSelectedDevice == model.deviceIdentifier {
                        deviceIdentifierOfSelectedDevice = nil
                    } else {
                        deviceIdentifierOfSelectedDevice = model.deviceIdentifier
                    }
                }
            }
        }
        
    }
}


extension ObvChooseDeviceToReactivateView {
    private struct TitleView: View {
        let title: String
        var body: some View {
            HStack {
                Text(title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                Spacer()
            }
        }
    }
}

extension ObvChooseDeviceToReactivateView {
    fileprivate struct ExplanationView: View {
        let text: String
        var body: some View {
            ObvCardView {
                HStack {
                    Text(text)
                    Spacer()
                }
            }
        }
    }
}


// MARK: - Internal view

extension ObvChooseDeviceToReactivateView {
    private struct QueryingServerView: View {
        
        let model: Model
        let actions: ObvChooseDeviceToReactivateViewInternalActions
        
        var body: some View {
            VStack {
                Spacer()
                Text("PLEASE_WAIT_WHILE_WE_CHECK_WHETHER_YOUR_DEVICE_\(model.currentDeviceName)_CAN_BE_REACTIVATED")
                    .multilineTextAlignment(.center)
                    .font(.body)
                    .foregroundColor(.secondary)
                ProgressView()
                Spacer()
                OlvidButtonNew(action: actions.userWantsToDismissObvChooseDeviceToReactivateView) {
                    Text("CANCEL")
                }
            }
        }
        
    }
}


struct DeviceCardView: View {
    
    let model: Model
    
    struct Model: Sendable, Equatable {
        let deviceIdentifier: Data
        let deviceName: String
        let expirationDate: Date?
        let latestRegistrationDate: Date?
    }

    var body: some View {
        ObvCardView {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: model.deviceName)
                        .font(.headline)
                    if let expirationDate = model.expirationDate {
                        Text("DEVICE_DEACTIVATED_\(expirationDate.relativeFormatted)")
                    } else {
                        Text("DEVICE_WONT_BE_DEACTIVATED")
                    }
                }
                Spacer()
            }
        }
    }
}





#if DEBUG

// MARK: - Previews

@MainActor
private final class DataSourceAndActionsForPreviews {}

extension DataSourceAndActionsForPreviews: ObvChooseDeviceToReactivateViewDataSource {
    
    func getObvChooseDeviceToReactivateViewModel(_ view: ObvChooseDeviceToReactivateView, ownedCryptoId: ObvCryptoId) async throws -> ObvChooseDeviceToReactivateView.Model {
        try? await Task.sleep(seconds: 1)
        return .init(currentDeviceName: "My current device name",
                     currentDeviceIdentifier: Data(repeating: 0x88, count: 16))
    }
    
    func performOwnedDeviceDiscoveryNow(_ view: ObvChooseDeviceToReactivateView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> ObvTypes.ObvOwnedDeviceDiscoveryResult {
        try? await Task.sleep(seconds: 1)
        let otherDevice1 = ObvOwnedDeviceDiscoveryResult.Device(
            identifier:  Data(repeating: 0x89, count: 16),
            expirationDate: nil,
            latestRegistrationDate: .now.addingTimeInterval(-.init(days: 1)),
            name: "Other device 1")
        let otherDevice2 = ObvOwnedDeviceDiscoveryResult.Device(
            identifier:  Data(repeating: 0x90, count: 16),
            expirationDate: nil,
            latestRegistrationDate: .now.addingTimeInterval(-.init(days: 2)),
            name: "Other device 2")
        return .init(devices: Set([otherDevice1, otherDevice2]),
                     isMultidevice: false)
    }
    
}

extension DataSourceAndActionsForPreviews: ObvChooseDeviceToReactivateViewActions {
    
    func userWantsToActivateCurrentDevice(_ view: ObvChooseDeviceToReactivateView, ownedCryptoId: ObvTypes.ObvCryptoId, currentDeviceIdentifier: Data, deviceIdentifierOfOtherDeviceToDeactivate: Data?) async throws {
        print("User wants to reactivate the current device")
        try? await Task.sleep(seconds: 3)
    }
    
}

extension DataSourceAndActionsForPreviews: ObvChooseDeviceToReactivateViewNavigation {
    
    func userWantsToDismissObvChooseDeviceToReactivateView(_ view: ObvChooseDeviceToReactivateView) {
        print("User wants to dismiss ObvChooseDeviceToReactivateView")
    }
    
}

@MainActor
private let dataSourceAndActionsForPreviews = DataSourceAndActionsForPreviews()

#Preview {
    ObvChooseDeviceToReactivateView(
        ownedCryptoId: .sampleOwnedCryptoId,
        dataSource: dataSourceAndActionsForPreviews,
        actions: dataSourceAndActionsForPreviews,
        navigation: dataSourceAndActionsForPreviews)
}


#endif
