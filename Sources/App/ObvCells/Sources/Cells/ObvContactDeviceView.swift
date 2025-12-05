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
import ObvTypes



@MainActor
public protocol ObvContactDeviceViewDataSource {
    func getAsyncStreamOfObvContactDeviceViewModel(_ view: ObvContactDeviceView, contactDeviceIdentifier: ObvContactDeviceIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvContactDeviceView.Model>)
    func finishAsyncStreamOfObvContactDeviceViewModel(_ view: ObvContactDeviceView, streamUUID: UUID)
}


@MainActor
public protocol ObvContactDeviceViewActions {
    func userWantsToRestartChannelCreationWithContactDevice(_ view: ObvContactDeviceView, contactDeviceIdentifier: ObvContactDeviceIdentifier) async throws
}


// MARK: - ObvContactDeviceView

public struct ObvContactDeviceView: View {
    
    let deviceIdentifier: ObvContactDeviceIdentifier
    let dataSource: ObvContactDeviceViewDataSource
    let actions: ObvContactDeviceViewActions

    public struct Model: Sendable, Equatable {
        let deviceIdentifier: ObvContactDeviceIdentifier
        let name: String
        let secureChannelStatus: SecureChannelStatus
        
        public init(contactDeviceIdentifier: ObvContactDeviceIdentifier, name: String, secureChannelStatus: SecureChannelStatus) {
            self.deviceIdentifier = contactDeviceIdentifier
            self.name = name
            self.secureChannelStatus = secureChannelStatus
        }
        
        public enum SecureChannelStatus: Sendable, Equatable {
            case creationInProgress(preKeyAvailable: Bool)
            case created(preKeyAvailable: Bool)
        }
        
        var isPreKeyAvailable: Bool {
            switch secureChannelStatus {
            case .creationInProgress(let preKeyAvailable),
                    .created(let preKeyAvailable):
                return preKeyAvailable
            }
        }
        
    }

    @State private var model: Model?
    
    @State private var isInterfaceDisabled: Bool = false
    
