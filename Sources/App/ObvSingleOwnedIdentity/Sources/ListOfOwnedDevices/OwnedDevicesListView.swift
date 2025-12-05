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
import ObvCrypto
import ObvDesignSystem
import ObvTypes


@MainActor
public protocol OwnedDevicesListViewDataSource {
    func getOwnedDevicesListViewModel(_ view: OwnedDevicesListView, ownedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<OwnedDevicesListView.Model>)
    func finishOwnedDevicesListViewModel(_ view: OwnedDevicesListView, streamUUID: UUID)
}


@MainActor
public protocol OwnedDevicesListViewActions: OwnedDeviceViewActions {
    func userWantsToSearchForNewOwnedDevices(_ view: OwnedDevicesListView, ownedCryptoId: ObvCryptoId) async throws
    func userWantsToClearAllOtherOwnedDevicesAndHasConfirmed(_ view: OwnedDevicesListView, ownedCryptoId: ObvCryptoId) async throws

}

@MainActor
public protocol OwnedDevicesListViewNavigation {
    func userWantsToSeeSubscriptionPlans(_ view: OwnedDevicesListView)
}

public struct OwnedDevicesListView: View {
    
    let ownedCryptoId: ObvCryptoId
    let dataSources: DataSources
    let actions: any OwnedDevicesListViewActions
    let navigation: any OwnedDevicesListViewNavigation
    
    public struct Model: Sendable, Equatable {
        let ownedDeviceUIDs: [UID]
        public init(ownedDeviceUIDs: [UID]) {
            self.ownedDeviceUIDs = ownedDeviceUIDs
        }
    }
    
    public struct DataSources {
        let dataSource: any OwnedDevicesListViewDataSource
        let ownedDeviceViewDataSource: any OwnedDeviceViewDataSource
        public init(dataSource: any OwnedDevicesListViewDataSource, ownedDeviceViewDataSource: any OwnedDeviceViewDataSource) {
            self.dataSource = dataSource
            self.ownedDeviceViewDataSource = ownedDeviceViewDataSource
        }
    }

    enum LoadModelState: Sendable, Equatable {
        case loading
        case loaded(Model)
    }
    
