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
import ObvDesignSystem


@MainActor
public protocol ObvListOfContactDevicesViewDataSource: ObvContactDeviceViewDataSource {
    func getAsyncStreamOfObvListOfContactDevicesViewModel(_ view: ObvListOfContactDevicesView, contactIdentifier: ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvListOfContactDevicesView.Model>)
    func finishAsyncStreamOfObvListOfContactDevicesViewModel(_ view: ObvListOfContactDevicesView, streamUUID: UUID)
}


@MainActor
public protocol ObvListOfContactDevicesViewActions: ObvContactDeviceViewActions {
    func userWantsToSearchForNewContactDevices(_ view: ObvListOfContactDevicesView, contactIdentifier: ObvContactIdentifier) async throws
    func userWantsToClearAllContactDevices(_ view: ObvListOfContactDevicesView, contactIdentifier: ObvContactIdentifier) async throws
}


public struct ObvListOfContactDevicesView: View {
    
    public let contactIdentifier: ObvContactIdentifier
    public let dataSource: any ObvListOfContactDevicesViewDataSource
    public let actions: any ObvListOfContactDevicesViewActions
    
    public init(contactIdentifier: ObvContactIdentifier, dataSource: any ObvListOfContactDevicesViewDataSource, actions: any ObvListOfContactDevicesViewActions) {
        self.contactIdentifier = contactIdentifier
        self.dataSource = dataSource
        self.actions = actions
    }
    
    @State private var model: Model?
    @State private var isInterfaceDisabled: Bool = false
    
    
    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfObvListOfContactDevicesViewModel(self, contactIdentifier: contactIdentifier)
            for await receivedModel in stream {
                withAnimation {
                    self.model = receivedModel
                }
            }
            dataSource.finishAsyncStreamOfObvListOfContactDevicesViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }

    @State private var hudCategory: HUDView.Category? = nil
    
    public var body: some View {
        ZStack {
            if let model {
                ObvListOfContactDevicesInternalView(
                    model: model,
                    datasource: dataSource,
                    actions: actions,
                    buttonActions: self)
                .navigationTitle(Text("LIST_OF_\(model.contactDisplayName)_DEVICES"))
            } else {
                HStack {
                    Spacer(minLength: 0)
                    ObvCenteredProgressView()
                    Spacer(minLength: 0)
                }
            }
            
            if let hudCategory = self.hudCategory {
                HUDView(category: hudCategory)
            }

        }
        .disabled(isInterfaceDisabled)
        .task(onTask)
        .background(Color(UIColor.systemGroupedBackground))
    }
    
}


extension ObvListOfContactDevicesView: ObvButtonsForListOfDevicesViewActions {
    
    func userWantsToSearchForMissingDevices() {
        withAnimation {
            isInterfaceDisabled = true
            hudCategory = .progress
        }
        Task {
            defer { withAnimation { isInterfaceDisabled = false } }
            do {
                try await actions.userWantsToSearchForNewContactDevices(self, contactIdentifier: contactIdentifier)
                withAnimation { hudCategory = .checkmark }
            } catch {
                assertionFailure()
                withAnimation { hudCategory = .xmark }
            }
            try? await Task.sleep(seconds: 1)
            withAnimation { hudCategory = nil }
        }
    }
    
    func userWantsToClearAllDevices() {
        withAnimation {
            isInterfaceDisabled = true
            hudCategory = .progress
        }
        Task {
            defer { withAnimation { isInterfaceDisabled = false } }
            do {
                try await actions.userWantsToClearAllContactDevices(self, contactIdentifier: contactIdentifier)
                withAnimation { hudCategory = .checkmark }
            } catch {
                assertionFailure()
                withAnimation { hudCategory = .xmark }
            }
            try? await Task.sleep(seconds: 1)
            withAnimation { hudCategory = nil }
        }
    }
    
}


// MARK: - Model

extension ObvListOfContactDevicesView {
    
    public struct Model: Sendable, Equatable {
        let contactIdentifier: ObvContactIdentifier
        let contactDisplayName: String
        let contactDeviceIdentifiers: [ObvContactDeviceIdentifier]
        
