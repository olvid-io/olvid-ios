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

import SwiftUI
import ObvTypes
import ObvDesignSystem
import ObvSystemIcon


@MainActor
public protocol ListOfOtherOwnedDevicesViewDataSource {
    func getAsyncStreamOfListOfOtherOwnedDevicesViewModels(_ view: ListOfOtherOwnedDevicesView, ownedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ListOfOtherOwnedDevicesView.Model>)
    func finishAsyncStreamOfListOfOtherOwnedDevicesViewModels(_ view: ListOfOtherOwnedDevicesView, streamUUID: UUID)
}


@MainActor
protocol ListOfOtherOwnedDevicesViewActions {
    func userDidChooseOtherOwnedDevice(_ view: ListOfOtherOwnedDevicesInnerView, otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier, nameOfRemoteDevice: String?)
    func userTappedBackButton(_ view: ListOfOtherOwnedDevicesView)
}


// MARK: - Main view

/// View shown on the source device.
public struct ListOfOtherOwnedDevicesView: View {
    
    let ownedCryptoId: ObvCryptoId
    let dataSource: any ListOfOtherOwnedDevicesViewDataSource
    let actions: any ListOfOtherOwnedDevicesViewActions
    
    public struct Model: Sendable, Equatable {
        let isCurrentDeviceActive: Bool
        let otherOwnedDevices: [OtherOwnedDeviceView.Model]
        public init(isCurrentDeviceActive: Bool, otherOwnedDevices: [OtherOwnedDeviceView.Model]) {
            self.isCurrentDeviceActive = isCurrentDeviceActive
            self.otherOwnedDevices = otherOwnedDevices
        }
    }
    
    @State private var model: Model?
    
    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfListOfOtherOwnedDevicesViewModels(self, ownedCryptoId: ownedCryptoId)
            for await receivedModel in stream {
                if self.model == nil {
                    self.model = receivedModel
                } else {
                    withAnimation { self.model = receivedModel }
                }
            }
            dataSource.finishAsyncStreamOfListOfOtherOwnedDevicesViewModels(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
    public var body: some View {
        Group {
            if let model {
                if !model.isCurrentDeviceActive {
                    CurrentDeviceIsInactiveView(actions: self)
                } else if model.otherOwnedDevices.isEmpty {
                    NoDeviceFoundView(actions: self)
                } else {
                    ListOfOtherOwnedDevicesInnerView(ownedCryptoId: ownedCryptoId,
                                                     model: model,
                                                     actions: actions)
                }
            } else {
                ObvCenteredProgressView()
            }
        }
        .task(onTask)
    }
    
}


extension ListOfOtherOwnedDevicesView: NoDeviceFoundViewInternalActions {

    fileprivate func userTappedBackButton(_ view: NoDeviceFoundView) {
        actions.userTappedBackButton(self)
    }
    
}


extension ListOfOtherOwnedDevicesView: CurrentDeviceIsInactiveViewInternalActions {
    
    fileprivate func userTappedBackButton(_ view: CurrentDeviceIsInactiveView) {
        actions.userTappedBackButton(self)
    }
    
}


// MARK: - CurrentDeviceIsInactiveView

@MainActor
private protocol CurrentDeviceIsInactiveViewInternalActions {
    func userTappedBackButton(_ view: CurrentDeviceIsInactiveView)
}

private struct CurrentDeviceIsInactiveView: View {
    
    let actions: any CurrentDeviceIsInactiveViewInternalActions

    private let title = String(localizedInThisBundle: "CURRENT_DEVICE_IS_INACTIVE_VIEW_TITLE")
    private let systemIcom: SystemIcon = .personSlash
    private let description = String(localizedInThisBundle: "CURRENT_DEVICE_IS_INACTIVE_VIEW_DESCRIPTION")
    private let buttonLabel = String(localizedInThisBundle: "CURRENT_DEVICE_IS_INACTIVE_VIEW_BUTTON_LABEL")

    private func buttonTapped() {
        actions.userTappedBackButton(self)
    }
    
    var body: some View {
        VStack {
            ObvContentUnavailableView(title: title, systemIcon: systemIcom, description: description)
            OlvidButtonNew(action: buttonTapped) {
                Text(buttonLabel)
            }
            .padding()
        }
    }
    
}


// MARK: - NoDeviceFoundView

@MainActor
private protocol NoDeviceFoundViewInternalActions {
    func userTappedBackButton(_ view: NoDeviceFoundView)
}


private struct NoDeviceFoundView: View {

