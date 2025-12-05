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
import OSLog
import ObvTypes
import ObvAppCoreConstants
import ObvDesignSystem



public struct ObvLocationsCellViewModel: Sendable, Hashable, Equatable {
    
    let ownedCryptoId: ObvCryptoId
    let numberOfLocationsReceivedForTheCurrentOwnedCryptoId: Int
    let someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice: Bool
 
    public init(ownedCryptoId: ObvCryptoId, numberOfLocationsReceivedForTheCurrentOwnedCryptoId: Int, someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice: Bool) {
        self.ownedCryptoId = ownedCryptoId
        self.numberOfLocationsReceivedForTheCurrentOwnedCryptoId = numberOfLocationsReceivedForTheCurrentOwnedCryptoId
        self.someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice = someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice
    }
    
    var isRelevantToDisplay: Bool {
        numberOfLocationsReceivedForTheCurrentOwnedCryptoId > 0 || someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice
    }
    
}


@MainActor
protocol LocationsCellViewActions {
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice() async throws
    func userWantsToShowMapToConsultLocationSharedContinously(ownedCryptoId: ObvCryptoId) async throws
}


@MainActor
public protocol ObvLocationsCellViewDataSource: AnyObject, Sendable {
    func getAsyncStreamOfLocationsCellViewModel(_ view: ObvDiscussionsListView, ownedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvLocationsCellViewModel>)
    func finishAsyncStreamOfLocationsCellViewModel(_ view: ObvDiscussionsListView, streamUUID: UUID)
}


struct LocationsCellView: View {
    
    let viewModel: ObvLocationsCellViewModel
    let actions: LocationsCellViewActions
    
    private let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "LocationsCellView")
            
    private func showMapButtonTapped() {
        Task {
            do {
                try await actions.userWantsToShowMapToConsultLocationSharedContinously(ownedCryptoId: viewModel.ownedCryptoId)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }

    private var doEmbedInternalViewInButton: Bool {
        return viewModel.numberOfLocationsReceivedForTheCurrentOwnedCryptoId > 0
    }
    
    public var body: some View {
        if doEmbedInternalViewInButton {
            Button(action: showMapButtonTapped) {
                InternalView(viewModel: viewModel, actions: actions)
            }
        } else {
            InternalView(viewModel: viewModel, actions: actions)
        }
    }
    
    
    private struct InternalView: View {
        
        let viewModel: ObvLocationsCellViewModel
        let actions: LocationsCellViewActions

        private func stopSharingButtonTapped() {
            Task {
                try? await actions.userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice()
            }
        }
        
        private var cornerSize: CGSize {
            if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
                return CGSize(width: 8, height: 8)
            } else {
                return CGSize(width: 12, height: 12)
            }
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
                    Button(String(localizedInThisBundle: "STOP_SHARING"), role: .destructive, action: stopSharingButtonTapped)
                        .buttonStyle(.bordered)
                }
                
                if viewModel.numberOfLocationsReceivedForTheCurrentOwnedCryptoId > 0 {
                    ObvChevronRight()
                }
                
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(RoundedRectangle(cornerSize: cornerSize, style: .continuous).foregroundStyle(Color(UIColor.secondarySystemBackground)))
        }
        
    }

    
    
}


#if DEBUG

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
    LocationsCellView(viewModel: ObvLocationsCellViewModel.sampleData[0],
                      actions: actionsForPreviews)
}

#Preview("One shared") {
    LocationsCellView(viewModel: ObvLocationsCellViewModel.sampleData[1],
                      actions: actionsForPreviews)
}

#Preview("Two shared") {
    LocationsCellView(viewModel:  ObvLocationsCellViewModel.sampleData[2],
                      actions: actionsForPreviews)
}

#Preview("Sharing") {
    LocationsCellView(viewModel:  ObvLocationsCellViewModel.sampleData[3],
                      actions: actionsForPreviews)
}

#Preview("All") {
    LocationsCellView(viewModel:  ObvLocationsCellViewModel.sampleData[4],
                      actions: actionsForPreviews)
}

#endif
