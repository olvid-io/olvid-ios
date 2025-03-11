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

import UIKit
import CoreLocation

/// This class centralizes all requests to disable/enable location for the current user, when sharing live coordinates for example
actor ObvLocationManager {
    
    private let clLocationManager: CLLocationManager
    
    private let locationTask = ObvLocationTask()
    
    /// The delegate which receive events from the underlying `locationManager` implementation
    /// and dispatch them to the `LocationTask` through the final output function.
    private let locationDelegate: ObvLocationDelegate
    
    /// Cache used to store some bits of the data retrived by the underlying core location service.
    private let cache = UserDefaults(suiteName: "io.olvid.location.cache")
    private let locationCacheKey = "lastLocation"
    
    // MARK: - Public Properties
    
    /// The last received location from underlying Location Manager service.
    /// This is persistent between sesssions and store the latest result with no
    /// filters or logic behind.
    var lastLocation: CLLocation? {
        get {
            cache?.location(forKey: locationCacheKey)
        }
        set {
            cache?.set(location: newValue, forKey: locationCacheKey)
        }
    }
    
    func setLastLocation(to lastLocation: CLLocation?) {
        self.lastLocation = lastLocation
    }
    
    /// Indicate whether location services are enabled on the device.
    var locationServicesEnabled: Bool {
        return self.clLocationManager.locationServicesEnabled()
    }
    
    /// The status of  authorization to provide parental controls.
    var authorizationStatus: CLAuthorizationStatus {
        clLocationManager.authorizationStatus
    }
    
    /// The minimum distance in meters the device must move horizontally before an update event is generated.
    /// By defualt is set to `kCLDistanceFilterNone`.
    var distanceFilter: CLLocationDistance {
        get { clLocationManager.distanceFilter }
        set { clLocationManager.distanceFilter = newValue }
    }
    
    /// Indicates whether the app receives location updates when running in the background.
    /// By default is `false`.
    /// When the value of this property is true and you start location updates while the app is in the foreground,
    /// Core Location configures the system to keep the app running to receive continuous background location updates,
    /// and arranges to show the background location indicator (blue bar or pill) if needed.
    /// Updates continue even if the app subsequently enters the background.
    var allowsBackgroundLocationUpdates: Bool {
        get { clLocationManager.allowsBackgroundLocationUpdates }
        set { clLocationManager.allowsBackgroundLocationUpdates = newValue }
    }
    
    
    var pausesLocationUpdatesAutomatically: Bool {
        get { clLocationManager.pausesLocationUpdatesAutomatically }
        set { clLocationManager.pausesLocationUpdatesAutomatically = newValue }
    }
    
    
    init(allowsBackgroundLocationUpdates: Bool = false, distanceFilter: CLLocationDistance, pausesLocationUpdatesAutomatically: Bool) async {
        self.locationDelegate = ObvLocationDelegate(locationTask: self.locationTask)
        self.clLocationManager = CLLocationManager()
        self.clLocationManager.delegate = self.locationDelegate
        self.clLocationManager.allowsBackgroundLocationUpdates = allowsBackgroundLocationUpdates
        self.distanceFilter = distanceFilter
        self.pausesLocationUpdatesAutomatically = pausesLocationUpdatesAutomatically
        await self.locationTask.setObvLocationManager(to: self)
    }
}

extension ObvLocationManager {
    
    // MARK: - Monitor Authorization Status
    /// Monitor updates about the authorization status.
    func startMonitoringAuthorization() async -> ObvLocationTaskKind.Authorization.Stream {
        let task = ObvLocationTaskKind.Authorization()
        return ObvLocationTaskKind.Authorization.Stream { stream in
            stream.onTermination = { @Sendable _ in
                Task { await self.stopMonitoringAuthorization() }
            }
            Task {
                await task.setStream(to: stream)
                await locationTask.add(task: task)
            }
        }
    }
    
    /// Stop monitoring changes of authorization status by stopping all running streams.
    func stopMonitoringAuthorization() async {
        await locationTask.cancel(tasksTypes: ObvLocationTaskKind.Authorization.self)
    }
    
