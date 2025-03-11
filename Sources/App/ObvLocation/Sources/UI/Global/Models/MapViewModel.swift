/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvUICoreData
import CoreLocation
import SwiftUI
import MapKit
import Combine
import ObvTypes

@available(iOS 17.0, *)
final class MapViewModel: MapViewModelProtocol {
    
    enum DragState {
        case dragging
        case dragEnded
        case notDragging
    }
    
    private(set) var ownedIdentity: PersistedObvOwnedIdentity
    
    @Published var position: MapCameraPosition
    @Published var userPosition: CLLocationCoordinate2D?
    @Published var usersToDisplay: [MapUserPositionContentViewModel] = []
    @Published var enableInteraction: Bool = false
    
    @Published var centeredToCurrentUser: Bool = false
    @Published var centeredUserContent: MapUserPositionContentViewModel? = nil
    
    @Published var selectedUserContent: MapUserPositionContentViewModel? = nil
    @Published var mapCameraChanged: Bool = false // Boolean telling if it move from dragging or not.
    @Published var mapCameraIsMoving: Bool = false
    @Published var dragState: DragState = .notDragging
    
    private(set) var interactionModes: MapInteractionModes = []
    var isAnimated = false
    var hasAppeared = false
    
    @Published var selectedContactCryptoId: ObvCryptoId?
    
    @Published var currentLocation: CLLocation?
    
    private var cancellables: Set<AnyCancellable> = []
    
    init(ownedIdentity: PersistedObvOwnedIdentity) {
        self.ownedIdentity = ownedIdentity
        position = .region(MKCoordinateRegion(.world))
        self.bind()
    }
    
    private func bind() {
        ObvLocationService.shared.$location.removeDuplicates().sink { [weak self] location in
            Task { [weak self] in
                guard let self else { return }
                await self.updateUserLocation(location)
            }
        }.store(in: &cancellables)
        
        $enableInteraction.sink { [weak self] enableInteraction in
            guard let self else { return }
            if enableInteraction {
                self.interactionModes = [.all]
            } else {
                self.interactionModes = []
            }
        }.store(in: &cancellables)
        
        $centeredToCurrentUser.sink { [weak self] centeredToCurrentUser in
            Task { [weak self] in
                guard let self else { return }
                await self.centerToCurrentUser(shouldCenter: centeredToCurrentUser)
            }
        }.store(in: &cancellables)
        
        $centeredUserContent.sink { [weak self] centeredUserContent in
            guard let self else { return }
            if let centeredUserContent, !self.mapCameraIsMoving {
                self.position = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: centeredUserContent.location.coordinate.latitude,
                                                                                           longitude: centeredUserContent.location.coordinate.longitude),
                                                  distance: 1000.0))
            }
        }.store(in: &cancellables)
        
    }
    
    func centerToCurrentUser(shouldCenter centeredToCurrentUser: Bool) async {
        if hasAppeared {
            self.isAnimated = centeredToCurrentUser
        }
        
        // Recenter the map to the current user position
        guard centeredToCurrentUser, !self.mapCameraIsMoving, let lastLocation = await ObvLocationService.shared.lastLocation else { return }
        self.position = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: lastLocation.coordinate.latitude,
                                                                                   longitude: lastLocation.coordinate.longitude),
                                          distance: 1000.0))
    }
    
    func onAppear() {}
    
    func onTask() async {
        do {
            try await ObvLocationService.shared.startMonitoringLocationContinuously()
        } catch {
            debugPrint("Error while sharing location continuously: \(error)")
        }
    }
    
    func onDisappear() {
        if ContinuousSharingLocationService.shared.continuousSharingLocationCanBeStopped {
            Task { await ObvLocationService.shared.stopUpdatingLocation() }
        }
    }
}

@available(iOS 17.0, *)
extension MapViewModel {
    
    private func updateUserLocation(_ location: CLLocation?) async {
        //If we follow user, we update the map position to the center of the current user
        if self.centeredToCurrentUser { await centerToCurrentUser(shouldCenter: true) }
        
        if let location = location {
            userPosition = CLLocationCoordinate2D(latitude: location.coordinate.latitude,
                                                  longitude: location.coordinate.longitude)
        } else {
            debugPrint("current user location: unknown")
        }
    }
    
}
