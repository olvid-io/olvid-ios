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
import ObvAppTypes
import ObvTypes
import ObvSystemIcon
import ObvAppCoreConstants
import OSLog
import ObvDesignSystem

public struct LocationsCellViewModel: Sendable, Hashable, Equatable {
    
    let ownedCryptoId: ObvCryptoId
    let numberOfLocationsReceivedForTheCurrentOwnedCryptoId: Int
    let someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice: Bool
 
    var isRelevantToDisplay: Bool {
        numberOfLocationsReceivedForTheCurrentOwnedCryptoId > 0 || someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice
    }
    
}

@MainActor
protocol LocationsCellViewActions {
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice()
    func userWantsToShowMapToConsultLocationSharedContinously(ownedCryptoId: ObvCryptoId) async throws
}

public struct LocationsCellView: View {
    
    let viewModel: LocationsCellViewModel?
    let actions: LocationsCellViewActions
    
    init(viewModel: LocationsCellViewModel?, actions: LocationsCellViewActions) {
        self.viewModel = viewModel
        self.actions = actions
    }
    
    private let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "LocationsCellView")
            
    private func showMapButtonTapped() {
        guard let viewModel else { assertionFailure(); return }
        Task {
            do {
                try await actions.userWantsToShowMapToConsultLocationSharedContinously(ownedCryptoId: viewModel.ownedCryptoId)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }

    private var doEmbedInternalViewInButton: Bool {
        guard let viewModel else { return false }
        return viewModel.numberOfLocationsReceivedForTheCurrentOwnedCryptoId > 0
    }
    
    public var body: some View {
        if let viewModel {
            if doEmbedInternalViewInButton {
                Button(action: showMapButtonTapped) {
                    InternalView(viewModel: viewModel, actions: actions)
                }
            } else {
                InternalView(viewModel: viewModel, actions: actions)
            }
        } else {
            ProgressView()
                .padding()
        }
    }
    
    
    private struct InternalView: View {
        
        let viewModel: LocationsCellViewModel
        let actions: LocationsCellViewActions

        private func stopSharingButtonTapped() {
            actions.userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice()
        }
        
        var body: some View {
            HStack {
                
                Label {
                    switch (viewModel.someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice, viewModel.numberOfLocationsReceivedForTheCurrentOwnedCryptoId > 0) {
                    case (false, false):
                        Text("LOCATION_CELL_LABEL_YOU_ARE_NOT_SHARING_YOUR_LOCATION")
                    case (false, true):
                        Text("LOCATION_CELL_LABEL_\(viewModel.numberOfLocationsReceivedForTheCurrentOwnedCryptoId)_LOCATIONS_ARE_SHARED_WITH_YOU")
                    case (true, false):
                        Text("LOCATION_CELL_LABEL_YOU_ARE_CURRENTLY_SHARING_YOUR_LOCATION")
                    case (true, true):
                        Text("LOCATION_CELL_LABEL_YOU_ARE_CURRENTLY_SHARING_YOUR_LOCATION_AND_\(viewModel.numberOfLocationsReceivedForTheCurrentOwnedCryptoId)_LOCATIONS_ARE_SHARED_WITH_YOU")
                    }
                } icon: {
                    Image(systemIcon: .locationCircle)
                        .foregroundStyle(Color(UIColor.systemBlue))
                }
                .multilineTextAlignment(.leading)
                .tint(.primary)

                Spacer()
                
                if viewModel.someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice {
                    Button("STOP_SHARING", role: .destructive, action: stopSharingButtonTapped)
                        .buttonStyle(.bordered)
                }
                
                if viewModel.numberOfLocationsReceivedForTheCurrentOwnedCryptoId > 0 {
                    ObvChevronRight()
                }
                
            }
            .padding()
        }
        
    }

    
    
}


#if DEBUG

@MainActor
private let ownedCryptoIdForPreviews = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)


private final class ActionsForPreviews: LocationsCellViewActions {
    
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice() {
        print("Button tapped: userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice")
    }
    
    func userWantsToShowMapToConsultLocationSharedContinously(ownedCryptoId: ObvCryptoId) async throws {
        print("Button tapped: show map")
    }
    
}


@MainActor
private let actionsForPreviews = ActionsForPreviews()

#Preview("None") {
    LocationsCellView(viewModel: .init(ownedCryptoId: ownedCryptoIdForPreviews,
                                       numberOfLocationsReceivedForTheCurrentOwnedCryptoId: 0,
                                       someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice: false),
                      actions: actionsForPreviews)
}

#Preview("One shared") {
    LocationsCellView(viewModel: .init(ownedCryptoId: ownedCryptoIdForPreviews,
                                       numberOfLocationsReceivedForTheCurrentOwnedCryptoId: 1,
                                       someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice: false),
                      actions: actionsForPreviews)
}

#Preview("Two shared") {
    LocationsCellView(viewModel: .init(ownedCryptoId: ownedCryptoIdForPreviews,
                                       numberOfLocationsReceivedForTheCurrentOwnedCryptoId: 2,
                                       someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice: false),
                      actions: actionsForPreviews)
}

#Preview("Sharing") {
    LocationsCellView(viewModel: .init(ownedCryptoId: ownedCryptoIdForPreviews,
                                       numberOfLocationsReceivedForTheCurrentOwnedCryptoId: 0,
                                       someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice: true),
                      actions: actionsForPreviews)
}

#Preview("All") {
    LocationsCellView(viewModel: .init(ownedCryptoId: ownedCryptoIdForPreviews,
                                       numberOfLocationsReceivedForTheCurrentOwnedCryptoId: 3,
                                       someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice: true),
                      actions: actionsForPreviews)
}

#endif
