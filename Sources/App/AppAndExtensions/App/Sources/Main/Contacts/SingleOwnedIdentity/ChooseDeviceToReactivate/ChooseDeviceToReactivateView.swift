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

import Foundation
import SwiftUI
import ObvTypes
import ObvEngine
import ObvUI
import ObvDesignSystem


protocol ChooseDeviceToReactivateViewModelProtocol: ObservableObject {
    
    associatedtype DeviceCardViewModel: DeviceCardViewModelProtocol

    var ownedCryptoId: ObvCryptoId { get }
    var currentDeviceName: String { get }
    var currentDeviceIdentifier: Data { get }
    var status: ChooseDeviceToReactivateViewStatus<DeviceCardViewModel> { get }
    
}


protocol ChooseDeviceToReactivateViewActionsDelegate: ReactivationProgressViewActionsDelegate {
    func theReactivationProgressViewDidAppear(ownedCryptoId: ObvCryptoId) async
    func userWantsToActivateCurrentDevice(ownedCryptoId: ObvCryptoId, currentDeviceIdentifier: Data, deviceIdentifierOfOtherDeviceToDeactivate: Data?) async
}


enum ChooseDeviceToReactivateViewStatus<Model: DeviceCardViewModelProtocol> {

    case queryingServer
    case serverAnswerReceived(status: ServerAnswerReceivedStatus)
    case serverQueryFailed
    
    enum ServerAnswerReceivedStatus {
        case noActiveDeviceFoundOnServer // ok
        case multideviceFeatureAvailable(devicesFromServer: [Model]) // ok
        case multideviceFeatureUnavailableAndAtLeastOneNonExpiringActiveDeviceFound(devicesFromServer: [Model]) // ok
        case multideviceFeatureUnavailableAndAllActiveDevicesExpire(devicesFromServer: [Model])
    }
    
}


// MARK: - ChooseDeviceToReactivateView

