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
import MapKit
import ObvAppTypes
import ObvAppCoreConstants



@MainActor
protocol ObvSharingMapViewActionsProtocol: AnyObject {
    func userWantsToSendLocation(_ locationData: ObvLocationData, discussionIdentifier: ObvDiscussionIdentifier)
    func userWantsToShareLocationContinuously(initialLocationData: ObvLocationData, expirationMode: SharingLocationExpirationMode, discussionIdentifier: ObvDiscussionIdentifier) async throws
    func userWantsToDismissObvSharingMapView()
}


public struct ObvSharingMapViewModel: Sendable {
    
    let discussionIdentifier: ObvDiscussionIdentifier
    let isAlreadyContinouslySharingLocationFromCurrentDevice: Bool
    
    public init(isAlreadyContinouslySharingLocationFromCurrentDevice: Bool, discussionIdentifier: ObvDiscussionIdentifier) {
        self.isAlreadyContinouslySharingLocationFromCurrentDevice = isAlreadyContinouslySharingLocationFromCurrentDevice
        self.discussionIdentifier = discussionIdentifier
    }
}


// MARK: - Main View ObvSharingMapView

@available(iOS 17.0, *)
public struct ObvSharingMapView: View {
    
    let model: ObvSharingMapViewModel
    let actions: any ObvSharingMapViewActionsProtocol
    
    @State private var mapSharingType: MapSharingType = .continuous
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var centerCoordinate: CLLocationCoordinate2D? // Used to send a "pin"
    @State private var currentLocationOfPhysicalDevice: CLLocation? // Used to send the initial position when performing a continuous location sharing

    private let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ObvSharingMapView")
    
    private func userWantsToSwitchType() {
        mapSharingType.toggle()
        if mapSharingType == .continuous {
            cameraPosition = .userLocation(fallback: .automatic)
        } else {
            cameraPosition = .automatic
        }
    }
    
    
    private func onTask() async {
        do {
            let updates = CLLocationUpdate.liveUpdates()
            for try await update in updates {
                guard let location = update.location else { continue }
                self.currentLocationOfPhysicalDevice = location
            }
        } catch {
            logger.fault("Failed to subscribe to live location updates: \(error.localizedDescription)")
            assertionFailure()
        }
    }

    
    private func userWantsToSharePlace() {
        guard mapSharingType == .landmark, let centerCoordinate else { return }
        let centerLocation = CLLocation(latitude: centerCoordinate.latitude, longitude: centerCoordinate.longitude)
        Task {
            let address = try? await ObvLocationGeocodingService.shared.reverseGeocoding(from: centerLocation)
            let locationData = ObvLocationData(clLocation: centerLocation, isStationary: false).withAddress(address)
            self.actions.userWantsToSendLocation(locationData, discussionIdentifier: model.discussionIdentifier)
        }
    }

    
    private var sharingTypeButton: some View {
        Button(action: userWantsToSwitchType) {
            mapSharingType.icon
                .padding(.all, 10.0)
                .frame(width: 40.0, height: 40.0)
                .foregroundColor(.white)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .clipShape(Circle())
        }
    }

    
    private var sharingButton: some View {
        Button(action: userWantsToSharePlace) {
            mapSharingType.text
                .font(.system(size: 12.0, weight: .semibold, design: .default))
                .padding(.horizontal, 35.0)
                .frame(height: 40.0)
                .foregroundColor(Color.white)
                .background(mapSharingType.background)
                .environment(\.colorScheme, .dark)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    
    public var body: some View {
        ZStack {
            Map(position: $cameraPosition,
                interactionModes: mapSharingType == .continuous ? [] : [.all]) {
                UserAnnotation()
            }
                .onMapCameraChange(frequency: .continuous, { mapCameraUpdateContext in
                    centerCoordinate = mapCameraUpdateContext.camera.centerCoordinate
                })
                .animation(.easeInOut, value: cameraPosition)
            
            if mapSharingType == .landmark { // User wants to share a particular location, we display a marker
                MapLandmarkView()
                    .alignmentGuide(VerticalAlignment.center) { viewDimensions in
                        let centerOffset = viewDimensions.height - 5.0
                        return centerOffset
                    }
                    .disabled(true)
            }
            
            VStack {
                HStack {
                    if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
                        Button(action: actions.userWantsToDismissObvSharingMapView) {
                            Text("CLOSE")
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 16.0)
                        .padding(.leading, 16.0)
                    }
                    sharingTypeButton
                        .padding(.top, 16.0)
                        .padding(.leading, 16.0)
                    Spacer()
                }
                Spacer()
                
                if mapSharingType == .landmark {
                    sharingButton
                        .padding(.bottom, 30.0)
                } else {
                    if model.isAlreadyContinouslySharingLocationFromCurrentDevice {
                        ContinuousSharingButtonWithoutExpiration(model: model,
                                                                 actions: actions,
                                                                 mapSharingType: mapSharingType,
                                                                 cameraPosition: cameraPosition,
                                                                 currentLocationOfPhysicalDevice: currentLocationOfPhysicalDevice)
                        .padding(.bottom, 30.0)
                    } else {
                        ContinuousSharingButton(model: model,
                                                actions: actions,
                                                mapSharingType: mapSharingType,
                                                cameraPosition: cameraPosition,
                                                currentLocationOfPhysicalDevice: currentLocationOfPhysicalDevice)
                        .padding(.bottom, 30.0)
                    }
                }
            }
        }
        .task { await onTask() }
    }
    
}



// MARK: - Subview ContinuousSharingButton

@available(iOS 17.0, *)
private struct ContinuousSharingButton: View {
    
