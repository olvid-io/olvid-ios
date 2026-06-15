/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

#if canImport(WiFiAware)
import SwiftUI
import OSLog
import Network
import WiFiAware
import DeviceDiscoveryUI
import ObvAppCoreConstants
import ObvDesignSystem
import ObvSystemIcon
import ObvTypes


@MainActor
@available(iOS 26.0, *)
protocol ObvWiFiAwareViewNavigation {
    func userDidChoosePairedDevice(_ view: ObvWiFiAwareView, selectedOwnedCryptoId: ObvCryptoId, role: ObvWiFiAwareViewTransferRole, device: ObvWAPairedDevice)
}


@MainActor
@available(iOS 26.0, *)
protocol ObvWiFiAwareViewDataSource {
    func getAsyncStreamOfObvWAPairedDevice(_ view: ObvWiFiAwareView) async -> AsyncThrowingStream<[ObvWAPairedDevice], Error>
}

enum ObvWiFiAwareViewTransferRole: Sendable, Hashable, Equatable {
    case source(scope: TransferScope)
    case destination
}

@available(iOS 26.0, *)
struct ObvWiFiAwareView: View {
    
    let role: ObvWiFiAwareViewTransferRole
    let selectedOwnedCryptoId: ObvCryptoId
    let dataSource: any ObvWiFiAwareViewDataSource
    let navigation: any ObvWiFiAwareViewNavigation

    private static let logger = Logger(subsystem: "io.olvid.messenger", category: "ObvWiFiAwareView")
    
    @State private var status: Status = .requestingPairedDevices
    
    private enum Status {
        case requestingPairedDevices
        case noPairedDevices
        case foundPairedDevices([ObvWAPairedDevice])
    }
    
    private func onTask() async {
        do {
            var isFirstUpdate = true
            let allPairedDevices = await dataSource.getAsyncStreamOfObvWAPairedDevice(self)
            for try await updatedDeviceList in allPairedDevices {
                if updatedDeviceList.isEmpty {
                    if isFirstUpdate {
                        status = .noPairedDevices
                    } else {
                        withAnimation { status = .noPairedDevices }
                    }
                } else {
                    if isFirstUpdate {
                        status = .foundPairedDevices(updatedDeviceList)
                    } else {
                        withAnimation { status = .foundPairedDevices(updatedDeviceList) }
                    }
                }
                isFirstUpdate = false
            }
        } catch {
            Self.logger.error("Failed to get paired devices: \(error)")
        }
    }
        
    @State private var isSheetPresented = false
    
    private func pairNewDeviceButtonTapped() {
        isSheetPresented = true
    }
    
    private var explanation: LocalizedStringKey {
        switch role {
        case .source:
            return "WIFIAWARE_FOUND_PAIRED_DEVICES_EXPLANATION_SOURCE"
        case .destination:
            return "WIFIAWARE_FOUND_PAIRED_DEVICES_EXPLANATION_DESTINATION"
        }
    }

    private var pairedDevicesSectionTitle: LocalizedStringKey {
        switch role {
        case .source:
            return "YOUR_PAIRED_DEVICES_SOURCE"
        case .destination:
            return "YOUR_PAIRED_DEVICES_DESTINATION"
        }
    }
    
    private var otherDeviceSteps: LocalizedStringKey {
        switch role {
        case .source:
            return "PAIR_DEVICE_OTHER_DEVICE_STEPS_SOURCE"
        case .destination:
            return "PAIR_DEVICE_OTHER_DEVICE_STEPS_DESTINATION"
        }
    }
    
