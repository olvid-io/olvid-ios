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

import Foundation
import CoreLocation
import OSLog
import ObvAppCoreConstants


@available(iOS 17.0, *)
@MainActor
public final class ObvLocationPermissionService {
    
    // MARK: Attributes
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ObvLocationPermissionService")
    
    // MARK: Singleton
    public static let shared = ObvLocationPermissionService()
    
    private(set) var locationManager: ObvLocationPermissionManager? // Accessed using getLocationManager()
    
    // MARK: Methods
    private init() {}
    
    private func getLocationManager() async -> ObvLocationPermissionManager {
        if let locationManager {
            return locationManager
        } else {
            let locationManager = await ObvLocationPermissionManager()
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

}