    let model: ObvSharingMapViewModel
    let actions: any ObvSharingMapViewActionsProtocol
    let mapSharingType: MapSharingType
    let cameraPosition: MapCameraPosition
    let currentLocationOfPhysicalDevice: CLLocation?

    private func buttonTapped(expirationMode: SharingLocationExpirationMode) {
        Task {
            do {
                guard let currentLocationOfPhysicalDevice else { return }
                let locationData = ObvLocationData(clLocation: currentLocationOfPhysicalDevice, isStationary: false)
                try await actions.userWantsToShareLocationContinuously(initialLocationData: locationData, expirationMode: expirationMode, discussionIdentifier: model.discussionIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
    var body: some View {
        Menu {
            Section(header: Text("SHARE_MY_LOCATION").textCase(.uppercase)) {
                
                ForEach(SharingLocationExpirationMode.allCases, id: \.rawValue) { expirationMode in
                    Button(action: { buttonTapped(expirationMode: expirationMode) }) {
                        HStack {
                            expirationMode.text
                            expirationMode.image
                        }
                    }
                    .disabled(currentLocationOfPhysicalDevice == nil)
                }
            }
        } label: {
            mapSharingType.text
                .font(.system(size: 12.0, weight: .semibold, design: .default))
                .padding(.horizontal, 35.0)
                .frame(height: 40.0)
                .foregroundColor(Color.white)
                .background(mapSharingType.background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}



// MARK: - Subview ContinuousSharingButtonWithoutExpiration

@available(iOS 17.0, *)
fileprivate struct ContinuousSharingButtonWithoutExpiration: View {
    
    let model: ObvSharingMapViewModel
    let actions: any ObvSharingMapViewActionsProtocol
    let mapSharingType: MapSharingType
    let cameraPosition: MapCameraPosition
    let currentLocationOfPhysicalDevice: CLLocation?

    private func buttonTapped() {
        Task {
            do {
                guard let currentLocationOfPhysicalDevice else { return }
                let locationData = ObvLocationData(clLocation: currentLocationOfPhysicalDevice, isStationary: false)
                try await actions.userWantsToShareLocationContinuously(initialLocationData: locationData, expirationMode: SharingLocationExpirationMode.infinity, discussionIdentifier: model.discussionIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
    var body: some View {
        Button(action: buttonTapped) {
            mapSharingType.text
                .font(.system(size: 12.0, weight: .semibold, design: .default))
                .padding(.horizontal, 35.0)
                .frame(height: 40.0)
                .foregroundColor(Color.white)
                .background(mapSharingType.background)
                .environment(\.colorScheme, .dark)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .disabled(currentLocationOfPhysicalDevice == nil)
        }
    }
    
}



#if DEBUG

@MainActor
private final class ActionsForPreviews: ObvSharingMapViewActionsProtocol {
    
    func userWantsToSendLocation(_ locationData: ObvAppTypes.ObvLocationData, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) {
        print("userWantsToSendLocation")
    }
    
    func userWantsToShareLocationContinuously(initialLocationData: ObvAppTypes.ObvLocationData, expirationMode: SharingLocationExpirationMode, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async throws {
        print("userWantsToShareLocationContinuously")
    }
    
    func userWantsToDismissObvSharingMapView() {
        print("userWantsToDismissObvSharingMapView")
    }
    
    
}

@MainActor
private let model = ObvSharingMapViewModel(isAlreadyContinouslySharingLocationFromCurrentDevice: true, discussionIdentifier: ObvDiscussionIdentifier.sampleDatas[0])

@MainActor
private let actionsForPreviews = ActionsForPreviews()

@available(iOS 17.0, *)
#Preview {
    ObvSharingMapView(model: model, actions: actionsForPreviews)
}

#endif