    var body: some View {
        ScrollView {
            VStack {
                switch status {
                    
                case .requestingPairedDevices:
                    
                    ObvCenteredProgressView()
                    
                case .noPairedDevices:
                    
                    PhoneWithPulsingRings()
                    
                    VStack(alignment: .center) {
                        Text("NO_PAIRED_DEVICE_TITLE")
                            .font(.headline)
                            .padding(.bottom)
                        Text("NO_PAIRED_DEVICE_MESSAGE")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .padding(.bottom)
                    
                    VStack(alignment: .leading) {
                        Text("STEP_ONE_ON_THE_OTHER_DEVICE")
                            .font(.headline)
                        ObvCardView {
                            Text(otherDeviceSteps)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                    
                    VStack(alignment: .leading) {
                        Text("STEP_TWO_ON_THIS_DEVICE")
                            .font(.headline)
                        ObvCardView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("PAIR_DEVICE_THIS_DEVICE_STEP")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                PairNewDeviceButton(role: role)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                    
                case .foundPairedDevices(let pairedDevices):
                    
                    VStack {
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                
                                // List of paired devices
                                
                                VStack(alignment: .leading) {
                                    Text(pairedDevicesSectionTitle)
                                        .font(.headline)
                                    ForEach(pairedDevices) { pairedDevice in
                                        PairedDeviceView(device: pairedDevice, actions: self)
                                    }
                                }
                                
                                // Role-specific explanation
                                
                                ObvCardView {
                                    Label {
                                        Text(explanation)
                                            .font(.subheadline)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } icon: {
                                        Image(systemIcon: .questionmarkCircle)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.bottom)
                                
                            }
                        }
                        
                        PairNewDeviceButton(role: role)
                        
                    }
                    .padding()
                    
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .task(onTask)
        .sheet(isPresented: $isSheetPresented) {
        }
    }
    
}


@available(iOS 26.0, *)
extension ObvWiFiAwareView: PairedDeviceViewInternalActions {
    
    fileprivate func userDidChoosePairedDevice(_ view: PairedDeviceView, device: ObvWAPairedDevice) {
        navigation.userDidChoosePairedDevice(self, selectedOwnedCryptoId: selectedOwnedCryptoId, role: role, device: device)
    }
    
}


// MARK: - PairNewDeviceButton

@available(iOS 26.0, *)
private struct PairNewDeviceButton: View {

    let role: ObvWiFiAwareViewTransferRole
    
    @ViewBuilder
    private var button: some View {
        HStack {
            Spacer(minLength: 0)
            Label(title: { Text("PAIR_NEW_DEVICE") }, icon: { Image(systemIcon: .plusCircle) })
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding()
        .background(Color.blue)
        .clipShape(Capsule())
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    var body: some View {
        switch role {
        case .source:
            if let chatHistoryTransferService = WAPublishableService.chatHistoryTransferService {
                DevicePairingView(.wifiAware(.connecting(to: chatHistoryTransferService, from: .selected([])))) {
                    button
                } fallback: {
                    Text("WI_FI_AWARE_ADVERTISING_NOT_AVAILABLE")
                }
            } else {
                button
            }
        case .destination:
            if let chatHistoryTransferService = WASubscribableService.chatHistoryTransferService {
                DevicePicker(.wifiAware(.connecting(to: .userSpecifiedDevices, from: chatHistoryTransferService))) { endpoint in
                    debugPrint("Paired Endpoint: \(endpoint)")
                } label: {
                    button
                } fallback: {
                    Text("WI_FI_AWARE_NOT_SUPPORTED")
                }
            } else {
                button
            }
        }
    }
    
}


// MARK: - PairedDeviceView

@MainActor
private protocol PairedDeviceViewInternalActions {
    func userDidChoosePairedDevice(_ view: PairedDeviceView, device: ObvWAPairedDevice)
}

private struct PairedDeviceView: View {
    
    let device: ObvWAPairedDevice
    let actions: any PairedDeviceViewInternalActions

    private let deviceWithNoName = String(localizedInThisBundle: "DEVICE_WITH_NO_NAME")

    private var systemIcon: SystemIcon {
        guard let modelName = device.pairingInfo?.modelName.lowercased() else { return .iphone }
        switch modelName {
        case "iphone": return .iphone
        case "ipad": return .ipad
        default: return .iphone
        }
    }
    
    private func userDidTapOnDevice() {
        actions.userDidChoosePairedDevice(self, device: device)
    }
    
    var body: some View {
        Button(action: userDidTapOnDevice) {
            ObvCardView {
                HStack(alignment: .firstTextBaseline) {
                    Label(title: { Text(device.pairingInfo?.pairingName ?? deviceWithNoName) }, icon: { Image(systemIcon: systemIcon) })
                    Spacer(minLength: 0)
                    ObvChevronRight()
                }
                .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped (trick)
            }
        }
    }
    
}


// MARK: - PulsingRingView

private struct PulsingRingView: View {

    let delay: Double
    @State private var animate = false
    @State private var isVisible = false

    var body: some View {
        Circle()
            .stroke(Color.blue.opacity(animate ? 0 : 0.4), lineWidth: 1.5)
            .scaleEffect(animate ? 2.2 : 0.6)
            .animation(
                .easeOut(duration: 1.5)
                .repeatForever(autoreverses: false),
                value: animate
            )
            // Keep the ring hidden until its animation is about to start, so it doesn't
            // appear as a static frozen circle during the pre-animation delay period.
            .opacity(isVisible ? 1 : 0)
            .task {
                try? await Task.sleep(for: .seconds(delay))
                isVisible = true
                animate = true
            }
    }

}


// MARK: - PhoneWithPulsingRings

private struct PhoneWithPulsingRings: View {
    
    var body: some View {
        ZStack {
            PulsingRingView(delay: 1.0)
            PulsingRingView(delay: 2.0)
            PulsingRingView(delay: 3.0)
            Image(systemIcon: .iphoneRadiowavesLeftAndRight)
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.blue)
        }
        .frame(width: 128, height: 128)
    }
    
}


#if DEBUG

@MainActor
@available(iOS 26.0, *)
private final class DataSourceForPreviews {}

@available(iOS 26.0, *)
extension DataSourceForPreviews: ObvWiFiAwareViewDataSource {
    
    func getAsyncStreamOfObvWAPairedDevice(_ view: ObvWiFiAwareView) async -> AsyncThrowingStream<[ObvWAPairedDevice], any Error> {
        let stream = AsyncThrowingStream<[ObvWAPairedDevice], any Error> { (continuation: AsyncThrowingStream<[ObvWAPairedDevice], any Error>.Continuation) in
            Task {

                let secondsToWait: TimeInterval = 2.0
                
                while true {

                    try await Task.sleep(seconds: secondsToWait)

                    var allPairedDevices = [ObvWAPairedDevice]()
                    continuation.yield(allPairedDevices)
                                        
                    try await Task.sleep(seconds: secondsToWait + 10000)
                    
                    let device1 = ObvWAPairedDevice(id: 0, pairingInfo: .init(vendorName: "Apple", modelName: "iPhone", pairingName: "Alice's iPhone 17", description: "Some description"))
                    allPairedDevices.append(device1)
                    continuation.yield(allPairedDevices)
                    
                    try await Task.sleep(seconds: secondsToWait)
                    
                    let device2 = ObvWAPairedDevice(id: 1, pairingInfo: .init(vendorName: "Apple", modelName: "iPad", pairingName: "Alice's iPad", description: "Some description"))
                    allPairedDevices.append(device2)
                    continuation.yield(allPairedDevices)

                    try await Task.sleep(seconds: secondsToWait + 10000)

                }

            }
        }
        return stream
    }
    
}

@available(iOS 26.0, *)
extension DataSourceForPreviews: ObvWiFiAwareViewNavigation {
    
    func userDidChoosePairedDevice(_ view: ObvWiFiAwareView, selectedOwnedCryptoId: ObvCryptoId, role: ObvWiFiAwareViewTransferRole, device: ObvWAPairedDevice) {
        print("User did choose paired device")
    }

}


@available(iOS 26.0, *)
extension DataSourceForPreviews: PairedDeviceViewInternalActions {
    
    func userDidChoosePairedDevice(_ view: PairedDeviceView, device: ObvWAPairedDevice) {
        print("User did choose paired device")
    }

}

@available(iOS 26.0, *)
private let dataSourceForPreviews = DataSourceForPreviews()

@available(iOS 26.0, *)
#Preview("ObvWiFiAwareView") {
    ObvWiFiAwareView(role: .destination,
                     selectedOwnedCryptoId: .sampleDatasForOwnedCryptoId[0],
                     dataSource: dataSourceForPreviews,
                     navigation: dataSourceForPreviews)
}

@available(iOS 26.0, *)
#Preview("PairedDeviceView") {
    VStack {
        Spacer()
        PairedDeviceView(device: .init(id: 0, pairingInfo: .init(vendorName: "Apple", modelName: "iPhone", pairingName: "Alice's iPhone", description: "Device description")), actions: dataSourceForPreviews)
        PairedDeviceView(device: .init(id: 0, pairingInfo: .init(vendorName: "Apple", modelName: "iPad", pairingName: "Alice's iPad", description: "Device description")), actions: dataSourceForPreviews)
        Spacer()
    }
    .padding()
    .background(Color.secondary)
}

#endif

#endif // canImport(WiFiAware)