    private func userWantsToRestartChannelCreationWithThisDevice() {
        isInterfaceDisabled = true
        Task {
            defer { isInterfaceDisabled = false }
            do {
                try await actions.userWantsToRestartChannelCreationWithContactDevice(self, contactDeviceIdentifier: deviceIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
    
    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfObvContactDeviceViewModel(self, contactDeviceIdentifier: deviceIdentifier)
            for await receivedModel in stream {
                withAnimation {
                    self.model = receivedModel
                }
            }
            dataSource.finishAsyncStreamOfObvContactDeviceViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }

    
    public var body: some View {
        Group {
            if let model {
                ObvContactDeviceInternalView(
                    model: model,
                    userWantsToRestartChannelCreationWithThisDevice: userWantsToRestartChannelCreationWithThisDevice)
            } else {
                HStack {
                    Spacer(minLength: 0)
                    ObvCenteredProgressView()
                    Spacer(minLength: 0)
                }
            }
        }
        .disabled(isInterfaceDisabled)
        .task(onTask)
    }
    
}


// MARK: - Internal view

private struct ObvContactDeviceInternalView: View {

    let model: ObvContactDeviceView.Model
    let userWantsToRestartChannelCreationWithThisDevice: () -> Void
    
    private var textForSecureChannelStatus: String {
        switch model.secureChannelStatus {
        case .creationInProgress:
            return String(localizedInThisBundle: "SECURE_CHANNEL_CREATION_IN_PROGRESS")
        case .created:
            return String(localizedInThisBundle: "SECURE_CHANNEL_CREATED")
        }
    }

    
    private var systemIconForSecureChannelStatus: SystemIcon {
        switch model.secureChannelStatus {
        case .creationInProgress:
            return .arrowTriangle2CirclepathCircle
        case .created:
            return .checkmarkShield
        }
    }

    
    private var colorForSecureChannelStatus: Color {
        switch model.secureChannelStatus {
        case .creationInProgress:
            return .primary
        case .created:
            return .green
        }
    }

    
    private var textForPreKeyStatus: String {
        if model.isPreKeyAvailable {
            return String(localizedInThisBundle: "PRE_KEY_IS_AVAILABLE_FOR_CONTACT_DEVICE")
        } else {
            return String(localizedInThisBundle: "PRE_KEY_IS_NOT_AVAILABLE_FOR_CONTACT_DEVICE")
        }
    }

    
    private var systemIconForPreKeyStatus: SystemIcon {
        if model.isPreKeyAvailable {
            return .key
        } else {
            return .keySlash
        }
    }

    
    private var systemIconColorForPreKeyStatus: Color {
        if model.isPreKeyAvailable {
            return Color(UIColor.systemGreen)
        } else {
            return .primary
        }
    }

    
    var body: some View {
        VStack(alignment: .leading) {
            
            HStack {
                Text("DEVICE \(model.name)")
                    .font(.headline)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                Spacer()
            }
            .padding(.bottom, 4.0)
            
            HStack {
                Label {
                    Text(textForSecureChannelStatus)
                        .font(.body)
                        .foregroundColor(.primary)
                } icon: {
                    Image(systemIcon: systemIconForSecureChannelStatus)
                        .foregroundColor(colorForSecureChannelStatus)
                }
            }
            .padding(.bottom, 2.0)
            
            HStack {
                Label {
                    Text(textForPreKeyStatus)
                        .font(.body)
                        .foregroundColor(.primary)
                } icon: {
                    Image(systemIcon: systemIconForPreKeyStatus)
                        .foregroundColor(systemIconColorForPreKeyStatus)
                }
            }
            .padding(.bottom, 2.0)

            Button(action: userWantsToRestartChannelCreationWithThisDevice) {
                Label(title: { Text("RECREATE_SECURE_CHANNEL_WITH_THIS_DEVICE") }, icon: { Image(systemIcon: .restartCircle) })
            }
            .padding(.bottom, 4.0)
            
        }
    }
    
}



#if DEBUG

// MARK: - Previews

@MainActor
private final class DataSourceAndActionsForPreviews {}

extension DataSourceAndActionsForPreviews: ObvContactDeviceViewDataSource {
    
    func getAsyncStreamOfObvContactDeviceViewModel(_ view: ObvContactDeviceView, contactDeviceIdentifier: ObvTypes.ObvContactDeviceIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvContactDeviceView.Model>) {
        let stream = AsyncStream<ObvContactDeviceView.Model> { (continuation: AsyncStream<ObvContactDeviceView.Model>.Continuation) in
            Task {
                var index = 0
                while true {
                    try? await Task.sleep(seconds: 2)
                    let model = ObvContactDeviceView.Model.sampleDatas[index]
                    continuation.yield(model)
                    index = (index + 1) % ObvContactDeviceView.Model.sampleDatas.count
                }
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfObvContactDeviceViewModel(_ view: ObvContactDeviceView, streamUUID: UUID) {}
    
    
}


extension DataSourceAndActionsForPreviews: ObvContactDeviceViewActions {
    
    func userWantsToRestartChannelCreationWithContactDevice(_ view: ObvContactDeviceView, contactDeviceIdentifier: ObvTypes.ObvContactDeviceIdentifier) async {
        print("User wants to restart channel creation with contact device")
    }
    
}


@MainActor
private let dataSourceAndActionsForPreviews = DataSourceAndActionsForPreviews()

#Preview {
    ScrollView {
        VStack {
            ObvCardView {
                ObvContactDeviceView(deviceIdentifier: .sampleData,
                                     dataSource: dataSourceAndActionsForPreviews,
                                     actions: dataSourceAndActionsForPreviews)
            }
            .padding()
        }
    }
    .background(Color(UIColor.secondarySystemBackground))
}


#endif