        public init(contactIdentifier: ObvContactIdentifier, contactDisplayName: String, contactDeviceIdentifiers: [ObvContactDeviceIdentifier]) {
            self.contactIdentifier = contactIdentifier
            self.contactDisplayName = contactDisplayName
            self.contactDeviceIdentifiers = contactDeviceIdentifiers
        }
        
    }
    
}


// MARK: - Internal view

private struct ObvListOfContactDevicesInternalView: View {

    let model: ObvListOfContactDevicesView.Model
    let datasource: ObvListOfContactDevicesViewDataSource
    let actions: ObvListOfContactDevicesViewActions
    let buttonActions: ObvButtonsForListOfDevicesViewActions
    
    var body: some View {
        ScrollView {
            VStack {
                
                ForEach(model.contactDeviceIdentifiers) { contactDeviceIdentifier in
                    ObvCardView {
                        ObvContactDeviceView(
                            deviceIdentifier: contactDeviceIdentifier,
                            dataSource: datasource,
                            actions: actions)
                    }
                    .padding(.horizontal)
                }
                
                ObvButtonsForListOfDevicesView(actions: buttonActions)
                    .padding([.horizontal, .top])

            }
        }
    }
    
}






#if DEBUG

// MARK: - Previews

private final class DataSourceAndActionsForPreviews {}


extension DataSourceAndActionsForPreviews: ObvContactDeviceViewDataSource {
    
    func getAsyncStreamOfObvContactDeviceViewModel(_ view: ObvContactDeviceView, contactDeviceIdentifier: ObvTypes.ObvContactDeviceIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvContactDeviceView.Model>) {
        let stream = AsyncStream<ObvContactDeviceView.Model> { (continuation: AsyncStream<ObvContactDeviceView.Model>.Continuation) in
            let model = ObvContactDeviceView.Model.sampleData(contactDeviceIdentifier: contactDeviceIdentifier)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfObvContactDeviceViewModel(_ view: ObvContactDeviceView, streamUUID: UUID) {}
    
}


extension DataSourceAndActionsForPreviews: ObvListOfContactDevicesViewDataSource {
    
    func getAsyncStreamOfObvListOfContactDevicesViewModel(_ view: ObvListOfContactDevicesView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvListOfContactDevicesView.Model>) {
        let stream = AsyncStream<ObvListOfContactDevicesView.Model> { (continuation: AsyncStream<ObvListOfContactDevicesView.Model>.Continuation) in
            let model = ObvListOfContactDevicesView.Model(
                contactIdentifier: contactIdentifier,
                contactDisplayName: "Alice",
                contactDeviceIdentifiers: ObvContactDeviceIdentifier.sampleDatas)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfObvListOfContactDevicesViewModel(_ view: ObvListOfContactDevicesView, streamUUID: UUID) {}
    
}


extension DataSourceAndActionsForPreviews: ObvContactDeviceViewActions {
    
    func userWantsToRestartChannelCreationWithContactDevice(_ view: ObvContactDeviceView, contactDeviceIdentifier: ObvTypes.ObvContactDeviceIdentifier) async {
        print("User wants to restart channel creation with contact device")
    }

}


extension DataSourceAndActionsForPreviews: ObvListOfContactDevicesViewActions {
    
    func userWantsToSearchForNewContactDevices(_ view: ObvListOfContactDevicesView, contactIdentifier: ObvTypes.ObvContactIdentifier) async {
        print("User wants to search for missing devices")
    }
    
    func userWantsToClearAllContactDevices(_ view: ObvListOfContactDevicesView, contactIdentifier: ObvTypes.ObvContactIdentifier) async {
        print("User wants to clear all devices")
    }
    
}


@MainActor
private let dataSourceAndActionsForPreviews = DataSourceAndActionsForPreviews()

#Preview {
    NavigationStack {
        ObvListOfContactDevicesView(
            contactIdentifier: .sampleData,
            dataSource: dataSourceAndActionsForPreviews,
            actions: dataSourceAndActionsForPreviews)
    }
}

#endif