struct ChooseDeviceToReactivateView<Model: ChooseDeviceToReactivateViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    let actions: ChooseDeviceToReactivateViewActionsDelegate?
    
    @State private var onAppearActionPerformed = false
    @State private var deviceIdentifierOfSelectedDeviceToDeactivate: Data?
    @State private var shouldDisableButtons = false
    
    private func theReactivationProgressViewDidAppear() {
        guard !onAppearActionPerformed else { return }
        onAppearActionPerformed = true
        let ownedCryptoId = model.ownedCryptoId
        Task {
            await actions?.theReactivationProgressViewDidAppear(ownedCryptoId: ownedCryptoId)
        }
    }
    
    private var aDeviceIsCurrentlySelected: Bool {
        deviceIdentifierOfSelectedDeviceToDeactivate != nil
    }
    
    private func userWantsToActivateThisDevice() {
        Task {
            shouldDisableButtons = true
            await actions?.userWantsToActivateCurrentDevice(
                ownedCryptoId: model.ownedCryptoId,
                currentDeviceIdentifier: model.currentDeviceIdentifier,
                deviceIdentifierOfOtherDeviceToDeactivate: deviceIdentifierOfSelectedDeviceToDeactivate)
            shouldDisableButtons = false
        }
    }
    
    
    private func userWantsToCancel() {
        Task {
            await actions?.userWantsToCancelReactivationOfCurrentDevice()
        }
    }
    
    
    var body: some View {
        
        switch model.status {
            
        case .queryingServer:
            
            ReactivationProgressView(
                nameOfCurrentDevice: model.currentDeviceName,
                actions: actions)
            .padding()
            .onAppear(perform: theReactivationProgressViewDidAppear)
            
        case .serverQueryFailed:
            
            ScrollView {
                VStack {
                    
                    TitleView(title: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_FAILED_TITLE")
                        .padding(.bottom)

                    ExplanationView(text: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_FAILED_BODY")
                        .padding(.bottom)
                    
                    Group {
                        OlvidButton(
                            style: .red,
                            title: Text("ACTIVATE_THIS_DEVICE"),
                            action: userWantsToActivateThisDevice)
                        OlvidButton(
                            style: .blue,
                            title: Text("MAYBE_LATER"),
                            action: userWantsToCancel)
                    }.disabled(shouldDisableButtons)
                    
                }.padding()
            }

        case .serverAnswerReceived(status: let serverAnswerReceivedStatus):

            ScrollView {
                VStack {
                    
                    switch serverAnswerReceivedStatus {
                        
                    case .noActiveDeviceFoundOnServer:

                        TitleView(title: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_NO_ACTIVE_DEVICE_FOUND_TITLE")
                            .padding(.bottom)

                        ExplanationView(text: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_NO_ACTIVE_DEVICE_FOUND_BODY")
                            .padding(.bottom)

                        Group {
                            OlvidButton(
                                style: .blue,
                                title: Text("ACTIVATE_THIS_DEVICE"),
                                action: userWantsToActivateThisDevice)
                            OlvidButton(
                                style: .standardWithBlueText,
                                title: Text("MAYBE_LATER"),
                                action: userWantsToCancel)
                        }.disabled(shouldDisableButtons)

                    case .multideviceFeatureAvailable(let devicesFromServer):
                        
                        TitleView(title: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_MULTIDEVICE_AVAILABLE_TITLE")
                            .padding(.bottom)

                        ExplanationView(text: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_MULTIDEVICE_AVAILABLE_BODY")
                            .padding(.bottom)

                        Group {
                            OlvidButton(
                                style: .blue,
                                title: Text("ACTIVATE_THIS_DEVICE"),
                                action: userWantsToActivateThisDevice)
                            OlvidButton(
                                style: .standardWithBlueText,
                                title: Text("MAYBE_LATER"),
                                action: userWantsToCancel)
                        }.disabled(shouldDisableButtons)
                        
                        if !devicesFromServer.isEmpty {
                            
                            HStack {
                                Text(String.localizedStringWithFormat(NSLocalizedString("YOUR_OTHER_DEVICES", comment: ""), devicesFromServer.count))
                                    .font(.headline)
                                Spacer()
                            }.padding(.top, 32)
                            
                            ForEach(devicesFromServer, id: \.deviceIdentifier) { deviceFromServer in
                                DeviceCardView(model: deviceFromServer)
                            }
                            
                        }

                    case .multideviceFeatureUnavailableAndAllActiveDevicesExpire(let devicesFromServer):
                        
                        TitleView(title: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_NO_MULTIDEVICE_ALL_DEVICES_EXPIRE_TITLE")
                            .padding(.bottom)
                                                
                        ExplanationViewAlt(text: String.localizedStringWithFormat(NSLocalizedString("OWNED_DEVICE_DISCOVERY_SERVER_QUERY_NO_MULTIDEVICE_N_DEVICES_EXPIRE_BODY", comment: ""), devicesFromServer.count))
                            .padding(.bottom)
                        
                        Group {
                            OlvidButton(
                                style: .blue,
                                title: Text("ACTIVATE_THIS_DEVICE"),
                                action: userWantsToActivateThisDevice)
                            OlvidButton(
                                style: .standardWithBlueText,
                                title: Text("MAYBE_LATER"),
                                action: userWantsToCancel)
                        }.disabled(shouldDisableButtons)

                        HStack {
                            Text(String.localizedStringWithFormat(NSLocalizedString("YOUR_OTHER_DEVICES", comment: ""), devicesFromServer.count))
                                .font(.headline)
                            Spacer()
                        }.padding(.top, 32)
                        
                        ForEach(devicesFromServer, id: \.deviceIdentifier) { deviceFromServer in
                            DeviceCardView(model: deviceFromServer)
                        }


                    case .multideviceFeatureUnavailableAndAtLeastOneNonExpiringActiveDeviceFound(let devicesFromServer):
                        
                        TitleView(title: "OWNED_DEVICE_DISCOVERY_SERVER_QUERY_NO_MULTIDEVICE_AT_LEAST_ONE_NON_EXPIRING_DEVICE_TITLE")
                            .padding(.bottom)

                        ExplanationViewAlt(text: String.localizedStringWithFormat(NSLocalizedString("OWNED_DEVICE_DISCOVERY_SERVER_QUERY_NO_MULTIDEVICE_AT_LEAST_ONE_NON_EXPIRING_DEVICE_BODY", comment: ""), devicesFromServer.count))
                            .padding(.bottom)

                        ForEach(devicesFromServer, id: \.deviceIdentifier) { deviceFromServer in
                            SelectableDeviceCardView(model: deviceFromServer, deviceIdentifierOfSelectedDevice: $deviceIdentifierOfSelectedDeviceToDeactivate)
                        }

                        Group {
                            OlvidButton(
                                style: .blue,
                                title: Text("DEACTIVATE_SELECTED_DEVICE_AND_ACTIVATE_THIS_ONE"),
                                action: userWantsToActivateThisDevice)
                            .disabled(!aDeviceIsCurrentlySelected)
                            OlvidButton(
                                style: .standardWithBlueText,
                                title: Text("MAYBE_LATER"),
                                action: userWantsToCancel)
                        }.disabled(shouldDisableButtons)

                    }
                    
                }.padding()
            }
            
        }
        
    }
    
}


fileprivate struct TitleView: View {
    
    let title: LocalizedStringKey
    
    var body: some View {
        HStack {
            Text(title)
                .font(.title)
            Spacer()
        }
    }
    
}


fileprivate struct ExplanationView: View {
    
    let text: LocalizedStringKey
    
    var body: some View {
        ObvCardView {
            HStack {
                Text(text)
                Spacer()
            }
        }
    }
    
}


fileprivate struct ExplanationViewAlt: View {
    
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


protocol DeviceCardViewModelProtocol {
    
    var deviceIdentifier: Data { get }
    var deviceName: String { get }
    var expirationDate: Date? { get }
    var latestRegistrationDate: Date? { get }

}


fileprivate struct DeviceCardView<Model: DeviceCardViewModelProtocol>: View {
    
    let model: Model

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


fileprivate struct SelectableDeviceCardView<Model: DeviceCardViewModelProtocol>: View {
    
    let model: Model
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


protocol ReactivationProgressViewActionsDelegate {
    func userWantsToCancelReactivationOfCurrentDevice() async
}


fileprivate struct ReactivationProgressView: View {
    
    let nameOfCurrentDevice: String
    let actions: ReactivationProgressViewActionsDelegate?

    private func userWantsToCancelReactivationOfCurrentDevice() {
        Task {
            await actions?.userWantsToCancelReactivationOfCurrentDevice()
        }
    }

    var body: some View {
        
        VStack {
            Spacer()
            Text("PLEASE_WAIT_WHILE_WE_CHECK_WHETHER_YOUR_DEVICE_\(nameOfCurrentDevice)_CAN_BE_REACTIVATED")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.primary)
            ProgressView()
            Spacer()
            OlvidButton(style: .blue, title: Text("Cancel"), action: userWantsToCancelReactivationOfCurrentDevice)
        }
        
    }
    
}



// MARK: - Previews

struct ChooseDeviceToReactivateView_Previews: PreviewProvider {

    final class DeviceCardViewModelForPreviews: DeviceCardViewModelProtocol {
        
        let deviceIdentifier: Data
        let deviceName: String
        let expirationDate: Date?
        let latestRegistrationDate: Date?

        init(deviceIdentifier: Data, deviceName: String, expirationDate: Date?, latestRegistrationDate: Date?) {
            self.deviceIdentifier = deviceIdentifier
            self.deviceName = deviceName
            self.expirationDate = expirationDate
            self.latestRegistrationDate = latestRegistrationDate
        }
        
    }
    
    private static let identityAsURL: URL = URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!
        
    private static let ownedCryptoId = ObvURLIdentity(urlRepresentation: identityAsURL)!.cryptoId

    
    final class ChooseDeviceToReactivateViewModelForPreviews: ChooseDeviceToReactivateViewModelProtocol {
        
        let ownedCryptoId: ObvCryptoId
        let currentDeviceName: String
        let currentDeviceIdentifier: Data
        let status: ChooseDeviceToReactivateViewStatus<DeviceCardViewModelForPreviews>
        
        init(ownedCryptoId: ObvCryptoId, currentDeviceName: String, currentDeviceIdentifier: Data, status: ChooseDeviceToReactivateViewStatus<DeviceCardViewModelForPreviews>) {
            self.ownedCryptoId = ownedCryptoId
            self.currentDeviceName = currentDeviceName
            self.currentDeviceIdentifier = currentDeviceIdentifier
            self.status = status
        }
        
    }
    
    
    private static let devices: [DeviceCardViewModelForPreviews] = {
       [
        .init(deviceIdentifier: Data(repeating: 0, count: 16),
              deviceName: "iPhone 14",
              expirationDate: Date(timeIntervalSinceNow: 2_000),
              latestRegistrationDate: Date(timeIntervalSinceNow: -300)),
        .init(deviceIdentifier: Data(repeating: 1, count: 16),
              deviceName: "iPad Pro",
              expirationDate: Date(timeIntervalSinceNow: 3_000),
        latestRegistrationDate: Date(timeIntervalSinceNow: -400)),
        .init(deviceIdentifier: Data(repeating: 2, count: 16),
              deviceName: "iPod",
              expirationDate: nil,
              latestRegistrationDate: Date(timeIntervalSinceNow: -500)),
       ]
    }()
    
    
    private static let models: [ChooseDeviceToReactivateViewModelForPreviews] = {
       [
        .init(ownedCryptoId: ownedCryptoId,
              currentDeviceName: devices[0].deviceName,
              currentDeviceIdentifier: devices[0].deviceIdentifier,
              status: .queryingServer),
        .init(ownedCryptoId: ownedCryptoId,
              currentDeviceName: devices[0].deviceName,
              currentDeviceIdentifier: devices[0].deviceIdentifier,
              status: .serverQueryFailed),
        .init(ownedCryptoId: ownedCryptoId,
              currentDeviceName: devices[0].deviceName,
              currentDeviceIdentifier: devices[0].deviceIdentifier,
              status: .serverAnswerReceived(status: .noActiveDeviceFoundOnServer)),
        .init(ownedCryptoId: ownedCryptoId,
              currentDeviceName: devices[0].deviceName,
              currentDeviceIdentifier: devices[0].deviceIdentifier,
              status: .serverAnswerReceived(
                status: .multideviceFeatureUnavailableAndAtLeastOneNonExpiringActiveDeviceFound(devicesFromServer: [devices[1]])
              )),
        .init(ownedCryptoId: ownedCryptoId,
              currentDeviceName: devices[0].deviceName,
              currentDeviceIdentifier: devices[0].deviceIdentifier,
              status: .serverAnswerReceived(
                status: .multideviceFeatureUnavailableAndAtLeastOneNonExpiringActiveDeviceFound(devicesFromServer: [devices[0], devices[1]])
              )),
       ]
    }()
    
    
    private struct ChooseDeviceToReactivateViewActionsForPreviews: ChooseDeviceToReactivateViewActionsDelegate {
        func userWantsToActivateCurrentDevice(ownedCryptoId: ObvTypes.ObvCryptoId, currentDeviceIdentifier: Data, deviceIdentifierOfOtherDeviceToDeactivate: Data?) async {}
        func theReactivationProgressViewDidAppear(ownedCryptoId: ObvCryptoId) async {}
        func userWantsToCancelReactivationOfCurrentDevice() async {}
    }
    
    private static let actions = ChooseDeviceToReactivateViewActionsForPreviews()
    
    static var previews: some View {
        Group {
            
            ChooseDeviceToReactivateView(model: models[0], actions: actions)
                .previewDisplayName("Querying server")
            
            ChooseDeviceToReactivateView(model: models[1], actions: actions)
                .previewDisplayName("Server query failed")
            
            ChooseDeviceToReactivateView(model: models[2], actions: actions)
                .previewDisplayName("No active device found on server")
            
            ChooseDeviceToReactivateView(
                model: ChooseDeviceToReactivateViewModelForPreviews(
                    ownedCryptoId: ownedCryptoId,
                    currentDeviceName: devices[0].deviceName,
                    currentDeviceIdentifier: devices[0].deviceIdentifier,
                    status: .serverAnswerReceived(
                        status: .multideviceFeatureAvailable(devicesFromServer: [])
                    )),
                actions: actions)
                .previewDisplayName("Multidevice available (no other device)")

            ChooseDeviceToReactivateView(
                model: ChooseDeviceToReactivateViewModelForPreviews(
                    ownedCryptoId: ownedCryptoId,
                    currentDeviceName: devices[0].deviceName,
                    currentDeviceIdentifier: devices[0].deviceIdentifier,
                    status: .serverAnswerReceived(
                        status: .multideviceFeatureAvailable(devicesFromServer: [devices[2]])
                    )),
                actions: actions)
                .previewDisplayName("Multidevice available (one other non-expiring device)")

            ChooseDeviceToReactivateView(
                model: ChooseDeviceToReactivateViewModelForPreviews(
                    ownedCryptoId: ownedCryptoId,
                    currentDeviceName: devices[0].deviceName,
                    currentDeviceIdentifier: devices[0].deviceIdentifier,
                    status: .serverAnswerReceived(
                        status: .multideviceFeatureUnavailableAndAllActiveDevicesExpire(devicesFromServer: [devices[0]])
                    )),
                actions: actions)
                .previewDisplayName("No multidevice but the other active device expires")

            ChooseDeviceToReactivateView(
                model: ChooseDeviceToReactivateViewModelForPreviews(
                    ownedCryptoId: ownedCryptoId,
                    currentDeviceName: devices[0].deviceName,
                    currentDeviceIdentifier: devices[0].deviceIdentifier,
                    status: .serverAnswerReceived(
                        status: .multideviceFeatureUnavailableAndAllActiveDevicesExpire(devicesFromServer: [devices[0], devices[1]])
                    )),
                actions: actions)
                .previewDisplayName("No multidevice but both other active devices expire")

            ChooseDeviceToReactivateView(
                model: ChooseDeviceToReactivateViewModelForPreviews(
                    ownedCryptoId: ownedCryptoId,
                    currentDeviceName: devices[0].deviceName,
                    currentDeviceIdentifier: devices[0].deviceIdentifier,
                    status: .serverAnswerReceived(
                        status: .multideviceFeatureUnavailableAndAtLeastOneNonExpiringActiveDeviceFound(devicesFromServer: [devices[2]])
                    )),
                actions: actions)
                .previewDisplayName("No multidevice and the other device does not expire")

        }
    }
    
}