    @State private var loadModelState: LoadModelState = .loading
    
    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSources.dataSource.getOwnedDevicesListViewModel(self, ownedCryptoId: ownedCryptoId)
            defer { dataSources.dataSource.finishOwnedDevicesListViewModel(self, streamUUID: streamUUID) }
            for await receivedModel in stream {
                switch loadModelState {
                case .loading:
                    loadModelState = .loaded(receivedModel)
                case .loaded:
                    withAnimation { loadModelState = .loaded(receivedModel) }
                }
            }
        } catch {
            assertionFailure()
        }
    }
    
    private var navigationTitle: String {
        String(localizedInThisBundle: "NAVIGATION_TITLE_YOUR_DEVICES")
    }
    
    public var body: some View {
        ScrollView {
            Group {
                switch loadModelState {
                case .loading:
                    ObvCenteredProgressView()
                case .loaded(let model):
                    ModelView(ownedCryptoId: ownedCryptoId,
                              model: model,
                              dataSources: dataSources,
                              actions: actions,
                              internalActions: self)
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .task(onTask)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
    
}


extension OwnedDevicesListView: OwnedDevicesListViewInternalActions {
    
    func userWantsToSearchForNewOwnedDevices() async throws {
        try await actions.userWantsToSearchForNewOwnedDevices(self, ownedCryptoId: ownedCryptoId)
    }
    
    func userWantsToClearAllOtherOwnedDevicesAndHasConfirmed() async throws {
        try await actions.userWantsToClearAllOtherOwnedDevicesAndHasConfirmed(self, ownedCryptoId: ownedCryptoId)
    }
    
    func userWantsToSeeSubscriptionPlans() {
        navigation.userWantsToSeeSubscriptionPlans(self)
    }
    
}


@MainActor
protocol OwnedDevicesListViewInternalActions {
    func userWantsToSearchForNewOwnedDevices() async throws
    func userWantsToClearAllOtherOwnedDevicesAndHasConfirmed() async throws
    func userWantsToSeeSubscriptionPlans()
}


extension OwnedDevicesListView{
    struct ModelView: View {
        
        let ownedCryptoId: ObvCryptoId
        let model: Model
        let dataSources: DataSources
        let actions: OwnedDevicesListViewActions
        let internalActions: any OwnedDevicesListViewInternalActions
        
        private func userWantsToClearAllOtherOwnedDevicesAndMustConfirm() {
            isAlertPresented = true
        }
        
        @State private var isAlertPresented: Bool = false
        
        @State private var isSearchingForNewOwnedDevices: Bool = false
        @State private var isClearingAllOwnedDevices: Bool = false
        
        private func userWantsToSearchForNewOwnedDevices() {
            withAnimation { isSearchingForNewOwnedDevices = true }
            Task {
                defer { withAnimation { isSearchingForNewOwnedDevices = false } }
                try await internalActions.userWantsToSearchForNewOwnedDevices()
            }
        }
        
        private func userWantsToClearAllOtherOwnedDevicesAndHasConfirmed() {
            withAnimation { isClearingAllOwnedDevices = true }
            Task {
                defer { withAnimation { isClearingAllOwnedDevices = false } }
                try await internalActions.userWantsToClearAllOtherOwnedDevicesAndHasConfirmed()
            }
        }

        var body: some View {
            VStack {
                
                ForEach(model.ownedDeviceUIDs) { deviceUID in
                    ObvCardView(padding: 0) {
                        OwnedDeviceView(
                            ownedDeviceIdentifier: .init(ownedCryptoId: ownedCryptoId, deviceUID: deviceUID),
                            dataSource: dataSources.ownedDeviceViewDataSource,
                            actions: actions,
                            navigation: self)
                    }
                    .padding(.bottom)
                }
                
                Group {
                    OlvidButtonNew(action: userWantsToSearchForNewOwnedDevices) {
                        HStack {
                            if isSearchingForNewOwnedDevices { ProgressView().progressViewStyle(.circular).tint(.white) }
                            Label(title: { Text("SEARCH_FOR_NEW_DEVICES") }, icon: { Image(systemIcon: .magnifyingglass) })
                        }
                    }
                    OlvidButtonNew(action: userWantsToClearAllOtherOwnedDevicesAndMustConfirm) {
                        HStack {
                            if isClearingAllOwnedDevices { ProgressView().progressViewStyle(.circular).tint(.white) }
                            Label(title: { Text("CLEAR_ALL_DEVICES") }, icon: { Image(systemIcon: .trash) })
                        }
                    }
                    .tint(.red)
                }
                .disabled(isClearingAllOwnedDevices || isSearchingForNewOwnedDevices)
                Spacer()
                
            }
            .padding()
            .alert(isPresented: $isAlertPresented) {
                Alert(title: Text("CLEAR_ALL_OTHER_OWNED_DEVICES_ALERT_TITLE"),
                      message: Text("CLEAR_ALL_OTHER_OWNED_DEVICES_ALERT_MESSAGE"),
                      primaryButton: Alert.Button.destructive(Text("Yes"), action: userWantsToClearAllOtherOwnedDevicesAndHasConfirmed),
                      secondaryButton: Alert.Button.cancel())
            }
        }
    }
    
}
    

extension OwnedDevicesListView.ModelView : OwnedDeviceViewNavigation {
    
    func userWantsToSeeSubscriptionPlans(_ view: OwnedDeviceView) {
        internalActions.userWantsToSeeSubscriptionPlans()
    }

}



// MARK: - Previews

#if DEBUG

private final class DataSourceAndActionsForPreviews {}

extension DataSourceAndActionsForPreviews: OwnedDevicesListViewDataSource {
    
    func getOwnedDevicesListViewModel(_ view: OwnedDevicesListView, ownedCryptoId: ObvTypes.ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<OwnedDevicesListView.Model>) {
        let stream = AsyncStream<OwnedDevicesListView.Model> { (continuation: AsyncStream<OwnedDevicesListView.Model>.Continuation) in
            Task {
                let model: OwnedDevicesListView.Model = .init(
                    ownedDeviceUIDs: [
                        UID.zero,
                        UID(uid: .init(repeating: 0x01, count: UID.length))!]
                )
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishOwnedDevicesListViewModel(_ view: OwnedDevicesListView, streamUUID: UUID) {}
    
}

extension DataSourceAndActionsForPreviews: OwnedDeviceViewDataSource {

    func getAsyncSequenceOfOwnedDeviceViewModel(_ view: OwnedDeviceView, ownedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<OwnedDeviceView.Model>) {
        let stream = AsyncStream<OwnedDeviceView.Model> { (continuation: AsyncStream<OwnedDeviceView.Model>.Continuation) in
            Task {
                switch ownedDeviceIdentifier {
                case .init(ownedCryptoId: ownedDeviceIdentifier.ownedCryptoId, deviceUID: UID.zero):
                    let model: OwnedDeviceView.Model = .init(
                        ownedDeviceName: "Current device name",
                        secureChannelStatus: .currentDevice,
                        latestRegistrationDate: Date.now.addingTimeInterval(-.init(hours: 2)),
                        ownedIdentityIsActive: true,
                        expiration: .init(date: Date.now.addingTimeInterval(.init(days: 2)),
                                          deviceWithoutExpiration: .init(deviceUID: UID(uid: .init(repeating: 0x01, count: UID.length))!,
                                                                         deviceName: "Other device name")),
                        ownedIdentityEffectiveAPIPermissionsContainsMultidevice: false)
                    continuation.yield(model)
                default:
                    let model: OwnedDeviceView.Model = .init(
                        ownedDeviceName: "Other device name",
                        secureChannelStatus: .created(preKeyAvailable: true),
                        latestRegistrationDate: Date.now.addingTimeInterval(-.init(hours: 2)),
                        ownedIdentityIsActive: true,
                        expiration: nil,
                        ownedIdentityEffectiveAPIPermissionsContainsMultidevice: false)
                    continuation.yield(model)
                }
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOwnedDeviceViewModel(_ view: OwnedDeviceView, streamUUID: UUID) {}

}

extension DataSourceAndActionsForPreviews: OwnedDeviceViewActions {
    
    func userWantsToUpdateOwnedDeviceName(_ view: OwnedDeviceView, ownedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier, newName: String) async throws {
        print("User wants to update owned device name")
    }
    
    func userWantsToDeactivateOtherOwnedDevice(_ view: OwnedDeviceView, otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier) async throws {
        try await Task.sleep(seconds: 2)
    }

    func userRequestedSettingUnexpiringDevice(_ view: OwnedDeviceView, identifierOfOwnedDeviceToKeepActive: ObvOwnedDeviceIdentifier) async throws {
        try await Task.sleep(seconds: 2)
    }

    func userWantsToRestartChannelCreationWithOtherOwnedDevice(_ view: OwnedDeviceView, otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier) async throws {
        try await Task.sleep(seconds: 2)
    }

}

extension DataSourceAndActionsForPreviews: OwnedDevicesListViewActions {
    
    func userWantsToSearchForNewOwnedDevices(_ view: OwnedDevicesListView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws {
        try? await Task.sleep(seconds: 3)
    }
    
    func userWantsToClearAllOtherOwnedDevicesAndHasConfirmed(_ view: OwnedDevicesListView, ownedCryptoId: ObvCryptoId) async throws {
        try? await Task.sleep(seconds: 3)
    }
    
}

extension DataSourceAndActionsForPreviews: OwnedDevicesListViewNavigation {
    
    func userWantsToSeeSubscriptionPlans(_ view: OwnedDevicesListView) {
        print("User wants to see subscription plans")
    }
    
}

@MainActor
private let dataSourceAndActionsForPreviews = DataSourceAndActionsForPreviews()

#Preview {
    NavigationStack {
        OwnedDevicesListView(ownedCryptoId: .sampleOwnedCryptoId,
                             dataSources: .init(dataSource: dataSourceAndActionsForPreviews,
                                                ownedDeviceViewDataSource: dataSourceAndActionsForPreviews),
                             actions: dataSourceAndActionsForPreviews,
                             navigation: dataSourceAndActionsForPreviews)
    }
}

#endif