    let actions: any NoDeviceFoundViewInternalActions
    
    private let title = String(localizedInThisBundle: "NO_ACTIVE_DEVICE_FOUND_TITLE")
    private let systemIcom: SystemIcon = .magnifyingglass
    private let description = String(localizedInThisBundle: "NO_ACTIVE_DEVICE_FOUND_EXPLANATION")
    private let buttonLabel = String(localizedInThisBundle: "NO_ACTIVE_DEVICE_FOUND_BUTTON_LABEL")
    
    private func buttonTapped() {
        actions.userTappedBackButton(self)
    }

    var body: some View {
        VStack {
            ObvContentUnavailableView(title: title, systemIcon: systemIcom, description: description)
            OlvidButtonNew(action: buttonTapped) {
                Text(buttonLabel)
            }
            .padding()
        }
    }
    
}


struct ListOfOtherOwnedDevicesInnerView: View {
    
    let ownedCryptoId: ObvCryptoId
    let model: ListOfOtherOwnedDevicesView.Model
    let actions: any ListOfOtherOwnedDevicesViewActions

    var body: some View {
        ScrollView {
            VStack {
                
                HistoryTransferSectionTitle(title: String(localizedInThisBundle: "CHOOSE_DESTINATION_DEVICE_TITLE"))
                
                ForEach(model.otherOwnedDevices) { otherOwnedDevice in
                    OtherOwnedDeviceView(model: otherOwnedDevice)
                        .onTapGesture {
                            actions.userDidChooseOtherOwnedDevice(self, otherOwnedDeviceIdentifier: otherOwnedDevice.ownedDeviceIdentifier, nameOfRemoteDevice: otherOwnedDevice.deviceName)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}



public struct OtherOwnedDeviceView: View {
    
    let model: Model
    
    public struct Model: Sendable, Equatable, Identifiable {
        let ownedDeviceIdentifier: ObvOwnedDeviceIdentifier
        let deviceName: String
        let platform: ObvTypes.OlvidPlatform
        public var id: ObvOwnedDeviceIdentifier { self.ownedDeviceIdentifier }
        public init(ownedDeviceIdentifier: ObvOwnedDeviceIdentifier, deviceName: String, platform: ObvTypes.OlvidPlatform) {
            self.ownedDeviceIdentifier = ownedDeviceIdentifier
            self.deviceName = deviceName
            self.platform = platform
        }
    }
    
    public var body: some View {
        ObvCardView {
            HStack(alignment: .center) {
                ObvDeviceImageView(platform: model.platform)
                Text(model.deviceName)
                Spacer(minLength: 0)
                ObvChevronRight()
            }
        }
    }
    
}


#if DEBUG

@MainActor
private final class AlternateDataSourceForPreviews {}

extension AlternateDataSourceForPreviews: ListOfOtherOwnedDevicesViewDataSource {
    
    func getAsyncStreamOfListOfOtherOwnedDevicesViewModels(_ view: ListOfOtherOwnedDevicesView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ListOfOtherOwnedDevicesView.Model>) {
        let stream = AsyncStream<ListOfOtherOwnedDevicesView.Model> { (continuation: AsyncStream<ListOfOtherOwnedDevicesView.Model>.Continuation) in
            let model: ListOfOtherOwnedDevicesView.Model = .init(isCurrentDeviceActive: true, otherOwnedDevices: [])
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfListOfOtherOwnedDevicesViewModels(_ view: ListOfOtherOwnedDevicesView, streamUUID: UUID) {}
    
}

private let dataSourceForPreviews = GenericDataSourceForPreviews()
private let alternateDataSourceForPreviews = AlternateDataSourceForPreviews()


#Preview("2 devices") {
    ListOfOtherOwnedDevicesView(ownedCryptoId: .sampleDatasForOwnedCryptoId[0],
                                dataSource: dataSourceForPreviews,
                                actions: dataSourceForPreviews)
}

#Preview("No device") {
    ListOfOtherOwnedDevicesView(ownedCryptoId: .sampleDatasForOwnedCryptoId[0],
                                dataSource: alternateDataSourceForPreviews,
                                actions: dataSourceForPreviews)
}

#endif