    // MARK: - Request Permission for Location
    
    
    /// Request to monitor location changes.
    @discardableResult
    func requestPermissionIfNotDetermined(_ permission: LocationPermission) async throws -> CLAuthorizationStatus {
        switch permission {
        case .whenInUse:
            return try await requestWhenInUsePermissionIfNotDetermined()
        case .always:
            return try await requestAlwaysPermissionIfNotDetermined()
        }
    }
    
    
    /// Request authorization to get location when app is in use.
    private func requestWhenInUsePermissionIfNotDetermined() async throws -> CLAuthorizationStatus {
        let task = ObvLocationTaskKind.LocatePermission(locationManager: self)
        return try await withTaskCancellationHandler {
            try await task.requestWhenInUsePermissionIfNotDetermined()
        } onCancel: {
            Task {
                await locationTask.cancel(task: task)
            }
        }
    }
    
    
    /// Exclusively called from an `ObvLocationTaskKind.LocatePermission` task.
    func requestWhenInUsePermission(for task: ObvLocationTaskKind.LocatePermission) async {
        await self.locationTask.add(task: task)
        self.clLocationManager.requestWhenInUseAuthorization()
    }
    
    
    /// Request authorization to get location both in foreground and background.
    private func requestAlwaysPermissionIfNotDetermined() async throws -> CLAuthorizationStatus {
        let task = ObvLocationTaskKind.LocatePermission(locationManager: self)
        return try await withTaskCancellationHandler {
            try await task.requestAlwaysPermissionIfNotDetermined()
        } onCancel: {
            Task {
                await locationTask.cancel(task: task)
            }
        }
    }
    
    
    /// Exclusively called from an `ObvLocationTaskKind.LocatePermission` task.
    func requestAlwaysAuthorization(for task: ObvLocationTaskKind.LocatePermission) async {
        await self.locationTask.add(task: task)
        self.clLocationManager.requestAlwaysAuthorization()
    }
    
    
    // MARK: - Monitor Location Updates
        
    /// Start receiving changes of the locations with a stream.
    func startMonitoringLocations() async throws -> ObvLocationTaskKind.ContinuousUpdatedLocation.Stream {
        guard clLocationManager.authorizationStatus != .notDetermined else { throw ObvLocationError.authorizationRequired }
        
        guard clLocationManager.authorizationStatus.canMonitorLocation else { throw ObvLocationError.notAuthorized }
        
        let task = ObvLocationTaskKind.ContinuousUpdatedLocation()
        return ObvLocationTaskKind.ContinuousUpdatedLocation.Stream { stream in
            stream.onTermination = { @Sendable _ in
                Task { await self.locationTask.cancel(task: task) }
            }
            Task {
                await task.setStream(to: stream)
                await locationTask.add(task: task)
                clLocationManager.startUpdatingLocation()
            }
        }
    }
    
    /// Stop updating location updates streams.
    func stopUpdatingLocation() async {
        clLocationManager.stopUpdatingLocation()
        await locationTask.cancel(tasksTypes: ObvLocationTaskKind.ContinuousUpdatedLocation.self)
    }
    
    // MARK: - Get Location
    
    /// Request a one-shot location from the underlying core location service.
    /// - Parameters:
    ///   - timeout: timeout interval for the request.
    func requestLocation(timeout: TimeInterval? = nil) async throws -> ObvLocationTaskKind.ContinuousUpdatedLocation.StreamEvent {
        let task = ObvLocationTaskKind.SingleUpdateLocation(locationManager: self, timeout: timeout)
        return try await withTaskCancellationHandler {
            try await task.run()
        } onCancel: {
            Task {
                await locationTask.cancel(task: task)
            }
        }
    }
    
    
    /// Exclusively called from an `ObvLocationTaskKind.SingleUpdateLocation` task.
    func requestLocation(for task: ObvLocationTaskKind.SingleUpdateLocation) async {
        await self.locationTask.add(task: task)
        self.clLocationManager.requestLocation()
    }
    
}

enum LocationPermission {
    case always
    case whenInUse
}

extension CLAuthorizationStatus {
    
    var canMonitorLocation: Bool {
        switch self {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }
    
}
