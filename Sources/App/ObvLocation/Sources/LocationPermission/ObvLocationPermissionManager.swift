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

import UIKit
import CoreLocation

/// This class centralizes all requests to disable/enable location for the current user, when sharing live coordinates for example
actor ObvLocationPermissionManager {
    
    private let clLocationManager: CLLocationManager
    
    private let locationTask = ObvLocationPermissionTask()
    
    /// The delegate which receive events from the underlying `locationManager` implementation
    /// and dispatch them to the `LocationTask` through the final output function.
    private let locationDelegate: ObvLocationPermissionDelegate
    
    // MARK: - Public Properties
    
    /// Indicate whether location services are enabled on the device.
    var locationServicesEnabled: Bool {
        return self.clLocationManager.locationServicesEnabled()
    }
    
    /// The status of  authorization to provide parental controls.
    var authorizationStatus: CLAuthorizationStatus {
        clLocationManager.authorizationStatus
    }
    
    init() async {
        self.locationDelegate = ObvLocationPermissionDelegate(locationTask: self.locationTask)
        self.clLocationManager = CLLocationManager()
        self.clLocationManager.delegate = self.locationDelegate
        await self.locationTask.setObvLocationPermissionManager(to: self)
    }
    
}

extension ObvLocationPermissionManager {
    
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
