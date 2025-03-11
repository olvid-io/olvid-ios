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
import UIKit
import CoreLocation

@MainActor
public final class ObvLocationService: ObservableObject {
    
    // MARK: Attributes
    
    // MARK: Publisher of last location received
    @Published var location: CLLocation?
    
    // MARK: last location received statically
    var lastLocation: CLLocation? {
        get async {
            let locationManager = await getLocationManager()
            return await locationManager.lastLocation
        }
    }
    
    // MARK: asynchronously request the current location
    var currentLocation: CLLocation? {
        get async throws {
            try await requestLocation()
        }
    }
    
    // MARK: Check if locatin services are enabled
    var locationServicesEnabled: Bool {
        get async {
            let locationManager = await getLocationManager()
            return await locationManager.locationServicesEnabled
        }
    }
    
    // MARK: Singleton
    public static let shared = ObvLocationService()
    
    private(set) var locationManager: ObvLocationManager? // Accessed using getLocationManager()
    
    // MARK: Methods
    private init() {}
    
    private func getLocationManager() async -> ObvLocationManager {
        if let locationManager {
            return locationManager
        } else {
            let locationManager = await ObvLocationManager(allowsBackgroundLocationUpdates: true, distanceFilter: 10, pausesLocationUpdatesAutomatically: false)
            self.locationManager = locationManager
            return locationManager
        }
    }
    
    
    public func requestPermissionIfNotDetermined() async throws -> CLAuthorizationStatus {
        let locationManager = await getLocationManager()
        switch await locationManager.authorizationStatus {
        case .notDetermined:
            return try await locationManager.requestPermissionIfNotDetermined(.always)
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorizedAlways:
            return .authorizedAlways
        case .authorizedWhenInUse:
            return .authorizedWhenInUse
        @unknown default:
            assertionFailure()
            return .denied
        }
    }
    
    
//    @discardableResult
//    public func requestPermission() async throws -> CLAuthorizationStatus {
//        let locationManager = await getLocationManager()
//        if await currentUserCanUseLocation {
//            return await locationManager.authorizationStatus
//        }
//        return try await locationManager.requestPermission(.always)
//    }
    
    public var currentUserCanUseLocation: Bool {
        get async {
            let locationManager = await getLocationManager()
            let authorizationStatus = await locationManager.authorizationStatus
            return authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
        }
    }

//    public var isAuthorizationDenied: Bool {
//        get async {
//            let locationManager = await getLocationManager()
//            let authorizationStatus = await locationManager.authorizationStatus
//            debugPrint(authorizationStatus.rawValue)
//            return authorizationStatus == .denied
//        }
//    }
    
//    public var authorizationStatus: CLAuthorizationStatus {
//        get async {
//            let locationManager = await getLocationManager()
//            return await locationManager.authorizationStatus
//        }
//    }
    
    @discardableResult
    func requestLocation() async throws -> CLLocation? {
        let locationManager = await getLocationManager()

        //try await requestPermission()
        
        // we set a timeout of 10s in order to fetch current user location
        let locationEvent = try await locationManager.requestLocation(timeout: 10)
        
        switch locationEvent {
        case .didPause, .didResume, .didUpdateLocations:
            self.location = locationEvent.location
            return locationEvent.location
        case .didFail(let error):
            self.location = nil
            throw error
        }
    }
    
    func startMonitoringLocationContinuously() async throws {
        let locationManager = await getLocationManager()

        //try await requestPermission()
        
        for await event in try await locationManager.startMonitoringLocations() {
            switch event {
            case .didResume:
                debugPrint("location updates resume")
            case .didPause:
                debugPrint("location updates paused")
            case .didUpdateLocations(let locations):
                self.location = locations.last
            case .didFail(let error):
                self.location = nil
                debugPrint("location updates did failed: \(error)")
            }
        }
    }
    
    func stopUpdatingLocation() async {
        let locationManager = await getLocationManager()
        await locationManager.stopUpdatingLocation()
    }
    
    static func getPublicLocationURL(latitude: Double, longitude: Double) -> String {
        var body = ""
        
        body += "https://www.google.com/maps/search/?api=1&query="
        body += String(latitude)
        body += "%2C"
        body += String(longitude)
        
        return body
    }
    
    static func getMapAppLocationURL(latitude: Double, longitude: Double, address: String?) -> String {
        var body = ""
        
        let query = (address ?? ObvLocationService.Strings.mapPinTitle).addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? ""
        
        body += "https://maps.apple.com/?q=\(query)&ll=\(latitude),\(longitude)"
        
        return body
    }
}

private extension ObvLocationService {
    
    struct Strings {
        
        static let mapPinTitle = String(localized: "MAP_PIN_TITLE", bundle: Bundle(for: ObvLocationResources.self))
        
    }
    
}
